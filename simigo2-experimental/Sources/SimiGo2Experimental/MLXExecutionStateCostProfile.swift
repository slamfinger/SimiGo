import Foundation
import SimiGoRuntimeContract
import Tokenizers

/// Phase-6 cost observation for the oversized MLX prefix-recompute path.
/// This records paired direct-vs-state generations and lifecycle operations;
/// it is not a throughput benchmark or production performance claim.
public enum MLXExecutionStateCostProfile {
  public struct TimingSummary: Encodable, Sendable {
    public let n: Int
    public let meanMs: Double
    public let medianMs: Double
    public let p95Ms: Double
    public let minMs: Double
    public let maxMs: Double
  }

  public struct PairedSample: Encodable, Sendable {
    public let index: Int
    public let directFirst: Bool
    public let directGenerationMs: Double
    public let stateGenerationMs: Double
    public let stateBindMs: Double
    public let stateCaptureMs: Double
    public let stateAdvanceMs: Double
    public let stateReleaseStaleMs: Double
    public let stateLocalMs: Double
    public let pairedStateMinusDirectMs: Double
    public let semanticIdentical: Bool
  }

  public struct LifecycleSample: Encodable, Sendable {
    public let index: Int
    public let captureMs: Double
    public let forkMs: Double
    public let divergentGenerationMs: Double
    public let divergentAdvanceMs: Double
    public let captureDivergentMs: Double
    public let releaseMs: Double
    public let restoreMs: Double
    public let replayGenerationMs: Double
    public let replayAdvanceMs: Double
    public let lifecycleLocalMs: Double
    public let replayMatchesReference: Bool
    public let branchDiverged: Bool
    public let parentNonInterference: Bool
  }

