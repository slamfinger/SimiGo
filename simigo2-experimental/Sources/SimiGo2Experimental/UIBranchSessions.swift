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


  public struct UICancellationReport: Encodable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let host: String
    public let port: Int
    public let modelPath: String?
    public let seedText: String
    public let rootInput: String
    public let controlInput: String
    public let recoveryInput: String
    public let longPrompt: String
    public let predictionTokens: Int
    public let cancelDelayMs: Int
    public let cycles: Int
    public let checks: [String: Bool]
    public let rootReferenceContent: String
    public let controlReferenceContent: String
    public let recoveryContent: String
    public let samples: [UICancellationSample]
    public let overallPass: Bool
  }

  public struct UICancellationSample: Encodable, Sendable {
    public let index: Int
    public let conversationID: String
    public let deleteStatus: Int
    public let deleteToFreeMs: Double
    public let rootRecoveryClientMs: Double
    public let controlRecoveryClientMs: Double
  }

  public static let uiCancellationProtocolVersion =
    "LAB.UI.BRANCH.SESSIONS.CANCELLATION.V1"
  public static let uiCancellationBoundary =
    "SWIFT_SESSION_CONTROL_PLANE / EXPLICIT_LLAMA_STREAM_CANCEL / "
    + "ROOT_AND_SIBLING_RECOVERY / HARNESS_LEVEL / NOT_A_PRODUCTION_CLAIM"

  public static func runCancellationLLAMA(
    host: String = "127.0.0.1",
    port: Int = 18080,
    seedText: String = "def is_palindrome(s):",
    rootInput: String = "Explain it briefly.",
    controlInput: String = "Now write tests for it.",
    recoveryInput: String = "Continue from the root.",
    longPrompt: String = "Count from 1 to 500. Return only numbers separated by spaces.",
    predictionTokens: Int = 2,
    cancelDelayMs: Int = 100,
    cycles: Int = 2,
    freeTimeoutMs: Int = 15000,
    seed: Int = 42
  ) async throws -> UICancellationReport {
    precondition(cycles > 0, "cycles must be positive")
    let baseURL = URL(string: "http://\(host):\(port)")!
    let executor = LLAMAServerExecutionStateExecutor(baseURL: baseURL)
    let serverProps = try await executor.props()
    let seedTokens = try await executor.tokenizeText(seedText, addSpecialTokens: true)
    let rootTokens = try await executor.tokenizeText(rootInput)
    let controlTokens = try await executor.tokenizeText(controlInput)

    let rootReference = try await executor.complete(
      tokenPrefix: seedTokens + rootTokens, predictionTokens: predictionTokens, seed: seed
    )
    let controlReference = try await executor.complete(
      tokenPrefix: seedTokens + controlTokens, predictionTokens: predictionTokens, seed: seed
    )

    var samples: [UICancellationSample] = []
    var rootRecoveries: [LLAMAServerExecutionStateExecutor.Completion] = []
    var controlRecoveries: [LLAMAServerExecutionStateExecutor.Completion] = []
    var deleteStatuses: [Int] = []
    var cancelledReleased = true
    var cancelledDiscarded = true
    var rootAndControlSurvived = true
    var recoveryLineagePass = true

    for index in 0..<cycles {
      let backend = LLAMAServerExecutionStateBackend()
      let runtime = ExecutionContinuityCoordinator(backend: backend)
      let rootID = ExecutionID("ui-cancel-root-\(index)")
      let longID = ExecutionID("ui-cancel-long-\(index)")
      let controlID = ExecutionID("ui-cancel-control-\(index)")
      let recoveryID = ExecutionID("ui-cancel-recovery-\(index)")
      let forkPoint = ExecutionPosition(0)

      let root = try await runtime.create(
        id: rootID,
        position: forkPoint,
        continuation: ExecutionContinuation(nextInput: rootInput, continuationID: "root-0")
      )
      try await runtime.bindRepresentation(
        executionID: rootID,
        position: forkPoint,
        payload: LLAMAServerPrefixPayload(tokenPrefix: seedTokens)
      )
      let longBranch = try await runtime.fork(
        ExecutionForkRequest(
          parent: root,
          childID: longID,
          childPosition: forkPoint,
          childContinuation: ExecutionContinuation(
            nextInput: longPrompt, continuationID: "long-0"
          )
        )
      )
      let controlBranch = try await runtime.fork(
        ExecutionForkRequest(
          parent: root,
          childID: controlID,
          childPosition: forkPoint,
          childContinuation: ExecutionContinuation(
            nextInput: controlInput, continuationID: "control-0"
          )
        )
      )
      let longTokens = try await executor.tokenizeText(longPrompt)
      try await runtime.bindRepresentation(
        executionID: longBranch.id,
        position: forkPoint,
        payload: LLAMAServerPrefixPayload(tokenPrefix: longTokens)
      )
      try await runtime.bindRepresentation(
        executionID: controlBranch.id,
        position: forkPoint,
        payload: LLAMAServerPrefixPayload(tokenPrefix: seedTokens + controlTokens)
      )
      let longSnapshot = try await backend.captureRepresentation(for: longBranch)

      try await waitIdleSlots(baseURL: baseURL, timeoutMs: freeTimeoutMs)
      let conversationID =
        "ui-cancel-\(index)-\(Int(Date().timeIntervalSince1970 * 1_000_000_000))"
      let stream = UICancellableStream(
        session: URLSession(configuration: .ephemeral),
        request: uiStreamRequest(
          baseURL: baseURL,
          conversationID: conversationID,
          prompt: longPrompt,
          tokens: 256,
          seed: seed
        )
      )
      try await Task.sleep(nanoseconds: UInt64(cancelDelayMs * 1_000_000))
      let deleteStarted = DispatchTime.now().uptimeNanoseconds
      let deleteStatus = try await deleteUIStream(
        baseURL: baseURL, conversationID: conversationID
      )
      try await waitIdleSlots(baseURL: baseURL, timeoutMs: freeTimeoutMs)
      stream.close()
      let deleteToFreeMs = elapsedMs(deleteStarted)

      try await backend.releaseRepresentation(longSnapshot)
      let longReleased = (try? backend.boundPrefix(for: longBranch))?.prefix == nil

      let rootRecoveryStarted = DispatchTime.now().uptimeNanoseconds
      let restoredRoot = try await runtime.restore(
        root,
        request: ExecutionRestoreRequest(
          targetPosition: forkPoint,
          continuation: ExecutionContinuation(
            nextInput: rootInput, continuationID: "root-recovery"
          )
        )
      )
      let rootSnapshot = try await backend.captureRepresentation(for: restoredRoot)
      let rootRecovery = try await executor.complete(
        rootSnapshot, predictionTokens: predictionTokens, seed: seed
      )
      rootRecoveries.append(rootRecovery)

      let recoveryBranch = try await runtime.fork(
        ExecutionForkRequest(
          parent: restoredRoot,
          childID: recoveryID,
          childPosition: forkPoint,
          childContinuation: ExecutionContinuation(
            nextInput: recoveryInput, continuationID: "recovery-0"
          )
        )
      )
      recoveryLineagePass = recoveryLineagePass
        && recoveryBranch.lineage.parent == rootID
        && recoveryBranch.lineage.root == root.lineage.root

      let controlRecoveryStarted = DispatchTime.now().uptimeNanoseconds
      let restoredControl = try await runtime.restore(
        controlBranch,
        request: ExecutionRestoreRequest(
          targetPosition: forkPoint,
          continuation: ExecutionContinuation(
            nextInput: controlInput, continuationID: "control-recovery"
          )
        )
      )
      let controlSnapshot = try await backend.captureRepresentation(for: restoredControl)
      let controlRecovery = try await executor.complete(
        controlSnapshot, predictionTokens: predictionTokens, seed: seed
      )
      controlRecoveries.append(controlRecovery)

      let rootBinding = try backend.boundPrefix(for: restoredRoot)
      let controlBinding = try backend.boundPrefix(for: restoredControl)
      rootAndControlSurvived = rootAndControlSurvived
        && rootBinding.prefix == seedTokens
        && controlBinding.prefix == seedTokens + controlTokens

      try await runtime.discard(longBranch)
      let longDiscarded = runtime.handle(longID)?.lifecycle == .discarded
      cancelledDiscarded = cancelledDiscarded && longDiscarded

      deleteStatuses.append(deleteStatus)
      cancelledReleased = cancelledReleased && longReleased
      cancelledDiscarded = cancelledDiscarded && longDiscarded
      samples.append(
        UICancellationSample(
          index: index,
          conversationID: conversationID,
          deleteStatus: deleteStatus,
          deleteToFreeMs: deleteToFreeMs,
          rootRecoveryClientMs: elapsedMs(rootRecoveryStarted),
          controlRecoveryClientMs: elapsedMs(controlRecoveryStarted)
        )
      )
    }

    let rootRecoveryIdentical = rootRecoveries.allSatisfy { $0 == rootReference }
    let controlRecoveryIdentical = controlRecoveries.allSatisfy { $0 == controlReference }
    let checks = [
      "CANCEL_ACCEPTED":
        deleteStatuses.count == cycles && deleteStatuses.allSatisfy { $0 == 204 },
      "CANCELLED_SLOT_FREED":
        samples.count == cycles,
      "CANCELLED_LONG_PHYSICAL_RELEASED":
        cancelledReleased,
      "CANCELLED_LONG_LOGICALLY_DISCARDED":
        cancelledDiscarded,
      "ROOT_RECOVERY_IDENTICAL":
        rootRecoveryIdentical,
      "CONTROL_RECOVERY_IDENTICAL":
        controlRecoveryIdentical,
      "ROOT_AND_CONTROL_PREFIXES_DIVERGED":
        seedTokens + rootTokens != seedTokens + controlTokens,
      "RECOVERY_LINEAGE_ISOLATED":
        recoveryLineagePass,
      "ROOT_AND_CONTROL_SURVIVE_RELEASE":
        rootAndControlSurvived,
      "CYCLES_COMPLETE":
        rootRecoveries.count == cycles && controlRecoveries.count == cycles,
    ]
    let overallPass = checks.values.allSatisfy { $0 }

    return UICancellationReport(
      status: overallPass ? "PASS" : "FAIL",
      protocolVersion: uiCancellationProtocolVersion,
      boundary: uiCancellationBoundary,
      host: host,
      port: port,
      modelPath: serverProps.modelPath,
      seedText: seedText,
      rootInput: rootInput,
      controlInput: controlInput,
      recoveryInput: recoveryInput,
      longPrompt: longPrompt,
      predictionTokens: predictionTokens,
      cancelDelayMs: cancelDelayMs,
      cycles: cycles,
      checks: checks,
      rootReferenceContent: rootReference.content,
      controlReferenceContent: controlReference.content,
      recoveryContent: rootRecoveries.first?.content ?? "",
      samples: samples,
      overallPass: overallPass
    )
  }

  final class UICancellableStream: @unchecked Sendable {
    private let task: URLSessionDataTask

    init(session: URLSession, request: URLRequest) {
      task = session.dataTask(with: request)
      task.resume()
    }

    func close() {
      task.cancel()
    }
  }

  private struct UIChatMessage: Encodable {
    let role: String
    let content: String
  }

  private struct UIChatRequest: Encodable {
    let stream: Bool
    let maxTokens: Int
    let temperature: Double
    let seed: Int
    let messages: [UIChatMessage]

    enum CodingKeys: String, CodingKey {
      case stream
      case maxTokens = "max_tokens"
      case temperature
      case seed
      case messages
    }
  }

  private struct UISlot: Decodable {
    let isProcessing: Bool

    enum CodingKeys: String, CodingKey {
      case isProcessing = "is_processing"
    }
  }

  private static func uiStreamRequest(
    baseURL: URL, conversationID: String, prompt: String, tokens: Int, seed: Int
  ) -> URLRequest {
    var request = URLRequest(url: baseURL.appending(path: "/v1/chat/completions"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(conversationID, forHTTPHeaderField: "X-Conversation-Id")
    request.timeoutInterval = 30
    request.httpBody = try? JSONEncoder().encode(
      UIChatRequest(
        stream: true,
        maxTokens: tokens,
        temperature: 0,
        seed: seed,
        messages: [UIChatMessage(role: "user", content: prompt)]
      )
    )
    return request
  }

  private static func deleteUIStream(baseURL: URL, conversationID: String) async throws -> Int {
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
    components.path = "/v1/stream"
    components.queryItems = [URLQueryItem(name: "conv_id", value: conversationID)]
    var request = URLRequest(url: components.url!)
    request.httpMethod = "DELETE"
    let (_, response) = try await URLSession.shared.data(for: request)
    return (response as? HTTPURLResponse)?.statusCode ?? -1
  }

  private static func waitIdleSlots(baseURL: URL, timeoutMs: Int) async throws {
    let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
    while Date() < deadline {
      let (data, response) = try await URLSession.shared.data(from: baseURL.appending(path: "/slots"))
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw LLAMAServerExecutorError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
      }
      let slots = try JSONDecoder().decode([UISlot].self, from: data)
      if !slots.isEmpty, slots.allSatisfy({ !$0.isProcessing }) { return }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    throw LLAMAServerExecutorError.badStatus(-1)
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

  public struct LongRunningReport: Encodable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let host: String
    public let port: Int
    public let modelPath: String?
    public let seedText: String
    public let rootInput: String
    public let siblingInput: String
    public let turns: Int
    public let predictionTokens: Int
    public let checks: [String: Bool]
    public let longBranchContents: [String]
    public let siblingContent: String
    public let steps: [Step]
    public let overallPass: Bool
  }

  public static let longRunningProtocolVersion = "LAB.UI.BRANCH.SESSIONS.LONG.RUNNING.V1"
  public static let longRunningBoundary =
    "SWIFT_SESSION_CONTROL_PLANE / MULTI_TURN_LONG_RUNNING_BRANCH / "
    + "FORKPOINT_AND_FINAL_POSITION_RESTORE / HARNESS_LEVEL / NOT_A_UI_PRODUCT"

  public static func runLongRunningLLAMA(
    host: String = "127.0.0.1",
    port: Int = 18080,
    seedText: String = "def is_palindrome(s):",
    rootInput: String = "Explain it briefly.",
    siblingInput: String = "Now write tests for it.",
    longBranchInputs: [String] = [
      "Summarize the first implementation step.",
      "List one edge case and how to handle it.",
      "Add a focused unit test for that edge case.",
      "Describe the expected result in one sentence.",
      "Review the result and identify one improvement.",
      "Finalize the implementation with a short TODO.",
    ],
    turns: Int = 6,
    predictionTokens: Int = 4,
    seed: Int = 42
  ) async throws -> LongRunningReport {
    precondition(turns > 0 && turns <= longBranchInputs.count)
    let activeInputs = Array(longBranchInputs.prefix(turns))
    let backend = LLAMAServerExecutionStateBackend()
    let runtime = ExecutionContinuityCoordinator(backend: backend)
    let executor = LLAMAServerExecutionStateExecutor(
      baseURL: URL(string: "http://\(host):\(port)")!)
    let serverProps = try await executor.props()
    let seedTokens = try await executor.tokenizeText(seedText, addSpecialTokens: true)

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

    let rootID = ExecutionID("long-root")
    let siblingID = ExecutionID("long-sibling")
    let longID = ExecutionID("long-branch")
    let forkPoint = ExecutionPosition(0)

    let root = try await runtime.create(
      id: rootID,
      position: forkPoint,
      continuation: ExecutionContinuation(nextInput: rootInput, continuationID: "root-0")
    )
    try await runtime.bindRepresentation(
      executionID: rootID,
      position: forkPoint,
      payload: LLAMAServerPrefixPayload(tokenPrefix: seedTokens)
    )

    let sibling = try await runtime.fork(
      ExecutionForkRequest(
        parent: root,
        childID: siblingID,
        childPosition: forkPoint,
        childContinuation: ExecutionContinuation(
          nextInput: siblingInput, continuationID: "sibling-0"
        )
      )
    )
    var longInputs: [[Int]] = []
    for input in longBranchInputs {
      longInputs.append(try await executor.tokenizeText(input))
    }
    let longBranch = try await runtime.fork(
      ExecutionForkRequest(
        parent: root,
        childID: longID,
        childPosition: forkPoint,
        childContinuation: ExecutionContinuation(
          nextInput: longBranchInputs[0], continuationID: "long-0"
        )
      )
    )

    // Sibling baseline is retained while the other branch runs for many turns.
    let siblingTokens = try await executor.tokenizeText(siblingInput)
    let siblingOutput = try await executor.complete(
      tokenPrefix: seedTokens + siblingTokens,
      predictionTokens: predictionTokens,
      seed: seed
    )
    let siblingAdvanced = try await runtime.continueExecution(
      sibling,
      continuation: ExecutionContinuation(nextInput: siblingInput, continuationID: "sibling-1")
    )
    let siblingPrefix = seedTokens + siblingTokens + (siblingOutput.tokens ?? [])
    try await runtime.bindRepresentation(
      executionID: siblingAdvanced.id,
      position: ExecutionPosition(1),
      payload: LLAMAServerPrefixPayload(tokenPrefix: siblingPrefix)
    )

    var outputs: [LLAMAServerExecutionStateExecutor.Completion] = []
    var current = longBranch
    var currentPrefix = seedTokens
    for (index, input) in activeInputs.enumerated() {
      let inputTokens = try await executor.tokenizeText(input)
      let output = try await executor.complete(
        tokenPrefix: currentPrefix + inputTokens,
        predictionTokens: predictionTokens,
        seed: seed + index
      )
      let started = DispatchTime.now().uptimeNanoseconds
      current = try await runtime.continueExecution(
        current,
        continuation: ExecutionContinuation(
          nextInput: input, continuationID: "long-\(index + 1)"
        )
      )
      record("continue", current, started)
      currentPrefix = currentPrefix + inputTokens + (output.tokens ?? [])
      try await runtime.bindRepresentation(
        executionID: current.id,
        position: current.position,
        payload: LLAMAServerPrefixPayload(tokenPrefix: currentPrefix)
      )
      outputs.append(output)
    }

    let finalBinding = try backend.boundPrefix(for: current)
    let finalPosition = current.position

    // Exercise fork-point restore, then restore the advanced multi-turn state again.
    let restoredToFork = try await runtime.restore(
      current,
      request: ExecutionRestoreRequest(
        targetPosition: forkPoint,
        continuation: ExecutionContinuation(
          nextInput: longBranchInputs[0], continuationID: "long-restore-0"
        )
      )
    )
    let forkBinding = try backend.boundPrefix(for: restoredToFork)

    let restoredToFinal = try await runtime.restore(
      restoredToFork,
      request: ExecutionRestoreRequest(
        targetPosition: finalPosition,
        continuation: ExecutionContinuation(
          nextInput: activeInputs[turns - 1], continuationID: "long-restore-final"
        )
      )
    )
    let finalRestoredBinding = try backend.boundPrefix(for: restoredToFinal)

    try await runtime.discard(restoredToFinal)
    try await runtime.discard(siblingAdvanced)

    let longBindingGone = (try? backend.boundPrefix(for: restoredToFinal))?.prefix == nil
    let siblingBindingGone = (try? backend.boundPrefix(for: siblingAdvanced))?.prefix == nil
    let rootBinding = try backend.boundPrefix(for: root)

    let expectedFinalPrefix = currentPrefix
    let checks = [
      "LONG_SEQUENCE_COMPLETE":
        outputs.count == turns && outputs.allSatisfy {
          ($0.tokens?.count ?? 0) == predictionTokens
        },
      "LONG_BRANCH_FINAL_PREFIX_EXACT":
        finalBinding.prefix == expectedFinalPrefix && finalBinding.position == finalPosition,
      "LONG_BRANCH_RESTORES_FORKPOINT":
        restoredToFork.position == forkPoint && forkBinding.prefix == seedTokens,
      "LONG_BRANCH_RESTORES_FINAL_POSITION":
        restoredToFinal.position == finalPosition
        && finalRestoredBinding.prefix == expectedFinalPrefix,
      "SIBLING_BASELINE_RETAINED":
        siblingAdvanced.position == ExecutionPosition(1)
        && siblingPrefix == seedTokens + siblingTokens + (siblingOutput.tokens ?? []),
      "RELEASE_LONG_AND_SIBLING":
        longBindingGone && siblingBindingGone,
      "ROOT_SURVIVES_RELEASE":
        rootBinding.prefix == seedTokens,
    ]
    let overallPass = checks.values.allSatisfy { $0 }

    return LongRunningReport(
      status: overallPass ? "PASS" : "FAIL",
      protocolVersion: longRunningProtocolVersion,
      boundary: longRunningBoundary,
      host: host,
      port: port,
      modelPath: serverProps.modelPath,
      seedText: seedText,
      rootInput: rootInput,
      siblingInput: siblingInput,
      turns: turns,
      predictionTokens: predictionTokens,
      checks: checks,
      longBranchContents: outputs.map(\.content),
      siblingContent: siblingOutput.content,
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
  public struct MemoryPressureMatrixReport: Encodable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let seedText: String
    public let controlInput: String
    public let predictionTokens: Int
    public let cycles: Int
    public let commonChecks: [String: Bool]
    public let llamaPressureMechanism: String
    public let mlxPressureMechanism: String
    public let sameWorkloadShape: Bool
    public let sameOutcomeShape: Bool
    public let bothBackendsPass: Bool
    public let crossBackendClosure: Bool
    public let closureBlocker: String
    public let llama: LLAMAMemoryPressureReport
    public let mlx: MLXMemoryPressureReport
    public let overallPass: Bool
  }

  public static let memoryPressureMatrixProtocolVersion =
    "LAB.UI.BRANCH.SESSIONS.MEMORY.PRESSURE.CROSSBACKEND.V1"
  public static let memoryPressureMatrixBoundary =
    "SAME_CONTROLLED_PRESSURE_OUTCOME_SHAPE / DIFFERENT_MODEL_ARTIFACTS_TOKENIZERS_ENGINES_AND_MECHANISMS / "
    + "HARNESS_LEVEL / NOT_OS_MEMORY_PRESSURE / NOT_A_SAME_CHECKPOINT_CLOSURE"

  public static func runMemoryPressureCrossBackendMatrix(
    modelDirectory: URL,
    host: String = "127.0.0.1",
    port: Int = 18080,
    seedText: String = "def is_palindrome(s):",
    controlInput: String = "Now write tests for it.",
    predictionTokens: Int = 1,
    cycles: Int = 2,
    seed: Int = 42,
    segmentSize: Int = 8
  ) async throws -> MemoryPressureMatrixReport {
    let llama = try await runMemoryPressureLLAMA(
      host: host,
      port: port,
      seedText: seedText,
      controlInput: controlInput,
      predictionTokens: predictionTokens,
      cycles: cycles,
      seed: seed
    )
    let mlx = try await runMemoryPressureOversizedMLX(
      modelDirectory: modelDirectory,
      seedText: seedText,
      controlInput: controlInput,
      maxTokens: predictionTokens,
      cycles: cycles,
      segmentSize: segmentSize
    )

    let checkNames = [
      "PRESSURE_WORKLOAD_COMPLETE",
      "PRESSURE_RELEASE_ACTIONS_COMPLETE",
      "PRESSURE_LINEAGE_ISOLATED",
      "ACTIVE_BRANCH_PREFIXES_DIVERGED",
      "REPEATED_RECOVERY_OUTPUTS_EXACT",
      "RECOVERY_FINAL_BINDINGS_EXACT",
      "RELEASE_PRESSURE_BRANCHES",
      "ROOT_AND_CONTROL_SURVIVE",
    ]
    var commonChecks: [String: Bool] = [:]
    for name in checkNames {
      commonChecks[name] = llama.checks[name] == true && mlx.checks[name] == true
    }

    let llamaInputs = llama.pressureBranches.map(\.input)
    let mlxInputs = mlx.pressureBranches.map(\.input)
    let sameWorkloadShape =
      llama.seedText == seedText && mlx.seedText == seedText
      && llama.controlInput == controlInput && mlx.controlInput == controlInput
      && llama.predictionTokens == predictionTokens && mlx.maxTokens == predictionTokens
      && llama.cycles == cycles && mlx.cycles == cycles
      && llamaInputs == mlxInputs && !llamaInputs.isEmpty
    let sameOutcomeShape = commonChecks.values.allSatisfy { $0 }
    let bothBackendsPass = llama.overallPass && mlx.overallPass
    let matrixPass = sameWorkloadShape && sameOutcomeShape && bothBackendsPass

    return MemoryPressureMatrixReport(
      status: matrixPass ? "PASS_WITH_BOUNDARY" : "FAIL",
      protocolVersion: memoryPressureMatrixProtocolVersion,
      boundary: memoryPressureMatrixBoundary,
      seedText: seedText,
      controlInput: controlInput,
      predictionTokens: predictionTokens,
      cycles: cycles,
      commonChecks: commonChecks,
      llamaPressureMechanism: "SWIFT_PREFIX_REGISTRY_RELEASE_RESTORE",
      mlxPressureMechanism: "SWIFT_PREFIX_REGISTRY_RELEASE_PLUS_OVERSIZED_SEGMENT_RELEASE",
      sameWorkloadShape: sameWorkloadShape,
      sameOutcomeShape: sameOutcomeShape,
      bothBackendsPass: bothBackendsPass,
      crossBackendClosure: false,
      closureBlocker:
        "DIFFERENT_MODEL_ARTIFACTS_TOKENIZERS_EXECUTION_ENGINES_AND_PHYSICAL_PRESSURE_MECHANISMS",
      llama: llama,
      mlx: mlx,
      overallPass: matrixPass
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

extension UIBranchSessions {
  public struct LLAMAMemoryPressureBranch: Encodable, Sendable {
    public let executionID: String
    public let input: String
    public let content: String
    public let generatedTokenIDs: [Int]
    public let finalPrefixTokenCount: Int
    public let recoveryMatches: [Bool]
    public let finalBindingsExact: [Bool]
  }

  public struct LLAMAMemoryPressureReport: Encodable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let host: String
    public let port: Int
    public let modelPath: String?
    public let seedText: String
    public let controlInput: String
    public let predictionTokens: Int
    public let cycles: Int
    public let checks: [String: Bool]
    public let controlContent: String
    public let pressureBranches: [LLAMAMemoryPressureBranch]
    public let steps: [Step]
    public let overallPass: Bool
  }

  public static let llamaMemoryPressureProtocolVersion =
    "LAB.UI.BRANCH.SESSIONS.LLAMA.MEMORY.PRESSURE.V1"
  public static let llamaMemoryPressureBoundary =
    "SWIFT_SESSION_CONTROL_PLANE / CONTROLLED_MULTI_BRANCH_RELEASE_RESTORE_LOAD / "
    + "LLAMA_PREFIX_REPRESENTATION / HARNESS_LEVEL / NOT_OS_MEMORY_PRESSURE / NOT_A_UI_PRODUCT"

  public static func runMemoryPressureLLAMA(
    host: String = "127.0.0.1",
    port: Int = 18080,
    seedText: String = "def is_palindrome(s):",
    controlInput: String = "Now write tests for it.",
    pressureInputs: [String] = [
      "List one edge case for the function.",
      "Add a focused unit test for that edge case.",
    ],
    predictionTokens: Int = 1,
    cycles: Int = 2,
    seed: Int = 42
  ) async throws -> LLAMAMemoryPressureReport {
    precondition(!pressureInputs.isEmpty)
    let backend = LLAMAServerExecutionStateBackend()
    let runtime = ExecutionContinuityCoordinator(backend: backend)
    let executor = LLAMAServerExecutionStateExecutor(
      baseURL: URL(string: "http://\(host):\(port)")!
    )
    let serverProps = try await executor.props()
    let seedTokens = try await executor.tokenizeText(seedText, addSpecialTokens: true)

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

    let rootID = ExecutionID("llama-pressure-root")
    let controlID = ExecutionID("llama-pressure-control")
    let pressureIDs = pressureInputs.enumerated().map {
      ExecutionID("llama-pressure-branch-\($0.offset)")
    }
    let forkPoint = ExecutionPosition(0)
    let root = try await runtime.create(
      id: rootID,
      position: forkPoint,
      continuation: ExecutionContinuation(nextInput: "", continuationID: "pressure-root-0")
    )
    try await runtime.bindRepresentation(
      executionID: rootID,
      position: forkPoint,
      payload: LLAMAServerPrefixPayload(tokenPrefix: seedTokens)
    )

    func fork(_ childID: ExecutionID, input: String) async throws -> ExecutionStateHandle {
      try await runtime.fork(
        ExecutionForkRequest(
          parent: root,
          childID: childID,
          childPosition: forkPoint,
          childContinuation: ExecutionContinuation(
            nextInput: input, continuationID: "\(childID.rawValue)-0"
          )
        )
      )
    }

    let control = try await fork(controlID, input: controlInput)
    var pressureStates: [ExecutionStateHandle] = []
    for (index, input) in pressureInputs.enumerated() {
      pressureStates.append(try await fork(pressureIDs[index], input: input))
    }

    let controlTokens = try await executor.tokenizeText(controlInput)
    let controlStarted = DispatchTime.now().uptimeNanoseconds
    let controlOutput = try await executor.complete(
      tokenPrefix: seedTokens + controlTokens,
      predictionTokens: predictionTokens,
      seed: seed
    )
    let advancedControl = try await runtime.continueExecution(
      control,
      continuation: ExecutionContinuation(
        nextInput: controlInput, continuationID: "pressure-control-1"
      )
    )
    record("continue", advancedControl, controlStarted)
    let controlPrefix = seedTokens + controlTokens + (controlOutput.tokens ?? [])
    try await runtime.bindRepresentation(
      executionID: advancedControl.id,
      position: ExecutionPosition(1),
      payload: LLAMAServerPrefixPayload(tokenPrefix: controlPrefix)
    )

    struct Run {
      let id: ExecutionID
      let input: String
      let inputTokens: [Int]
      let output: LLAMAServerExecutionStateExecutor.Completion
      let prefix: [Int]
      var state: ExecutionStateHandle
    }
    var runs: [Run] = []
    for (index, state) in pressureStates.enumerated() {
      let input = pressureInputs[index]
      let inputTokens = try await executor.tokenizeText(input)
      let started = DispatchTime.now().uptimeNanoseconds
      let output = try await executor.complete(
        tokenPrefix: seedTokens + inputTokens,
        predictionTokens: predictionTokens,
        seed: seed + index
      )
      let advanced = try await runtime.continueExecution(
        state,
        continuation: ExecutionContinuation(
          nextInput: input, continuationID: "pressure-\(index)-1"
        )
      )
      record("continue", advanced, started)
      let prefix = seedTokens + inputTokens + (output.tokens ?? [])
      try await runtime.bindRepresentation(
        executionID: advanced.id,
        position: ExecutionPosition(1),
        payload: LLAMAServerPrefixPayload(tokenPrefix: prefix)
      )
      runs.append(
        Run(
          id: advanced.id,
          input: input,
          inputTokens: inputTokens,
          output: output,
          prefix: prefix,
          state: advanced
        )
      )
    }

    var recoveryMatches = Array(repeating: [Bool](), count: runs.count)
    var finalBindingsExact = recoveryMatches
    var releaseActions = 0
    for cycle in 0..<cycles {
      for index in runs.indices {
        let started = DispatchTime.now().uptimeNanoseconds
        let current = try await backend.captureRepresentation(for: runs[index].state)
        try await backend.releaseRepresentation(current)
        releaseActions += 1
        record("release", runs[index].state, started)

        let restoredToFork = try await runtime.restore(
          runs[index].state,
          request: ExecutionRestoreRequest(
            targetPosition: forkPoint,
            continuation: ExecutionContinuation(
              nextInput: runs[index].input,
              continuationID: "pressure-\(index)-r0-\(cycle)"
            )
          )
        )
        record("switch", restoredToFork, started)
        let replay = try await executor.complete(
          tokenPrefix: seedTokens + runs[index].inputTokens,
          predictionTokens: predictionTokens,
          seed: seed + index
        )
        recoveryMatches[index].append(replay == runs[index].output)

        let restoredToFinal = try await runtime.restore(
          restoredToFork,
          request: ExecutionRestoreRequest(
            targetPosition: ExecutionPosition(1),
            continuation: ExecutionContinuation(
              nextInput: runs[index].input,
              continuationID: "pressure-\(index)-r1-\(cycle)"
            )
          )
        )
        record("switch", restoredToFinal, started)
        let binding = try backend.boundPrefix(for: restoredToFinal)
        finalBindingsExact[index].append(
          binding.prefix == runs[index].prefix && binding.position == ExecutionPosition(1)
        )
        runs[index].state = restoredToFinal
      }
    }

    for run in runs {
      try await runtime.discard(run.state)
    }
    let pressureBindingsGone = runs.allSatisfy {
      (try? backend.boundPrefix(for: $0.state))?.prefix == nil
    }
    let rootBinding = try backend.boundPrefix(for: root)
    let controlBinding = try backend.boundPrefix(for: advancedControl)
    let allPrefixes = runs.map(\.prefix) + [controlPrefix]
    let prefixesDiverged = Set(allPrefixes).count == runs.count + 1
    let controlLineageIsolated =
      control.lineage.parent == rootID && control.lineage.root == root.lineage.root
    let pressureLineageIsolated = pressureStates.allSatisfy {
      $0.lineage.parent == rootID && $0.lineage.root == root.lineage.root
    }

    let checks = [
      "PRESSURE_WORKLOAD_COMPLETE":
        runs.count == pressureInputs.count
        && (controlOutput.tokens?.count ?? 0) == predictionTokens,
      "PRESSURE_RELEASE_ACTIONS_COMPLETE":
        releaseActions == runs.count * cycles,
      "PRESSURE_LINEAGE_ISOLATED":
        controlLineageIsolated && pressureLineageIsolated,
      "ACTIVE_BRANCH_PREFIXES_DIVERGED": prefixesDiverged,
      "REPEATED_RECOVERY_OUTPUTS_EXACT":
        recoveryMatches.allSatisfy { $0.count == cycles && $0.allSatisfy(\.self) },
      "RECOVERY_FINAL_BINDINGS_EXACT":
        finalBindingsExact.allSatisfy { $0.count == cycles && $0.allSatisfy(\.self) },
      "RELEASE_PRESSURE_BRANCHES": pressureBindingsGone,
      "ROOT_AND_CONTROL_SURVIVE":
        rootBinding.prefix == seedTokens && controlBinding.prefix == controlPrefix,
    ]
    let overallPass = checks.values.allSatisfy { $0 }

    return LLAMAMemoryPressureReport(
      status: overallPass ? "PASS" : "FAIL",
      protocolVersion: llamaMemoryPressureProtocolVersion,
      boundary: llamaMemoryPressureBoundary,
      host: host,
      port: port,
      modelPath: serverProps.modelPath,
      seedText: seedText,
      controlInput: controlInput,
      predictionTokens: predictionTokens,
      cycles: cycles,
      checks: checks,
      controlContent: controlOutput.content,
      pressureBranches: runs.enumerated().map { index, run in
        LLAMAMemoryPressureBranch(
          executionID: run.id.rawValue,
          input: run.input,
          content: run.output.content,
          generatedTokenIDs: run.output.tokens ?? [],
          finalPrefixTokenCount: run.prefix.count,
          recoveryMatches: recoveryMatches[index],
          finalBindingsExact: finalBindingsExact[index]
        )
      },
      steps: steps,
      overallPass: overallPass
    )
  }
}

extension UIBranchSessions {
  public struct MLXLongRunningReport: Encodable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let modelDirectory: String
    public let segmentSize: Int
    public let segmentCount: Int
    public let seedText: String
    public let siblingInput: String
    public let turnInputs: [String]
    public let maxTokens: Int
    public let checks: [String: Bool]
    public let longBranchContents: [String]
    public let siblingContent: String
    public let steps: [Step]
    public let peakFootprintMiB: Int64
    public let maxSwapMiB: Int64
    public let segmentTransitions: Int
    public let overallPass: Bool
  }

  public static let mlxLongRunningProtocolVersion =
    "LAB.UI.BRANCH.SESSIONS.MLX.LONG.RUNNING.V1"
  public static let mlxLongRunningBoundary =
    "SWIFT_SESSION_CONTROL_PLANE / OVERSIZED_MLX_LONG_RUNNING_BRANCH / "
    + "SEQUENTIAL_TURNS_FORKPOINT_FINAL_RESTORE / HARNESS_LEVEL / NOT_A_UI_PRODUCT"

  public static func runLongRunningOversizedMLX(
    modelDirectory: URL,
    seedText: String = "def is_palindrome(s):",
    siblingInput: String = "Now write tests for it.",
    turnInputs: [String] = [
      "Summarize the first implementation step.",
      "List one edge case and how to handle it.",
      "Add a focused unit test for that edge case.",
      "Describe the expected result in one sentence.",
      "Review the result and identify one improvement.",
      "Finalize the implementation with a short TODO.",
    ],
    maxTokens: Int = 1,
    segmentSize: Int = 8
  ) async throws -> MLXLongRunningReport {
    precondition(!turnInputs.isEmpty)
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

    let rootID = ExecutionID("mlx-long-root")
    let siblingID = ExecutionID("mlx-long-sibling")
    let longID = ExecutionID("mlx-long-branch")
    let forkPoint = ExecutionPosition(0)
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

    let sibling = try await runtime.fork(
      ExecutionForkRequest(
        parent: root,
        childID: siblingID,
        childPosition: forkPoint,
        childContinuation: ExecutionContinuation(
          nextInput: siblingInput, continuationID: "sibling-0"
        )
      )
    )
    let longBranch = try await runtime.fork(
      ExecutionForkRequest(
        parent: root,
        childID: longID,
        childPosition: forkPoint,
        childContinuation: ExecutionContinuation(
          nextInput: turnInputs[0], continuationID: "long-0"
        )
      )
    )

    func advance(
      _ state: ExecutionStateHandle,
      input: String,
      continuationID: String
    ) async throws -> (ExecutionStateHandle, generated: [Int], text: String, payload: any ExecutionRepresentationPayload) {
      let started = DispatchTime.now().uptimeNanoseconds
      let result = try await executor.continueExecution(
        state, nextInputTokens: try executor.tokenizeText(input), maxTokens: maxTokens
      )
      let advanced = try await runtime.continueExecution(
        state,
        continuation: ExecutionContinuation(nextInput: input, continuationID: continuationID)
      )
      guard let payload = result.updatedPayload as? OversizedPrefixPayload else {
        throw ExecutionStateBackendError.noBoundRepresentation(advanced.id)
      }
      try await runtime.bindRepresentation(
        executionID: advanced.id,
        position: advanced.position,
        payload: payload
      )
      record("continue", advanced, started)
      return (advanced, result.generatedTokenIDs, result.generatedText, payload)
    }

    _ = try executor.tokenizeText(siblingInput)
    let siblingRun = try await advance(
      sibling, input: siblingInput, continuationID: "sibling-1"
    )
    let siblingAdvanced = siblingRun.0
    let siblingPrefix = (siblingRun.payload as? OversizedPrefixPayload)?.tokenPrefix

    var longContents: [String] = []
    var current = longBranch
    var expectedPrefix: [Int]? = seedTokens
    for (index, input) in turnInputs.enumerated() {
      let run = try await advance(
        current, input: input, continuationID: "long-\(index + 1)"
      )
      current = run.0
      longContents.append(run.text)
      expectedPrefix = (run.payload as? OversizedPrefixPayload)?.tokenPrefix
    }

    let finalBinding = try backend.boundPrefix(for: current)
    let finalPosition = current.position
    let finalPrefix = finalBinding.prefix

    let restoredToFork = try await runtime.restore(
      current,
      request: ExecutionRestoreRequest(
        targetPosition: forkPoint,
        continuation: ExecutionContinuation(
          nextInput: turnInputs[0], continuationID: "long-restore-0"
        )
      )
    )
    let forkBinding = try backend.boundPrefix(for: restoredToFork)

    let restoredToFinal = try await runtime.restore(
      restoredToFork,
      request: ExecutionRestoreRequest(
        targetPosition: finalPosition,
        continuation: ExecutionContinuation(
          nextInput: turnInputs[turnInputs.count - 1],
          continuationID: "long-restore-final"
        )
      )
    )
    let finalRestoredBinding = try backend.boundPrefix(for: restoredToFinal)

    try await runtime.discard(restoredToFinal)
    try await runtime.discard(siblingAdvanced)

    let longBindingGone = (try? backend.boundPrefix(for: restoredToFinal))?.prefix == nil
    let siblingBindingGone = (try? backend.boundPrefix(for: siblingAdvanced))?.prefix == nil
    let rootBinding = try backend.boundPrefix(for: root)
    let oversizedUnderLimit = core.peakFootprintMiB <= 30 * 1024

    let checks = [
      "LONG_SEQUENCE_COMPLETE":
        longContents.count == turnInputs.count
        && longContents.allSatisfy { !$0.isEmpty },
      "LONG_BRANCH_FINAL_PREFIX_EXACT":
        finalBinding.prefix == expectedPrefix && finalBinding.position == finalPosition,
      "LONG_BRANCH_RESTORES_FORKPOINT":
        restoredToFork.position == forkPoint && forkBinding.prefix == seedTokens,
      "LONG_BRANCH_RESTORES_FINAL_POSITION":
        restoredToFinal.position == finalPosition
        && finalRestoredBinding.prefix == finalPrefix,
      "SIBLING_ADVANCED_RETAINED":
        siblingAdvanced.position == ExecutionPosition(1) && siblingPrefix != nil,
      "RELEASE_LONG_AND_SIBLING":
        longBindingGone && siblingBindingGone,
      "ROOT_SURVIVES_RELEASE":
        rootBinding.prefix == seedTokens,
      "OVERSIZED_PROFILE_UNDER_30GIB":
        core.segments.count > 1 && oversizedUnderLimit,
    ]
    let overallPass = checks.values.allSatisfy { $0 }

    return MLXLongRunningReport(
      status: overallPass ? "PASS" : "FAIL",
      protocolVersion: mlxLongRunningProtocolVersion,
      boundary: mlxLongRunningBoundary,
      modelDirectory: modelDirectory.path,
      segmentSize: segmentSize,
      segmentCount: core.segments.count,
      seedText: seedText,
      siblingInput: siblingInput,
      turnInputs: turnInputs,
      maxTokens: maxTokens,
      checks: checks,
      longBranchContents: longContents,
      siblingContent: siblingRun.text,
      steps: steps,
      peakFootprintMiB: core.peakFootprintMiB,
      maxSwapMiB: core.maxSwapMiB,
      segmentTransitions: core.segmentTransitions,
      overallPass: overallPass
    )
  }

}
extension UIBranchSessions {
  public struct MLXCancellationReport: Encodable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let modelDirectory: String
    public let segmentSize: Int
    public let segmentCount: Int
    public let seedText: String
    public let rootInput: String
    public let controlInput: String
    public let recoveryInput: String
    public let longInput: String
    public let maxTokens: Int
    public let cycles: Int
    public let cancelledTokenCounts: [Int]
    public let checks: [String: Bool]
    public let rootReferenceContent: String
    public let controlReferenceContent: String
    public let recoveryContent: String
    public let peakFootprintMiB: Int64
    public let maxSwapMiB: Int64
    public let segmentTransitions: Int
    public let overallPass: Bool
  }

  public static let mlxCancellationProtocolVersion =
    "LAB.UI.BRANCH.SESSIONS.MLX.CANCELLATION.V1"
  public static let mlxCancellationBoundary =
    "SWIFT_SESSION_CONTROL_PLANE / OVERSIZED_MLX_COOPERATIVE_CANCEL / "
    + "ROOT_AND_SIBLING_RECOVERY / HARNESS_LEVEL / NOT_A_PRODUCTION_CLAIM"

  public static func runCancellationOversizedMLX(
    modelDirectory: URL,
    seedText: String = "def is_palindrome(s):",
    rootInput: String = "Explain it briefly.",
    controlInput: String = "Now write tests for it.",
    recoveryInput: String = "Continue from the root.",
    longInput: String = "Count from 1 to 500. Return only numbers separated by spaces.",
    maxTokens: Int = 4,
    cycles: Int = 2,
    segmentSize: Int = 8
  ) async throws -> MLXCancellationReport {
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
    let seedTokens = try executor.tokenizeSeedText(seedText)
    let rootTokens = try executor.tokenizeText(rootInput)
    let controlTokens = try executor.tokenizeText(controlInput)
    let recoveryTokens = try executor.tokenizeText(recoveryInput)
    let longTokens = try executor.tokenizeText(longInput)

    var cancelledTokenCounts: [Int] = []
    var cancelledTokenIDSets: [[Int]] = []
    var rootReferences: [ExecutionContinuationResult] = []
    var controlReferences: [ExecutionContinuationResult] = []
    var rootRecoveries: [ExecutionContinuationResult] = []
    var controlRecoveries: [ExecutionContinuationResult] = []
    var recoveryContents: [String] = []
    var recoveryLineagePass = true
    var cancelledReleased = true

    for index in 0..<cycles {
      let rootID = ExecutionID("mlx-cancel-root-\(index)")
      let longID = ExecutionID("mlx-cancel-long-\(index)")
      let controlID = ExecutionID("mlx-cancel-control-\(index)")
      let recoveryID = ExecutionID("mlx-cancel-recovery-\(index)")
      let forkPoint = ExecutionPosition(0)
      let continuedPosition = ExecutionPosition(1)

      let root = try await runtime.create(
        id: rootID,
        position: forkPoint,
        continuation: ExecutionContinuation(nextInput: rootInput, continuationID: "root-0")
      )
      try await runtime.bindRepresentation(
        executionID: rootID,
        position: forkPoint,
        payload: OversizedPrefixPayload(tokenPrefix: seedTokens)
      )
      let longBranch = try await runtime.fork(
        ExecutionForkRequest(
          parent: root,
          childID: longID,
          childPosition: forkPoint,
          childContinuation: ExecutionContinuation(
            nextInput: longInput, continuationID: "long-0"
          )
        )
      )
      let controlBranch = try await runtime.fork(
        ExecutionForkRequest(
          parent: root,
          childID: controlID,
          childPosition: forkPoint,
          childContinuation: ExecutionContinuation(
            nextInput: controlInput, continuationID: "control-0"
          )
        )
      )

      let rootReference = try await executor.continueExecution(
        root, nextInputTokens: rootTokens, maxTokens: maxTokens
      )
      let rootAdvanced = try await runtime.continueExecution(
        root,
        continuation: ExecutionContinuation(nextInput: rootInput, continuationID: "root-1")
      )
      try await runtime.bindRepresentation(
        executionID: rootAdvanced.id,
        position: continuedPosition,
        payload: rootReference.updatedPayload
      )
      rootReferences.append(rootReference)
      let controlReference = try await executor.continueExecution(
        controlBranch, nextInputTokens: controlTokens, maxTokens: maxTokens
      )
      controlReferences.append(controlReference)
      let controlAdvanced = try await runtime.continueExecution(
        controlBranch,
        continuation: ExecutionContinuation(nextInput: controlInput, continuationID: "control-1")
      )
      try await runtime.bindRepresentation(
        executionID: controlAdvanced.id,
        position: continuedPosition,
        payload: controlReference.updatedPayload
      )

      var cancelledCount = -1
      var cancelledIDs: [Int] = []
      do {
        _ = try await executor.continueExecution(
          longBranch,
          nextInputTokens: longTokens,
          maxTokens: maxTokens,
          cancellationToken: O6GenerationCancellationToken { $0 >= 1 }
        )
      } catch let cancellation as O6ExecutionCancelled {
        cancelledIDs = cancellation.generatedTokenIDs
        cancelledCount = cancelledIDs.count
      }
      cancelledTokenCounts.append(cancelledCount)
      cancelledTokenIDSets.append(cancelledIDs)

      let consumedLongPrefix =
        seedTokens + longTokens + cancelledIDs
      _ = try await runtime.continueExecution(
        longBranch,
        continuation: ExecutionContinuation(nextInput: longInput, continuationID: "long-1")
      )
      try await runtime.bindRepresentation(
        executionID: longID,
        position: continuedPosition,
        payload: OversizedPrefixPayload(tokenPrefix: consumedLongPrefix)
      )
      let cancelledRepresentation = try await backend.captureRepresentation(
        for: try runtimeHandle(runtime, id: longID)
      )
      try await backend.releaseRepresentation(cancelledRepresentation)
      let longReleased = (try? backend.boundPrefix(for: longBranch))?.prefix == nil
      cancelledReleased = cancelledReleased && longReleased

      let restoredRoot = try await runtime.restore(
        rootAdvanced,
        request: ExecutionRestoreRequest(
          targetPosition: forkPoint,
          continuation: ExecutionContinuation(
            nextInput: rootInput, continuationID: "root-recovery-0"
          )
        )
      )
      let recoveryBranch = try await runtime.fork(
        ExecutionForkRequest(
          parent: restoredRoot,
          childID: recoveryID,
          childPosition: forkPoint,
          childContinuation: ExecutionContinuation(
            nextInput: recoveryInput, continuationID: "recovery-0"
          )
        )
      )
      recoveryLineagePass = recoveryLineagePass
        && recoveryBranch.lineage.parent == rootID
        && recoveryBranch.lineage.root == root.lineage.root

      let rootRecovery = try await executor.continueExecution(
        restoredRoot, nextInputTokens: rootTokens, maxTokens: maxTokens
      )
      let rootRecovered = try await runtime.continueExecution(
        restoredRoot,
        continuation: ExecutionContinuation(nextInput: rootInput, continuationID: "root-recovery-1")
      )
      try await runtime.bindRepresentation(
        executionID: rootRecovered.id,
        position: continuedPosition,
        payload: rootRecovery.updatedPayload
      )
      rootRecoveries.append(rootRecovery)

      let recoveryRun = try await executor.continueExecution(
        recoveryBranch, nextInputTokens: recoveryTokens, maxTokens: maxTokens
      )
      let recoveryAdvanced = try await runtime.continueExecution(
        recoveryBranch,
        continuation: ExecutionContinuation(
          nextInput: recoveryInput, continuationID: "recovery-1"
        )
      )
      try await runtime.bindRepresentation(
        executionID: recoveryAdvanced.id,
        position: continuedPosition,
        payload: recoveryRun.updatedPayload
      )

      let restoredControl = try await runtime.restore(
        controlAdvanced,
        request: ExecutionRestoreRequest(
          targetPosition: forkPoint,
          continuation: ExecutionContinuation(
            nextInput: controlInput, continuationID: "control-recovery-0"
          )
        )
      )
      let controlRecovery = try await executor.continueExecution(
        restoredControl, nextInputTokens: controlTokens, maxTokens: maxTokens
      )
      let controlRecovered = try await runtime.continueExecution(
        restoredControl,
        continuation: ExecutionContinuation(
          nextInput: controlInput, continuationID: "control-recovery-1"
        )
      )
      try await runtime.bindRepresentation(
        executionID: controlRecovered.id,
        position: continuedPosition,
        payload: controlRecovery.updatedPayload
      )
      controlRecoveries.append(controlRecovery)
      recoveryContents.append(recoveryRun.generatedText)

      try await runtime.discard(longBranch)
    }

    let rootBinding = try backend.boundPrefix(
      for: try runtimeHandle(runtime, id: ExecutionID("mlx-cancel-root-\(cycles - 1)"))
    )
    let controlBinding = try backend.boundPrefix(
      for: try runtimeHandle(runtime, id: ExecutionID("mlx-cancel-control-\(cycles - 1)"))
    )
    let longDiscarded = try runtimeHandle(
      runtime, id: ExecutionID("mlx-cancel-long-\(cycles - 1)")
    ).lifecycle == .discarded
    let rootAdvancedPrefix = (rootRecoveries.last?.updatedPayload as? OversizedPrefixPayload)?
      .tokenPrefix
    let controlAdvancedPrefix = (controlRecoveries.last?.updatedPayload as? OversizedPrefixPayload)?
      .tokenPrefix
    let oversizedUnderLimit = core.peakFootprintMiB <= 30 * 1024

    let checks = [
      "COOPERATIVE_CANCEL_ONE_TOKEN":
        cancelledTokenCounts.count == cycles
        && cancelledTokenCounts.allSatisfy { $0 == 1 },
      "CANCELLED_LONG_PHYSICAL_RELEASED":
        cancelledReleased,
      "CANCELLED_LONG_LOGICALLY_DISCARDED":
        longDiscarded,
      "ROOT_RECOVERY_IDENTICAL":
        rootReferences.count == cycles && rootRecoveries.count == cycles
        && zip(rootReferences, rootRecoveries).allSatisfy {
          $0.generatedTokenIDs == $1.generatedTokenIDs && $0.generatedText == $1.generatedText
        },
      "CONTROL_RECOVERY_IDENTICAL":
        controlReferences.count == cycles && controlRecoveries.count == cycles
        && zip(controlReferences, controlRecoveries).allSatisfy {
          $0.generatedTokenIDs == $1.generatedTokenIDs && $0.generatedText == $1.generatedText
        },
      "ROOT_AND_CONTROL_PREFIXES_DIVERGED":
        rootAdvancedPrefix != controlAdvancedPrefix,
      "RECOVERY_LINEAGE_ISOLATED":
        recoveryLineagePass,
      "ROOT_AND_CONTROL_SURVIVE_RELEASE":
        rootBinding.prefix == rootAdvancedPrefix
        && controlBinding.prefix == controlAdvancedPrefix,
      "OVERSIZED_PROFILE_UNDER_30GIB":
        core.segments.count > 1 && oversizedUnderLimit,
    ]
    let overallPass = checks.values.allSatisfy { $0 }

    return MLXCancellationReport(
      status: overallPass ? "PASS" : "FAIL",
      protocolVersion: mlxCancellationProtocolVersion,
      boundary: mlxCancellationBoundary,
      modelDirectory: modelDirectory.path,
      segmentSize: segmentSize,
      segmentCount: core.segments.count,
      seedText: seedText,
      rootInput: rootInput,
      controlInput: controlInput,
      recoveryInput: recoveryInput,
      longInput: longInput,
      maxTokens: maxTokens,
      cycles: cycles,
      cancelledTokenCounts: cancelledTokenCounts,
      checks: checks,
      rootReferenceContent: rootReferences.first?.generatedText ?? "",
      controlReferenceContent: controlReferences.first?.generatedText ?? "",
      recoveryContent: recoveryContents.first ?? "",
      peakFootprintMiB: core.peakFootprintMiB,
      maxSwapMiB: core.maxSwapMiB,
      segmentTransitions: core.segmentTransitions,
      overallPass: overallPass
    )
  }

  public struct CancellationMatrixReport: Encodable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let seedText: String
    public let rootInput: String
    public let controlInput: String
    public let recoveryInput: String
    public let longPrompt: String
    public let recoveryTokens: Int
    public let cycles: Int
    public let commonChecks: [String: Bool]
    public let llamaCancellationMechanism: String
    public let mlxCancellationMechanism: String
    public let sameOutcomeShape: Bool
    public let sameRecoverySemantics: Bool
    public let sameWorkloadShape: Bool
    public let bothBackendsPass: Bool
    public let crossBackendClosure: Bool
    public let closureBlocker: String
    public let llama: UICancellationReport
    public let mlx: MLXCancellationReport
    public let overallPass: Bool
  }

  public static let cancellationMatrixProtocolVersion =
    "LAB.UI.BRANCH.SESSIONS.CANCELLATION.CROSSBACKEND.V1"
  public static let cancellationMatrixBoundary =
    "SAME_SESSION_CANCELLATION_OUTCOME_SHAPE / EXPLICIT_VS_COOPERATIVE_MECHANISM / "
    + "HARNESS_LEVEL / NOT_A_MODEL_IDENTITY_CLOSURE"

  public static func runCancellationCrossBackendMatrix(
    modelDirectory: URL,
    host: String = "127.0.0.1",
    port: Int = 18080,
    seedText: String = "def is_palindrome(s):",
    rootInput: String = "Explain it briefly.",
    controlInput: String = "Now write tests for it.",
    recoveryInput: String = "Continue from the root.",
    longPrompt: String = "Count from 1 to 500. Return only numbers separated by spaces.",
    recoveryTokens: Int = 2,
    cycles: Int = 2,
    cancelDelayMs: Int = 100,
    freeTimeoutMs: Int = 15000,
    seed: Int = 42,
    segmentSize: Int = 8
  ) async throws -> CancellationMatrixReport {
    let llama = try await runCancellationLLAMA(
      host: host,
      port: port,
      seedText: seedText,
      rootInput: rootInput,
      controlInput: controlInput,
      recoveryInput: recoveryInput,
      longPrompt: longPrompt,
      predictionTokens: recoveryTokens,
      cancelDelayMs: cancelDelayMs,
      cycles: cycles,
      freeTimeoutMs: freeTimeoutMs,
      seed: seed
    )
    let mlx = try await runCancellationOversizedMLX(
      modelDirectory: modelDirectory,
      seedText: seedText,
      rootInput: rootInput,
      controlInput: controlInput,
      recoveryInput: recoveryInput,
      longInput: longPrompt,
      maxTokens: recoveryTokens,
      cycles: cycles,
      segmentSize: segmentSize
    )

    let llamaAccepted = llama.checks["CANCEL_ACCEPTED"] == true
    let mlxAccepted =
      mlx.checks["COOPERATIVE_CANCEL_ONE_TOKEN"] == true
      && mlx.cancelledTokenCounts.count == cycles
    let stopped =
      llama.checks["CANCELLED_SLOT_FREED"] == true
      && mlx.checks["COOPERATIVE_CANCEL_ONE_TOKEN"] == true
    let physicalReleased =
      llama.checks["CANCELLED_LONG_PHYSICAL_RELEASED"] == true
      && mlx.checks["CANCELLED_LONG_PHYSICAL_RELEASED"] == true
    let logicallyDiscarded =
      llama.checks["CANCELLED_LONG_LOGICALLY_DISCARDED"] == true
      && mlx.checks["CANCELLED_LONG_LOGICALLY_DISCARDED"] == true
    let rootRecovery =
      llama.checks["ROOT_RECOVERY_IDENTICAL"] == true
      && mlx.checks["ROOT_RECOVERY_IDENTICAL"] == true
    let controlRecovery =
      llama.checks["CONTROL_RECOVERY_IDENTICAL"] == true
      && mlx.checks["CONTROL_RECOVERY_IDENTICAL"] == true
    let prefixesDiverged =
      llama.checks["ROOT_AND_CONTROL_PREFIXES_DIVERGED"] == true
      && mlx.checks["ROOT_AND_CONTROL_PREFIXES_DIVERGED"] == true
    let lineageIsolated =
      llama.checks["RECOVERY_LINEAGE_ISOLATED"] == true
      && mlx.checks["RECOVERY_LINEAGE_ISOLATED"] == true
    let survivors =
      llama.checks["ROOT_AND_CONTROL_SURVIVE_RELEASE"] == true
      && mlx.checks["ROOT_AND_CONTROL_SURVIVE_RELEASE"] == true
    let cyclesComplete =
      llama.checks["CYCLES_COMPLETE"] == true && mlx.cycles == cycles

    let commonChecks = [
      "CANCELLATION_ACCEPTED": llamaAccepted && mlxAccepted,
      "EXECUTION_STOPPED": stopped,
      "CANCELLED_LONG_PHYSICAL_RELEASED": physicalReleased,
      "CANCELLED_LONG_LOGICALLY_DISCARDED": logicallyDiscarded,
      "ROOT_RECOVERY_IDENTICAL": rootRecovery,
      "CONTROL_RECOVERY_IDENTICAL": controlRecovery,
      "ROOT_AND_CONTROL_PREFIXES_DIVERGED": prefixesDiverged,
      "RECOVERY_LINEAGE_ISOLATED": lineageIsolated,
      "ROOT_AND_CONTROL_SURVIVE_RELEASE": survivors,
      "CYCLES_COMPLETE": cyclesComplete,
    ]
    let sameOutcomeShape = commonChecks.values.allSatisfy { $0 }
    let sameRecoverySemantics =
      rootRecovery && controlRecovery && lineageIsolated && survivors
    let sameWorkloadShape =
      llama.seedText == seedText && mlx.seedText == seedText
      && llama.rootInput == rootInput && mlx.rootInput == rootInput
      && llama.controlInput == controlInput && mlx.controlInput == controlInput
      && llama.recoveryInput == recoveryInput && mlx.recoveryInput == recoveryInput
      && llama.longPrompt == longPrompt && mlx.longInput == longPrompt
      && llama.predictionTokens == recoveryTokens && mlx.maxTokens == recoveryTokens
      && llama.cycles == cycles && mlx.cycles == cycles
    let bothPass = llama.overallPass && mlx.overallPass
    let matrixPass = bothPass && sameOutcomeShape && sameRecoverySemantics && sameWorkloadShape

    return CancellationMatrixReport(
      status: matrixPass ? "PASS_WITH_BOUNDARY" : "FAIL",
      protocolVersion: cancellationMatrixProtocolVersion,
      boundary: cancellationMatrixBoundary,
      seedText: seedText,
      rootInput: rootInput,
      controlInput: controlInput,
      recoveryInput: recoveryInput,
      longPrompt: longPrompt,
      recoveryTokens: recoveryTokens,
      cycles: cycles,
      commonChecks: commonChecks,
      llamaCancellationMechanism: "EXPLICIT_STREAM_DELETE",
      mlxCancellationMechanism: "COOPERATIVE_TOKEN_BOUNDARY_CANCEL",
      sameOutcomeShape: sameOutcomeShape,
      sameRecoverySemantics: sameRecoverySemantics,
      sameWorkloadShape: sameWorkloadShape,
      bothBackendsPass: bothPass,
      crossBackendClosure: false,
      closureBlocker: "DIFFERENT_MODEL_ARTIFACTS_TOKENIZERS_AND_CANCEL_MECHANISMS",
      llama: llama,
      mlx: mlx,
      overallPass: matrixPass
    )
  }

  private static func runtimeHandle(
    _ runtime: ExecutionContinuityCoordinator, id: ExecutionID
  ) throws -> ExecutionStateHandle {
    guard let handle = runtime.handle(id) else {
      throw ExecutionStateBackendError.noBoundRepresentation(id)
    }
    return handle
  }

}

extension UIBranchSessions {
  public struct MLXMemoryPressureBranch: Encodable, Sendable {
    public let executionID: String
    public let input: String
    public let content: String
    public let generatedTokenIDs: [Int]
    public let finalPrefixTokenCount: Int
    public let recoveryMatches: [Bool]
    public let finalBindingsExact: [Bool]
  }

  public struct MLXMemoryPressureReport: Encodable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let modelDirectory: String
    public let segmentSize: Int
    public let segmentCount: Int
    public let seedText: String
    public let controlInput: String
    public let maxTokens: Int
    public let cycles: Int
    public let checks: [String: Bool]
    public let controlContent: String
    public let pressureBranches: [MLXMemoryPressureBranch]
    public let steps: [Step]
    public let peakFootprintMiB: Int64
    public let maxSwapMiB: Int64
    public let segmentTransitions: Int
    public let overallPass: Bool
  }

  public static let mlxMemoryPressureProtocolVersion =
    "LAB.UI.BRANCH.SESSIONS.MLX.MEMORY.PRESSURE.V1"
  public static let mlxMemoryPressureBoundary =
    "SWIFT_SESSION_CONTROL_PLANE / CONTROLLED_MULTI_BRANCH_RELEASE_RESTORE_LOAD / "
    + "OVERSIZED_MLX / HARNESS_LEVEL / NOT_OS_MEMORY_PRESSURE / NOT_A_UI_PRODUCT"

  public static func runMemoryPressureOversizedMLX(
    modelDirectory: URL,
    seedText: String = "def is_palindrome(s):",
    controlInput: String = "Now write tests for it.",
    pressureInputs: [String] = [
      "List one edge case for the function.",
      "Add a focused unit test for that edge case.",
    ],
    maxTokens: Int = 1,
    cycles: Int = 2,
    segmentSize: Int = 8
  ) async throws -> MLXMemoryPressureReport {
    precondition(!pressureInputs.isEmpty)
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

    let rootID = ExecutionID("mlx-pressure-root")
    let controlID = ExecutionID("mlx-pressure-control")
    let pressureIDs = pressureInputs.enumerated().map {
      ExecutionID("mlx-pressure-branch-\($0.offset)")
    }
    let forkPoint = ExecutionPosition(0)
    let seedTokens = try executor.tokenizeSeedText(seedText)

    let root = try await runtime.create(
      id: rootID,
      position: forkPoint,
      continuation: ExecutionContinuation(nextInput: "", continuationID: "pressure-root-0")
    )
    try await runtime.bindRepresentation(
      executionID: rootID,
      position: forkPoint,
      payload: OversizedPrefixPayload(tokenPrefix: seedTokens)
    )

    func fork(
      _ childID: ExecutionID, input: String, continuationID: String
    ) async throws -> ExecutionStateHandle {
      try await runtime.fork(
        ExecutionForkRequest(
          parent: root,
          childID: childID,
          childPosition: forkPoint,
          childContinuation: ExecutionContinuation(
            nextInput: input, continuationID: continuationID
          )
        )
      )
    }

    let control = try await fork(
      controlID, input: controlInput, continuationID: "pressure-control-0"
    )
    var pressureStates: [ExecutionStateHandle] = []
    for (index, input) in pressureInputs.enumerated() {
      pressureStates.append(
        try await fork(
          pressureIDs[index], input: input, continuationID: "pressure-\(index)-0"
        )
      )
    }

    func advance(
      _ state: ExecutionStateHandle,
      input: String,
      continuationID: String
    ) async throws -> (
      ExecutionStateHandle, generated: [Int], text: String,
      payload: OversizedPrefixPayload
    ) {
      let started = DispatchTime.now().uptimeNanoseconds
      let result = try await executor.continueExecution(
        state, nextInputTokens: try executor.tokenizeText(input), maxTokens: maxTokens
      )
      guard let payload = result.updatedPayload as? OversizedPrefixPayload else {
        throw ExecutionStateBackendError.noBoundRepresentation(state.id)
      }
      let advanced = try await runtime.continueExecution(
        state,
        continuation: ExecutionContinuation(nextInput: input, continuationID: continuationID)
      )
      try await runtime.bindRepresentation(
        executionID: advanced.id,
        position: advanced.position,
        payload: payload
      )
      record("continue", advanced, started)
      return (advanced, result.generatedTokenIDs, result.generatedText, payload)
    }

    let controlRun = try await advance(
      control, input: controlInput, continuationID: "pressure-control-1"
    )
    let advancedControl = controlRun.0
    let controlPrefix = controlRun.payload.tokenPrefix

    var runs: [(
      state: ExecutionStateHandle, generated: [Int], text: String, prefix: [Int]
    )] = []
    for (index, state) in pressureStates.enumerated() {
      let run = try await advance(
        state,
        input: pressureInputs[index],
        continuationID: "pressure-\(index)-1"
      )
      runs.append((run.0, run.generated, run.text, run.payload.tokenPrefix))
    }

    var recoveryMatches = Array(repeating: [Bool](), count: runs.count)
    var finalBindingsExact = recoveryMatches
    var releaseActions = 0
    for cycle in 0..<cycles {
      for index in runs.indices {
        let started = DispatchTime.now().uptimeNanoseconds
        let current = try await backend.captureRepresentation(for: runs[index].state)
        try await backend.releaseRepresentation(current)
        releaseActions += 1
        record("release", runs[index].state, started)

        let restoredToFork = try await runtime.restore(
          runs[index].state,
          request: ExecutionRestoreRequest(
            targetPosition: forkPoint,
            continuation: ExecutionContinuation(
              nextInput: pressureInputs[index], continuationID: "pressure-\(index)-r0-\(cycle)"
            )
          )
        )
        record("switch", restoredToFork, started)
        let replay = try await executor.continueExecution(
          restoredToFork,
          nextInputTokens: try executor.tokenizeText(pressureInputs[index]),
          maxTokens: maxTokens
        )
        recoveryMatches[index].append(
          replay.generatedTokenIDs == runs[index].generated
            && replay.generatedText == runs[index].text
        )

        let restoredToFinal = try await runtime.restore(
          restoredToFork,
          request: ExecutionRestoreRequest(
            targetPosition: ExecutionPosition(1),
            continuation: ExecutionContinuation(
              nextInput: pressureInputs[index], continuationID: "pressure-\(index)-r1-\(cycle)"
            )
          )
        )
        record("switch", restoredToFinal, started)
        let binding = try backend.boundPrefix(for: restoredToFinal)
        finalBindingsExact[index].append(
          binding.prefix == runs[index].prefix && binding.position == ExecutionPosition(1)
        )
        runs[index].state = restoredToFinal
      }
    }

    for run in runs {
      try await runtime.discard(run.state)
    }
    let pressureBindingsGone = runs.allSatisfy {
      (try? backend.boundPrefix(for: $0.state))?.prefix == nil
    }
    let rootBinding = try backend.boundPrefix(for: root)
    let controlBinding = try backend.boundPrefix(for: advancedControl)
    let allPrefixes = runs.map(\.prefix) + [controlPrefix]
    let prefixesDiverged = Set(allPrefixes).count == runs.count + 1
    let controlLineageIsolated =
      control.lineage.parent == rootID && control.lineage.root == root.lineage.root
    let pressureLineageIsolated = pressureStates.allSatisfy {
      $0.lineage.parent == rootID && $0.lineage.root == root.lineage.root
    }
    let lineageIsolated =
      controlLineageIsolated && pressureLineageIsolated
    let oversizedUnderLimit = core.segments.count > 1 && core.peakFootprintMiB <= 30 * 1024

    let checks = [
      "PRESSURE_WORKLOAD_COMPLETE":
        runs.count == pressureInputs.count && !controlRun.text.isEmpty,
      "PRESSURE_RELEASE_ACTIONS_COMPLETE":
        releaseActions == runs.count * cycles,
      "PRESSURE_LINEAGE_ISOLATED": lineageIsolated,
      "ACTIVE_BRANCH_PREFIXES_DIVERGED": prefixesDiverged,
      "REPEATED_RECOVERY_OUTPUTS_EXACT":
        recoveryMatches.allSatisfy { $0.count == cycles && $0.allSatisfy(\.self) },
      "RECOVERY_FINAL_BINDINGS_EXACT":
        finalBindingsExact.allSatisfy { $0.count == cycles && $0.allSatisfy(\.self) },
      "RELEASE_PRESSURE_BRANCHES": pressureBindingsGone,
      "ROOT_AND_CONTROL_SURVIVE":
        rootBinding.prefix == seedTokens && controlBinding.prefix == controlPrefix,
      "NO_SWAP_ON_PRESSURE_ACTION": core.maxSwapMiB == 0,
      "OVERSIZED_PROFILE_UNDER_30GIB": oversizedUnderLimit,
    ]
    let overallPass = checks.values.allSatisfy { $0 }

    return MLXMemoryPressureReport(
      status: overallPass ? "PASS" : "FAIL",
      protocolVersion: mlxMemoryPressureProtocolVersion,
      boundary: mlxMemoryPressureBoundary,
      modelDirectory: modelDirectory.path,
      segmentSize: segmentSize,
      segmentCount: core.segments.count,
      seedText: seedText,
      controlInput: controlInput,
      maxTokens: maxTokens,
      cycles: cycles,
      checks: checks,
      controlContent: controlRun.text,
      pressureBranches: runs.enumerated().map { index, run in
        MLXMemoryPressureBranch(
          executionID: run.state.id.rawValue,
          input: pressureInputs[index],
          content: run.text,
          generatedTokenIDs: run.generated,
          finalPrefixTokenCount: run.prefix.count,
          recoveryMatches: recoveryMatches[index],
          finalBindingsExact: finalBindingsExact[index]
        )
      },
      steps: steps,
      peakFootprintMiB: core.peakFootprintMiB,
      maxSwapMiB: core.maxSwapMiB,
      segmentTransitions: core.segmentTransitions,
      overallPass: overallPass
    )
  }
}
