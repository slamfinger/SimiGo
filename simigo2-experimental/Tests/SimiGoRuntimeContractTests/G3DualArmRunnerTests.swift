import XCTest
@testable import SimiGoRuntimeContract

// MODEL-FREE TESTS FOR ARM RESOURCE OWNERSHIP + THE DUAL-ARM G3 RUNNER.
//
// Isolation is decided against a NORMALIZED UNDERLYING-STORAGE identity, not a
// Swift wrapper identity and not a label. Two distinct wrapper objects over the
// same live buffer must be caught as shared; a resource whose underlying store
// cannot be confirmed must fail closed. The four reviewer cases are covered:
//   * different wrappers, same underlying storage  -> detected shared (mutable => refuse)
//   * legal shared READ-ONLY weights                -> allowed (single-variable control)
//   * shared MUTABLE KV/prefix storage              -> refused
//   * unconfirmable underlying identity (mutable)   -> refused (fail-closed)
// Plus the lifecycle boundary: after the pre-generation check passes and the arms
// are sealed, a resource materialized DURING generation cannot bypass isolation —
// registerDuringGeneration re-checks it live and refuses a violating allocation.
//
// The registration channel itself is now wired end to end: the runner seals each
// owner, obtains its G3AllocationRegistrar, and threads it through
// G3ExecutionRoute.g3 into the gated continuation, so a during-generation
// allocation reaches the LIVE registry instead of being invisible. These cases
// prove ownership is no longer a one-shot pre-run snapshot.
final class G3DualArmRunnerTests: XCTestCase {
    static let modelSHA = String(repeating: "a", count: 64)
    static let tokSHA = String(repeating: "b", count: 64)

    // MARK: Builders

    /// A verified read-only store. Sharing it across arms is allowed; identity is
    /// irrelevant to isolation, so it never enters the mutable set.
    private func ro(_ role: G3ResourceRole, id: String, back: AnyObject? = nil) -> OwnedResource {
        OwnedResource(role: role, ownerLabel: "arm", access: .sharedReadOnly,
                      storage: .confirmed(id), backing: back)
    }
    /// A per-arm mutable resource with a CONFIRMED underlying-storage id.
    private func mut(_ role: G3ResourceRole, id: String, back: AnyObject? = nil) -> OwnedResource {
        OwnedResource(role: role, ownerLabel: "arm", access: .armExclusiveMutable,
                      storage: .confirmed(id), backing: back)
    }
    /// The same, with the owning arm's label recorded (diagnostics only — sharing
    /// is still decided on the storage id, never on the label).
    private func mut(_ role: G3ResourceRole, id: String, arm: String) -> OwnedResource {
        OwnedResource(role: role, ownerLabel: arm, access: .armExclusiveMutable,
                      storage: .confirmed(id))
    }
    /// A per-arm mutable resource whose underlying store cannot be confirmed.
    private func mutUnknown(_ role: G3ResourceRole) -> OwnedResource {
        OwnedResource(role: role, ownerLabel: "arm", access: .armExclusiveMutable,
                      storage: .indeterminate)
    }

    /// Build an owner. Mutable ids default to per-arm-unique confirmed ids so the
    /// owner is isolated unless a caller deliberately shares an id or supplies an
    /// unknown store. `weightsShared` marks the read-only weight store as the SAME
    /// confirmed store on both arms (allowed sharing).
    private func makeOwner(
        _ arm: String, writeRoot: String,
        kvID: String? = nil, prefixID: String? = nil, scratchID: String? = nil,
        extraID: String? = nil,
        kv: OwnedResource? = nil, prefix: OwnedResource? = nil,
        scratch: OwnedResource? = nil, extra: [OwnedResource]? = nil,
        weights: OwnedResource? = nil
    ) -> G3ArmResourceOwner {
        G3ArmResourceOwner(
            armID: RuntimeArmID(arm), isolationUnitID: "iso-\(arm)",
            modelWeights: weights ?? ro(.modelWeights, id: "weights-\(arm)"),
            modelContentSHA256: G3DualArmRunnerTests.modelSHA,
            tokenizerData: ro(.tokenizerData, id: "tok-\(arm)"),
            tokenizerContentSHA256: G3DualArmRunnerTests.tokSHA,
            kvCache: kv ?? mut(.kvCache, id: kvID ?? "kv-\(arm)"),
            prefixCache: prefix ?? mut(.prefixCache, id: prefixID ?? "prefix-\(arm)"),
            runtimeScratch: scratch ?? mut(.runtimeScratch, id: scratchID ?? "scratch-\(arm)"),
            mutableResources: extra ?? [mut(.extraMutable, id: extraID ?? "extra-\(arm)")],
            writeRoot: writeRoot)
    }

