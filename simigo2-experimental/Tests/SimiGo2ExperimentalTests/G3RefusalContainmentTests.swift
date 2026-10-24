// SPDX-License-Identifier: MIT

// REFUSAL CONTAINMENT — fault injection at the layer and step level (stage A/B)
//
// Stage A traced the refusal from `KVCacheSimple.update` to the arm's termination.
// These tests pin the three invariants that trace depends on, with REAL native
// caches and the REAL `attentionWithCacheUpdate` consumer, no model loaded:
//
//   1. A refusal in one layer must not be followed by later layers of the SAME
//      forward writing their KV. The gateway keeps an arm-level termination latch,
//      so every later write is refused before it touches a buffer. The sampler is
//      never called and no token is committed.
//   2. Termination is irreversible. A stray `beginStep()` (boundary or native)
//      cannot make `isolationAborted` false again, the gateway latch cannot be
//      cleared, and the gated caches cannot be wrapped in a second session.
//   3. A step that was entered but threw (forward or sampling) also terminates the
//      arm: it can never be retried against a cache it may have advanced.
//
// Honest limit: MLX's cache API returns a tuple, not a throwing result, so the
// remaining forward compute is NOT cancelled — it is inert (writes no KV, logits
// never read). These tests do not claim a model-level G3 run; the trust registry
// stays empty and no model is loaded.
//
// STAGE C (lifecycle) adds the paths around generation:
//   * a boundary already dead at step entry (cache resolution / observer install
//     failure) is refused BEFORE forward, and the executor terminates the session;
//   * `release()` terminates the session, is idempotent, retires the slot and
//     deallocates the cache/gateway/observer graph (weak probes, real admitted KV);
//   * one arm's release never terminates, clears or re-arms the peer's cache;
//   * a concurrent step, a cancelled step and a release racing a step all discard
//     the candidate token instead of committing it.

import Foundation
import Dispatch
import Testing
import MLX
import MLXLMCommon
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

/// Minimal boundary for the contract-level throw tests (no native cache).
private final class StubBoundary: G3ArmCacheBoundary {
    private(set) var aborted = false
    private(set) var reason: String?

    /// Mirrors the MLX boundary: a live step resets, a terminated one does not.
    func beginStep() {
        guard !aborted else { return }
        reason = nil
    }

    /// Model a boundary that failed during cache resolution / observer install.
    func forceAbort(reason: String) {
        aborted = true
        self.reason = reason
    }

    var isolationAborted: Bool { aborted }
    var isolationAbortReason: String? { reason }
}

private enum StubError: Error, Equatable {
    case forward
    case sample
}

/// Cross-thread result holder for the concurrent-step test.
private final class StepOutcomeBox: @unchecked Sendable {
    var outcome: G3ArmStepOutcome?
}

struct G3RefusalContainmentTests {

