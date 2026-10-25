// SPDX-License-Identifier: MIT

// PS1 — CONTROLLED NATIVE TERMINATION AT THE WRITE BOUNDARY
//
// This suite pins the production seam added for PS1: a gateway-owned, capability-
// bound termination entry that makes the REAL KV write path refuse, cascade and
// latch, without turning the gateway into a universal off switch.
//
// The invariants under test (all model-free, real `KVCacheSimple` + real
// `attentionWithCacheUpdate`):
//
//   1. After the first accepted termination, every layer's next write is refused
//      BEFORE eval, before admission and before the slice-assign: no layer's
//      offset advances and `admittedCount` stays where it was.
//   2. The first reason is permanent. A second terminate call cannot overwrite or
//      clear it, `beginStep()` cannot reset it, and the cascade reason on later
//      layers carries the ORIGINAL reason.
//   3. A terminated session refuses before entering a forward: the forward count
//      and the sampler stay at zero, no token is committed, and the session is
//      terminally marked (the executor's settle path is unreachable because it
//      throws on `abortReason` before `consumeBinding`).
//   4. Terminating one arm does not touch the peer: the peer still admits, writes
//      and commits its own token.
//   5. The capability is bound to one gateway/arm. Another arm's grant is
//      rejected and changes nothing; an empty reason is rejected too.
//   6. A cache with no observer (ordinary inference, no G3) keeps native behavior:
//      writes advance the offset and nothing latches.
//
// Honest limits: the remaining forward compute is not cancelled (MLX's cache API
// returns a tuple); it is inert — no KV is written and the logits are never read.
// No model is loaded, no provider is registered, no G3 run executes, and the work
// tree is not committed.

import Foundation
import Testing
import MLX
import MLXLMCommon
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

struct G3GatewayTerminationTests {

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

