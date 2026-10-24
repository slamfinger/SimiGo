import XCTest
@testable import SimiGoRuntimeContract

// DISPATCH-LEVEL MODEL-FREE TESTS FOR PER-ARM KV CACHE WIRING.
//
// The gateway suite proved the native cache mechanics (write-before-register,
// consumer abort). This suite proves the PRODUCTION DISPATCH wiring around them,
// with no model and no MLX:
//   * both arms receive DISTINCT cache sessions, and a shared boundary is refused
//     BEFORE dispatch;
//   * a refused step terminates THAT arm, its partial tokens are NOT settled, and
//     the peer arm is unaffected;
//   * a terminated arm refuses later steps without running a forward — no
//     fallback, no second cache;
//   * the `.standard` route never touches a per-arm cache (normal inference is
//     unchanged).
final class G3PerArmCacheWiringTests: XCTestCase {

    // MARK: Fake cache boundary

    /// A model-free stand-in for the MLX `KVCacheSimple` boundary. `beginStep`
    /// resets the latch exactly like the real `KVCacheSimple.beginStep()`; the
    /// spy's forward flips `aborted` to model a refused KV write.
    final class FakeArmCacheBoundary: G3ArmCacheBoundary {
        var aborted = false
        var reason: String?
        private(set) var beginStepCalls = 0
        func beginStep() { beginStepCalls += 1; aborted = false; reason = nil }
        var isolationAborted: Bool { aborted }
        var isolationAbortReason: String? { reason }
    }

    // MARK: Owner + provider builders

    private func resource(
        _ role: G3ResourceRole, id: String, arm: String,
        access: G3ResourceAccess = .armExclusiveMutable
    ) -> OwnedResource {
        OwnedResource(role: role, ownerLabel: arm, access: access, storage: .confirmed(id))
    }

    private func makeOwner(_ arm: String) -> G3ArmResourceOwner {
        G3ArmResourceOwner(
            armID: RuntimeArmID(arm), isolationUnitID: "iso-\(arm)",
            modelWeights: resource(.modelWeights, id: "weights-\(arm)", arm: arm, access: .sharedReadOnly),
            modelContentSHA256: String(repeating: "a", count: 64),
            tokenizerData: OwnedResource(
                role: .tokenizerData, ownerLabel: arm, access: .sharedReadOnly, storage: .indeterminate),
            tokenizerContentSHA256: String(repeating: "b", count: 64),
            kvCache: resource(.kvCache, id: "kv-\(arm)", arm: arm),
            prefixCache: resource(.prefixCache, id: "prefix-\(arm)", arm: arm),
            runtimeScratch: resource(.runtimeScratch, id: "scratch-\(arm)", arm: arm),
            mutableResources: [resource(.extraMutable, id: "extra-\(arm)", arm: arm)],
            writeRoot: "/tmp/g3/\(arm)")
    }

    private func request() throws -> AttestationRequest {
        try AttestationRequest(runID: "cache-wiring-run", challengeNonce: "cache-wiring-nonce")
    }

    struct UntrustedLiveProvider: RuntimeAttestationProvider {
        let providerID = "simigo.g3.per-arm-cache.live"
        let providerKind: RuntimeProviderKind = .swiftMLXLiveWorker
        func collect(_ request: AttestationRequest) throws -> [RuntimeAttestation] { [] }
    }

    // MARK: Cache-aware spy executor

    /// Drives an arm's installed cache session step by step, exactly where the MLX
    /// executor would run `context.model(_, cache: [armCache])`. It records the
    /// forwarded steps and can force a KV refusal at a chosen 1-based step.
    final class CacheAwareSpyExecutor: G3RoutableContinuation, G3CacheSessionInstalling, @unchecked Sendable {
        typealias ContinuationResult = G3GateOutcome

        var tokensToEmit: [Int] = [11, 22, 33]
        var abortOnStep: Int?
        var abortReason = "test_shared_kv"
        /// When true, the gated entry refuses BEFORE any step (an untrusted
        /// provider), so the wired cache is never touched.
        var refuseGate = false