    private func request() throws -> AttestationRequest {
        try AttestationRequest(runID: "dual-run", challengeNonce: "dual-nonce")
    }

    // MARK: Per-arm cache wiring (mandatory since G8a)

    /// Model-free stand-in for the MLX cache boundary. `beginStep` resets the
    /// per-step latch exactly like `KVCacheSimple.beginStep()`.
    final class FakeCacheBoundary: G3ArmCacheBoundary {
        var aborted = false
        var reason: String?
        func beginStep() { aborted = false; reason = nil }
        var isolationAborted: Bool { aborted }
        var isolationAbortReason: String? { reason }
    }

    /// `G3DualArmRunner.run` now REQUIRES this argument: G8a closed the
    /// no-session recompute path, so every routing test must state its wiring.
    private func sessions() -> G3PerArmCacheSessionFactory {
        { armID, _ in
            G3ArmCacheSession(armID: armID.rawValue, boundary: FakeCacheBoundary())
        }
    }

    struct WiringFailure: Error, CustomStringConvertible {
        let description: String
    }

    struct UntrustedLiveProvider: RuntimeAttestationProvider {
        let providerID = "simigo.g3.dual-arm.live"
        let providerKind: RuntimeProviderKind = .swiftMLXLiveWorker
        func collect(_ request: AttestationRequest) throws -> [RuntimeAttestation] { [] }
    }

    /// A routing spy whose gated method behaves as if the gate cleared, so the
    /// runner's routing + aggregation can be observed without a real provider.
    /// It also models the executor's during-generation obligation: it hands the
    /// registrar the resources its "forward" materialized, so the test observes
    /// the whole channel — seal → route → gated method → live re-validation.
    final class SpyExecutor: G3RoutableContinuation, G3CacheSessionInstalling, @unchecked Sendable {
        typealias ContinuationResult = G3GateOutcome
        var standardCalls = 0
        var gatedCalls = 0
        /// Resources this arm's fake forward "allocated during generation".
        var duringGenerationAllocations: [OwnedResource] = []
        /// The channel the runner passed in, recorded to prove it really arrives.
        var receivedRegistrar: G3AllocationRegistrar?
        var registrationError: Error?
        /// The wire the runner installed, recorded so a test can prove the
        /// executor really holds its own session (and that the peer's is different).
        private(set) var installedSession: G3ArmCacheSession?

        @discardableResult
        func installG3CacheSession(_ session: G3ArmCacheSession) -> Bool {
            if let existing = installedSession { return existing === session }
            installedSession = session
            return true
        }

        func continueExecution(_ state: ExecutionStateHandle, nextInputTokens: [Int], maxTokens: Int) async throws -> G3GateOutcome {
            standardCalls += 1
            return G3GateOutcome(gate: "spy", stage: "standard", passed: false, eligibleForRuntimeEvidence: false,
                                 evidenceClass: "x", generationCallCount: 1, modelGenerationStartedByGate: false,
                                 isExecutionEvidence: false, reason: "", failedChecks: [], runID: "", challengeNonce: "",
                                 providerID: "", providerKind: "", trustedLiveProviderCount: 0)
        }
        func continueExecutionG3(_ state: ExecutionStateHandle, nextInputTokens: [Int], maxTokens: Int, provider: any RuntimeAttestationProvider, request: AttestationRequest) async throws -> G3GateOutcome {
            gatedCalls += 1
            return Self.cleared(request: request, provider: provider)
        }
        /// The registrar-aware override: the production executor shape, where the
        /// forward runs and then its new allocations are registered.
        func continueExecutionG3(
            _ state: ExecutionStateHandle, nextInputTokens: [Int], maxTokens: Int,
            provider: any RuntimeAttestationProvider, request: AttestationRequest,
            registrar: G3AllocationRegistrar?
        ) async throws -> G3GateOutcome {
            gatedCalls += 1
            receivedRegistrar = registrar
            for resource in duringGenerationAllocations {
                do {
                    try registrar?.register(resource)
                } catch {
                    registrationError = error
                    throw error        // fail closed: the forward does not continue
                }
            }
            // A cleared spy run stands in for the production settlement seam.
            if let session = installedSession {
                let ledger = session.runLedger
                ledger.recordPhase(.generation, .succeeded("spy"))
                ledger.markSettleEntered()
                ledger.markBindingConsumed()
                ledger.recordPhase(.decode, .succeeded("spy"))
                ledger.recordPhase(.registration, .skipped("spy"))
                ledger.recordPhase(.commit, .succeeded("spy"))
            }
            return Self.cleared(request: request, provider: provider)
        }

