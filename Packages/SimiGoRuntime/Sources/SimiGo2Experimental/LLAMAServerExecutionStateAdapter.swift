import Foundation
import SimiGoRuntimeContract

/// BACKEND-1 adapter engineering — minimal real integration skeleton
/// (registration 2026-09-30: M-1…M-5 mandatory checks and the seven stop
/// conditions are in force; see SIMIGO_LAB_BACKEND1_ADAPTER_ENGINEERING_
/// AUDIT_20260930.md).
///
/// Composition of already-registered pieces (reuse, no redesign):
///   E1  ExecutionContinuityCoordinator — Runtime-owned semantic lifecycle
///   E3  LLAMAServerExecutionStateBackend — token-prefix representation
///       strategy (the same backend type already in the cross-backend
///       conformance matrix)
///   transport  LLAMAServerExecutionStateExecutor — real URLSession I/O
///
/// The adapter owns only R/T/P-layer responsibilities: transport, turn
/// serialization, model identity, and the failure/cancellation boundary.
/// It never writes an ExecutionStateHandle and adds no D-level state.
/// B1 is intentionally not part of this adapter shape: the external server
/// owns the physical model lifecycle (engineering audit, A1).
///
/// Evidence boundary: this type carries targeted adapter evidence only —
/// not a production-readiness or performance claim (M-5).
public struct LLAMAServerAdapterConfig: Sendable {
  public let baseURL: URL
  public let session: URLSession
  public let predictionTokens: Int
  public let seed: Int

  public init(
    baseURL: URL,
    session: URLSession = .shared,
    predictionTokens: Int = 16,
    seed: Int = 0
  ) {
    self.baseURL = baseURL
    self.session = session
    self.predictionTokens = predictionTokens
    self.seed = seed
  }
}

public enum LLAMAServerAdapterError: Error, Equatable, Sendable {
  /// /props failed at open: no model identity, and no semantic state exists.
  case serverUnavailable(status: Int)
  /// Adapter use before a successful open().
  case adapterNotOpen
  /// No execution with this ID is known to the adapter.
  case unknownExecution(ExecutionID)
  /// No lifecycle record exists for the requested restore position.
  case unknownPosition(executionID: ExecutionID, position: ExecutionPosition)
  /// The server did not return token identities for the completion. Fail
  /// closed: without tokens the advanced prefix cannot be derived, so the
  /// logical state must not advance.
  case missingCompletionTokens
}

/// Session-shaped composition of the registered seam pieces against a real
/// llama-server transport. Adapter-local state is R/T/P only (see the
/// engineering audit §3 for the full classification).
public final class LLAMAServerExecutionStateAdapter: @unchecked Sendable {
  private let backend: LLAMAServerExecutionStateBackend
  private let executor: LLAMAServerExecutionStateExecutor
  private let coordinator: ExecutionContinuityCoordinator
  private let config: LLAMAServerAdapterConfig
  /// Adapter-local serialization of the read-modify-write turn pipeline
  /// (boundPrefix → tokenize → complete → commit). This is adapter
  /// engineering, NOT a resolution of G-2 (coordinator locking), which
  /// stays inherited and unclosed.
  private let pipelineLock = AsyncLock()
  /// Guards open-state and model identity; never held across an await.
  private let stateLock = NSLock()
  private var openState = false
  private var openModelIdentity: String?

  public init(config: LLAMAServerAdapterConfig) {
    self.backend = LLAMAServerExecutionStateBackend()
    self.executor = LLAMAServerExecutionStateExecutor(
      baseURL: config.baseURL, session: config.session)
    self.coordinator = ExecutionContinuityCoordinator(backend: backend)
    self.config = config
  }

  /// The E3 representation strategy this adapter runs. It is the SAME
  /// backend type the cross-backend conformance matrix covers, so the
  /// adapter introduces no second set of semantic expectations.
  public var executionStateBackend: any ExecutionStateBackend { backend }

  /// P-layer model identity reported by the server at open. Observability
  /// metadata only; it never enters Execution Semantic State.
  public var modelIdentity: String? {
    stateLock.lock()
    defer { stateLock.unlock() }
    return openModelIdentity
  }