  public struct Report: Encodable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let modelDirectory: String
    public let segmentSize: Int
    public let segmentCount: Int
    public let seedText: String
    public let rootInput: String
    public let branchInput: String
    public let maxTokens: Int
    public let pairedCycles: Int
    public let lifecycleCycles: Int
    public let pairedSamples: [PairedSample]
    public let lifecycleSamples: [LifecycleSample]
    public let directGenerationMs: TimingSummary
    public let stateGenerationMs: TimingSummary
    public let pairedStateMinusDirectMs: TimingSummary
    public let stateLocalMs: TimingSummary
    public let lifecycleCaptureMs: TimingSummary
    public let lifecycleForkMs: TimingSummary
    public let lifecycleReleaseMs: TimingSummary
    public let lifecycleRestoreMs: TimingSummary
    public let lifecycleLocalMs: TimingSummary
    public let checks: [String: Bool]
    public let peakFootprintMiB: Int64
    public let maxSwapMiB: Int64
    public let segmentTransitions: Int
    public let overallPass: Bool
  }

  public static let protocolVersion = "LAB.MLX.EXECSTATE.COST.PROFILE.V1"
  public static let boundary =
    "OVERSIZED_MLX_PREFIX_RECOMPUTE / PAIRED_COST_OBSERVATION / "
    + "CAPTURE_FORK_RELEASE_RESTORE_REPLAY / NOT_A_PERFORMANCE_BENCHMARK"

  public static func run(
    modelDirectory: URL,
    seedText: String = "def is_palindrome(s):",
    rootInput: String = "Explain it briefly.",
    branchInput: String = "Now write tests for it.",
    divergentInput: String = "Add a one-line TODO.",
    maxTokens: Int = 2,
    pairedCycles: Int = 3,
    lifecycleCycles: Int = 2,
    segmentSize: Int = 8
  ) async throws -> Report {
    precondition(pairedCycles > 0 && lifecycleCycles > 0, "cycle counts must be positive")
    let core = try await O6SegmentedCore(
      modelDirectory: modelDirectory, segmentSize: segmentSize
    )
    let backend = OversizedSegmentedStateBackend(
      releaseAll: { try core.releaseAllSegments() }
    )
    let runtime = ExecutionContinuityCoordinator(backend: backend)
    let tokenizer = try await Tokenizers.AutoTokenizer.from(modelFolder: modelDirectory)
    let executor = OversizedSegmentedExecutor(
      core: core, backend: backend, tokenizer: tokenizer
    )
    let seedTokens = try executor.tokenizeSeedText(seedText)
    let rootTokens = try executor.tokenizeText(rootInput)
    let branchTokens = try executor.tokenizeText(branchInput)
    let divergentTokens = try executor.tokenizeText(divergentInput)

    func summary(_ values: [Double]) -> TimingSummary {
      let sorted = values.sorted()
      let p95Index = max(0, Int((Double(sorted.count - 1) * 0.95).rounded()))
      return TimingSummary(
        n: values.count,
        meanMs: values.reduce(0, +) / Double(max(values.count, 1)),
        medianMs: sorted.count % 2 == 1
          ? sorted[sorted.count / 2]
          : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2,
        p95Ms: sorted[p95Index],
        minMs: sorted.first ?? 0,
        maxMs: sorted.last ?? 0
      )
    }

    var pairedSamples: [PairedSample] = []
    for index in 0..<pairedCycles {
      let directFirst = index % 2 == 0
      var directMs = 0.0
      var directResult: OversizedSegmentedExecutor.DirectGenerationResult?
      var stateMs = 0.0
      var stateResult: ExecutionContinuationResult?
      var bindMs = 0.0
      var captureMs = 0.0
      var advanceMs = 0.0
      var releaseStaleMs = 0.0

      func runDirect() throws {
        let started = DispatchTime.now().uptimeNanoseconds
        directResult = try executor.directGenerate(
          prefix: seedTokens, nextInputTokens: rootTokens, maxTokens: maxTokens
        )
        directMs = elapsedMs(started)
      }

      func runState() async throws {
        let rootID = ExecutionID("cost-state-root-\(index)")
        let root = try await runtime.create(
          id: rootID,
          position: ExecutionPosition(0),
          continuation: ExecutionContinuation(nextInput: rootInput, continuationID: "state-0")
        )
        var started = DispatchTime.now().uptimeNanoseconds
        try await runtime.bindRepresentation(
          executionID: rootID,
          position: ExecutionPosition(0),
          payload: OversizedPrefixPayload(tokenPrefix: seedTokens)
        )
        bindMs = elapsedMs(started)

        started = DispatchTime.now().uptimeNanoseconds
        let checkpoint = try await backend.captureRepresentation(for: root)
        captureMs = elapsedMs(started)

        started = DispatchTime.now().uptimeNanoseconds
        let generated = try await executor.continueExecution(
          root, nextInputTokens: rootTokens, maxTokens: maxTokens
        )
        stateMs = elapsedMs(started)
        stateResult = generated

        started = DispatchTime.now().uptimeNanoseconds
        let advanced = try await runtime.continueExecution(
          root,
          continuation: ExecutionContinuation(nextInput: rootInput, continuationID: "state-1")
        )
        try await runtime.bindRepresentation(
          executionID: advanced.id,
          position: ExecutionPosition(1),
          payload: generated.updatedPayload
        )
        advanceMs = elapsedMs(started)

        started = DispatchTime.now().uptimeNanoseconds
        try await backend.releaseRepresentation(checkpoint)
        releaseStaleMs = elapsedMs(started)
      }

      if directFirst {
        try runDirect()
        try await runState()
      } else {
        try await runState()
        try runDirect()
      }

      let direct = try XCTUnwrapOptional(directResult)
      let state = try XCTUnwrapOptional(stateResult)
      let local = bindMs + captureMs + advanceMs + releaseStaleMs
      pairedSamples.append(
        PairedSample(
          index: index,
          directFirst: directFirst,
          directGenerationMs: directMs,
          stateGenerationMs: stateMs,
          stateBindMs: bindMs,
          stateCaptureMs: captureMs,
          stateAdvanceMs: advanceMs,
          stateReleaseStaleMs: releaseStaleMs,
          stateLocalMs: local,
          pairedStateMinusDirectMs: stateMs - directMs,
          semanticIdentical:
            direct.generatedTokenIDs == state.generatedTokenIDs
            && direct.updatedPrefix == seedTokens + rootTokens + state.generatedTokenIDs
        )
      )
    }

    var lifecycleSamples: [LifecycleSample] = []
    for index in 0..<lifecycleCycles {
      let suffix = String(index)
      let parentID = ExecutionID("cost-parent-\(suffix)")
      let childID = ExecutionID("cost-child-\(suffix)")

      let referenceStarted = DispatchTime.now().uptimeNanoseconds
      let reference = try executor.directGenerate(
        prefix: seedTokens, nextInputTokens: branchTokens, maxTokens: maxTokens
      )
      let referenceMs = elapsedMs(referenceStarted)

      let parent = try await runtime.create(
        id: parentID,
        position: ExecutionPosition(0),
        continuation: ExecutionContinuation(nextInput: branchInput, continuationID: "parent-0")
      )
      try await runtime.bindRepresentation(
        executionID: parentID,
        position: ExecutionPosition(0),
        payload: OversizedPrefixPayload(tokenPrefix: seedTokens)
      )

      var started = DispatchTime.now().uptimeNanoseconds
      let parentCheckpoint = try await backend.captureRepresentation(for: parent)
      let captureMs = elapsedMs(started)

      started = DispatchTime.now().uptimeNanoseconds
      let child = try await runtime.fork(
        ExecutionForkRequest(
          parent: parent,
          childID: childID,
          childPosition: ExecutionPosition(0),
          childContinuation: ExecutionContinuation(
            nextInput: branchInput, continuationID: "child-0"
          )
        )
      )
      let forkMs = elapsedMs(started)

      started = DispatchTime.now().uptimeNanoseconds
      let divergent = try await executor.continueExecution(
        child, nextInputTokens: divergentTokens, maxTokens: maxTokens
      )
      let divergentGenerationMs = elapsedMs(started)

      started = DispatchTime.now().uptimeNanoseconds
      let divergentAdvanced = try await runtime.continueExecution(
        child,
        continuation: ExecutionContinuation(nextInput: divergentInput, continuationID: "child-1")
      )
      try await runtime.bindRepresentation(
        executionID: divergentAdvanced.id,
        position: ExecutionPosition(1),
        payload: divergent.updatedPayload
      )
      let divergentAdvanceMs = elapsedMs(started)

      started = DispatchTime.now().uptimeNanoseconds
      let divergentCheckpoint = try await backend.captureRepresentation(
        for: divergentAdvanced
      )
      let captureDivergentMs = elapsedMs(started)

      started = DispatchTime.now().uptimeNanoseconds
      try await backend.releaseRepresentation(divergentCheckpoint)
      let releaseMs = elapsedMs(started)

      started = DispatchTime.now().uptimeNanoseconds
      let restoredChild = try await runtime.restore(
        divergentAdvanced,
        request: ExecutionRestoreRequest(
          targetPosition: ExecutionPosition(0),
          continuation: ExecutionContinuation(
            nextInput: branchInput, continuationID: "child-restore"
          )
        )
      )
      let restoreMs = elapsedMs(started)

      started = DispatchTime.now().uptimeNanoseconds
      let replay = try await executor.continueExecution(
        restoredChild, nextInputTokens: branchTokens, maxTokens: maxTokens
      )
      let replayGenerationMs = elapsedMs(started)

      started = DispatchTime.now().uptimeNanoseconds
      let replayAdvanced = try await runtime.continueExecution(
        restoredChild,
        continuation: ExecutionContinuation(nextInput: branchInput, continuationID: "child-2")
      )
      try await runtime.bindRepresentation(
        executionID: replayAdvanced.id,
        position: ExecutionPosition(1),
        payload: replay.updatedPayload
      )
      let replayAdvanceMs = elapsedMs(started)

      let parentBinding = try backend.boundPrefix(for: parent)
      let childBinding = try backend.boundPrefix(for: replayAdvanced)
      let lifecycleLocal =
        captureMs + forkMs + divergentAdvanceMs + captureDivergentMs + releaseMs
        + restoreMs + replayAdvanceMs
      lifecycleSamples.append(
        LifecycleSample(
          index: index,
          captureMs: captureMs,
          forkMs: forkMs,
          divergentGenerationMs: divergentGenerationMs,
          divergentAdvanceMs: divergentAdvanceMs,
          captureDivergentMs: captureDivergentMs,
          releaseMs: releaseMs,
          restoreMs: restoreMs,
          replayGenerationMs: replayGenerationMs,
          replayAdvanceMs: replayAdvanceMs,
          lifecycleLocalMs: lifecycleLocal,
          replayMatchesReference:
            replay.generatedTokenIDs == reference.generatedTokenIDs
            && (replay.updatedPayload as? OversizedPrefixPayload)?.tokenPrefix
              == seedTokens + branchTokens + replay.generatedTokenIDs,
          branchDiverged:
            divergent.generatedTokenIDs != reference.generatedTokenIDs,
          parentNonInterference:
            parentBinding.prefix == seedTokens
            && childBinding.prefix == seedTokens + branchTokens + replay.generatedTokenIDs
        )
      )
      _ = parentCheckpoint
      _ = referenceMs
    }

    let directValues = pairedSamples.map(\.directGenerationMs)
    let stateValues = pairedSamples.map(\.stateGenerationMs)
    let pairedValues = pairedSamples.map(\.pairedStateMinusDirectMs)
    let stateLocalValues = pairedSamples.map(\.stateLocalMs)
    let checks = [
      "PAIRED_SEMANTICS_STABLE":
        pairedSamples.count == pairedCycles
        && pairedSamples.allSatisfy(\.semanticIdentical),
      "LIFECYCLE_REPLAY_EXACT":
        lifecycleSamples.count == lifecycleCycles
        && lifecycleSamples.allSatisfy(\.replayMatchesReference),
      "LIFECYCLE_BRANCH_DIVERGED":
        lifecycleSamples.allSatisfy(\.branchDiverged),
      "PARENT_NON_INTERFERENCE":
        lifecycleSamples.allSatisfy(\.parentNonInterference),
      "OVERSIZED_PROFILE_UNDER_30GIB":
        core.segments.count > 1 && core.peakFootprintMiB <= 30 * 1024,
    ]

    return Report(
      status: checks.values.allSatisfy(\.self) ? "PASS" : "FAIL",
      protocolVersion: protocolVersion,
      boundary: boundary,
      modelDirectory: modelDirectory.path,
      segmentSize: segmentSize,
      segmentCount: core.segments.count,
      seedText: seedText,
      rootInput: rootInput,
      branchInput: branchInput,
      maxTokens: maxTokens,
      pairedCycles: pairedCycles,
      lifecycleCycles: lifecycleCycles,
      pairedSamples: pairedSamples,
      lifecycleSamples: lifecycleSamples,
      directGenerationMs: summary(directValues),
      stateGenerationMs: summary(stateValues),
      pairedStateMinusDirectMs: summary(pairedValues),
      stateLocalMs: summary(stateLocalValues),
      lifecycleCaptureMs: summary(lifecycleSamples.map(\.captureMs)),
      lifecycleForkMs: summary(lifecycleSamples.map(\.forkMs)),
      lifecycleReleaseMs: summary(lifecycleSamples.map(\.releaseMs)),
      lifecycleRestoreMs: summary(lifecycleSamples.map(\.restoreMs)),
      lifecycleLocalMs: summary(lifecycleSamples.map(\.lifecycleLocalMs)),
      checks: checks,
      peakFootprintMiB: core.peakFootprintMiB,
      maxSwapMiB: core.maxSwapMiB,
      segmentTransitions: core.segmentTransitions,
      overallPass: checks.values.allSatisfy(\.self)
    )
  }

  private static func XCTUnwrapOptional<T>(_ value: T?) throws -> T {
    guard let value else {
      throw ExecutionStateBackendError.noBoundRepresentation(ExecutionID("missing-cost-result"))
    }
    return value
  }

  private static func elapsedMs(_ started: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds &- started) / 1e6
  }
}