        private(set) var standardCalls = 0
        private(set) var gatedCalls = 0
        private(set) var forwardCalls = 0
        private(set) var session: G3ArmCacheSession?

        @discardableResult
        func installG3CacheSession(_ session: G3ArmCacheSession) -> Bool {
            if let existing = self.session { return existing === session }
            self.session = session
            return true
        }

        func continueExecution(
            _ state: ExecutionStateHandle, nextInputTokens: [Int], maxTokens: Int
        ) async throws -> G3GateOutcome {
            standardCalls += 1
            // Normal inference must NOT touch the per-arm cache.
            return outcome(stage: "standard_ungated", passed: false,
                           evidenceClass: "not_a_g3_run", generationCallCount: 1)
        }

        func continueExecutionG3(
            _ state: ExecutionStateHandle, nextInputTokens: [Int], maxTokens: Int,
            provider: any RuntimeAttestationProvider, request: AttestationRequest
        ) async throws -> G3GateOutcome {
            try await continueExecutionG3(
                state, nextInputTokens: nextInputTokens, maxTokens: maxTokens,
                provider: provider, request: request, registrar: nil)
        }

        func continueExecutionG3(
            _ state: ExecutionStateHandle, nextInputTokens: [Int], maxTokens: Int,
            provider: any RuntimeAttestationProvider, request: AttestationRequest,
            registrar: G3AllocationRegistrar?
        ) async throws -> G3GateOutcome {
            gatedCalls += 1
            if refuseGate {
                throw G3FirstGenerationEntry.EntryError.refused(
                    outcome(stage: "provider_trust", passed: false,
                            evidenceClass: "gate_refused_before_generation",
                            generationCallCount: 0))
            }
            guard let session else {
                throw G3PerArmCacheError.missingCacheSession("spy")
            }
            let boundary = session.boundary as? FakeArmCacheBoundary
            for (index, token) in tokensToEmit.enumerated() {
                let abortNow = (abortOnStep == index + 1)
                let outcome = session.runStep(
                    forward: {
                        self.forwardCalls += 1
                        if abortNow {
                            boundary?.aborted = true
                            boundary?.reason = self.abortReason
                        }
                    },
                    candidateToken: { token })
                switch outcome {
                case .committed, .refusedAfterTermination:
                    break
                case .aborted(let reason):
                    // A refused KV step terminates the arm: the partial output is
                    // never settled and nothing falls back.
                    throw G3PerArmCacheError.armTerminated(reason: reason)
                }
            }
            // Stand in for the production settlement seam: a cleared run enters
            // the gate, consumes its binding and delivers every stage. The axes
            // are recorded explicitly so the runner never infers them.
            let ledger = session.runLedger
            ledger.recordPhase(.generation, .succeeded("committed=\(tokensToEmit.count)"))
            ledger.markSettleEntered()
            ledger.markBindingConsumed()
            ledger.recordPhase(.decode, .succeeded("tokens=\(tokensToEmit.count)"))
            ledger.recordPhase(.registration, .skipped("spy"))
            ledger.recordPhase(.commit, .succeeded("spy"))
            return self.outcome(stage: "cleared", passed: true,
                                evidenceClass: "registered_live_runtime_attestation",
                                generationCallCount: 1)
        }

        private func outcome(
            stage: String, passed: Bool, evidenceClass: String, generationCallCount: Int
        ) -> G3GateOutcome {
            G3GateOutcome(
                gate: "spy", stage: stage, passed: passed, eligibleForRuntimeEvidence: passed,
                evidenceClass: evidenceClass, generationCallCount: generationCallCount,
                modelGenerationStartedByGate: false, isExecutionEvidence: false, reason: "",
                failedChecks: [], runID: "", challengeNonce: "", providerID: "", providerKind: "",
                trustedLiveProviderCount: 0)
        }
    }

