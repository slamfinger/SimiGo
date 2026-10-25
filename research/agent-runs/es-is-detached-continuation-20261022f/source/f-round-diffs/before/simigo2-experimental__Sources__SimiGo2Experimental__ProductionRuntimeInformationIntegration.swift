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
  /// Recovery requires the production runtime to be wired to a durable
  /// execution-state store; a stateless integration cannot recover an ES.
  case durableRecoveryNotConfigured
  /// The Information Space holds no settled (ADVANCED) execution state, so it
  /// cannot authorize recovering an ES. IS is the recovery authority: without a
  /// settled result there is nothing legitimate to resume.
  case informationSpaceHasNoSettledExecution(state: String)
  /// IS authorizes recovery but the durable execution-state store has no handle
  /// for the production execution: the ES cannot be reconstructed.
  case durableExecutionStateMissing(executionID: String)
  /// The durable handle was recovered but no persisted representation exists at
  /// its position, so the physical prefix cannot be rebound from settled state.
  case persistedRepresentationUnavailable(executionID: String, position: Int64)
  /// IS authorizes recovery and a durable ES handle exists, but the ES carries no
  /// settlement checkpoint, so it cannot be proven to correspond to IS's latest
  /// settled execution. Recovery fails closed rather than resume an ES whose IS
  /// settlement link was never recorded.
  case settlementCheckpointMissing(executionID: String)
  /// The ES settlement checkpoint no longer matches the Information Space's
  /// current settled state (`field` names the first divergent anchor: the
  /// confirmation record id, its prior/original advancement id, the result
  /// digest, the validity basis, or the ES identity/position). The ES is either
  /// stale (IS advanced past it) or was tampered with, so continuing/recovering
  /// it would resume work inconsistent with IS — rejected before any new side
  /// effect.
  case settlementCheckpointMismatch(executionID: String, field: String)
  /// The bridge refused a request with a structured admission verdict (stage,
  /// reason, optional item id) instead of an opaque failure message.
  case bridgeRefused(command: String, stage: String, reason: String, itemID: String?)
  /// IS holds no admissible settlement for one of the task item's declared
  /// input dependencies (missing, invalid, expired, byte-tampered, or no longer
  /// matching the item's version/dependency set). Refused BEFORE tokenization
  /// and model generation, so an unadmitted input never pays a generation cost.
  case informationSpaceInputAdmissionRefused(itemID: String, stage: String, reason: String)
  /// The admitted input could not be reproduced from the returned bindings:
  /// input digest, byte range, value digest, or object identity disagreed.
  case informationSpaceInputBindingMismatch(field: String)
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

/// One settlement action the Information Space actually took while resolving a
/// task demand. `settlementObjectID` identifies the physical settlement record
/// the value came from, so a later stage can prove it reused the SAME settled
/// object instead of merely reaching an equal answer.
public struct ProductionTaskSettlementAction: Equatable, Sendable {
  public let itemID: String
  public let action: String
  public let settlementObjectID: String
  public let resultDigest: String
  /// Detached signature object that covers this settlement, when the action
  /// produced one in this call (a REUSE was verified, not re-signed).
  public let settlementSignatureObjectID: String?

  public init(
    itemID: String,
    action: String,
    settlementObjectID: String,
    resultDigest: String,
    settlementSignatureObjectID: String? = nil
  ) {
    self.itemID = itemID
    self.action = action
    self.settlementObjectID = settlementObjectID
    self.resultDigest = resultDigest
    self.settlementSignatureObjectID = settlementSignatureObjectID
  }
}

/// Evidence for one real-model task advancement: what the model consumed, what
/// it produced, which items the Information Space reused vs recomputed, and the
/// IS runtime-application confirmation the ES checkpoint is bound to.
public struct ProductionTaskContinuationReport: Equatable, Sendable {
  public let demandID: String
  public let taskItemID: String
  public let created: Bool
  public let computedItemIDs: [String]
  public let reusedItemIDs: [String]
  public let settlementActions: [ProductionTaskSettlementAction]
  public let resultDigest: String
  public let isPendingStateID: String
  public let isConfirmationStateID: String
  public let advancedPosition: Int64
  public let advancedLifecycle: String
  public let consumedPrefixLength: Int
  public let nextInputTokenCount: Int
  public let nextInputTokenIDs: [Int]
  public let generatedTokenIDs: [Int]
  public let generatedText: String
  public let updatedPrefixTokenCount: Int
  public let tokenizeSeedCallCount: Int
  public let tokenizeNextInputCallCount: Int
  public let modelContinuationCallCount: Int
  /// Identity of the detached signature object that this call produced. The
  /// model result is only reported as settled when the producer signature
  /// exists.
  public let settlementSignatureObjectID: String
  /// Identity of the settlement object the signature covers. It is kept
  /// separate from `settlementSignatureObjectID` so evidence never mistakes
  /// the signature for the settlement it authenticates.
  public let signedSettlementObjectID: String
  public let settlementSignatureKeyID: String
}

/// One admitted substitution in the model input. `byteOffset`/`byteLength`
/// address the value inside the UTF-8 input bytes, so the executor can prove
/// that the identity it admitted is exactly the bytes the model receives.
public struct ProductionTaskInputBinding: Equatable, Sendable {
  public let placeholder: String
  public let itemID: String
  public let resultField: String
  public let value: String
  public let valueSHA256: String
  public let settlementObjectID: String
  public let settlementObjectSHA256: String
  public let resultValueSHA256: String
  public let byteOffset: Int
  public let byteLength: Int
}

/// The production input admission for one task item: which settled objects were
/// admitted, what the executor verified, and the exact input materialized from
/// the item's own template.
public struct ProductionTaskInputAdmission: Equatable, Sendable {
  public let taskItemID: String
  public let declaredDependencies: [String]
  public let templateSHA256: String
  public let inputText: String
  public let inputSHA256: String
  public let inputByteLength: Int
  public let bindings: [ProductionTaskInputBinding]
  public let dependencySettlementObjectIDs: [String: String]
  /// Every admitted settlement's verified signature identity. The consumer
  /// checks these itself; the producer's signature is never taken on trust.
  public let settlementSignatures: [ProductionTaskSettlementSignature]
  public let checks: [String: Bool]

  public func value(forPlaceholder placeholder: String) -> String? {
    bindings.first { $0.placeholder == placeholder }?.value
  }

  /// Machine-readable evidence: identities and digests only, never the raw
  /// admitted values (they are already carried by the input the model saw).
  public func evidenceDictionary() -> [String: Any] {
    [
      "task_item_id": taskItemID,
      "declared_dependencies": declaredDependencies,
      "template_sha256": templateSHA256,
      "input_sha256": inputSHA256,
      "input_byte_length": inputByteLength,
      "dependency_settlement_object_ids": dependencySettlementObjectIDs,
      "settlement_signatures": settlementSignatures.map { $0.evidenceDictionary() },
      "checks": checks,
      "bindings": bindings.map { binding in
        [
          "placeholder": binding.placeholder,
          "item_id": binding.itemID,
          "result_field": binding.resultField,
          "value_sha256": binding.valueSHA256,
          "settlement_object_id": binding.settlementObjectID,
          "result_value_sha256": binding.resultValueSHA256,
          "byte_offset": binding.byteOffset,
          "byte_length": binding.byteLength,
        ]
      },
    ]
  }
}