        private static func cleared(
            request: AttestationRequest, provider: any RuntimeAttestationProvider
        ) -> G3GateOutcome {
            G3GateOutcome(gate: RuntimeIsolationGate.gateID, stage: "cleared", passed: true, eligibleForRuntimeEvidence: true,
                                 evidenceClass: "spy_cleared", generationCallCount: 1, modelGenerationStartedByGate: false,
                                 isExecutionEvidence: false, reason: "", failedChecks: [],
                                 runID: request.runID, challengeNonce: request.challengeNonce,
                                 providerID: provider.providerID, providerKind: provider.providerKind.rawValue,
                                 trustedLiveProviderCount: 0)
        }
    }

    // MARK: Case 1 — different wrappers over the SAME underlying storage

    func testDistinctWrappersOverSameUnderlyingStorageAreDetectedAsShared() {
        // Two genuinely different Swift objects (distinct ObjectIdentifier), but the
        // native holder folds both to the SAME confirmed underlying-storage id. This
        // is exactly what comparing Swift wrapper identity would have missed.
        let wrapperA = NSObject()
        let wrapperB = NSObject()
        let a = makeOwner("ES+IS", writeRoot: "/tmp/g3/es",
                          kv: mut(.kvCache, id: "shared-buffer-1", back: wrapperA))
        let b = makeOwner("IS-only", writeRoot: "/tmp/g3/is",
                          kv: mut(.kvCache, id: "shared-buffer-1", back: wrapperB))
        XCTAssertTrue(a.kvCache.backing !== b.kvCache.backing,
                      "the two backing objects are different Swift instances")
        let report = G3OwnershipIsolation.check(a, b)
        XCTAssertFalse(report.passed)
        XCTAssertTrue(report.failedReasons.contains { $0.hasPrefix("shared_mutable_storage") },
                      "got \(report.failedReasons)")
    }

    // MARK: Case 2 — legal shared READ-ONLY weights

    func testSharedReadOnlyWeightStoreIsAllowed() {
        // Both arms declare the SAME confirmed weight store as read-only: sharing it
        // is the single-variable control, NOT an isolation leak.
        let a = makeOwner("ES+IS", writeRoot: "/tmp/g3/es",
                          weights: ro(.modelWeights, id: "weights-canonical"))
        let b = makeOwner("IS-only", writeRoot: "/tmp/g3/is",
                          weights: ro(.modelWeights, id: "weights-canonical"))
        let report = G3OwnershipIsolation.check(a, b)
        XCTAssertTrue(report.passed, "unexpected: \(report.failedReasons)")
    }

    func testDistinctOwnersWithDistinctMutableInstancesAreIsolated() {
        let a = makeOwner("ES+IS", writeRoot: "/tmp/g3/es")
        let b = makeOwner("IS-only", writeRoot: "/tmp/g3/is")
        XCTAssertTrue(G3OwnershipIsolation.check(a, b).passed)
    }

    // MARK: Case 3 — shared MUTABLE KV / prefix storage

    func testSharedKVMutableStorageFailsClosed() {
        let a = makeOwner("ES+IS", writeRoot: "/tmp/g3/es", kvID: "kv-shared")
        let b = makeOwner("IS-only", writeRoot: "/tmp/g3/is", kvID: "kv-shared")
        let report = G3OwnershipIsolation.check(a, b)
        XCTAssertFalse(report.passed)
        XCTAssertTrue(report.failedReasons.contains { $0.hasPrefix("shared_mutable_storage") })
    }