extension MLXExecutionStateCostProfile {
  public struct ScaleSample: Encodable, Sendable {
    public let tokenLength: Int
    public let pairIndex: Int
    public let directFirst: Bool
    public let directGenerationMs: Double
    public let stateGenerationMs: Double
    public let pairedStateMinusDirectMs: Double
    public let directTokensPerSec: Double
    public let stateTokensPerSec: Double
    public let stateLocalMs: Double
    public let footprintMiB: Int64
    public let semanticIdentical: Bool
  }

  public struct ScalePoint: Encodable, Sendable {
    public let tokenLength: Int
    public let pairs: Int
    public let directMeanMs: Double
    public let stateMeanMs: Double
    public let pairedStateMinusDirectMeanMs: Double
    public let directTokensPerSec: Double
    public let stateTokensPerSec: Double
    public let stateLocalMeanMs: Double
    public let peakFootprintMiB: Int64
    public let allSemanticIdentical: Bool
  }

  public struct ScaleReport: Encodable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let modelDirectory: String
    public let segmentSize: Int
    public let segmentCount: Int
    public let seedText: String
    public let rootInput: String
    public let tokenLengths: [Int]
    public let pairsPerLength: Int
    public let maxTokens: Int
    public let points: [ScalePoint]
    public let samples: [ScaleSample]
    public let checks: [String: Bool]
    public let peakFootprintMiB: Int64
    public let maxSwapMiB: Int64
    public let segmentTransitions: Int
    public let overallPass: Bool
  }

  public static let scaleProtocolVersion = "LAB.MLX.EXECSTATE.COST.SCALE.V1"
  public static let scaleBoundary =
    "OVERSIZED_MLX_PREFIX_RECOMPUTE / TOKEN_LENGTH_SCALE_OBSERVATION / "
    + "SMALL_SAMPLE / NOT_A_PERFORMANCE_BENCHMARK"

  public static func runScaleSweep(
    modelDirectory: URL,
    seedText: String = "def is_palindrome(s):",
    rootInput: String = "Explain it briefly.",
    tokenLengths: [Int] = [8, 64, 256],
    pairsPerLength: Int = 2,
    maxTokens: Int = 1,
    segmentSize: Int = 8
  ) async throws -> ScaleReport {
    precondition(!tokenLengths.isEmpty && tokenLengths.allSatisfy({ $0 > 0 }))
    precondition(pairsPerLength > 0 && maxTokens > 0)
    let core = try await O6SegmentedCore(
      modelDirectory: modelDirectory, segmentSize: segmentSize
    )
    let backend = OversizedSegmentedStateBackend(
      releaseAll: { try core.releaseAllSegments() }
    )
    let tokenizer = try await Tokenizers.AutoTokenizer.from(modelFolder: modelDirectory)
    let executor = OversizedSegmentedExecutor(
      core: core,
      backend: backend,
      tokenizer: tokenizer
    )
    let seedTokens = try executor.tokenizeSeedText(seedText)
    let rootTokens = try executor.tokenizeText(rootInput)

    _ = try executor.directGenerate(
      prefix: seedTokens, nextInputTokens: rootTokens, maxTokens: 1
    )
    try core.releaseAllSegments()

    var samples: [ScaleSample] = []
    for tokenLength in tokenLengths {
      var pointFootprint: Int64 = 0
      for pairIndex in 0..<pairsPerLength {
        let directFirst = pairIndex % 2 == 0
        let prefix = makePrefix(
          seedTokens: seedTokens,
          fillerTokens: try executor.tokenizeText(
            "Explain the tradeoff, then list a concise implementation plan "
              + "with tests, failure modes, and rollback steps."
          ),
          length: tokenLength
        )
        let runtime = ExecutionContinuityCoordinator(
          backend: backend
        )
        let rootID = ExecutionID("scale-\(tokenLength)-\(pairIndex)")
        let root = try await runtime.create(
          id: rootID,
          position: ExecutionPosition(0),
          continuation: ExecutionContinuation(nextInput: rootInput, continuationID: "state-0")
        )
        try await runtime.bindRepresentation(
          executionID: rootID,
          position: ExecutionPosition(0),
          payload: OversizedPrefixPayload(tokenPrefix: prefix)
        )

        var directMs = 0.0
        var directResult: OversizedSegmentedExecutor.DirectGenerationResult?
        var stateMs = 0.0
        var stateResult: ExecutionContinuationResult?
        var stateLocalMs = 0.0

        func runDirect() throws {
          let started = DispatchTime.now().uptimeNanoseconds
          directResult = try executor.directGenerate(
            prefix: prefix, nextInputTokens: rootTokens, maxTokens: maxTokens
          )
          directMs = elapsedMs(started)
        }

        func runState() async throws {
          let captureStarted = DispatchTime.now().uptimeNanoseconds
          let checkpoint = try await backendCapture(
            backend, root
          )
          let captureMs = elapsedMs(captureStarted)
          let generatedStarted = DispatchTime.now().uptimeNanoseconds
          let generated = try await executor.continueExecution(
            root, nextInputTokens: rootTokens, maxTokens: maxTokens
          )
          stateMs = elapsedMs(generatedStarted)
          stateResult = generated

          let advanceStarted = DispatchTime.now().uptimeNanoseconds
          let advanced = try await runtime.continueExecution(
            root,
            continuation: ExecutionContinuation(
              nextInput: rootInput, continuationID: "state-1"
            )
          )
          try await runtime.bindRepresentation(
            executionID: advanced.id,
            position: ExecutionPosition(1),
            payload: generated.updatedPayload
          )
          try await backend.releaseRepresentation(checkpoint)
          let advanceReleaseMs = elapsedMs(advanceStarted)
          stateLocalMs = captureMs + advanceReleaseMs
        }

        if directFirst {
          try runDirect()
          try await runState()
        } else {
          try await runState()
          try runDirect()
        }

        let direct = try XCTUnwrapOptional(directResult)
        let state = try XCTUnwrapOptional(stateResult)
        let identical =
          direct.generatedTokenIDs == state.generatedTokenIDs
          && (state.updatedPayload as? OversizedPrefixPayload)?.tokenPrefix
            == prefix + rootTokens + state.generatedTokenIDs
        pointFootprint = max(pointFootprint, core.gauge().footprintMiB)

        samples.append(
          ScaleSample(
            tokenLength: tokenLength,
            pairIndex: pairIndex,
            directFirst: directFirst,
            directGenerationMs: directMs,
            stateGenerationMs: stateMs,
            pairedStateMinusDirectMs: stateMs - directMs,
            directTokensPerSec: Double(maxTokens) / (directMs / 1000),
            stateTokensPerSec: Double(maxTokens) / (stateMs / 1000),
            stateLocalMs: stateLocalMs,
            footprintMiB: core.gauge().footprintMiB,
            semanticIdentical: identical
          )
        )
        try core.releaseAllSegments()
      }
      _ = pointFootprint
    }

    var points: [ScalePoint] = []
    for tokenLength in tokenLengths {
      let group = samples.filter { $0.tokenLength == tokenLength }
      let direct = group.map(\.directGenerationMs)
      let state = group.map(\.stateGenerationMs)
      let delta = group.map(\.pairedStateMinusDirectMs)
      let local = group.map(\.stateLocalMs)
      points.append(
        ScalePoint(
          tokenLength: tokenLength,
          pairs: group.count,
          directMeanMs: mean(direct),
          stateMeanMs: mean(state),
          pairedStateMinusDirectMeanMs: mean(delta),
          directTokensPerSec: Double(maxTokens * group.count) / (mean(direct) / 1000),
          stateTokensPerSec: Double(maxTokens * group.count) / (mean(state) / 1000),
          stateLocalMeanMs: mean(local),
          peakFootprintMiB: group.map(\.footprintMiB).max() ?? 0,
          allSemanticIdentical: group.allSatisfy(\.semanticIdentical)
        )
      )
    }

    let checks = [
      "ALL_SCALE_SEMANTICS_STABLE":
        samples.count == tokenLengths.count * pairsPerLength
        && samples.allSatisfy(\.semanticIdentical),
      "ALL_LENGTHS_OBSERVED":
        Set(samples.map(\.tokenLength)) == Set(tokenLengths)
        && tokenLengths.allSatisfy({ length in
          samples.filter { $0.tokenLength == length }.count == pairsPerLength
        }),
      "OVERSIZED_PROFILE_UNDER_30GIB":
        core.segments.count > 1 && core.peakFootprintMiB <= 30 * 1024,
    ]

    return ScaleReport(
      status: checks.values.allSatisfy(\.self) ? "PASS" : "FAIL",
      protocolVersion: scaleProtocolVersion,
      boundary: scaleBoundary,
      modelDirectory: modelDirectory.path,
      segmentSize: segmentSize,
      segmentCount: core.segments.count,
      seedText: seedText,
      rootInput: rootInput,
      tokenLengths: tokenLengths,
      pairsPerLength: pairsPerLength,
      maxTokens: maxTokens,
      points: points,
      samples: samples,
      checks: checks,
      peakFootprintMiB: core.peakFootprintMiB,
      maxSwapMiB: core.maxSwapMiB,
      segmentTransitions: core.segmentTransitions,
      overallPass: checks.values.allSatisfy(\.self)
    )
  }

  private static func makePrefix(
    seedTokens: [Int], fillerTokens: [Int], length: Int
  ) -> [Int] {
    precondition(length >= seedTokens.count, "token length must include seed")
    var tokens = seedTokens
    while tokens.count < length {
      tokens.append(contentsOf: fillerTokens)
    }
    return Array(tokens.prefix(length))
  }

  private static func backendCapture(
    _ backend: OversizedSegmentedStateBackend, _ state: ExecutionStateHandle
  ) async throws -> ExecutionRepresentation {
    try await backend.captureRepresentation(for: state)
  }

  private static func mean(_ values: [Double]) -> Double {
    values.reduce(0, +) / Double(max(values.count, 1))
  }
}