    private func arm(
        _ owner: G3ArmResourceOwner, _ executor: CacheAwareSpyExecutor
    ) throws -> G3ArmExecution<CacheAwareSpyExecutor> {
        G3ArmExecution(
            owner: owner, executor: executor, provider: UntrustedLiveProvider(),
            request: try request(), state: .g3RoutingPlaceholder,
            nextInputTokens: [1, 2], maxTokens: 3)
    }

    private func distinctSessionFactory(
        abortOnStepForES: Int? = nil
    ) -> G3PerArmCacheSessionFactory {
        { armID, _ in
            G3ArmCacheSession(armID: armID.rawValue, boundary: FakeArmCacheBoundary())
        }
    }

    // MARK: 1. Both arms get independent sessions and settle

    func testTwoArmsGetIndependentCacheSessionsAndBothSettle() async throws {
        let esOwner = makeOwner("ES+IS")
        let isOwner = makeOwner("IS-only")
        let esSpy = CacheAwareSpyExecutor()
        let isSpy = CacheAwareSpyExecutor()
        let report = try await G3DualArmRunner.run(
            try arm(esOwner, esSpy), try arm(isOwner, isSpy),
            makeCacheSession: distinctSessionFactory())

        XCTAssertTrue(report.perArmCacheWired)
        XCTAssertTrue(report.cacheBoundariesDistinct)
        XCTAssertTrue(report.eachArmSettled)
        XCTAssertTrue(report.armTerminations.isEmpty)
        XCTAssertTrue(report.arms.allSatisfy { $0.settled })
        XCTAssertEqual(esSpy.standardCalls, 0)
        XCTAssertEqual(isSpy.standardCalls, 0)
        XCTAssertEqual(esSpy.gatedCalls, 1)
        XCTAssertEqual(isSpy.gatedCalls, 1)
        // Distinct sessions, distinct arm ids, separate committed ledgers.
        let esSession = try XCTUnwrap(esSpy.session)
        let isSession = try XCTUnwrap(isSpy.session)
        XCTAssertFalse(esSession === isSession)
        XCTAssertNotEqual(esSession.armID, isSession.armID)
        XCTAssertEqual(esSession.committedTokens, [11, 22, 33])
        XCTAssertEqual(isSession.committedTokens, [11, 22, 33])
        XCTAssertEqual(esSpy.forwardCalls, 3)
        XCTAssertEqual(isSpy.forwardCalls, 3)
    }

    // MARK: 2. A refused step terminates THAT arm and is not settled

    func testRefusedStepTerminatesThatArmAndIsNotSettled() async throws {
        let esOwner = makeOwner("ES+IS")
        let isOwner = makeOwner("IS-only")
        let esSpy = CacheAwareSpyExecutor()
        let isSpy = CacheAwareSpyExecutor()
        esSpy.abortOnStep = 2                       // second step's KV write is refused
        let report = try await G3DualArmRunner.run(
            try arm(esOwner, esSpy), try arm(isOwner, isSpy),
            makeCacheSession: distinctSessionFactory())

        XCTAssertTrue(report.perArmCacheWired)
        XCTAssertFalse(report.eachArmSettled, "a terminated arm means the run is not settled")
        XCTAssertEqual(report.armTerminations["ES+IS"], "test_shared_kv")
        XCTAssertNil(report.armTerminations["IS-only"])
        XCTAssertTrue(report.isolationCompromisedAfterAllocation)

        let esRecord = try XCTUnwrap(report.arms.first { $0.armID == "ES+IS" })
        let isRecord = try XCTUnwrap(report.arms.first { $0.armID == "IS-only" })
        XCTAssertFalse(esRecord.settled)
        XCTAssertEqual(esRecord.outcome.stage, "kv_isolation_abort")
        XCTAssertEqual(esRecord.outcome.reason, "test_shared_kv")
        XCTAssertTrue(isRecord.settled, "the peer arm is unaffected by this arm's refusal")

        let esSession = try XCTUnwrap(esSpy.session)
        // The refused token (22) and everything after it were never committed.
        XCTAssertEqual(esSession.committedTokens, [11])
        XCTAssertTrue(esSession.isTerminated)
        // The forward ran only for steps 1 and 2 — no later step after the abort.
        XCTAssertEqual(esSpy.forwardCalls, 2)
        // The peer committed all three tokens independently.
        XCTAssertEqual(isSpy.session?.committedTokens, [11, 22, 33])
        XCTAssertEqual(isSpy.forwardCalls, 3)
    }

