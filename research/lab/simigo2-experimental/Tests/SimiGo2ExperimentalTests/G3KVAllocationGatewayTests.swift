// SPDX-License-Identifier: MIT

// NATIVE KV ALLOCATION GATEWAY TESTS (MLX layer, real cache lifecycle)
//
// The prior suites proved the registration CHANNEL rejects a shared buffer and
// that a real MLXArray maps to a confirmable storage id. This file closes the
// specific gap the reviewer named: the G3 path must register every mutable KV
// buffer BEFORE its first read/write, and a refusal must BLOCK generation rather
// than surface after the forward already wrote.
//
// These drive the GENUINE `MLXLMCommon.KVCacheSimple.update(keys:values:)`
// lifecycle — the real allocation (`MLXArray.zeros`), expansion (`concatenated`)
// and replacement boundaries — with tiny CPU tensors. Two seams are exercised:
//   (a) `G3KVAllocationGateway.admit` as the register-before-write gate; and
//   (b) the NATIVE `KVCacheSimple.writeObserver` seam added in the forked
//       mlx-swift-lm (`feature/g3-kv-write-observer`), which fires INSIDE
//       `update` after the buffer exists but BEFORE its first write — the timing
//       the outer callback provably could not reach (test 6 pins that gap).
//
//   * first allocation → admitted, id enters the arm's live set;
//   * expansion produces a NEW buffer → admitted as a distinct id (grow is not
//     silently treated as the old buffer);
//   * a buffer aliasing the peer's live KV → REFUSED, and the simulated write
//     loop STOPS (proves refusal blocks subsequent generation, not post-hoc);
//   * an unmaterialized/unconfirmable buffer → REFUSED fail-closed;
//   * re-admitting the same buffer → REFUSED as shared within the arm;
//   * the KV buffer is only OBSERVABLE after `update` wrote it — pinned here as
//     concrete evidence of why the native write-boundary seam is required;
//   * the REAL observer registers a fresh buffer before its first write and lets
//     the step commit; a REFUSAL rolls the offset back, writes NOTHING, and
//     BLOCKS subsequent generation (`isolationAborted`);
//   * a legitimate multi-step reuse of an already-registered buffer is NOT
//     falsely refused, so ordinary generation is not broken.
//
// No model load, no G3 execution, no emitter trust registered; the empty registry
// still refuses. Normal inference is untouched.

import Foundation
import Testing
import MLX
import MLXLMCommon
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

/// A deterministic refusing ``KVCacheWriteObserver`` used to exercise the fork's
/// native write-boundary ROLLBACK in isolation from the gateway's policy: it proves
/// that a `.refuse` at the seam makes `update` skip the write, roll the offset back,
/// and latch `isolationAborted` — the mechanism by which a failed registration
/// blocks the generation step rather than leaking shared KV.
private final class AlwaysRefusingObserver: KVCacheWriteObserver {
    let reason: String
    private(set) var invocations = 0
    var lastFreshStorage: Bool?
    init(reason: String) { self.reason = reason }
    func kvCache(
        _ cache: KVCacheSimple, willWriteKeys keys: MLXArray, values: MLXArray,
        range: Range<Int>, freshStorage: Bool
    ) -> KVCacheWriteDecision {
        invocations += 1
        lastFreshStorage = freshStorage
        return .refuse(reason: reason)
    }
}

/// A strict cold-start probe that wraps a real gateway observer and captures, at the
/// native write boundary BEFORE any external materialization, whether the freshly
/// allocated / grown KV buffer's storage identity is observable. It then delegates to
/// the gateway, which materializes + confirms + admits -- all before `update` returns
/// and therefore before its slice-assign write. This is what answers the reviewer's
/// first acceptance point: the first-allocation identity is NOT assumed present (a
/// cold buffer reports `materialized == false`), and admission still happens before
/// the write -- the honest "materialize the G3 cache, then confirm and admit" outcome.
private final class ColdStartRecordingObserver: KVCacheWriteObserver {
    private let inner: KVCacheWriteObserver
    private let armLabel: String
    private(set) var invocations = 0
    private(set) var freshFlags: [Bool] = []
    private(set) var materializedBeforeEval: [Bool] = []
    private(set) var freshConfirmedKeyIDs: [String] = []
    init(_ inner: KVCacheWriteObserver, armLabel: String) {
        self.inner = inner
        self.armLabel = armLabel
    }
    func kvCache(
        _ cache: KVCacheSimple, willWriteKeys keys: MLXArray, values: MLXArray,
        range: Range<Int>, freshStorage: Bool
    ) -> KVCacheWriteDecision {
        invocations += 1
        freshFlags.append(freshStorage)
        // `mlxStorageIdentity` never evaluates; on a cold fresh/grown buffer this is
        // false, proving the identity is only made confirmable by the gateway's
        // materialize step, not by a pre-eval that would slip past the boundary.
        materializedBeforeEval.append(keys.mlxStorageIdentity.materialized)
        let decision = inner.kvCache(
            cache, willWriteKeys: keys, values: values, range: range, freshStorage: freshStorage)
        if freshStorage, case .allow = decision,
           let id = G3MLXRuntimeResourceProbe.mapAllocation(
               keys, role: .kvCache, armLabel: armLabel).first?.storage.confirmedID
        {
            freshConfirmedKeyIDs.append(id)
        }
        return decision
    }
}

struct G3KVAllocationGatewayTests {

