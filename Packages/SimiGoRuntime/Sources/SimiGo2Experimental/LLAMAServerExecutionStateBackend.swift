import Foundation
import SimiGoRuntimeContract

/// RQ1 — non-MLX conformance vehicle.
///
/// llama-server owns computation and its native runtime cache. This adapter
/// owns only the Execution State representation strategy: the prompt-token
/// prefix that a llama-server executor resubmits. Keeping that strategy
/// separate from MLX proves the contract surface is not tied to MLX types.
public struct LLAMAServerPrefixPayload: ExecutionRepresentationPayload, Equatable, Sendable {
  public let tokenPrefix: [Int]

  public init(tokenPrefix: [Int]) {
    self.tokenPrefix = tokenPrefix
  }
}

public final class LLAMAServerExecutionStateBackend: ExecutionStateBackend, @unchecked Sendable {
  private let lock = NSLock()
  private var prefixes: [ExecutionID: [Int]] = [:]
  private var boundPositions: [ExecutionID: ExecutionPosition] = [:]

  public init() {}

  public func bind(executionID: ExecutionID, position: ExecutionPosition, tokenPrefix: [Int]) {
    lock.lock()
    defer { lock.unlock() }
    prefixes[executionID] = tokenPrefix
    boundPositions[executionID] = position
  }

  public func boundPrefix(for state: ExecutionStateHandle) throws -> (
    prefix: [Int], position: ExecutionPosition
  ) {
    lock.lock()
    defer { lock.unlock() }
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

  public func captureRepresentation(for state: ExecutionStateHandle) async throws
    -> ExecutionRepresentation
  {
    let (prefix, bound) = try boundPrefix(for: state)
    return ExecutionRepresentation(
      executionID: state.id,
      position: bound,
      payload: LLAMAServerPrefixPayload(tokenPrefix: prefix)
    )
  }

  public func deriveRepresentation(
    from parent: ExecutionRepresentation,
    for child: ExecutionStateHandle
  ) async throws -> ExecutionRepresentation {
    guard parent.position == child.position else {
      throw ExecutionStateBackendError.representationPositionMismatch(
        executionID: child.id,
        bound: parent.position,
        logical: child.position
      )
    }
    guard let payload = parent.payload as? LLAMAServerPrefixPayload else {
      throw ExecutionStateBackendError.foreignRepresentationPayload(child.id)
    }
    bind(executionID: child.id, position: child.position, tokenPrefix: payload.tokenPrefix)
    return ExecutionRepresentation(
      executionID: child.id,
      position: child.position,
      payload: LLAMAServerPrefixPayload(tokenPrefix: payload.tokenPrefix)
    )
  }

  public func restoreRepresentation(_ representation: ExecutionRepresentation) async throws {
    guard let payload = representation.payload as? LLAMAServerPrefixPayload else {
      throw ExecutionStateBackendError.foreignRepresentationPayload(representation.executionID)
    }
    bind(
      executionID: representation.executionID,
      position: representation.position,
      tokenPrefix: payload.tokenPrefix
    )
  }

  public func releaseRepresentation(_ representation: ExecutionRepresentation) async throws {
    releaseIfCurrent(representation)
  }

  private func releaseIfCurrent(_ representation: ExecutionRepresentation) {
    lock.lock()
    defer { lock.unlock() }
    // A stale snapshot cannot invalidate a newer physical binding.
    guard boundPositions[representation.executionID] == representation.position else { return }
    prefixes[representation.executionID] = nil
    boundPositions[representation.executionID] = nil
  }
}
