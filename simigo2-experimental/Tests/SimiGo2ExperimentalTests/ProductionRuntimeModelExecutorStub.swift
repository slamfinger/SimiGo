import SimiGoRuntimeContract
@testable import SimiGo2Experimental

final class ProductionRuntimeModelExecutorStub: ProductionRuntimeModelContinuationExecutor {
  var seedTokenError: Error?
  var continuationError: Error?
  var nextInputError: Error?

  init(
    seedTokenError: Error? = nil,
    nextInputError: Error? = nil,
    continuationError: Error? = nil
  ) {
    self.seedTokenError = seedTokenError
    self.nextInputError = nextInputError
    self.continuationError = continuationError
  }

  func tokenizeText(_ text: String) async throws -> [Int] {
    if let nextInputError { throw nextInputError }
    return Array(text.utf8.prefix(24)).map(Int.init)
  }

  func tokenizeSeedText(_ text: String) async throws -> [Int] {
    if let seedTokenError { throw seedTokenError }
    return Array(text.utf8.prefix(32)).map(Int.init)
  }

  func continueExecution(
    _ state: ExecutionStateHandle,
    nextInputTokens: [Int],
    maxTokens: Int
  ) async throws -> ExecutionContinuationResult {
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
