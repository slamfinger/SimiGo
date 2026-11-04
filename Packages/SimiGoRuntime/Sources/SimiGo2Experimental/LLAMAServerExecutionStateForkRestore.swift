import Foundation
import SimiGoRuntimeContract

/// RQ3 — live Swift fork/restore integration for the existing LLAMA prefix
/// representation. llama-server remains the inference and native-cache
/// authority; this harness only drives the contract and HTTP transport.
public enum LLAMAServerExecutionStateForkRestore {
  public static let protocolVersion = "RQ3.LLAMA.SWIFT.EXECSTATE.FORK.RESTORE.V1"
  public static let boundary =
    "SWIFT_CONTRACT_LIFECYCLE_AND_HTTP_EXECUTOR / HARNESS_LEVEL / "
    + "NO_NATIVE_KV_AUTHORITY_CHANGE / NOT_A_PERFORMANCE_OR_PRODUCTION_CLAIM"

  public struct Check: Encodable {
    public let name: String
    public let pass: Bool
    public let detail: String
  }

  public struct Sample: Encodable {
    public let index: Int
    public let referenceClientMs: Double
    public let divergenceClientMs: Double
    public let replayClientMs: Double
    public let forkCaptureMs: Double
    public let releaseRestoreMs: Double
    public let referenceContent: String
    public let divergenceContent: String
    public let replayContent: String
    public let checks: [String: Bool]
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
    public let parentTokenPrefix: [Int]
    public let divergentTokenPrefix: [Int]
    public let predictionTokens: Int
    public let seed: Int
    public let checks: [String: Int]
    public let samples: [Sample]
    public let inferenceClientMs: [String: TimingSummary]
    public let replayMinusReferenceClientMs: TimingSummary
    public let localForkCaptureMs: TimingSummary
    public let localReleaseRestoreMs: TimingSummary
    public let overallPass: Bool
  }

  public static func run(
    host: String = "127.0.0.1",
    port: Int = 18080,
    samples: Int = 30,
    parentTokenPrefix: [Int] = [5423, 6681, 799, 3299, 25, 29018],
    divergentTokenPrefix: [Int] = [
      12139, 279, 2235, 1622, 13, 3301, 6681, 25, 8029, 13053,
    ],
    predictionTokens: Int = 8,
    seed: Int = 42
  ) async throws -> Report {
    let executor = LLAMAServerExecutionStateExecutor(
      baseURL: URL(string: "http://\(host):\(port)")!)
    let warmup = try await runSample(
      index: -1,
      executor: executor,
      parentTokenPrefix: parentTokenPrefix,
      divergentTokenPrefix: divergentTokenPrefix,
      predictionTokens: predictionTokens,
      seed: seed
    )
    let reference = warmup.reference

    var samplesOut: [Sample] = []
    for index in 0..<samples {
      let result = try await runSample(
        index: index,
        executor: executor,
        parentTokenPrefix: parentTokenPrefix,
        divergentTokenPrefix: divergentTokenPrefix,
        predictionTokens: predictionTokens,
        seed: seed
      )
      samplesOut.append(
        Sample(
          index: index,
          referenceClientMs: result.referenceClientMs,
          divergenceClientMs: result.divergenceClientMs,
          replayClientMs: result.replayClientMs,
          forkCaptureMs: result.forkCaptureMs,
          releaseRestoreMs: result.releaseRestoreMs,
          referenceContent: result.reference.content,
          divergenceContent: result.divergence.content,
          replayContent: result.replay.content,
          checks: result.checks
        )
      )
      _ = reference
    }

    let counts = [
      "RESTORE_REPLAY_IDENTICAL": samplesOut.filter({ $0.checks["RESTORE_REPLAY_IDENTICAL"] == true }).count,
      "BRANCH_DIVERGED": samplesOut.filter({ $0.checks["BRANCH_DIVERGED"] == true }).count,
      "PARENT_NON_INTERFERENCE": samplesOut.filter({ $0.checks["PARENT_NON_INTERFERENCE"] == true }).count,
      "CHILD_RESTORED_TO_FORK_POINT": samplesOut.filter({ $0.checks["CHILD_RESTORED_TO_FORK_POINT"] == true }).count,
    ]
    let deltas = samplesOut.map({ $0.replayClientMs - $0.referenceClientMs })
    let overallPass = counts.values.allSatisfy({ $0 == samples })

    return Report(
      status: overallPass ? "PASS" : "FAIL",
      protocolVersion: protocolVersion,
      boundary: boundary,
      host: host,
      port: port,
      parentTokenPrefix: parentTokenPrefix,
      divergentTokenPrefix: divergentTokenPrefix,
      predictionTokens: predictionTokens,
      seed: seed,
      checks: counts,
      samples: samplesOut,
      inferenceClientMs: [
        "reference": timingSummary(samplesOut.map({ $0.referenceClientMs })),
        "divergence": timingSummary(samplesOut.map({ $0.divergenceClientMs })),
        "replayAfterRestore": timingSummary(samplesOut.map({ $0.replayClientMs })),
      ],
      replayMinusReferenceClientMs: timingSummary(deltas),
      localForkCaptureMs: timingSummary(samplesOut.map({ $0.forkCaptureMs })),
      localReleaseRestoreMs: timingSummary(samplesOut.map({ $0.releaseRestoreMs })),
      overallPass: overallPass
    )
  }

