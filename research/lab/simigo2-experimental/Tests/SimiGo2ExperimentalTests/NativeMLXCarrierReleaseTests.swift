// SPDX-License-Identifier: MIT

// NATIVE MLX CARRIER-RELEASE LIFECYCLE TESTS — real MLX objects, ZERO model weights
//
// NativeCarrierLifecycleTests proved the release PROTOCOL against a model-free
// double. This file closes the reviewer's named evidence gap: do the release
// facts hold against the REAL MLX runtime — a genuine `G3ArmCacheSession` over a
// real `MLXKVCacheBoundary` + `KVCacheSimple` + write observer, and storage
// identity read from actual `MLXArray`s through the published
// `MLXArray.mlxStorageIdentity`? No model is loaded; every array is materialized
// on the CPU device and every cache holds tiny synthetic KV.
//
// THREE PROPOSITIONS, DELIBERATELY KEPT APART (the reviewer's core warning):
//   (A) ARC OBJECT LIFECYCLE — the cache/gateway/observer graph is deallocated.
//       Proven with weak probes after `release()`. This is a Swift reference fact.
//   (B) OLD-CARRIER NON-REUSE — the retired slot/session/carrier can no longer be
//       installed, read, or written. Proven by tombstones and terminal state.
//   (C) STORAGE RELATIONSHIP — two buffers share / are distinct / are unconfirmable,
//       read from `mlxStorageIdentity`. This is an ALIASING RELATION, NOT proof
//       that MLX's allocator returned pages to the OS.
// None of these measures the GPU allocator freeing device memory to the operating
// system; deallocating the Swift objects (A) and confirming distinct storage (C)
// are claimed, OS-level page reclamation is NOT.

import Foundation
import Testing
import MLX
import MLXLMCommon
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

struct NativeMLXCarrierReleaseTests {

