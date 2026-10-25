import Foundation
import SimiGoRuntimeContract

// NATIVE EXECUTION-CARRIER LIFECYCLE
//
// The physical handoff the E5/E3 line has been missing: an explicit, VERIFIABLE
// release of the OLD execution carrier between "the old Execution State has
// settled and its checkpoint is persisted" and "a brand-new Execution State
// resumes the settled representation". Releasing a carrier is not creating
// another backend — it means dropping the model context / KV cache / physical
// representation references the old state held AND proving the old carrier can
// no longer serve the old ES.
//
// This file owns the LIFECYCLE VOCABULARY (errors + the pure storage-isolation
// decision). The concrete release lives on ``MLXExecutionStateBackend`` (the
// retired-carrier tombstone) and ``MLXPrefixRecomputeExecutor`` (which reuses the
// single-use ``G3CacheSessionSlot`` teardown and the published
// `MLXArray.mlxStorageIdentity` evidence via ``G3KVAllocationGateway``). The
// Information-Space authority, settlement-checkpoint cross-validation and
// persisted-representation restore are REUSED from the existing recovery path —
// nothing here re-implements them.
//
// Fail-closed rule: every throw below is a refusal to resume. When one is raised
// the caller MUST NOT advance the Information Space, because the physical handoff
// (release / non-reuse / isolation) cannot be proven, and a resume on top of it
// would be indistinguishable from silently reusing the old carrier.

/// Refusals raised by the native carrier-release / handoff protocol.
public enum CarrierLifecycleError: Error, Equatable, Sendable {
    /// The old carrier could not be released cleanly: its physical representation
    /// was not retired, its bound read did not come back as `.carrierReleased`,
    /// or its G3 cache-session slot is still armable. A partial release is not a
    /// release, so the handoff is refused.
    case releaseIncomplete(reason: String)
    /// After release the old carrier is STILL usable by the old ES (a bound
    /// representation reads back, or a cache re-arms). Resuming would silently
    /// reuse the old physical state instead of a freshly recovered one.
    case carrierStillUsable(executionID: String)
    /// The freshly adopted carrier's mutable storage shares a confirmed underlying
    /// buffer (same `mlxStorageIdentity` evidence) with the retired carrier: the
    /// old state was never actually released, so continuing would generate over
    /// aliased memory.
    case carriersShareStorage(executionID: String, sharedBufferIDs: [String])
    /// The retired carrier held observable mutable storage but the adopting
    /// carrier exposes none confirmable, so isolation from the retired carrier is
    /// UNPROVEN. Missing evidence fails closed rather than assuming distinct.
    case carrierStorageIsolationUnobservable(executionID: String)
    /// The bound ``ProductionRuntimeModelContinuationExecutor`` cannot perform an
    /// explicit carrier release at all (it is not an ``ExecutionCarrierReleasing``
    ///), so the native lifecycle path cannot prove release and refuses.
    case carrierReleaseUnsupported
}

/// The outcome of proving a freshly adopted carrier is isolated from the retired
/// one, keyed on the CONFIRMED underlying-buffer storage ids each carrier
/// registered (derived from the published `MLXArray.mlxStorageIdentity`).
public enum CarrierStorageIsolation: Equatable, Sendable {
    case isolated
    case shared(Set<String>)
    case unobservable
}

/// Pure classification of carrier isolation from two sets of confirmed
/// underlying-buffer storage ids. Deliberately value-only (no runtime, no model),
/// so the same rule is unit-testable and is applied unchanged at the live handoff:
/// an id present in BOTH carriers means the old mutable state was never released;
/// a retired carrier that held observable mutable storage met by a new carrier
/// that exposes none confirmable is unproven, never "distinct".
public enum CarrierStorageIsolationEvaluator {
    /// - Parameters:
    ///   - retired: the released carrier's confirmed mutable-storage ids.
    ///   - adopting: the freshly adopted carrier's confirmed mutable-storage ids.
    public static func evaluate(
        retired: Set<String>,
        adopting: Set<String>
    ) -> CarrierStorageIsolation {
        // The recompute / no-KV carrier registered no observable mutable storage,
        // so there is nothing it could still alias — honestly isolated, not a
        // claimed verified-isolation over buffers we never saw.
        if retired.isEmpty { return .isolated }
        // The retired carrier DID hold mutable storage; a new carrier that cannot
        // show its own observable ids cannot prove it is disjoint from them.
        guard !adopting.isEmpty else { return .unobservable }
        let overlap = retired.intersection(adopting)
        return overlap.isEmpty ? .isolated : .shared(overlap)
    }
}

/// The explicit carrier lifecycle an execution component must offer for the
/// native release→verify→handoff protocol. The production MLX executor conforms
/// by reusing its single-use KV-session teardown and the backend retired-carrier
/// tombstone; a model-free test double conforms against the same
/// ``MLXExecutionStateBackend`` so the protocol and its fail-closed behavior are
/// verifiable without loading model weights.
public protocol ExecutionCarrierReleasing: AnyObject {
    /// Drop the execution's physical representation and KV/mutable references and
    /// RETIRE the carrier so it can no longer serve the old ES. Captures the
    /// retired carrier's confirmed mutable-storage ids for the handoff check.
    func releaseExecutionCarrier(for state: ExecutionStateHandle) throws

    /// Prove the release actually took: the old carrier is unusable by the old ES.
    /// Throws ``CarrierLifecycleError`` instead of reporting a false release.
    func verifyCarrierUnusable(for state: ExecutionStateHandle) throws

    /// The confirmed mutable-storage ids the retired carrier held (empty when it
    /// never observed mutable KV storage). Feeds the isolation evaluator.
    func retiredCarrierStorageIDs(for state: ExecutionStateHandle) -> Set<String>

    /// Prove a freshly adopted carrier on THIS executor is isolated from a retired
    /// carrier's storage ids. Refuses shared or unobservable aliasing fail-closed.
    func verifyAdoptedCarrierIsolated(
        from retiredStorageIDs: Set<String>,
        for state: ExecutionStateHandle
    ) throws
}
