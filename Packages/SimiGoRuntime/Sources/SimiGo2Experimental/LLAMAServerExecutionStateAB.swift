import Foundation
import SimiGoRuntimeContract

/// RQ3 — prove the existing prefix representation is consumed by a Swift
/// llama-server transport, then compare ordinary generation OFF/ON. This is
/// a research harness, not a general-purpose inference runtime.
public enum LLAMAServerExecutionStateAB {
  public static let protocolVersion = "RQ3.LLAMA.SWIFT.EXECSTATE.HOTPATH.AB.V1"
  public static let boundary =
    "SWIFT_REPRESENTATION_CONSUMING_HTTP_CLIENT / HARNESS_LEVEL / "
    + "NO_NATIVE_KV_AUTHORITY_CHANGE / NOT_A_PERFORMANCE_OR_PRODUCTION_CLAIM"

  public struct Check: Encodable {
    public let name: String
    public let pass: Bool
    public let detail: String

    init(name: String, pass: Bool, detail: String) {
      self.name = name
      self.pass = pass
      self.detail = detail
    }
  }

  public struct Sample: Encodable {
    public let index: Int
    public let mode: String
    public let clientMs: Double
    public let stateOperationMs: Double
    public let content: String
    public let tokens: [Int]
    public let semanticIdentical: Bool
  }

  public struct SemanticSummary: Encodable {
    public let n: Int
    public let meanMs: Double
    public let medianMs: Double
    public let semanticIdentical: Int
  }

  public struct TimingSummary: Encodable {
    public let n: Int
    public let meanMs: Double
    public let medianMs: Double
  }

