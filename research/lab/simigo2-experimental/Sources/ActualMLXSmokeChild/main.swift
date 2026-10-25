import Foundation
import Crypto
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers
import SimiGoRuntimeContract
import SimiGo2Experimental

enum ChildError: Error {
  case missingEnvironment(String)
  case invalidEnvironment(String)
  case terminalRecordAlreadyExists
  case terminalWriteFailed(String)
}

let environment = ProcessInfo.processInfo.environment
func requiredEnvironment(_ name: String) throws -> String {
  guard let value = environment[name], !value.isEmpty else {
    throw ChildError.missingEnvironment(name)
  }
  return value
}

func sha256(_ data: Data) -> String {
  data.withUnsafeBytes { buffer in
    SHA256.hash(data: buffer).map { String(format: "%02x", $0) }.joined()
  }
}

func writeTerminalRecord(_ record: [String: Any], to url: URL) throws {
  let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .prettyPrinted])
  let descriptor = open(url.path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
  guard descriptor >= 0 else {
    if errno == EEXIST {
      throw ChildError.terminalRecordAlreadyExists
    }
    throw ChildError.terminalWriteFailed(url.path)
  }
  let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
  try handle.write(contentsOf: data)
}

do {
  if environment["SIMIGO_MLX_SMOKE_FAULT"] == "WRITE_ONCE_CONFLICT" {
    let conflictURL = URL(fileURLWithPath: environment["SIMIGO_MLX_SMOKE_CONFLICT_FILE"] ?? "")
    let sample: [String: Any] = [
      "schema_id": "ACTUAL-MLX-SMOKE-RECORD-V1",
      "terminal_state": "MLX_SMOKE_FAIL",
      "run_count": 1,
    ]
    try writeTerminalRecord(sample, to: conflictURL)
    do {
      try writeTerminalRecord(sample, to: conflictURL)
      FileHandle.standardError.write(Data("second exclusive write unexpectedly succeeded\n".utf8))
      exit(1)
    } catch ChildError.terminalRecordAlreadyExists {
      exit(0)
    }
  }
  if environment["SIMIGO_MLX_SMOKE_FAULT"] == "PROCESS_TREE_WAIT" {
    let descendant = Process()
    descendant.executableURL = URL(fileURLWithPath: "/bin/sleep")
    descendant.arguments = ["5"]
    try descendant.run()
    if let descendantPath = environment["SIMIGO_MLX_SMOKE_DESCENDANT_FILE"], !descendantPath.isEmpty {
      try Data("\(descendant.processIdentifier)\n".utf8).write(
        to: URL(fileURLWithPath: descendantPath),
        options: .atomic
      )
    }
    descendant.waitUntilExit()
    exit(0)
  }
  guard environment["SIMIGO_MLX_SMOKE_RUN_TOKEN"]?.isEmpty == false else {
    throw ChildError.missingEnvironment("SIMIGO_MLX_SMOKE_RUN_TOKEN")
  }
  let labRoot = try URL(fileURLWithPath: requiredEnvironment("SIMIGO_MLX_SMOKE_LAB_ROOT"), isDirectory: true)
  let evidenceRoot = try URL(fileURLWithPath: requiredEnvironment("SIMIGO_MLX_SMOKE_EVIDENCE_ROOT"), isDirectory: true)
  let modelDirectory = try URL(fileURLWithPath: requiredEnvironment("SIMIGO_MLX_SMOKE_MODEL_DIRECTORY"), isDirectory: true)
  let manifestDigest = try requiredEnvironment("SIMIGO_MLX_SMOKE_MANIFEST_SHA256")
  let database = try URL(fileURLWithPath: requiredEnvironment("SIMIGO_MLX_SMOKE_DATABASE"), isDirectory: false)
  guard FileManager.default.fileExists(atPath: evidenceRoot.path) else {
    throw ChildError.invalidEnvironment("evidence root must be created by the one-run parent")
  }

  let startedAt = ISO8601DateFormatter().string(from: Date())
  let start = Date()
  var container: ModelContainer?
  var outcome: (handle: ExecutionStateHandle, report: ProductionRuntimeBridgeReport, boundTokenCount: Int)?
  var audit: [String: Any]?
  do {
    container = try await LLMModelFactory.shared.loadContainer(
      from: modelDirectory,
      using: #huggingFaceTokenizerLoader()
    )
    guard let unwrappedContainer = container else {
      throw ChildError.invalidEnvironment("model container unavailable")
    }
    let backend = MLXExecutionStateBackend()
    let executor = MLXPrefixRecomputeExecutor(container: unwrappedContainer, backend: backend)
    let configuration = ProductionRuntimeLaunchConfiguration(
      runtimeRoot: labRoot.appendingPathComponent("execution-information-loop"),
      pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"),
      snapshotPath: labRoot.appendingPathComponent(
        "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"
      ),
      validityPolicyPath: labRoot.appendingPathComponent(
        "integrated-es-palace/mlx-smoke-v1/ISOLATED_VALIDITY_POLICY.json"
      )
    )
    // The coordinator and the MLX executor must share one physical-state backend.
    let integration = ProductionRuntimeInformationIntegration(
      configuration: configuration,
      modelExecutor: executor,
      backend: backend
    )
    try integration.initialize(database: database, validUntil: "2030-12-31T23:59:59Z")
    let result = try await integration.continueWithRealInformation(
      database: database,
      handle: nil,
      advancementID: "actual-mlx-smoke-v6",
      evaluatedAtUTC: "2026-10-10T00:00:00Z"
    )
    let bound = try backend.boundPrefix(for: result.handle)
    audit = try ProductionRuntimeInformationIntegration(labRoot: labRoot).audit(database: database)
    outcome = (
      handle: result.handle,
      report: result.report,
      boundTokenCount: bound.prefix.count
    )
  } catch {
    var record: [String: Any] = [
      "schema_id": "ACTUAL-MLX-SMOKE-RECORD-V1",
      "manifest_sha256": manifestDigest,
      "terminal_state": "MLX_SMOKE_FAIL",
      "run_count": 1,
      "started_at_utc": startedAt,
      "completed_at_utc": ISO8601DateFormatter().string(from: Date()),
      "duration_seconds": Date().timeIntervalSince(start),
      "failure": String(describing: error),
    ]
    if let audit {
      record["audit"] = audit
    }
    try writeTerminalRecord(record, to: evidenceRoot.appendingPathComponent("MLX_SMOKE_FAIL.json"))
    throw error
  }

  guard let result = outcome, let audit else {
    throw ChildError.invalidEnvironment("smoke result unavailable")
  }
  let executionState = audit["execution_state"] as? [String: Any] ?? [:]
  let settlementStates = audit["current_settlement_states"] as? [String: String] ?? [:]
  let pendingObligations = executionState["pending_obligations"] as? [Any]
  var databaseIsDirectory: ObjCBool = false
  let carrierDatabasePresent = FileManager.default.fileExists(
    atPath: database.path,
    isDirectory: &databaseIsDirectory
  ) && !databaseIsDirectory.boolValue
  let successGate = ActualMLXSmokeSuccessGate.evaluate(
    ActualMLXSmokeSuccessGate.Observation(
      reportAdvanced: result.report.advanced,
      reportState: result.report.state,
      finalPosition: result.handle.position.value,
      finalLifecycle: result.handle.lifecycle.rawValue,
      boundRepresentationTokenCount: result.boundTokenCount,
      executionStateStatus: executionState["status"] as? String ?? "",
      runtimeApplicationStatus: executionState["runtime_application_status"] as? String ?? "",
      settlementStates: settlementStates,
      pendingObligationsRead: pendingObligations != nil,
      pendingObligationCount: pendingObligations?.count ?? 0,
      carrierObjectsVerified: audit["carrier_all_objects_verify"] as? Bool ?? false,
      carrierDatabasePresent: carrierDatabasePresent
    )
  )
  let passed = successGate.passed
  let terminalState = passed ? "MLX_SMOKE_PASS" : "MLX_SMOKE_FAIL"
  var record: [String: Any] = [
    "schema_id": "ACTUAL-MLX-SMOKE-RECORD-V1",
    "manifest_sha256": manifestDigest,
    "terminal_state": terminalState,
    "run_count": 1,
    "started_at_utc": startedAt,
    "completed_at_utc": ISO8601DateFormatter().string(from: Date()),
    "duration_seconds": Date().timeIntervalSince(start),
    "carrier_database_path": database.path,
    "result": [
      "advanced": result.report.advanced,
      "state": result.report.state,
      "computed_item_ids": result.report.computedItemIDs,
      "reused_item_ids": result.report.reusedItemIDs,
      "result_digest": result.report.resultDigest,
      "final_position": result.handle.position.value,
      "final_lifecycle": result.handle.lifecycle.rawValue,
      "bound_representation_token_count": result.boundTokenCount,
    ],
    "audit": audit,
    "success_gate_checks": successGate.checks,
  ]
  if !passed {
    let failedChecks = successGate.checks.filter { !$0.value }.keys.sorted()
    record["failure"] = "success gate failed: \(failedChecks.joined(separator: ","))"
  }
  try writeTerminalRecord(record, to: evidenceRoot.appendingPathComponent("\(terminalState).json"))
}
