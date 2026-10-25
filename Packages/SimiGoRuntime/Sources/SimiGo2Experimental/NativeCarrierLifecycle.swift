import Foundation

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
// This file owns the LIFECYCLE VOCABULARY (errors, the carrier address, the
// release report and the pure storage-isolation decision). The concrete release
// lives where the resources actually live:
//   * ``MLXRuntimeCarrierOwner`` (app side) over `NativeMLX`, whose session pool
//     holds the real `ChatSession` — and therefore the real KV cache — keyed by
//     agent/session/branch. Releasing removes that session, calls the vendor
//     `clear()`, detaches its prefix binding and deletes its checkpoints;
//   * ``MLXExecutionStateBackend`` (package side) holds the ES-identity
//     tombstone, so a retired carrier cannot be re-bound by the old Execution
//     State even if a caller still holds a handle.
// The Information-Space authority, settlement-checkpoint cross-validation and
// persisted-representation restore are REUSED from the existing recovery path —
// nothing here re-implements them.
//
// Fail-closed rule: every throw below is a refusal. When one is raised the
// caller MUST NOT advance the Information Space, because the physical handoff
// (release / non-reuse / isolation) cannot be proven, and a resume on top of it
// would be indistinguishable from silently reusing the old carrier.
//
// THREE DISTINCT FACTS, never merged into one word:
//   1. the release was INVOKED (``CarrierReleaseReport`` fields);
//   2. the carrier's REFERENCES are gone (no live session; binding detached);
//   3. the vendor KV memory was actually freed — NOT provable here. `ChatSession`
//      exposes no buffer identity in this tree, so ``CarrierStorageEvidence``
//      reports `.unobservable` instead of letting an empty set mean "nothing was
//      held". Claim (3) stays open (G3 D1 NO-GO).

/// Refusals raised by the native carrier-release / handoff protocol.
public enum CarrierLifecycleError: Error, Equatable, Sendable {
    /// The old carrier could not be released cleanly: the runtime still serves a
    /// session for the address after the release ran, so the drop is partial. A
    /// partial release is not a release, so the handoff is refused.
    case releaseIncomplete(reason: String)
    /// After release the old carrier is STILL usable by the old ES (a live
    /// session still resolves the address). Resuming would silently reuse the old
    /// physical state instead of a freshly recovered one.
    case carrierStillUsable(executionID: String)
    /// The freshly adopted carrier's mutable storage shares a confirmed underlying
    /// buffer with the retired carrier: the old state was never actually released,
    /// so continuing would generate over aliased memory.
    case carriersShareStorage(executionID: String, sharedBufferIDs: [String])
    /// The retired carrier held observable mutable storage but the adopting
    /// carrier exposes none confirmable, so isolation from the retired carrier is
    /// UNPROVEN. Missing evidence fails closed rather than assuming distinct.
    case carrierStorageIsolationUnobservable(executionID: String)
    /// The bound executor cannot perform an explicit carrier release at all (it is
    /// not an ``ExecutionCarrierReleasing``), so the native lifecycle path cannot
    /// prove release and refuses.
    case carrierReleaseUnsupported
}

/// Address of a physical carrier in the runtime that owns it.
///
/// An Execution State id alone is NOT enough: the real owner keys its sessions by
/// (agent, session, logical branch), and the BRANCH is the physical carrier. The
/// continuation path uses the admitted child ES id as exactly that branch id, so
/// a caller can address the carrier without inventing a second identity space.
public struct ExecutionCarrierRef: Sendable, Hashable {
    public let agentID: String?
    public let sessionID: String
    /// The runtime branch identity (the continuation child ES id on that path).
    public let branchID: String

    public init(agentID: String?, sessionID: String, branchID: String) {
        self.agentID = agentID
        self.sessionID = sessionID
        self.branchID = branchID
    }
}

