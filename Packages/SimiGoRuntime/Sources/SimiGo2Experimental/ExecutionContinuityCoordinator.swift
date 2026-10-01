import Foundation
import SimiGoRuntimeContract

/// E3 — production Execution Continuity runtime: E1 lifecycle semantics
/// (registry + one authoritative lifecycle record per transition) combined
/// with Backend representation binding.
///
/// Sovereignty: the coordinator owns identity/lineage/position/continuation
/// and lifecycle records; the ExecutionStateBackend owns physical
/// representation. Backend operations can never alter a handle's identity,
/// lineage, or continuation.
public final class ExecutionContinuityCoordinator: ExecutionContinuityRuntime, @unchecked Sendable {
    public enum CoordinatorError: Error, Equatable, Sendable {
        case unknownExecution(ExecutionID)
        case duplicateExecution(ExecutionID)
        case discardedExecution(ExecutionID)
        /// No captured representation exists at the restore target position:
        /// a logical restore requires a captured physical representation at
        /// that position (capture one before continuing past it).
        case noRepresentationAtPosition(executionID: ExecutionID, position: ExecutionPosition)
    }

    /// One authoritative lifecycle record per transition (⑧ discipline
    /// carried from the verification skeleton into production).
    public struct LifecycleRecord: Equatable, Sendable {
        public enum Operation: String, Equatable, Sendable {
            case created, attached, continued, forked, restored, reattached, discarded
        }

        public let sequence: Int
        public let operation: Operation
        public let executionID: ExecutionID
        public let relatedID: ExecutionID?
        public let resultLifecycle: ExecutionBranchLifecycle
        public let resultPosition: ExecutionPosition
        public let resultContinuation: ExecutionContinuation
    }

    /// ExecutionRepresentation is not Equatable (opaque payload); equality
    /// is keyed on (executionID, position) which the coordinator owns.
    public struct RepresentationRecord: Equatable, Sendable {
        public let executionID: ExecutionID
        public let position: ExecutionPosition
    }

    private let backend: any ExecutionStateBackend
    private var handles: [ExecutionID: ExecutionStateHandle] = [:]
    private(set) var records: [LifecycleRecord] = []
    /// Representation history per execution: appended on every bind/capture/
    /// derive; restore finds its target here.
    private var representationHistory: [ExecutionID: [ExecutionRepresentation]] = [:]
    private var sequence = 0

    public init(backend: any ExecutionStateBackend) {
        self.backend = backend
    }

    private func appendRecord(
        _ operation: LifecycleRecord.Operation,
        executionID: ExecutionID,
        relatedID: ExecutionID? = nil,
        resultLifecycle: ExecutionBranchLifecycle,
        resultPosition: ExecutionPosition,
        resultContinuation: ExecutionContinuation
    ) {
        sequence += 1
        records.append(
            LifecycleRecord(
                sequence: sequence,
                operation: operation,
                executionID: executionID,
                relatedID: relatedID,
                resultLifecycle: resultLifecycle,
                resultPosition: resultPosition,
                resultContinuation: resultContinuation
            )
        )
    }

    private func guardKnown(_ id: ExecutionID) throws -> ExecutionStateHandle {
        guard let handle = handles[id] else {
            throw CoordinatorError.unknownExecution(id)
        }
        guard handle.lifecycle != .discarded else {
            throw CoordinatorError.discardedExecution(id)
        }
        return handle
    }

    // MARK: - Representation binding (host drives after each generation)

    /// The host binds the execution's physical representation after a
    /// generation pass. The coordinator records it in the representation
    /// history (so later logical restores can find a captured physical
    /// state at that position) and pushes it to the backend via the
    /// contract's restore operation (make the backend's physical state
    /// match this representation).
    public func bindRepresentation(
        executionID: ExecutionID,
        position: ExecutionPosition,
        payload: any ExecutionRepresentationPayload
    ) async throws {
        guard handles[executionID] != nil else {
            throw CoordinatorError.unknownExecution(executionID)
        }
        let representation = ExecutionRepresentation(
            executionID: executionID,
            position: position,
            payload: payload
        )
        try await backend.restoreRepresentation(representation)
        representationHistory[executionID, default: []].append(representation)
    }

    // MARK: - ExecutionContinuityRuntime

    public func create(
        id: ExecutionID,
        position: ExecutionPosition,
        continuation: ExecutionContinuation
    ) async throws -> ExecutionStateHandle {
        if handles[id] != nil {
            throw CoordinatorError.duplicateExecution(id)
        }
        let handle = ExecutionStateHandle(
            id: id,
            lineage: ExecutionLineage(root: id),
            position: position,
            continuation: continuation,
            lifecycle: .attached
        )
        handles[id] = handle
        appendRecord(.created, executionID: id, resultLifecycle: .attached, resultPosition: position, resultContinuation: continuation)
        return handle
    }

    public func attach(_ state: ExecutionStateHandle) async throws -> ExecutionStateHandle {
        if handles[state.id] != nil {
            throw CoordinatorError.duplicateExecution(state.id)
        }
        handles[state.id] = state
        appendRecord(.attached, executionID: state.id, resultLifecycle: state.lifecycle, resultPosition: state.position, resultContinuation: state.continuation)
        return state
    }