    func testCrossRoleMutableAliasingFailsClosed() {
        // Arm A's KV cache and arm B's prefix cache alias the SAME underlying buffer.
        // A per-role comparison would miss this; the cross-arm mutable-id intersection
        // catches it.
        let a = makeOwner("ES+IS", writeRoot: "/tmp/g3/es", kv: mut(.kvCache, id: "alias-7"))
        let b = makeOwner("IS-only", writeRoot: "/tmp/g3/is", prefix: mut(.prefixCache, id: "alias-7"))
        XCTAssertTrue(G3OwnershipIsolation.check(a, b).failedReasons
                      .contains { $0.hasPrefix("shared_mutable_storage") })
    }

    // MARK: Case 4 — unconfirmable underlying identity (fail closed)

    func testMutableResourceWithUnknownStorageIdentityFailsClosed() {
        let a = makeOwner("ES+IS", writeRoot: "/tmp/g3/es", kv: mutUnknown(.kvCache))
        let b = makeOwner("IS-only", writeRoot: "/tmp/g3/is")
        let report = G3OwnershipIsolation.check(a, b)
        XCTAssertFalse(report.passed)
        XCTAssertTrue(report.failedReasons.contains("indeterminate_storage_identity(kv_cache)"),
                      "got \(report.failedReasons)")
    }

    func testUnverifiedMutabilityFailsClosed() {
        let suspect = OwnedResource(role: .runtimeScratch, ownerLabel: "arm",
                                    access: .unverified, storage: .indeterminate)
        let a = makeOwner("ES+IS", writeRoot: "/tmp/g3/es", scratch: suspect)
        let b = makeOwner("IS-only", writeRoot: "/tmp/g3/is")
        XCTAssertTrue(G3OwnershipIsolation.check(a, b).failedReasons
                      .contains("indeterminate_mutability(runtime_scratch)"))
    }

    func testExclusionRoleDowngradedToReadOnlyFailsClosed() {
        // Declaring a KV cache as read-only to evade isolation is itself a violation.
        let sneakyKV = OwnedResource(role: .kvCache, ownerLabel: "arm",
                                     access: .sharedReadOnly, storage: .indeterminate)
        let a = makeOwner("ES+IS", writeRoot: "/tmp/g3/es", kv: sneakyKV)
        let b = makeOwner("IS-only", writeRoot: "/tmp/g3/is")
        XCTAssertTrue(G3OwnershipIsolation.check(a, b).failedReasons
                      .contains("role_requires_isolation(kv_cache)"))
    }

    func testSameArmIDAndNestedWriteRootsAndReleasedOwnerFail() {
        let same = makeOwner("ES+IS", writeRoot: "/tmp/g3/a")
        let same2 = makeOwner("ES+IS", writeRoot: "/tmp/g3/b")
        XCTAssertTrue(G3OwnershipIsolation.check(same, same2).failedReasons.contains("same_arm_id"))

        let parent = makeOwner("ES+IS", writeRoot: "/tmp/g3")
        let child = makeOwner("IS-only", writeRoot: "/tmp/g3/es")
        XCTAssertTrue(G3OwnershipIsolation.check(parent, child).failedReasons.contains("runtime_write_roots_not_disjoint"))

        let live = makeOwner("ES+IS", writeRoot: "/tmp/g3/es")
        let stale = makeOwner("IS-only", writeRoot: "/tmp/g3/is")
        stale.release()
        XCTAssertTrue(G3OwnershipIsolation.check(live, stale).failedReasons.contains { $0.hasPrefix("owner_not_active") })
    }

    // MARK: Lifecycle — sealing + post-generation allocations

    func testRegisterBeforeSealThrowsNotSealed() {
        let owner = makeOwner("ES+IS", writeRoot: "/tmp/g3/es")
        XCTAssertThrowsError(try owner.registerDuringGeneration(mut(.extraMutable, id: "late"))) { error in
            guard case G3ArmResourceOwner.AllocationError.notSealed = error else {
                return XCTFail("expected notSealed, got \(error)")
            }
        }
    }

