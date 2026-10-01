import Foundation
import SimiGoRuntimeContract

/// E3 — the first concrete ExecutionStateBackend: the prefix-recompute
/// representation strategy of the currently validated harness. An
/// execution's physical state is its token prefix (prompt + generated);
/// continue/fork/restore bind token prefixes, and the executor recomputes
/// over the bound prefix. Future KV-copy or shared-prefix strategies
/// replace THIS strategy only — the E1 logical contract and this backend
/// contract are unchanged.
///
/// This backend is pure data: it holds bindings and captured
/// representations but performs no model execution. Execution consumes the
/// bound representation through the MLXPrefixRecomputeExecutor.
public struct MLXPrefixPayload: ExecutionRepresentationPayload, Equatable, Sendable {
    public let tokenPrefix: [Int]

    public init(tokenPrefix: [Int]) {
        self.tokenPrefix = tokenPrefix
    }
}

public final class MLXExecutionStateBackend: ExecutionStateBackend, @unchecked Sendable {
    public enum BackendError: Error, Equatable, Sendable {
        case noBoundRepresentation(ExecutionID)
        case representationPositionMismatch(executionID: ExecutionID, bound: ExecutionPosition, logical: ExecutionPosition)
        case foreignRepresentationPayload(ExecutionID)
    }

    private var prefixes: [ExecutionID: [Int]] = [:]
    private var boundPositions: [ExecutionID: ExecutionPosition] = [:]

    public init() {}

    /// Host records the physical prefix after a generation pass: this is
    /// how the backend learns the execution's current physical state.
    public func bind(
        executionID: ExecutionID,
        position: ExecutionPosition,
        tokenPrefix: [Int]
    ) {
        prefixes[executionID] = tokenPrefix
        boundPositions[executionID] = position
    }

    /// Concrete accessor for the execution component: the bound prefix of
    /// one logical execution state, with position validation.
    public func boundPrefix(
        for state: ExecutionStateHandle
    ) throws -> (prefix: [Int], position: ExecutionPosition) {
        guard let prefix = prefixes[state.id], let bound = boundPositions[state.id] else {
            throw ExecutionStateBackendError.noBoundRepresentation(state.id)
        }
        guard bound == state.position else {
            throw ExecutionStateBackendError.representationPositionMismatch(
                executionID: state.id,
                bound: bound,
                logical: state.position
            )
        }
        return (prefix, bound)
    }

    /// Concrete accessor for the execution component: consume the CURRENT
    /// binding after the physical prefix advanced (the Runtime rebinds the
    /// advanced representation afterwards).
    func consumeBinding(for state: ExecutionStateHandle) {
        prefixes.removeValue(forKey: state.id)
        boundPositions.removeValue(forKey: state.id)
    }

    public func captureRepresentation(
        for state: ExecutionStateHandle
    ) async throws -> ExecutionRepresentation {
        let (prefix, bound) = try boundPrefix(for: state)
        return ExecutionRepresentation(
            executionID: state.id,
            position: bound,
            payload: MLXPrefixPayload(tokenPrefix: prefix)
        )
    }

    public func deriveRepresentation(
        from parent: ExecutionRepresentation,
        for child: ExecutionStateHandle
    ) async throws -> ExecutionRepresentation {
        // A fork physically copies the parent's representation at the fork
        // point; the child must fork at the parent's bound position.
        guard parent.position == child.position else {
            throw ExecutionStateBackendError.representationPositionMismatch(
                executionID: child.id,
                bound: parent.position,
                logical: child.position
            )
        }
        guard let payload = parent.payload as? MLXPrefixPayload else {
            throw ExecutionStateBackendError.foreignRepresentationPayload(child.id)
        }
        prefixes[child.id] = payload.tokenPrefix
        boundPositions[child.id] = child.position
        return ExecutionRepresentation(
            executionID: child.id,
            position: child.position,
            payload: MLXPrefixPayload(tokenPrefix: payload.tokenPrefix)
        )
    }

    public func restoreRepresentation(
        _ representation: ExecutionRepresentation
    ) async throws {
        guard let payload = representation.payload as? MLXPrefixPayload else {
            throw ExecutionStateBackendError.foreignRepresentationPayload(representation.executionID)
        }
        prefixes[representation.executionID] = payload.tokenPrefix
        boundPositions[representation.executionID] = representation.position
    }

    public func releaseRepresentation(
        _ representation: ExecutionRepresentation
    ) async throws {
        // Only the CURRENT binding is released; a stale captured snapshot
        // stays releasable at any time, but releasing it must not disturb a
        // newer binding.
        guard boundPositions[representation.executionID] == representation.position else {
            return
        }
        prefixes.removeValue(forKey: representation.executionID)
        boundPositions.removeValue(forKey: representation.executionID)
    }
}