    // MARK: 3. A terminated arm refuses later steps — no fallback, no new cache

    func testTerminatedArmRefusesFurtherStepsWithoutFallback() async throws {
        let esOwner = makeOwner("ES+IS")
        let isOwner = makeOwner("IS-only")
        let esSpy = CacheAwareSpyExecutor()
        let isSpy = CacheAwareSpyExecutor()
        esSpy.abortOnStep = 1
        _ = try await G3DualArmRunner.run(
            try arm(esOwner, esSpy), try arm(isOwner, isSpy),
            makeCacheSession: distinctSessionFactory())

        let session = try XCTUnwrap(esSpy.session)
        let forwardsAfterRun = esSpy.forwardCalls
        let standardAfterRun = esSpy.standardCalls
        var cursor = 0
        let outcome = session.runStep(
            forward: { cursor += 1 },
            candidateToken: { 99 })
        XCTAssertEqual(outcome, .refusedAfterTermination(reason: "test_shared_kv"))
        XCTAssertEqual(cursor, 0, "a terminated arm must not run another forward")
        XCTAssertEqual(esSpy.forwardCalls, forwardsAfterRun)
        XCTAssertEqual(esSpy.standardCalls, standardAfterRun,
                       "termination must not fall back to the standard route")
        XCTAssertEqual(session.committedTokens, [], "the refused token was never committed")
    }

    // MARK: 4. One cache shared by both arms is refused BEFORE dispatch

    func testSharedCacheBoundaryIsRefusedBeforeDispatch() async throws {
        let esOwner = makeOwner("ES+IS")
        let isOwner = makeOwner("IS-only")
        let esSpy = CacheAwareSpyExecutor()
        let isSpy = CacheAwareSpyExecutor()
        let shared = FakeArmCacheBoundary()
        let sharedFactory: G3PerArmCacheSessionFactory = { armID, _ in
            G3ArmCacheSession(armID: armID.rawValue, boundary: shared)
        }

        do {
            _ = try await G3DualArmRunner.run(
                try arm(esOwner, esSpy), try arm(isOwner, isSpy),
                makeCacheSession: sharedFactory)
            XCTFail("a shared mutable cache must be refused before dispatch")
        } catch let error as G3DualArmRunner.RunError {
            guard case .cacheWiringRefused(let reason) = error else {
                return XCTFail("expected cacheWiringRefused, got \(error)")
            }
            XCTAssertTrue(reason.contains("armsShareMutableCache"), reason)
        }
        XCTAssertEqual(esSpy.gatedCalls, 0, "no arm may be dispatched on a shared cache")
        XCTAssertEqual(isSpy.gatedCalls, 0)
        XCTAssertEqual(esSpy.standardCalls, 0)
    }

    // MARK: 5. The standard route never touches a per-arm cache

    func testStandardRouteNeverTouchesPerArmCache() async throws {
        let esOwner = makeOwner("ES+IS")
        let isOwner = makeOwner("IS-only")
        let esSpy = CacheAwareSpyExecutor()
        let isSpy = CacheAwareSpyExecutor()
        // Install a session first: normal inference must still ignore it.
        let session = G3ArmCacheSession(armID: "ES+IS", boundary: FakeArmCacheBoundary())
        XCTAssertTrue(esSpy.installG3CacheSession(session))

        let _ = try await G3ExecutionDispatch.run(
            esSpy, route: .standard, state: .g3RoutingPlaceholder,
            nextInputTokens: [1], maxTokens: 1)
        _ = isSpy

        XCTAssertEqual(esSpy.standardCalls, 1)
        XCTAssertEqual(esSpy.gatedCalls, 0)
        XCTAssertEqual(esSpy.forwardCalls, 0)
        XCTAssertEqual(session.stepCount, 0)
        XCTAssertEqual(session.committedTokens, [])
    }