  public struct Report: Encodable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let host: String
    public let port: Int
    public let tokenPrefix: [Int]
    public let predictionTokens: Int
    public let seed: Int
    public let checks: [Check]
    public let samples: [Sample]
    public let results: [String: SemanticSummary]
    public let pairedOnMinusOffClientMs: TimingSummary
    public let stateOperation: TimingSummary
    public let overallPass: Bool
  }

  public static func run(
    host: String = "127.0.0.1",
    port: Int = 18080,
    samples: Int = 30,
    tokenPrefix: [Int] = [5423, 6681, 799, 3299, 25, 29018],
    predictionTokens: Int = 8,
    seed: Int = 42
  ) async throws -> Report {
    let executor = LLAMAServerExecutionStateExecutor(
      baseURL: URL(string: "http://\(host):\(port)")!)
    let backend = LLAMAServerExecutionStateBackend()
    let coordinator = ExecutionContinuityCoordinator(backend: backend)
    let root = try await coordinator.create(
      id: ExecutionID("llama-swift-root"),
      position: ExecutionPosition(0),
      continuation: ExecutionContinuation(nextInput: "", continuationID: "root-0"))
    try await coordinator.bindRepresentation(
      executionID: root.id,
      position: ExecutionPosition(0),
      payload: LLAMAServerPrefixPayload(tokenPrefix: tokenPrefix))

    let warmRepresentation = try await backend.captureRepresentation(for: root)
    let warmOff = try await executor.complete(
      tokenPrefix: tokenPrefix, predictionTokens: predictionTokens, seed: seed)
    let warmOn = try await executor.complete(
      warmRepresentation, predictionTokens: predictionTokens, seed: seed)
    let warmIdentical = warmOff == warmOn
    let reference = warmOff

    var samplesOut: [Sample] = []
    var pairedDeltas: [Double] = []
    var stateOperations: [Double] = []

    for index in 0..<samples {
      let offFirst = index % 2 == 0
      let modes: [(String, Bool)] = offFirst
        ? [("off", false), ("swift_execution_state_on", true)]
        : [("swift_execution_state_on", true), ("off", false)]

      for (mode, usesState) in modes {
        let started = DispatchTime.now().uptimeNanoseconds
        var stateOperationMs = 0.0
        let completion: LLAMAServerExecutionStateExecutor.Completion
        if usesState {
          let stateStarted = DispatchTime.now().uptimeNanoseconds
          let representation = try await backend.captureRepresentation(for: root)
          stateOperationMs = elapsedMs(stateStarted)
          completion = try await executor.complete(
            representation, predictionTokens: predictionTokens, seed: seed)
        } else {
          completion = try await executor.complete(
            tokenPrefix: tokenPrefix, predictionTokens: predictionTokens, seed: seed)
        }
        let clientMs = elapsedMs(started)
        let identical = completion == reference
        samplesOut.append(
          Sample(
            index: index,
            mode: mode,
            clientMs: clientMs,
            stateOperationMs: stateOperationMs,
            content: completion.content,
            tokens: completion.tokens ?? [],
            semanticIdentical: identical))
        if usesState {
          stateOperations.append(stateOperationMs)
        }
      }

      let off = try sample(samplesOut, index: index, mode: "off")
      let on = try sample(samplesOut, index: index, mode: "swift_execution_state_on")
      pairedDeltas.append(on.clientMs - off.clientMs)
    }

    let off = samplesOut.filter { $0.mode == "off" }
    let on = samplesOut.filter { $0.mode == "swift_execution_state_on" }
    let checks = [
      Check(
        name: "SWIFT_REPRESENTATION_PAYLOAD_CONSUMED",
        pass: warmIdentical,
        detail: "captured LLAMAServerPrefixPayload produced the warm reference"),
      Check(
        name: "OFF_SEMANTIC_STABILITY",
        pass: off.allSatisfy({ $0.semanticIdentical }),
        detail: "\(off.filter({ $0.semanticIdentical }).count)/\(off.count) matched reference"),
      Check(
        name: "SWIFT_EXECSTATE_SEMANTIC_STABILITY",
        pass: on.allSatisfy({ $0.semanticIdentical }),
        detail: "\(on.filter({ $0.semanticIdentical }).count)/\(on.count) matched reference"),
    ]
    let overallPass = checks.allSatisfy({ $0.pass })

    return Report(
      status: overallPass ? "PASS" : "FAIL",
      protocolVersion: protocolVersion,
      boundary: boundary,
      host: host,
      port: port,
      tokenPrefix: tokenPrefix,
      predictionTokens: predictionTokens,
      seed: seed,
      checks: checks,
      samples: samplesOut,
      results: [
        "off": summary(off.map({ $0.clientMs }), identical: off.filter({ $0.semanticIdentical }).count),
        "swiftExecutionStateOn": summary(
          on.map({ $0.clientMs }), identical: on.filter({ $0.semanticIdentical }).count),
      ],
      pairedOnMinusOffClientMs: timingSummary(pairedDeltas),
      stateOperation: timingSummary(stateOperations),
      overallPass: overallPass)
  }

  private static func elapsedMs(_ started: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds &- started) / 1e6
  }

  private static func sample(_ samples: [Sample], index: Int, mode: String) throws -> Sample {
    guard let value = samples.first(where: { $0.index == index && $0.mode == mode }) else {
      throw LLAMAServerExecutorError.missingSample(index: index, mode: mode)
    }
    return value
  }

  private static func summary(_ values: [Double], identical: Int) -> SemanticSummary {
    let ordered = values.sorted()
    let median = ordered.isEmpty
      ? 0
      : (ordered.count % 2 == 1
        ? ordered[ordered.count / 2]
        : (ordered[ordered.count / 2 - 1] + ordered[ordered.count / 2]) / 2)
    return SemanticSummary(
      n: values.count,
      meanMs: values.reduce(0, +) / Double(values.count),
      medianMs: median,
      semanticIdentical: identical)
  }

  private static func timingSummary(_ values: [Double]) -> TimingSummary {
    let ordered = values.sorted()
    let median = ordered.isEmpty
      ? 0
      : (ordered.count % 2 == 1
        ? ordered[ordered.count / 2]
        : (ordered[ordered.count / 2 - 1] + ordered[ordered.count / 2]) / 2)
    return TimingSummary(
      n: values.count,
      meanMs: values.reduce(0, +) / Double(values.count),
      medianMs: median)
  }
}
