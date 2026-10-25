import CryptoKit
import Foundation
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import SimiGoRuntimeContract
import Tokenizers

/// LAB.REPCONSISTENCY.BOUNDARY — behavior-only C0/C1/C2/C3 probe for the
/// existing MLX prefix-recompute path. Experimental instrumentation only:
/// adds no integrity field and changes no production validation.
public enum RepresentationConsistencyBoundaryExperiment {
  public static let protocolVersion = "LAB.REPCONSISTENCY.BOUNDARY.V1"
  public static let boundary =
    "MLX_PREFIX_RECOMPUTE / EXECUTION_LOGIC_VS_PHYSICAL_PREFIX / "
    + "REAL_GREEDY_MLX_EXECUTION / NOT_AN_INTEGRITY_DESIGN_PROPOSAL"

  private static let executionID = ExecutionID("repconsistency-single")
  private static let seedText = """
    The project directory ReferenceFiles contains project management documents.
    """
  private static let nextInput = "What folder did I create?"
  private static let continuation = ExecutionContinuation(
    nextInput: nextInput,
    continuationID: "repconsistency-next-input"
  )

  public struct TokenObservation: Codable, Sendable, Equatable {
    public let position: Int
    public let tokenCount: Int
    public let tokenIDs: [Int]
    public let sha256: String

    init(_ tokenIDs: [Int], position: Int) {
      self.position = position
      self.tokenCount = tokenIDs.count
      self.tokenIDs = tokenIDs
      let digest = SHA256.hash(data: Data(tokenIDs.map(String.init).joined(separator: ",").utf8))
      sha256 = "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }
  }

  public struct ErrorObservation: Codable, Sendable, Equatable {
    public let kind: String
    public let message: String

    init(error: Error) {
      kind = String(describing: type(of: error))
      message = String(describing: error)
    }
  }

  public struct CaseRecord: Codable, Sendable {
    public let caseName: String
    public let executionID: String
    public let logicalPositionBefore: Int
    public let representationPosition: Int
    public let representationAcceptedByCoordinator: Bool
    public let representationAcceptedForExecution: Bool
    public let realMLXExecution: Bool
    public let detectionLayer: String
    public let detectionMechanism: String
    public let representationBefore: TokenObservation
    public let nextInputTokenCount: Int
    public let generatedTokenIDs: [Int]?
    public let generatedText: String?
    public let outputDifferenceFromC0: String?
    public let logicalPositionAfter: Int?
    public let representationAfter: TokenObservation?
    public let error: ErrorObservation?
  }

  public struct Report: Codable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let modelDirectory: String
    public let modelType: String
    public let executionID: String
    public let nextInput: String
    public let continuationID: String
    public let seed: UInt64
    public let generationMode: String
    public let maxTokens: Int
    public let c0: CaseRecord
    public let c1: CaseRecord
    public let c2Runs: [CaseRecord]
    public let c3: CaseRecord
    public let c2OutputDifferencesFromC0: [String]
    public let c2StableOutputDifference: Bool
    public let firstObservableDivergence: String
    public let controlAssessment: [String: String]
  }

  public static func run(
    modelDirectory: URL,
    maxTokens: Int,
    c2Repetitions: Int
  ) async throws -> Report {
    precondition(c2Repetitions > 0, "C2 must run at least once")
    MLXRandom.seed(42)

    let container = try await LLMModelFactory.shared.loadContainer(
      from: modelDirectory,
      using: #huggingFaceTokenizerLoader()
    )
    let modelType = await container.perform { context in
      String(describing: type(of: context.model))
    }
    let seedTokens: [Int] = await container.perform { context in
      context.tokenizer.encode(text: seedText, addSpecialTokens: true)
    }

    // Replace exactly one token while preserving array length. The +1
    // replacement cannot equal the original token in this fixture.
    let mutationIndex = min(8, max(0, seedTokens.count - 1))
    var mutatedTokens = seedTokens
    mutatedTokens[mutationIndex] += 1

    let c0 = try await runCase(
      container: container,
      caseName: "C0",
      prefix: seedTokens,
      representationPosition: 0,
      maxTokens: maxTokens,
      baseline: nil
    )

    let c1 = try await runCase(
      container: container,
      caseName: "C1",
      prefix: seedTokens,
      representationPosition: 999,
      maxTokens: maxTokens,
      baseline: c0
    )

    var c2Runs: [CaseRecord] = []
    for repetition in 1...c2Repetitions {
      MLXRandom.seed(42)
      c2Runs.append(
        try await runCase(
          container: container,
          caseName: "C2.rep\(repetition)",
          prefix: mutatedTokens,
          representationPosition: 0,
          maxTokens: maxTokens,
          baseline: c0
        )
      )
    }

    let c3 = try await runCase(
      container: container,
      caseName: "C3",
      prefix: mutatedTokens,
      representationPosition: 999,
      maxTokens: maxTokens,
      baseline: c0
    )

    let differences = c2Runs.map { $0.outputDifferenceFromC0 ?? "UNKNOWN" }
    let stable = !differences.isEmpty && differences.allSatisfy { $0 != "IDENTICAL_TO_C0" }

    let firstDivergence: String
    if !c0.realMLXExecution {
      firstDivergence = "C0 did not reach real backend execution; experiment inconclusive"
    } else if c2Runs.allSatisfy(\.realMLXExecution) {
      firstDivergence = "backend execution output"
    } else if c2Runs.contains(where: \.realMLXExecution) {
      firstDivergence = "unstable backend acceptance/execution boundary"
    } else {
      firstDivergence = "backend/representation acceptance boundary"
    }

    let control = [
      "executionID": "same (\(executionID.rawValue))",
      "logicalPositionBefore": "same (0)",
      "continuation": "same (\(continuation.continuationID))",
      "model": "same (\(modelDirectory.path))",
      "tokenizer": "same container tokenizer",
      "nextInput": "same",
      "generationMode": "same greedy argMax; MLXRandom.seed(42) reset before each run",
      "maxTokens": "same (\(maxTokens))",
      "representationLength": (seedTokens.count == mutatedTokens.count)
        ? "same (\(seedTokens.count))"
        : "CONTROL FAILURE (\(seedTokens.count) vs \(mutatedTokens.count))",
      "representationContent": "C0/C1 original; C2/C3 token index \(mutationIndex) incremented",
    ]

    return Report(
      status: "EXECUTED",
      protocolVersion: protocolVersion,
      boundary: boundary,
      modelDirectory: modelDirectory.path,
      modelType: modelType,
      executionID: executionID.rawValue,
      nextInput: nextInput,
      continuationID: continuation.continuationID,
      seed: 42,
      generationMode: "greedy argMax, cache nil, whole-prefix recompute",
      maxTokens: maxTokens,
      c0: c0,
      c1: c1,
      c2Runs: c2Runs,
      c3: c3,
      c2OutputDifferencesFromC0: differences,
      c2StableOutputDifference: stable,
      firstObservableDivergence: firstDivergence,
      controlAssessment: control
    )
  }

