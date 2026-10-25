//
//  G3NativeCacheDispatchTests.swift
//  SimiGo2ExperimentalTests
//
// DISPATCH-LEVEL PROOF OVER REAL NATIVE CACHES (no model, no provider trust).
//
// The contract suite proved the runner/dispatch wiring over a FAKE boundary; the
// gateway suite proved the native seam over standalone caches. Neither proved the
// two composed: that a production-shaped `G3DualArmRunner.run` with the REAL
// `MLXPerArmKVCacheFactory` gives each arm its own per-layer `KVCacheSimple`,
// that each layer's write is gated before its first write, that the refusal
// reaches the REAL attention consumer, and that only the refusing arm dies.
//
// These tests drive `attentionWithCacheUpdate` over real caches from inside
// `G3ArmCacheSession.runStep`, which is exactly where `continueExecutionG3` runs
// `context.model(_, cache: caches)`. No model is loaded, no live provider is
// registered, no G3 execution is claimed: the executor's gate is simulated at
// the dispatch level, so `isExecutionEvidence` stays false.
//

import Foundation
import Testing
import MLX
import MLXLMCommon
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

// MARK: - Model-free executor over REAL per-arm caches

/// Drives its installed session step by step, with each step writing through the
/// REAL `attentionWithCacheUpdate` on the arm's OWN per-layer caches. It mirrors
/// the production executor's commit rule: only a non-aborted step commits a
/// token; an aborted step terminates the arm by throwing out of the gated method.
private final class NativeCacheStepExecutor:
    G3RoutableContinuation, G3CacheSessionInstalling, @unchecked Sendable
{
    typealias ContinuationResult = G3GateOutcome

    var tokensToEmit: [Int] = [11, 22, 33]
    /// Optional fault injection BEFORE a step's forward runs. Used to seat a layer
    /// on foreign KV at a chosen step, or to attempt removing a layer's write gate,
    /// so the outcome comes from the REAL gateway/binding policy rather than a
    /// substituted observer.
    var beforeStep: ((Int, [KVCacheSimple]) throws -> Void)?

    private(set) var standardCalls = 0
    private(set) var gatedCalls = 0
    private(set) var forwards = 0
    private(set) var session: G3ArmCacheSession?

    @discardableResult
    func installG3CacheSession(_ session: G3ArmCacheSession) -> Bool {
        if let existing = self.session { return existing === session }
        self.session = session
        return true
    }

    /// Normal inference: no gate, and the per-arm cache is not touched at all.
    func continueExecution(
        _ state: ExecutionStateHandle, nextInputTokens: [Int], maxTokens: Int
    ) async throws -> G3GateOutcome {
        standardCalls += 1
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
        guard let session else { throw G3PerArmCacheError.missingCacheSession("native-dispatch") }
        guard let boundary = session.boundary as? MLXKVCacheBoundary else {
            throw G3PerArmCacheError.missingCacheSession("not an MLX boundary")
        }
        let caches = boundary.caches.compactMap { $0 as? KVCacheSimple }
        guard !caches.isEmpty else {
            throw G3PerArmCacheError.missingCacheSession("no resolved native cache")
        }

        for (index, token) in tokensToEmit.enumerated() {
            let thisStep = index + 1
            let outcome = try session.runStep(
                forward: {
                    self.forwards += 1
                    if let beforeStep = self.beforeStep {
                        try beforeStep(thisStep, caches)
                    }
                    for cache in caches {
                        let attended = attentionWithCacheUpdate(
                            queries: Self.tensor(), keys: Self.tensor(),
                            values: Self.tensor(), cache: cache, scale: 0.25)
                        attended.eval()
                    }
                },
                candidateToken: { token })
            switch outcome {
            case .committed:
                continue
            case .aborted(let reason):
                throw G3PerArmCacheError.armTerminated(reason: reason)
            case .refusedAfterTermination(let reason):
                throw G3PerArmCacheError.armTerminated(reason: reason)
            }
        }
        // Model-free stand-in for the production settlement seam. A cleared run
        // records all three axes; an aborted step threw above and leaves them
        // `notEntered`.
        let ledger = session.runLedger
        ledger.recordPhase(.generation, .succeeded("committed=\(tokensToEmit.count)"))
        ledger.markSettleEntered()
        ledger.markBindingConsumed()
        ledger.recordPhase(.decode, .succeeded("tokens=\(tokensToEmit.count)"))
        ledger.recordPhase(.registration, .skipped("spy"))
        ledger.recordPhase(.commit, .succeeded("spy"))
        return outcome(stage: "cleared", passed: true,
                       evidenceClass: "registered_live_runtime_attestation",
                       generationCallCount: 1)
    }

    /// A [B, heads, L, dim] tensor shaped like one decode step's Q/K/V.
    private static func tensor() -> MLXArray {
        let t = ones([1, 1, 1, 8], dtype: .float32)
        t.eval()
        return t
    }

    private func outcome(
        stage: String, passed: Bool, evidenceClass: String, generationCallCount: Int
    ) -> G3GateOutcome {
        G3GateOutcome(
            gate: "native-dispatch", stage: stage, passed: passed,
            eligibleForRuntimeEvidence: passed, evidenceClass: evidenceClass,
            generationCallCount: generationCallCount, modelGenerationStartedByGate: false,
            isExecutionEvidence: false, reason: "", failedChecks: [],
            runID: "", challengeNonce: "", providerID: "", providerKind: "",
            trustedLiveProviderCount: 0)
    }
}

