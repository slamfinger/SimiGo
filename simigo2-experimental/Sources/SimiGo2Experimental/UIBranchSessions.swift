import Foundation
import SimiGoRuntimeContract
import Tokenizers

/// Minimal user-level control plane over the existing Execution State contract.
/// This is a research harness, not a product UI or second inference runtime.
public enum UIBranchSessions {
  public static let protocolVersion = "LAB.UI.BRANCH.SESSIONS.V2"
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
    public let modelPath: String?
    public let seedText: String
    public let rootInput: String
    public let branchAInput: String
    public let branchBInput: String
    public let predictionTokens: Int
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
    seedText: String = "def is_palindrome(s):",
    rootInput: String = "Explain it briefly.",
    branchAInput: String = "Now write tests for it.",
    branchBInput: String = "Add a one-line TODO.",
    predictionTokens: Int = 8,
    seed: Int = 42
  ) async throws -> Report {
    let backend = LLAMAServerExecutionStateBackend()
    let runtime = ExecutionContinuityCoordinator(backend: backend)
    let executor = LLAMAServerExecutionStateExecutor(
      baseURL: URL(string: "http://\(host):\(port)")!)
    let serverProps = try await executor.props()
    let seedTokens = try await executor.tokenizeText(seedText, addSpecialTokens: true)
    let rootInputTokens = try await executor.tokenizeText(rootInput)
    let branchAInputTokens = try await executor.tokenizeText(branchAInput)
    let branchBInputTokens = try await executor.tokenizeText(branchBInput)

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

    let rootID = ExecutionID("ui-session-root")
    let branchAID = ExecutionID("ui-branch-a")
    let branchBID = ExecutionID("ui-branch-b")
    let forkPoint = ExecutionPosition(0)
    let continuedPosition = ExecutionPosition(1)

    var root = try await runtime.create(
      id: rootID,
      position: forkPoint,
      continuation: ExecutionContinuation(nextInput: rootInput, continuationID: "root-0")
    )
    try await runtime.bindRepresentation(
      executionID: rootID,
      position: forkPoint,
      payload: LLAMAServerPrefixPayload(tokenPrefix: seedTokens)
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

    started = DispatchTime.now().uptimeNanoseconds
    let rootOutput = try await executor.complete(
      tokenPrefix: seedTokens + rootInputTokens,
      predictionTokens: predictionTokens,
      seed: seed
    )
    root = try await runtime.continueExecution(
      root,
      continuation: ExecutionContinuation(nextInput: rootInput, continuationID: "root-1")
    )
    record("continue", root, started)
    try await runtime.bindRepresentation(
      executionID: root.id,
      position: continuedPosition,
      payload: LLAMAServerPrefixPayload(
        tokenPrefix: seedTokens + rootInputTokens + (rootOutput.tokens ?? []))
    )

    started = DispatchTime.now().uptimeNanoseconds
    let branchAOutput = try await executor.complete(
      tokenPrefix: seedTokens + branchAInputTokens,
      predictionTokens: predictionTokens,
      seed: seed
    )
    let advancedA = try await runtime.continueExecution(
      branchA,
      continuation: ExecutionContinuation(nextInput: branchAInput, continuationID: "branch-a-1")
    )
    record("continue", advancedA, started)
    try await runtime.bindRepresentation(
      executionID: advancedA.id,
      position: continuedPosition,
      payload: LLAMAServerPrefixPayload(
        tokenPrefix: seedTokens + branchAInputTokens + (branchAOutput.tokens ?? []))
    )

    started = DispatchTime.now().uptimeNanoseconds
    let branchBOutput = try await executor.complete(
      tokenPrefix: seedTokens + branchBInputTokens,
      predictionTokens: predictionTokens,
      seed: seed
    )
    let advancedB = try await runtime.continueExecution(
      branchB,
      continuation: ExecutionContinuation(nextInput: branchBInput, continuationID: "branch-b-1")
    )
    record("continue", advancedB, started)
    try await runtime.bindRepresentation(
      executionID: advancedB.id,
      position: continuedPosition,
      payload: LLAMAServerPrefixPayload(
        tokenPrefix: seedTokens + branchBInputTokens + (branchBOutput.tokens ?? []))
    )

    started = DispatchTime.now().uptimeNanoseconds
    let restoredRoot = try await runtime.restore(
      root,
      request: ExecutionRestoreRequest(
        targetPosition: forkPoint,
        continuation: ExecutionContinuation(nextInput: rootInput, continuationID: "root-switch-0")
      )
    )
    record("switch", restoredRoot, started)
    let restoredRootRepresentation = try await backend.captureRepresentation(for: restoredRoot)
    let rootReplay = try await executor.complete(
      tokenPrefix: restoredRootPrefix(restoredRootRepresentation) + rootInputTokens,
      predictionTokens: predictionTokens,
      seed: seed
    )

    started = DispatchTime.now().uptimeNanoseconds
    let restoredA = try await runtime.restore(
      advancedA,
      request: ExecutionRestoreRequest(
        targetPosition: continuedPosition,
        continuation: ExecutionContinuation(
          nextInput: branchAInput, continuationID: "branch-a-switch-1"
        )
      )
    )
    _ = try await backend.captureRepresentation(for: restoredA)
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

    started = DispatchTime.now().uptimeNanoseconds
    try await runtime.discard(restoredA)
    try await runtime.discard(advancedB)
    record("release", restoredA, started)
    let branchAReleased = (try? backend.boundPrefix(for: restoredA))?.prefix == nil
    let branchBReleased = (try? backend.boundPrefix(for: advancedB))?.prefix == nil
    let rootSurvives = (try? backend.boundPrefix(for: switchedRoot))?.prefix != nil

    let rootAdvancedPrefix = seedTokens + rootInputTokens + (rootOutput.tokens ?? [])
    let branchAPrefix = seedTokens + branchAInputTokens + (branchAOutput.tokens ?? [])
    let branchBPrefix = seedTokens + branchBInputTokens + (branchBOutput.tokens ?? [])

    let checks = [
      "BRANCHES_DIVERGED":
        rootAdvancedPrefix != branchAPrefix && rootAdvancedPrefix != branchBPrefix
        && branchAPrefix != branchBPrefix,
      "BRANCH_LINEAGE_ISOLATED":
        branchA.lineage.parent == rootID && branchB.lineage.parent == rootID
        && branchA.lineage.root == root.lineage.root,
      "SWITCH_ROOT_TO_FORK_REPLAYS":
        rootReplay == rootOutput,
      "SWITCH_BRANCH_RETAINS_DIVERGENCE":
        branchABinding.prefix
        == branchAPrefix,
      "SWITCH_ROOT_RETAINS_ADVANCE":
        rootBinding.prefix == rootAdvancedPrefix,
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
      modelPath: serverProps.modelPath,
      seedText: seedText,
      rootInput: rootInput,
      branchAInput: branchAInput,
      branchBInput: branchBInput,
      predictionTokens: predictionTokens,
      checks: checks,
      rootContent: rootOutput.content,
      branchAContent: branchAOutput.content,
      branchBContent: branchBOutput.content,
      rootReplayContent: rootReplay.content,
      steps: steps,
      overallPass: overallPass
    )
  }

  private static func restoredRootPrefix(_ representation: ExecutionRepresentation) -> [Int] {
    guard let payload = representation.payload as? LLAMAServerPrefixPayload else { return [] }
    return payload.tokenPrefix
  }

  private static func elapsedMs(_ started: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds &- started) / 1e6
  }

  public struct MatrixReport: Encodable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let seedText: String
    public let rootInput: String
    public let branchAInput: String
    public let branchBInput: String
    public let predictionTokens: Int
    public let commonChecks: [String: Bool]
    public let llamaOperationSequence: [String]
    public let mlxOperationSequence: [String]
    public let sameSemanticChecks: Bool
    public let sameOperationSequence: Bool
    public let sameWorkloadShape: Bool
    public let bothBackendsPass: Bool
    public let crossBackendClosure: Bool
    public let closureBlocker: String
    public let llama: Report
    public let mlx: MLXReport
    public let overallPass: Bool
  }

  public static let matrixProtocolVersion = "LAB.UI.BRANCH.SESSIONS.CROSSBACKEND.V1"
  public static let matrixBoundary =
    "SAME_TEXT_WORKLOAD_SHAPE_AND_OPERATION_SEQUENCE / HARNESS_LEVEL / "
    + "NO_NATIVE_KV_AUTHORITY_CHANGE / NOT_A_MODEL_IDENTITY_CLOSURE"

  public static func runCrossBackendMatrix(
    modelDirectory: URL,
    host: String = "127.0.0.1",
    port: Int = 18080,
    seedText: String = "def is_palindrome(s):",
    rootInput: String = "Explain it briefly.",
    branchAInput: String = "Now write tests for it.",
    branchBInput: String = "Add a one-line TODO.",
    predictionTokens: Int = 2,
    seed: Int = 42,
    segmentSize: Int = 8
  ) async throws -> MatrixReport {
    let llama = try await run(
      host: host,
      port: port,
      seedText: seedText,
      rootInput: rootInput,
      branchAInput: branchAInput,
      branchBInput: branchBInput,
      predictionTokens: predictionTokens,
      seed: seed
    )
    let mlx = try await runOversizedMLX(
      modelDirectory: modelDirectory,
      seedText: seedText,
      rootInput: rootInput,
      branchAInput: branchAInput,
      branchBInput: branchBInput,
      maxTokens: predictionTokens,
      segmentSize: segmentSize
    )

    func signature(_ step: Step) -> String {
      "\(step.operation)@\(step.position)"
    }
    let llamaOperations = llama.steps.map(signature)
    let mlxOperations = mlx.steps.map(signature)
    let commonChecks = llama.checks
    let sameSemanticChecks = commonChecks.allSatisfy { name, expected in
      mlx.checks[name] == expected
    }
    let sameOperationSequence = llamaOperations == mlxOperations
    let sameWorkloadShape =
      llama.predictionTokens == predictionTokens && mlx.maxTokens == predictionTokens
      && mlx.modelDirectory == modelDirectory.path
    let semanticMatrixPass =
      llama.overallPass && mlx.overallPass && sameSemanticChecks
      && sameOperationSequence && sameWorkloadShape

    return MatrixReport(
      status: semanticMatrixPass ? "PASS_WITH_BOUNDARY" : "FAIL",
      protocolVersion: matrixProtocolVersion,
      boundary: matrixBoundary,
      seedText: seedText,
      rootInput: rootInput,
      branchAInput: branchAInput,
      branchBInput: branchBInput,
      predictionTokens: predictionTokens,
      commonChecks: commonChecks,
      llamaOperationSequence: llamaOperations,
      mlxOperationSequence: mlxOperations,
      sameSemanticChecks: sameSemanticChecks,
      sameOperationSequence: sameOperationSequence,
      sameWorkloadShape: sameWorkloadShape,
      bothBackendsPass: llama.overallPass && mlx.overallPass,
      crossBackendClosure: false,
      closureBlocker: "DIFFERENT_MODEL_ARTIFACTS_AND_TOKENIZERS",
      llama: llama,
      mlx: mlx,
      overallPass: semanticMatrixPass
    )
  }

  public struct NestedMatrixReport: Encodable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let seedText: String
    public let branchAInput: String
    public let nestedInput: String
    public let branchBInput: String
    public let predictionTokens: Int
    public let cycles: Int
    public let commonChecks: [String: Bool]
    public let llamaOperationSequence: [String]
    public let mlxOperationSequence: [String]
    public let sameSemanticChecks: Bool
    public let sameOperationSequence: Bool
    public let sameWorkloadShape: Bool
    public let bothBackendsPass: Bool
    public let crossBackendClosure: Bool
    public let closureBlocker: String
    public let llama: NestedReport
    public let mlx: MLXNestedReport
    public let overallPass: Bool
  }

  public static let nestedMatrixProtocolVersion =
    "LAB.UI.BRANCH.SESSIONS.NESTED.CROSSBACKEND.V1"
  public static let nestedMatrixBoundary =
    "SAME_NESTED_TEXT_WORKLOAD_AND_OPERATION_SEQUENCE / HARNESS_LEVEL / "
    + "NO_NATIVE_KV_AUTHORITY_CHANGE / NOT_A_MODEL_IDENTITY_CLOSURE"

  public static func runNestedCrossBackendMatrix(
    modelDirectory: URL,
    host: String = "127.0.0.1",
    port: Int = 18080,
    seedText: String = "def is_palindrome(s):",
    branchAInput: String = "Now write tests for it.",
    nestedInput: String = "Explain the first test.",
    branchBInput: String = "Add a one-line TODO.",
    predictionTokens: Int = 2,
    cycles: Int = 2,
    seed: Int = 42,
    segmentSize: Int = 8
  ) async throws -> NestedMatrixReport {
    let llama = try await runNestedLLAMA(
      host: host,
      port: port,
      seedText: seedText,
      branchAInput: branchAInput,
      nestedInput: nestedInput,
      branchBInput: branchBInput,
      predictionTokens: predictionTokens,
      cycles: cycles,
      seed: seed
    )
    let mlx = try await runNestedOversizedMLX(
      modelDirectory: modelDirectory,
      seedText: seedText,
      branchAInput: branchAInput,
      nestedInput: nestedInput,
      branchBInput: branchBInput,
      maxTokens: predictionTokens,
      cycles: cycles,
      segmentSize: segmentSize
    )

    func signature(_ step: Step) -> String {
      "\(step.operation)@\(step.position)"
    }
    let llamaOperations = llama.steps.map(signature)
    let mlxOperations = mlx.steps.map(signature)
    let commonChecks = llama.checks
    let sameSemanticChecks = commonChecks.allSatisfy { name, expected in
      mlx.checks[name] == expected
    }
    let sameOperationSequence = llamaOperations == mlxOperations
    let sameWorkloadShape =
      llama.seedText == seedText && mlx.seedText == seedText
      && llama.branchAInput == branchAInput && mlx.branchAInput == branchAInput
      && llama.nestedInput == nestedInput && mlx.nestedInput == nestedInput
      && llama.branchBInput == branchBInput && mlx.branchBInput == branchBInput
      && llama.predictionTokens == predictionTokens && mlx.maxTokens == predictionTokens
      && llama.cycles == cycles && mlx.cycles == cycles
    let semanticMatrixPass =
      llama.overallPass && mlx.overallPass && sameSemanticChecks
      && sameOperationSequence && sameWorkloadShape

    return NestedMatrixReport(
      status: semanticMatrixPass ? "PASS_WITH_BOUNDARY" : "FAIL",
      protocolVersion: nestedMatrixProtocolVersion,
      boundary: nestedMatrixBoundary,
      seedText: seedText,
      branchAInput: branchAInput,
      nestedInput: nestedInput,
      branchBInput: branchBInput,
      predictionTokens: predictionTokens,
      cycles: cycles,
      commonChecks: commonChecks,
      llamaOperationSequence: llamaOperations,
      mlxOperationSequence: mlxOperations,
      sameSemanticChecks: sameSemanticChecks,
      sameOperationSequence: sameOperationSequence,
      sameWorkloadShape: sameWorkloadShape,
      bothBackendsPass: llama.overallPass && mlx.overallPass,
      crossBackendClosure: false,
      closureBlocker: "DIFFERENT_MODEL_ARTIFACTS_AND_TOKENIZERS",
      llama: llama,
      mlx: mlx,
      overallPass: semanticMatrixPass
    )
  }

  public struct NestedReport: Encodable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let host: String
    public let port: Int
    public let modelPath: String?
    public let seedText: String
    public let branchAInput: String
    public let nestedInput: String
    public let branchBInput: String
    public let predictionTokens: Int
    public let cycles: Int
    public let checks: [String: Bool]
    public let branchAContent: String
    public let nestedContent: String
    public let branchBContent: String
    public let nestedReplayContents: [String]
    public let steps: [Step]
    public let overallPass: Bool
  }

  public static let nestedProtocolVersion = "LAB.UI.BRANCH.SESSIONS.NESTED.V1"
  public static let nestedBoundary =
    "SWIFT_SESSION_CONTROL_PLANE / NESTED_BRANCH_GRAPH / "
    + "REPEATED_RELEASE_RESTORE_SWITCH / HARNESS_LEVEL / NOT_A_UI_PRODUCT"

  public static func runNestedLLAMA(
    host: String = "127.0.0.1",
    port: Int = 18080,
    seedText: String = "def is_palindrome(s):",
    branchAInput: String = "Now write tests for it.",
    nestedInput: String = "Explain the first test.",
    branchBInput: String = "Add a one-line TODO.",
    predictionTokens: Int = 2,
    cycles: Int = 2,
    seed: Int = 42
  ) async throws -> NestedReport {
    precondition(cycles > 0, "cycles must be positive")
    let backend = LLAMAServerExecutionStateBackend()
    let runtime = ExecutionContinuityCoordinator(backend: backend)
    let executor = LLAMAServerExecutionStateExecutor(
      baseURL: URL(string: "http://\(host):\(port)")!)
    let serverProps = try await executor.props()
    let seedTokens = try await executor.tokenizeText(seedText, addSpecialTokens: true)
    let branchATokens = try await executor.tokenizeText(branchAInput)
    let nestedTokens = try await executor.tokenizeText(nestedInput)
    let branchBTokens = try await executor.tokenizeText(branchBInput)

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

    let rootID = ExecutionID("nested-root")
    let branchAID = ExecutionID("nested-branch-a")
    let nestedID = ExecutionID("nested-branch-a1")
    let branchBID = ExecutionID("nested-branch-b")
    let forkPoint = ExecutionPosition(0)
    let continuedPosition = ExecutionPosition(1)

    let root = try await runtime.create(
      id: rootID,
      position: forkPoint,
      continuation: ExecutionContinuation(nextInput: "", continuationID: "root-0")
    )
    try await runtime.bindRepresentation(
      executionID: rootID,
      position: forkPoint,
      payload: LLAMAServerPrefixPayload(tokenPrefix: seedTokens)
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
    let nested = try await runtime.fork(
      ExecutionForkRequest(
        parent: branchA,
        childID: nestedID,
        childPosition: forkPoint,
        childContinuation: ExecutionContinuation(
          nextInput: nestedInput, continuationID: "branch-a1-0"
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
    record("fork", nested, started)

    let nestedForkPrefix = try backend.boundPrefix(for: nested).prefix

    started = DispatchTime.now().uptimeNanoseconds
    let branchAOutput = try await executor.complete(
      tokenPrefix: seedTokens + branchATokens,
      predictionTokens: predictionTokens,
      seed: seed
    )
    let advancedA = try await runtime.continueExecution(
      branchA,
      continuation: ExecutionContinuation(nextInput: branchAInput, continuationID: "branch-a-1")
    )
    record("continue", advancedA, started)
    try await runtime.bindRepresentation(
      executionID: advancedA.id,
      position: continuedPosition,
      payload: LLAMAServerPrefixPayload(
        tokenPrefix: seedTokens + branchATokens + (branchAOutput.tokens ?? []))
    )

    started = DispatchTime.now().uptimeNanoseconds
    let nestedOutput = try await executor.complete(
      tokenPrefix: seedTokens + nestedTokens,
      predictionTokens: predictionTokens,
      seed: seed
    )
    let advancedNested = try await runtime.continueExecution(
      nested,
      continuation: ExecutionContinuation(nextInput: nestedInput, continuationID: "branch-a1-1")
    )
    record("continue", advancedNested, started)
    let nestedAdvancedPrefix = seedTokens + nestedTokens + (nestedOutput.tokens ?? [])
    try await runtime.bindRepresentation(
      executionID: advancedNested.id,
      position: continuedPosition,
      payload: LLAMAServerPrefixPayload(tokenPrefix: nestedAdvancedPrefix)
    )

    started = DispatchTime.now().uptimeNanoseconds
    let branchBOutput = try await executor.complete(
      tokenPrefix: seedTokens + branchBTokens,
      predictionTokens: predictionTokens,
      seed: seed
    )
    let advancedB = try await runtime.continueExecution(
      branchB,
      continuation: ExecutionContinuation(nextInput: branchBInput, continuationID: "branch-b-1")
    )
    record("continue", advancedB, started)
    try await runtime.bindRepresentation(
      executionID: advancedB.id,
      position: continuedPosition,
      payload: LLAMAServerPrefixPayload(
        tokenPrefix: seedTokens + branchBTokens + (branchBOutput.tokens ?? []))
    )

    var replays: [LLAMAServerExecutionStateExecutor.Completion] = []
    var retainedAfterSwitch = true
    for index in 0..<cycles {
      started = DispatchTime.now().uptimeNanoseconds
      let current = try await backend.captureRepresentation(for: advancedNested)
      try await backend.releaseRepresentation(current)
      record("release", advancedNested, started)

      started = DispatchTime.now().uptimeNanoseconds
      let restored = try await runtime.restore(
        advancedNested,
        request: ExecutionRestoreRequest(
          targetPosition: forkPoint,
          continuation: ExecutionContinuation(
            nextInput: branchAInput, continuationID: "branch-a1-switch-0-\(index)"
          )
        )
      )
      record("switch", restored, started)
      let replay = try await executor.complete(
        tokenPrefix: seedTokens + branchATokens,
        predictionTokens: predictionTokens,
        seed: seed
      )
      replays.append(replay)

      started = DispatchTime.now().uptimeNanoseconds
      let switched = try await runtime.restore(
        restored,
        request: ExecutionRestoreRequest(
          targetPosition: continuedPosition,
          continuation: ExecutionContinuation(
            nextInput: nestedInput, continuationID: "branch-a1-switch-1-\(index)"
          )
        )
      )
      record("switch", switched, started)
      let binding = try backend.boundPrefix(for: switched)
      retainedAfterSwitch = retainedAfterSwitch && binding.prefix == nestedAdvancedPrefix
    }

    started = DispatchTime.now().uptimeNanoseconds
    try await runtime.discard(advancedNested)
    try await runtime.discard(advancedB)
    record("release", advancedNested, started)

    let branchABinding = try backend.boundPrefix(for: advancedA)
    let rootBinding = try backend.boundPrefix(for: root)
    let branchAAdvancedPrefix = seedTokens + branchATokens + (branchAOutput.tokens ?? [])
    let nestedBindingGone = (try? backend.boundPrefix(for: advancedNested))?.prefix == nil
    let branchBBindingGone = (try? backend.boundPrefix(for: advancedB))?.prefix == nil
    let branchAPrefix = seedTokens + branchATokens + (branchAOutput.tokens ?? [])
    let nestedAdvancedPhysicalPrefix = seedTokens + nestedTokens + (nestedOutput.tokens ?? [])
    let branchBAdvancedPrefix = seedTokens + branchBTokens + (branchBOutput.tokens ?? [])

    let checks = [
      "NESTED_LINEAGE_ISOLATED":
        branchA.lineage.parent == rootID && nested.lineage.parent == branchAID
        && nested.lineage.root == root.lineage.root && branchB.lineage.parent == rootID,
      "FORK_POINT_ISOLATED":
        nestedForkPrefix == seedTokens,
      "BRANCH_PREFIXES_DIVERGED":
        branchAPrefix != nestedAdvancedPhysicalPrefix
        && branchAPrefix != branchBAdvancedPrefix
        && nestedAdvancedPhysicalPrefix != branchBAdvancedPrefix,
      "REPEATED_RELEASE_RESTORE_REPLAYS":
        replays.count == cycles && replays.allSatisfy { $0 == branchAOutput },
      "REPEATED_ADVANCE_RETAINED":
        retainedAfterSwitch,
      "RELEASE_NESTED_AND_DIRECT_BRANCH":
        nestedBindingGone && branchBBindingGone,
      "PARENT_BRANCH_SURVIVES_RELEASE":
        branchABinding.prefix == branchAAdvancedPrefix,
      "ROOT_SURVIVES_RELEASE":
        rootBinding.prefix == seedTokens,
    ]
    let overallPass = checks.values.allSatisfy { $0 }

    return NestedReport(
      status: overallPass ? "PASS" : "FAIL",
      protocolVersion: nestedProtocolVersion,
      boundary: nestedBoundary,
      host: host,
      port: port,
      modelPath: serverProps.modelPath,
      seedText: seedText,
      branchAInput: branchAInput,
      nestedInput: nestedInput,
      branchBInput: branchBInput,
      predictionTokens: predictionTokens,
      cycles: cycles,
      checks: checks,
      branchAContent: branchAOutput.content,
      nestedContent: nestedOutput.content,
      branchBContent: branchBOutput.content,
      nestedReplayContents: replays.map(\.content),
      steps: steps,
      overallPass: overallPass
    )
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

    started = DispatchTime.now().uptimeNanoseconds
    try await runtime.discard(restoredA)
    try await runtime.discard(advancedB)
    record("release", restoredA, started)
    let branchAReleased = (try? backend.boundPrefix(for: restoredA))?.prefix == nil
    let branchBReleased = (try? backend.boundPrefix(for: advancedB))?.prefix == nil
    let rootSurvives = (try? backend.boundPrefix(for: switchedRoot))?.prefix != nil

    let rootAdvancedPrefix = (rootRun.payload as? OversizedPrefixPayload)?.tokenPrefix
    let branchAPrefix = (branchARun.payload as? OversizedPrefixPayload)?.tokenPrefix
    let branchBPrefix = (branchBRun.payload as? OversizedPrefixPayload)?.tokenPrefix
    let branchesDiverged =
      rootAdvancedPrefix != branchAPrefix && rootAdvancedPrefix != branchBPrefix
      && branchAPrefix != branchBPrefix
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

extension UIBranchSessions {
  public struct MLXNestedReport: Encodable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let modelDirectory: String
    public let segmentSize: Int
    public let segmentCount: Int
    public let seedText: String
    public let branchAInput: String
    public let nestedInput: String
    public let branchBInput: String
    public let maxTokens: Int
    public let cycles: Int
    public let checks: [String: Bool]
    public let branchAContent: String
    public let nestedContent: String
    public let branchBContent: String
    public let nestedReplayContents: [String]
    public let steps: [Step]
    public let peakFootprintMiB: Int64
    public let maxSwapMiB: Int64
    public let segmentTransitions: Int
    public let overallPass: Bool
  }

  public static let mlxNestedProtocolVersion = "LAB.UI.BRANCH.SESSIONS.MLX.NESTED.V1"
  public static let mlxNestedBoundary =
    "SWIFT_SESSION_CONTROL_PLANE / OVERSIZED_MLX_NESTED_BRANCH_GRAPH / "
    + "REPEATED_RELEASE_RESTORE_SWITCH / HARNESS_LEVEL / NOT_A_UI_PRODUCT"

  public static func runNestedOversizedMLX(
    modelDirectory: URL,
    seedText: String = "def is_palindrome(s):",
    branchAInput: String = "Now write tests for it.",
    nestedInput: String = "Explain the first test.",
    branchBInput: String = "Add a one-line TODO.",
    maxTokens: Int = 2,
    cycles: Int = 2,
    segmentSize: Int = 8
  ) async throws -> MLXNestedReport {
    precondition(cycles > 0, "cycles must be positive")
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

    let rootID = ExecutionID("mlx-nested-root")
    let branchAID = ExecutionID("mlx-nested-branch-a")
    let nestedID = ExecutionID("mlx-nested-branch-a1")
    let branchBID = ExecutionID("mlx-nested-branch-b")
    let forkPoint = ExecutionPosition(0)
    let continuedPosition = ExecutionPosition(1)
    let seedTokens = try executor.tokenizeSeedText(seedText)

    let root = try await runtime.create(
      id: rootID,
      position: forkPoint,
      continuation: ExecutionContinuation(nextInput: "", continuationID: "root-0")
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
    let nested = try await runtime.fork(
      ExecutionForkRequest(
        parent: branchA,
        childID: nestedID,
        childPosition: forkPoint,
        childContinuation: ExecutionContinuation(
          nextInput: nestedInput, continuationID: "branch-a1-0"
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
    record("fork", nested, started)
    let nestedForkPrefix = try backend.boundPrefix(for: nested).prefix

    func advance(
      _ state: ExecutionStateHandle,
      input: String,
      continuationID: String
    ) async throws -> (ExecutionStateHandle, generated: [Int], text: String, payload: any ExecutionRepresentationPayload) {
      let mark = DispatchTime.now().uptimeNanoseconds
      let result = try await executor.continueExecution(
        state, nextInputTokens: try executor.tokenizeText(input), maxTokens: maxTokens
      )
      let advanced = try await runtime.continueExecution(
        state,
        continuation: ExecutionContinuation(nextInput: input, continuationID: continuationID)
      )
      try await runtime.bindRepresentation(
        executionID: advanced.id,
        position: advanced.position,
        payload: result.updatedPayload
      )
      record("continue", advanced, mark)
      return (advanced, result.generatedTokenIDs, result.generatedText, result.updatedPayload)
    }

    let branchARun = try await advance(branchA, input: branchAInput, continuationID: "branch-a-1")
    let advancedA = branchARun.0
    let nestedRun = try await advance(nested, input: nestedInput, continuationID: "branch-a1-1")
    let advancedNested = nestedRun.0
    let nestedAdvancedPrefix = (nestedRun.payload as? OversizedPrefixPayload)?.tokenPrefix
    let branchBRun = try await advance(branchB, input: branchBInput, continuationID: "branch-b-1")
    let advancedB = branchBRun.0

    var replays: [ExecutionContinuationResult] = []
    var retainedAfterSwitch = true
    for index in 0..<cycles {
      started = DispatchTime.now().uptimeNanoseconds
      let current = try await backend.captureRepresentation(for: advancedNested)
      try await backend.releaseRepresentation(current)
      record("release", advancedNested, started)

      started = DispatchTime.now().uptimeNanoseconds
      let restored = try await runtime.restore(
        advancedNested,
        request: ExecutionRestoreRequest(
          targetPosition: forkPoint,
          continuation: ExecutionContinuation(
            nextInput: branchAInput, continuationID: "branch-a1-switch-0-\(index)"
          )
        )
      )
      record("switch", restored, started)
      let replay = try await executor.continueExecution(
        restored,
        nextInputTokens: try executor.tokenizeText(branchAInput),
        maxTokens: maxTokens
      )
      replays.append(replay)

      started = DispatchTime.now().uptimeNanoseconds
      let switched = try await runtime.restore(
        restored,
        request: ExecutionRestoreRequest(
          targetPosition: continuedPosition,
          continuation: ExecutionContinuation(
            nextInput: nestedInput, continuationID: "branch-a1-switch-1-\(index)"
          )
        )
      )
      record("switch", switched, started)
      let binding = try backend.boundPrefix(for: switched)
      retainedAfterSwitch = retainedAfterSwitch && binding.prefix == nestedAdvancedPrefix
    }

    started = DispatchTime.now().uptimeNanoseconds
    try await runtime.discard(advancedNested)
    try await runtime.discard(advancedB)
    record("release", advancedNested, started)

    let branchABinding = try backend.boundPrefix(for: advancedA)
    let rootBinding = try backend.boundPrefix(for: root)
    let branchAPrefix = (branchARun.payload as? OversizedPrefixPayload)?.tokenPrefix
    let branchBPrefix = (branchBRun.payload as? OversizedPrefixPayload)?.tokenPrefix
    let nestedBindingGone = (try? backend.boundPrefix(for: advancedNested))?.prefix == nil
    let branchBBindingGone = (try? backend.boundPrefix(for: advancedB))?.prefix == nil
    let oversizedUnderLimit = core.peakFootprintMiB <= 30 * 1024

    let checks = [
      "NESTED_LINEAGE_ISOLATED":
        branchA.lineage.parent == rootID && nested.lineage.parent == branchAID
        && nested.lineage.root == root.lineage.root && branchB.lineage.parent == rootID,
      "FORK_POINT_ISOLATED":
        nestedForkPrefix == seedTokens,
      "BRANCH_PREFIXES_DIVERGED":
        branchAPrefix != nestedAdvancedPrefix && branchAPrefix != branchBPrefix
        && nestedAdvancedPrefix != branchBPrefix,
      "REPEATED_RELEASE_RESTORE_REPLAYS":
        replays.count == cycles
        && replays.allSatisfy {
          $0.generatedTokenIDs == branchARun.generated && $0.generatedText == branchARun.text
        },
      "REPEATED_ADVANCE_RETAINED":
        retainedAfterSwitch,
      "RELEASE_NESTED_AND_DIRECT_BRANCH":
        nestedBindingGone && branchBBindingGone,
      "PARENT_BRANCH_SURVIVES_RELEASE":
        branchABinding.prefix == branchAPrefix,
      "ROOT_SURVIVES_RELEASE":
        rootBinding.prefix == seedTokens,
      "OVERSIZED_PROFILE_UNDER_30GIB":
        core.segments.count > 1 && oversizedUnderLimit,
    ]
    let overallPass = checks.values.allSatisfy { $0 }

    return MLXNestedReport(
      status: overallPass ? "PASS" : "FAIL",
      protocolVersion: mlxNestedProtocolVersion,
      boundary: mlxNestedBoundary,
      modelDirectory: modelDirectory.path,
      segmentSize: segmentSize,
      segmentCount: core.segments.count,
      seedText: seedText,
      branchAInput: branchAInput,
      nestedInput: nestedInput,
      branchBInput: branchBInput,
      maxTokens: maxTokens,
      cycles: cycles,
      checks: checks,
      branchAContent: branchARun.text,
      nestedContent: nestedRun.text,
      branchBContent: branchBRun.text,
      nestedReplayContents: replays.map(\.generatedText),
      steps: steps,
      peakFootprintMiB: core.peakFootprintMiB,
      maxSwapMiB: core.maxSwapMiB,
      segmentTransitions: core.segmentTransitions,
      overallPass: overallPass
    )
  }
}