    private let refusal = "d1_planned_kv_refusal"

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
        let es = makeArm("ES+IS", writeRoot: "/tmp/g3/ps1/es")
        let peer = makeArm("IS-only", writeRoot: "/tmp/g3/ps1/is")
        es.seal(against: peer); peer.seal(against: es)
        return (es, peer)
    }

    private func makeSession(
        arm: String, owner: G3ArmResourceOwner, layers: Int
    ) throws -> (G3ArmCacheSession, MLXKVCacheBoundary, [KVCacheSimple]) {
        let registrar = try #require(owner.makeRegistrar())
        let caches = (0..<layers).map { _ in KVCacheSimple() }
        let session = try MLXPerArmKVCacheFactory.makeSession(
            armID: RuntimeArmID(arm), registrar: registrar, caches: caches)
        let boundary = try #require(session.boundary as? MLXKVCacheBoundary)
        let simples = caches.compactMap { $0 as? KVCacheSimple }
        #expect(simples.count == layers)
        return (session, boundary, simples)
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

    // MARK: 1. Termination refuses every later layer before any write

    @Test func terminationRefusesEveryLayerBeforeAnyWrite() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let (_, boundary, layers) = try makeSession(arm: "ES+IS", owner: es, layers: 3)

            #expect(boundary.terminateArm(reason: refusal) == .terminated(reason: refusal))
            #expect(boundary.gateway.admittedCount == 0)

            // The real write path: each layer allocates, hits the observer, and is
            // refused before eval/admission/slice-assign.
            attendAllLayers(layers)

            for (index, layer) in layers.enumerated() {
                #expect(layer.state[0].dim(2) == 0,
                        "layer \(index) wrote KV after the arm was terminated")
                #expect(layer.isolationAborted)
                #expect(layer.isolationAbortReason == "arm_terminated_after(\(refusal))")
            }
            #expect(boundary.gateway.admittedCount == 0,
                    "a terminated gateway must not admit any buffer")
            #expect(boundary.gateway.terminatedReason == refusal)
        }
    }

    // MARK: 2. The first reason is permanent and beginStep cannot clear it

    @Test func firstTerminationReasonIsPermanent() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let (session, boundary, layers) = try makeSession(arm: "ES+IS", owner: es, layers: 2)

            #expect(boundary.terminateArm(reason: "first_reason")
                    == .terminated(reason: "first_reason"))
            #expect(boundary.terminateArm(reason: "second_reason")
                    == .alreadyTerminated(reason: "first_reason"))
            #expect(boundary.gateway.terminatedReason == "first_reason")

            // A per-step reset must not re-arm a dead arm.
            boundary.beginStep()
            #expect(boundary.isolationAborted)
            #expect(boundary.isolationAbortReason == "first_reason")
            #expect(session.abortReason == nil,
                    "beginStep alone must not fabricate a session tombstone")

            // Later writes cascade with the ORIGINAL reason, not the second one.
            attendAllLayers(layers)
            #expect(layers[0].isolationAbortReason
                    == "arm_terminated_after(first_reason)")
            #expect(layers[0].state[0].dim(2) == 0)
            #expect(boundary.gateway.terminatedReason == "first_reason")
        }
    }

    // MARK: 3. A terminated session refuses before forward and never commits

    @Test func terminatedSessionRefusesBeforeForwardAndNeverCommits() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, _) = sealedPair()
            let (session, boundary, layers) = try makeSession(arm: "ES+IS", owner: es, layers: 3)
            boundary.terminateArm(reason: refusal)

            var forwards = 0
            var sampled = 0
            let outcome = session.runStep(
                forward: {
                    forwards += 1
                    attendAllLayers(layers)
                },
                candidateToken: {
                    sampled += 1
                    return 11
                })

            #expect(outcome == .refusedAfterTermination(reason: refusal))
            // The exact production predicate the executor's pre-generation gate AND
            // its pre-settlement backstop read.
            #expect(session.terminalAbortReason == refusal)
            #expect(forwards == 0, "a terminated gateway must be observed before the forward")
            #expect(sampled == 0, "the sampler must never run on a terminated arm")
            #expect(session.committedTokens.isEmpty, "no token may be committed")
            #expect(session.isTerminated)
            #expect(session.abortReason == refusal)
            // No step ran, so the caches were never touched: no buffer exists and
            // no offset advanced.
            #expect(layers.allSatisfy { $0.offset == 0 && $0.state.isEmpty })

            // Repeated attempts stay refused with the same tombstone.
            let again = session.runStep(
                forward: { forwards += 1 },
                candidateToken: { sampled += 1; return 12 })
            #expect(again == .refusedAfterTermination(reason: refusal))
            #expect(forwards == 0)
            #expect(sampled == 0)
            #expect(session.committedTokens.isEmpty)
        }
    }

    // MARK: 4. The peer arm keeps writing and committing

    @Test func terminatingOneArmLeavesThePeerLive() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, peer) = sealedPair()
            let (esSession, esBoundary, esLayers) =
                try makeSession(arm: "ES+IS", owner: es, layers: 2)
            let (peerSession, peerBoundary, peerLayers) =
                try makeSession(arm: "IS-only", owner: peer, layers: 2)

            esBoundary.terminateArm(reason: refusal)

            let outcome = peerSession.runStep(
                forward: { attendAllLayers(peerLayers) },
                candidateToken: { 7 })

            #expect(outcome == .committed(token: 7))
            #expect(peerSession.committedTokens == [7])
            #expect(peerBoundary.terminatedReason == nil)
            #expect(peerBoundary.gateway.admittedCount > 0)
            #expect(peerLayers.allSatisfy { $0.state[0].dim(2) == 1 })

            // The terminated arm wrote nothing and committed nothing (its caches
            // were never entered, so they hold no buffer at all).
            #expect(esSession.committedTokens.isEmpty)
            #expect(esLayers.allSatisfy { $0.offset == 0 && $0.state.isEmpty })
        }
    }

    // MARK: 5. Termination authority is bound to one gateway/arm

    @Test func terminationIsBoundToTheOwningGateway() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let (es, peer) = sealedPair()
            let (esSession, esBoundary, _) = try makeSession(arm: "ES+IS", owner: es, layers: 1)
            let (peerSession, peerBoundary, _) = try makeSession(arm: "IS-only", owner: peer, layers: 1)
            let esGateway = esBoundary.gateway
            let peerGateway = peerBoundary.gateway

            // Another arm's capability is not authority over this gateway.
            #expect(esGateway.terminate(
                reason: refusal, grant: peerGateway.terminationGrant)
                == .rejected(reason: "termination_grant_mismatch"))
            #expect(esGateway.terminatedReason == nil)
            #expect(!esBoundary.isolationAborted)
            #expect(esSession.terminalAbortReason == nil, "a rejected call must not arm the arm")

            // An empty reason must not create an unreadable tombstone.
            #expect(esGateway.terminate(
                reason: "   ", grant: esGateway.terminationGrant)
                == .rejected(reason: "empty_termination_reason"))
            #expect(esGateway.terminatedReason == nil)

            // Its own capability works, and does not touch the peer.
            #expect(esGateway.terminate(reason: refusal, grant: esGateway.terminationGrant)
                    == .terminated(reason: refusal))
            #expect(esSession.terminalAbortReason == refusal)
            #expect(peerGateway.terminatedReason == nil)
            #expect(peerSession.terminalAbortReason == nil)
            #expect(!peerBoundary.isolationAborted)
        }
    }

    // MARK: 6. Ordinary (non-G3) cache behavior is unchanged

    @Test func standardCacheWithoutObserverKeepsNativeBehavior() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let cache = KVCacheSimple()
            #expect(cache.writeObserver == nil)

            _ = cache.update(keys: kvTensor(4), values: kvTensor(4))
            #expect(cache.offset == 4)
            #expect(cache.state[0].dim(2) == 4)
            #expect(!cache.isolationAborted)

            _ = cache.update(keys: kvTensor(1), values: kvTensor(1))
            #expect(cache.offset == 5)
            #expect(cache.state[0].dim(2) == 5)
            #expect(!cache.isolationAborted)
        }
    }
}
