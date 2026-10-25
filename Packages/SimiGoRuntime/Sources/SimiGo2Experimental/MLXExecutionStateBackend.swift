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
    /// Executions whose PHYSICAL CARRIER was explicitly released via
    /// ``releaseCarrier(for:)``. Once retired, this backend instance refuses to
    /// serve that identity on any path — bound read, restore, capture, derive or
    /// a re-bind — so the old Execution State can never reuse the old carrier.
    /// A fresh Execution State must be recovered into a NEW backend instance;
    /// the tombstone is what turns "drop the binding" into "the carrier is
    /// genuinely unusable" instead of merely "currently unbound".
    private var retiredCarriers: Set<ExecutionID> = []

    public init() {}

    /// Explicit, ONE-WAY carrier release. Drops the current physical binding and
    /// RETIRES this carrier for the execution so it can no longer serve the old
    /// ES. Deliberately stronger than ``releaseRepresentation(_:)``: that drops
    /// one captured representation but leaves the carrier re-bindable, whereas a
    /// retired carrier refuses every later bind/restore/capture/derive/read.
    /// Idempotent — releasing an already-retired carrier stays retired.
    public func releaseCarrier(for executionID: ExecutionID) {
        prefixes.removeValue(forKey: executionID)
        boundPositions.removeValue(forKey: executionID)
        retiredCarriers.insert(executionID)
    }

    /// Whether the carrier for `executionID` was retired on THIS backend instance.
    /// A retired carrier is unusable by the old ES by construction.
    public func isCarrierRetired(for executionID: ExecutionID) -> Bool {
        retiredCarriers.contains(executionID)
    }

    /// Host records the physical prefix after a generation pass: this is
    /// how the backend learns the execution's current physical state.
    /// A retired carrier is never re-armed — the write is ignored so the carrier
    /// stays unusable even against a caller that tries to re-bind it.
    public func bind(
        executionID: ExecutionID,
        position: ExecutionPosition,
        tokenPrefix: [Int]
    ) {
        guard !retiredCarriers.contains(executionID) else { return }
        prefixes[executionID] = tokenPrefix
        boundPositions[executionID] = position
    }

    /// Concrete accessor for the execution component: the bound prefix of
    /// one logical execution state, with position validation.
    public func boundPrefix(
        for state: ExecutionStateHandle
    ) throws -> (prefix: [Int], position: ExecutionPosition) {
        // The retirement tombstone wins over any (impossible) residual binding:
        // a released carrier is reported as released, not as merely unbound, so
        // the old ES cannot mistake a retired carrier for one it can rebind.
        if retiredCarriers.contains(state.id) {
            throw ExecutionStateBackendError.carrierReleased(state.id)
        }
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
        // A retired child carrier cannot be re-armed by a fork derivation.
        if retiredCarriers.contains(child.id) {
            throw ExecutionStateBackendError.carrierReleased(child.id)
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
        // Recovery into a retired carrier is the exact hazard req1 forbids: the
        // old ES must not reuse the old carrier. Refuse so a fresh carrier (a NEW
        // backend instance) is required to resume settled work.
        if retiredCarriers.contains(representation.executionID) {
            throw ExecutionStateBackendError.carrierReleased(representation.executionID)
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
