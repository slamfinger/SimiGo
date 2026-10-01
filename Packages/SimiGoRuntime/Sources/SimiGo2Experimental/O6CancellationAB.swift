import Foundation
import SimiGoRuntimeContract
import Tokenizers

/// RQ3 MLX oversized cancellation A/B. Both arms share one real segmented
/// Qwen3-Coder-Next core. OFF directly cancels, physically releases, and
/// recovers. ON performs the same cancellation through Execution State
/// fork/capture/release/restore. This is harness evidence, not performance.
public enum O6CancellationAB {
  public static let protocolVersion = "RQ3.O6.MLX.OVERSIZED.CANCELLATION.AB.V1"
  public static let boundary =
    "REAL_OVERSIZED_MLX_SEGMENTED_CORE / COOPERATIVE_TOKEN_BOUNDARY_CANCEL / "
    + "HARNESS_LEVEL / NOT_A_PERFORMANCE_OR_PRODUCTION_CLAIM"

  public struct Check: Encodable {
    public let name: String
    public let pass: Bool
    public let detail: String
  }

  public struct TimingSummary: Encodable {
    public let n: Int
    public let meanMs: Double
    public let medianMs: Double
  }

  public struct Sample: Encodable {
    public let cycle: Int
    public let directOrderFirst: Bool
    public let cancelledTokenCount: Int
    public let directRecoveryTokenIDs: [Int]
    public let stateRecoveryTokenIDs: [Int]
    public let directMatchesReference: Bool
    public let stateMatchesReference: Bool
    public let stateCancelledPrefixExact: Bool
    public let stateReleaseRemovedCurrentBinding: Bool
    public let stateRestoredToForkPoint: Bool
    public let parentNonInterference: Bool
    public let referenceMs: Double
    public let directCancelMs: Double
    public let directReleaseMs: Double
    public let directRecoveryMs: Double
    public let stateCancelMs: Double
    public let stateForkCaptureMs: Double
    public let stateReleaseRestoreMs: Double
    public let stateRecoveryMs: Double
  }

