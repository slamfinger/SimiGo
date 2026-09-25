import XCTest
import SimiGoRuntimeContract
@testable import SimiGoRuntimeContract

/// E2 — FakeExecutionBackend: a minimal logical Execution Continuity runtime
/// used to verify the E1 contract WITHOUT MLX and WITHOUT any residency or
/// physical-representation modeling. Representation state is deliberately
/// orthogonal (⑦): a representation migration touches nothing logical.
final class FakeExecutionContinuityRuntime: ExecutionContinuityRuntime, @unchecked Sendable {
    enum FakeError: Error, Equatable {
        case unknownExecution(ExecutionID)
        case duplicateExecution(ExecutionID)
        case discardedExecution(ExecutionID)
        case missingParent(ExecutionID)
    }

    /// ⑧ The single authoritative lifecycle record: one record per
    /// lifecycle transition, in order. Representation migrations are NOT
    /// lifecycle transitions and never appear here.
    struct LifecycleRecord: Equatable, Sendable {
        enum Operation: String, Equatable, Sendable {
            case created, attached, continued, forked, restored, reattached, discarded
        }

        let sequence: Int
        let operation: Operation
        let executionID: ExecutionID
        let relatedID: ExecutionID?
        let resultLifecycle: ExecutionBranchLifecycle
        let resultPosition: ExecutionPosition
        let resultContinuation: ExecutionContinuation
    }

    private(set) var records: [LifecycleRecord] = []
    private(set) var handles: [ExecutionID: ExecutionStateHandle] = [:]
    private(set) var discardedIDs: Set<ExecutionID> = []
    /// ⑦ Representation migrations recorded SEPARATELY from lifecycle
    /// records: migrating a representation is not a lifecycle transition and
    /// must not touch identity, position, or continuation.
    private(set) var representationMigrations: [(executionID: ExecutionID, representation: String)] = []

    private var sequence = 0

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

    private func guardKnownAndNotDiscarded(_ id: ExecutionID) throws -> ExecutionStateHandle {
        guard let handle = handles[id] else {
            throw FakeError.unknownExecution(id)
        }
        guard handle.lifecycle != .discarded else {
            throw FakeError.discardedExecution(id)
        }
        return handle
    }

    func create(
        id: ExecutionID,
        position: ExecutionPosition,
        continuation: ExecutionContinuation
    ) async throws -> ExecutionStateHandle {
        if handles[id] != nil || discardedIDs.contains(id) {
            throw FakeError.duplicateExecution(id)
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

    func attach(_ state: ExecutionStateHandle) async throws -> ExecutionStateHandle {
        if handles[state.id] != nil || discardedIDs.contains(state.id) {
            throw FakeError.duplicateExecution(state.id)
        }
        handles[state.id] = state
        appendRecord(.attached, executionID: state.id, resultLifecycle: state.lifecycle, resultPosition: state.position, resultContinuation: state.continuation)
        return state
    }

    func continueExecution(
        _ state: ExecutionStateHandle,
        continuation: ExecutionContinuation
    ) async throws -> ExecutionStateHandle {
        let current = try guardKnownAndNotDiscarded(state.id)
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

    func fork(_ request: ExecutionForkRequest) async throws -> ExecutionStateHandle {
        let parent = try guardKnownAndNotDiscarded(request.parent.id)
        if handles[request.childID] != nil || discardedIDs.contains(request.childID) {
            throw FakeError.duplicateExecution(request.childID)
        }
        // The child's lineage traces to the parent; the parent is untouched.
        let child = ExecutionStateHandle(
            id: request.childID,
            lineage: ExecutionLineage(root: parent.lineage.root, parent: parent.id),
            position: request.childPosition,
            continuation: request.childContinuation,
            lifecycle: .active
        )
        handles[request.childID] = child
        appendRecord(.forked, executionID: request.childID, relatedID: parent.id, resultLifecycle: .active, resultPosition: request.childPosition, resultContinuation: request.childContinuation)
        return child
    }

    func restore(
        _ state: ExecutionStateHandle,
        request: ExecutionRestoreRequest
    ) async throws -> ExecutionStateHandle {
        let current = try guardKnownAndNotDiscarded(state.id)
        // Logical restore: identity and lineage are preserved; position and
        // continuation are set to the requested LOGICAL target. No tensor,
        // snapshot, or physical artifact exists in this contract.
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

    func reattach(_ state: ExecutionStateHandle) async throws -> ExecutionStateHandle {
        let current = try guardKnownAndNotDiscarded(state.id)
        // Reattach re-activates the state WITHOUT changing its continuation
        // contract (identity, position, continuation all preserved).
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

    func discard(_ state: ExecutionStateHandle) async throws {
        let current = try guardKnownAndNotDiscarded(state.id)
        let discardedHandle = ExecutionStateHandle(
            id: current.id,
            lineage: current.lineage,
            position: current.position,
            continuation: current.continuation,
            lifecycle: .discarded
        )
        handles[current.id] = discardedHandle
        discardedIDs.insert(current.id)
        appendRecord(.discarded, executionID: current.id, resultLifecycle: .discarded, resultPosition: current.position, resultContinuation: current.continuation)
    }

    /// ⑦ Simulated representation migration (e.g. checkpoint, KV copy,
    /// re-materialization). Deliberately touches NOTHING logical.
    func migrateRepresentation(of id: ExecutionID, to representation: String) throws {
        guard handles[id] != nil, !discardedIDs.contains(id) else {
            throw FakeError.unknownExecution(id)
        }
        representationMigrations.append((id, representation))
    }
}