/// The result of one production continuation whose input was resolved and
/// admitted from the Information Space: the ES handle, the settlement report,
/// and the exact admission identity the model consumed.
public struct ProductionTaskInformationContinuation: Equatable, Sendable {
  public let handle: ExecutionStateHandle
  public let report: ProductionTaskContinuationReport
  public let admission: ProductionTaskInputAdmission

  public init(
    handle: ExecutionStateHandle,
    report: ProductionTaskContinuationReport,
    admission: ProductionTaskInputAdmission
  ) {
    self.handle = handle
    self.report = report
    self.admission = admission
  }
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
  /// Deployment file holding the settlement-signature public key. It lives
  /// outside the Information Space database on purpose: a process that can
  /// rewrite the database must not be able to install its own anchor.
  public let settlementTrustAnchorPath: URL?

  public init(
    runtimeRoot: URL,
    pythonExecutable: URL,
    snapshotPath: URL,
    validityPolicyPath: URL,
    settlementTrustAnchorPath: URL? = nil
  ) {
    self.runtimeRoot = runtimeRoot.standardizedFileURL
    self.pythonExecutable = pythonExecutable.standardizedFileURL
    self.snapshotPath = snapshotPath.standardizedFileURL
    self.validityPolicyPath = validityPolicyPath.standardizedFileURL
    self.settlementTrustAnchorPath = settlementTrustAnchorPath?.standardizedFileURL
  }

  public var environment: [String: String] {
    var value = [
      "SIMIGO_RUNTIME_ROOT": runtimeRoot.path,
      "SIMIGO_INFO_SNAPSHOT_PATH": snapshotPath.path,
      "SIMIGO_INFO_VALIDITY_POLICY_PATH": validityPolicyPath.path,
    ]
    if let settlementTrustAnchorPath {
      value["SIMIGO_SETTLEMENT_TRUST_ANCHOR"] = settlementTrustAnchorPath.path
    }
    return value
  }
}

public final class ProductionRuntimeInformationIntegration: @unchecked Sendable {
  public static let continuationPoint = "bounded-production-runtime-integration"
  public static let executionID = ExecutionID("PRODUCTION-REAL-PALACE")
  /// Stable identity the durable codec stamps on persisted prefix payloads, so a
  /// recovered store is readable only by the matching production backend.
  public static let prefixBackendIdentity = "mlx-production-prefix-v1"

  private let labRoot: URL
  private let launchConfiguration: ProductionRuntimeLaunchConfiguration?
  private let backend: MLXExecutionStateBackend
  private let stateStore: DurableExecutionStateStore?
  var representationBindingFault: Error?
  var carrierConfirmationFault: Error?
  var logicalAdvanceFault: Error?
  private var modelExecutor: (any ProductionRuntimeModelContinuationExecutor)?
  private let runtime: ExecutionContinuityCoordinator

  public convenience init(labRoot: URL? = nil) {
    self.init(labRoot: labRoot, modelExecutor: nil)
  }

  public init(
    labRoot: URL?,
    modelExecutor: (any ProductionRuntimeModelContinuationExecutor)?,
    backend: MLXExecutionStateBackend = MLXExecutionStateBackend()
  ) {
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
    self.backend = backend
    self.modelExecutor = modelExecutor
    stateStore = nil
    runtime = ExecutionContinuityCoordinator(backend: backend)
  }

  public init(
    configuration: ProductionRuntimeLaunchConfiguration,
    modelExecutor: (any ProductionRuntimeModelContinuationExecutor)? = nil,
    backend: MLXExecutionStateBackend = MLXExecutionStateBackend()
  ) {
    launchConfiguration = configuration
    self.backend = backend
    self.modelExecutor = modelExecutor
    labRoot = configuration.runtimeRoot
    stateStore = nil
    runtime = ExecutionContinuityCoordinator(backend: backend)
  }

