import CryptoKit
import Foundation
import SimiGoRuntimeContract

/// LAB.LLAMA.REPCONSISTENCY — minimal cross-backend replication of the MLX
/// representation-consistency observation. Uses the existing llama-server
/// prefix backend/executor; adds no integrity check and no new schema.
public enum LLAMARepresentationConsistencyExperiment {
  public static let protocolVersion = "LAB.LLAMA.REPCONSISTENCY.V1"
  public static let boundary =
    "LLAMA_SERVER_FULL_PREFIX / EXECUTION_LOGIC_VS_PHYSICAL_PREFIX / "
    + "REAL_GREEDY_LLAMA_EXECUTION / NOT_AN_INTEGRITY_DESIGN_PROPOSAL"

  public struct TokenObservation: Codable, Sendable, Equatable {
    public let position: Int
    public let tokenCount: Int
    public let tokenIDs: [Int]
    public let sha256: String
  }

  public struct CaseRecord: Codable, Sendable {
    public let caseName: String
    public let executionID: String
    public let logicalPosition: Int
    public let representationPosition: Int
    public let backendBindingAccepted: Bool
    public let realLlamaExecution: Bool
    public let generatedTokenIDs: [Int]?
    public let generatedText: String?
    public let outputDifferenceFromC0: String?
    public let logicalPositionAfter: Int
    public let error: String?
  }

  public struct Report: Codable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let serverURL: String
    public let serverModelPath: String?
    public let executionID: String
    public let seedText: String
    public let nextInput: String
    public let predictionTokens: Int
    public let seed: Int
    public let originalPrefix: TokenObservation
    public let mutatedPrefix: TokenObservation
    public let c0: CaseRecord
    public let c2Runs: [CaseRecord]
    public let c2OutputDifferencesFromC0: [String]
    public let c2StableOutputDifference: Bool
  }

  public static func run(
    serverURL: URL,
    seedText: String,
    nextInput: String,
    predictionTokens: Int,
    repetitions: Int
  ) async throws -> Report {
    precondition(repetitions > 0)
    let executor = LLAMAServerExecutionStateExecutor(baseURL: serverURL)
    let props = try await executor.props()

    let original = try await executor.tokenizeText(seedText)
    var mutated = original
    let mutationIndex = min(8, max(0, original.count - 1))
    mutated[mutationIndex] += 1

    func observation(_ tokens: [Int]) -> TokenObservation {
      TokenObservation(
        position: 0,
        tokenCount: tokens.count,
        tokenIDs: tokens,
        sha256: "sha256:"
          + SHA256.hash(
            data: Data(tokens.map(String.init).joined(separator: ",").utf8)
          ).map { String(format: "%02x", $0) }.joined()
      )
    }
    let originalObservation = observation(original)
    let mutatedObservation = observation(mutated)

    let executionID = ExecutionID("llama-repconsistency-single")
    let continuation = ExecutionContinuation(
      nextInput: nextInput,
      continuationID: "llama-repconsistency"
    )

    let c0 = try await runCase(
      executor: executor,
      caseName: "C0",
      prefix: original,
      predictionTokens: predictionTokens,
      executionID: executionID,
      continuation: continuation,
      baseline: nil
    )

    var runs: [CaseRecord] = []
    for repetition in 1...repetitions {
      runs.append(
        try await runCase(
          executor: executor,
          caseName: "C2.rep\(repetition)",
          prefix: mutated,
          predictionTokens: predictionTokens,
          executionID: executionID,
          continuation: continuation,
          baseline: c0
        )
      )
    }

    let differences = runs.map { $0.outputDifferenceFromC0 ?? "UNKNOWN" }
    let stable = !differences.isEmpty && differences.allSatisfy { $0 != "IDENTICAL_TO_C0" }

    return Report(
      status: "EXECUTED",
      protocolVersion: protocolVersion,
      boundary: boundary,
      serverURL: serverURL.absoluteString,
      serverModelPath: props.modelPath,
      executionID: executionID.rawValue,
      seedText: seedText,
      nextInput: nextInput,
      predictionTokens: predictionTokens,
      seed: 42,
      originalPrefix: originalObservation,
      mutatedPrefix: mutatedObservation,
      c0: c0,
      c2Runs: runs,
      c2OutputDifferencesFromC0: differences,
      c2StableOutputDifference: stable
    )
  }

  private static func runCase(
    executor: LLAMAServerExecutionStateExecutor,
    caseName: String,
    prefix: [Int],
    predictionTokens: Int,
    executionID: ExecutionID,
    continuation: ExecutionContinuation,
    baseline: CaseRecord?
  ) async throws -> CaseRecord {
    let backend = LLAMAServerExecutionStateBackend()
    let coordinator = ExecutionContinuityCoordinator(backend: backend)
    let handle = try await coordinator.create(
      id: executionID,
      position: ExecutionPosition(0),
      continuation: continuation
    )
    try await coordinator.bindRepresentation(
      executionID: executionID,
      position: ExecutionPosition(0),
      payload: LLAMAServerPrefixPayload(tokenPrefix: prefix)
    )

    // Real llama-server execution only happens after the backend accepts the
    // bound representation for this logical state.
    _ = try backend.boundPrefix(for: handle)
    let representation = try await backend.captureRepresentation(for: handle)
    let completion = try await executor.complete(
      representation,
      predictionTokens: predictionTokens,
      seed: 42
    )
    let advanced = try await coordinator.continueExecution(
      handle,
      continuation: continuation
    )

    let difference: String?
    if let baseline {
      difference =
        completion.tokens == baseline.generatedTokenIDs
        ? "IDENTICAL_TO_C0"
        : "DIFFERENT_FROM_C0(token_ids)"
    } else {
      difference = "BASELINE"
    }

    return CaseRecord(
      caseName: caseName,
      executionID: executionID.rawValue,
      logicalPosition: Int(handle.position.value),
      representationPosition: 0,
      backendBindingAccepted: true,
      realLlamaExecution: true,
      generatedTokenIDs: completion.tokens,
      generatedText: completion.content,
      outputDifferenceFromC0: difference,
      logicalPositionAfter: Int(advanced.position.value),
      error: nil
    )
  }
}
