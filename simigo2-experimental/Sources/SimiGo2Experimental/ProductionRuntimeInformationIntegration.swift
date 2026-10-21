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
}
