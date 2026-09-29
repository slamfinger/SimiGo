import Foundation
import SimiGoRuntimeContract
import Tokenizers

/// Minimal user-level control plane over the existing Execution State contract.
/// This is a research harness, not a product UI or second inference runtime.
public enum UIBranchSessions {
  public static let protocolVersion = "LAB.UI.BRANCH.SESSIONS.V1"
  public static let boundary =
    "SWIFT_SESSION_CONTROL_PLANE / LLAMA_PREFIX_REPRESENTATION / "
    + "HARNESS_LEVEL / NO_NATIVE_KV_AUTHORITY_CHANGE / NOT_A_UI_PRODUCT"

  struct Completion: Codable, Equatable, Sendable {
    let content: String
    let tokens: [Int]?
  }

  public struct Step: Encodable, Sendable {
    let operation: String
    let executionID: String
    let position: Int64
    let clientMs: Double
  }

  public struct Report: Encodable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let host: String
    public let port: Int
    public let seed: Int
    public let checks: [String: Bool]
    public let rootContent: String
    public let branchAContent: String
    public let branchBContent: String
    public let rootReplayContent: String
    public let steps: [Step]
    public let overallPass: Bool
  }

  public static func run(
    host: String = "127.0.0.1",
    port: Int = 18080,
    rootTokenPrefix: [Int] = [5423, 6681, 799, 3299, 25, 29018],
    branchAInputTokens: [Int] = [12139, 279, 2235, 1622, 13],
    branchBInputTokens: [Int] = [3301, 6681, 25, 8029, 13053],
    predictionTokens: Int = 8,
    seed: Int = 42
  ) async throws -> Report {
    let backend = LLAMAServerExecutionStateBackend()
    let runtime = ExecutionContinuityCoordinator(backend: backend)
    let executor = LLAMAServerExecutionStateExecutor(
      baseURL: URL(string: "http://\(host):\(port)")!)

    var steps: [Step] = []

    func record(_ operation: String, _ id: ExecutionStateHandle, _ started: UInt64) {
      steps.append(
        Step(
          operation: operation,
          executionID: id.id.rawValue,
          position: id.position.value,
          clientMs: elapsedMs(started)
        )
      )
    }

    let rootID = ExecutionID("ui-session-root")
    let branchAID = ExecutionID("ui-branch-a")
    let branchBID = ExecutionID("ui-branch-b")
    let forkPoint = ExecutionPosition(0)
    let continuedPosition = ExecutionPosition(1)

    var root = try await runtime.create(
      id: rootID,
      position: forkPoint,
      continuation: ExecutionContinuation(nextInput: "", continuationID: "root-0")
    )
    try await runtime.bindRepresentation(
      executionID: rootID,
      position: forkPoint,
      payload: LLAMAServerPrefixPayload(tokenPrefix: rootTokenPrefix)
    )

    var started = DispatchTime.now().uptimeNanoseconds
    let branchA = try await runtime.fork(
      ExecutionForkRequest(
        parent: root,
        childID: branchAID,
        childPosition: forkPoint,
        childContinuation: ExecutionContinuation(nextInput: "", continuationID: "branch-a-0")
      )
    )
    let branchB = try await runtime.fork(
      ExecutionForkRequest(
        parent: root,
        childID: branchBID,
        childPosition: forkPoint,
        childContinuation: ExecutionContinuation(nextInput: "", continuationID: "branch-b-0")
      )
    )
    record("fork", branchA, started)
    let rootCheckpoint = try await backend.captureRepresentation(for: root)

    started = DispatchTime.now().uptimeNanoseconds
    let rootOutput = try await executor.complete(
      rootCheckpoint, predictionTokens: predictionTokens, seed: seed
    )
    record("continue", root, started)
    root = try await runtime.continueExecution(
      root,
      continuation: ExecutionContinuation(nextInput: "", continuationID: "root-1")
    )
    try await runtime.bindRepresentation(
      executionID: root.id,
      position: continuedPosition,
      payload: LLAMAServerPrefixPayload(
        tokenPrefix: rootTokenPrefix + (rootOutput.tokens ?? []))
    )

    started = DispatchTime.now().uptimeNanoseconds
    let branchAOutput = try await executor.complete(
      tokenPrefix: rootTokenPrefix + branchAInputTokens,
      predictionTokens: predictionTokens,
      seed: seed
    )
    record("continue", branchA, started)
    let advancedA = try await runtime.continueExecution(
      branchA,
      continuation: ExecutionContinuation(nextInput: "", continuationID: "branch-a-1")
    )
    try await runtime.bindRepresentation(
      executionID: advancedA.id,
      position: continuedPosition,
      payload: LLAMAServerPrefixPayload(
        tokenPrefix: rootTokenPrefix + branchAInputTokens + (branchAOutput.tokens ?? []))
    )

    started = DispatchTime.now().uptimeNanoseconds
    let branchBOutput = try await executor.complete(
      tokenPrefix: rootTokenPrefix + branchBInputTokens,
      predictionTokens: predictionTokens,
      seed: seed
    )
    record("continue", branchB, started)
    let advancedB = try await runtime.continueExecution(
      branchB,
      continuation: ExecutionContinuation(nextInput: "", continuationID: "branch-b-1")
    )
    try await runtime.bindRepresentation(
      executionID: advancedB.id,
      position: continuedPosition,
      payload: LLAMAServerPrefixPayload(
        tokenPrefix: rootTokenPrefix + branchBInputTokens + (branchBOutput.tokens ?? []))
    )

    started = DispatchTime.now().uptimeNanoseconds
    let restoredRoot = try await runtime.restore(
      root,
      request: ExecutionRestoreRequest(
        targetPosition: forkPoint,
        continuation: ExecutionContinuation(nextInput: "", continuationID: "root-switch-0")
      )
    )
    record("switch", restoredRoot, started)
    let restoredRootRepresentation = try await backend.captureRepresentation(for: restoredRoot)
    let rootReplay = try await executor.complete(
      restoredRootRepresentation, predictionTokens: predictionTokens, seed: seed
    )

    started = DispatchTime.now().uptimeNanoseconds
    let restoredA = try await runtime.restore(
      advancedA,
      request: ExecutionRestoreRequest(
        targetPosition: continuedPosition,
        continuation: ExecutionContinuation(nextInput: "", continuationID: "branch-a-switch-1")
      )
    )
    _ = try await backend.captureRepresentation(for: restoredA)
    record("switch", restoredA, started)

    started = DispatchTime.now().uptimeNanoseconds
    let switchedRoot = try await runtime.restore(
      root,
      request: ExecutionRestoreRequest(
        targetPosition: continuedPosition,
        continuation: ExecutionContinuation(nextInput: "", continuationID: "root-switch-1")
      )
    )
    let rootRepresentation = try await backend.captureRepresentation(for: switchedRoot)
    record("switch", switchedRoot, started)

    let rootBinding = try backend.boundPrefix(for: switchedRoot)
    let branchABinding = try backend.boundPrefix(for: restoredA)

    started = DispatchTime.now().uptimeNanoseconds
    try await runtime.discard(restoredA)
    try await runtime.discard(advancedB)
    record("release", restoredA, started)
    let branchAReleased = (try? backend.boundPrefix(for: restoredA))?.prefix == nil
    let branchBReleased = (try? backend.boundPrefix(for: advancedB))?.prefix == nil
    let rootSurvives = (try? backend.boundPrefix(for: switchedRoot))?.prefix != nil

    let checks = [
      "BRANCHES_DIVERGED":
        rootOutput != branchAOutput && rootOutput != branchBOutput
        && branchAOutput != branchBOutput,
      "BRANCH_LINEAGE_ISOLATED":
        branchA.lineage.parent == rootID && branchB.lineage.parent == rootID
        && branchA.lineage.root == root.lineage.root,
      "SWITCH_ROOT_TO_FORK_REPLAYS":
        rootReplay == rootOutput,
      "SWITCH_BRANCH_RETAINS_DIVERGENCE":
        branchABinding.prefix
        == rootTokenPrefix + branchAInputTokens + (branchAOutput.tokens ?? []),
      "SWITCH_ROOT_RETAINS_ADVANCE":
        rootBinding.prefix == rootTokenPrefix + (rootOutput.tokens ?? []),
      "RELEASE_BRANCHES":
        branchAReleased && branchBReleased,
      "ROOT_SURVIVES_RELEASE":
        rootSurvives && rootRepresentation.payload is LLAMAServerPrefixPayload,
    ]

    let overallPass = checks.values.allSatisfy { $0 }

    return Report(
      status: overallPass ? "PASS" : "FAIL",
      protocolVersion: protocolVersion,
      boundary: boundary,
      host: host,
      port: port,
      seed: seed,
      checks: checks,
      rootContent: rootOutput.content,
      branchAContent: branchAOutput.content,
      branchBContent: branchBOutput.content,
      rootReplayContent: rootReplay.content,
      steps: steps,
      overallPass: overallPass
    )
  }

  private static func elapsedMs(_ started: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds &- started) / 1e6
  }

  public struct MLXReport: Encodable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let modelDirectory: String
    public let segmentSize: Int
    public let segmentCount: Int
    public let maxTokens: Int
    public let checks: [String: Bool]
    public let rootContent: String
    public let branchAContent: String
    public let branchBContent: String
    public let rootReplayContent: String
    public let steps: [Step]
    public let peakFootprintMiB: Int64
    public let maxSwapMiB: Int64
    public let segmentTransitions: Int
    public let overallPass: Bool
  }

  public static let mlxProtocolVersion = "LAB.UI.BRANCH.SESSIONS.MLX.V1"
  public static let mlxBoundary =
    "SWIFT_SESSION_CONTROL_PLANE / OVERSIZED_MLX_PREFIX_REPRESENTATION / "
    + "HARNESS_LEVEL / SEGMENTED_CACHELESS_GREEDY / NOT_A_UI_PRODUCT"

  public static func runOversizedMLX(
    modelDirectory: URL,
    seedText: String = "def is_palindrome(s):",
    rootInput: String = "Explain it briefly.",
    branchAInput: String = "Now write tests for it.",
    branchBInput: String = "Add a one-line TODO.",
    maxTokens: Int = 2,
    segmentSize: Int = 8
  ) async throws -> MLXReport {
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

    var steps: [Step] = []
    func record(_ operation: String, _ state: ExecutionStateHandle, _ started: UInt64) {
      steps.append(
        Step(
          operation: operation,
          executionID: state.id.rawValue,
          position: state.position.value,
          clientMs: elapsedMs(started)
        )
      )
    }

    let rootID = ExecutionID("mlx-ui-root")
    let branchAID = ExecutionID("mlx-branch-a")
    let branchBID = ExecutionID("mlx-branch-b")
    let forkPoint = ExecutionPosition(0)
    let continuedPosition = ExecutionPosition(1)
    let seedTokens = try executor.tokenizeSeedText(seedText)

    var root = try await runtime.create(
      id: rootID,
      position: forkPoint,
      continuation: ExecutionContinuation(nextInput: rootInput, continuationID: "root-0")
    )
    try await runtime.bindRepresentation(
      executionID: rootID,
      position: forkPoint,
      payload: OversizedPrefixPayload(tokenPrefix: seedTokens)
    )

    var started = DispatchTime.now().uptimeNanoseconds
    let branchA = try await runtime.fork(
      ExecutionForkRequest(
        parent: root,
        childID: branchAID,
        childPosition: forkPoint,
        childContinuation: ExecutionContinuation(
          nextInput: branchAInput, continuationID: "branch-a-0"
        )
      )
    )
    let branchB = try await runtime.fork(
      ExecutionForkRequest(
        parent: root,
        childID: branchBID,
        childPosition: forkPoint,
        childContinuation: ExecutionContinuation(
          nextInput: branchBInput, continuationID: "branch-b-0"
        )
      )
    )
    record("fork", branchA, started)
    _ = try await backend.captureRepresentation(for: root)

    func advance(
      _ state: ExecutionStateHandle,
      input: String,
      operation: String
    ) async throws -> (ExecutionStateHandle, generated: [Int], text: String, payload: any ExecutionRepresentationPayload) {
      let mark = DispatchTime.now().uptimeNanoseconds
      let result = try await executor.continueExecution(
        state, nextInputTokens: try executor.tokenizeText(input), maxTokens: maxTokens
      )
      let advanced = try await runtime.continueExecution(
        state,
        continuation: ExecutionContinuation(nextInput: input, continuationID: operation)
      )
      try await runtime.bindRepresentation(
        executionID: advanced.id,
        position: advanced.position,
        payload: result.updatedPayload
      )
      record(operation, advanced, mark)
      return (advanced, result.generatedTokenIDs, result.generatedText, result.updatedPayload)
    }

    let rootRun = try await advance(root, input: rootInput, operation: "continue")
    root = rootRun.0
    let branchARun = try await advance(branchA, input: branchAInput, operation: "continue")
    let advancedA = branchARun.0
    let branchBRun = try await advance(branchB, input: branchBInput, operation: "continue")
    let advancedB = branchBRun.0

    started = DispatchTime.now().uptimeNanoseconds
    let restoredRoot = try await runtime.restore(
      root,
      request: ExecutionRestoreRequest(
        targetPosition: forkPoint,
        continuation: ExecutionContinuation(nextInput: "", continuationID: "root-switch-0")
      )
    )
    record("switch", restoredRoot, started)
    let rootReplay = try await executor.continueExecution(
      restoredRoot,
      nextInputTokens: try executor.tokenizeText(rootInput),
      maxTokens: maxTokens
    )

    started = DispatchTime.now().uptimeNanoseconds
    let restoredA = try await runtime.restore(
      advancedA,
      request: ExecutionRestoreRequest(
        targetPosition: continuedPosition,
        continuation: ExecutionContinuation(nextInput: branchAInput, continuationID: "branch-a-switch-1")
      )
    )
    record("switch", restoredA, started)

    started = DispatchTime.now().uptimeNanoseconds
    let switchedRoot = try await runtime.restore(
      root,
      request: ExecutionRestoreRequest(
        targetPosition: continuedPosition,
        continuation: ExecutionContinuation(nextInput: rootInput, continuationID: "root-switch-1")
      )
    )
    let rootRepresentation = try await backend.captureRepresentation(for: switchedRoot)
    record("switch", switchedRoot, started)

    let rootBinding = try backend.boundPrefix(for: switchedRoot)
    let branchABinding = try backend.boundPrefix(for: restoredA)
    let rootAdvancedPrefix = (rootRun.payload as? OversizedPrefixPayload)?.tokenPrefix
    let branchAPrefix = (branchARun.payload as? OversizedPrefixPayload)?.tokenPrefix

    started = DispatchTime.now().uptimeNanoseconds
    try await runtime.discard(restoredA)
    try await runtime.discard(advancedB)
    record("release", restoredA, started)
    let branchAReleased = (try? backend.boundPrefix(for: restoredA))?.prefix == nil
    let branchBReleased = (try? backend.boundPrefix(for: advancedB))?.prefix == nil
    let rootSurvives = (try? backend.boundPrefix(for: switchedRoot))?.prefix != nil

    let branchesDiverged =
      rootRun.generated != branchARun.generated
      && rootRun.generated != branchBRun.generated
      && branchARun.generated != branchBRun.generated
    let lineageIsolated =
      branchA.lineage.parent == rootID && branchB.lineage.parent == rootID
      && branchA.lineage.root == root.lineage.root
    let rootForkReplays =
      rootReplay.generatedTokenIDs == rootRun.generated
      && rootReplay.generatedText == rootRun.text
    let branchRetains = branchABinding.prefix == branchAPrefix
    let rootRetains = rootBinding.prefix == rootAdvancedPrefix
    let oversizedUnderLimit = core.peakFootprintMiB <= 30 * 1024
    let checks = [
      "BRANCHES_DIVERGED": branchesDiverged,
      "BRANCH_LINEAGE_ISOLATED": lineageIsolated,
      "SWITCH_ROOT_TO_FORK_REPLAYS": rootForkReplays,
      "SWITCH_BRANCH_RETAINS_DIVERGENCE": branchRetains,
      "SWITCH_ROOT_RETAINS_ADVANCE": rootRetains,
      "RELEASE_BRANCHES": branchAReleased && branchBReleased,
      "ROOT_SURVIVES_RELEASE": rootSurvives
        && rootRepresentation.payload is OversizedPrefixPayload,
      "OVERSIZED_PROFILE_UNDER_30GIB": core.segments.count > 1 && oversizedUnderLimit,
    ]
    let overallPass = checks.values.allSatisfy { $0 }

    return MLXReport(
      status: overallPass ? "PASS" : "FAIL",
      protocolVersion: mlxProtocolVersion,
      boundary: mlxBoundary,
      modelDirectory: modelDirectory.path,
      segmentSize: segmentSize,
      segmentCount: core.segments.count,
      maxTokens: maxTokens,
      checks: checks,
      rootContent: rootRun.text,
      branchAContent: branchARun.text,
      branchBContent: branchBRun.text,
      rootReplayContent: rootReplay.generatedText,
      steps: steps,
      peakFootprintMiB: core.peakFootprintMiB,
      maxSwapMiB: core.maxSwapMiB,
      segmentTransitions: core.segmentTransitions,
      overallPass: overallPass
    )
  }
}