// MARK: - Suite

struct G3NativeCacheDispatchTests {

    /// Same explicit metallib discovery as the gateway suite: a skipped MLX test
    /// is not evidence, so the CPU runtime is initialized eagerly.
    private static let ensureRuntime: Void = {
        let fm = FileManager.default
        if let path = ProcessInfo.processInfo.environment["SIMIGO_MLX_METALLIB"],
           !path.isEmpty, fm.fileExists(atPath: path) {
            GPU.metallib = URL(fileURLWithPath: path); return
        }
        let relative = "mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
        let bases = [Bundle.main.resourceURL, Bundle.main.bundleURL,
                     Bundle.main.bundleURL.appendingPathComponent("../Resources")]
        for base in bases {
            let cand = base?.appendingPathComponent(relative)
            if let cand, fm.fileExists(atPath: cand.path) { GPU.metallib = cand; return }
        }
        let build = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build")
        if let e = fm.enumerator(at: build, includingPropertiesForKeys: nil) {
            for case let url as URL in e where url.path.hasSuffix(relative) { GPU.metallib = url; break }
        }
    }()

    private func mlx() { _ = Self.ensureRuntime }

    // MARK: Sealed arms + unavailable provider

    private func resource(
        _ role: G3ResourceRole, id: String, arm: String,
        access: G3ResourceAccess = .armExclusiveMutable
    ) -> OwnedResource {
        OwnedResource(role: role, ownerLabel: arm, access: access, storage: .confirmed(id))
    }