    func testRegisterConflictingMutableAfterSealIsRefusedAndRecorded() {
        let a = makeOwner("ES+IS", writeRoot: "/tmp/g3/es")   // owns kv-ES+IS ...
        let b = makeOwner("IS-only", writeRoot: "/tmp/g3/is")
        XCTAssertTrue(G3OwnershipIsolation.check(a, b).passed)
        a.seal(against: b)
        b.seal(against: a)

        // During generation, arm B materializes a NEW mutable buffer that aliases
        // arm A's KV cache (same confirmed underlying id). It must not slip past.
        XCTAssertThrowsError(try b.registerDuringGeneration(mut(.extraMutable, id: "kv-ES+IS"))) { error in
            guard case G3ArmResourceOwner.AllocationError.violation(let reason) = error else {
                return XCTFail("expected violation, got \(error)")
            }
            XCTAssertTrue(reason.hasPrefix("shared_mutable_storage"))
        }
        XCTAssertTrue(b.allocationViolations.contains { $0.hasPrefix("shared_mutable_storage") })
    }

    func testRegisterIndeterminateMutableAfterSealIsRefused() {
        let a = makeOwner("ES+IS", writeRoot: "/tmp/g3/es")
        let b = makeOwner("IS-only", writeRoot: "/tmp/g3/is")
        a.seal(against: b); b.seal(against: a)
        XCTAssertThrowsError(try b.registerDuringGeneration(mutUnknown(.runtimeScratch))) { error in
            guard case G3ArmResourceOwner.AllocationError.violation(let reason) = error else {
                return XCTFail("expected violation, got \(error)")
            }
            XCTAssertEqual(reason, "indeterminate_storage_identity(runtime_scratch)")
        }
    }

    func testRegisterFreshDisjointMutableAfterSealIsAdmittedOnce() throws {
        let a = makeOwner("ES+IS", writeRoot: "/tmp/g3/es")
        let b = makeOwner("IS-only", writeRoot: "/tmp/g3/is")
        a.seal(against: b); b.seal(against: a)
        // A genuinely new, disjoint mutable store is admitted and then guarded.
        _ = try b.registerDuringGeneration(mut(.extraMutable, id: "buf-new"))
        XCTAssertTrue(b.confirmedMutableIDs.contains("buf-new"))
        // Registering the same underlying store again now conflicts with B's own set.
        XCTAssertThrowsError(try b.registerDuringGeneration(mut(.extraMutable, id: "buf-new")))
    }

    func testRegisterReadOnlyStoreDuringGenerationIsAllowed() throws {
        let a = makeOwner("ES+IS", writeRoot: "/tmp/g3/es")
        let b = makeOwner("IS-only", writeRoot: "/tmp/g3/is")
        a.seal(against: b); b.seal(against: a)
        // A freshly verified read-only store added mid-run cannot leak mutable state.
        _ = try b.registerDuringGeneration(ro(.modelWeights, id: "weights-extra-shared"))
        XCTAssertTrue(b.allocationViolations.isEmpty)
    }

    // MARK: Dual-arm routing — both arms only via the dispatcher's .g3

    func testExecutorWithoutPerArmSessionWiringIsRefusedBeforeDispatch() async throws {
        // G8a: an executor that cannot hold its own per-arm session is not a
        // "no KV observed" mode of a G3 run — it is a wiring refusal. Nothing
        // is dispatched, so neither arm's forward can run and no binding can be
        // consumed by a sessionless recompute path.
        let aOwner = makeOwner("ES+IS", writeRoot: "/tmp/g3/es")
        let bOwner = makeOwner("IS-only", writeRoot: "/tmp/g3/is")
        var aGen = 0
        var bGen = 0
        let armA = G3ArmExecution(
            owner: aOwner, executor: G3IsolatedWorker(generate: { aGen += 1 }),
            provider: UntrustedLiveProvider(), request: try request(),
            state: .g3RoutingPlaceholder, nextInputTokens: [1], maxTokens: 4)
        let armB = G3ArmExecution(
            owner: bOwner, executor: G3IsolatedWorker(generate: { bGen += 1 }),
            provider: UntrustedLiveProvider(), request: try request(),
            state: .g3RoutingPlaceholder, nextInputTokens: [2], maxTokens: 4)

        do {
            _ = try await G3DualArmRunner.run(
                armA, armB, makeCacheSession: sessions())
            XCTFail("a G3 run without installable per-arm sessions must be refused")
        } catch G3DualArmRunner.RunError.cacheWiringRefused(let reason) {
            XCTAssertTrue(
                reason.contains("executor_cannot_install_cache_session"), reason)
        }
        XCTAssertEqual(aGen, 0, "no arm may be dispatched without a wired session")
        XCTAssertEqual(bGen, 0)
    }