  private static func runCase(
    container: ModelContainer,
    caseName: String,
    prefix: [Int],
    representationPosition: Int,
    maxTokens: Int,
    baseline: CaseRecord?
  ) async throws -> CaseRecord {
    // Each case gets a fresh runtime/backend pair keyed by the SAME logical
    // ExecutionID, preventing C0 output rebinding from leaking into later cases.
    let backend = MLXExecutionStateBackend()
    let coordinator = ExecutionContinuityCoordinator(backend: backend)
    let executor = MLXPrefixRecomputeExecutor(container: container, backend: backend)

    let handle = try await coordinator.create(
      id: executionID,
      position: ExecutionPosition(0),
      continuation: continuation
    )

    var bindingAccepted = true
    var bindingError: Error?
    do {
      try await coordinator.bindRepresentation(
        executionID: executionID,
        position: ExecutionPosition(Int64(representationPosition)),
        payload: MLXPrefixPayload(tokenPrefix: prefix)
      )
    } catch {
      bindingAccepted = false
      bindingError = error
    }

    var generatedIDs: [Int]?
    var generatedText: String?
    var executionError: Error?
    var realExecution = false
    var advancedHandle = handle
    do {
      let nextTokens = try await executor.tokenizeText(nextInput)
      let result = try await executor.continueExecution(
        handle,
        nextInputTokens: nextTokens,
        maxTokens: maxTokens
      )
      realExecution = true
      generatedIDs = result.generatedTokenIDs
      generatedText = result.generatedText

      advancedHandle = try await coordinator.continueExecution(
        handle,
        continuation: continuation
      )
      try await coordinator.bindRepresentation(
        executionID: executionID,
        position: ExecutionPosition(1),
        payload: result.updatedPayload
      )
    } catch {
      executionError = error
    }

    let beforeObservation = TokenObservation(
      prefix,
      position: representationPosition
    )
    let captured = try? await backend.captureRepresentation(for: advancedHandle)
    let afterTokens = captured?.payload as? MLXPrefixPayload
    let afterObservation = afterTokens.map {
      TokenObservation($0.tokenPrefix, position: Int(advancedHandle.position.value))
    }

    let outputDifference: String?
    if let baseline, let generatedIDs {
      outputDifference =
        generatedIDs == baseline.generatedTokenIDs
        ? "IDENTICAL_TO_C0"
        : "DIFFERENT_FROM_C0(token_ids)"
    } else if generatedIDs != nil {
      outputDifference = "UNAVAILABLE_NO_C0_EXECUTION"
    } else {
      outputDifference = nil
    }

    let detection: (layer: String, mechanism: String)
    if let bindingError {
      detection = ("coordinator/backend binding", String(describing: bindingError))
    } else if let executionError {
      detection = (
        "backend bound-prefix/position check before MLX executor loop",
        String(describing: executionError)
      )
    } else {
      detection = (
        "NONE",
        "representation bound and consumed by MLXPrefixRecomputeExecutor"
      )
    }

    return CaseRecord(
      caseName: caseName,
      executionID: executionID.rawValue,
      logicalPositionBefore: Int(handle.position.value),
      representationPosition: representationPosition,
      representationAcceptedByCoordinator: bindingAccepted,
      representationAcceptedForExecution: realExecution,
      realMLXExecution: realExecution,
      detectionLayer: detection.layer,
      detectionMechanism: detection.mechanism,
      representationBefore: beforeObservation,
      nextInputTokenCount: nextInput.count,
      generatedTokenIDs: generatedIDs,
      generatedText: generatedText,
      outputDifferenceFromC0: outputDifference,
      logicalPositionAfter: Int(advancedHandle.position.value),
      representationAfter: afterObservation,
      error: executionError.map(ErrorObservation.init)
    )
  }
}