extension MLXExecutionStateCostProfile {
  public struct ReleaseSample: Encodable, Sendable {
    public let tokenLength: Int
    public let index: Int
    public let captureCheckpointMs: Double
    public let captureCurrentMs: Double
    public let currentReleaseMs: Double
    public let currentReleaseTransitionDelta: Int
    public let restoreMs: Double
    public let staleReleaseNoopMs: Double
    public let staleReleaseTransitionDelta: Int
    public let footprintMiB: Int64
    public let currentRemoved: Bool
    public let restoreReboundCheckpoint: Bool
    public let staleNoopPreservedCheckpoint: Bool
  }

  public struct ReleasePoint: Encodable, Sendable {
    public let tokenLength: Int
    public let samples: Int
    public let captureCheckpointMeanMs: Double
    public let captureCurrentMeanMs: Double
    public let currentReleaseMeanMs: Double
    public let restoreMeanMs: Double
    public let staleReleaseNoopMeanMs: Double
    public let staleOverCurrentMeanRatio: Double
  }

  public struct ReleaseReport: Encodable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let modelDirectory: String
    public let segmentSize: Int
    public let segmentCount: Int
    public let tokenLengths: [Int]
    public let samplesPerLength: Int
    public let points: [ReleasePoint]
    public let samples: [ReleaseSample]
    public let captureCheckpointMs: TimingSummary
    public let captureCurrentMs: TimingSummary
    public let currentReleaseMs: TimingSummary
    public let restoreMs: TimingSummary
    public let staleReleaseNoopMs: TimingSummary
    public let checks: [String: Bool]
    public let peakFootprintMiB: Int64
    public let maxSwapMiB: Int64
    public let segmentTransitions: Int
    public let overallPass: Bool
  }

  public static let releaseProtocolVersion = "LAB.MLX.EXECSTATE.RELEASE.COST.V1"
  public static let releaseBoundary =
    "OVERSIZED_MLX_RELEASE_ACTION_ISOLATION / CURRENT_VS_STALE_NOOP / "
    + "NO_GENERATION / SMALL_SAMPLE / NOT_A_PERFORMANCE_BENCHMARK"

  public static func runReleaseCostProfile(
    modelDirectory: URL,
    seedText: String = "def is_palindrome(s):",
    tokenLengths: [Int] = [8, 64, 256],
    samplesPerLength: Int = 10,
    segmentSize: Int = 8
  ) async throws -> ReleaseReport {
    precondition(!tokenLengths.isEmpty && tokenLengths.allSatisfy({ $0 > 0 }))
    precondition(samplesPerLength > 0)
    let core = try await O6SegmentedCore(
      modelDirectory: modelDirectory, segmentSize: segmentSize
    )
    let backend = OversizedSegmentedStateBackend(
      releaseAll: { try core.releaseAllSegments() }
    )
    let runtime = ExecutionContinuityCoordinator(backend: backend)
    let tokenizer = try await Tokenizers.AutoTokenizer.from(modelFolder: modelDirectory)
    let filler = tokenizer.encode(
      text: "Explain the tradeoff, then list a concise implementation plan "
        + "with tests, failure modes, and rollback steps.",
      addSpecialTokens: false
    )
    let seedTokens = tokenizer.encode(
      text: seedText, addSpecialTokens: true
    )

    var samples: [ReleaseSample] = []
    for tokenLength in tokenLengths {
      for index in 0..<samplesPerLength {
        let prefix = makePrefix(seedTokens: seedTokens, fillerTokens: filler, length: tokenLength)
        let rootID = ExecutionID("release-root-\(tokenLength)-\(index)")
        let root = try await runtime.create(
          id: rootID,
          position: ExecutionPosition(0),
          continuation: ExecutionContinuation(nextInput: "", continuationID: "release-0")
        )
        backend.bind(
          executionID: rootID, position: ExecutionPosition(0), prefix: prefix
        )

        let captureCheckpointStarted = DispatchTime.now().uptimeNanoseconds
        let checkpoint = try await backend.captureRepresentation(for: root)
        let captureCheckpointMs = elapsedMs(captureCheckpointStarted)

        let advanced = try await runtime.continueExecution(
          root,
          continuation: ExecutionContinuation(nextInput: "", continuationID: "release-1")
        )
        backend.bind(
          executionID: advanced.id,
          position: ExecutionPosition(1),
          prefix: prefix + [0]
        )
        let captureCurrentStarted = DispatchTime.now().uptimeNanoseconds
        let current = try await backend.captureRepresentation(for: advanced)
        let captureCurrentMs = elapsedMs(captureCurrentStarted)

        let transitionsBeforeRelease = core.segmentTransitions
        let currentReleaseStarted = DispatchTime.now().uptimeNanoseconds
        try await backend.releaseRepresentation(current)
        let currentReleaseMs = elapsedMs(currentReleaseStarted)
        let currentReleaseTransitionDelta =
          core.segmentTransitions - transitionsBeforeRelease
        let currentRemoved = (try? backend.boundPrefix(for: advanced))?.prefix == nil

        let restoreStarted = DispatchTime.now().uptimeNanoseconds
        try await backend.restoreRepresentation(checkpoint)
        let restoreMs = elapsedMs(restoreStarted)

        let transitionsBeforeStale = core.segmentTransitions
        let staleReleaseStarted = DispatchTime.now().uptimeNanoseconds
        try await backend.releaseRepresentation(current)
        let staleReleaseNoopMs = elapsedMs(staleReleaseStarted)
        let staleReleaseTransitionDelta = core.segmentTransitions - transitionsBeforeStale

        let restoredBinding = try backend.boundPrefix(for: root)
        let restoreReboundCheckpoint =
          restoredBinding.prefix == prefix
          && restoredBinding.position == ExecutionPosition(0)
        let staleNoopPreservedCheckpoint =
          (try? backend.boundPrefix(for: root))?.prefix != nil

        samples.append(
          ReleaseSample(
            tokenLength: tokenLength,
            index: index,
            captureCheckpointMs: captureCheckpointMs,
            captureCurrentMs: captureCurrentMs,
            currentReleaseMs: currentReleaseMs,
            currentReleaseTransitionDelta: currentReleaseTransitionDelta,
            restoreMs: restoreMs,
            staleReleaseNoopMs: staleReleaseNoopMs,
            staleReleaseTransitionDelta: staleReleaseTransitionDelta,
            footprintMiB: core.gauge().footprintMiB,
            currentRemoved: currentRemoved,
            restoreReboundCheckpoint: restoreReboundCheckpoint,
            staleNoopPreservedCheckpoint: staleNoopPreservedCheckpoint
          )
        )
      }
    }

    func summary(_ values: [Double]) -> TimingSummary {
      let sorted = values.sorted()
      let p95Index = max(0, Int((Double(sorted.count - 1) * 0.95).rounded()))
      return TimingSummary(
        n: values.count,
        meanMs: values.reduce(0, +) / Double(max(values.count, 1)),
        medianMs: sorted.count % 2 == 1
          ? sorted[sorted.count / 2]
          : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2,
        p95Ms: sorted[p95Index],
        minMs: sorted.first ?? 0,
        maxMs: sorted.last ?? 0
      )
    }

    func mean(_ values: [Double]) -> Double {
      values.reduce(0, +) / Double(max(values.count, 1))
    }

    var points: [ReleasePoint] = []
    for tokenLength in tokenLengths {
      let group = samples.filter { $0.tokenLength == tokenLength }
      let current = group.map(\.currentReleaseMs)
      let stale = group.map(\.staleReleaseNoopMs)
      points.append(
        ReleasePoint(
          tokenLength: tokenLength,
          samples: group.count,
          captureCheckpointMeanMs: mean(group.map(\.captureCheckpointMs)),
          captureCurrentMeanMs: mean(group.map(\.captureCurrentMs)),
          currentReleaseMeanMs: mean(current),
          restoreMeanMs: mean(group.map(\.restoreMs)),
          staleReleaseNoopMeanMs: mean(stale),
          staleOverCurrentMeanRatio: mean(stale) / max(mean(current), .leastNormalMagnitude)
        )
      )
    }

    let checks = [
      "CURRENT_RELEASE_REMOVES_BINDING":
        samples.count == tokenLengths.count * samplesPerLength
        && samples.allSatisfy(\.currentRemoved),
      "RESTORE_REBINDS_CHECKPOINT":
        samples.allSatisfy(\.restoreReboundCheckpoint),
      "STALE_RELEASE_PRESERVES_CHECKPOINT":
        samples.allSatisfy(\.staleNoopPreservedCheckpoint),
      "STALE_RELEASE_DOES_NOT_RELEASE_SEGMENTS":
        samples.allSatisfy {
          $0.staleReleaseTransitionDelta < $0.currentReleaseTransitionDelta
        },
      "ALL_LENGTHS_OBSERVED":
        Set(samples.map(\.tokenLength)) == Set(tokenLengths)
        && tokenLengths.allSatisfy({ length in
          samples.filter { $0.tokenLength == length }.count == samplesPerLength
        }),
      "OVERSIZED_PROFILE_UNDER_30GIB":
        core.segments.count > 1 && core.peakFootprintMiB <= 30 * 1024,
    ]

    return ReleaseReport(
      status: checks.values.allSatisfy(\.self) ? "PASS" : "FAIL",
      protocolVersion: releaseProtocolVersion,
      boundary: releaseBoundary,
      modelDirectory: modelDirectory.path,
      segmentSize: segmentSize,
      segmentCount: core.segments.count,
      tokenLengths: tokenLengths,
      samplesPerLength: samplesPerLength,
      points: points,
      samples: samples,
      captureCheckpointMs: summary(samples.map(\.captureCheckpointMs)),
      captureCurrentMs: summary(samples.map(\.captureCurrentMs)),
      currentReleaseMs: summary(samples.map(\.currentReleaseMs)),
      restoreMs: summary(samples.map(\.restoreMs)),
      staleReleaseNoopMs: summary(samples.map(\.staleReleaseNoopMs)),
      checks: checks,
      peakFootprintMiB: core.peakFootprintMiB,
      maxSwapMiB: core.maxSwapMiB,
      segmentTransitions: core.segmentTransitions,
      overallPass: checks.values.allSatisfy(\.self)
    )
  }
}