    func testThrowingSessionFactoryRefusesBeforeDispatch() async throws {
        let aOwner = makeOwner("ES+IS", writeRoot: "/tmp/g3/es")
        let bOwner = makeOwner("IS-only", writeRoot: "/tmp/g3/is")
        let spyA = SpyExecutor(); let spyB = SpyExecutor()
        let armA = G3ArmExecution(
            owner: aOwner, executor: spyA, provider: UntrustedLiveProvider(),
            request: try request(), state: .g3RoutingPlaceholder,
            nextInputTokens: [1], maxTokens: 4)
        let armB = G3ArmExecution(
            owner: bOwner, executor: spyB, provider: UntrustedLiveProvider(),
            request: try request(), state: .g3RoutingPlaceholder,
            nextInputTokens: [2], maxTokens: 4)

        do {
            _ = try await G3DualArmRunner.run(
                armA, armB,
                makeCacheSession: { _, _ in
                    throw WiringFailure(description: "no_cache_available")
                })
            XCTFail("a failed per-arm session build must refuse the run")
        } catch G3DualArmRunner.RunError.cacheWiringRefused(let reason) {
            XCTAssertTrue(reason.contains("no_cache_available"), reason)
        }
        XCTAssertEqual(spyA.gatedCalls, 0)
        XCTAssertEqual(spyB.gatedCalls, 0)
        XCTAssertEqual(spyA.standardCalls, 0)
        XCTAssertNil(spyA.installedSession)
    }

    func testOwnershipPreconditionRefusesBeforeDispatchingEitherArm() async throws {
        let aOwner = makeOwner("ES+IS", writeRoot: "/tmp/g3/es", kvID: "kv-shared")
        let bOwner = makeOwner("IS-only", writeRoot: "/tmp/g3/is", kvID: "kv-shared")
        let spyA = SpyExecutor()
        let spyB = SpyExecutor()
        let armA = G3ArmExecution(owner: aOwner, executor: spyA, provider: UntrustedLiveProvider(),
                                  request: try request(), state: .g3RoutingPlaceholder, nextInputTokens: [1], maxTokens: 4)
        let armB = G3ArmExecution(owner: bOwner, executor: spyB, provider: UntrustedLiveProvider(),
                                  request: try request(), state: .g3RoutingPlaceholder, nextInputTokens: [2], maxTokens: 4)

        do {
            _ = try await G3DualArmRunner.run(armA, armB, makeCacheSession: sessions())
            XCTFail("expected the ownership precondition to refuse")
        } catch G3DualArmRunner.RunError.preconditionRefused(let iso) {
            XCTAssertFalse(iso.passed)
            XCTAssertTrue(iso.failedReasons.contains { $0.hasPrefix("shared_mutable_storage") })
        }
        // Refused BEFORE dispatch/seal: neither the gated nor the standard method ran.
        XCTAssertEqual(spyA.gatedCalls, 0); XCTAssertEqual(spyA.standardCalls, 0)
        XCTAssertEqual(spyB.gatedCalls, 0); XCTAssertEqual(spyB.standardCalls, 0)
    }

    func testClearedArmsRouteViaGatedMethodOnlyAndSumGeneration() async throws {
        // When the gated method clears (spy), the runner sums generation and the
        // standard method is still never touched — proving no fallback path exists.
        let aOwner = makeOwner("ES+IS", writeRoot: "/tmp/g3/es")
        let bOwner = makeOwner("IS-only", writeRoot: "/tmp/g3/is")
        let spyA = SpyExecutor(); let spyB = SpyExecutor()
        let armA = G3ArmExecution(owner: aOwner, executor: spyA, provider: UntrustedLiveProvider(),
                                  request: try request(), state: .g3RoutingPlaceholder, nextInputTokens: [1], maxTokens: 4)
        let armB = G3ArmExecution(owner: bOwner, executor: spyB, provider: UntrustedLiveProvider(),
                                  request: try request(), state: .g3RoutingPlaceholder, nextInputTokens: [2], maxTokens: 4)

        let report = try await G3DualArmRunner.run(armA, armB, makeCacheSession: sessions())

        XCTAssertEqual(report.totalGenerationCallCount, 2)
        XCTAssertTrue(report.anyArmClearedGate)
        XCTAssertTrue(report.armsSealed)
        XCTAssertEqual(spyA.gatedCalls, 1); XCTAssertEqual(spyB.gatedCalls, 1)
        XCTAssertEqual(spyA.standardCalls, 0); XCTAssertEqual(spyB.standardCalls, 0)  // no fallback
        XCTAssertFalse(report.isExecutionEvidence)   // still never real execution evidence
    }

