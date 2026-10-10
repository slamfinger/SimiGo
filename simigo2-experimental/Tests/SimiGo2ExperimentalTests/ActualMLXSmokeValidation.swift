import Crypto
import Foundation
import XCTest

private enum ActualMLXSmokeError: Error {
  case manifestDigestMismatch(actual: String, marker: String, sidecar: String)
  case manifestFieldMismatch(String)
  case bindingMismatch(String, expected: String, actual: String)
  case terminalEvidenceInvalid(String)
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
    ]
    let data = try JSONSerialization.data(withJSONObject: sample, options: [.sortedKeys])
    let restored = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    XCTAssertEqual("MLX_SMOKE_PASS", restored?["terminal_state"] as? String)
  }

  func testActualMLXSmokeTimeoutAndWriteOncePrecheck() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("actual-mlx-smoke-precheck-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let writeOnce = directory.appendingPathComponent("write-once.json")
    XCTAssertTrue(try Self.createFileOnce(Data("first".utf8), at: writeOnce))
    XCTAssertFalse(try Self.createFileOnce(Data("second".utf8), at: writeOnce))
    XCTAssertEqual("first", String(decoding: try Data(contentsOf: writeOnce), as: UTF8.self))

    let sleep = Process()
    sleep.executableURL = URL(fileURLWithPath: "/bin/sleep")
    sleep.arguments = ["2"]
    try sleep.run()
    XCTAssertTrue(Self.waitForExit(sleep, timeout: 0.1))
    XCTAssertEqual(.uncaughtSignal, sleep.terminationReason)
  }

  func testActualMLXSmokeSingleRun() throws {
    let packageRoot = labRoot.appendingPathComponent("integrated-es-palace/mlx-smoke-v1")
    let markerURL = packageRoot.appendingPathComponent("ACTUAL_MLX_SMOKE_V2_AUTHORIZED")
    guard FileManager.default.fileExists(atPath: markerURL.path) else {
      throw XCTSkip("ACTUAL MLX SMOKE = CANDIDATE / HUMAN AUTHORIZATION REQUIRED")
    }
    let manifestURL = packageRoot.appendingPathComponent("ACTUAL_MLX_SMOKE_MANIFEST_V2.json")
    let sidecarURL = packageRoot.appendingPathComponent("ACTUAL_MLX_SMOKE_MANIFEST_V2.sha256")
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
    try Self.verifyManifest(manifest, labRoot: labRoot, manifestDigest: manifestDigest)

    let evidenceRoot = labRoot.appendingPathComponent(
      manifest["evidence_root"] as! String,
      isDirectory: true
    )
    guard !FileManager.default.fileExists(atPath: evidenceRoot.path) else {
      throw ActualMLXSmokeError.manifestFieldMismatch("write-once evidence root already exists")
    }
    try FileManager.default.createDirectory(at: evidenceRoot, withIntermediateDirectories: false)

    let startedAt = Date()
    let startedAtText = ISO8601DateFormatter().string(from: startedAt)
    let stdout = evidenceRoot.appendingPathComponent("child.stdout.log")
    let stderr = evidenceRoot.appendingPathComponent("child.stderr.log")
    guard try Self.createFileOnce(Data(), at: stdout), try Self.createFileOnce(Data(), at: stderr) else {
      throw ActualMLXSmokeError.manifestFieldMismatch("write-once child logs")
    }

    let consumedMarker = packageRoot.appendingPathComponent("ACTUAL_MLX_SMOKE_V2_AUTHORIZATION_CONSUMED")
    guard !FileManager.default.fileExists(atPath: consumedMarker.path) else {
      throw ActualMLXSmokeError.manifestFieldMismatch("authorization already consumed")
    }
    try FileManager.default.moveItem(at: markerURL, to: consumedMarker)

    let timeout = (manifest["execution"] as? [String: Any])?["wall_clock_timeout_seconds"] as? Int ?? 0
    var timedOut = false
    var launchFailure: Error?
    let child = Process()
    child.executableURL = labRoot.appendingPathComponent(
      "simigo2-experimental/.build/debug/ActualMLXSmokeChild"
    )
    child.arguments = []
    child.environment = [
      "SIMIGO_MLX_SMOKE_LAB_ROOT": labRoot.path,
      "SIMIGO_MLX_SMOKE_EVIDENCE_ROOT": evidenceRoot.path,
      "SIMIGO_MLX_SMOKE_MANIFEST_SHA256": manifestDigest,
      "SIMIGO_MLX_SMOKE_MODEL_DIRECTORY": manifest["model_directory"] as! String,
      "SIMIGO_MLX_SMOKE_DATABASE": evidenceRoot.appendingPathComponent("carrier.sqlite").path,
      "SIMIGO_MLX_SMOKE_RUN_TOKEN": UUID().uuidString,
    ]
    do {
      child.standardOutput = try FileHandle(forWritingTo: stdout)
      child.standardError = try FileHandle(forWritingTo: stderr)
      try child.run()
      timedOut = Self.waitForExit(child, timeout: TimeInterval(timeout))
    } catch {
      launchFailure = error
      if child.isRunning { _ = Self.waitForExit(child, timeout: 0) }
    }
    let completedAt = Date()

    let terminalURL = evidenceRoot.appendingPathComponent("MLX_SMOKE_FAIL.json")
    let passURL = evidenceRoot.appendingPathComponent("MLX_SMOKE_PASS.json")
    if !FileManager.default.fileExists(atPath: passURL.path),
       !FileManager.default.fileExists(atPath: terminalURL.path) {
      var record = Self.baseRecord(
        manifestDigest: manifestDigest,
        terminalState: "MLX_SMOKE_FAIL",
        startedAt: startedAtText,
        completedAt: completedAt
      )
      record["failure"] = timedOut
        ? "wall-clock timeout; child was terminated with SIGKILL"
        : launchFailure.map { String(describing: $0) }
          ?? "child exited without terminal evidence"
      record["timeout_seconds"] = timeout
      record["timed_out"] = timedOut
      record["child_exit_code"] = child.terminationStatus
      record["child_termination_reason"] = String(describing: child.terminationReason)
      _ = try Self.createFileOnce(
        try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .prettyPrinted]),
        at: terminalURL
      )
    }

    guard let evidenceData = try Self.terminalData(passURL: passURL, failURL: terminalURL),
          let record = try JSONSerialization.jsonObject(with: evidenceData) as? [String: Any],
          Self.validTerminalRecord(record, manifestDigest: manifestDigest, evidenceRoot: evidenceRoot)
    else {
      throw ActualMLXSmokeError.terminalEvidenceInvalid("missing or invalid write-once terminal record")
    }
    if record["terminal_state"] as? String == "MLX_SMOKE_FAIL" {
      throw ActualMLXSmokeError.terminalEvidenceInvalid("authorized smoke terminated with MLX_SMOKE_FAIL")
    }
  }

  private static func terminalData(passURL: URL, failURL: URL) throws -> Data? {
    if FileManager.default.fileExists(atPath: passURL.path) {
      return try Data(contentsOf: passURL)
    }
    if FileManager.default.fileExists(atPath: failURL.path) {
      return try Data(contentsOf: failURL)
    }
    return nil
  }

  private static func validTerminalRecord(
    _ record: [String: Any],
    manifestDigest: String,
    evidenceRoot: URL
  ) -> Bool {
    guard record["schema_id"] as? String == "ACTUAL-MLX-SMOKE-RECORD-V1",
          record["manifest_sha256"] as? String == manifestDigest,
          record["run_count"] as? Int == 1,
          let terminal = record["terminal_state"] as? String,
          ["MLX_SMOKE_PASS", "MLX_SMOKE_FAIL"].contains(terminal)
    else { return false }
    guard terminal == "MLX_SMOKE_PASS" else { return true }
    let result = record["result"] as? [String: Any] ?? [:]
    let audit = record["audit"] as? [String: Any] ?? [:]
    let executionState = audit["execution_state"] as? [String: Any] ?? [:]
    return result["state"] as? String == "ADVANCED"
      && result["final_position"] as? Int == 1
      && result["final_lifecycle"] as? String == "active"
      && (result["bound_representation_token_count"] as? Int ?? 0) > 0
      && executionState["status"] as? String == "SETTLED"
      && FileManager.default.fileExists(atPath: evidenceRoot.appendingPathComponent("carrier.sqlite").path)
  }

  private static func baseRecord(
    manifestDigest: String,
    terminalState: String,
    startedAt: String,
    completedAt: Date
  ) -> [String: Any] {
    [
      "schema_id": "ACTUAL-MLX-SMOKE-RECORD-V1",
      "manifest_sha256": manifestDigest,
      "terminal_state": terminalState,
      "run_count": 1,
      "started_at_utc": startedAt,
      "completed_at_utc": ISO8601DateFormatter().string(from: completedAt),
    ]
  }

  private static func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.2)
    }
    guard process.isRunning else { return false }
    kill(process.processIdentifier, SIGKILL)
    process.waitUntilExit()
    return true
  }

  private static func createFileOnce(_ data: Data, at url: URL) throws -> Bool {
    let descriptor = open(url.path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
    guard descriptor >= 0 else { return false }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    try handle.write(contentsOf: data)
    return true
  }

  private static func verifyManifest(
    _ manifest: [String: Any],
    labRoot: URL,
    manifestDigest: String
  ) throws {
    guard manifest["schema_id"] as? String == "ACTUAL-MLX-SMOKE-MANIFEST-V2",
          manifest["status"] as? String == "CANDIDATE — HUMAN AUTHORIZATION REQUIRED",
          manifest["smoke_authorized"] as? Bool == false,
          manifest["smoke_executed"] as? Bool == false,
          manifest["authorized_runs_if_approved"] as? Int == 1,
          manifest["maximum_total_new_runs"] as? Int == 1 else {
      throw ActualMLXSmokeError.manifestFieldMismatch("one-run authorization fields")
    }
    guard let sourceBindings = manifest["source_bindings"] as? [String: [String: String]] else {
      throw invalidObject()
    }
    guard Set(sourceBindings.keys) == Set(Self.sourceBindings.keys) else {
      throw ActualMLXSmokeError.manifestFieldMismatch("source binding key set")
    }
    for (field, expectedPath) in Self.sourceBindings {
      guard let binding = sourceBindings[field] else {
        throw invalidObject()
      }
      guard binding["path"] == expectedPath else {
        throw ActualMLXSmokeError.bindingMismatch(
          field,
          expected: expectedPath,
          actual: binding["path"] ?? ""
        )
      }
      let actual = try fileDigest(labRoot.appendingPathComponent(expectedPath))
      guard actual == binding["sha256"] else {
        throw ActualMLXSmokeError.bindingMismatch(field, expected: binding["sha256"] ?? "", actual: actual)
      }
    }

    guard let runner = manifest["runner_binding"] as? [String: Any],
          let childPath = runner["child_source_path"] as? String,
          let childExpected = runner["child_source_sha256"] as? String else {
      throw invalidObject()
    }
    let childActual = try fileDigest(labRoot.appendingPathComponent(childPath))
    guard childActual == childExpected else {
      throw ActualMLXSmokeError.bindingMismatch("child_source", expected: childExpected, actual: childActual)
    }
    guard let packagePath = runner["package_manifest_path"] as? String,
          let packageExpected = runner["package_manifest_sha256"] as? String else {
      throw invalidObject()
    }
    let packageActual = try fileDigest(labRoot.appendingPathComponent(packagePath))
    guard packageActual == packageExpected else {
      throw ActualMLXSmokeError.bindingMismatch("package_manifest", expected: packageExpected, actual: packageActual)
    }

    guard let execution = manifest["execution"] as? [String: Any] else {
      throw invalidObject()
    }
    guard execution["mode"] as? String == "ONE_FRESH_ENTRY_ACTUAL_MLX_RUN",
          execution["model_calls_authorized"] as? Int == 1,
          execution["max_tokens_upper_bound"] as? Int == 32,
          execution["wall_clock_timeout_seconds"] as? Int == 1200,
          execution["parent_process_hard_kill_on_timeout"] as? Bool == true else {
      throw ActualMLXSmokeError.manifestFieldMismatch("bounded execution fields")
    }

    guard let evidence = manifest["evidence"] as? [String: Any] else {
      throw invalidObject()
    }
    guard evidence["root"] as? String == "integrated-es-palace/mlx-smoke-v1/mlx-smoke-evidence-v2",
          evidence["write_once"] as? Bool == true,
          evidence["must_not_exist_before_authorized_run"] as? Bool == true,
          evidence["terminal_record_create_mode"] as? String == "create_exclusive_no_overwrite" else {
      throw ActualMLXSmokeError.manifestFieldMismatch("write-once evidence fields")
    }

    guard let gate = manifest["authorization_gate"] as? [String: Any] else {
      throw invalidObject()
    }
    guard gate["marker_path"] as? String == "integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_V2_AUTHORIZED",
          gate["consumption_path"] as? String == "integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_V2_AUTHORIZATION_CONSUMED",
          gate["consumption_mode"] as? String == "atomic_rename_before_child_launch" else {
      throw ActualMLXSmokeError.manifestFieldMismatch("one-shot authorization gate")
    }

    guard let information = manifest["information_space_binding"] as? [String: Any],
          let snapshot = information["sealed_palace_snapshot"] as? [String: Any] else {
      throw invalidObject()
    }
    try verifyFileBinding(snapshot, labRoot: labRoot, pathField: "path", digestField: "sha256", label: "snapshot")
    guard let policy = information["validity_policy"] as? [String: Any] else {
      throw invalidObject()
    }
    try verifyFileBinding(policy, labRoot: labRoot, pathField: "path", digestField: "raw_sha256", label: "policy")

    let modelDirectory = URL(fileURLWithPath: manifest["model_directory"] as! String)
    for (field, relativePath) in modelFiles {
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
    "execution_state_backend": "simigo2-experimental/Sources/SimiGo2Experimental/MLXExecutionStateBackend.swift",
    "continuity_coordinator": "simigo2-experimental/Sources/SimiGo2Experimental/ExecutionContinuityCoordinator.swift",
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

  private static func invalidObject() -> Error {
    ActualMLXSmokeError.manifestFieldMismatch("required object")
  }

  private static func sha256(_ data: Data) -> String {
    data.withUnsafeBytes { buffer in
      SHA256.hash(data: buffer).map { String(format: "%02x", $0) }.joined()
    }
  }
}