extension MLXExecutionStateCostProfile {
  public struct ReleaseRecoverySample: Encodable, Sendable {
    public let index: Int
    public let retainFirst: Bool
    public let strategy: String
    public let actionMs: Double
    public let actionTransitionDelta: Int
    public let generationMs: Double
    public let generationTransitionDelta: Int
    public let totalMs: Double
    public let advancedBindingExact: Bool
    public let generatedTokenIDs: [Int]
    public let generatedText: String
    public let semanticIdentical: Bool
  }

  public struct ReleaseRecoveryPoint: Encodable, Sendable {
    public let strategy: String
    public let cycles: Int
    public let actionMeanMs: Double
    public let actionTransitionDeltaMean: Double
    public let generationMeanMs: Double
    public let generationTransitionDeltaMean: Double
    public let totalMeanMs: Double
    public let recoveryTokensPerSec: Double
    public let allAdvancedBindingsExact: Bool
    public let allSemanticIdentical: Bool
  }

  public struct ReleaseRecoveryReport: Encodable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let modelDirectory: String
    public let segmentSize: Int
    public let segmentCount: Int
    public let seedText: String
    public let rootInput: String
    public let prefixTokenLength: Int
    public let maxTokens: Int
    public let cycles: Int
    public let retainPoint: ReleaseRecoveryPoint
    public let releasePoint: ReleaseRecoveryPoint
    public let samples: [ReleaseRecoverySample]
    public let pairedOutputsExact: Bool
    public let checks: [String: Bool]
    public let peakFootprintMiB: Int64
    public let maxSwapMiB: Int64
    public let segmentTransitions: Int
    public let overallPass: Bool
  }

  public static let releaseRecoveryProtocolVersion =
    "LAB.MLX.EXECSTATE.RELEASE.RECOVERY.COST.V1"
  public static let releaseRecoveryBoundary =
    "OVERSIZED_MLX_RETAIN_VS_RELEASE_RESTORE / PAIRED_RECOVERY_OBSERVATION / "
    + "SMALL_SAMPLE / NOT_A_PERFORMANCE_BENCHMARK"

  public static func runReleaseRecoveryProfile(
    modelDirectory: URL,
    seedText: String = "def is_palindrome(s):",
    rootInput: String = "Explain it briefly.",
    prefixTokenLength: Int = 64,
    maxTokens: Int = 2,
    cycles: Int = 4,
    segmentSize: Int = 8
  ) async throws -> ReleaseRecoveryReport {
    precondition(cycles > 0 && prefixTokenLength > 0 && maxTokens > 0)
    let core = try await O6SegmentedCore(
      modelDirectory: modelDirectory, segmentSize: segmentSize
    )
    let backend = OversizedSegmentedStateBackend(
      releaseAll: { try core.releaseAllSegments() }
    )
    let runtime = ExecutionContinuityCoordinator(backend: backend)
    let tokenizer = try await Tokenizers.AutoTokenizer.from(modelFolder: modelDirectory)
    let executor = OversizedSegmentedExecutor(
      core: core, backend: backend, tokenizer: tokenizer
    )
    let seedTokens = try executor.tokenizeSeedText(seedText)
    let rootTokens = try executor.tokenizeText(rootInput)
    let prefix = makePrefix(
      seedTokens: seedTokens,
      fillerTokens: try executor.tokenizeText(
        "Explain the tradeoff, then list a concise implementation plan "
          + "with tests, failure modes, and rollback steps."
      ),
      length: prefixTokenLength
    )

    _ = try executor.directGenerate(
      prefix: prefix, nextInputTokens: rootTokens, maxTokens: 1
    )
    try core.releaseAllSegments()

    var samples: [ReleaseRecoverySample] = []
    var outputsByCycle: [Int: [String: ExecutionContinuationResult]] = [:]
    for index in 0..<cycles {
      let retainFirst = index % 2 == 0
      let strategies: [(String, Bool)] = retainFirst
        ? [("RETAIN", true), ("RELEASE_RESTORE", false)]
        : [("RELEASE_RESTORE", false), ("RETAIN", true)]

      for (strategy, isRetain) in strategies {
        try core.releaseAllSegments()
        let rootID = ExecutionID("release-recovery-\(strategy)-\(index)")
        let root = try await runtime.create(
          id: rootID,
          position: ExecutionPosition(0),
          continuation: ExecutionContinuation(nextInput: rootInput, continuationID: "action-0")
        )
        backend.bind(
          executionID: rootID,
          position: ExecutionPosition(0),
          prefix: prefix
        )

        let actionStarted = DispatchTime.now().uptimeNanoseconds
        let transitionsBeforeAction = core.segmentTransitions
        let checkpoint = try await backend.captureRepresentation(for: root)
        if !isRetain {
          try await backend.releaseRepresentation(checkpoint)
          try await backend.restoreRepresentation(checkpoint)
        }
        let actionMs = elapsedMs(actionStarted)
        let actionTransitionDelta = core.segmentTransitions - transitionsBeforeAction

        let generationStarted = DispatchTime.now().uptimeNanoseconds
        let transitionsBeforeGeneration = core.segmentTransitions
        let generated = try await executor.continueExecution(
          root, nextInputTokens: rootTokens, maxTokens: maxTokens
        )
        let generationMs = elapsedMs(generationStarted)
        let generationTransitionDelta =
          core.segmentTransitions - transitionsBeforeGeneration

        let advanced = try await runtime.continueExecution(
          root,
          continuation: ExecutionContinuation(nextInput: rootInput, continuationID: "recovery-1")
        )
        try await runtime.bindRepresentation(
          executionID: advanced.id,
          position: ExecutionPosition(1),
          payload: generated.updatedPayload
        )
        let advancedBinding = try backend.boundPrefix(for: advanced)
        let advancedBindingExact =
          advancedBinding.prefix == prefix + rootTokens + generated.generatedTokenIDs
          && advancedBinding.position == ExecutionPosition(1)
        outputsByCycle[index, default: [:]][strategy] = generated

        samples.append(
          ReleaseRecoverySample(
            index: index,
            retainFirst: retainFirst,
            strategy: strategy,
            actionMs: actionMs,
            actionTransitionDelta: actionTransitionDelta,
            generationMs: generationMs,
            generationTransitionDelta: generationTransitionDelta,
            totalMs: actionMs + generationMs,
            advancedBindingExact: advancedBindingExact,
            generatedTokenIDs: generated.generatedTokenIDs,
            generatedText: generated.generatedText,
            semanticIdentical:
              generated.generatedTokenIDs.count == maxTokens
              && generated.updatedPayload is OversizedPrefixPayload
          )
        )
      }
    }

    func point(_ strategy: String) -> ReleaseRecoveryPoint {
      let group = samples.filter { $0.strategy == strategy }
      let action = group.map(\.actionMs)
      let generation = group.map(\.generationMs)
      let total = group.map(\.totalMs)
      let actionDelta = group.map(\.actionTransitionDelta)
      let generationDelta = group.map(\.generationTransitionDelta)
      return ReleaseRecoveryPoint(
        strategy: strategy,
        cycles: group.count,
        actionMeanMs: mean(action),
        actionTransitionDeltaMean: mean(actionDelta.map(Double.init)),
        generationMeanMs: mean(generation),
        generationTransitionDeltaMean: mean(generationDelta.map(Double.init)),
        totalMeanMs: mean(total),
        recoveryTokensPerSec: Double(maxTokens * group.count) / (mean(generation) / 1000),
        allAdvancedBindingsExact: group.allSatisfy(\.advancedBindingExact),
        allSemanticIdentical: group.allSatisfy { $0.generatedTokenIDs.count == maxTokens }
      )
    }

    let retain = point("RETAIN")
    let release = point("RELEASE_RESTORE")
    let retainOutputTokenIDs = samples.filter { $0.strategy == "RETAIN" }.count
    let releaseOutputTokenIDs = samples.filter { $0.strategy == "RELEASE_RESTORE" }.count
    let pairedOutputsExact =
      (0..<cycles).allSatisfy { index in
        guard let retain = outputsByCycle[index]?["RETAIN"],
          let release = outputsByCycle[index]?["RELEASE_RESTORE"]
        else { return false }
        return retain.generatedTokenIDs == release.generatedTokenIDs
          && retain.generatedText == release.generatedText
      }
    let checks = [
      "BOTH_STRATEGIES_COMPLETE":
        retain.cycles == cycles && release.cycles == cycles,
      "RECOVERY_BINDINGS_EXACT":
        retain.allAdvancedBindingsExact && release.allAdvancedBindingsExact,
      "GENERATION_TOKEN_BUDGET_COMPLETE":
        retainOutputTokenIDs == cycles && releaseOutputTokenIDs == cycles,
      "RETAIN_ACTION_DOES_NOT_RELEASE_SEGMENTS":
        samples.filter { $0.strategy == "RETAIN" }.allSatisfy {
          $0.actionTransitionDelta == 0
        },
      "RELEASE_ACTION_RELEASES_SEGMENTS":
        samples.filter { $0.strategy == "RELEASE_RESTORE" }.allSatisfy {
          $0.actionTransitionDelta > 0
        },
      "PAIRED_STRATEGY_OUTPUTS_EXACT":
        pairedOutputsExact,
      "OVERSIZED_PROFILE_UNDER_30GIB":
        core.segments.count > 1 && core.peakFootprintMiB <= 30 * 1024,
    ]

    return ReleaseRecoveryReport(
      status: checks.values.allSatisfy(\.self) ? "PASS" : "FAIL",
      protocolVersion: releaseRecoveryProtocolVersion,
      boundary: releaseRecoveryBoundary,
      modelDirectory: modelDirectory.path,
      segmentSize: segmentSize,
      segmentCount: core.segments.count,
      seedText: seedText,
      rootInput: rootInput,
      prefixTokenLength: prefixTokenLength,
      maxTokens: maxTokens,
      cycles: cycles,
      retainPoint: retain,
      releasePoint: release,
      samples: samples,
      pairedOutputsExact: pairedOutputsExact,
      checks: checks,
      peakFootprintMiB: core.peakFootprintMiB,
      maxSwapMiB: core.maxSwapMiB,
      segmentTransitions: core.segmentTransitions,
      overallPass: checks.values.allSatisfy(\.self)
    )
  }
}