    // MARK: 5b. Release retires the slot: a terminated arm cannot be re-armed

    /// The executor-level form of "termination is irreversible". A second
    /// session cannot replace the first, and after `release()` (the only way the
    /// installed reference disappears) the slot still refuses every install. The
    /// terminated arm therefore cannot re-enter generation through a fresh cache.
    func testReleasedSessionSlotCannotBeReArmed() {
        let slot = G3CacheSessionSlot()
        let first = G3ArmCacheSession(armID: "ES+IS", boundary: FakeArmCacheBoundary())
        let different = G3ArmCacheSession(armID: "ES+IS", boundary: FakeArmCacheBoundary())

        XCTAssertTrue(slot.install(first))
        XCTAssertTrue(slot.install(first), "installing the same session again is idempotent")
        XCTAssertFalse(slot.install(different), "one arm cannot hold two cache sessions")
        XCTAssertFalse(slot.isRetired)

        // Terminate the arm, then release the slot (the caches are dropped).
        first.terminate(reason: "kv_write_to_unregistered_storage(kv_cache)")
        slot.release()
        XCTAssertNil(slot.installed, "release must drop the cache reference")
        XCTAssertTrue(slot.isRetired)

        let fresh = G3ArmCacheSession(armID: "ES+IS", boundary: FakeArmCacheBoundary())
        XCTAssertFalse(slot.install(fresh), "a released arm must not be re-armed")
        XCTAssertNil(slot.installed)

        // Releasing again is harmless and does not resurrect the slot.
        slot.release()
        XCTAssertFalse(slot.install(fresh))
    }

    /// A release must terminate a LIVE session, not only drop the reference. This
    /// is the contract-level half of "release racing a step fails closed": the
    /// step's commit check observes the tombstone and refuses before sampling.
    func testReleaseTerminatesTheLiveSession() {
        let slot = G3CacheSessionSlot()
        let session = G3ArmCacheSession(armID: "ES+IS", boundary: FakeArmCacheBoundary())
        XCTAssertTrue(slot.install(session))
        XCTAssertNil(session.abortReason)

        slot.release()

        XCTAssertEqual(session.abortReason, "cache_session_released")
        XCTAssertTrue(session.isTerminated)
        let outcome = session.runStep(
            forward: { XCTFail("a released session must not run a forward") },
            candidateToken: { 7 })
        XCTAssertEqual(outcome, .refusedAfterTermination(reason: "cache_session_released"))
        XCTAssertTrue(session.committedTokens.isEmpty)
    }

    /// The prefill claim is atomic: two continuations racing one session cannot
    /// both win, so the bound prefix cannot be appended to the cache twice. The
    /// claim is never released, including after a failed first continuation.
    func testContinuationClaimIsSingleUse() {
        let session = G3ArmCacheSession(armID: "ES+IS", boundary: FakeArmCacheBoundary())
        XCTAssertTrue(session.claimContinuation())
        XCTAssertFalse(session.claimContinuation(), "a second prefill must be refused")

        // Even a terminated session does not give its claim back.
        session.terminate(reason: "forward_threw(boom)")
        XCTAssertFalse(session.claimContinuation())
    }

    // MARK: 6. A gate refusal with a wired cache is NOT settled