    /// Same explicit metallib discovery as the other native suites: a skipped
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
            for case let url as URL in e where url.path.hasSuffix(relative) {
                GPU.metallib = url; break
            }
        }
    }()

    private func mlx() { _ = Self.ensureRuntime }

    // MARK: Model-free sealed arms and tensors

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
        let peer = makeArm("IS-only", writeRoot: "/tmp/g3/is")
        es.seal(against: peer); peer.seal(against: es)
        return (es, peer)
    }

    /// A [B, kvHeads, seq, headDim] KV slice.
    private func kvTensor(_ seq: Int, headDim: Int = 8) -> MLXArray {
        let t = ones([1, 1, seq, headDim], dtype: .float32)
        t.eval()
        return t
    }

    /// One decode step over EVERY layer, through the real attention consumer.
    private func attendAllLayers(_ layers: [KVCacheSimple]) {
        for layer in layers {
            let attended = attentionWithCacheUpdate(
                queries: kvTensor(1), keys: kvTensor(1), values: kvTensor(1),
                cache: layer, scale: 0.25)
            attended.eval()
        }
    }

    /// Seat `cache` on the PEER's live KV with spare capacity, so its next write
    /// takes `update`'s REUSE path into storage this arm never registered.
    private func seatOnPeerStorage(
        _ cache: KVCacheSimple, peerKeys: MLXArray, peerValues: MLXArray
    ) {
        cache.state = [peerKeys, peerValues]
        _ = cache.trim(1)  // offset 3 of capacity 4: the next token is a reuse write
    }

    // MARK: B1. A first-layer refusal stops every later layer from writing

    @Test func firstLayerRefusalStopsEveryLaterLayerWrite() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, peer) = sealedPair()
            let esRegistrar = try #require(es.makeRegistrar())
            let peerRegistrar = try #require(peer.makeRegistrar())
            let peerGateway = G3KVAllocationGateway(
                registrar: peerRegistrar, armLabel: peer.armID.rawValue)
            let peerKeys = kvTensor(4)
            let peerValues = kvTensor(4)
            _ = try peerGateway.admit(peerKeys, role: .kvCache)
            _ = try peerGateway.admit(peerValues, role: .kvCache)

            let session = try MLXPerArmKVCacheFactory.makeSession(
                armID: RuntimeArmID("ES+IS"), registrar: esRegistrar,
                caches: (0..<3).map { _ in KVCacheSimple() })
            let boundary = try #require(session.boundary as? MLXKVCacheBoundary)
            let layers = boundary.caches.compactMap { $0 as? KVCacheSimple }
            #expect(layers.count == 3)
            seatOnPeerStorage(layers[0], peerKeys: peerKeys, peerValues: peerValues)

            var sampled = 0
            let outcome = session.runStep(
                forward: { attendAllLayers(layers) },
                candidateToken: { sampled += 1; return 42 })

            let refusal = "kv_write_to_unregistered_storage(kv_cache)"
            #expect(outcome == .aborted(reason: refusal))
            #expect(sampled == 0, "the sampler must never run on a refused step")
            #expect(session.committedTokens.isEmpty, "no token may be committed")
            #expect(session.isTerminated)

            // The refusing layer rolled its offset back and wrote nothing.
            #expect(layers[0].state[0].dim(2) == 3)
            // Layers AFTER the refusal reached the write boundary and were refused
            // by the arm-level latch: allocated but never written (window length 0).
            #expect(layers[1].state[0].dim(2) == 0)
            #expect(layers[2].state[0].dim(2) == 0)
            #expect(layers[1].isolationAborted)
            #expect(layers[2].isolationAbortReason?.hasPrefix("arm_terminated_after(") == true)
            #expect(boundary.gateway.terminatedReason == refusal,
                    "the first refusal becomes the arm's permanent termination reason")
        }
    }

    // MARK: B2. A later-layer refusal leaves partial state that is UNREACHABLE

    @Test func laterLayerRefusalLeavesEarlierWritesUnreachable() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, peer) = sealedPair()
            let esRegistrar = try #require(es.makeRegistrar())
            let peerRegistrar = try #require(peer.makeRegistrar())
            let peerGateway = G3KVAllocationGateway(
                registrar: peerRegistrar, armLabel: peer.armID.rawValue)
            let peerKeys = kvTensor(4)
            let peerValues = kvTensor(4)
            _ = try peerGateway.admit(peerKeys, role: .kvCache)
            _ = try peerGateway.admit(peerValues, role: .kvCache)

            let session = try MLXPerArmKVCacheFactory.makeSession(
                armID: RuntimeArmID("ES+IS"), registrar: esRegistrar,
                caches: (0..<4).map { _ in KVCacheSimple() })
            let boundary = try #require(session.boundary as? MLXKVCacheBoundary)
            let layers = boundary.caches.compactMap { $0 as? KVCacheSimple }
            #expect(layers.count == 4)

            // Step 1: all four layers write and the token commits.
            #expect(session.runStep(
                forward: { attendAllLayers(layers) },
                candidateToken: { 7 }) == .committed(token: 7))
            #expect(layers.map { $0.state[0].dim(2) } == [1, 1, 1, 1])

            // Step 2: inject the refusal at layer 2, after layers 0 and 1 wrote.
            seatOnPeerStorage(layers[2], peerKeys: peerKeys, peerValues: peerValues)
            var sampled = 0
            let outcome = session.runStep(
                forward: { attendAllLayers(layers) },
                candidateToken: { sampled += 1; return 8 })

            let refusal = "kv_write_to_unregistered_storage(kv_cache)"
            #expect(outcome == .aborted(reason: refusal))
            #expect(sampled == 0, "the refused step's token is never read")
            #expect(session.committedTokens == [7], "only step 1 is committed")
            // Layers 0/1 did write step 2; layer 2 rolled back; layer 3 was cascaded.
            #expect(layers.map { $0.state[0].dim(2) } == [2, 2, 3, 1])

            // Lock 1: no further forward runs on this session.
            var furtherForwards = 0
            #expect(session.runStep(
                forward: { furtherForwards += 1 },
                candidateToken: { 99 }) == .refusedAfterTermination(reason: refusal))
            #expect(furtherForwards == 0)

            // Lock 2: a stray per-step reset cannot re-arm the boundary...
            boundary.beginStep()
            #expect(boundary.isolationAborted,
                    "a terminated boundary must not report itself live after beginStep()")
            // ...and even a direct native reset is re-refused by the gateway latch.
            layers[0].beginStep()
            #expect(layers[0].isolationAborted == false)
            _ = layers[0].update(keys: kvTensor(1), values: kvTensor(1))
            #expect(layers[0].isolationAborted)
            #expect(layers[0].isolationAbortReason?.hasPrefix("arm_terminated_after(") == true)
            #expect(layers[0].state[0].dim(2) == 2, "the blocked write did not advance the window")

            // Lock 3: the gated caches cannot be wrapped in a second session.
            var rearm: Error?
            do {
                _ = try MLXPerArmKVCacheFactory.makeSession(
                    armID: RuntimeArmID("ES+IS"), registrar: esRegistrar, caches: layers)
            } catch {
                rearm = error
            }
            guard case .armsShareMutableCache = (rearm as? G3PerArmCacheError) else {
                Issue.record("expected the gated caches to refuse a second session, got \(String(describing: rearm))")
                return
            }
        }
    }

    // MARK: B3. A step that throws terminates the arm (same failure semantics)

    @Test func enteredStepThatThrowsTerminatesTheArm() throws {
        let session = G3ArmCacheSession(armID: "ES+IS", boundary: StubBoundary())
        var thrown: Error?
        do {
            try session.runStep(
                forward: { throw StubError.forward },
                candidateToken: { 1 })
        } catch {
            thrown = error
        }
        #expect(thrown as? StubError == .forward)
        #expect(session.isTerminated, "an entered step that threw must not leave the arm live")
        #expect(session.stepCount == 1)
        #expect(session.committedTokens.isEmpty)
        #expect(session.abortReason?.hasPrefix("forward_threw(") == true)

        var furtherForwards = 0
        #expect(session.runStep(
            forward: { furtherForwards += 1 },
            candidateToken: { 2 }) == .refusedAfterTermination(reason: session.abortReason ?? ""))
        #expect(furtherForwards == 0)

        let second = G3ArmCacheSession(armID: "IS-only", boundary: StubBoundary())
        var sampled = 0
        do {
            try second.runStep(
                forward: {},
                candidateToken: { sampled += 1; throw StubError.sample })
        } catch {
            #expect(error as? StubError == .sample)
        }
        #expect(sampled == 1)
        #expect(second.isTerminated, "a failed sample read must terminate, not retry")
        #expect(second.committedTokens.isEmpty)
        #expect(second.abortReason?.hasPrefix("candidate_token_threw(") == true)
    }

    // MARK: C1. A boundary dead before the step is refused BEFORE forward

    /// Models a cache-resolution / observer-install failure that latched the
    /// boundary. The step must not enter forward at all, and the session must
    /// carry the failure as its termination reason.
    @Test func alreadyTerminatedBoundaryIsRefusedBeforeForward() {
        let boundary = StubBoundary()
        boundary.forceAbort(reason: "cache_resolution_failed")
        let session = G3ArmCacheSession(armID: "ES+IS", boundary: boundary)
        var forwards = 0
        let outcome = session.runStep(
            forward: { forwards += 1 },
            candidateToken: { 1 })
        #expect(outcome == .refusedAfterTermination(reason: "cache_resolution_failed"))
        #expect(forwards == 0, "a dead boundary must not receive a new forward")
        #expect(session.stepCount == 0, "a refused-before-forward step is not an entered step")
        #expect(session.isTerminated)
        #expect(session.committedTokens.isEmpty)
    }

    // MARK: C2. Release drops the cache, gateway and observer references

    /// Logical retirement is not enough: after `release()` the only strong path to
    /// the cache, its gateway and its observer is gone. Weak probes prove the ARC
    /// graph actually deallocates (no cache -> observer -> gateway -> cache cycle)
    /// with real admitted KV in the cache. SCOPE: this proves the native objects are
    /// deallocated; it does NOT measure MLX's allocator cache, so "the cache object
    /// is freed" is not claimed as "the GPU pages are returned to the OS".
    /// A release also TERMINATES the session and is idempotent: the second release
    /// changes nothing, and no later install can succeed.
    @Test func releaseDropsCacheGatewayAndObserver() throws {
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
                // Materialize real KV state first: the release must free a cache
                // that actually holds admitted KV, not just an empty shell.
                #expect(session.runStep(
                    forward: { attendAllLayers([cache]) },
                    candidateToken: { 3 }) == .committed(token: 3))
                #expect(cache.state[0].dim(2) == 1)
                weakCache = cache
                weakGateway = boundary.gateway
                weakObserver = cache.writeObserver as? G3KVCacheWriteObserver
                #expect(weakCache != nil)
                #expect(weakGateway != nil)
                #expect(weakObserver != nil)

                slot.release()
                #expect(session.abortReason == "cache_session_released",
                        "release must terminate the session, not only drop it")
                #expect(slot.installed == nil)
                #expect(slot.isRetired)
                // Idempotent: a second release neither resurrects nor re-terminates.
                slot.release()
                #expect(slot.installed == nil)
                #expect(slot.isRetired)
                #expect(slot.install(session) == false)
            }
            #expect(weakCache == nil, "release must free the cache")
            #expect(weakGateway == nil, "release must free the gateway")
            #expect(weakObserver == nil, "release must free the observer")
        }
    }

    // MARK: C4. Releasing one arm never touches the peer's cache

    /// Each arm owns its slot, session, caches and observer. Releasing the ES arm
    /// must leave the IS-only arm installed, live and gated: no shared slot, no
    /// shared termination latch, no observer removed from the peer's cache.
    @Test func releasingOneArmDoesNotTouchThePeer() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, peer) = sealedPair()
            let esRegistrar = try #require(es.makeRegistrar())
            let peerRegistrar = try #require(peer.makeRegistrar())

            let esCache = KVCacheSimple()
            let peerCache = KVCacheSimple()
            let esSession = try MLXPerArmKVCacheFactory.makeSession(
                armID: RuntimeArmID("ES+IS"), registrar: esRegistrar, caches: [esCache])
            let peerSession = try MLXPerArmKVCacheFactory.makeSession(
                armID: RuntimeArmID("IS-only"), registrar: peerRegistrar, caches: [peerCache])
            let esSlot = G3CacheSessionSlot()
            let peerSlot = G3CacheSessionSlot()
            #expect(esSlot.install(esSession))
            #expect(peerSlot.install(peerSession))

            #expect(peerSession.runStep(
                forward: { attendAllLayers([peerCache]) },
                candidateToken: { 11 }) == .committed(token: 11))
            #expect(peerCache.state[0].dim(2) == 1)

            esSlot.release()

            #expect(esSession.abortReason == "cache_session_released")
            #expect(peerSession.abortReason == nil,
                    "releasing ES must not terminate the peer arm")
            #expect(peerSlot.installed === peerSession,
                    "the peer slot must still hold its own session")
            #expect(peerSlot.isRetired == false)
            #expect(peerCache.writeObserver != nil,
                    "releasing ES must not remove the peer cache's observer")

            // The peer arm still generates: its observer admits, its step commits.
            #expect(peerSession.runStep(
                forward: { attendAllLayers([peerCache]) },
                candidateToken: { 12 }) == .committed(token: 12))
            #expect(peerCache.state[0].dim(2) == 2)
            #expect(peerSession.committedTokens == [11, 12])
        }
    }

    // MARK: C3. A partial observer-install failure leaves nothing behind

    /// The boundary validates EVERY layer before installing any observer, so a
    /// failure on layer 1 must not leave layer 0 gated. The failed creation never
    /// produced a session, so no slot was installed or retired.
    @Test func partialObserverInstallFailureLeavesNoObserverAndNoSlot() throws {
        let (es, _) = sealedPair()
        let registrar = try #require(es.makeRegistrar())
        let good = KVCacheSimple()
        // A real `KVCacheSimple` SUBCLASS whose `update` never calls the write
        // observer: the exact bypass the install-time type check exists for.
        let bad = ChunkedKVCache(chunkSize: nil)
        var failure: Error?
        do {
            _ = try MLXPerArmKVCacheFactory.makeSession(
                armID: RuntimeArmID("ES+IS"), registrar: registrar, caches: [good, bad])
        } catch {
            failure = error
        }
        guard case .unobservableCache = (failure as? G3PerArmCacheError) else {
            Issue.record("expected unobservableCache, got \(String(describing: failure))")
            return
        }
        #expect(good.writeObserver == nil, "a failed install must not leave a partial observer")
        #expect(bad.writeObserver == nil)
        let slot = G3CacheSessionSlot()
        #expect(slot.installed == nil)
        #expect(slot.isRetired == false,
                "creation failed before install, so the slot is not retired")
    }

    // MARK: C5. Concurrent and cancelled steps cannot commit

    /// Two loops over one session would be a wiring error. The second is refused
    /// and terminates the arm; the first forward then sees the termination and
    /// aborts without appending its token.
    @Test func concurrentStepTerminatesInsteadOfCommittingTwice() {
        let session = G3ArmCacheSession(armID: "ES+IS", boundary: StubBoundary())
        let entered = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let box = StepOutcomeBox()

        DispatchQueue.global().async {
            box.outcome = session.runStep(
                forward: {
                    entered.signal()
                    releaseFirst.wait()
                },
                candidateToken: { 1 })
            finished.signal()
        }

        #expect(entered.wait(timeout: .now() + 5) == .success)
        let second = session.runStep(forward: {}, candidateToken: { 2 })
        #expect(second == .refusedAfterTermination(reason: "concurrent_runStep"))
        releaseFirst.signal()
        #expect(finished.wait(timeout: .now() + 5) == .success)
        #expect(box.outcome == .aborted(reason: "concurrent_runStep"))
        #expect(session.committedTokens.isEmpty, "neither step may commit")
        #expect(session.isTerminated)
    }

    /// Cancellation is cooperative in MLX (the forward is synchronous), so the
    /// step checks `Task.isCancelled` before sampling. The token is never read or
    /// committed, and the session carries a `task_cancelled` tombstone.
    @Test func cancelledStepTerminatesWithoutCommit() async {
        let session = G3ArmCacheSession(armID: "ES+IS", boundary: StubBoundary())
        let cancelled = await Task { () -> Bool in
            do {
                _ = try session.runStep(
                    forward: { withUnsafeCurrentTask { $0?.cancel() } },
                    candidateToken: {
                        if Task.isCancelled { throw CancellationError() }
                        return 1
                    })
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }.value
        #expect(cancelled)
        #expect(session.isTerminated)
        #expect(session.abortReason == "task_cancelled")
        #expect(session.committedTokens.isEmpty)
    }

    /// A release that lands DURING a step must stop the commit. The forward returns
    /// normally (the cache is still sound), but the session's commit check sees the
    /// release tombstone and discards the token; every later step is refused.
    @Test func releaseDuringStepStopsTheCommit() throws {
        let slot = G3CacheSessionSlot()
        let session = G3ArmCacheSession(armID: "ES+IS", boundary: StubBoundary())
        #expect(slot.install(session))

        var sampled = 0
        let outcome = session.runStep(
            forward: { slot.release() },
            candidateToken: { sampled += 1; return 5 })

        #expect(outcome == .aborted(reason: "cache_session_released"))
        #expect(sampled == 0, "a released arm's token must never be read")
        #expect(session.committedTokens.isEmpty, "a released arm's token must not be committed")
        #expect(session.abortReason == "cache_session_released")
        #expect(slot.isRetired)
        #expect(session.runStep(
            forward: { Issue.record("no forward after release") },
            candidateToken: { 6 }) == .refusedAfterTermination(reason: "cache_session_released"))
    }
}