    private func makeArm(_ arm: String) -> G3ArmResourceOwner {
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
            writeRoot: "/tmp/g3/native/\(arm)")
    }

    /// Two ACTIVE arms. Deliberately NOT pre-sealed: `G3DualArmRunner.run` checks
    /// isolation and then seals them itself; sealing early would make the check
    /// see each arm's own resources as already-owned and refuse it.
    private func pair() -> (G3ArmResourceOwner, G3ArmResourceOwner) {
        (makeArm("ES+IS"), makeArm("IS-only"))
    }

    /// A single arm sealed against a peer, for tests that need a registrar without
    /// going through the runner.
    private func sealedOwner(_ arm: String) -> G3ArmResourceOwner {
        let owner = makeArm(arm)
        let peer = makeArm("\(arm)-peer")
        owner.seal(against: peer); peer.seal(against: owner)
        return owner
    }

    struct UntrustedLiveProvider: RuntimeAttestationProvider {
        let providerID = "simigo.g3.native-cache-dispatch.live"
        let providerKind: RuntimeProviderKind = .swiftMLXLiveWorker
        func collect(_ request: AttestationRequest) throws -> [RuntimeAttestation] { [] }
    }

    /// The PRODUCTION per-arm shape: one native cache PER LAYER, built by the real
    /// factory, distinct instances for every arm.
    private func nativePerArmFactory(layers: Int = 2) -> G3PerArmCacheSessionFactory {
        { armID, registrar in
            try MLXPerArmKVCacheFactory.makeSession(
                armID: armID, registrar: registrar,
                caches: (0..<layers).map { _ in KVCacheSimple() })
        }
    }

    private func execution(
        _ owner: G3ArmResourceOwner, _ executor: NativeCacheStepExecutor
    ) throws -> G3ArmExecution<NativeCacheStepExecutor> {
        G3ArmExecution(
            owner: owner, executor: executor, provider: UntrustedLiveProvider(),
            request: try AttestationRequest(runID: "native-dispatch-run",
                                            challengeNonce: "native-dispatch-nonce"),
            state: .g3RoutingPlaceholder, nextInputTokens: [1, 2], maxTokens: 3)
    }

    private func caches(of executor: NativeCacheStepExecutor) -> [KVCacheSimple] {
        guard let boundary = executor.session?.boundary as? MLXKVCacheBoundary else { return [] }
        return boundary.caches.compactMap { $0 as? KVCacheSimple }
    }

    // MARK: 1. Both arms run and settle over their OWN per-layer native caches

    @Test func bothArmsSettleOverIndependentPerLayerNativeCaches() async throws {
        mlx()
        try await Device.withDefaultDevice(.cpu) {
            let (esOwner, isOwner) = pair()
            let es = NativeCacheStepExecutor()
            let isArm = NativeCacheStepExecutor()

            let report = try await G3DualArmRunner.run(
                try execution(esOwner, es), try execution(isOwner, isArm),
                makeCacheSession: nativePerArmFactory())

            #expect(report.perArmCacheWired)
            #expect(report.cacheBoundariesDistinct)
            #expect(report.eachArmSettled)
            #expect(report.arms.map(\.settled) == [true, true])
            #expect(report.totalGenerationCallCount == 2)
            #expect(report.armTerminations.isEmpty)
            #expect(es.standardCalls == 0)
            #expect(isArm.standardCalls == 0)
            #expect(es.forwards == 3)
            #expect(isArm.forwards == 3)
            #expect(es.session?.committedTokens == [11, 22, 33])
            #expect(isArm.session?.committedTokens == [11, 22, 33])

            // Each arm's native caches are distinct objects, one per layer, and
            // each layer's KV really was written through the native seam.
            let esCaches = caches(of: es)
            let isCaches = caches(of: isArm)
            #expect(esCaches.count == 2)
            #expect(isCaches.count == 2)
            #expect(Set(esCaches.map { ObjectIdentifier($0) })
                        .isDisjoint(with: Set(isCaches.map { ObjectIdentifier($0) })))
            for cache in esCaches + isCaches {
                #expect(cache.writeObserver != nil, "every layer is gated")
                #expect(cache.state[0].dim(2) == 3, "three committed tokens per layer")
            }
        }
    }

    // MARK: 2. Clearing a BOUND write gate is refused and kills ONLY that arm

    /// The bypass named in review: a path that merely HOLDS a cache reference
    /// assigned `cache.writeObserver = nil`, after which `update()` would write
    /// with no gateway. The gate is now a binding, so the assignment is refused
    /// and latched. The attempt is made MID-FORWARD of step 2 on purpose: that is
    /// the strongest window, because no pre-step verification can help anymore —
    /// the very `update()` of the tampering step must refuse the write, the step's
    /// token must be discarded, and every later step must be refused.
    @Test func clearingABoundObserverIsRefusedAndTerminatesOnlyThatArm() async throws {
        mlx()
        try await Device.withDefaultDevice(.cpu) {
            let (esOwner, isOwner) = pair()
            let es = NativeCacheStepExecutor()
            let isArm = NativeCacheStepExecutor()

            es.beforeStep = { step, caches in
                guard step == 2, let first = caches.first else { return }
                // The attempted un-gating. A bound cache refuses it.
                first.writeObserver = nil
            }

            let report = try await G3DualArmRunner.run(
                try execution(esOwner, es), try execution(isOwner, isArm),
                makeCacheSession: nativePerArmFactory())

            let violation = "write_observer_mutated_after_binding"
            #expect(report.perArmCacheWired)
            #expect(report.eachArmSettled == false, "a terminated arm means the run is not settled")
            #expect(report.armTerminations["ES+IS"] == violation)
            #expect(report.armTerminations["IS-only"] == nil)
            #expect(report.isolationCompromisedAfterAllocation)

            let esRecord = try #require(report.arms.first { $0.armID == "ES+IS" })
            let isRecord = try #require(report.arms.first { $0.armID == "IS-only" })
            #expect(esRecord.outcome.stage == "kv_isolation_abort")
            #expect(esRecord.outcome.reason == violation)
            #expect(esRecord.settled == false)
            #expect(isRecord.settled, "the peer arm is unaffected by this arm's refusal")

            // The tampering step DID run a forward (the clear happens inside it),
            // but its token is discarded: the write was refused, so there is no
            // output of that step to sample from.
            #expect(es.session?.committedTokens == [11])
            #expect(es.session?.isTerminated == true)
            #expect(es.forwards == 2)
            #expect(es.standardCalls == 0, "termination must not fall back to the standard route")

            // The gate was NOT removed: the cache still carries its observer, the
            // violation is latched permanently, and the tampered layer wrote
            // nothing this step. The peer layer's partial write exists but is
            // never consumed again because the arm is dead.
            let esCaches = caches(of: es)
            #expect(esCaches[0].writeObserver != nil, "a bound gate cannot be cleared")
            #expect(esCaches[0].observerBindingViolation == violation)
            #expect(esCaches[0].isolationAborted)
            #expect(esCaches[0].state[0].dim(2) == 1)
            #expect(esCaches[1].state[0].dim(2) == 2)

            // The peer committed all three tokens on both layers.
            #expect(isArm.session?.committedTokens == [11, 22, 33])
            let isCaches = caches(of: isArm)
            #expect(isCaches.allSatisfy { $0.state[0].dim(2) == 3 && !$0.isolationAborted })
        }
    }

    // MARK: 2b. A REAL gateway refusal (cascade) is reported as unsettled for that arm only

    /// Same report invariants as test 2, but the refusal is produced by the
    /// PRODUCTION gateway policy: layer 0 is seated at step 2 on a window whose
    /// storage this arm never registered, so its reuse write is refused, and the
    /// gateway's arm-level latch refuses layer 1 as well. This closes the gap
    /// between the session-level cascade tests and the runner report: the run must
    /// NOT report the terminated arm as settled, and the peer must still settle.
    @Test func gatewayCascadeIsReportedUnsettledOnlyForTheRefusingArm() async throws {
        mlx()
        try await Device.withDefaultDevice(.cpu) {
            let (esOwner, isOwner) = pair()
            let es = NativeCacheStepExecutor()
            let isArm = NativeCacheStepExecutor()

            es.beforeStep = { step, caches in
                guard step == 2, let first = caches.first else { return }
                let k = ones([1, 1, 4, 8], dtype: .float32)
                let v = ones([1, 1, 4, 8], dtype: .float32)
                k.eval(); v.eval()
                // Foreign, unregistered storage with spare capacity: the next
                // 1-token write is a REUSE, which the gateway must refuse.
                first.state = [k, v]
                _ = first.trim(1)
            }

            let report = try await G3DualArmRunner.run(
                try execution(esOwner, es), try execution(isOwner, isArm),
                makeCacheSession: nativePerArmFactory())

            let refusal = "kv_write_to_unregistered_storage(kv_cache)"
            #expect(report.perArmCacheWired)
            #expect(report.eachArmSettled == false, "a terminated arm means the run is not settled")
            #expect(report.armTerminations["ES+IS"] == refusal)
            #expect(report.armTerminations["IS-only"] == nil)
            #expect(report.isolationCompromisedAfterAllocation)

            let esRecord = try #require(report.arms.first { $0.armID == "ES+IS" })
            let isRecord = try #require(report.arms.first { $0.armID == "IS-only" })
            #expect(esRecord.outcome.stage == "kv_isolation_abort")
            #expect(esRecord.outcome.reason == refusal)
            #expect(esRecord.settled == false)
            #expect(isRecord.settled, "the peer arm is unaffected by this arm's refusal")

            #expect(es.session?.committedTokens == [11], "the refused step's token is never committed")
            #expect(es.session?.isTerminated == true)
            #expect(es.forwards == 2, "no step after the refusal enters a forward")
            #expect(es.standardCalls == 0, "termination must not fall back to the standard route")

            // Layer 0 kept only the injected foreign window (offset rolled back to
            // 3); layer 1 wrote step 1 only and was refused by the cascade at step 2.
            let esCaches = caches(of: es)
            #expect(esCaches[0].state[0].dim(2) == 3)
            #expect(esCaches[1].state[0].dim(2) == 1)
            #expect(esCaches[1].isolationAbortReason?.hasPrefix("arm_terminated_after(") == true)

            #expect(isArm.session?.committedTokens == [11, 22, 33])
            let isCaches = caches(of: isArm)
            let peerStillClean = isCaches.allSatisfy {
                $0.state[0].dim(2) == 3 && !$0.isolationAborted
            }
            #expect(peerStillClean)
        }
    }

    // MARK: 3. The same native cache for both arms is refused BEFORE dispatch

    /// A holder so the factory can hand the SAME native arrays to both arms — the
    /// exact wiring bug the reviewer asked to forbid. The boundary-object guard
    /// cannot see it; the native observer check must refuse it, and the runner
    /// must surface that as a wiring refusal with nothing dispatched.
    private final class SharedCacheBox: @unchecked Sendable {
        var caches: [KVCache] = []
    }

    @Test func sameNativeCacheForBothArmsIsRefusedBeforeDispatch() async throws {
        mlx()
        try await Device.withDefaultDevice(.cpu) {
            let (esOwner, isOwner) = pair()
            let es = NativeCacheStepExecutor()
            let isArm = NativeCacheStepExecutor()
            let box = SharedCacheBox()
            let factory: G3PerArmCacheSessionFactory = { armID, registrar in
                if box.caches.isEmpty {
                    box.caches = [KVCacheSimple(), KVCacheSimple()]
                }
                return try MLXPerArmKVCacheFactory.makeSession(
                    armID: armID, registrar: registrar, caches: box.caches)
            }

            do {
                _ = try await G3DualArmRunner.run(
                    try execution(esOwner, es), try execution(isOwner, isArm),
                    makeCacheSession: factory)
                Issue.record("one native cache serving both arms must be refused")
            } catch let error as G3DualArmRunner.RunError {
                guard case .cacheWiringRefused(let reason) = error else {
                    Issue.record("expected cacheWiringRefused, got \(error)")
                    return
                }
                #expect(reason.contains("armsShareMutableCache"), Comment(rawValue: reason))
            }
            #expect(es.gatedCalls == 0, "no arm may be dispatched on a shared native cache")
            #expect(isArm.gatedCalls == 0)
            #expect(es.standardCalls == 0)
            #expect(es.forwards == 0)
        }
    }

    // MARK: 4. Normal inference is untouched by an installed per-arm cache

    @Test func standardRouteIgnoresTheInstalledNativeCache() async throws {
        mlx()
        try await Device.withDefaultDevice(.cpu) {
            let esOwner = sealedOwner("ES+IS")
            let es = NativeCacheStepExecutor()
            let registrar = try #require(esOwner.makeRegistrar())
            let session = try MLXPerArmKVCacheFactory.makeSession(
                armID: RuntimeArmID("ES+IS"), registrar: registrar,
                caches: (0..<2).map { _ in KVCacheSimple() })
            #expect(es.installG3CacheSession(session))

            _ = try await G3ExecutionDispatch.run(
                es, route: .standard, state: .g3RoutingPlaceholder,
                nextInputTokens: [1], maxTokens: 1)

            #expect(es.standardCalls == 1)
            #expect(es.gatedCalls == 0)
            #expect(es.forwards == 0)
            #expect(session.stepCount == 0)
            #expect(session.committedTokens.isEmpty)
            #expect(caches(of: es).allSatisfy { $0.state.isEmpty })
        }
    }
}
