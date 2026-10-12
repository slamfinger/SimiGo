import Foundation
import SimiGoRuntimeContract

/// Serializes coordinator transitions across backend awaits. A transition
/// must keep exclusive access to logical state until its physical backend
/// operation and logical commit are both complete.
private actor CoordinatorAsyncOperationGate {
    private var occupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withPermit<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        await acquire()
        do {
            // A cancelled caller queued behind another transition must not
            // begin a new state mutation when its turn arrives.
            try Task.checkCancellation()
            let result = try await operation()
            release()
            return result
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async {
        if !occupied {
            occupied = true
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            occupied = false
        } else {
            // Keep the permit occupied while handing it directly to the
            // next waiter, preventing a new caller from jumping the queue.
            waiters.removeFirst().resume()
        }
    }
}

/// A restore commit hook failed and the compensating backend rebind also
/// failed. Logical Coordinator state has not been committed, but physical
/// state may now require recovery; this is deliberately not an atomicity claim.
private struct RestoreCompensationFailure: Error, LocalizedError, Sendable {
    let commitFailure: String
    let rollbackFailure: String

    var errorDescription: String? {
        "restore pre-commit hook failed (\(commitFailure)); restoring the previous backend representation also failed (\(rollbackFailure)); logical Coordinator state was not committed"
    }
}

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
        /// No captured representation exists at the restore/fork target
        /// position: a logical restore or a physical fork derivation
        /// requires a captured physical representation at that position
        /// (capture one before continuing past it).
        case noRepresentationAtPosition(executionID: ExecutionID, position: ExecutionPosition)
        /// A previous restore's compensation rebind failed for this
        /// execution, so the backend's physical binding may still sit at the
        /// restore target while the logical handle remains at the prior
        /// position. Operations that assume the binding corresponds to the
        /// logical position (fork derivation, discard's physical release)
        /// are rejected until a successful restore — or a bind at the
        /// current handle position — re-establishes the correspondence.
        case backendBindingUncertain(executionID: ExecutionID)
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
    private let operationGate = CoordinatorAsyncOperationGate()
    /// The async gate serializes writers across suspension points. This lock
    /// protects synchronous observation while a transition commits.
    private let stateLock = NSRecursiveLock()
    private var handles: [ExecutionID: ExecutionStateHandle] = [:]
    private var records: [LifecycleRecord] = []
    /// Representation history per execution: appended on every bind/capture/
    /// derive; restore finds its target here.
    private var representationHistory: [ExecutionID: [ExecutionRepresentation]] = [:]
    /// Executions whose backend binding may not correspond to the logical
    /// handle position: set ONLY when a restore's compensation rebind failed
    /// (the physical rollback could not undo the target rebind), cleared
    /// when a successful restore — or a bind at the current handle position
    /// — re-establishes the correspondence.
    private var bindingUncertain: Set<ExecutionID> = []
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
        stateLock.withLock {
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
        try await operationGate.withPermit { [self] in
            guard stateLock.withLock({ handles[executionID] != nil }) else {
                throw CoordinatorError.unknownExecution(executionID)
            }
            let representation = ExecutionRepresentation(
                executionID: executionID,
                position: position,
                payload: payload
            )
            try await backend.restoreRepresentation(representation)
            stateLock.withLock {
                representationHistory[executionID, default: []].append(representation)
                // A bind at the current handle position re-establishes the
                // physical↔logical correspondence (the backend binding was
                // overwritten with a representation for exactly this
                // position); a bind elsewhere leaves the uncertainty.
                if handles[executionID]?.position == position {
                    bindingUncertain.remove(executionID)
                }
            }
        }
    }

    // MARK: - ExecutionContinuityRuntime

    public func create(
        id: ExecutionID,
        position: ExecutionPosition,
        continuation: ExecutionContinuation
    ) async throws -> ExecutionStateHandle {
        try await operationGate.withPermit { [self] in
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
            stateLock.withLock {
                handles[id] = handle
                appendRecord(.created, executionID: id, resultLifecycle: .attached, resultPosition: position, resultContinuation: continuation)
            }
            return handle
        }
    }

    public func attach(_ state: ExecutionStateHandle) async throws -> ExecutionStateHandle {
        try await operationGate.withPermit { [self] in
            if handles[state.id] != nil {
                throw CoordinatorError.duplicateExecution(state.id)
            }
            stateLock.withLock {
                handles[state.id] = state
                appendRecord(.attached, executionID: state.id, resultLifecycle: state.lifecycle, resultPosition: state.position, resultContinuation: state.continuation)
            }
            return state
        }
    }

    public func continueExecution(
        _ state: ExecutionStateHandle,
        continuation: ExecutionContinuation
    ) async throws -> ExecutionStateHandle {
        try await operationGate.withPermit { [self] in
            let current = try guardKnown(state.id)
            let advanced = ExecutionStateHandle(
                id: current.id,
                lineage: current.lineage,
                position: ExecutionPosition(current.position.value + 1),
                continuation: continuation,
                lifecycle: .active
            )
            stateLock.withLock {
                handles[current.id] = advanced
                appendRecord(.continued, executionID: current.id, resultLifecycle: .active, resultPosition: advanced.position, resultContinuation: continuation)
            }
            return advanced
        }
    }

    public func fork(_ request: ExecutionForkRequest) async throws -> ExecutionStateHandle {
        try await operationGate.withPermit { [self] in
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
            var childRep: ExecutionRepresentation?
            if parent.position == request.childPosition {
                let history = representationHistory[parent.id] ?? []
                // The representation must match the forked logical position
                // exactly (`parent` is the coordinator's current handle, from
                // guardKnown). A stale `.last` (e.g. after a restore rewound the
                // handle) must never be derived from.
                if let parentRep = history.last(where: { $0.position == parent.position }) {
                    // The derivation hands the backend a representation on
                    // the assumption that it describes the parent's CURRENT
                    // physical state. After a failed compensation rebind that
                    // assumption is unverifiable — fail closed before any
                    // physical derivation (a lazy fork below never touches
                    // the backend and stays available).
                    if stateLock.withLock({ bindingUncertain.contains(parent.id) }) {
                        throw CoordinatorError.backendBindingUncertain(executionID: parent.id)
                    }
                    let probe = ExecutionStateHandle(
                        id: request.childID,
                        lineage: ExecutionLineage(root: parent.lineage.root, parent: parent.id),
                        position: request.childPosition,
                        continuation: request.childContinuation,
                        lifecycle: .active
                    )
                    childRep = try await backend.deriveRepresentation(from: parentRep, for: probe)
                } else if !history.isEmpty {
                    // Representations exist but none at the fork point: fail
                    // closed before any child mutation (never guess from a
                    // mismatched position).
                    throw CoordinatorError.noRepresentationAtPosition(
                        executionID: parent.id,
                        position: parent.position
                    )
                }
                // No history at all: unchanged lazy fork — the child binds
                // after its first generation.
            }

            let child = ExecutionStateHandle(
                id: request.childID,
                lineage: ExecutionLineage(root: parent.lineage.root, parent: parent.id),
                position: request.childPosition,
                continuation: request.childContinuation,
                lifecycle: .active
            )
            stateLock.withLock {
                handles[request.childID] = child
                appendRecord(.forked, executionID: request.childID, relatedID: parent.id, resultLifecycle: .active, resultPosition: request.childPosition, resultContinuation: request.childContinuation)

                if let rep = childRep {
                    representationHistory[request.childID, default: []].append(rep)
                }
            }
            return child
        }
    }

    public func restore(
        _ state: ExecutionStateHandle,
        request: ExecutionRestoreRequest
    ) async throws -> ExecutionStateHandle {
        try await restoreImpl(state, request: request, beforeCommit: nil)
    }

    /// Engine-only transaction seam: run a synchronous, throwing cross-layer
    /// commit hook after the physical target rebind but before committing the
    /// logical handle and lifecycle record. If the hook fails, rebind the
    /// previous physical representation and leave logical Coordinator state
    /// untouched. This covers the token-ledger marker boundary, not arbitrary
    /// external writes or general cross-component transaction atomicity.
    func restore(
        _ state: ExecutionStateHandle,
        request: ExecutionRestoreRequest,
        beforeCommit: @escaping @Sendable () throws -> Void
    ) async throws -> ExecutionStateHandle {
        try await restoreImpl(state, request: request, beforeCommit: beforeCommit)
    }

    private func restoreImpl(
        _ state: ExecutionStateHandle,
        request: ExecutionRestoreRequest,
        beforeCommit: (@Sendable () throws -> Void)?
    ) async throws -> ExecutionStateHandle {
        try await operationGate.withPermit { [self] in
            let current = try guardKnown(state.id)
            let history = representationHistory[current.id] ?? []

            // A logical restore requires a captured physical representation at
            // the target position — otherwise the runtime would promise a state
            // it cannot physically deliver.
            guard let targetRep = history.last(where: { $0.position == request.targetPosition })
            else {
                throw CoordinatorError.noRepresentationAtPosition(
                    executionID: current.id,
                    position: request.targetPosition
                )
            }

            // The transactional variant needs a known prior representation
            // to compensate if the cross-layer commit hook rejects the restore.
            let priorRep: ExecutionRepresentation?
            if beforeCommit != nil {
                guard let capturedPrior = history.last(where: { $0.position == current.position }) else {
                    throw CoordinatorError.noRepresentationAtPosition(
                        executionID: current.id,
                        position: current.position
                    )
                }
                priorRep = capturedPrior
            } else {
                priorRep = nil
            }

            try await backend.restoreRepresentation(targetRep)

            if let beforeCommit {
                do {
                    try beforeCommit()
                } catch let commitError {
                    if let priorRep {
                        do {
                            try await backend.restoreRepresentation(priorRep)
                            // The compensation rebind succeeded: the backend
                            // binding is back at the prior (== current logical)
                            // position, so any earlier uncertainty is resolved
                            // and the original retry behavior is preserved.
                            stateLock.withLock { bindingUncertain.remove(current.id) }
                        } catch let rollbackError {
                            // The physical rollback failed: the backend may
                            // still be bound at the restore target while the
                            // logical handle stays at the prior position.
                            // Mark the correspondence uncertain (fail-closed)
                            // and keep BOTH failures visible.
                            stateLock.withLock { bindingUncertain.insert(current.id) }
                            throw RestoreCompensationFailure(
                                commitFailure: String(describing: commitError),
                                rollbackFailure: String(describing: rollbackError)
                            )
                        }
                    }
                    throw commitError
                }
            }

            let restored = ExecutionStateHandle(
                id: current.id,
                lineage: current.lineage,
                position: request.targetPosition,
                continuation: request.continuation,
                lifecycle: .restored
            )
            stateLock.withLock {
                handles[current.id] = restored
                // Logical and physical both sit at the target now.
                bindingUncertain.remove(current.id)
                appendRecord(.restored, executionID: current.id, resultLifecycle: .restored, resultPosition: request.targetPosition, resultContinuation: request.continuation)
            }
            return restored
        }
    }

    public func reattach(_ state: ExecutionStateHandle) async throws -> ExecutionStateHandle {
        try await operationGate.withPermit { [self] in
            let current = try guardKnown(state.id)
            let reattached = ExecutionStateHandle(
                id: current.id,
                lineage: current.lineage,
                position: current.position,
                continuation: current.continuation,
                lifecycle: .active
            )
            stateLock.withLock {
                handles[current.id] = reattached
                appendRecord(.reattached, executionID: current.id, resultLifecycle: .active, resultPosition: current.position, resultContinuation: current.continuation)
            }
            return reattached
        }
    }

    public func discard(_ state: ExecutionStateHandle) async throws {
        try await operationGate.withPermit { [self] in
            let current = try guardKnown(state.id)

            // TRANSACTIONAL DISCARD (review fix: failure atomicity) — the
            // physical representation is released FIRST; the logical discard
            // commits only after the release succeeded. A failed release leaves
            // the logical state UNCHANGED (still resumable/retryable) instead of
            // a "discarded-but-weights-resident" split.
            // The release targets the LAST history representation on the
            // assumption that it IS the current physical binding. After a
            // failed compensation rebind that assumption is unverifiable and
            // the release would silently no-op while the discard still
            // committed — reject instead until the state is re-established.
            if stateLock.withLock({ bindingUncertain.contains(current.id) }) {
                throw CoordinatorError.backendBindingUncertain(executionID: current.id)
            }
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
            stateLock.withLock {
                handles[current.id] = discardedHandle
                appendRecord(.discarded, executionID: current.id, resultLifecycle: .discarded, resultPosition: current.position, resultContinuation: current.continuation)
            }
        }
    }

    public var recordCount: Int {
        stateLock.withLock { records.count }
    }

    public var recordsSnapshot: [LifecycleRecord] {
        stateLock.withLock { records }
    }

    public func handle(_ id: ExecutionID) -> ExecutionStateHandle? {
        stateLock.withLock { handles[id] }
    }
}