  public var isOpen: Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    return openState
  }

  /// Real transport handshake: fetch /props for model identity. Failure
  /// leaves no semantic state behind (nothing has been created yet).
  @discardableResult
  public func open() async throws -> String? {
    do {
      let props = try await executor.props()
      stateLock.withLock {
        openState = true
        openModelIdentity = props.modelPath
      }
      return props.modelPath
    } catch let error as LLAMAServerExecutorError {
      if case .badStatus(let status) = error {
        throw LLAMAServerAdapterError.serverUnavailable(status: status)
      }
      throw error
    }
  }

  private func requireOpen() throws {
    stateLock.lock()
    defer { stateLock.unlock() }
    guard openState else { throw LLAMAServerAdapterError.adapterNotOpen }
  }

  // MARK: - E1 lifecycle through the real adapter

  /// Create an execution from initial text. The tokenize happens FIRST:
  /// a tokenize failure creates nothing (fail closed, no partial state).
  /// The logical create commits before the prefix bind — the registered
  /// recovery for a missing binding is recompute, and binding this
  /// adapter's own payload type cannot fail.
  @discardableResult
  public func createExecution(id: ExecutionID, text: String) async throws
    -> ExecutionStateHandle
  {
    try requireOpen()
    await pipelineLock.lock()
    defer { pipelineLock.unlock() }
    let tokens = try await executor.tokenizeText(text)
    try Task.checkCancellation()
    let handle = try await coordinator.create(
      id: id,
      position: ExecutionPosition(0),
      continuation: ExecutionContinuation(nextInput: text, continuationID: "turn-0")
    )
    try await coordinator.bindRepresentation(
      executionID: id,
      position: ExecutionPosition(0),
      payload: LLAMAServerPrefixPayload(tokenPrefix: tokens)
    )
    return handle
  }

  /// One real turn against the server: read the current bound prefix,
  /// tokenize the user text, run a real /completion, and only on full
  /// success advance the logical state one position and bind the advanced
  /// prefix. I/O failure, mid-flight cancellation, or missing token
  /// identities leave the logical state unchanged and retryable — the
  /// physical failure can never produce a partial logical commit (T6/T7).
  @discardableResult
  public func continueTurn(id: ExecutionID, userText: String) async throws
    -> ExecutionStateHandle
  {
    try requireOpen()
    await pipelineLock.lock()
    defer { pipelineLock.unlock() }
    guard let current = coordinator.handle(id) else {
      throw LLAMAServerAdapterError.unknownExecution(id)
    }
    let (prefix, _) = try backend.boundPrefix(for: current)
    let userTokens = try await executor.tokenizeText(userText)
    let prompt = prefix + userTokens
    let completion = try await executor.complete(
      tokenPrefix: prompt, predictionTokens: config.predictionTokens, seed: config.seed)
    guard let generated = completion.tokens else {
      throw LLAMAServerAdapterError.missingCompletionTokens
    }
    // Cancellation gate: a task cancelled after paying for generation but
    // before the semantic commit discards the turn whole — no logical
    // advance, no binding change. Past this gate the commit sequence has
    // no further suspension points.
    try Task.checkCancellation()
    let advancedPrefix = prompt + generated
    let advanced = try await coordinator.continueExecution(
      current,
      continuation: ExecutionContinuation(
        nextInput: userText,
        continuationID: "turn-\(current.position.value + 1)")
    )
    try await coordinator.bindRepresentation(
      executionID: id,
      position: advanced.position,
      payload: LLAMAServerPrefixPayload(tokenPrefix: advancedPrefix)
    )
    return advanced
  }

  /// Fork at the parent's CURRENT bound position through the coordinator's
  /// transactional fork (physical derive before the child commits); the
  /// child inherits the parent's continuation at the fork point.
  @discardableResult
  public func forkExecution(parentID: ExecutionID, childID: ExecutionID) async throws
    -> ExecutionStateHandle
  {
    try requireOpen()
    await pipelineLock.lock()
    defer { pipelineLock.unlock() }
    guard let parent = coordinator.handle(parentID) else {
      throw LLAMAServerAdapterError.unknownExecution(parentID)
    }
    return try await coordinator.fork(
      ExecutionForkRequest(
        parent: parent,
        childID: childID,
        childPosition: parent.position,
        childContinuation: parent.continuation
      )
    )
  }

  /// Restore to a captured position. The restored continuation is the one
  /// the Runtime recorded for that position — the adapter does not invent
  /// semantic state. Restore failure leaves the logical state unchanged.
  @discardableResult
  public func restoreExecution(id: ExecutionID, to targetPosition: ExecutionPosition)
    async throws -> ExecutionStateHandle
  {
    try requireOpen()
    await pipelineLock.lock()
    defer { pipelineLock.unlock() }
    guard let current = coordinator.handle(id) else {
      throw LLAMAServerAdapterError.unknownExecution(id)
    }
    // If no lifecycle record exists at the position, no captured
    // representation can exist there either (every adapter binding follows
    // a lifecycle record), so the coordinator's registered
    // noRepresentationAtPosition outcome governs; the current continuation
    // is passed as a neutral value that only reaches semantic state on a
    // successful restore.
    let continuation =
      (try? restoredContinuation(for: id, at: targetPosition))
      ?? current.continuation
    return try await coordinator.restore(
      current,
      request: ExecutionRestoreRequest(
        targetPosition: targetPosition,
        continuation: continuation)
    )
  }

  @discardableResult
  public func reattachExecution(id: ExecutionID) async throws -> ExecutionStateHandle {
    try requireOpen()
    await pipelineLock.lock()
    defer { pipelineLock.unlock() }
    guard let current = coordinator.handle(id) else {
      throw LLAMAServerAdapterError.unknownExecution(id)
    }
    return try await coordinator.reattach(current)
  }

  /// Discard with the registered release-first ordering; a release failure
  /// leaves the execution resumable and retryable.
  public func discardExecution(id: ExecutionID) async throws {
    try requireOpen()
    await pipelineLock.lock()
    defer { pipelineLock.unlock() }
    guard let current = coordinator.handle(id) else {
      throw LLAMAServerAdapterError.unknownExecution(id)
    }
    try await coordinator.discard(current)
  }

  /// The logical handle as the Runtime sees it. Observability access only;
  /// the adapter never mutates a handle.
  public func handle(for id: ExecutionID) -> ExecutionStateHandle? {
    coordinator.handle(id)
  }

  private func restoredContinuation(for id: ExecutionID, at position: ExecutionPosition)
    throws -> ExecutionContinuation
  {
    if let record = coordinator.recordsSnapshot.last(where: {
      $0.executionID == id && $0.resultPosition == position
    }) {
      return record.resultContinuation
    }
    throw LLAMAServerAdapterError.unknownPosition(
      executionID: id, position: position)
  }
}
