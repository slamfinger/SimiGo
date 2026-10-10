import Foundation
import SimiGoRuntimeContract
import CryptoKit

public enum ProductionRuntimeInformationError: Error, Equatable, Sendable {
  case bridgeFailed(command: String, exitCode: Int32, message: String)
  case invalidBridgeResponse(command: String)
  case launchConfigurationInvalid(path: String, message: String)
  case blockedInformationDemand(
    command: String,
    state: String,
    validityFailureItemIDs: [String]
  )
  case invalidPersistedExecutionState(lifecycle: String)
  case modelExecutorUnavailable
  case modelExecutionFailed(reason: String)
}

public protocol ProductionRuntimeModelContinuationExecutor: Sendable {
  func tokenizeText(_ text: String) async throws -> [Int]
  func tokenizeSeedText(_ text: String) async throws -> [Int]
  func continueExecution(
    _ state: ExecutionStateHandle,
    nextInputTokens: [Int],
    maxTokens: Int
  ) async throws -> ExecutionContinuationResult
}

extension MLXPrefixRecomputeExecutor: ProductionRuntimeModelContinuationExecutor {}


public struct ProductionRuntimeBridgeReport: Equatable, Sendable {
  public let command: String
  public let advanced: Bool
  public let state: String
  public let computedItemIDs: [String]
  public let reusedItemIDs: [String]
  public let resultDigest: String
}

public struct SerializedProductionExecutionState: Codable, Equatable, Sendable {
  public let id: String
  public let lineageRoot: String
  public let lineageParent: String?
  public let position: Int64
  public let nextInput: String
  public let continuationID: String
  public let lifecycle: String

  public init(handle: ExecutionStateHandle) {
    id = handle.id.rawValue
    lineageRoot = handle.lineage.root.rawValue
    lineageParent = handle.lineage.parent?.rawValue
    position = handle.position.value
    nextInput = handle.continuation.nextInput
    continuationID = handle.continuation.continuationID
    lifecycle = handle.lifecycle.rawValue
  }

  public init(
    id: String,
    lineageRoot: String,
    lineageParent: String?,
    position: Int64,
    nextInput: String,
    continuationID: String,
    lifecycle: String
  ) {
    self.id = id
    self.lineageRoot = lineageRoot
    self.lineageParent = lineageParent
    self.position = position
    self.nextInput = nextInput
    self.continuationID = continuationID
    self.lifecycle = lifecycle
  }

  public func validatedHandle() throws -> ExecutionStateHandle {
    // A persisted production handle may only resume from a live lifecycle.
    // `discarded` is intentionally rejected here: it is a valid lifecycle
    // value, but not a valid recovery source.
    guard
      let lifecycle = ExecutionBranchLifecycle(rawValue: lifecycle),
      lifecycle != .discarded
    else {
      throw ProductionRuntimeInformationError.invalidPersistedExecutionState(
        lifecycle: lifecycle
      )
    }
    return ExecutionStateHandle(
      id: ExecutionID(id),
      lineage: ExecutionLineage(
        root: ExecutionID(lineageRoot),
        parent: lineageParent.map(ExecutionID.init)
      ),
      position: ExecutionPosition(position),
      continuation: ExecutionContinuation(
        nextInput: nextInput,
        continuationID: continuationID
      ),
      lifecycle: lifecycle
    )
  }
}

public struct ProductionRuntimeLaunchConfiguration: Equatable, Sendable {
  public let runtimeRoot: URL
  public let pythonExecutable: URL
  public let snapshotPath: URL
  public let validityPolicyPath: URL

  public init(
    runtimeRoot: URL,
    pythonExecutable: URL,
    snapshotPath: URL,
    validityPolicyPath: URL
  ) {
    self.runtimeRoot = runtimeRoot.standardizedFileURL
    self.pythonExecutable = pythonExecutable.standardizedFileURL
    self.snapshotPath = snapshotPath.standardizedFileURL
    self.validityPolicyPath = validityPolicyPath.standardizedFileURL
  }