    // MARK: During-generation registration — the channel is live, not a snapshot

    func testActiveOrReleasedOwnerGivesNoRegistrar() {
        // An owner that has not passed the pre-generation check cannot hand out a
        // registration channel, and a released one never can.
        let live = makeOwner("ES+IS", writeRoot: "/tmp/g3/es")
        XCTAssertNil(live.makeRegistrar(), "an unsealed owner must not offer a registrar")

        let peer = makeOwner("IS-only", writeRoot: "/tmp/g3/is")
        live.seal(against: peer)
        XCTAssertNotNil(live.makeRegistrar(), "a sealed owner must offer the live channel")

        live.release()
        XCTAssertNil(live.makeRegistrar(), "a released owner is never an authority")
    }

    func testRunnerThreadsSealedOwnersRegistrarIntoGatedMethod() async throws {
        let aOwner = makeOwner("ES+IS", writeRoot: "/tmp/g3/es")
        let bOwner = makeOwner("IS-only", writeRoot: "/tmp/g3/is")
        let spyA = SpyExecutor(); let spyB = SpyExecutor()
        let armA = G3ArmExecution(owner: aOwner, executor: spyA, provider: UntrustedLiveProvider(),
                                  request: try request(), state: .g3RoutingPlaceholder, nextInputTokens: [1], maxTokens: 4)
        let armB = G3ArmExecution(owner: bOwner, executor: spyB, provider: UntrustedLiveProvider(),
                                  request: try request(), state: .g3RoutingPlaceholder, nextInputTokens: [2], maxTokens: 4)

        _ = try await G3DualArmRunner.run(armA, armB, makeCacheSession: sessions())

        // Each arm reached the gated method WITH its own arm's channel: the run is
        // no longer decided only by the pre-generation snapshot.
        XCTAssertEqual(spyA.receivedRegistrar?.armID, aOwner.armID)
        XCTAssertEqual(spyB.receivedRegistrar?.armID, bOwner.armID)
        XCTAssertTrue(aOwner.state == .sealed && bOwner.state == .sealed)
    }

    func testAllocationSharedWithPeerDuringGenerationFailsRunClosed() async throws {
        // Both arms pass the pre-generation snapshot (their own KV/prefix/scratch
        // are disjoint). Then arm A's generation materializes a buffer that aliases
        // arm B's KV cache — only the LIVE registry can see it.
        let aOwner = makeOwner("ES+IS", writeRoot: "/tmp/g3/es")
        let bOwner = makeOwner("IS-only", writeRoot: "/tmp/g3/is")
        XCTAssertTrue(G3OwnershipIsolation.check(aOwner, bOwner).passed)

        let spyA = SpyExecutor(); let spyB = SpyExecutor()
        spyA.duringGenerationAllocations = [mut(.kvCache, id: "kv-IS-only", arm: "ES+IS")]
        let armA = G3ArmExecution(owner: aOwner, executor: spyA, provider: UntrustedLiveProvider(),
                                  request: try request(), state: .g3RoutingPlaceholder, nextInputTokens: [1], maxTokens: 4)
        let armB = G3ArmExecution(owner: bOwner, executor: spyB, provider: UntrustedLiveProvider(),
                                  request: try request(), state: .g3RoutingPlaceholder, nextInputTokens: [2], maxTokens: 4)

        let report = try await G3DualArmRunner.run(armA, armB, makeCacheSession: sessions())

        XCTAssertTrue(report.isolationPrecondition.passed, "snapshot alone would pass")
        XCTAssertTrue(report.allocationViolations.contains { $0.hasPrefix("shared_mutable_storage") },
                      "got \(report.allocationViolations)")
        XCTAssertTrue(report.isolationCompromisedAfterAllocation)
        XCTAssertEqual(report.arms.first { $0.armID == "ES+IS" }?.outcome.stage, "dispatch_error",
                       "a refused allocation must not be reported as a cleared arm")
        XCTAssertEqual(spyA.gatedCalls, 1); XCTAssertEqual(spyA.standardCalls, 0)
    }