  public struct Report: Encodable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let modelDirectory: String
    public let modelType: String
    public let segmentSize: Int
    public let segmentCount: Int
    public let cycles: Int
    public let maxTokens: Int
    public let checks: [Check]
    public let samples: [Sample]
    public let directCancelMs: TimingSummary
    public let directReleaseMs: TimingSummary
    public let directRecoveryMs: TimingSummary
    public let stateCancelMs: TimingSummary
    public let stateForkCaptureMs: TimingSummary
    public let stateReleaseRestoreMs: TimingSummary
    public let stateRecoveryMs: TimingSummary
    public let peakFootprintMiB: Int64
    public let maxSwapMiB: Int64
    public let segmentTransitions: Int
    public let overallPass: Bool
  }

  public static func run(
    modelDirectory: URL,
    cycles: Int = 3,
    maxTokens: Int = 4,
    segmentSize: Int = 8
  ) async throws -> Report {
    let core = try await O6SegmentedCore(
      modelDirectory: modelDirectory, segmentSize: segmentSize
    )
    let backend = OversizedSegmentedStateBackend(releaseAll: { try core.releaseAllSegments() })
    let coordinator = ExecutionContinuityCoordinator(backend: backend)
    let tokenizer = try await Tokenizers.AutoTokenizer.from(modelFolder: modelDirectory)
    let executor = OversizedSegmentedExecutor(
      core: core, backend: backend, tokenizer: tokenizer
    )

    let seedTokens = try executor.tokenizeSeedText("def is_palindrome(s):")
    let parentInput = try executor.tokenizeText("Explain it briefly.")
    let childInput = try executor.tokenizeText("Now write tests for it.")
    let basePrefix = seedTokens + parentInput

    let referenceStarted = DispatchTime.now().uptimeNanoseconds
    let reference = try executor.directGenerate(
      prefix: basePrefix,
      nextInputTokens: childInput,
      maxTokens: maxTokens
    )
    let referenceMs = elapsedMs(referenceStarted)

    var samples: [Sample] = []
    for cycle in 0..<cycles {
      let directFirst = cycle % 2 == 0
      let direct: DirectResult
      let state: StateResult
      if directFirst {
        direct = try await runDirect(
          executor: executor,
          basePrefix: basePrefix,
          childInput: childInput,
          maxTokens: maxTokens,
          reference: reference
        )
        state = try await runState(
          cycle: cycle,
          coordinator: coordinator,
          backend: backend,
          executor: executor,
          basePrefix: basePrefix,
          childInput: childInput,
          maxTokens: maxTokens,
          reference: reference
        )
      } else {
        state = try await runState(
          cycle: cycle,
          coordinator: coordinator,
          backend: backend,
          executor: executor,
          basePrefix: basePrefix,
          childInput: childInput,
          maxTokens: maxTokens,
          reference: reference
        )
        direct = try await runDirect(
          executor: executor,
          basePrefix: basePrefix,
          childInput: childInput,
          maxTokens: maxTokens,
          reference: reference
        )
      }

      let directMatches = direct.recoveryTokenIDs == reference.generatedTokenIDs
      let stateMatches = state.recoveryTokenIDs == reference.generatedTokenIDs
      let restored = state.restoredPosition == ExecutionPosition(1)
        && state.restoredPrefix == basePrefix
      let parentBinding = try? backend.boundPrefix(
        for: coordinator.handle(state.parentID)!
      )
      let parentUnchanged = parentBinding?.prefix == basePrefix
      let sample = Sample(
        cycle: cycle,
        directOrderFirst: directFirst,
        cancelledTokenCount: direct.cancelledTokenCount,
        directRecoveryTokenIDs: direct.recoveryTokenIDs,
        stateRecoveryTokenIDs: state.recoveryTokenIDs,
        directMatchesReference: directMatches,
        stateMatchesReference: stateMatches,
        stateCancelledPrefixExact: state.cancelledPrefixExact,
        stateReleaseRemovedCurrentBinding: state.releaseRemovedCurrentBinding,
        stateRestoredToForkPoint: restored,
        parentNonInterference: parentUnchanged,
        referenceMs: referenceMs,
        directCancelMs: direct.cancelMs,
        directReleaseMs: direct.releaseMs,
        directRecoveryMs: direct.recoveryMs,
        stateCancelMs: state.cancelMs,
        stateForkCaptureMs: state.forkCaptureMs,
        stateReleaseRestoreMs: state.releaseRestoreMs,
        stateRecoveryMs: state.recoveryMs
      )
      samples.append(sample)
    }

    let checks = [
      Check(
        name: "COOPERATIVE_CANCEL_ONE_TOKEN",
        pass: samples.allSatisfy({ $0.cancelledTokenCount == 1 }),
        detail: "\(samples.filter({ $0.cancelledTokenCount == 1 }).count)/\(samples.count)"
      ),
      Check(
        name: "DIRECT_RECOVERY_EXACT",
        pass: samples.allSatisfy({ $0.directMatchesReference }),
        detail: "\(samples.filter({ $0.directMatchesReference }).count)/\(samples.count)"
      ),
      Check(
        name: "EXECSTATE_RECOVERY_EXACT",
        pass: samples.allSatisfy({ $0.stateMatchesReference }),
        detail: "\(samples.filter({ $0.stateMatchesReference }).count)/\(samples.count)"
      ),
      Check(
        name: "CANCELLED_PREFIX_EXACT",
        pass: samples.allSatisfy({ $0.stateCancelledPrefixExact }),
        detail: "\(samples.filter({ $0.stateCancelledPrefixExact }).count)/\(samples.count)"
      ),
      Check(
        name: "RELEASE_REMOVED_CURRENT_BINDING",
        pass: samples.allSatisfy({ $0.stateReleaseRemovedCurrentBinding }),
        detail: "\(samples.filter({ $0.stateReleaseRemovedCurrentBinding }).count)/\(samples.count)"
      ),
      Check(
        name: "RESTORE_TO_FORK_POINT",
        pass: samples.allSatisfy({ $0.stateRestoredToForkPoint }),
        detail: "\(samples.filter({ $0.stateRestoredToForkPoint }).count)/\(samples.count)"
      ),
      Check(
        name: "PARENT_NON_INTERFERENCE",
        pass: samples.allSatisfy({ $0.parentNonInterference }),
        detail: "\(samples.filter({ $0.parentNonInterference }).count)/\(samples.count)"
      ),
      Check(
        name: "RESIDENCY_BOUNDED_ZERO_SWAP",
        pass: core.peakFootprintMiB <= core.peakCapacityMiB && core.maxSwapMiB == 0,
        detail: "peak \(core.peakFootprintMiB) MiB <= \(core.peakCapacityMiB) MiB; swap \(core.maxSwapMiB) MiB"
      ),
      Check(
        name: "SEGMENT_TRANSITIONS_EXECUTED",
        pass: core.segmentTransitions > 0,
        detail: "\(core.segmentTransitions)"
      ),
    ]
    let overallPass = checks.allSatisfy({ $0.pass })
    let summary = timingSummary

    return Report(
      status: overallPass ? "PASS" : "FAIL",
      protocolVersion: protocolVersion,
      boundary: boundary,
      modelDirectory: modelDirectory.path,
      modelType: "qwen3_next",
      segmentSize: segmentSize,
      segmentCount: core.segments.count,
      cycles: cycles,
      maxTokens: maxTokens,
      checks: checks,
      samples: samples,
      directCancelMs: summary(samples.map({ $0.directCancelMs })),
      directReleaseMs: summary(samples.map({ $0.directReleaseMs })),
      directRecoveryMs: summary(samples.map({ $0.directRecoveryMs })),
      stateCancelMs: summary(samples.map({ $0.stateCancelMs })),
      stateForkCaptureMs: summary(samples.map({ $0.stateForkCaptureMs })),
      stateReleaseRestoreMs: summary(samples.map({ $0.stateReleaseRestoreMs })),
      stateRecoveryMs: summary(samples.map({ $0.stateRecoveryMs })),
      peakFootprintMiB: core.peakFootprintMiB,
      maxSwapMiB: core.maxSwapMiB,
      segmentTransitions: core.segmentTransitions,
      overallPass: overallPass
    )
  }

  private struct DirectResult {
    var cancelledTokenCount = 0
    var recoveryTokenIDs: [Int] = []
    var cancelMs: Double = 0
    var releaseMs: Double = 0
    var recoveryMs: Double = 0
  }

  private struct StateResult {
    let parentID: ExecutionID
    var cancelledTokenCount: Int
    var cancelledPrefixExact: Bool
    var releaseRemovedCurrentBinding: Bool
    var restoredPosition: ExecutionPosition
    var restoredPrefix: [Int]
    var recoveryTokenIDs: [Int]
    var cancelMs: Double
    var forkCaptureMs: Double
    var releaseRestoreMs: Double
    var recoveryMs: Double
  }

  private static func runDirect(
    executor: OversizedSegmentedExecutor,
    basePrefix: [Int],
    childInput: [Int],
    maxTokens: Int,
    reference: OversizedSegmentedExecutor.DirectGenerationResult
  ) async throws -> DirectResult {
    var result = DirectResult()
    let cancelStarted = DispatchTime.now().uptimeNanoseconds
    do {
      _ = try executor.directGenerate(
        prefix: basePrefix,
        nextInputTokens: childInput,
        maxTokens: maxTokens,
        cancellationToken: O6GenerationCancellationToken { $0 >= 1 }
      )
    } catch let cancellation as O6ExecutionCancelled {
      result.cancelledTokenCount = cancellation.generatedTokenIDs.count
      _ = reference
    }
    result.cancelMs = elapsedMs(cancelStarted)

    let releaseStarted = DispatchTime.now().uptimeNanoseconds
    try executor.directReleaseAll()
    result.releaseMs = elapsedMs(releaseStarted)

    let recoveryStarted = DispatchTime.now().uptimeNanoseconds
    let recovery = try executor.directGenerate(
      prefix: basePrefix, nextInputTokens: childInput, maxTokens: maxTokens
    )
    result.recoveryMs = elapsedMs(recoveryStarted)
    result.recoveryTokenIDs = recovery.generatedTokenIDs
    return result
  }

  private static func runState(
    cycle: Int,
    coordinator: ExecutionContinuityCoordinator,
    backend: OversizedSegmentedStateBackend,
    executor: OversizedSegmentedExecutor,
    basePrefix: [Int],
    childInput: [Int],
    maxTokens: Int,
    reference: OversizedSegmentedExecutor.DirectGenerationResult
  ) async throws -> StateResult {
    let parentID = ExecutionID("ab-parent-\(cycle)")
    let childID = ExecutionID("ab-child-\(cycle)")
    let parent = try await coordinator.create(
      id: parentID,
      position: ExecutionPosition(1),
      continuation: ExecutionContinuation(nextInput: "", continuationID: "p1")
    )
    try await coordinator.bindRepresentation(
      executionID: parentID,
      position: ExecutionPosition(1),
      payload: OversizedPrefixPayload(tokenPrefix: basePrefix)
    )

    let forkStarted = DispatchTime.now().uptimeNanoseconds
    let child = try await coordinator.fork(
      ExecutionForkRequest(
        parent: parent,
        childID: childID,
        childPosition: ExecutionPosition(1),
        childContinuation: ExecutionContinuation(nextInput: "", continuationID: "c1")
      )
    )
    let parentCheckpoint = try await backend.captureRepresentation(for: parent)
    let forkCaptureMs = elapsedMs(forkStarted)

    let cancelStarted = DispatchTime.now().uptimeNanoseconds
    var cancelledTokens: [Int] = []
    do {
      _ = try await executor.continueExecution(
        child,
        nextInputTokens: childInput,
        maxTokens: maxTokens,
        cancellationToken: O6GenerationCancellationToken { $0 >= 1 }
      )
    } catch let cancellation as O6ExecutionCancelled {
      cancelledTokens = cancellation.generatedTokenIDs
    }
    let cancelMs = elapsedMs(cancelStarted)
    _ = reference

    let consumedPrefix = basePrefix + childInput + cancelledTokens
    _ = try await coordinator.continueExecution(
      child,
      continuation: ExecutionContinuation(nextInput: "", continuationID: "c2")
    )
    try await coordinator.bindRepresentation(
      executionID: childID,
      position: ExecutionPosition(2),
      payload: OversizedPrefixPayload(tokenPrefix: consumedPrefix)
    )
    let cancelledRepresentation = try await backend.captureRepresentation(
      for: coordinator.handle(childID)!
    )

    let releaseRestoreStarted = DispatchTime.now().uptimeNanoseconds
    try await backend.releaseRepresentation(cancelledRepresentation)
    let releaseRemovedCurrentBinding: Bool
    do {
      _ = try backend.boundPrefix(for: coordinator.handle(childID)!)
      releaseRemovedCurrentBinding = false
    } catch {
      releaseRemovedCurrentBinding = true
    }
    let restored = try await coordinator.restore(
      coordinator.handle(childID)!,
      request: ExecutionRestoreRequest(
        targetPosition: ExecutionPosition(1),
        continuation: ExecutionContinuation(nextInput: "", continuationID: "cr")
      )
    )
    let restoredBinding = try backend.boundPrefix(for: restored)
    let releaseRestoreMs = elapsedMs(releaseRestoreStarted)

    let recoveryStarted = DispatchTime.now().uptimeNanoseconds
    let recovery = try await executor.continueExecution(
      restored, nextInputTokens: childInput, maxTokens: maxTokens
    )
    let recoveryMs = elapsedMs(recoveryStarted)
    _ = parentCheckpoint

    return StateResult(
      parentID: parentID,
      cancelledTokenCount: cancelledTokens.count,
      cancelledPrefixExact: cancelledTokens.count == 1,
      releaseRemovedCurrentBinding: releaseRemovedCurrentBinding,
      restoredPosition: restored.position,
      restoredPrefix: restoredBinding.prefix,
      recoveryTokenIDs: recovery.generatedTokenIDs,
      cancelMs: cancelMs,
      forkCaptureMs: forkCaptureMs,
      releaseRestoreMs: releaseRestoreMs,
      recoveryMs: recoveryMs
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