    public func continueExecution(
        _ state: ExecutionStateHandle,
        continuation: ExecutionContinuation
    ) async throws -> ExecutionStateHandle {
        let current = try guardKnown(state.id)
        let advanced = ExecutionStateHandle(
            id: current.id,
            lineage: current.lineage,
            position: ExecutionPosition(current.position.value + 1),
            continuation: continuation,
            lifecycle: .active
        )
        handles[current.id] = advanced
        appendRecord(.continued, executionID: current.id, resultLifecycle: .active, resultPosition: advanced.position, resultContinuation: continuation)
        return advanced
    }

    public func fork(_ request: ExecutionForkRequest) async throws -> ExecutionStateHandle {
        let parent = try guardKnown(request.parent.id)
        if handles[request.childID] != nil {
            throw CoordinatorError.duplicateExecution(request.childID)
        }

        // TRANSACTIONAL FORK (review FM-02): the physical derivation runs
        // BEFORE the logical child commits — a derivation failure leaves the
        // parent unchanged and the child UNCOMMITTED (no handle, no fork
        // record, no partial representation history). The logical fork
        // (handle + record + history) is in-memory and commits only after
        // the physical derivation succeeded.
        var child: ExecutionStateHandle?
        var childRep: ExecutionRepresentation?
        if parent.position == request.childPosition,
            let parentRep = representationHistory[parent.id]?.last {
            let probe = ExecutionStateHandle(
                id: request.childID,
                lineage: ExecutionLineage(root: parent.lineage.root, parent: parent.id),
                position: request.childPosition,
                continuation: request.childContinuation,
                lifecycle: .active
            )
            childRep = try await backend.deriveRepresentation(from: parentRep, for: probe)
        }

        child = ExecutionStateHandle(
            id: request.childID,
            lineage: ExecutionLineage(root: parent.lineage.root, parent: parent.id),
            position: request.childPosition,
            continuation: request.childContinuation,
            lifecycle: .active
        )
        handles[request.childID] = child!
        appendRecord(.forked, executionID: request.childID, relatedID: parent.id, resultLifecycle: .active, resultPosition: request.childPosition, resultContinuation: request.childContinuation)

        if let rep = childRep {
            representationHistory[request.childID, default: []].append(rep)
        }
        return child!
    }

    public func restore(
        _ state: ExecutionStateHandle,
        request: ExecutionRestoreRequest
    ) async throws -> ExecutionStateHandle {
        let current = try guardKnown(state.id)

        // A logical restore requires a captured physical representation at
        // the target position — otherwise the runtime would promise a state
        // it cannot physically deliver.
        guard let targetRep = representationHistory[state.id]?
            .last(where: { $0.position == request.targetPosition })
        else {
            throw CoordinatorError.noRepresentationAtPosition(
                executionID: current.id,
                position: request.targetPosition
            )
        }
        try await backend.restoreRepresentation(targetRep)

        let restored = ExecutionStateHandle(
            id: current.id,
            lineage: current.lineage,
            position: request.targetPosition,
            continuation: request.continuation,
            lifecycle: .restored
        )
        handles[current.id] = restored
        appendRecord(.restored, executionID: current.id, resultLifecycle: .restored, resultPosition: request.targetPosition, resultContinuation: request.continuation)
        return restored
    }

    public func reattach(_ state: ExecutionStateHandle) async throws -> ExecutionStateHandle {
        let current = try guardKnown(state.id)
        let reattached = ExecutionStateHandle(
            id: current.id,
            lineage: current.lineage,
            position: current.position,
            continuation: current.continuation,
            lifecycle: .active
        )
        handles[current.id] = reattached
        appendRecord(.reattached, executionID: current.id, resultLifecycle: .active, resultPosition: current.position, resultContinuation: current.continuation)
        return reattached
    }

    public func discard(_ state: ExecutionStateHandle) async throws {
        let current = try guardKnown(state.id)

        // TRANSACTIONAL DISCARD (review fix: failure atomicity) — the
        // physical representation is released FIRST; the logical discard
        // commits only after the release succeeded. A failed release leaves
        // the logical state UNCHANGED (still resumable/retryable) instead of
        // a "discarded-but-weights-resident" split.
        if let last = representationHistory[current.id]?.last {
            try await backend.releaseRepresentation(last)
        }

        let discardedHandle = ExecutionStateHandle(
            id: current.id,
            lineage: current.lineage,
            position: current.position,
            continuation: current.continuation,
            lifecycle: .discarded
        )
        handles[current.id] = discardedHandle
        appendRecord(.discarded, executionID: current.id, resultLifecycle: .discarded, resultPosition: current.position, resultContinuation: current.continuation)
    }

    public var recordCount: Int { records.count }

    public var recordsSnapshot: [LifecycleRecord] { records }

    public func handle(_ id: ExecutionID) -> ExecutionStateHandle? {
        handles[id]
    }
}
