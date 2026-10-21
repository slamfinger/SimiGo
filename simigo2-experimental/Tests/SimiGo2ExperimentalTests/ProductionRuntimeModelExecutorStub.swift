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
