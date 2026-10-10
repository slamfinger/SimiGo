import XCTest
import Crypto
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

private enum ActualMLXSmokeError: Error {
  case manifestDigestMismatch(actual: String, marker: String, sidecar: String)
  case manifestFieldMismatch(String)
  case bindingMismatch(String, expected: String, actual: String)
}

final class ActualMLXSmokeValidation: XCTestCase {
  private let labRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  func testActualMLXSmokeEvidenceSerializationPrecheck() throws {
    let sample: [String: Any] = [
      "schema_id": "ACTUAL-MLX-SMOKE-RECORD-V1",
      "terminal_state": "MLX_SMOKE_PASS",
      "run_count": 1,
      "result": [
        "advanced": true,
        "state": "ADVANCED",
        "computed_item_ids": ["REAL-1"],
        "reused_item_ids": [String](),
      ],
    ]
    let data = try JSONSerialization.data(withJSONObject: sample, options: [.sortedKeys])
    let restored = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    XCTAssertEqual("MLX_SMOKE_PASS", restored?["terminal_state"] as? String)
  }

  func testActualMLXSmokeSingleRun() async throws {
    let packageRoot = labRoot.appendingPathComponent("integrated-es-palace/mlx-smoke-v1")
    let markerURL = packageRoot.appendingPathComponent("ACTUAL_MLX_SMOKE_AUTHORIZED")
    guard FileManager.default.fileExists(atPath: markerURL.path) else {
      throw XCTSkip("ACTUAL MLX SMOKE = CANDIDATE / HUMAN AUTHORIZATION REQUIRED")
    }
    let manifestURL = packageRoot.appendingPathComponent("ACTUAL_MLX_SMOKE_MANIFEST_V1.json")
    let sidecarURL = packageRoot.appendingPathComponent("ACTUAL_MLX_SMOKE_MANIFEST_V1.sha256")
    let manifestData = try Data(contentsOf: manifestURL)
    let manifestDigest = Self.sha256(manifestData)
    let markerDigest = String(decoding: try Data(contentsOf: markerURL), as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let sidecarDigest = String(decoding: try Data(contentsOf: sidecarURL), as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard manifestDigest == markerDigest, manifestDigest == sidecarDigest else {
      throw ActualMLXSmokeError.manifestDigestMismatch(
        actual: manifestDigest,
        marker: markerDigest,
        sidecar: sidecarDigest
      )
    }
    let manifest = try JSONSerialization.jsonObject(with: manifestData) as! [String: Any]
    try Self.verifyManifest(manifest, labRoot: labRoot)

    let database = FileManager.default.temporaryDirectory
      .appendingPathComponent("actual-mlx-smoke-\(UUID().uuidString).sqlite")
    var result: (
      handle: ExecutionStateHandle,
      report: ProductionRuntimeBridgeReport,
      auditDatabase: URL,
      boundTokenCount: Int
    )?
    var failure: Error?
    let startedAt = ISO8601DateFormatter().string(from: Date())
    do {
      let modelDirectory = URL(fileURLWithPath: manifest["model_directory"] as! String)
      let container = try await LLMModelFactory.shared.loadContainer(
        from: modelDirectory,
        using: #huggingFaceTokenizerLoader()
      )
      let backend = MLXExecutionStateBackend()
      let executor = MLXPrefixRecomputeExecutor(container: container, backend: backend)
      let configuration = try Self.configuration(labRoot: labRoot)
      let integration = ProductionRuntimeInformationIntegration(
        configuration: configuration,
        modelExecutor: executor
      )
      try integration.initialize(
        database: database,
        validUntil: "2030-12-31T23:59:59Z"
      )
      result = try await Self.oneBoundedRun(
        integration: integration,
        database: database,
        backend: backend
      )
    } catch {
      failure = error
    }

    let evidenceRoot = labRoot.appendingPathComponent(
      manifest["evidence_root"] as! String,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: evidenceRoot, withIntermediateDirectories: true)
    var audit: [String: Any]?
    if let result {
      audit = try Self.integrationAudit(result.auditDatabase)
    }
    let executionStateStatus = ((audit?["execution_state"] as? [String: Any])?["status"] as? String) ?? ""
    let smokePass = failure == nil
      && result?.report.state == "ADVANCED"
      && result?.handle.position.value == 1
      && result?.handle.lifecycle == .active
      && (result?.boundTokenCount ?? 0) > 0
      && executionStateStatus == "SETTLED"
    let terminalState = smokePass ? "MLX_SMOKE_PASS" : "MLX_SMOKE_FAIL"
    var record: [String: Any] = [
      "schema_id": "ACTUAL-MLX-SMOKE-RECORD-V1",
      "manifest_sha256": manifestDigest,
      "terminal_state": terminalState,
      "run_count": 1,
      "started_at_utc": startedAt,
      "completed_at_utc": ISO8601DateFormatter().string(from: Date()),
    ]
    if let result {
      record["result"] = [
        "advanced": result.report.advanced,
        "state": result.report.state,
        "computed_item_ids": result.report.computedItemIDs,
        "reused_item_ids": result.report.reusedItemIDs,
        "result_digest": result.report.resultDigest,
        "final_position": result.handle.position.value,
        "final_lifecycle": result.handle.lifecycle.rawValue,
        "bound_representation_token_count": result.boundTokenCount,
      ]
      record["audit"] = audit
    } else {
      record["failure"] = String(describing: failure!)
    }
    let evidenceData = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    try evidenceData.write(
      to: evidenceRoot.appendingPathComponent("\(terminalState).json"),
      options: .atomic
    )
    if let result {
      try FileManager.default.copyItem(at: database, to: evidenceRoot.appendingPathComponent("carrier.sqlite"))
    }
    if !smokePass {
      throw failure ?? ActualMLXSmokeError.manifestFieldMismatch("actual smoke invariants")
    }
  }

  private static func oneBoundedRun(
    integration: ProductionRuntimeInformationIntegration,
    database: URL,
    backend: MLXExecutionStateBackend
  ) async throws -> (
    handle: ExecutionStateHandle,
    report: ProductionRuntimeBridgeReport,
    auditDatabase: URL,
    boundTokenCount: Int
  ) {
    try await withThrowingTaskGroup(of: (ExecutionStateHandle, ProductionRuntimeBridgeReport).self) { group in
      group.addTask {
        let outcome = try await integration.continueWithRealInformation(
          database: database,
          handle: nil,
          advancementID: "actual-mlx-smoke-v1",
          evaluatedAtUTC: "2026-10-10T00:00:00Z"
        )
        return (outcome.handle, outcome.report)
      }
      group.addTask {
        try await Task.sleep(nanoseconds: 20 * 60 * 1_000_000_000)
        throw ActualMLXSmokeError.manifestFieldMismatch("wall_clock_timeout")
      }
      guard let first = try await group.next() else {
        throw ActualMLXSmokeError.manifestFieldMismatch("missing smoke result")
      }
      group.cancelAll()
      let bound = try backend.boundPrefix(for: first.0)
      return (first.0, first.1, database, bound.prefix.count)
    }
  }

  private static func configuration(labRoot: URL) throws -> ProductionRuntimeLaunchConfiguration {
    ProductionRuntimeLaunchConfiguration(
      runtimeRoot: labRoot.appendingPathComponent("execution-information-loop"),
      pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"),
      snapshotPath: labRoot.appendingPathComponent(
        "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"
      ),
      validityPolicyPath: labRoot.appendingPathComponent(
        "integrated-es-palace/mlx-smoke-v1/ISOLATED_VALIDITY_POLICY.json"
      )
    )
  }

  private static func integrationAudit(_ database: URL) throws -> [String: Any] {
    try ProductionRuntimeInformationIntegration(labRoot: nil).audit(database: database)
  }

  private static func verifyManifest(_ manifest: [String: Any], labRoot: URL) throws {
    guard manifest["schema_id"] as? String == "ACTUAL-MLX-SMOKE-MANIFEST-V1" else {
      throw ActualMLXSmokeError.manifestFieldMismatch("schema_id")
    }
    guard manifest["status"] as? String == "CANDIDATE — HUMAN AUTHORIZATION REQUIRED" else {
      throw ActualMLXSmokeError.manifestFieldMismatch("status")
    }
    guard manifest["smoke_authorized"] as? Bool == false,
          manifest["smoke_executed"] as? Bool == false else {
      throw ActualMLXSmokeError.manifestFieldMismatch("authorization fields")
    }
    guard manifest["authorized_runs_if_approved"] as? Int == 1 else {
      throw ActualMLXSmokeError.manifestFieldMismatch("authorized_runs_if_approved")
    }
    for (field, relativePath) in sourceBindings {
      let actual = try fileDigest(labRoot.appendingPathComponent(relativePath))
      let expected = ((manifest["source_bindings"] as? [String: [String: String]])?[field]?["sha256"]) ?? ""
      guard actual == expected else {
        throw ActualMLXSmokeError.bindingMismatch(field, expected: expected, actual: actual)
      }
    }
    let information = try XCTUnwrap(manifest["information_space_binding"] as? [String: Any])
    let snapshot = try XCTUnwrap(information["sealed_palace_snapshot"] as? [String: Any])
    try verifyFileBinding(
      snapshot,
      labRoot: labRoot,
      pathField: "path",
      digestField: "sha256",
      label: "sealed_palace_snapshot"
    )
    let policy = try XCTUnwrap(information["validity_policy"] as? [String: Any])
    try verifyFileBinding(
      policy,
      labRoot: labRoot,
      pathField: "path",
      digestField: "raw_sha256",
      label: "validity_policy"
    )
    for (field, relativePath) in modelFiles {
      let modelDirectory = URL(fileURLWithPath: manifest["model_directory"] as! String)
      let actual = try fileDigest(modelDirectory.appendingPathComponent(relativePath))
      let expected = ((manifest["model_files"] as? [String: String])?[field]) ?? ""
      guard actual == expected else {
        throw ActualMLXSmokeError.bindingMismatch("model.\(field)", expected: expected, actual: actual)
      }
    }
  }

  private static let sourceBindings: [String: String] = [
    "smoke_runner": "simigo2-experimental/Tests/SimiGo2ExperimentalTests/ActualMLXSmokeValidation.swift",
    "production_integration": "simigo2-experimental/Sources/SimiGo2Experimental/ProductionRuntimeInformationIntegration.swift",
    "mlx_executor": "simigo2-experimental/Sources/SimiGo2Experimental/MLXPrefixRecomputeExecutor.swift",
    "failure_boundary_tests": "simigo2-experimental/Tests/SimiGo2ExperimentalTests/ProductionRuntimeFailureBoundaryTests.swift",
    "runtime_bridge": "execution-information-loop/production_runtime_bridge.py",
    "carrier_loop": "execution-information-loop/carrier_loop.py",
    "real_palace_loop": "execution-information-loop/real_palace_loop.py",
  ]

  private static let modelFiles: [String: String] = [
    "config": "config.json",
    "tokenizer": "tokenizer.json",
    "tokenizer_config": "tokenizer_config.json",
    "weight_1": "model-00001-of-00002.safetensors",
    "weight_2": "model-00002-of-00002.safetensors",
  ]

  private static func fileDigest(_ url: URL) throws -> String {
    sha256(try Data(contentsOf: url))
  }

  private static func verifyFileBinding(
    _ binding: [String: Any],
    labRoot: URL,
    pathField: String,
    digestField: String,
    label: String
  ) throws {
    let actual = try fileDigest(labRoot.appendingPathComponent(binding[pathField] as! String))
    let expected = binding[digestField] as? String ?? ""
    guard actual == expected else {
      throw ActualMLXSmokeError.bindingMismatch(label, expected: expected, actual: actual)
    }
  }

  private static func sha256(_ data: Data) -> String {
    data.withUnsafeBytes { buffer in
      SHA256.hash(data: buffer).map { String(format: "%02x", $0) }.joined()
    }
  }
}