    /// The report must never claim settlement just because a per-arm cache was
    /// wired: if the gate refuses, no step ran and no output exists. This pins the
    /// "partial/unrun output is not a settled result" rule at the report level.
    func testGateRefusalWithWiredCacheIsNotSettled() async throws {
        let esOwner = makeOwner("ES+IS")
        let isOwner = makeOwner("IS-only")
        let esSpy = CacheAwareSpyExecutor()
        let isSpy = CacheAwareSpyExecutor()
        esSpy.refuseGate = true
        isSpy.refuseGate = true
        let report = try await G3DualArmRunner.run(
            try arm(esOwner, esSpy), try arm(isOwner, isSpy),
            makeCacheSession: distinctSessionFactory())

        XCTAssertTrue(report.perArmCacheWired)
        XCTAssertTrue(report.cacheBoundariesDistinct)
        XCTAssertFalse(report.eachArmSettled,
                       "a refused gate has no settled output, even with a wired cache")
        XCTAssertFalse(report.anyArmClearedGate)
        XCTAssertEqual(report.totalGenerationCallCount, 0)
        XCTAssertTrue(report.armTerminations.isEmpty,
                      "no KV abort occurred; the gate refused before any step")
        XCTAssertTrue(report.arms.allSatisfy { !$0.settled })
        XCTAssertEqual(esSpy.forwardCalls, 0)
        XCTAssertEqual(isSpy.forwardCalls, 0)
        XCTAssertEqual(esSpy.session?.stepCount, 0)
        XCTAssertEqual(isSpy.session?.stepCount, 0)
    }

    // MARK: 7. An executor that cannot hold its own session is refused before dispatch

    func testExecutorWithoutSessionSupportIsRefusedBeforeDispatch() async throws {
        let esOwner = makeOwner("ES+IS")
        let isOwner = makeOwner("IS-only")
        // G3IsolatedWorker is a value type and cannot install a session.
        let esWorker = G3IsolatedWorker(generate: {})
        let isWorker = G3IsolatedWorker(generate: {})
        let req = try request()
        let provider = UntrustedLiveProvider()

        do {
            _ = try await G3DualArmRunner.run(
                G3ArmExecution(owner: esOwner, executor: esWorker, provider: provider,
                               request: req, state: .g3RoutingPlaceholder,
                               nextInputTokens: [1], maxTokens: 1),
                G3ArmExecution(owner: isOwner, executor: isWorker, provider: provider,
                               request: req, state: .g3RoutingPlaceholder,
                               nextInputTokens: [1], maxTokens: 1),
                makeCacheSession: distinctSessionFactory())
            XCTFail("an executor that cannot hold a per-arm cache must be refused")
        } catch let error as G3DualArmRunner.RunError {
            guard case .cacheWiringRefused(let reason) = error else {
                return XCTFail("expected cacheWiringRefused, got \(error)")
            }
            XCTAssertTrue(reason.contains("executor_cannot_install_cache_session"), reason)
        }
    }

    // MARK: 8. One executor reused for both arms is refused before dispatch

    /// The per-arm cache lives on the executor. Reusing ONE executor for both arms
    /// would try to install a second, different session — refused, so a single
    /// mutable cache can never silently serve both arms.
    func testOneExecutorReusedForBothArmsIsRefusedBeforeDispatch() async throws {
        let esOwner = makeOwner("ES+IS")
        let isOwner = makeOwner("IS-only")
        let sharedExecutor = CacheAwareSpyExecutor()

        do {
            _ = try await G3DualArmRunner.run(
                try arm(esOwner, sharedExecutor), try arm(isOwner, sharedExecutor),
                makeCacheSession: distinctSessionFactory())
            XCTFail("one executor cannot hold two per-arm caches")
        } catch let error as G3DualArmRunner.RunError {
            guard case .cacheWiringRefused(let reason) = error else {
                return XCTFail("expected cacheWiringRefused, got \(error)")
            }
            XCTAssertTrue(reason.contains("executor_cannot_install_cache_session"), reason)
        }
        XCTAssertEqual(sharedExecutor.gatedCalls, 0, "nothing may be dispatched")
        XCTAssertEqual(sharedExecutor.standardCalls, 0)
    }
}