  public var environment: [String: String] {
    [
      "SIMIGO_RUNTIME_ROOT": runtimeRoot.path,
      "SIMIGO_INFO_SNAPSHOT_PATH": snapshotPath.path,
      "SIMIGO_INFO_VALIDITY_POLICY_PATH": validityPolicyPath.path,
    ]
  }
}

public final class ProductionRuntimeInformationIntegration: @unchecked Sendable {
  public static let continuationPoint = "bounded-production-runtime-integration"
  public static let executionID = ExecutionID("PRODUCTION-REAL-PALACE")

  private let labRoot: URL
  private let launchConfiguration: ProductionRuntimeLaunchConfiguration?
  private let backend = MLXExecutionStateBackend()
  private var modelExecutor: (any ProductionRuntimeModelContinuationExecutor)?
  private lazy var runtime = ExecutionContinuityCoordinator(backend: backend)

  public convenience init(labRoot: URL? = nil) {
    self.init(labRoot: labRoot, modelExecutor: nil)
  }

  public init(labRoot: URL?, modelExecutor: (any ProductionRuntimeModelContinuationExecutor)?) {
    if let labRoot {
      self.labRoot = labRoot.standardizedFileURL
    } else {
      // Sources/SimiGo2Experimental/File.swift -> Lab root.
      self.labRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    }
    launchConfiguration = nil
    self.modelExecutor = modelExecutor
  }

  public init(
    configuration: ProductionRuntimeLaunchConfiguration,
    modelExecutor: (any ProductionRuntimeModelContinuationExecutor)? = nil,
  ) {
    launchConfiguration = configuration
    self.modelExecutor = modelExecutor
    labRoot = configuration.runtimeRoot
  }

  public func attachModelExecutor(
    _ executor: any ProductionRuntimeModelContinuationExecutor
  ) {
    modelExecutor = executor
  }

  private var bridgeURL: URL {
    if let launchConfiguration {
      return launchConfiguration.runtimeRoot.appendingPathComponent("production_runtime_bridge.py")
    }
    return labRoot.appendingPathComponent("execution-information-loop/production_runtime_bridge.py")
  }
  private var pythonURL: URL {
    if let launchConfiguration {
      return launchConfiguration.pythonExecutable
    }
    return URL(fileURLWithPath: "/usr/bin/python3")
  }

  private func runBridge(_ command: String, arguments: [String]) throws -> [String: Any] {
    if let launchConfiguration {
      let required = [
        launchConfiguration.pythonExecutable,
        launchConfiguration.runtimeRoot.appendingPathComponent("production_runtime_bridge.py"),
        launchConfiguration.snapshotPath,
        launchConfiguration.validityPolicyPath,
      ]
      for path in required where !FileManager.default.fileExists(atPath: path.path) {
        throw ProductionRuntimeInformationError.launchConfigurationInvalid(
          path: path.path,
          message: "required production runtime file is missing"
        )
      }
    }
    guard FileManager.default.fileExists(atPath: pythonURL.path) else {
      throw ProductionRuntimeInformationError.launchConfigurationInvalid(
        path: pythonURL.path,
        message: "Python executable is missing"
      )
    }
    let processArguments = [bridgeURL.path, command] + arguments

    let process = Process()
    process.executableURL = pythonURL
    process.arguments = processArguments
    if let launchConfiguration {
      var environment = process.environment ?? ProcessInfo.processInfo.environment
      environment = environment.merging(
        launchConfiguration.environment
      ) { _, deployed in deployed }
      process.environment = environment
    }
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard let decoded = try JSONSerialization.jsonObject(with: outputData) as? [String: Any] else {
      throw ProductionRuntimeInformationError.invalidBridgeResponse(command: command)
    }
    guard process.terminationStatus == 0, decoded["ok"] as? Bool == true else {
      let message = decoded["error"] as? String ?? String(decoding: error.fileHandleForReading.availableData, as: UTF8.self)
      throw ProductionRuntimeInformationError.bridgeFailed(
        command: command,
        exitCode: process.terminationStatus,
        message: message
      )
    }
    return decoded
  }

