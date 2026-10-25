import SimiGoRuntimeContract
@testable import SimiGo2Experimental

final class ProductionRuntimeModelExecutorStub: ProductionRuntimeModelContinuationExecutor {
  var seedTokenError: Error?
  var continuationError: Error?
  var nextInputError: Error?
  private let representationBackend: MLXExecutionStateBackend?
  private(set) var observedBoundPrefixCount: Int?
  /// Distinguishes genuine recovery/reuse from re-execution: a recovered ES
  /// must NOT re-tokenize the seed (which would fabricate a prefix), while
  /// `continueExecutionCallCount` counts only forward steps actually run.
  private(set) var tokenizeSeedCallCount = 0
  private(set) var tokenizeTextCallCount = 0
  private(set) var continueExecutionCallCount = 0

  // Native carrier lifecycle (model-free double) — stored here because an
  // extension cannot add stored properties.
  /// Injected failure so a test can prove the native lifecycle refuses to advance
  /// the Information Space when release does not take.
  var releaseCarrierError: Error?
  /// The mutable-storage ids this (old) carrier reports as registered, captured at
  /// release. Empty models the recompute / no-KV path.
  var simulatedRetiredStorageIDs: Set<String> = []
  /// The mutable-storage ids the FRESH carrier exposes for the handoff isolation
  /// check (a shared id with `simulatedRetiredStorageIDs` triggers refusal).
  var simulatedAdoptedStorageIDs: Set<String> = []
  private var capturedRetiredStorage: [String: Set<String>] = [:]

  init(
    seedTokenError: Error? = nil,
    nextInputError: Error? = nil,
    continuationError: Error? = nil,
    representationBackend: MLXExecutionStateBackend? = nil
  ) {
    self.seedTokenError = seedTokenError
    self.nextInputError = nextInputError
    self.continuationError = continuationError
    self.representationBackend = representationBackend
  }

  func tokenizeText(_ text: String) async throws -> [Int] {
    tokenizeTextCallCount += 1
    if let nextInputError { throw nextInputError }
    return Array(text.utf8.prefix(24)).map(Int.init)
  }

  func tokenizeSeedText(_ text: String) async throws -> [Int] {
    tokenizeSeedCallCount += 1
    if let seedTokenError { throw seedTokenError }
    return Array(text.utf8.prefix(32)).map(Int.init)
  }

  func continueExecution(
    _ state: ExecutionStateHandle,
    nextInputTokens: [Int],
    maxTokens: Int
  ) async throws -> ExecutionContinuationResult {
    continueExecutionCallCount += 1
    if let representationBackend {
      let bound = try representationBackend.boundPrefix(for: state)
      observedBoundPrefixCount = bound.prefix.count
    }
    if let continuationError { throw continuationError }
    return ExecutionContinuationResult(
      executionID: state.id,
      consumedPrefixLength: 1,
      nextInputTokenCount: nextInputTokens.count,
      generatedTokenIDs: [101, 102, 103],
      generatedText: "isolated production executor stub",
      updatedPayload: MLXPrefixPayload(tokenPrefix: [9, 18, 27])
    )
  }
}

// MARK: - Native carrier lifecycle conformance
//
// Drives the SAME retired-carrier tombstone the production executor uses (the
// real `MLXExecutionStateBackend`) so release / verify-unusable are exercised for
// real, while the mutable-storage ids are supplied directly so the shared and
// unobservable isolation branches are reachable without any model or GPU runtime.
extension ProductionRuntimeModelExecutorStub: ExecutionCarrierReleasing {
  func releaseExecutionCarrier(for state: ExecutionStateHandle) throws {
    if let releaseCarrierError { throw releaseCarrierError }
    capturedRetiredStorage[state.id.rawValue] = simulatedRetiredStorageIDs
    // Exercise the real retired-carrier tombstone on the shared backend.
    representationBackend?.releaseCarrier(for: state.id)
  }

  func verifyCarrierUnusable(for state: ExecutionStateHandle) throws {
    guard let representationBackend else {
      throw CarrierLifecycleError.releaseIncomplete(reason: "stub has no backend to retire")
    }
    guard representationBackend.isCarrierRetired(for: state.id) else {
      throw CarrierLifecycleError.releaseIncomplete(reason: "carrier not retired")
    }
    do {
      _ = try representationBackend.boundPrefix(for: state)
      throw CarrierLifecycleError.carrierStillUsable(executionID: state.id.rawValue)
    } catch let error as ExecutionStateBackendError {
      guard case .carrierReleased = error else {
        throw CarrierLifecycleError.releaseIncomplete(
          reason: "bound read failed as \(error), not carrierReleased")
      }
    }
  }

  func retiredCarrierStorageIDs(for state: ExecutionStateHandle) -> Set<String> {
    capturedRetiredStorage[state.id.rawValue] ?? []
  }

  func verifyAdoptedCarrierIsolated(
    from retiredStorageIDs: Set<String>,
    for state: ExecutionStateHandle
  ) throws {
    switch CarrierStorageIsolationEvaluator.evaluate(
      retired: retiredStorageIDs, adopting: simulatedAdoptedStorageIDs) {
    case .isolated:
      return
    case .shared(let overlap):
      throw CarrierLifecycleError.carriersShareStorage(
        executionID: state.id.rawValue, sharedBufferIDs: overlap.sorted())
    case .unobservable:
      throw CarrierLifecycleError.carrierStorageIsolationUnobservable(
        executionID: state.id.rawValue)
    }
  }
}
