import Foundation

/// E1 — backend-neutral semantic contract for SimiGo Execution Continuity.
///
/// This target is intentionally MLX-free. It describes logical execution
/// identity and lifecycle only; physical KV/recurrent state and model-specific
/// state remain owned by the Backend.
public struct ExecutionID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Logical parent linkage for an execution branch.
///
/// Physical representation is deliberately absent. Nested ancestry is obtained
/// by following parent identities through the authoritative lifecycle records.
public struct ExecutionLineage: Hashable, Sendable {
    public let root: ExecutionID
    public let parent: ExecutionID?

    public init(root: ExecutionID, parent: ExecutionID? = nil) {
        self.root = root
        self.parent = parent
    }
}

/// Logical execution position in the execution's own timeline.
public struct ExecutionPosition: Hashable, Sendable {
    public let value: Int64

    public init(_ value: Int64) {
        self.value = value
    }
}

/// Backend-neutral description of what continuation means.
///
/// The contract deliberately uses logical identifiers rather than tensors,
/// KV buffers, cache pages, or model-architecture state. A concrete Backend
/// translates these semantics to its own physical representation.
public struct ExecutionContinuation: Hashable, Sendable {
    public let nextInput: String
    public let continuationID: String

    public init(nextInput: String, continuationID: String) {
        self.nextInput = nextInput
        self.continuationID = continuationID
    }
}

/// Logical lifecycle state of an execution branch.
///
/// These values describe the Runtime lifecycle, not physical residency.
/// Resident/evicted/materialized/checkpointed/migrated are Backend
/// representation states and are intentionally absent here.
public enum ExecutionBranchLifecycle: String, Hashable, Sendable {
    case attached
    case active
    case restored
    case discarded
}

/// Logical Execution State handle.
///
/// This is the Runtime's semantic identity record. It contains no physical
/// state authority and no Backend-specific representation.
public struct ExecutionStateHandle: Hashable, Sendable {
    public let id: ExecutionID
    public let lineage: ExecutionLineage
    public let position: ExecutionPosition
    public let continuation: ExecutionContinuation
    public let lifecycle: ExecutionBranchLifecycle

    public init(
        id: ExecutionID,
        lineage: ExecutionLineage,
        position: ExecutionPosition,
        continuation: ExecutionContinuation,
        lifecycle: ExecutionBranchLifecycle
    ) {
        self.id = id
        self.lineage = lineage
        self.position = position
        self.continuation = continuation
        self.lifecycle = lifecycle
    }
}

/// Parameters for deriving a child Execution State from a parent.
public struct ExecutionForkRequest: Hashable, Sendable {
    public let parent: ExecutionStateHandle
    public let childID: ExecutionID
    public let childPosition: ExecutionPosition
    public let childContinuation: ExecutionContinuation

    public init(
        parent: ExecutionStateHandle,
        childID: ExecutionID,
        childPosition: ExecutionPosition,
        childContinuation: ExecutionContinuation
    ) {
        self.parent = parent
        self.childID = childID
        self.childPosition = childPosition
        self.childContinuation = childContinuation
    }
}

/// Logical target for restore. No physical snapshot or tensor type is exposed.
public struct ExecutionRestoreRequest: Hashable, Sendable {
    public let targetPosition: ExecutionPosition
    public let continuation: ExecutionContinuation

    public init(
        targetPosition: ExecutionPosition,
        continuation: ExecutionContinuation
    ) {
        self.targetPosition = targetPosition
        self.continuation = continuation
    }
}

/// E1 lifecycle surface.
///
/// The operations are intentionally limited to the Track B-derived set:
/// create/attach, continue, fork, restore, reattach, discard.
///
/// This protocol defines semantic lifecycle only. It does not prescribe how
/// a Backend stores, copies, checkpoints, materializes, or executes state.
public protocol ExecutionContinuityRuntime: Sendable {
    func create(
        id: ExecutionID,
        position: ExecutionPosition,
        continuation: ExecutionContinuation
    ) async throws -> ExecutionStateHandle

    func attach(
        _ state: ExecutionStateHandle
    ) async throws -> ExecutionStateHandle

    func continueExecution(
        _ state: ExecutionStateHandle,
        continuation: ExecutionContinuation
    ) async throws -> ExecutionStateHandle

    func fork(
        _ request: ExecutionForkRequest
    ) async throws -> ExecutionStateHandle

    func restore(
        _ state: ExecutionStateHandle,
        request: ExecutionRestoreRequest
    ) async throws -> ExecutionStateHandle

    func reattach(
        _ state: ExecutionStateHandle
    ) async throws -> ExecutionStateHandle

    func discard(
        _ state: ExecutionStateHandle
    ) async throws
}