/// What the owner ACTUALLY did when asked to release a carrier. Each field is a
/// separate fact, so a caller cannot report "the KV is freed" from "clear() was
/// called".
public struct CarrierReleaseReport: Sendable, Equatable {
    /// A live session/branch existed at this address before the release.
    public let carrierWasLive: Bool
    /// The vendor `clear()` was issued. This says the CALL happened; it does not
    /// prove the allocator returned the pages.
    public let clearIssued: Bool
    /// How many live sessions (client shards of the same branch) were removed
    /// from the runtime's pool.
    public let sessionsReleased: Int
    /// The execution binding was detached from the prefix pool.
    public let bindingDetached: Bool
    /// Checkpoint files removed from the branch store.
    public let checkpointFilesDeleted: Int
    /// The branch was still live after the release. A true value means the release
    /// did not take, and the handoff must be refused (the owner throws instead).
    public let stillLiveAfterwards: Bool
    /// What the retired carrier could be shown to hold. Never guessed.
    public let retiredStorage: CarrierStorageEvidence

    public init(
        carrierWasLive: Bool,
        clearIssued: Bool,
        sessionsReleased: Int,
        bindingDetached: Bool,
        checkpointFilesDeleted: Int,
        stillLiveAfterwards: Bool,
        retiredStorage: CarrierStorageEvidence
    ) {
        self.carrierWasLive = carrierWasLive
        self.clearIssued = clearIssued
        self.sessionsReleased = sessionsReleased
        self.bindingDetached = bindingDetached
        self.checkpointFilesDeleted = checkpointFilesDeleted
        self.stillLiveAfterwards = stillLiveAfterwards
        self.retiredStorage = retiredStorage
    }
}

/// What a carrier can be shown to hold, honestly separated from "we could not
/// look": conflating the two would let an unobserved KV cache pass as isolated.
public enum CarrierStorageEvidence: Equatable, Sendable {
    /// The carrier holds no observable mutable storage at all (a recompute /
    /// no-KV carrier). Nothing can alias it.
    case noneObserved
    /// Confirmed underlying-buffer ids.
    case observable(Set<String>)
    /// The carrier may hold mutable storage but exposes no identity for it.
    /// Isolation from it is UNPROVEN and must be refused, not assumed.
    case unobservable(String)
}

/// The outcome of proving a freshly adopted carrier is isolated from the retired
/// one, keyed on the CONFIRMED underlying-buffer storage ids each carrier
/// registered (derived from the published `MLXArray.mlxStorageIdentity`).
public enum CarrierStorageIsolation: Equatable, Sendable {
    case isolated
    case shared(Set<String>)
    case unobservable
}

/// Pure classification of carrier isolation. Deliberately value-only (no runtime,
/// no model), so the same rule is unit-testable and is applied unchanged at the
/// live handoff: an id present in BOTH carriers means the old mutable state was
/// never released; a retired carrier that held observable mutable storage met by
/// a new carrier that exposes none confirmable is unproven, never "distinct".
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

    /// Evidence-carrying form of the same rule: the only form that can express
    /// the honest third answer. A retired carrier whose storage could not be
    /// observed is never "isolated", it is unproven.
    public static func evaluate(
        retired: CarrierStorageEvidence,
        adopting: CarrierStorageEvidence
    ) -> CarrierStorageIsolation {
        switch (retired, adopting) {
        case (.noneObserved, _):
            return .isolated
        case (.unobservable, _), (_, .unobservable):
            return .unobservable
        case (.observable, .noneObserved):
            return .unobservable
        case (.observable(let old), .observable(let new)):
            let overlap = old.intersection(new)
            return overlap.isEmpty ? .isolated : .shared(overlap)
        }
    }
}

/// The explicit carrier lifecycle an execution component must offer for the
/// native release→verify→handoff protocol. The production runtime conforms by
/// ``MLXRuntimeCarrierOwner`` over `NativeMLX` (its real session pool), and the
/// package-side ``MLXExecutionStateBackend`` carries the retired-identity
/// tombstone. A model-free test double conforms to the same protocol, so the
/// wiring is verifiable without loading model weights.
public protocol ExecutionCarrierReleasing: AnyObject {
    /// Drop the carrier's physical references and RETIRE it so it can no longer
    /// serve the old ES. Returns what was actually done; throws
    /// ``CarrierLifecycleError/releaseIncomplete(reason:)`` instead of reporting a
    /// partial release (a branch still live afterwards).
    func releaseExecutionCarrier(_ ref: ExecutionCarrierRef) async throws -> CarrierReleaseReport

    /// Prove the release actually took: nothing is live at that address and the
    /// old ES cannot use it. Throws ``CarrierLifecycleError`` on a false release.
    func verifyCarrierUnusable(_ ref: ExecutionCarrierRef) throws
}
