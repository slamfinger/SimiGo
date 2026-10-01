import Foundation

/// E3 — ExecutionStateBackend contract: the Backend's REPRESENTATION
/// STRATEGY for logical execution states. Pure Swift (MLX-free target):
/// the physical payload is opaque to the Runtime.
///
/// Sovereignty boundary (Backend Boundary gate v1.0 / E0 §4):
/// implementations answer "given this logical state, what is the physical
/// representation, and can it be captured, derived, restored, released?"
/// Implementations MUST NOT create, assign, or alter Execution Identity,
/// Lineage, Position semantics, or Continuation — those belong to the
/// Runtime (E1 contract). The contract never expresses HOW the model
/// computes.

/// Opaque physical payload owned by a concrete Backend (e.g. an MLX
/// prefix-recompute strategy carries its token prefix; a future KV strategy
/// would carry its own handle type). The Runtime never interprets it.
public protocol ExecutionRepresentationPayload: Sendable {}

/// A physical representation bound to one logical execution state at one
/// logical position. The Runtime treats the payload as opaque.
public struct ExecutionRepresentation: Sendable {
    public let executionID: ExecutionID
    public let position: ExecutionPosition
    public let payload: any ExecutionRepresentationPayload

    public init(
        executionID: ExecutionID,
        position: ExecutionPosition,
        payload: any ExecutionRepresentationPayload
    ) {
        self.executionID = executionID
        self.position = position
        self.payload = payload
    }
}

public enum ExecutionStateBackendError: Error, Equatable, Sendable {
    case noBoundRepresentation(ExecutionID)
    /// The physical representation's position does not match the logical
    /// position the Runtime asked about — the Runtime MUST rebind before
    /// capturing (representation can never silently redefine position).
    case representationPositionMismatch(executionID: ExecutionID, bound: ExecutionPosition, logical: ExecutionPosition)
    /// The representation's payload was not produced by this backend.
    case foreignRepresentationPayload(ExecutionID)
}

public protocol ExecutionStateBackend: Sendable {
    /// Capture the CURRENT physical representation of a logical execution
    /// state. MUST fail if the bound representation's position does not
    /// match the logical position (no silent redefinition).
    func captureRepresentation(
        for state: ExecutionStateHandle
    ) async throws -> ExecutionRepresentation

    /// Physically DERIVE a child representation from a parent's (e.g. copy
    /// the prefix / clone the KV state) at the fork point.
    func deriveRepresentation(
        from parent: ExecutionRepresentation,
        for child: ExecutionStateHandle
    ) async throws -> ExecutionRepresentation

    /// Make the backend's physical state for `representation.executionID`
    /// match this representation again (restore semantics are the backend's
    /// strategy; the Runtime only requires that the bound position equals
    /// the representation's position afterwards).
    func restoreRepresentation(_ representation: ExecutionRepresentation) async throws

    /// Drop the physical representation (the logical Execution State
    /// survives — only the representation is released).
    func releaseRepresentation(_ representation: ExecutionRepresentation) async throws
}
