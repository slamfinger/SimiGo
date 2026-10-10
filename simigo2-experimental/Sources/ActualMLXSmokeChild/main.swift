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
  guard FileManager.default.createFile(atPath: url.path, contents: data) else {
    throw ChildError.terminalRecordAlreadyExists
  }
}

do {
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
    let integration = ProductionRuntimeInformationIntegration(
      configuration: configuration,
      modelExecutor: executor
    )
    try integration.initialize(database: database, validUntil: "2030-12-31T23:59:59Z")
    let result = try await integration.continueWithRealInformation(
      database: database,
      handle: nil,
      advancementID: "actual-mlx-smoke-v1",
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
  let executionStateStatus = ((audit["execution_state"] as? [String: Any])?["status"] as? String) ?? ""
  let passed = result.report.state == "ADVANCED"
    && result.handle.position.value == 1
    && result.handle.lifecycle == .active
    && result.boundTokenCount > 0
    && executionStateStatus == "SETTLED"
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
  ]
  if !passed {
    record["failure"] = "success gate did not pass"
  }
  try writeTerminalRecord(record, to: evidenceRoot.appendingPathComponent("\(terminalState).json"))
}