    /// Same eager metallib discovery as the other native suites: a skipped
    /// isolation test is not evidence, so the CPU runtime is initialized eagerly
    /// and these tests fail loudly rather than silently passing with no real MLX.
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
            for case let url as URL in e where url.path.hasSuffix(relative) {
                GPU.metallib = url; break
            }
        }
    }()

    private func mlx() { _ = Self.ensureRuntime }

    // MARK: Model-free sealed arms and real tensors (mirrors the native G3 suites)

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
            writeRoot: "/tmp/g3-ncl/\(arm)")
    }

    private func sealedPair() -> (G3ArmResourceOwner, G3ArmResourceOwner) {
        let es = makeArm("ES+IS")
        let peer = makeArm("IS-only")
        es.seal(against: peer); peer.seal(against: es)
        return (es, peer)
    }

    private func kvTensor(_ seq: Int, headDim: Int = 8) -> MLXArray {
        let t = ones([1, 1, seq, headDim], dtype: .float32)
        t.eval()
        return t
    }

    @discardableResult
    private func materialize(_ a: MLXArray) -> MLXArray { a.eval(); return a }

    private func attend(_ cache: KVCacheSimple) {
        let attended = attentionWithCacheUpdate(
            queries: kvTensor(1), keys: kvTensor(1), values: kvTensor(1),
            cache: cache, scale: 0.25)
        attended.eval()
    }

    /// The confirmed storage id of a real, materialized buffer, exactly as the
    /// gateway records it (`mlx:d=<desc>:b=<handle>`). `nil` when the array is
    /// unmaterialized — the honest "cannot confirm" case, never a fabricated id.
    private func confirmedID(_ array: MLXArray, arm: String) -> String? {
        G3MLXRuntimeResourceProbe.mapAllocation(
            array, role: .kvCache, armLabel: arm).first?.storage.confirmedID
    }

    private func handle(_ id: String, position: Int64 = 0) -> ExecutionStateHandle {
        ExecutionStateHandle(
            id: ExecutionID(id),
            lineage: ExecutionLineage(root: ExecutionID(id)),
            position: ExecutionPosition(position),
            continuation: ExecutionContinuation(nextInput: "n", continuationID: "c"),
            lifecycle: .active)
    }

    // MARK: Requirement 1 — REAL storage identity feeds the carrier-isolation decision
    // Proposition (C): aliasing RELATION from the native runtime. Reuses the
    // published `mlxStorageIdentity`; adds no identity mechanism of its own.

    /// Two independently allocated real buffers carry distinct confirmed ids, so a
    /// retired carrier and a fresh carrier over DISJOINT storage evaluate `.isolated`.
    @Test func realIndependentBuffersEvaluateIsolated() {
        mlx()
        Device.withDefaultDevice(.cpu) {
            let retired = materialize(kvTensor(4))
            let adopting = materialize(kvTensor(4))
            let retiredID = confirmedID(retired, arm: "ES+IS")
            let adoptingID = confirmedID(adopting, arm: "IS-only")
            #expect(retiredID != nil && adoptingID != nil, "real materialized buffers must be confirmable")
            #expect(retiredID != adoptingID, "two allocations must not share a confirmed id")
            // The native runtime itself reports them distinct (axis-independent read).
            #expect(retired.mlxStorageIdentity.relationship(to: adopting.mlxStorageIdentity) == .distinct)
            #expect(CarrierStorageIsolationEvaluator.evaluate(
                retired: [retiredID!], adopting: [adoptingID!]) == .isolated)
        }
    }

    /// The SAME real allocation surfaced to two carriers collapses to one confirmed
    /// id, so the carrier-isolation decision is `.shared` — the old mutable state
    /// was never actually released. (String-id equality holds because it is literally
    /// one allocation, both identity axes equal.)
    @Test func realSharedBufferEvaluatesShared() {
        mlx()
        Device.withDefaultDevice(.cpu) {
            let shared = materialize(kvTensor(4))
            let id = confirmedID(shared, arm: "ES+IS")
            #expect(id != nil)
            let result = CarrierStorageIsolationEvaluator.evaluate(retired: [id!], adopting: [id!])
            #expect(result == .shared([id!]), "one allocation seen by both carriers must refuse")
        }
    }

    /// An unmaterialized fresh buffer exposes no confirmable id. A retired carrier
    /// that DID hold observable storage met by a fresh carrier that cannot confirm
    /// any is UNPROVEN, never "distinct" — the evaluator must report `.unobservable`.
    @Test func realIndeterminateBufferEvaluatesUnobservable() {
        mlx()
        Device.withDefaultDevice(.cpu) {
            let retired = materialize(kvTensor(4))
            let retiredID = confirmedID(retired, arm: "ES+IS")
            #expect(retiredID != nil)
            // Lazy op, never evaluated: the fresh buffer's identity is indeterminate.
            let lazyFresh = retired * 2
            #expect(confirmedID(lazyFresh, arm: "IS-only") == nil,
                    "an unmaterialized buffer must not yield a confirmed id")
            // The fresh carrier can confirm nothing → adopting set empty → unobservable.
            #expect(CarrierStorageIsolationEvaluator.evaluate(
                retired: [retiredID!], adopting: []) == .unobservable)
        }
    }

    // MARK: Requirement 2 — REAL KV session release
    // Proposition (A) ARC deallocation + Proposition (B) non-reuse. Explicitly NOT
    // a claim about GPU pages returning to the OS.

    /// After `G3CacheSessionSlot.release()`: the slot no longer HOLDS the session
    /// (weak probes over the real cache/gateway/observer deallocate — Proposition A),
    /// the session cannot be re-installed (Proposition B), and the retirement is
    /// idempotent — with REAL admitted KV in the cache, not an empty shell.
    @Test func releaseRetiresRealSessionAndFreesCarrierObjects() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let registrar = try #require(es.makeRegistrar())
            let slot = G3CacheSessionSlot()
            weak var weakCache: KVCacheSimple?
            weak var weakGateway: G3KVAllocationGateway?
            weak var weakObserver: G3KVCacheWriteObserver?
            do {
                let cache = KVCacheSimple()
                let session = try MLXPerArmKVCacheFactory.makeSession(
                    armID: RuntimeArmID("ES+IS"), registrar: registrar, caches: [cache])
                let boundary = try #require(session.boundary as? MLXKVCacheBoundary)
                #expect(slot.install(session))
                // Commit real KV so the carrier actually owns mutable storage before release.
                #expect(session.runStep(
                    forward: { attend(cache) },
                    candidateToken: { 7 }) == .committed(token: 7))
                #expect(cache.state[0].dim(2) == 1)

                weakCache = cache
                weakGateway = boundary.gateway
                weakObserver = cache.writeObserver as? G3KVCacheWriteObserver
                #expect(weakCache != nil && weakGateway != nil && weakObserver != nil)

                slot.release()

                // Proposition B — the retirement is real and one-way.
                #expect(session.abortReason == "cache_session_released",
                        "release must TERMINATE the session, not merely drop it")
                #expect(slot.installed == nil, "the slot must no longer hold the session")
                #expect(slot.isRetired)
                #expect(slot.install(session) == false, "a retired slot cannot re-install")
                slot.release()  // idempotent
                #expect(slot.installed == nil && slot.isRetired)
            }
            // Proposition A — the whole native object graph actually deallocates
            // (no cache -> observer -> gateway -> cache retain cycle). This is an ARC
            // fact; it does NOT measure MLX's allocator returning device pages to the OS.
            #expect(weakCache == nil, "release must free the real cache object")
            #expect(weakGateway == nil, "release must free the real gateway object")
            #expect(weakObserver == nil, "release must free the real write observer")
        }
    }

    /// The released session's write path is dead: a further `runStep` is refused
    /// BEFORE any forward runs, so the old observer can never admit a post-release
    /// (isolation-violating) write. Proposition B.
    @Test func terminatedSessionRefusesWritesAfterRelease() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let registrar = try #require(es.makeRegistrar())
            let cache = KVCacheSimple()
            let session = try MLXPerArmKVCacheFactory.makeSession(
                armID: RuntimeArmID("ES+IS"), registrar: registrar, caches: [cache])
            #expect(session.runStep(
                forward: { attend(cache) }, candidateToken: { 1 }) == .committed(token: 1))
            let stepCountAfterCommit = session.stepCount

            session.terminate(reason: "owner_released")
            var forwards = 0
            let outcome = session.runStep(
                forward: { forwards += 1; attend(cache) },
                candidateToken: { 99 })

            #expect(forwards == 0, "a terminated session must not run forward again")
            #expect(outcome == .refusedAfterTermination(reason: "owner_released"))
            #expect(session.committedTokens == [1], "no new token may commit post-release")
            #expect(session.stepCount == stepCountAfterCommit,
                    "a refused post-release step is not an entered step")
        }
    }

    // MARK: Requirement 3 — recovery on a FRESH carrier after releasing the REAL one

    /// Settle a representation, release the real MLX KV carrier AND retire the old
    /// backend carrier, then recover into a brand-new backend. The old carrier is
    /// unreadable; the recovered representation is byte-identical to the settled one
    /// and arrives ONLY via restoreRepresentation — no re-tokenization of a seed.
    @Test func settledRepresentationRecoversOnFreshBackendAfterRealCarrierRelease() async throws {
        mlx()
        let (es, _) = sealedPair()
        let registrar = try #require(es.makeRegistrar())

        // OLD carrier: a REAL MLX KV session with genuinely admitted state, built
        // and committed on the CPU device (no model).
        let oldSlot = G3CacheSessionSlot()
        let oldCache = KVCacheSimple()
        try Device.withDefaultDevice(.cpu) {
            let session = try MLXPerArmKVCacheFactory.makeSession(
                armID: RuntimeArmID("ES+IS"), registrar: registrar, caches: [oldCache])
            _ = oldSlot.install(session)
            _ = session.runStep(
                forward: { attend(oldCache) }, candidateToken: { 5 })
        }

        // The settled physical representation, held by the OLD backend carrier.
        let oldBackend = MLXExecutionStateBackend()
        let h = handle("E-REC", position: 3)
        oldBackend.bind(executionID: h.id, position: h.position, tokenPrefix: [9, 18, 27])
        let settled = try await oldBackend.captureRepresentation(for: h)

        // RELEASE: drop the real MLX carrier (ARC) AND retire the backend carrier.
        oldSlot.release()
        oldBackend.releaseCarrier(for: h.id)

        // The old carrier is genuinely unusable (Proposition B).
        #expect(oldSlot.isRetired)
        #expect(oldBackend.isCarrierRetired(for: h.id))
        #expect(throws: ExecutionStateBackendError.carrierReleased(h.id)) {
            try oldBackend.boundPrefix(for: h)
        }

        // A NEW carrier recovers the settled representation. Byte-identity of the
        // prefix proves the recovery reused the persisted result rather than
        // re-deriving it — there is no seed re-tokenization on this path.
        let freshBackend = MLXExecutionStateBackend()
        try await freshBackend.restoreRepresentation(settled)
        let recovered = try freshBackend.boundPrefix(for: h)
        #expect(recovered.prefix == [9, 18, 27], "recovered prefix must equal the settled one")
        #expect(recovered.position == h.position)
        if let payload = settled.payload as? MLXPrefixPayload {
            #expect(payload.tokenPrefix == recovered.prefix,
                    "the recovered representation must be the settled representation itself")
        } else {
            Issue.record("settled payload must be an MLXPrefixPayload")
        }
        // Recovery into the retired OLD carrier is still refused — the fresh ES had
        // to adopt a NEW backend, exactly the req1 hazard.
        await #expect(throws: ExecutionStateBackendError.carrierReleased(h.id)) {
            try await oldBackend.restoreRepresentation(settled)
        }
    }

    // MARK: Requirement 4 — fail-closed handoffs with REAL storage ids

    /// A retired carrier and an adopting carrier over the SAME real allocation share
    /// a confirmed id: the adopted-carrier gate refuses with `carriersShareStorage`,
    /// carrying the real overlapping id, so a new execution cannot start on aliased
    /// KV. (This gate is the one `recoverExecutionState` runs BEFORE returning a
    /// handle — refusing here is refusing before the Information Space advances.)
    @Test func sharedRealStorageRefusesAdoptedCarrier() {
        mlx()
        Device.withDefaultDevice(.cpu) {
            let buffer = materialize(kvTensor(4))
            let id = confirmedID(buffer, arm: "ES+IS")
            #expect(id != nil)
            let backend = MLXExecutionStateBackend()
            let stub = ProductionRuntimeModelExecutorStub(representationBackend: backend)
            stub.simulatedAdoptedStorageIDs = [id!]  // fresh carrier aliases the same buffer
            #expect(throws: CarrierLifecycleError.carriersShareStorage(
                executionID: "E-SHARE", sharedBufferIDs: [id!])) {
                try stub.verifyAdoptedCarrierIsolated(from: [id!], for: self.handle("E-SHARE"))
            }
        }
    }

    /// A retired carrier that held observable storage met by a fresh carrier that
    /// can confirm nothing (its buffer is unmaterialized) is UNPROVEN, so the gate
    /// refuses with `carrierStorageIsolationUnobservable` — missing evidence never
    /// becomes an "isolated" claim.
    @Test func unobservableAdoptedCarrierIsRefused() {
        mlx()
        Device.withDefaultDevice(.cpu) {
            let retired = materialize(kvTensor(4))
            let retiredID = confirmedID(retired, arm: "ES+IS")
            #expect(retiredID != nil)
            let backend = MLXExecutionStateBackend()
            let stub = ProductionRuntimeModelExecutorStub(representationBackend: backend)
            stub.simulatedAdoptedStorageIDs = []  // fresh carrier exposes no confirmable id
            #expect(throws: CarrierLifecycleError.carrierStorageIsolationUnobservable(
                executionID: "E-UNOBS")) {
                try stub.verifyAdoptedCarrierIsolated(from: [retiredID!], for: self.handle("E-UNOBS"))
            }
        }
    }

    /// An INCOMPLETE release is a refusal, not a partial success: if the old carrier
    /// was never retired (the release step was skipped or failed), verify-unusable
    /// throws `releaseIncomplete` and the caller can never proceed to a recovery that
    /// assumes the old state was released.
    @Test func incompleteReleaseIsRefusedBeforeRecovery() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let registrar = try #require(es.makeRegistrar())
            let slot = G3CacheSessionSlot()
            let cache = KVCacheSimple()
            let session = try MLXPerArmKVCacheFactory.makeSession(
                armID: RuntimeArmID("ES+IS"), registrar: registrar, caches: [cache])
            #expect(slot.install(session))

            let backend = MLXExecutionStateBackend()
            let stub = ProductionRuntimeModelExecutorStub(representationBackend: backend)
            let h = handle("E-PARTIAL")

            backend.bind(executionID: h.id, position: h.position, tokenPrefix: [1, 2, 3])
            // The carrier was NEVER released, so verify-unusable must refuse rather
            // than report a false release; the slot likewise is not retired.
            #expect(throws: CarrierLifecycleError.releaseIncomplete(reason: "carrier not retired")) {
                try stub.verifyCarrierUnusable(for: h)
            }
            #expect(slot.isRetired == false)
            // And a genuinely unusable carrier cannot be claimed: the old backend
            // still serves it, which is exactly the state the lifecycle forbids.
            #expect(noThrow(try backend.boundPrefix(for: h)))
        }
    }
}

private func noThrow<T>(_ body: @autoclosure () throws -> T) -> Bool {
    do { _ = try body(); return true } catch { return false }
}
