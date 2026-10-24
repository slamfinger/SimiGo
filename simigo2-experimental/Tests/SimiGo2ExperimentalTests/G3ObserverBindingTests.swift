// SPDX-License-Identifier: MIT

// PS1 — THE WRITE GATE IS A BINDING, NOT AN ASSIGNABLE VARIABLE
//
// The reviewer's bypass: `KVCacheSimple.writeObserver` used to be a plain public
// var, so ANY path holding a cache reference could clear it, after which
// `update()` would write KV with no gateway. A termination grant does not help —
// it protects the terminate authority, not the integrity of the write hook.
//
// The fork now separates the two:
//   * `writeObserver` stays assignable for ordinary callers while the cache is
//     UNBOUND (normal inference is unchanged);
//   * `bindWriteObserver` installs a G3 gate and returns a capability. Once
//     bound, an assignment that clears or replaces the gate is REFUSED and
//     latched (`write_observer_mutated_after_binding`), permanently;
//   * `unbindWriteObserver` accepts only the capability minted for that cache;
//   * the boundary re-verifies every layer's binding BEFORE each forward and
//     fails closed, and `update()` itself refuses to write after a violation.
//
// These tests are model-free: no model is loaded, no provider is trusted, no G3
// execution is claimed.

import Foundation
import Testing
import MLX
import MLXLMCommon
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

/// A permissive observer: lets writes through so a refusal in these tests can
/// only come from the BINDING policy, not from the observer's own decision.
private final class AllowAllObserver: KVCacheWriteObserver {
    private(set) var offered = 0

    func kvCache(
        _ cache: KVCacheSimple, willWriteKeys keys: MLXArray, values: MLXArray,
        range: Range<Int>, freshStorage: Bool
    ) -> KVCacheWriteDecision {
        offered += 1
        return .allow
    }
}

struct G3ObserverBindingTests {