    /// Same explicit metallib discovery as the storage-identity suite: a skipped
    /// isolation test is not evidence, so the CPU runtime is initialized eagerly.
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

    // MARK: Model-free sealed arms

    private func resource(
        _ role: G3ResourceRole, id: String, arm: String,
        access: G3ResourceAccess = .armExclusiveMutable
    ) -> OwnedResource {
        OwnedResource(role: role, ownerLabel: arm, access: access, storage: .confirmed(id))
    }

    private func makeArm(_ arm: String, writeRoot: String) -> G3ArmResourceOwner {
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
            writeRoot: writeRoot)
    }

    private func sealedPair() -> (G3ArmResourceOwner, G3ArmResourceOwner) {
        let es = makeArm("ES+IS", writeRoot: "/tmp/g3/es")
        let isArm = makeArm("IS-only", writeRoot: "/tmp/g3/is")
        es.seal(against: isArm); isArm.seal(against: es)
        return (es, isArm)
    }

    private func gateway(_ owner: G3ArmResourceOwner) -> G3KVAllocationGateway {
        guard let registrar = owner.makeRegistrar() else {
            preconditionFailure("a sealed owner must hand out a registrar")
        }
        return G3KVAllocationGateway(registrar: registrar, armLabel: owner.armID.rawValue)
    }

    /// A key tensor shaped like a KV-cache slice: [B, kvHeads, seq, headDim].
    private func kvTensor(_ seq: Int, headDim: Int = 8) -> MLXArray {
        let t = ones([1, 1, seq, headDim], dtype: .float32)
        t.eval()
        return t
    }

    /// Force MLX to realize a freshly allocated cache buffer so its storage
    /// identity becomes observable. This `eval` is exactly the point of the
    /// finding: the buffer that `update` already wrote only exposes a confirmable
    /// id once someone reads it back, i.e. AFTER the write.
    @discardableResult
    private func materialize(_ a: MLXArray) -> MLXArray { a.eval(); return a }

    // MARK: 1. First allocation is admitted and enters the live set

    @Test func firstCacheAllocationIsAdmitted() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let cache = KVCacheSimple()
            let (_, _) = cache.update(keys: kvTensor(4), values: kvTensor(4))
            // The cache's own state exposes the freshly allocated buffer (post-write
            // — see test 6 for why that matters); the gateway registers it as-is.
            let keysBuffer = materialize(cache.state[0])

            let gw = gateway(es)
            let admission = try gw.admit(keysBuffer, role: .kvCache)
            #expect(gw.admittedCount == 1)
            #expect(gw.observedAnyAllocation)
            let id = try #require(admission.registered.first?.storage.confirmedID)
            #expect(es.confirmedMutableIDs.contains(id),
                    "an admitted KV buffer must be in the arm's live mutable set")
            #expect(es.allocationViolations.isEmpty)
        }
    }

    // MARK: 2. Expansion reallocates — the new buffer is admitted as a distinct id

    @Test func expansionProducesANewBufferAdmittedDistinctly() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let cache = KVCacheSimple()
            cache.step = 4                         // force a reset/grow on the 2nd update
            let _ = cache.update(keys: kvTensor(4), values: kvTensor(4))
            let firstBuffer = materialize(cache.state[0])
            let firstID = G3MLXRuntimeResourceProbe
                .mapAllocation(firstBuffer, role: .kvCache, armLabel: "ES+IS")[0]
                .storage.confirmedID

            // Grow past capacity: concatenated([current, new]) allocates a NEW buffer.
            let _ = cache.update(keys: kvTensor(4), values: kvTensor(4))
            let grownBuffer = materialize(cache.state[0])
            let grownID = G3MLXRuntimeResourceProbe
                .mapAllocation(grownBuffer, role: .kvCache, armLabel: "ES+IS")[0]
                .storage.confirmedID

            // The expansion really replaced the storage — otherwise "admitting the
            // new buffer" would be a no-op and the test would prove nothing.
            #expect(firstID != grownID,
                    "a grown KV cache must present a new underlying buffer, got \(firstID)")

            let gw = gateway(es)
            _ = try gw.admit(firstBuffer, role: .kvCache)   // this arm's own first buffer
            _ = try gw.admit(grownBuffer, role: .kvCache)   // the grown replacement
            #expect(gw.admittedCount == 2,
                    "both of the arm's own distinct buffers must be admitted, not refused")
            #expect(es.allocationViolations.isEmpty)
        }
    }

    // MARK: 3. A buffer aliasing the peer is refused AND blocks further generation

    @Test func aliasOfPeerKVIsRefusedAndBlocksTheWriteLoop() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, isArm) = sealedPair()
            // IS-only materializes a real KV buffer and registers it first.
            let peerCache = KVCacheSimple()
            let _ = peerCache.update(keys: kvTensor(4), values: kvTensor(4))
            let peerBuffer = materialize(peerCache.state[0])
            _ = try gateway(isArm).admit(peerBuffer, role: .kvCache)

            // ES+IS now "generates": a loop that admits each buffer BEFORE writing it.
            // The second buffer is a VIEW of IS's live KV — the aliasing shape a leak
            // takes. Admission must throw, so the loop never writes it.
            let own = kvTensor(4)
            let aliased = peerBuffer.reshaped([1, 1, 2, 16])   // same storage, new wrapper
            aliased.eval()

            let gw = gateway(es)
            var writtenBuffers = 0
            var loopThrew = false
            do {
                for buffer in [own, aliased] {
                    _ = try gw.admit(buffer, role: .kvCache)  // register BEFORE first write
                    writtenBuffers += 1                        // only reached if admitted
                }
            } catch {
                loopThrew = true
            }
            #expect(loopThrew, "admitting a peer-aliased buffer must throw before its write")
            #expect(writtenBuffers == 1,
                    "a refused allocation must STOP generation; wrote \(writtenBuffers) of 2")
            #expect(es.allocationViolations.contains { $0.hasPrefix("shared_mutable_storage") },
                    "got \(es.allocationViolations)")
        }
    }

    // MARK: 4. An unconfirmable (unmaterialized) buffer is refused fail-closed

    @Test func unmaterializedKVBufferIsRefused() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let base = kvTensor(4)
            let lazy = base * 2                    // never evaluated: no observable storage
            let gw = gateway(es)
            #expect(throws: G3AllocationRegistrar.RegistrationError.violation(
                        reason: "indeterminate_storage_identity(kv_cache)")) {
                _ = try gw.admit(lazy, role: .kvCache)
            }
            #expect(gw.admittedCount == 0)
            #expect(gw.observedAnyAllocation, "an offered-but-refused buffer was still observed")
        }
    }

    // MARK: 5. Re-admitting the same buffer is refused as shared within the arm

    @Test func reAdmittingSameBufferIsRefusedAsShared() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let cache = KVCacheSimple()
            let _ = cache.update(keys: kvTensor(4), values: kvTensor(4))
            let buffer = materialize(cache.state[0])
            let gw = gateway(es)
            _ = try gw.admit(buffer, role: .kvCache)           // first admit OK
            #expect(throws: G3AllocationRegistrar.RegistrationError.self) {
                _ = try gw.admit(buffer, role: .kvCache)        // second: already owned
            }
            #expect(es.allocationViolations.contains { $0.hasPrefix("shared_mutable_storage") },
                    "got \(es.allocationViolations)")
        }
    }

    // MARK: 6. The pre-write seam is genuinely MISSING: the buffer is only visible after update

    /// Pins the reviewer's acceptance condition as an executable fact: with the
    /// current MLX cache API, the freshly allocated KV buffer cannot be observed
    /// until `update` has ALREADY written into it. `state` is empty before the
    /// first `update`, and non-empty (post-write) after — so an outer callback
    /// provably cannot register-before-write, which is why
    /// `G3KVAllocationExtensionPoint` marks the native hook as the required fix.
    @Test func cacheBufferIsOnlyObservableAfterUpdate_writesHaveAlreadyHappened() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let cache = KVCacheSimple()
            #expect(cache.state.isEmpty,
                    "before any update the cache exposes no buffer — nothing to register")
            let _ = cache.update(keys: kvTensor(4), values: kvTensor(4))
            // Reaching here means update() already slice-assigned into the buffer
            // (self.keys[..] = keys). The identity only becomes readable NOW, and
            // only once the write is materialized — an outer callback cannot see it
            // any earlier.
            #expect(cache.state.count == 2)
            let postWrite = G3MLXRuntimeResourceProbe
                .mapAllocation(materialize(cache.state[0]), role: .kvCache, armLabel: "ES+IS")[0].storage
            #expect(postWrite.isConfirmed,
                    "the buffer is observable only post-write, which is too late to block a leak")
            // The missing-hook documentation must stay accurate to the traced source.
            #expect(G3KVAllocationExtensionPoint.cacheSymbol
                    == "MLXLMCommon.KVCacheSimple.update(keys:values:)")
        }
    }

    // MARK: 7. The REAL native seam: a gateway observer registers KV before its first write

    /// Installs the fork's `KVCacheSimple.writeObserver` (via
    /// `gateway.makeWriteObserver()`) on a genuine cache and drives `update`. The
    /// observer fires INSIDE `update` after the zeros buffer is allocated but before
    /// the slice-assign, so the fresh KV storage enters the arm's ownership set
    /// BEFORE MLX touches it — the acceptance condition. A clean allocation commits.
    @Test func realGatewayObserverRegistersKVBeforeWriteAndLetsTheStepCommit() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let cache = KVCacheSimple()
            let gw = gateway(es)
            cache.writeObserver = gw.makeWriteObserver()   // native seam installed
            let (outK, _) = cache.update(keys: kvTensor(4), values: kvTensor(4))
            outK.eval()
            #expect(cache.isolationAborted == false, "a clean fresh allocation must not abort")
            #expect(gw.observedAnyAllocation)
            #expect(gw.admittedCount >= 1,
                    "the fresh KV keys+values must be registered before their first write")
            #expect(outK.dim(2) == 4, "the admitted step commits its 4 tokens")
            // Ownership was proven pre-use: the registered ids are the arm's live set.
            #expect(!es.confirmedMutableIDs.isEmpty,
                    "the admitted KV buffer id must be in the arm's live mutable set")
        }
    }

    // MARK: 8. A REFUSAL at the seam skips the write, rolls back, and BLOCKS generation

    /// The reviewer's hardest requirement: "does a refused registration stop
    /// subsequent generation?" A refusing observer makes `update` roll the offset
    /// back and write NOTHING; a generation loop that checks `isolationAborted`
    /// runs exactly one step and stops. This is the block-at-the-boundary guarantee,
    /// not a post-forward rejection.
    @Test func nativeRefusalSkipsTheWriteAndBlocksSubsequentGeneration() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let cache = KVCacheSimple()
            let observer = AlwaysRefusingObserver(reason: "test_refuse")
            cache.writeObserver = observer
            var stepsRun = 0
            for _ in 0..<3 {
                let _ = cache.update(keys: kvTensor(4), values: kvTensor(4))
                stepsRun += 1
                if cache.isolationAborted { break }   // refuse blocks further generation
            }
            #expect(observer.invocations == 1,
                    "the seam fires once at the first write boundary, then the loop stops")
            #expect(observer.lastFreshStorage == true,
                    "the first update is a fresh allocation offered to the observer")
            #expect(cache.isolationAborted, "a refused registration must latch the abort")
            #expect(cache.isolationAbortReason == "test_refuse")
            #expect(stepsRun == 1, "a refused step must BLOCK subsequent generation, ran \(stepsRun)/3")
            // Nothing committed: offset rolled back to 0, so the cache exposes no tokens.
            #expect(cache.state.isEmpty || cache.state[0].dim(2) == 0,
                    "a refusal must not advance the cache window (the shared buffer stays unwritten)")
        }
    }

    // MARK: 9. A legitimate multi-step reuse of a registered buffer is NOT falsely refused

    /// Guards against a gate that would break ordinary generation by treating the
    /// second step's reuse of an already-owned buffer as "shared". With a gateway
    /// observer and a capacity that keeps two 4-token steps in one buffer, the first
    /// step registers (fresh) and the second is allowed as reuse WITHOUT re-admitting.
    @Test func realGatewayObserverAllowsReuseWithoutFalseRefusal() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let cache = KVCacheSimple()
            cache.step = 8   // capacity 8: a 4 + 4 two-step stays within one buffer (reuse)
            let gw = gateway(es)
            cache.writeObserver = gw.makeWriteObserver()
            let _ = cache.update(keys: kvTensor(4), values: kvTensor(4))   // fresh -> admit
            let admittedAfterFirst = gw.admittedCount
            #expect(cache.isolationAborted == false)
            let _ = cache.update(keys: kvTensor(4), values: kvTensor(4))   // reuse -> allow
            #expect(cache.isolationAborted == false,
                    "a legitimate second step must NOT be refused as shared")
            #expect(gw.admittedCount == admittedAfterFirst,
                    "reuse confirms ownership without re-registering the same buffer")
        }
    }

    // MARK: 10. Cold-start: first-allocation identity is indeterminate before the gateway materializes it, and admission still precedes the write

    /// Strict cold-start probe the reviewer required: a brand new `KVCacheSimple`,
    /// the gateway observer installed BEFORE the first `update`, and NEITHER the
    /// cache buffer NOR the step inputs pre-materialized. It proves two things at the
    /// native boundary: (1) a freshly `zeros`'d buffer is `materialized == false` when
    /// first observed (the test is not slipping past cold start via a pre-eval), and
    /// (2) the gateway materializes + confirms + admits inside the observer, which runs
    /// strictly before `update`'s slice-assign, so the write still happens AFTER the
    /// first-allocation registration.
    @Test func coldStartFirstAllocationConfirmsIdentityAndAdmitsBeforeWrite() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let gw = gateway(es)
            let spy = ColdStartRecordingObserver(gw.makeWriteObserver(), armLabel: "ES+IS")
            let cache = KVCacheSimple()          // brand new, never updated
            cache.writeObserver = spy            // installed before the first update
            // cold step inputs: NOT evaluated
            let k = ones([1, 1, 4, 8], dtype: .float32)
            let v = ones([1, 1, 4, 8], dtype: .float32)
            let _ = cache.update(keys: k, values: v)

            #expect(spy.invocations == 1)
            #expect(spy.freshFlags == [true], "the first update is a fresh allocation")
            #expect(spy.materializedBeforeEval == [false],
                    "on a cold fresh allocation the buffer identity is indeterminate before the gateway materializes it")
            #expect(spy.freshConfirmedKeyIDs.count == 1,
                    "after the gateway materialized + confirmed it, the first-allocation identity is confirmable")
            #expect(gw.admittedCount >= 1, "the fresh buffer is admitted inside the observer (before the write)")
            #expect(cache.isolationAborted == false)
            #expect(!es.confirmedMutableIDs.isEmpty, "admitted-before-write -> the KV id is in the arm's live set")
            // The write DID happen only after admission: the committed window is nonzero.
            #expect(cache.state[0].dim(2) == 4)
        }
    }

    // MARK: 11. Cold-start growth: crossing the capacity boundary registers the NEW buffer before its write

    /// Reproduces the growth the reviewer described (the step that first exceeds
    /// capacity -> `concatenated` allocates a new buffer) at the real 256/257 boundary
    /// with single-token steps, driven entirely through the gateway observer. It shows
    /// the grown buffer is offered with `freshStorage == true` and admitted as a NEW
    /// distinct id before its write, while the intervening in-capacity steps are reuse
    /// (allowed, not re-admitted) -- so a genuine 257-token generation never false-refuses.
    @Test func coldStartGrowthAtCapacityBoundaryRegistersNewBufferBeforeWrite() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let gw = gateway(es)
            let spy = ColdStartRecordingObserver(gw.makeWriteObserver(), armLabel: "ES+IS")
            let cache = KVCacheSimple()
            cache.step = 256                     // capacity 256 -> the 257th token grows it
            cache.writeObserver = spy
            for _ in 0..<257 {                   // 257 single-token cold updates
                let k = ones([1, 1, 1, 8], dtype: .float32)
                let v = ones([1, 1, 1, 8], dtype: .float32)
                let _ = cache.update(keys: k, values: v)
                #expect(cache.isolationAborted == false, "a legitimate generation must not be refused")
            }
            #expect(spy.invocations == 257)
            // fresh only at step 1 (first alloc) and step 257 (capacity crossing / grow).
            #expect(spy.freshFlags.first == true)
            #expect(spy.freshFlags[1] == false, "step 2 reuses the first buffer")
            #expect(spy.freshFlags[256] == true, "step 257 crosses capacity -> concatenated grow -> new buffer")
            #expect(spy.freshFlags.filter { $0 }.count == 2, "exactly two fresh physical buffers across the run")
            #expect(spy.materializedBeforeEval[0] == false, "cold first allocation identity starts indeterminate")
            // keys+values admitted once each for the two fresh buffers (reuse never re-admits).
            #expect(gw.admittedCount == 4)
            // the grown buffer is a genuinely NEW physical storage, distinct from the first.
            #expect(spy.freshConfirmedKeyIDs.count == 2)
            #expect(spy.freshConfirmedKeyIDs[0] != spy.freshConfirmedKeyIDs[1],
                    "the grown KV cache must present a new underlying buffer, got \(spy.freshConfirmedKeyIDs)")
            #expect(cache.state[0].dim(2) == 257)
        }
    }

    // MARK: 12. Consumer boundary: an admitted step commits and never trips the abort (real attention route)

    /// Drives the REAL `attentionWithCacheUpdate` -- the single central function every
    /// mlx-swift-lm model uses, whose plain branch is exactly `cache.update` followed by
    /// `scaledDotProductAttention` -- so the assertion is about the production consumer,
    /// not a re-implementation. A gateway-registered (admitted) step must commit and must
    /// NOT fire the isolation-abort handler.
    @Test func admittedStepCommitsThroughRealAttentionAndNeverTripsAbort() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let gw = gateway(es)
            let cache = KVCacheSimple()
            cache.writeObserver = gw.makeWriteObserver()
            var aborts = 0
            cache.onIsolationAbort = { _ in aborts += 1 }
            cache.beginStep()
            let out = attentionWithCacheUpdate(
                queries: ones([1, 1, 1, 8], dtype: .float32),
                keys: ones([1, 1, 1, 8], dtype: .float32),
                values: ones([1, 1, 1, 8], dtype: .float32),
                cache: cache, scale: 0.25)
            out.eval()
            #expect(aborts == 0, "an admitted step never reaches the abort boundary")
            #expect(cache.isolationAborted == false)
            #expect(gw.admittedCount >= 1)
            #expect(cache.state[0].dim(2) == 1, "the admitted token IS in the cache the consumer reads")
        }
    }

    // MARK: 13. Consumer boundary: a refused step aborts at update->attend and is NOT committed

    /// The reviewer's hardest requirement for Gap 2, proven on the REAL attention route:
    /// a step whose KV registration is refused must (a) fire the native abort exactly at
    /// the `update`->attend boundary, (b) never hand the refused token to the cache the
    /// consumer reads, and (c) not commit the current model step -- not merely block the
    /// next one. Step 1 commits (gateway); step 2 uses a refusing observer to stand in
    /// for a refused registration (the propagation path is independent of the reason).
    @Test func refusedStepIsBlockedAtConsumerAndNotCommitted() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let gw = gateway(es)
            let cache = KVCacheSimple()
            cache.writeObserver = gw.makeWriteObserver()
            var aborts = 0
            var abortReason: String?
            cache.onIsolationAbort = { r in aborts += 1; abortReason = r }
            var committed = 0

            // Step 1: legitimate admitted write commits through the real attention route.
            cache.beginStep()
            let out1 = attentionWithCacheUpdate(
                queries: ones([1, 1, 1, 8], dtype: .float32),
                keys: ones([1, 1, 1, 8], dtype: .float32),
                values: ones([1, 1, 1, 8], dtype: .float32),
                cache: cache, scale: 0.25)
            if !cache.isolationAborted { out1.eval(); committed += 1 }

            // Step 2: a refusing observer stands in for a refused registration.
            cache.writeObserver = AlwaysRefusingObserver(reason: "consumer_boundary_probe")
            cache.beginStep()
            let out2 = attentionWithCacheUpdate(
                queries: ones([1, 1, 1, 8], dtype: .float32),
                keys: ones([1, 1, 1, 8], dtype: .float32),
                values: ones([1, 1, 1, 8], dtype: .float32),
                cache: cache, scale: 0.25)
            if !cache.isolationAborted { out2.eval(); committed += 1 }

            #expect(committed == 1, "only the admitted step commits; the refused step is discarded (committed \(committed))")
            #expect(aborts == 1, "the refused step fires the native update->attend abort exactly once")
            #expect(abortReason == "consumer_boundary_probe")
            // The refused token never entered the cache the consumer reads (offset stayed 1).
            #expect(cache.state.isEmpty || cache.state[0].dim(2) == 1,
                    "a refused write must not advance the cache the consumer attends over")
        }
    }

    // MARK: 14. A real per-arm session commits, then terminates on a refused step

    /// Drives the PRODUCTION per-arm wiring model-free: `MLXPerArmKVCacheFactory`
    /// builds a real `KVCacheSimple` with its gateway observer installed before the
    /// first use, and `G3ArmCacheSession` commits step 1 through the REAL
    /// `attentionWithCacheUpdate`. Step 2's write is refused, so the candidate token
    /// is discarded, the arm terminates, and step 3 never runs a forward.
    @Test func perArmCacheSessionRejectsSharedKVThenTerminatesThroughRealAttention() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let registrar = try #require(es.makeRegistrar())
            let session = try MLXPerArmKVCacheFactory.makeSession(
                armID: RuntimeArmID("ES+IS"), registrar: registrar, step: 8)
            let boundary = try #require(session.boundary as? MLXKVCacheBoundary)
            let cache = try #require(boundary.caches.first as? KVCacheSimple)

            // Step 1: genuine allocation, gated by the observer, committed.
            let step1 = session.runStep(
                forward: {
                    let out = attentionWithCacheUpdate(
                        queries: kvTensor(1), keys: kvTensor(1), values: kvTensor(1),
                        cache: cache, scale: 0.25)
                    out.eval()
                },
                candidateToken: { 7 })
            #expect(step1 == .committed(token: 7))
            #expect(session.committedTokens == [7])
            #expect(boundary.gateway.admittedCount >= 1,
                    "the first allocation is registered before its first write")

            // Step 2: the write boundary refuses a REUSE of storage this arm never
            // registered (the production policy — the installed observer can no
            // longer be swapped for a refusing one). The token is discarded and
            // the arm terminates.
            let foreignK = kvTensor(4)
            let foreignV = kvTensor(4)
            foreignK.eval(); foreignV.eval()
            cache.state = [foreignK, foreignV]
            _ = cache.trim(1)
            let refusal = "kv_write_to_unregistered_storage(kv_cache)"
            let step2 = session.runStep(
                forward: {
                    let out = attentionWithCacheUpdate(
                        queries: kvTensor(1), keys: kvTensor(1), values: kvTensor(1),
                        cache: cache, scale: 0.25)
                    out.eval()
                },
                candidateToken: { 99 })
            #expect(step2 == .aborted(reason: refusal))
            #expect(session.committedTokens == [7],
                    "a refused step's token must never be committed")
            #expect(session.isTerminated)

            // Step 3: a terminated arm refuses without running a forward.
            var furtherForwards = 0
            let step3 = session.runStep(
                forward: { furtherForwards += 1 },
                candidateToken: { 1 })
            #expect(step3 == .refusedAfterTermination(reason: refusal))
            #expect(furtherForwards == 0, "no generation may follow a refusal")
            // The refused write did not advance: the cache kept only the foreign
            // window it was seated on.
            #expect(cache.state[0].dim(2) == 3)
        }
    }

    // MARK: 15. The write-boundary eval() is bounded and does not change lifecycle

    /// The reviewer's caution: the observer calls `eval()` to confirm the buffer's
    /// identity, so it must be shown to be BOUNDED (not an uncontrolled graph
    /// realization) and lifecycle-neutral. The eval targets the cache's own
    /// `self.keys` / `self.values` buffers; an unrelated lazy graph must stay
    /// unrealized, and the committed window must be identical to an observer-free
    /// update. This does NOT claim zero overhead — see `G3PerArmKVCache.swift`: a
    /// fresh/grow step gains one bounded synchronous realization.
    @Test func gatewayObserverEvaluationIsBoundedToTheKVBuffer() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let gw = gateway(es)
            // Unrelated lazy computation: nothing may realize this but us.
            let unrelated = kvTensor(4) * 2
            #expect(unrelated.mlxStorageIdentity.materialized == false,
                    "precondition: the unrelated graph starts unrealized")

            let cache = KVCacheSimple()
            cache.writeObserver = gw.makeWriteObserver()
            let (outK, _) = cache.update(keys: kvTensor(4), values: kvTensor(4))
            outK.eval()

            #expect(unrelated.mlxStorageIdentity.materialized == false,
                    "the write-boundary eval must not realize unrelated computation")
            #expect(cache.isolationAborted == false)
            #expect(gw.admittedCount >= 1)
            // Lifecycle is unchanged: same committed window as an observer-free run.
            #expect(cache.state[0].dim(2) == 4,
                    "installing an observer must not change the cache's committed window")
        }
    }

    // MARK: 16. One arm, one cache per LAYER, one shared gate

    /// A real transformer indexes `cache[l]` per layer, so a per-arm session over a
    /// SINGLE cache is not a valid production shape. This drives two real layers
    /// under ONE arm/gateway: both layers' fresh buffers are admitted before their
    /// first write, and a refusal in ANY layer aborts the whole step and terminates
    /// the arm — the peer layer's already-written step is partial and is never used
    /// again.
    @Test func perArmBoundaryGatesEveryLayerAndOneLayerRefusalTerminatesTheArm() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let registrar = try #require(es.makeRegistrar())
            let layer0 = KVCacheSimple(); layer0.step = 8
            let layer1 = KVCacheSimple(); layer1.step = 8
            let session = try MLXPerArmKVCacheFactory.makeSession(
                armID: RuntimeArmID("ES+IS"), registrar: registrar,
                caches: [layer0, layer1])
            let boundary = try #require(session.boundary as? MLXKVCacheBoundary)
            #expect(boundary.observedCacheCount == 2, "every layer is gated")
            #expect(boundary.caches.count == 2)

            // Step 1: BOTH layers allocate, are admitted, and commit.
            let step1 = session.runStep(
                forward: {
                    let out0 = attentionWithCacheUpdate(
                        queries: kvTensor(1), keys: kvTensor(1), values: kvTensor(1),
                        cache: layer0, scale: 0.25)
                    let out1 = attentionWithCacheUpdate(
                        queries: kvTensor(1), keys: kvTensor(1), values: kvTensor(1),
                        cache: layer1, scale: 0.25)
                    out0.eval(); out1.eval()
                },
                candidateToken: { 5 })
            #expect(step1 == .committed(token: 5))
            #expect(layer0.state[0].dim(2) == 1)
            #expect(layer1.state[0].dim(2) == 1)
            #expect(boundary.gateway.admittedCount >= 2,
                    "each layer's fresh buffer is registered before its first write")

            // Step 2: layer 1 refuses. Its window is REPLACED by foreign storage
            // this arm never registered, so its next write is a REUSE the gateway
            // must refuse — the production policy, not a substituted observer.
            // Layer 0 has already written this step, but the token is discarded
            // and the arm terminates, so that partial KV is never consumed again.
            let foreignK = kvTensor(4)
            let foreignV = kvTensor(4)
            foreignK.eval(); foreignV.eval()
            layer1.state = [foreignK, foreignV]
            _ = layer1.trim(1)
            let refusal = "kv_write_to_unregistered_storage(kv_cache)"
            let step2 = session.runStep(
                forward: {
                    let out0 = attentionWithCacheUpdate(
                        queries: kvTensor(1), keys: kvTensor(1), values: kvTensor(1),
                        cache: layer0, scale: 0.25)
                    let out1 = attentionWithCacheUpdate(
                        queries: kvTensor(1), keys: kvTensor(1), values: kvTensor(1),
                        cache: layer1, scale: 0.25)
                    out0.eval(); out1.eval()
                },
                candidateToken: { 6 })
            #expect(step2 == .aborted(reason: refusal))
            #expect(session.committedTokens == [5], "the refused step's token is never committed")
            #expect(session.isTerminated)
            #expect(layer0.state[0].dim(2) == 2, "layer 0's partial step exists")
            #expect(layer1.state[0].dim(2) == 3,
                    "the refused layer kept only the foreign window it was seated on")

            // Step 3: terminated — no forward on ANY layer.
            var furtherForwards = 0
            let step3 = session.runStep(
                forward: { furtherForwards += 1 }, candidateToken: { 7 })
            #expect(step3 == .refusedAfterTermination(reason: refusal))
            #expect(furtherForwards == 0)
        }
    }

    // MARK: 17. A cache type with no write seam is refused before any forward

    @Test func unobservableCacheTypeIsRefusedBeforeAnyForward() throws {
        mlx()
        let (es, _) = sealedPair()
        let registrar = try #require(es.makeRegistrar())
        // RotatingKVCache has no write boundary in the fork, so a G3 arm cannot
        // gate it. Refused fail-closed instead of running ungated generation.
        #expect(throws: G3PerArmCacheError.self) {
            _ = try MLXPerArmKVCacheFactory.makeSession(
                armID: RuntimeArmID("ES+IS"), registrar: registrar,
                caches: [KVCacheSimple(), RotatingKVCache(maxSize: 8)])
        }
        // ONE cache instance reused for two layer slots is refused too: it would
        // mix two layers' KV inside the arm before the cross-arm check runs.
        let sharedLayer = KVCacheSimple()
        #expect(throws: G3PerArmCacheError.self) {
            _ = try MLXPerArmKVCacheFactory.makeSession(
                armID: RuntimeArmID("ES+IS"), registrar: registrar,
                caches: [sharedLayer, sharedLayer])
        }
    }

    // MARK: 18. The write-boundary eval does not realize the step's projection

    /// The reviewer's sharpest cost question: does `eval()` inside the observer
    /// force the model's K/V projection (or the forward graph)? The observer is
    /// handed the cache's OWN buffer, built from a zeros leaf plus the already
    /// realized cache — never the incoming projection. This test keeps a lazy
    /// projection unrealized across `update` and asserts it stays that way until
    /// someone outside evaluates the output.
    @Test func incomingProjectionIsNotRealizedByWriteBoundaryEval() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let gw = gateway(es)
            let cache = KVCacheSimple()
            cache.writeObserver = gw.makeWriteObserver()

            let projectionK = kvTensor(1) * 2      // lazy: nothing realized this
            let projectionV = kvTensor(1) * 3
            #expect(projectionK.mlxStorageIdentity.materialized == false,
                    "precondition: the projection starts unrealized")

            let (outK, outV) = cache.update(keys: projectionK, values: projectionV)

            #expect(projectionK.mlxStorageIdentity.materialized == false,
                    "the write-boundary eval must not realize the step's K projection")
            #expect(projectionV.mlxStorageIdentity.materialized == false,
                    "the write-boundary eval must not realize the step's V projection")
            outK.eval(); outV.eval()
            #expect(cache.isolationAborted == false)
            #expect(cache.state[0].dim(2) == 1)
        }
    }

    // MARK: 19. Post-forward re-report of already-admitted KV is idempotent

    /// The post-forward registration hook may report the same KV window the write
    /// observer already admitted. That is the same storage, not an alias: it must
    /// not be refused as "shared within the arm" (which would fail a legitimate
    /// first run closed).
    @Test func postForwardReReportOfWriteAdmittedKVIsNotAFalseRefusal() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let gw = gateway(es)
            let cache = KVCacheSimple()
            cache.writeObserver = gw.makeWriteObserver()
            let (outK, _) = cache.update(keys: kvTensor(4), values: kvTensor(4))
            outK.eval()
            let afterWriteBoundary = gw.admittedCount
            #expect(afterWriteBoundary >= 1)

            // The post-forward hook reports materialized views of the same window.
            let state = cache.state
            state[0].eval(); state[1].eval()
            _ = try gw.admit(state[0], role: .kvCache)
            _ = try gw.admit(state[1], role: .kvCache)

            #expect(gw.admittedCount == afterWriteBoundary,
                    "a re-report is idempotent, not a new admission")
            #expect(es.allocationViolations.isEmpty,
                    "no false shared-within-arm violation: \(es.allocationViolations)")
        }
    }

    // MARK: 20. A KVCacheSimple SUBCLASS that bypasses the seam is refused

    /// `ChunkedKVCache` inherits `KVCacheSimple` but OVERRIDES `update`, so the
    /// native write observer is never called. This test first proves the bypass
    /// directly (a refusing observer is installed and the write still happens),
    /// then proves the boundary refuses such a cache fail-closed instead of
    /// reporting an arm as gated while its KV was written unobserved.
    @Test func subclassWhoseUpdateBypassesTheSeamIsRefusedNotSilentlyUngated() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            // (a) The bypass is real: a refusing observer cannot stop this write.
            let chunked = ChunkedKVCache(chunkSize: 64)
            let refusing = AlwaysRefusingObserver(reason: "must_not_be_consulted")
            chunked.writeObserver = refusing
            let (outK, _) = chunked.update(keys: kvTensor(2), values: kvTensor(2))
            outK.eval()
            #expect(refusing.invocations == 0,
                    "ChunkedKVCache.update must not consult the write observer")
            #expect(chunked.isolationAborted == false)
            #expect(chunked.state[0].dim(2) == 2, "the KV was written ungated")

            // (b) So the arm builder refuses it BEFORE any forward, and leaves no
            // half-installed observer behind.
            let (es, _) = sealedPair()
            let registrar = try #require(es.makeRegistrar())
            let fresh = ChunkedKVCache(chunkSize: 64)
            let refused: G3PerArmCacheError? = {
                do {
                    _ = try MLXPerArmKVCacheFactory.makeSession(
                        armID: RuntimeArmID("ES+IS"), registrar: registrar, caches: [fresh])
                    return nil
                } catch let error as G3PerArmCacheError {
                    return error
                } catch {
                    return nil
                }
            }()
            switch refused {
            case .unobservableCache(let reason):
                #expect(reason.contains("ChunkedKVCache"), Comment(rawValue: reason))
                #expect(reason.contains("bypasses"), Comment(rawValue: reason))
            default:
                Issue.record("expected unobservableCache, got \(String(describing: refused))")
            }
            #expect(fresh.writeObserver == nil, "a refused arm must not leave an observer installed")
        }
    }

    // MARK: 21. One native cache cannot be gated by two arms

    /// The pair guard compares BOUNDARY objects, so it cannot see two boundaries
    /// that wrap the SAME native `KVCacheSimple`. Without an explicit check the
    /// second arm's install would overwrite the first arm's write observer, and
    /// the first arm's writes would then be graded by the second arm's registrar.
    /// This pins the native-object refusal and proves the first gate survives.
    @Test func nativeCacheAlreadyGatedByAnotherArmIsRefusedAndKeepsItsFirstGate() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, isArm) = sealedPair()
            let esRegistrar = try #require(es.makeRegistrar())
            let isRegistrar = try #require(isArm.makeRegistrar())
            let nativeCache = KVCacheSimple()

            let esSession = try MLXPerArmKVCacheFactory.makeSession(
                armID: RuntimeArmID("ES+IS"), registrar: esRegistrar, caches: [nativeCache])
            let esBoundary = try #require(esSession.boundary as? MLXKVCacheBoundary)
            let installed = try #require(nativeCache.writeObserver)

            let refused: G3PerArmCacheError? = {
                do {
                    _ = try MLXPerArmKVCacheFactory.makeSession(
                        armID: RuntimeArmID("IS-only"), registrar: isRegistrar, caches: [nativeCache])
                    return nil
                } catch let error as G3PerArmCacheError {
                    return error
                } catch {
                    return nil
                }
            }()
            switch refused {
            case .armsShareMutableCache(let reason):
                #expect(reason.contains("already carries a write observer"), Comment(rawValue: reason))
            default:
                Issue.record("expected armsShareMutableCache, got \(String(describing: refused))")
            }

            // The FIRST arm's gate is still the installed one; the second install
            // neither replaced it nor registered anything.
            #expect(nativeCache.writeObserver === installed)
            #expect(esBoundary.observedCacheCount == 1)
            let before = esBoundary.gateway.admittedCount
            let (outK, _) = nativeCache.update(keys: kvTensor(1), values: kvTensor(1))
            outK.eval()
            #expect(esBoundary.gateway.admittedCount > before,
                    "a write through the shared cache is still graded by the FIRST arm")
            #expect(isArm.allocationViolations.isEmpty)
        }
    }
}