  private struct SampleResult {
    let reference: LLAMAServerExecutionStateExecutor.Completion
    let divergence: LLAMAServerExecutionStateExecutor.Completion
    let replay: LLAMAServerExecutionStateExecutor.Completion
    let referenceClientMs: Double
    let divergenceClientMs: Double
    let replayClientMs: Double
    let forkCaptureMs: Double
    let releaseRestoreMs: Double
    let checks: [String: Bool]
  }

  private static func runSample(
    index: Int,
    executor: LLAMAServerExecutionStateExecutor,
    parentTokenPrefix: [Int],
    divergentTokenPrefix: [Int],
    predictionTokens: Int,
    seed: Int
  ) async throws -> SampleResult {
    let backend = LLAMAServerExecutionStateBackend()
    let coordinator = ExecutionContinuityCoordinator(backend: backend)
    let suffix = index < 0 ? "warmup" : String(index)
    let parentID = ExecutionID("swift-parent-\(suffix)")
    let childID = ExecutionID("swift-child-\(suffix)")

    let parent = try await coordinator.create(
      id: parentID,
      position: ExecutionPosition(0),
      continuation: ExecutionContinuation(nextInput: "", continuationID: "p0")
    )
    try await coordinator.bindRepresentation(
      executionID: parentID,
      position: ExecutionPosition(0),
      payload: LLAMAServerPrefixPayload(tokenPrefix: parentTokenPrefix)
    )

    let forkStarted = DispatchTime.now().uptimeNanoseconds
    let childAtFork = try await coordinator.fork(
      ExecutionForkRequest(
        parent: parent,
        childID: childID,
        childPosition: ExecutionPosition(0),
        childContinuation: ExecutionContinuation(nextInput: "", continuationID: "c0")
      )
    )
    let parentCheckpoint = try await backend.captureRepresentation(for: parent)
    let forkCaptureMs = elapsedMs(forkStarted)

    let referenceStarted = DispatchTime.now().uptimeNanoseconds
    let reference = try await executor.complete(
      parentCheckpoint, predictionTokens: predictionTokens, seed: seed
    )
    let referenceClientMs = elapsedMs(referenceStarted)

    let parentAdvanced = try await coordinator.continueExecution(
      parent,
      continuation: ExecutionContinuation(nextInput: "", continuationID: "p1")
    )
    try await coordinator.bindRepresentation(
      executionID: parentAdvanced.id,
      position: ExecutionPosition(1),
      payload: LLAMAServerPrefixPayload(
        tokenPrefix: parentTokenPrefix + (reference.tokens ?? []))
    )

    let divergentChild = try await coordinator.continueExecution(
      childAtFork,
      continuation: ExecutionContinuation(nextInput: "", continuationID: "c1")
    )
    let divergencePrefix = parentTokenPrefix + divergentTokenPrefix
    try await coordinator.bindRepresentation(
      executionID: divergentChild.id,
      position: ExecutionPosition(1),
      payload: LLAMAServerPrefixPayload(tokenPrefix: divergencePrefix)
    )
    let divergentRepresentation = try await backend.captureRepresentation(
      for: divergentChild
    )

    let divergenceStarted = DispatchTime.now().uptimeNanoseconds
    let divergence = try await executor.complete(
      divergentRepresentation, predictionTokens: predictionTokens, seed: seed
    )
    let divergenceClientMs = elapsedMs(divergenceStarted)

    let releaseRestoreStarted = DispatchTime.now().uptimeNanoseconds
    try await backend.releaseRepresentation(divergentRepresentation)
    let restoredChild = try await coordinator.restore(
      divergentChild,
      request: ExecutionRestoreRequest(
        targetPosition: ExecutionPosition(0),
        continuation: ExecutionContinuation(nextInput: "", continuationID: "cr")
      )
    )
    let restoredRepresentation = try await backend.captureRepresentation(
      for: restoredChild
    )
    let releaseRestoreMs = elapsedMs(releaseRestoreStarted)
    let childBinding = try backend.boundPrefix(for: restoredChild)

    let replayStarted = DispatchTime.now().uptimeNanoseconds
    let replay = try await executor.complete(
      restoredRepresentation, predictionTokens: predictionTokens, seed: seed
    )
    let replayClientMs = elapsedMs(replayStarted)

    try await coordinator.bindRepresentation(
      executionID: restoredChild.id,
      position: ExecutionPosition(1),
      payload: LLAMAServerPrefixPayload(
        tokenPrefix: parentTokenPrefix + (replay.tokens ?? []))
    )

    let parentBinding = try backend.boundPrefix(for: parentAdvanced)
    let checks = [
      "RESTORE_REPLAY_IDENTICAL":
        replay == reference,
      "BRANCH_DIVERGED":
        divergence != reference,
      "PARENT_NON_INTERFERENCE":
        parentBinding.prefix == parentTokenPrefix + (reference.tokens ?? [])
          && parentBinding.position == ExecutionPosition(1),
      "CHILD_RESTORED_TO_FORK_POINT":
        childBinding.prefix == parentTokenPrefix
          && childBinding.position == ExecutionPosition(0),
    ]

    return SampleResult(
      reference: reference,
      divergence: divergence,
      replay: replay,
      referenceClientMs: referenceClientMs,
      divergenceClientMs: divergenceClientMs,
      replayClientMs: replayClientMs,
      forkCaptureMs: forkCaptureMs,
      releaseRestoreMs: releaseRestoreMs,
      checks: checks
    )
  }

  private static func elapsedMs(_ started: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds &- started) / 1e6
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
      medianMs: median
    )
  }
}
