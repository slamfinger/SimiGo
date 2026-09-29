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