    func testAllocationWithUnconfirmableIdentityDuringGenerationIsRefused() async throws {
        let aOwner = makeOwner("ES+IS", writeRoot: "/tmp/g3/es")
        let bOwner = makeOwner("IS-only", writeRoot: "/tmp/g3/is")
        let spyA = SpyExecutor()
        // A mutable buffer whose underlying store the holder cannot confirm.
        spyA.duringGenerationAllocations = [
            OwnedResource(role: .runtimeScratch, ownerLabel: "ES+IS",
                          access: .armExclusiveMutable, storage: .indeterminate)]
        let armA = G3ArmExecution(owner: aOwner, executor: spyA, provider: UntrustedLiveProvider(),
                                  request: try request(), state: .g3RoutingPlaceholder, nextInputTokens: [1], maxTokens: 4)
        let armB = G3ArmExecution(owner: bOwner, executor: SpyExecutor(), provider: UntrustedLiveProvider(),
                                  request: try request(), state: .g3RoutingPlaceholder, nextInputTokens: [2], maxTokens: 4)

        let report = try await G3DualArmRunner.run(armA, armB, makeCacheSession: sessions())
        XCTAssertTrue(report.allocationViolations.contains("indeterminate_storage_identity(runtime_scratch)"),
                      "got \(report.allocationViolations)")
        XCTAssertTrue(report.isolationCompromisedAfterAllocation)
    }

    func testGenuinelyFreshAllocationDuringGenerationIsAdmittedAndGuarded() async throws {
        let aOwner = makeOwner("ES+IS", writeRoot: "/tmp/g3/es")
        let bOwner = makeOwner("IS-only", writeRoot: "/tmp/g3/is")
        let spyA = SpyExecutor()
        spyA.duringGenerationAllocations = [mut(.kvCache, id: "kv-block-2", arm: "ES+IS")]
        let armA = G3ArmExecution(owner: aOwner, executor: spyA, provider: UntrustedLiveProvider(),
                                  request: try request(), state: .g3RoutingPlaceholder, nextInputTokens: [1], maxTokens: 4)
        let armB = G3ArmExecution(owner: bOwner, executor: SpyExecutor(), provider: UntrustedLiveProvider(),
                                  request: try request(), state: .g3RoutingPlaceholder, nextInputTokens: [2], maxTokens: 4)

        let report = try await G3DualArmRunner.run(armA, armB, makeCacheSession: sessions())

        // A per-arm buffer that aliases nothing is admitted: the channel does not
        // simply refuse everything, which would make it useless as a control.
        XCTAssertTrue(report.allocationViolations.isEmpty, "got \(report.allocationViolations)")
        XCTAssertFalse(report.isolationCompromisedAfterAllocation)
        XCTAssertTrue(aOwner.confirmedMutableIDs.contains("kv-block-2"))
        XCTAssertEqual(spyA.receivedRegistrar?.armID, aOwner.armID)

        // And it is now part of the live set: re-registering the same store conflicts.
        let registrar = try XCTUnwrap(aOwner.makeRegistrar())
        XCTAssertThrowsError(try registrar.register(mut(.kvCache, id: "kv-block-2", arm: "ES+IS"))) { error in
            guard case G3AllocationRegistrar.RegistrationError.violation(let reason) = error else {
                return XCTFail("expected violation, got \(error)")
            }
            XCTAssertTrue(reason.hasPrefix("shared_mutable_storage"))
        }
    }

    func testRegistrarRefusesWhenOwnerWasNeverSealed() throws {
        // Defence in depth: a channel only ever exists for a sealed owner, so a
        // caller that skipped the isolation precondition has nothing to register
        // through, and cannot fabricate one from an active owner.
        let owner = makeOwner("ES+IS", writeRoot: "/tmp/g3/es")
        XCTAssertNil(owner.makeRegistrar())
        XCTAssertThrowsError(try owner.registerDuringGeneration(mut(.extraMutable, id: "sneak"))) { error in
            guard case G3ArmResourceOwner.AllocationError.notSealed = error else {
                return XCTFail("expected notSealed, got \(error)")
            }
        }
        XCTAssertTrue(owner.allocationViolations.isEmpty,
                      "an unsealed registration is a lifecycle error, not an isolation violation")
    }
}
