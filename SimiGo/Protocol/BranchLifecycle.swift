import Foundation

/// Branch lifecycle contract shared by the HTTP layer and the engine
/// wirings (owner ruling 2026-11-05 S3-A).
///
/// Deliberately located OUTSIDE NativeMLX: the llama.cpp ES-semantics
/// integration owns the branch generation model. This file carries only
/// the transport-stable contract — the outcome/error shapes and the
/// optional `expected_generation` guard — so the engine-side generation
/// source can land later without breaking the HTTP seam.

/// The result of a branch deletion. The outcome is CONSUMED by the HTTP
/// layer: a successful deletion reports what was removed and what
/// remains, and every failure path is typed — a silent `ok:true` is
/// unreachable.
public struct BranchDeletionOutcome: Equatable, Sendable {
    public let deletedBranch: String
    public let hadLiveSession: Bool
    public let hadCheckpointFile: Bool
    /// The runtime-tracked generation of the deleted branch, when the
    /// runtime tracks one (the llama.cpp ES integration will supply it).
    /// `nil` means this runtime does not carry a generation source; the
    /// response omits the field rather than inventing a number.
    public let generation: UInt64?
    public let remainingLiveBranches: [String]
    public let remainingCheckpointBranches: [String]

    public init(
        deletedBranch: String,
        hadLiveSession: Bool,
        hadCheckpointFile: Bool,
        generation: UInt64? = nil,
        remainingLiveBranches: [String],
        remainingCheckpointBranches: [String]
    ) {
        self.deletedBranch = deletedBranch
        self.hadLiveSession = hadLiveSession
        self.hadCheckpointFile = hadCheckpointFile
        self.generation = generation
        self.remainingLiveBranches = remainingLiveBranches
        self.remainingCheckpointBranches = remainingCheckpointBranches
    }
}

/// Typed failures for branch lifecycle operations. They map to explicit
/// HTTP outcomes (404 / 409) — never to an `ok:true` body.
public enum BranchLifecycleError: Error, Equatable, Sendable {
    /// Neither a live session nor a checkpoint exists under this session's
    /// namespace. Covers nonexistent branches and cross-session targets by
    /// construction: the execution key namespace is agent/session-scoped,
    /// so a branch of another session is unknown here by design.
    case branchUnknown(sessionId: String, branchId: String)
    /// The caller's view is stale relative to the tracked generation.
    /// Raised only by runtimes that carry a generation source.
    case branchGenerationMismatch(expected: UInt64, actual: UInt64)
}
