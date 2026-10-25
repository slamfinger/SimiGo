import Foundation
import SimiGo2Experimental

/// The narrow seam between the lifecycle protocol and the object that actually
/// OWNS execution carriers: `NativeMLX`, whose session pool holds the real
/// `ChatSession` (and therefore the real KV cache) for a branch.
///
/// It is a protocol only so the owner's decision logic can be exercised without
/// loading weights: the production conformer is `NativeMLX` itself
/// (``extension NativeMLX: SessionBranchReleasing``), so a test that drives this
/// seam cannot accidentally prove behaviour the runtime does not have.
protocol SessionBranchReleasing: AnyObject {
    /// Drop the branch's live session(s), clear the vendor session, detach the
    /// prefix binding, delete the branch checkpoints and REPORT each fact.
    func releaseSessionBranch(
        agentId: String?,
        sessionId: String,
        logicalBranchId: String,
        in storeDirectory: URL?
    ) async throws -> SessionBranchRelease

    /// Whether any live session still serves this branch (model-free read).
    func hasLiveSessionBranch(
        agentId: String?,
        sessionId: String,
        logicalBranchId: String
    ) -> Bool
}

extension NativeMLX: SessionBranchReleasing {}

/// The carrier owner wired into the product's HTTP server.
///
/// This is the object that turns "the continuation was refused" into "the branch
/// it forked no longer holds a live carrier". It is deliberately thin: every
/// operation it reports is performed by the runtime, and the one thing it cannot
/// observe (the vendor KV buffer identity) is reported as `.unobservable` rather
/// than as an empty set — so a caller can never read "released" as "pages
/// returned to the allocator".
///
/// `verifyCarrierUnusable` is the point of the whole type: `clear()` being issued
/// is NOT the same fact as the carrier no longer resolving. The product path
/// calls it right after the release, so the trace records the stronger claim and
/// a surviving carrier stays visible instead of being reported gone.
final class MLXRuntimeCarrierOwner: ExecutionCarrierReleasing, @unchecked Sendable {
    private let pool: any SessionBranchReleasing

    init(pool: any SessionBranchReleasing) {
        self.pool = pool
    }

    convenience init(runtime: NativeMLX) {
        self.init(pool: runtime)
    }

    func releaseExecutionCarrier(
        _ ref: ExecutionCarrierRef
    ) async throws -> CarrierReleaseReport {
        let release = try await pool.releaseSessionBranch(
            agentId: ref.agentID,
            sessionId: ref.sessionID,
            logicalBranchId: ref.branchID,
            in: nil
        )
        // A branch that still resolves after the release is NOT a release: report
        // it as a refusal instead of handing back a report a caller could read as
        // "released".
        guard !release.stillLiveAfterwards else {
            throw CarrierLifecycleError.releaseIncomplete(
                reason: "branch \(ref.branchID) still live after release"
                    + " (sessionsReleased=\(release.sessionsReleased))")
        }
        return CarrierReleaseReport(
            carrierWasLive: release.carrierWasLive,
            clearIssued: release.clearIssued,
            sessionsReleased: release.sessionsReleased,
            bindingDetached: release.bindingDetached,
            checkpointFilesDeleted: release.checkpointFilesDeleted,
            stillLiveAfterwards: release.stillLiveAfterwards,
            retiredStorage: release.retiredStorage
        )
    }

    func verifyCarrierUnusable(_ ref: ExecutionCarrierRef) throws {
        guard !pool.hasLiveSessionBranch(
            agentId: ref.agentID,
            sessionId: ref.sessionID,
            logicalBranchId: ref.branchID
        ) else {
            throw CarrierLifecycleError.carrierStillUsable(executionID: ref.branchID)
        }
    }
}