  /// Production recovery authority. Wires the runtime coordinator to a durable
  /// execution-state store rooted at `semanticStateDirectory`: handles, lifecycle
  /// records and physical representations persist there, so a NEW integration
  /// backed by a FRESH `MLXExecutionStateBackend` pointed at the same directory
  /// can recover the ES from durable state plus the Information Space, with no
  /// side-channel handle file. `resetToFreshBaseline` archives any prior store so
  /// a stale ES can never leak into a new session (DCC-1 fresh baseline).
  public init(
    configuration: ProductionRuntimeLaunchConfiguration,
    modelExecutor: (any ProductionRuntimeModelContinuationExecutor)? = nil,
    backend: MLXExecutionStateBackend = MLXExecutionStateBackend(),
    semanticStateDirectory: URL,
    resetToFreshBaseline: Bool = false
  ) throws {
    launchConfiguration = configuration
    self.backend = backend
    self.modelExecutor = modelExecutor
    labRoot = configuration.runtimeRoot
    let store = DurableExecutionStateStore(
      directory: semanticStateDirectory.standardizedFileURL,
      payloadCodec: MLXPrefixPayloadPersistence(backendIdentity: Self.prefixBackendIdentity))
    if resetToFreshBaseline {
      try store.prepareForFreshBaseline()
    }
    stateStore = store
    runtime = try ExecutionContinuityCoordinator(
      backend: backend, identityAllocator: nil, stateStore: store)
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
      if let refusal = decoded["refusal"] as? [String: Any],
         let stage = refusal["stage"] as? String,
         let reason = refusal["reason"] as? String {
        let detail = refusal["detail"] as? [String: Any]
        throw ProductionRuntimeInformationError.bridgeRefused(
          command: command,
          stage: stage,
          reason: reason,
          itemID: detail?["item_id"] as? String
        )
      }
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

  func runtimeLifecycleRecords(executionID: ExecutionID) -> [ExecutionContinuityCoordinator.LifecycleRecord] {
    runtime.recordsSnapshot.filter { $0.executionID == executionID }
  }

  /// Serialized lifecycle transitions for experiment evidence. This is a
  /// read-only projection of the coordinator's authoritative records; it does
  /// not add, alter, or replay a transition.
  public func lifecycleRecordSummary() -> [[String: Any]] {
    runtime.recordsSnapshot.map { record in
      [
        "sequence": record.sequence,
        "operation": record.operation.rawValue,
        "execution_id": record.executionID.rawValue,
        "related_id": record.relatedID?.rawValue ?? NSNull(),
        "result_lifecycle": record.resultLifecycle.rawValue,
        "result_position": Int(record.resultPosition.value),
      ]
    }
  }

  func runtimeHandle(executionID: ExecutionID) -> ExecutionStateHandle? {
    runtime.handle(executionID)
  }

  /// Reads the Information Space's LATEST execution state (the authoritative
  /// settlement record IS itself holds). After a confirmed runtime application
  /// this is the `<advancement>:runtime-applied` CONFIRMATION record whose
  /// `prior_state_id` links back to the original advancement — never the raw
  /// advancement id alone.
  private func informationSpaceLatestExecutionState(database: URL) throws -> [String: Any]? {
    let statusResponse = try status(database: database)
    return statusResponse["execution_state"] as? [String: Any]
  }

  /// Whether IS's latest execution state is a settled, runtime-CONFIRMED record
  /// (ADVANCED + APPLIED_SWIFT). A pending (PENDING_SWIFT) or blocked/unrecorded
  /// state does not authorize resuming an ES.
  private func informationSpaceStateIsSettled(_ isState: [String: Any]?) -> Bool {
    guard let isState else { return false }
    return (isState["status"] as? String) == "ADVANCED"
        && (isState["runtime_application_status"] as? String) == "APPLIED_SWIFT"
  }

  /// Cross-layer fail-closed check: the persisted ES settlement checkpoint must
  /// correspond to IS's CURRENT settled execution state. The comparison is
  /// confirmation-aware — IS's latest record is the `:runtime-applied`
  /// confirmation, whose `prior_state_id` is the original advancement — so we
  /// match the checkpoint's separate original/confirmation ids against it rather
  /// than demanding the ES's last advancement equal the latest state id (which
  /// would wrongly reject a normally completed recovery). Any divergence in the
  /// settlement identity chain, result digest, validity basis, or ES
  /// identity/position throws before the caller performs a new side effect.
  private func validateSettlementAgainstInformationSpace(
    checkpoint: ExecutionContinuityCoordinator.SettlementCheckpoint,
    isState: [String: Any]?,
    handle: ExecutionStateHandle?
  ) throws {
    let executionID = checkpoint.executionID.rawValue
    guard informationSpaceStateIsSettled(isState), let isState else {
      throw ProductionRuntimeInformationError.informationSpaceHasNoSettledExecution(
        state: isState?["status"] as? String ?? "MISSING"
      )
    }
    // The latest record is the completion confirmation; its prior links to the
    // original advancement that produced the settled result.
    guard let latestStateID = isState["state_id"] as? String,
          let priorStateID = isState["prior_state_id"] as? String else {
      throw ProductionRuntimeInformationError.settlementCheckpointMismatch(
        executionID: executionID, field: "confirmation_record_shape"
      )
    }
    guard checkpoint.isConfirmationStateID == latestStateID else {
      throw ProductionRuntimeInformationError.settlementCheckpointMismatch(
        executionID: executionID, field: "confirmation_state_id"
      )
    }
    guard checkpoint.isOriginalStateID == priorStateID else {
      throw ProductionRuntimeInformationError.settlementCheckpointMismatch(
        executionID: executionID, field: "original_advancement_state_id"
      )
    }
    guard let isResultDigest = isState["result_digest"] as? String,
          checkpoint.resultDigest == isResultDigest else {
      throw ProductionRuntimeInformationError.settlementCheckpointMismatch(
        executionID: executionID, field: "result_digest"
      )
    }
    guard let isValidityBasis = isState["demand_digest"] as? String,
          checkpoint.validityBasis == isValidityBasis else {
      throw ProductionRuntimeInformationError.settlementCheckpointMismatch(
        executionID: executionID, field: "validity_basis"
      )
    }
    // ES identity/position the checkpoint was written for must still hold.
    if let handle, handle.id != checkpoint.executionID || handle.position != checkpoint.position {
      throw ProductionRuntimeInformationError.settlementCheckpointMismatch(
        executionID: executionID, field: "es_identity_position"
      )
    }
  }

  /// Native lifecycle step between "the old ES settled and its checkpoint is
  /// persisted" and "a fresh ES resumes the settled representation": explicitly
  /// release and retire THIS instance's execution carrier for a settled handle and
  /// VERIFY it is genuinely unusable, so a following recovery cannot quietly reuse
  /// the old MLX objects. Returns the retired carrier's confirmed mutable-storage
  /// ids so the recovery can prove the fresh carrier is disjoint from them.
  /// Fail-closed: an executor with no explicit release path, or a carrier that
  /// verifies still-usable, throws — the caller MUST NOT advance the Information
  /// Space on top of an unproven handoff.
  @discardableResult
  public func releaseExecutionCarrier(
    for handle: ExecutionStateHandle
  ) throws -> Set<String> {
    guard let carrier = modelExecutor as? any ExecutionCarrierReleasing else {
      throw CarrierLifecycleError.carrierReleaseUnsupported
    }
    try carrier.releaseExecutionCarrier(for: handle)
    try carrier.verifyCarrierUnusable(for: handle)
    return carrier.retiredCarrierStorageIDs(for: handle)
  }

  /// The ES identity (lineage/position/continuation) is sourced from the
  /// durable execution-state store — never a side-channel handle file — while
  /// the Information Space is the AUTHORITY that authorizes recovery: with no
  /// settled execution state recorded in IS, there is nothing legitimate to
  /// resume and recovery fails closed. On success the settled physical prefix
  /// is rebound from durable state into this instance's (fresh) backend, so the
  /// returned handle can continue WITHOUT re-tokenizing or falling back to the
  /// previous session's in-memory state.
  public func recoverExecutionState(
    database: URL,
    carrierIsolationAgainst retiredStorageIDs: Set<String>? = nil
  ) async throws -> ExecutionStateHandle {
    guard stateStore != nil else {
      throw ProductionRuntimeInformationError.durableRecoveryNotConfigured
    }
    // IS is the recovery authority: refuse to resume an ES it has not settled
    // AND runtime-confirmed. A pending (unconfirmed) state is not settled.
    let isState = try informationSpaceLatestExecutionState(database: database)
    guard informationSpaceStateIsSettled(isState) else {
      throw ProductionRuntimeInformationError.informationSpaceHasNoSettledExecution(
        state: isState?["status"] as? String ?? "MISSING"
      )
    }
    // The ES to recover comes from durable state, not a caller-supplied handle.
    guard let recovered = runtime.handle(Self.executionID) else {
      throw ProductionRuntimeInformationError.durableExecutionStateMissing(
        executionID: Self.executionID.rawValue
      )
    }
    // Cross-layer checkpoint: prove the persisted ES corresponds to IS's current
    // settled state BEFORE rebinding or returning a resumable handle. A missing
    // checkpoint means the ES never recorded its IS settlement link.
    guard let checkpoint = runtime.settlementCheckpoint(for: Self.executionID) else {
      throw ProductionRuntimeInformationError.settlementCheckpointMissing(
        executionID: Self.executionID.rawValue
      )
    }
    try validateSettlementAgainstInformationSpace(
      checkpoint: checkpoint,
      isState: isState,
      handle: recovered
    )
    // Re-establish the settled physical binding from persisted representations.
    if (try? backend.boundPrefix(for: recovered)) == nil {
      let rebound = try await runtime.restorePersistedBinding(
        executionID: recovered.id,
        position: recovered.position
      )
      guard rebound else {
        throw ProductionRuntimeInformationError.persistedRepresentationUnavailable(
          executionID: recovered.id.rawValue,
          position: recovered.position.value
        )
      }
    }
    // Handoff isolation (native carrier lifecycle): when the caller supplies a
    // retired carrier's confirmed mutable-storage ids, prove the freshly adopted
    // carrier is disjoint from them BEFORE returning a resumable handle. A shared
    // or unobservable alias is refused fail-closed — it means the old physical
    // state was never truly released, so resuming would reuse aliased memory. An
    // empty/nil retired set (recompute / no-KV carrier) has nothing to alias, so
    // it passes honestly rather than claiming verified isolation over unseen
    // buffers.
    if let retiredStorageIDs, !retiredStorageIDs.isEmpty {
      guard let carrier = modelExecutor as? any ExecutionCarrierReleasing else {
        throw CarrierLifecycleError.carrierReleaseUnsupported
      }
      try carrier.verifyAdoptedCarrierIsolated(
        from: retiredStorageIDs, for: recovered)
    }
    return recovered
  }

  @discardableResult
  public func continueWithRealInformation(
    database: URL,
    handle: ExecutionStateHandle?,
    advancementID: String,
    evaluatedAtUTC: String
  ) async throws -> (handle: ExecutionStateHandle, report: ProductionRuntimeBridgeReport) {
    // Fail-closed BEFORE any new execution side effect: when this ES already
    // carries a settlement checkpoint, it must still match IS's current settled
    // state. A stale or tampered ES (IS advanced past it, or its record no longer
    // agrees) is rejected here — we never advance IS first and discover the ES
    // mismatch afterwards. A fresh ES with no checkpoint has nothing to
    // cross-check yet, so its first settlement proceeds normally.
    if let checkpoint = runtime.settlementCheckpoint(for: Self.executionID) {
      let preExecutionISState = try informationSpaceLatestExecutionState(database: database)
      try validateSettlementAgainstInformationSpace(
        checkpoint: checkpoint,
        isState: preExecutionISState,
        handle: handle
      )
      // On the DURABLE resume path the settled physical carrier must also be
      // recoverable BEFORE we advance IS. Otherwise the recovery would proceed,
      // hit a missing representation mid-run, and silently fabricate a seed
      // prefix — masquerading as "recovered work" (the exact hazard req2 forbids)
      // and only discover the mismatch after IS already advanced. Fail closed now
      // so no new execution side effect is performed.
      if stateStore != nil, let handle,
         (try? backend.boundPrefix(for: handle)) == nil,
         !runtime.hasPersistedRepresentation(
          executionID: handle.id, position: handle.position) {
        throw ProductionRuntimeInformationError.persistedRepresentationUnavailable(
          executionID: handle.id.rawValue,
          position: handle.position.value
        )
      }
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
      _ = try runBridge("record-blocked", arguments: [
        "--database", database.path,
        "--state-id", "\(pendingStateID):executor-missing",
        "--prior-state-id", pendingStateID,
        "--reason", "model executor unavailable",
      ])
      throw ProductionRuntimeInformationError.modelExecutorUnavailable
    }

    let informationContext = String(decoding: resultData, as: UTF8.self)
    let continuationText = "\(Self.continuationPoint):\(advancementID)\n\(informationContext)"

    func failPending(_ stage: String, _ reason: String) throws {
      _ = try runBridge("record-blocked", arguments: [
        "--database", database.path,
        "--state-id", "\(pendingStateID):\(stage)-failed",
        "--prior-state-id", pendingStateID,
        "--reason", "\(stage): \(reason)",
      ])
    }

    var created = false
    var current: ExecutionStateHandle?
    var priorRepresentation: ExecutionRepresentation?
    var advanced: ExecutionStateHandle?
    var modelResult: ExecutionContinuationResult?
    var failureStage: String?
    var settledConfirmationState: [String: Any]?

    do {
      // Next-input tokenization precedes any logical mutation so a failure
      // here leaves zero lifecycle records (ProductionRuntimeFailureBoundary).
      failureStage = "tokenize_next_input"
      let nextInputTokens = try await modelExecutor.tokenizeText(continuationText)

      failureStage = "runtime_create_or_attach"
      if let handle {
        if runtime.handle(handle.id) != nil {
          current = try await runtime.reattach(handle)
        } else {
          current = try await runtime.attach(handle)
        }
        guard let attached = current else {
          throw ProductionRuntimeInformationError.modelExecutionFailed(reason: "runtime handle unavailable")
        }
        // RECOVERY PRIORITY: when this (fresh) backend has no physical binding
        // at the recovered position, rebind the PERSISTED representation rather
        // than re-tokenizing a seed. Re-tokenizing would fabricate a prefix and
        // masquerade as recovered work; the durable representation is the actual
        // settled physical state. On the DURABLE path a missing persisted carrier
        // is an inconsistency and MUST fail closed — never a silent seed fallback.
        // Only the stateless legacy mode (no store, no durable carrier by design)
        // keeps the first-ever seed bind here.
        if (try? backend.boundPrefix(for: attached)) == nil {
          failureStage = "representation_recovery_rebind"
          let reboundFromDurableState = try await runtime.restorePersistedBinding(
            executionID: attached.id,
            position: attached.position
          )
          if !reboundFromDurableState {
            guard stateStore == nil else {
              throw ProductionRuntimeInformationError.persistedRepresentationUnavailable(
                executionID: attached.id.rawValue,
                position: attached.position.value
              )
            }
            failureStage = "tokenize_seed"
            let seedTokens = try await modelExecutor.tokenizeSeedText(informationContext)
            failureStage = "representation_binding"
            try await runtime.bindRepresentation(
              executionID: attached.id,
              position: attached.position,
              payload: MLXPrefixPayload(tokenPrefix: seedTokens)
            )
          }
        }
      } else {
        // Fresh create: tokenize the seed BEFORE creating the logical ES, so a
        // seed failure yields zero lifecycle records (no partially-created state).
        failureStage = "tokenize_seed"
        let seedTokens = try await modelExecutor.tokenizeSeedText(informationContext)
        created = true
        failureStage = "runtime_create_or_attach"
        let fresh = try await runtime.create(
          id: Self.executionID,
          position: ExecutionPosition(0),
          continuation: ExecutionContinuation(
            nextInput: "\(Self.continuationPoint)-initial",
            continuationID: "\(Self.continuationPoint)-initial-cont"
          )
        )
        current = fresh
        failureStage = "representation_binding"
        try await runtime.bindRepresentation(
          executionID: fresh.id,
          position: fresh.position,
          payload: MLXPrefixPayload(tokenPrefix: seedTokens)
        )
      }
      guard let current else {
        throw ProductionRuntimeInformationError.modelExecutionFailed(reason: "runtime handle unavailable")
      }
      failureStage = "capture_pre_model_representation"
      priorRepresentation = try await backend.captureRepresentation(for: current)

      failureStage = "model_execution"
      modelResult = try await modelExecutor.continueExecution(
        current,
        nextInputTokens: nextInputTokens,
        maxTokens: 32
      )
      failureStage = "logical_advance"
      if let logicalAdvanceFault {
        throw logicalAdvanceFault
      }
      advanced = try await runtime.continueExecution(
        current,
        continuation: ExecutionContinuation(
          nextInput: "\(Self.continuationPoint):\(advancementID)",
          continuationID: "\(Self.continuationPoint):\(advancementID):cont"
        )
      )
      failureStage = "representation_binding"
      guard let unwrappedAdvanced = advanced,
            let unwrappedModelResult = modelResult else {
        throw ProductionRuntimeInformationError.modelExecutionFailed(reason: "runtime continuation result missing")
      }
      if let representationBindingFault {
        throw representationBindingFault
      }
      try await runtime.bindRepresentation(
        executionID: unwrappedAdvanced.id,
        position: unwrappedAdvanced.position,
        payload: unwrappedModelResult.updatedPayload
      )
      failureStage = "post_bind_verification"
      _ = try backend.boundPrefix(for: unwrappedAdvanced)
      failureStage = "carrier_confirmation"
      if let carrierConfirmationFault {
        throw carrierConfirmationFault
      }
      let confirmationResponse = try runBridge(
        "confirm-runtime-application",
        arguments: ["--database", database.path, "--state-id", pendingStateID]
      )
      settledConfirmationState = confirmationResponse["execution_state"] as? [String: Any]
    } catch {
      print("COMPENSATION_ENTER", failureStage as Any, advanced != nil, current != nil)
      failureStage = failureStage ?? "unclassified"
      try? failPending(failureStage!, String(describing: error))

      if let priorRepresentation {
        try? await backend.restoreRepresentation(priorRepresentation)
      }
      if let base = current {
        try await runtime.restore(
          base,
          request: ExecutionRestoreRequest(
            targetPosition: base.position,
            continuation: base.continuation
          )
        )
      }
      if let terminal = advanced ?? current {
        try await runtime.discard(terminal)
        backend.consumeBinding(for: terminal)
      }
      throw ProductionRuntimeInformationError.modelExecutionFailed(
        reason: "[\(failureStage ?? "unclassified")] \(error)"
      )
    }

    // Persist the ES↔IS settlement checkpoint AFTER the run fully succeeded
    // (logical advance + physical bind + IS runtime confirmation). The IS side
    // is captured from the authoritative confirmation record so a later recovery
    // can prove the ES matches IS's latest settled state. The confirmation
    // record (the new IS latest) is the completion evidence for the raw
    // advancement — capture BOTH ids so recovery never has to equate the ES
    // advancement with the raw advancement state id (which would wrongly reject
    // a normally completed recovery).
    if stateStore != nil,
       let confirmedState = settledConfirmationState,
       let confirmationStateID = confirmedState["state_id"] as? String,
       let confirmationPriorID = confirmedState["prior_state_id"] as? String,
       let isResultDigest = confirmedState["result_digest"] as? String,
       let isValidityBasis = confirmedState["demand_digest"] as? String,
       let advancedHandle = advanced {
      try await runtime.recordSettlementCheckpoint(
        ExecutionContinuityCoordinator.SettlementCheckpoint(
          executionID: advancedHandle.id,
          position: advancedHandle.position,
          lastSettledAdvancementID: advancementID,
          isOriginalStateID: confirmationPriorID,
          isConfirmationStateID: confirmationStateID,
          resultDigest: isResultDigest,
          validityBasis: isValidityBasis
        )
      )
    }

    return (
      advanced!,
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

  // MARK: - Real-model task continuation (model result settled into IS)

  /// Run one task step on the real model executor and settle ITS RESULT into the
  /// Information Space through the ordinary demand machinery.
  ///
  /// Ordering is deliberate and differs from ``continueWithRealInformation``:
  /// the model produces the value FIRST (from the ES's bound representation),
  /// then the value is settled, then the ES advances and rebinds the advanced
  /// representation, then IS confirms runtime application. The bridge accepts a
  /// model result only for exactly one item; if any dependency is not reusable
  /// the settlement refuses instead of covering work the model never did.
  ///
  /// `handle == nil` creates a fresh ES seeded with `seedText`. Passing a
  /// recovered handle resumes the durable representation; a missing persisted
  /// representation fails closed rather than fabricating a seed prefix.
  ///
  /// The model input is NEVER supplied by the caller: this entry resolves and
  /// admits it from the Information Space for `taskItemID` before any new side
  /// effect, so every ordinary task execution consumes the item's declared
  /// dependency settlements through the same admission contract. A missing,
  /// invalid, expired, byte-tampered or dependency-mismatched settlement
  /// refuses here, before tokenization and before generation.
  public func continueTask(
    database: URL,
    handle: ExecutionStateHandle?,
    advancementID: String,
    evaluatedAtUTC: String,
    demandID: String,
    taskItemID: String,
    seedText: String?,
    provenance: ProductionTaskProvenance,
    maxTokens: Int = 32,
    modelValue: (ExecutionContinuationResult, ProductionTaskInputAdmission) throws -> [String: Any]
  ) async throws -> ProductionTaskInformationContinuation {
    let admission = try resolveTaskInput(
      database: database, taskItemID: taskItemID, evaluatedAtUTC: evaluatedAtUTC)
    // Fail closed BEFORE any new side effect when this ES already carries a
    // settlement checkpoint that no longer matches IS's current settled state.
    if let checkpoint = runtime.settlementCheckpoint(for: Self.executionID) {
      let preExecutionISState = try informationSpaceLatestExecutionState(database: database)
      try validateSettlementAgainstInformationSpace(
        checkpoint: checkpoint,
        isState: preExecutionISState,
        handle: handle
      )
      if stateStore != nil, let handle,
         (try? backend.boundPrefix(for: handle)) == nil,
         !runtime.hasPersistedRepresentation(
          executionID: handle.id, position: handle.position) {
        throw ProductionRuntimeInformationError.persistedRepresentationUnavailable(
          executionID: handle.id.rawValue,
          position: handle.position.value
        )
      }
    }
    guard let modelExecutor else {
      throw ProductionRuntimeInformationError.modelExecutorUnavailable
    }

    var tokenizeSeedCallCount = 0
    var tokenizeNextInputCallCount = 0
    var modelContinuationCallCount = 0
    tokenizeNextInputCallCount += 1
    let nextInputTokens = try await modelExecutor.tokenizeText(admission.inputText)

    var created = false
    var current: ExecutionStateHandle?
    var priorRepresentation: ExecutionRepresentation?
    var advanced: ExecutionStateHandle?
    var modelResult: ExecutionContinuationResult?
    var failureStage: String?
    var settledConfirmationState: [String: Any]?
    var bridgeComputed: [String] = []
    var bridgeReused: [String] = []
    var bridgeActions: [ProductionTaskSettlementAction] = []
    var bridgeResultDigest = ""
    var pendingStateID = ""
    var valueFileURL: URL?
    var provenanceFileURL: URL?
    var settlementSignatureObjectID = ""
    var settlementSignedObjectID = ""
    var settlementSignatureKeyID = ""

    func failPending(_ stage: String, _ reason: String) throws {
      _ = try runBridge("record-blocked", arguments: [
        "--database", database.path,
        "--state-id", "\(pendingStateID.isEmpty ? advancementID : pendingStateID):\(stage)-failed",
        "--prior-state-id", pendingStateID.isEmpty ? advancementID : pendingStateID,
        "--reason", "\(stage): \(reason)",
      ])
    }

    do {
      failureStage = "runtime_create_or_attach"
      if let handle {
        if runtime.handle(handle.id) != nil {
          current = try await runtime.reattach(handle)
        } else {
          current = try await runtime.attach(handle)
        }
        guard let attached = current else {
          throw ProductionRuntimeInformationError.modelExecutionFailed(reason: "runtime handle unavailable")
        }
        // Recovery priority: rebind the PERSISTED representation. Re-tokenizing
        // a seed here would fabricate a prefix and masquerade as recovered work.
        if (try? backend.boundPrefix(for: attached)) == nil {
          failureStage = "representation_recovery_rebind"
          let reboundFromDurableState = try await runtime.restorePersistedBinding(
            executionID: attached.id,
            position: attached.position
          )
          guard reboundFromDurableState, stateStore != nil else {
            throw ProductionRuntimeInformationError.persistedRepresentationUnavailable(
              executionID: attached.id.rawValue,
              position: attached.position.value
            )
          }
        }
      } else {
        guard let seedText else {
          throw ProductionRuntimeInformationError.modelExecutionFailed(
            reason: "a fresh execution requires seed text")
        }
        failureStage = "tokenize_seed"
        tokenizeSeedCallCount += 1
        let seedTokens = try await modelExecutor.tokenizeSeedText(seedText)
        created = true
        failureStage = "runtime_create_or_attach"
        let fresh = try await runtime.create(
          id: Self.executionID,
          position: ExecutionPosition(0),
          continuation: ExecutionContinuation(
            nextInput: "\(Self.continuationPoint)-initial",
            continuationID: "\(Self.continuationPoint)-initial-cont"
          )
        )
        current = fresh
        failureStage = "representation_binding"
        try await runtime.bindRepresentation(
          executionID: fresh.id,
          position: fresh.position,
          payload: MLXPrefixPayload(tokenPrefix: seedTokens)
        )
      }
      guard let current else {
        throw ProductionRuntimeInformationError.modelExecutionFailed(reason: "runtime handle unavailable")
      }
      failureStage = "capture_pre_model_representation"
      priorRepresentation = try await backend.captureRepresentation(for: current)

      failureStage = "model_execution"
      modelContinuationCallCount += 1
      let produced = try await modelExecutor.continueExecution(
        current,
        nextInputTokens: nextInputTokens,
        maxTokens: maxTokens
      )
      modelResult = produced

      failureStage = "model_result_preparation"
      let value = try modelValue(produced, admission)
      let valueData = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
      let valueURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("simigo-model-result-\(UUID().uuidString).json")
      try valueData.write(to: valueURL, options: .atomic)
      valueFileURL = valueURL

      // Producer attestation: the run/execution/process/build identity, the
      // model snapshot and the exact generated tokens. The signing settlement
      // path binds these into the declaration; it never signs caller-supplied
      // bytes, and it recomputes the token digest against the model value.
      let provenanceURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("simigo-settlement-provenance-\(UUID().uuidString).json")
      let provenanceData = try JSONSerialization.data(
        withJSONObject: provenance.override(generatedTokenIDs: produced.generatedTokenIDs),
        options: [.sortedKeys])
      try provenanceData.write(to: provenanceURL, options: .atomic)
      provenanceFileURL = provenanceURL

      failureStage = "information_settlement"
      let response = try runBridge("execute-with-model-result", arguments: [
        "--database", database.path,
        "--demand-id", demandID,
        "--advancement", advancementID,
        "--evaluated-at", evaluatedAtUTC,
        "--item-id", taskItemID,
        "--value-file", valueURL.path,
        "--provenance-file", provenanceURL.path,
        "--run-id", provenance.runID,
        "--execution-id", provenance.executionID,
        "--build-sha256", provenance.buildSHA256,
        "--producer-process-id", provenance.processID,
      ])
      guard let signature = response["settlement_signature"] as? [String: Any],
            let signatureObjectID = signature["signature_object_id"] as? String,
            !signatureObjectID.isEmpty,
            let signedSettlementObjectID = signature["settlement_object_id"] as? String,
            !signedSettlementObjectID.isEmpty,
            let signatureKeyID = signature["key_id"] as? String,
            !signatureKeyID.isEmpty else {
        throw ProductionRuntimeInformationError.invalidBridgeResponse(
          command: "execute-with-model-result")
      }
      settlementSignatureObjectID = signatureObjectID
      settlementSignedObjectID = signedSettlementObjectID
      settlementSignatureKeyID = signatureKeyID
      guard let result = response["result"] as? [String: Any] else {
        throw ProductionRuntimeInformationError.invalidBridgeResponse(command: "execute-with-model-result")
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
            let unwrappedPendingStateID = executionState["state_id"] as? String else {
        throw ProductionRuntimeInformationError.invalidBridgeResponse(command: "execute-with-model-result")
      }
      pendingStateID = unwrappedPendingStateID
      bridgeComputed = result["computed_item_ids"] as? [String] ?? []
      bridgeReused = result["reused_item_ids"] as? [String] ?? []
      bridgeActions = (result["actions"] as? [[String: Any]] ?? []).map { action in
        ProductionTaskSettlementAction(
          itemID: action["item_id"] as? String ?? "",
          action: action["action"] as? String ?? "",
          settlementObjectID: action["settlement_object_id"] as? String ?? "",
          resultDigest: action["result_digest"] as? String ?? "",
          settlementSignatureObjectID: action["settlement_signature_object_id"] as? String
        )
      }
      // The signature envelope names the settlement it covers. That object must
      // be the very settlement this call reports for the executed item, and the
      // signature object named per action must be the envelope just read.
      guard let executedAction = bridgeActions.first(where: { $0.itemID == taskItemID }),
            executedAction.settlementObjectID == settlementSignedObjectID,
            executedAction.settlementSignatureObjectID == settlementSignatureObjectID else {
        throw ProductionRuntimeInformationError.invalidBridgeResponse(
          command: "execute-with-model-result")
      }
      let resultPayload = result["result"] as? [String: Any] ?? [:]
      let resultData = try JSONSerialization.data(withJSONObject: resultPayload, options: [.sortedKeys])
      bridgeResultDigest = SHA256.hash(data: resultData).map { String(format: "%02x", $0) }.joined()

      failureStage = "logical_advance"
      advanced = try await runtime.continueExecution(
        current,
        continuation: ExecutionContinuation(
          nextInput: "\(Self.continuationPoint):\(advancementID)",
          continuationID: "\(Self.continuationPoint):\(advancementID):cont"
        )
      )
      failureStage = "representation_binding"
      guard let unwrappedAdvanced = advanced, let unwrappedModelResult = modelResult else {
        throw ProductionRuntimeInformationError.modelExecutionFailed(
          reason: "runtime continuation result missing")
      }
      try await runtime.bindRepresentation(
        executionID: unwrappedAdvanced.id,
        position: unwrappedAdvanced.position,
        payload: unwrappedModelResult.updatedPayload
      )
      failureStage = "post_bind_verification"
      _ = try backend.boundPrefix(for: unwrappedAdvanced)
      failureStage = "carrier_confirmation"
      let confirmationResponse = try runBridge(
        "confirm-runtime-application",
        arguments: ["--database", database.path, "--state-id", pendingStateID]
      )
      settledConfirmationState = confirmationResponse["execution_state"] as? [String: Any]
    } catch {
      failureStage = failureStage ?? "unclassified"
      try? failPending(failureStage!, String(describing: error))
      if let priorRepresentation {
        try? await backend.restoreRepresentation(priorRepresentation)
      }
      if let base = current {
        try? await runtime.restore(
          base,
          request: ExecutionRestoreRequest(
            targetPosition: base.position,
            continuation: base.continuation
          )
        )
      }
      if let terminal = advanced ?? current {
        try? await runtime.discard(terminal)
        backend.consumeBinding(for: terminal)
      }
      if let valueFileURL { try? FileManager.default.removeItem(at: valueFileURL) }
      if let provenanceFileURL { try? FileManager.default.removeItem(at: provenanceFileURL) }
      throw ProductionRuntimeInformationError.modelExecutionFailed(
        reason: "[\(failureStage ?? "unclassified")] \(error)"
      )
    }
    if let valueFileURL { try? FileManager.default.removeItem(at: valueFileURL) }
    if let provenanceFileURL { try? FileManager.default.removeItem(at: provenanceFileURL) }

    // Bind the ES↔IS checkpoint to the authoritative confirmation record, so a
    // later recovery can prove the recovered ES matches IS's latest settlement.
    if stateStore != nil,
       let confirmedState = settledConfirmationState,
       let confirmationStateID = confirmedState["state_id"] as? String,
       let confirmationPriorID = confirmedState["prior_state_id"] as? String,
       let isResultDigest = confirmedState["result_digest"] as? String,
       let isValidityBasis = confirmedState["demand_digest"] as? String,
       let advancedHandle = advanced {
      try await runtime.recordSettlementCheckpoint(
        ExecutionContinuityCoordinator.SettlementCheckpoint(
          executionID: advancedHandle.id,
          position: advancedHandle.position,
          lastSettledAdvancementID: advancementID,
          isOriginalStateID: confirmationPriorID,
          isConfirmationStateID: confirmationStateID,
          resultDigest: isResultDigest,
          validityBasis: isValidityBasis
        )
      )
    }

    guard let advancedHandle = advanced,
          let produced = modelResult,
          let confirmation = settledConfirmationState,
          let confirmationStateID = confirmation["state_id"] as? String,
          let updatedPrefix = (produced.updatedPayload as? MLXPrefixPayload)?.tokenPrefix else {
      throw ProductionRuntimeInformationError.modelExecutionFailed(
        reason: "task continuation evidence unavailable")
    }
    let report = ProductionTaskContinuationReport(
      demandID: demandID,
      taskItemID: taskItemID,
      created: created,
      computedItemIDs: bridgeComputed,
      reusedItemIDs: bridgeReused,
      settlementActions: bridgeActions,
      resultDigest: bridgeResultDigest,
      isPendingStateID: pendingStateID,
      isConfirmationStateID: confirmationStateID,
      advancedPosition: advancedHandle.position.value,
      advancedLifecycle: advancedHandle.lifecycle.rawValue,
      consumedPrefixLength: produced.consumedPrefixLength,
      nextInputTokenCount: produced.nextInputTokenCount,
      nextInputTokenIDs: nextInputTokens,
      generatedTokenIDs: produced.generatedTokenIDs,
      generatedText: produced.generatedText,
      updatedPrefixTokenCount: updatedPrefix.count,
      tokenizeSeedCallCount: tokenizeSeedCallCount,
      tokenizeNextInputCallCount: tokenizeNextInputCallCount,
      modelContinuationCallCount: modelContinuationCallCount,
      settlementSignatureObjectID: settlementSignatureObjectID,
      signedSettlementObjectID: settlementSignedObjectID,
      settlementSignatureKeyID: settlementSignatureKeyID
    )
    return ProductionTaskInformationContinuation(
      handle: advancedHandle, report: report, admission: admission)
  }

  // MARK: - Information Space input admission (production task path)

  private static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  /// Template placeholders are the task item's OWN declaration (`{name}`); the
  /// production resolver expands them from admitted settlements only.
  private static let inputPlaceholderPattern: NSRegularExpression = {
    // Compile-time constant: an invalid pattern is a programming error.
    try! NSRegularExpression(pattern: "\\{([a-z][a-z0-9_]*)\\}")
  }()

  private static func expandInputTemplate(
    _ template: String,
    values: [String: String]
  ) -> String? {
    let text = template as NSString
    let matches = inputPlaceholderPattern.matches(
      in: template, range: NSRange(location: 0, length: text.length))
    var expanded = ""
    var cursor = 0
    for match in matches {
      expanded += text.substring(
        with: NSRange(location: cursor, length: match.range.location - cursor))
      let name = text.substring(with: match.range(at: 1))
      guard let value = values[name] else { return nil }
      expanded += value
      cursor = match.range.location + match.range.length
    }
    expanded += text.substring(from: cursor)
    return expanded
  }

  /// Resolve and ADMIT the model input for one task item from the Information
  /// Space, before any tokenization or generation.
  ///
  /// The production resolver reads the item's declared dependency closure,
  /// admits every settled dependency through the ordinary settlement reuse
  /// decision, and expands the item's own template. This method then verifies
  /// the returned material byte-for-byte: the object identity IS the content
  /// digest, the admitted value occupies exactly the declared byte range, and
  /// re-expanding the template reproduces the same input. The identity the
  /// executor admitted is therefore exactly the bytes handed to the model.
  public func resolveTaskInput(
    database: URL,
    taskItemID: String,
    evaluatedAtUTC: String
  ) throws -> ProductionTaskInputAdmission {
    let response: [String: Any]
    do {
      response = try runBridge("resolve-model-input", arguments: [
        "--database", database.path,
        "--item-id", taskItemID,
        "--evaluated-at", evaluatedAtUTC,
      ])
    } catch ProductionRuntimeInformationError.bridgeRefused(
      _, let stage, let reason, let itemID
    ) {
      throw ProductionRuntimeInformationError.informationSpaceInputAdmissionRefused(
        itemID: itemID ?? taskItemID, stage: stage, reason: reason)
    }
    guard let inputText = response["input_text"] as? String,
          let inputSHA256 = response["input_sha256"] as? String,
          let inputByteLength = response["input_byte_length"] as? Int,
          let template = response["template"] as? String,
          let templateSHA256 = response["template_sha256"] as? String,
          let declaredDependencies = response["declared_dependencies"] as? [String],
          let rawBindings = response["bindings"] as? [[String: Any]],
          let rawDependencies = response["dependencies"] as? [[String: Any]],
          let rawSignatures = response["settlement_signatures"] as? [[String: Any]],
          let rawChecks = response["checks"] as? [String: Any] else {
      throw ProductionRuntimeInformationError.invalidBridgeResponse(
        command: "resolve-model-input")
    }

    let inputData = Data(inputText.utf8)
    guard Self.sha256Hex(inputData) == inputSHA256 else {
      throw ProductionRuntimeInformationError.informationSpaceInputBindingMismatch(
        field: "input_sha256")
    }
    guard inputData.count == inputByteLength else {
      throw ProductionRuntimeInformationError.informationSpaceInputBindingMismatch(
        field: "input_byte_length")
    }
    guard Self.sha256Hex(Data(template.utf8)) == templateSHA256 else {
      throw ProductionRuntimeInformationError.informationSpaceInputBindingMismatch(
        field: "template_sha256")
    }
    // Every admission check the resolver reports must be present and true; an
    // unknown-but-false check also refuses rather than being ignored.
    let requiredChecks = [
      "all_declared_dependencies_admitted",
      "settlement_objects_readable",
      "object_identity_matches_bytes",
      "result_digests_match_values",
      "source_versions_match_items",
      "dependency_object_sets_match",
      "validity_satisfied",
      "all_placeholders_bound",
      "settlement_signatures_valid",
    ]
    for name in requiredChecks {
      guard rawChecks[name] as? Bool == true else {
        throw ProductionRuntimeInformationError.informationSpaceInputBindingMismatch(
          field: "admission_check:\(name)")
      }
    }
    for (name, value) in rawChecks where value as? Bool != true {
      throw ProductionRuntimeInformationError.informationSpaceInputBindingMismatch(
        field: "admission_check:\(name)")
    }

    var bindings: [ProductionTaskInputBinding] = []
    var boundValues: [String: String] = [:]
    for raw in rawBindings {
      guard let placeholder = raw["placeholder"] as? String,
            let itemID = raw["item_id"] as? String,
            let resultField = raw["result_field"] as? String,
            let value = raw["value"] as? String,
            let valueSHA256 = raw["value_sha256"] as? String,
            let settlementObjectID = raw["settlement_object_id"] as? String,
            let settlementObjectSHA256 = raw["settlement_object_sha256"] as? String,
            let resultValueSHA256 = raw["result_value_sha256"] as? String,
            let byteOffset = raw["byte_offset"] as? Int,
            let byteLength = raw["byte_length"] as? Int else {
        throw ProductionRuntimeInformationError.invalidBridgeResponse(
          command: "resolve-model-input")
      }
      let valueData = Data(value.utf8)
      guard Self.sha256Hex(valueData) == valueSHA256 else {
        throw ProductionRuntimeInformationError.informationSpaceInputBindingMismatch(
          field: "value_sha256:\(placeholder)")
      }
      // The object id IS the content digest: an identity that no longer hashes
      // to its own bytes cannot be the settled object it claims to be.
      guard settlementObjectID == settlementObjectSHA256 else {
        throw ProductionRuntimeInformationError.informationSpaceInputBindingMismatch(
          field: "object_identity:\(placeholder)")
      }
      guard byteOffset >= 0, byteLength == valueData.count,
            byteOffset + byteLength <= inputData.count else {
        throw ProductionRuntimeInformationError.informationSpaceInputBindingMismatch(
          field: "byte_range:\(placeholder)")
      }
      guard inputData.subdata(
        in: byteOffset..<(byteOffset + byteLength)) == valueData else {
        throw ProductionRuntimeInformationError.informationSpaceInputBindingMismatch(
          field: "byte_slice:\(placeholder)")
      }
      guard declaredDependencies.contains(itemID) else {
        throw ProductionRuntimeInformationError.informationSpaceInputBindingMismatch(
          field: "binding_dependency:\(placeholder)")
      }
      guard boundValues[placeholder] == nil else {
        throw ProductionRuntimeInformationError.informationSpaceInputBindingMismatch(
          field: "duplicate_placeholder:\(placeholder)")
      }
      boundValues[placeholder] = value
      bindings.append(ProductionTaskInputBinding(
        placeholder: placeholder,
        itemID: itemID,
        resultField: resultField,
        value: value,
        valueSHA256: valueSHA256,
        settlementObjectID: settlementObjectID,
        settlementObjectSHA256: settlementObjectSHA256,
        resultValueSHA256: resultValueSHA256,
        byteOffset: byteOffset,
        byteLength: byteLength))
    }

    var dependencyObjectIDs: [String: String] = [:]
    var dependenciesByItem: [String: [String: Any]] = [:]
    for raw in rawDependencies {
      guard let itemID = raw["item_id"] as? String,
            let objectID = raw["settlement_object_id"] as? String,
            let objectSHA256 = raw["settlement_object_sha256"] as? String else {
        throw ProductionRuntimeInformationError.invalidBridgeResponse(
          command: "resolve-model-input")
      }
      guard objectID == objectSHA256 else {
        throw ProductionRuntimeInformationError.informationSpaceInputBindingMismatch(
          field: "dependency_object_identity:\(itemID)")
      }
      guard dependenciesByItem[itemID] == nil else {
        throw ProductionRuntimeInformationError.informationSpaceInputBindingMismatch(
          field: "duplicate_dependency:\(itemID)")
      }
      dependencyObjectIDs[itemID] = objectID
      dependenciesByItem[itemID] = raw
    }
    guard dependencyObjectIDs.count == declaredDependencies.count,
          Set(dependencyObjectIDs.keys) == Set(declaredDependencies) else {
      throw ProductionRuntimeInformationError.informationSpaceInputBindingMismatch(
        field: "dependency_closure")
    }

    // Consumer-side provenance verification. Every admitted settlement must
    // carry an Ed25519 signature that verifies against the deployment anchor
    // AND whose signed provenance still names the exact settlement object,
    // source version, dependency closure, result digest and validity basis we
    // are about to feed to the model. This runs before tokenization.
    guard let trustAnchorPath = launchConfiguration?.settlementTrustAnchorPath?.path
      ?? ProcessInfo.processInfo.environment["SIMIGO_SETTLEMENT_TRUST_ANCHOR"] else {
      throw ProductionRuntimeInformationError.informationSpaceInputAdmissionRefused(
        itemID: taskItemID,
        stage: "SETTLEMENT_TRUST_ANCHOR_UNAVAILABLE",
        reason: "no deployment trust anchor path is configured for the consumer")
    }
    let verifiedSignatures: [ProductionTaskSettlementSignature]
    do {
      verifiedSignatures = try SettlementProvenanceVerifier.verify(
        signatures: rawSignatures,
        dependencies: dependenciesByItem,
        declaredDependencies: declaredDependencies,
        bindings: bindings,
        trustAnchorPath: trustAnchorPath)
    } catch let error as SettlementProvenanceError {
      throw ProductionRuntimeInformationError.informationSpaceInputAdmissionRefused(
        itemID: taskItemID, stage: error.code, reason: error.detail)
    }
    guard let expanded = Self.expandInputTemplate(template, values: boundValues) else {
      throw ProductionRuntimeInformationError.informationSpaceInputBindingMismatch(
        field: "template_placeholder_unbound")
    }
    guard expanded == inputText else {
      throw ProductionRuntimeInformationError.informationSpaceInputBindingMismatch(
        field: "template_expansion")
    }

    var checks: [String: Bool] = [:]
    for (name, value) in rawChecks { checks[name] = value as? Bool }
    return ProductionTaskInputAdmission(
      taskItemID: taskItemID,
      declaredDependencies: declaredDependencies,
      templateSHA256: templateSHA256,
      inputText: inputText,
      inputSHA256: inputSHA256,
      inputByteLength: inputByteLength,
      bindings: bindings,
      dependencySettlementObjectIDs: dependencyObjectIDs,
      settlementSignatures: verifiedSignatures,
      checks: checks
    )
  }

  // MARK: - Task bridge accessors

  @discardableResult
  public func defineTask(
    database: URL,
    evaluatedAtUTC: String,
    runLabel: String,
    secret: String? = nil,
    randomSecret: Bool = false
  ) throws -> [String: Any] {
    var arguments = [
      "--database", database.path,
      "--evaluated-at", evaluatedAtUTC,
      "--run-label", runLabel,
    ]
    if randomSecret {
      arguments += ["--random-secret"]
    } else if let secret {
      arguments += ["--secret", secret]
    }
    return try runBridge("define-task", arguments: arguments)
  }

  public func readItem(database: URL, itemID: String) throws -> [String: Any] {
    try runBridge("read-item", arguments: [
      "--database", database.path,
      "--item-id", itemID,
    ])
  }

  public func readSettlement(database: URL, itemID: String) throws -> [String: Any] {
    try runBridge("read-settlement", arguments: [
      "--database", database.path,
      "--item-id", itemID,
    ])
  }
}