    // MARK: Sealed arm (model-free)

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
            writeRoot: "/tmp/g3/observer-binding/\(arm)")
    }

    private func sealedOwner(_ arm: String) -> G3ArmResourceOwner {
        let owner = makeArm(arm)
        let peer = makeArm("\(arm)-peer")
        owner.seal(against: peer); peer.seal(against: owner)
        return owner
    }

    /// One arm, one layer, via the PRODUCTION factory — the same wiring the
    /// executor uses, only without a model.
    private func soloSession(
        _ arm: String = "ES+IS"
    ) throws -> (G3ArmCacheSession, MLXKVCacheBoundary, KVCacheSimple) {
        let owner = sealedOwner(arm)
        let registrar = try #require(owner.makeRegistrar())
        let cache = KVCacheSimple()
        let session = try MLXPerArmKVCacheFactory.makeSession(
            armID: RuntimeArmID(arm), registrar: registrar, caches: [cache])
        let boundary = try #require(session.boundary as? MLXKVCacheBoundary)
        return (session, boundary, cache)
    }

    // MARK: 1. Clearing / replacing a BOUND gate is refused and latched

    @Test func aBoundGateRejectsClearingAndReplacement() throws {
        let cache = KVCacheSimple()
        let original = AllowAllObserver()
        let binding = try #require(cache.bindWriteObserver(original))
        #expect(cache.writeObserver === original)
        #expect(cache.writeObserverBindingID == binding.id)

        // Re-assigning the SAME observer is idempotent, not a mutation.
        cache.writeObserver = original
        #expect(cache.observerBindingViolation == nil)

        // The reviewer's bypass: clear the gate through the legacy property.
        cache.writeObserver = nil
        #expect(cache.writeObserver === original, "a bound gate cannot be cleared")
        #expect(cache.observerBindingViolation == "write_observer_mutated_after_binding")
        #expect(cache.isolationAborted)

        // A per-step reset cannot make the tampered cache look live again.
        cache.beginStep()
        #expect(cache.isolationAborted)
        #expect(cache.isolationAbortReason == "write_observer_mutated_after_binding")

        // Swapping in another observer is refused the same way.
        cache.writeObserver = AllowAllObserver()
        #expect(cache.writeObserver === original, "a bound gate cannot be replaced")
    }

    // MARK: 2. Removal is a capability, not a property write

    @Test func unbindingRequiresTheCapabilityMintedForThatCache() throws {
        let cache = KVCacheSimple()
        let observer = AllowAllObserver()
        let binding = try #require(cache.bindWriteObserver(observer))

        // A capability minted for a DIFFERENT cache is not authority over this one.
        let other = KVCacheSimple()
        let otherBinding = try #require(other.bindWriteObserver(AllowAllObserver()))
        #expect(cache.unbindWriteObserver(otherBinding) == false,
                "a borrowed capability must not remove this cache's gate")
        #expect(cache.writeObserver === observer)
        #expect(cache.writeObserverBindingID == binding.id)
        #expect(cache.observerBindingViolation == nil, "a refused unbind is not tampering")

        // A second bind cannot take over an already-bound gate.
        #expect(cache.bindWriteObserver(AllowAllObserver()) == nil)

        // Only the minted capability removes it.
        #expect(cache.unbindWriteObserver(binding))
        #expect(cache.writeObserver == nil)
        #expect(cache.writeObserverBindingID == nil)
    }

    // MARK: 3. Ordinary (unbound) caches keep their legacy semantics

    @Test func anUnboundCacheKeepsLegacyAssignmentSemantics() {
        let cache = KVCacheSimple()
        let observer = AllowAllObserver()

        cache.writeObserver = observer
        #expect(cache.writeObserver === observer)
        #expect(cache.writeObserverBindingID == nil, "a plain assignment is not a binding")

        cache.writeObserver = nil
        #expect(cache.writeObserver == nil)
        #expect(cache.observerBindingViolation == nil, "an unbound cache latches nothing")
        #expect(cache.isolationAborted == false)
    }

    // MARK: 4. A cleared gate refuses the NEXT step before its forward

    @Test func aClearedGateRefusesTheNextStepBeforeItsForward() throws {
        let (session, boundary, cache) = try soloSession()
        #expect(boundary.observedCacheCount == 1)

        var forwards = 0
        let step1 = session.runStep(forward: { forwards += 1 }, candidateToken: { 5 })
        #expect(step1 == .committed(token: 5))
        #expect(cache.isolationAborted == false)

        // A path that merely holds the cache reference attempts to un-gate it.
        cache.writeObserver = nil
        #expect(cache.writeObserver != nil, "the attempt did not remove the gate")

        let violation = "write_observer_mutated_after_binding"
        let step2 = session.runStep(forward: { forwards += 1 }, candidateToken: { 6 })
        #expect(step2 == .refusedAfterTermination(reason: violation))
        #expect(forwards == 1, "the pre-execution check fails closed BEFORE the forward")
        #expect(session.committedTokens == [5], "the refused step commits no token")
        #expect(session.abortReason == violation)

        // The boundary's own verification is latched: a later `beginStep` cannot
        // make the tampered arm look live again.
        boundary.beginStep()
        #expect(boundary.isolationAborted)
        #expect(boundary.isolationAbortReason == violation)
    }

    // MARK: 5. A replaced gate refuses the NEXT step before its forward

    @Test func aReplacedGateRefusesTheNextStepBeforeItsForward() throws {
        let (session, boundary, cache) = try soloSession()
        let installed = try #require(cache.writeObserver)

        var forwards = 0
        #expect(session.runStep(forward: { forwards += 1 }, candidateToken: { 5 })
                    == .committed(token: 5))

        // Attempted swap to a permissive observer: refused, original still bound.
        cache.writeObserver = AllowAllObserver()
        #expect(cache.writeObserver === installed)
        #expect(cache.writeObserverBindingID != nil)

        let violation = "write_observer_mutated_after_binding"
        let step2 = session.runStep(forward: { forwards += 1 }, candidateToken: { 6 })
        #expect(step2 == .refusedAfterTermination(reason: violation))
        #expect(forwards == 1)
        #expect(session.committedTokens == [5])
        #expect(boundary.isolationAbortReason == violation)
    }
}