  public func initialize(
    database: URL,
    validUntil: String?
  ) throws {
    try FileManager.default.createDirectory(
      at: database.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    var arguments = ["--database", database.path]
    if let validUntil {
      arguments += ["--valid-until", validUntil]
    }
    _ = try runBridge("initialize", arguments: arguments)
  }

  public func status(database: URL) throws -> [String: Any] {
    try runBridge("status", arguments: ["--database", database.path])
  }

  public func audit(database: URL) throws -> [String: Any] {
    try runBridge("audit", arguments: ["--database", database.path])
  }

  public func diagnostics(
    database: URL,
    evaluatedAtUTC: String
  ) throws -> [String: Any] {
    try runBridge("diagnostics", arguments: [
      "--database", database.path,
      "--evaluated-at", evaluatedAtUTC,
    ])
  }

  @discardableResult
  public func recordBlockedExecutionState(
    database: URL,
    stateID: String,
    priorStateID: String?,
    reason: String
  ) throws -> [String: Any] {
    var arguments = [
      "--database", database.path,
      "--state-id", stateID,
      "--reason", reason,
    ]
    if let priorStateID {
      arguments += ["--prior-state-id", priorStateID]
    }
    return try runBridge("record-blocked", arguments: arguments)
  }

  @discardableResult
  public func rollbackToExecutionState(
    database: URL,
    targetStateID: String,
    newStateID: String
  ) throws -> [String: Any] {
    try runBridge("rollback-to-state", arguments: [
      "--database", database.path,
      "--target-state-id", targetStateID,
      "--new-state-id", newStateID,
    ])
  }

  public func invalidate(
    database: URL,
    itemID: String,
    reason: String
  ) throws {
    _ = try runBridge("invalidate", arguments: [
      "--database", database.path,
      "--item-id", itemID,
      "--reason", reason,
    ])
  }

  public func applyIsolatedSourceRevision(
    database: URL,
    itemID: String,
    version: String,
    validUntil: String = "2030-12-31T23:59:59Z"
  ) throws {
    _ = try runBridge("source-change", arguments: [
      "--database", database.path,
      "--item-id", itemID,
      "--version", version,
      "--valid-until", validUntil,
    ])
  }

  public func probeMissingInformation(
    database: URL,
    evaluatedAtUTC: String
  ) throws -> [String: Any] {
    try runBridge("probe-missing", arguments: [
      "--database", database.path,
      "--evaluated-at", evaluatedAtUTC,
    ])
  }

  @discardableResult
  public func continueWithRealInformation(
    database: URL,
    handle: ExecutionStateHandle?,
    advancementID: String,
    evaluatedAtUTC: String
  ) async throws -> (handle: ExecutionStateHandle, report: ProductionRuntimeBridgeReport) {
    let current: ExecutionStateHandle
    if let handle {
      if runtime.handle(handle.id) != nil {
        current = try await runtime.reattach(handle)
      } else {
        current = try await runtime.attach(handle)
      }
    } else {
      current = try await runtime.create(
        id: Self.executionID,
        position: ExecutionPosition(0),
        continuation: ExecutionContinuation(
          nextInput: "\(Self.continuationPoint)-initial",
          continuationID: "\(Self.continuationPoint)-initial-cont"
        )
      )
    }

    let response = try runBridge("execute", arguments: [
      "--database", database.path,
      "--advancement", advancementID,
      "--evaluated-at", evaluatedAtUTC,
    ])
    guard let result = response["result"] as? [String: Any] else {
      throw ProductionRuntimeInformationError.invalidBridgeResponse(command: "execute")
    }
    let state = result["state"] as? String ?? "UNKNOWN"
    guard result["advanced"] as? Bool == true, state == "ADVANCED" else {
      throw ProductionRuntimeInformationError.blockedInformationDemand(
        command: advancementID,
        state: state,
        validityFailureItemIDs: result["validity_failure_item_ids"] as? [String] ?? []
      )
    }
    guard let executionState = result["execution_state"] as? [String: Any],
          let pendingStateID = executionState["state_id"] as? String else {
      throw ProductionRuntimeInformationError.invalidBridgeResponse(command: "execute")
    }

    let computed = result["computed_item_ids"] as? [String] ?? []
    let reused = result["reused_item_ids"] as? [String] ?? []
    let resultPayload = result["result"] as? [String: Any] ?? [:]
    let resultData = try JSONSerialization.data(
      withJSONObject: resultPayload,
      options: [.sortedKeys]
    )
    let digest = SHA256.hash(data: resultData).map { String(format: "%02x", $0) }.joined()
    guard let modelExecutor else {
      throw ProductionRuntimeInformationError.modelExecutorUnavailable
    }

    // The real continuation prompt is derived from the Information Space
    // result returned by the isolated carrier, not from a fixture digest.
    let informationContext = String(decoding: resultData, as: UTF8.self)
    let continuationText = "\(Self.continuationPoint):\(advancementID)\n\(informationContext)"

    func failPending(_ reason: String) throws {
      _ = try runBridge("record-blocked", arguments: [
        "--database", database.path,
        "--state-id", "\(pendingStateID):model-failed",
        "--prior-state-id", pendingStateID,
        "--reason", reason,
      ])
    }

    func restorePreModelState() async {
      if let priorRepresentation {
        try? await backend.restoreRepresentation(priorRepresentation)
      }
      _ = try? await runtime.restore(
        current,
        request: ExecutionRestoreRequest(
          targetPosition: current.position,
          continuation: current.continuation
        )
      )
    }

    // If the runtime has no physical prefix yet, seed it from the actual
    // recovered Information Space payload. Existing bound prefixes continue
    // to be consumed unchanged.
    if (try? backend.boundPrefix(for: current)) == nil {
      let seedTokens = try await modelExecutor.tokenizeSeedText(informationContext)
      try await runtime.bindRepresentation(
        executionID: current.id,
        position: current.position,
        payload: MLXPrefixPayload(tokenPrefix: seedTokens)
      )
    }
    let priorRepresentation = try? await backend.captureRepresentation(for: current)
    let nextInputTokens = try await modelExecutor.tokenizeText(continuationText)

    let advanced: ExecutionStateHandle
    let modelResult: ExecutionContinuationResult
    do {
      modelResult = try await modelExecutor.continueExecution(
        current,
        nextInputTokens: nextInputTokens,
        maxTokens: 32
      )
      advanced = try await runtime.continueExecution(
        current,
        continuation: ExecutionContinuation(
          nextInput: "\(Self.continuationPoint):\(advancementID)",
          continuationID: "\(Self.continuationPoint):\(advancementID):cont"
        )
      )
      try await runtime.bindRepresentation(
        executionID: advanced.id,
        position: advanced.position,
        payload: modelResult.updatedPayload
      )
    } catch {
      try? await restorePreModelState()
      try? failPending("MLX continuation or representation binding failed: \(error)")
      throw ProductionRuntimeInformationError.modelExecutionFailed(reason: String(describing: error))
    }

    do {
      _ = try runBridge(
        "confirm-runtime-application",
        arguments: ["--database", database.path, "--state-id", pendingStateID]
      )
    } catch {
      try? await restorePreModelState()
      try? failPending("runtime application confirmation failed: \(error)")
      throw ProductionRuntimeInformationError.modelExecutionFailed(reason: String(describing: error))
    }

    return (
      advanced,
      ProductionRuntimeBridgeReport(
        command: advancementID,
        advanced: true,
        state: state,
        computedItemIDs: computed,
        reusedItemIDs: reused,
        resultDigest: digest
      )
    )
  }
}
