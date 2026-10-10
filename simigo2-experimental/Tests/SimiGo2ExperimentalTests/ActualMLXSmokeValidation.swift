import Crypto
import Darwin
import Foundation
import XCTest
import SimiGo2Experimental

private enum ActualMLXSmokeError: Error {
  case manifestDigestMismatch(actual: String, marker: String, sidecar: String)
  case manifestFieldMismatch(String)
  case bindingMismatch(String, expected: String, actual: String)
  case terminalEvidenceInvalid(String)
}

private struct ActualMLXSmokeSidecar {
  let digest: String
  let filename: String
}

private struct SpawnedChildExit {
  let exitCode: Int32
  let signalNumber: Int32?
  let timedOut: Bool
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

  func testActualMLXSmokeSidecarFormatPrecheck() throws {
    let packageRoot = labRoot.appendingPathComponent("integrated-es-palace/mlx-smoke-v1")
    let manifestURL = packageRoot.appendingPathComponent("ACTUAL_MLX_SMOKE_MANIFEST_V6.json")
    let sidecarURL = packageRoot.appendingPathComponent("ACTUAL_MLX_SMOKE_MANIFEST_V6.sha256")
    let sidecar = try Self.parseSidecar(String(decoding: Data(contentsOf: sidecarURL), as: UTF8.self))
    XCTAssertEqual(manifestURL.lastPathComponent, sidecar.filename)
    XCTAssertEqual(Self.sha256(try Data(contentsOf: manifestURL)), sidecar.digest)
  }

  func testActualMLXSmokeManifestEvidenceFieldPrecheck() throws {
    let manifestURL = labRoot.appendingPathComponent(
      "integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_MANIFEST_V6.json"
    )
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
    let evidence = try Self.evidenceBinding(manifest, labRoot: labRoot)
    XCTAssertEqual("integrated-es-palace/mlx-smoke-v1/mlx-smoke-evidence-v6", evidence.relativePath)
    XCTAssertEqual(
      labRoot.appendingPathComponent(evidence.relativePath, isDirectory: true).standardizedFileURL,
      evidence.url.standardizedFileURL
    )
  }

  func testActualMLXSmokeSuccessGateSeparatesCarrierStateLayers() {
    let settlements = [
      "REAL-COLLECTION": "SETTLED",
      "REAL-SEGMENT": "SETTLED",
      "REAL-1": "SETTLED",
      "REAL-2": "SETTLED",
      "REAL-3": "SETTLED",
      "REAL-4": "SETTLED",
      "REAL-5": "SETTLED",
      "REAL-6": "SETTLED",
      "REAL-7": "SETTLED",
    ]
    let healthy = ActualMLXSmokeSuccessGate.evaluate(
      ActualMLXSmokeSuccessGate.Observation(
        reportAdvanced: true,
        reportState: "ADVANCED",
        finalPosition: 1,
        finalLifecycle: "active",
        boundRepresentationTokenCount: 1,
        executionStateStatus: "ADVANCED",
        runtimeApplicationStatus: "APPLIED_SWIFT",
        settlementStates: settlements,
        pendingObligationsRead: true,
        pendingObligationCount: 0,
        carrierObjectsVerified: true,
        carrierDatabasePresent: true
      )
    )
    XCTAssertTrue(healthy.passed)
    XCTAssertTrue(healthy.checks.values.allSatisfy { $0 })

    // This reproduces the V5 gate defect: settlement completion must not be
    // mistaken for Execution State advancement.
    let conflated = ActualMLXSmokeSuccessGate.evaluate(
      ActualMLXSmokeSuccessGate.Observation(
        reportAdvanced: true,
        reportState: "ADVANCED",
        finalPosition: 1,
        finalLifecycle: "active",
        boundRepresentationTokenCount: 1,
        executionStateStatus: "SETTLED",
        runtimeApplicationStatus: "APPLIED_SWIFT",
        settlementStates: settlements,
        pendingObligationsRead: true,
        pendingObligationCount: 0,
        carrierObjectsVerified: true,
        carrierDatabasePresent: true
      )
    )
    XCTAssertFalse(conflated.passed)
    XCTAssertEqual(false, conflated.checks["execution_state_advanced"])
    XCTAssertEqual(true, conflated.checks["required_settlements_settled"])
  }

  func testActualMLXSmokeSuccessGateRejectsPendingAndDatabaseDefects() {
    func observation(pendingRead: Bool, pendingCount: Int, databasePresent: Bool)
      -> ActualMLXSmokeSuccessGate.Observation {
      ActualMLXSmokeSuccessGate.Observation(
        reportAdvanced: true,
        reportState: "ADVANCED",
        finalPosition: 1,
        finalLifecycle: "active",
        boundRepresentationTokenCount: 1,
        executionStateStatus: "ADVANCED",
        runtimeApplicationStatus: "APPLIED_SWIFT",
        settlementStates: Self.requiredSettlements,
        pendingObligationsRead: pendingRead,
        pendingObligationCount: pendingCount,
        carrierObjectsVerified: true,
        carrierDatabasePresent: databasePresent
      )
    }

    let defects: [(label: String, pendingRead: Bool, pendingCount: Int, databasePresent: Bool)] = [
      ("missing-field", pendingRead: false, pendingCount: 0, databasePresent: true),
      ("wrong-type", pendingRead: false, pendingCount: 0, databasePresent: true),
      ("non-empty", pendingRead: true, pendingCount: 1, databasePresent: true),
      ("database-missing", pendingRead: true, pendingCount: 0, databasePresent: false),
    ]
    for defect in defects {
      let gate = ActualMLXSmokeSuccessGate.evaluate(
        observation(pendingRead: defect.pendingRead, pendingCount: defect.pendingCount, databasePresent: defect.databasePresent)
      )
      XCTAssertFalse(gate.passed, defect.label)
    }
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

  func testActualMLXSmokeChildWriteOncePrecheck() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("actual-mlx-child-precheck-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let conflictFile = directory.appendingPathComponent("terminal.json")
    let childPID = try Self.spawnIsolatedChild(
      executable: labRoot.appendingPathComponent("simigo2-experimental/.build/debug/ActualMLXSmokeChild"),
      environment: [
      "SIMIGO_MLX_SMOKE_FAULT": "WRITE_ONCE_CONFLICT",
      "SIMIGO_MLX_SMOKE_CONFLICT_FILE": conflictFile.path,
      ],
      stdout: nil,
      stderr: nil
    )
    let childExit = Self.waitForExit(childPID, timeout: 5)
    XCTAssertFalse(childExit.timedOut)
    XCTAssertEqual(0, childExit.exitCode)
    XCTAssertNil(childExit.signalNumber)
    XCTAssertEqual("MLX_SMOKE_FAIL", try Self.terminalState(Data(contentsOf: conflictFile)))
  }

  func testActualMLXSmokeChildProcessTreeTerminationPrecheck() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("actual-mlx-process-tree-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pgidFile = directory.appendingPathComponent("child.pgid")
    let descendantFile = directory.appendingPathComponent("descendant.pid")
    let childPID = try Self.spawnIsolatedChild(
      executable: labRoot.appendingPathComponent("simigo2-experimental/.build/debug/ActualMLXSmokeChild"),
      environment: [
      "SIMIGO_MLX_SMOKE_FAULT": "PROCESS_TREE_WAIT",
      "SIMIGO_MLX_SMOKE_DESCENDANT_FILE": descendantFile.path,
      ],
      stdout: nil,
      stderr: nil
    )
    try Data("\(childPID)\n".utf8).write(to: pgidFile, options: .atomic)
    let deadline = Date().addingTimeInterval(2)
    while (!FileManager.default.fileExists(atPath: pgidFile.path)
        || !FileManager.default.fileExists(atPath: descendantFile.path)), Date() < deadline {
      Thread.sleep(forTimeInterval: 0.02)
    }
    let pgid = childPID
    let descendant = pid_t(String(decoding: try Data(contentsOf: descendantFile), as: UTF8.self).trimmingCharacters(in: .newlines))!
    let childExit = Self.waitForExit(childPID, timeout: 1)
    XCTAssertTrue(childExit.timedOut)
    for _ in 0..<100 where kill(descendant, 0) == 0 {
      Thread.sleep(forTimeInterval: 0.05)
    }
    XCTAssertEqual(ESRCH, errno)
    for _ in 0..<100 where kill(-pgid, 0) == 0 {
      Thread.sleep(forTimeInterval: 0.05)
    }
    XCTAssertEqual(ESRCH, errno)
  }

  func testActualMLXSmokeSingleRun() throws {
    let packageRoot = labRoot.appendingPathComponent("integrated-es-palace/mlx-smoke-v1")
    let markerURL = packageRoot.appendingPathComponent("ACTUAL_MLX_SMOKE_V6_AUTHORIZED")
    guard FileManager.default.fileExists(atPath: markerURL.path) else {
      throw XCTSkip("ACTUAL MLX SMOKE = CANDIDATE / HUMAN AUTHORIZATION REQUIRED")
    }
    let manifestURL = packageRoot.appendingPathComponent("ACTUAL_MLX_SMOKE_MANIFEST_V6.json")
    let sidecarURL = packageRoot.appendingPathComponent("ACTUAL_MLX_SMOKE_MANIFEST_V6.sha256")
    let manifestData = try Data(contentsOf: manifestURL)
    let manifestDigest = Self.sha256(manifestData)
    let markerDigest = String(decoding: try Data(contentsOf: markerURL), as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let sidecar = try Self.parseSidecar(String(decoding: try Data(contentsOf: sidecarURL), as: UTF8.self))
    guard sidecar.filename == manifestURL.lastPathComponent else {
      throw ActualMLXSmokeError.manifestFieldMismatch("sidecar filename")
    }
    let sidecarDigest = sidecar.digest
    guard manifestDigest == markerDigest, manifestDigest == sidecarDigest else {
      throw ActualMLXSmokeError.manifestDigestMismatch(
        actual: manifestDigest,
        marker: markerDigest,
        sidecar: sidecarDigest
      )
    }
    let manifest = try JSONSerialization.jsonObject(with: manifestData) as! [String: Any]
    try Self.verifyManifest(manifest, labRoot: labRoot, manifestDigest: manifestDigest)

    let evidence = try Self.evidenceBinding(manifest, labRoot: labRoot)
    let evidenceRoot = evidence.url
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

    let consumedMarker = packageRoot.appendingPathComponent("ACTUAL_MLX_SMOKE_V6_AUTHORIZATION_CONSUMED")
    guard !FileManager.default.fileExists(atPath: consumedMarker.path) else {
      throw ActualMLXSmokeError.manifestFieldMismatch("authorization already consumed")
    }
    try FileManager.default.moveItem(at: markerURL, to: consumedMarker)

    let timeout = (manifest["execution"] as? [String: Any])?["wall_clock_timeout_seconds"] as? Int ?? 0
    var childExit = SpawnedChildExit(exitCode: 0, signalNumber: nil, timedOut: false)
    var launchFailure: Error?
    var childPID: pid_t?
    do {
      childPID = try Self.spawnIsolatedChild(
        executable: labRoot.appendingPathComponent("simigo2-experimental/.build/debug/ActualMLXSmokeChild"),
        environment: [
          "SIMIGO_MLX_SMOKE_LAB_ROOT": labRoot.path,
          "SIMIGO_MLX_SMOKE_EVIDENCE_ROOT": evidenceRoot.path,
          "SIMIGO_MLX_SMOKE_MANIFEST_SHA256": manifestDigest,
          "SIMIGO_MLX_SMOKE_MODEL_DIRECTORY": manifest["model_directory"] as! String,
          "SIMIGO_MLX_SMOKE_DATABASE": evidenceRoot.appendingPathComponent("carrier.sqlite").path,
          "SIMIGO_MLX_SMOKE_RUN_TOKEN": UUID().uuidString,
        ],
        stdout: stdout,
        stderr: stderr
      )
      try Data("\(childPID!)\n".utf8).write(
        to: evidenceRoot.appendingPathComponent("child.pgid"),
        options: .atomic
      )
      childExit = Self.waitForExit(childPID!, timeout: TimeInterval(timeout))
    } catch {
      launchFailure = error
      if let childPID { _ = Self.waitForExit(childPID, timeout: 0) }
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
      record["failure"] = childExit.timedOut
        ? "wall-clock timeout; child was terminated with SIGKILL"
        : launchFailure.map { String(describing: $0) }
          ?? "child exited without terminal evidence"
      record["timeout_seconds"] = timeout
      record["timed_out"] = childExit.timedOut
      record["child_pid"] = childPID
      record["child_process_group_id"] = childPID
      record["child_exit_code"] = childExit.exitCode
      record["child_exit_signal"] = childExit.signalNumber
      _ = try Self.createFileOnce(
        try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .prettyPrinted]),
        at: terminalURL
      )
    }

    switch try Self.selectTerminalEvidence(passURL: passURL, failURL: terminalURL) {
    case .conflict:
      throw ActualMLXSmokeError.terminalEvidenceInvalid("conflicting write-once terminal records")
    case .missing:
      throw ActualMLXSmokeError.terminalEvidenceInvalid("missing write-once terminal record")
    case .pass(let evidenceData), .fail(let evidenceData):
      guard let record = try JSONSerialization.jsonObject(with: evidenceData) as? [String: Any],
            Self.validTerminalRecord(record, manifestDigest: manifestDigest, evidenceRoot: evidenceRoot)
      else {
        throw ActualMLXSmokeError.terminalEvidenceInvalid("invalid write-once terminal record")
      }
      if record["terminal_state"] as? String == "MLX_SMOKE_FAIL" {
        throw ActualMLXSmokeError.terminalEvidenceInvalid("authorized smoke terminated with MLX_SMOKE_FAIL")
      }
    }
  }

  private enum TerminalEvidence: Equatable {
    case pass(Data)
    case fail(Data)
    case conflict
    case missing
  }

  private static func selectTerminalEvidence(passURL: URL, failURL: URL) throws -> TerminalEvidence {
    let passExists = FileManager.default.fileExists(atPath: passURL.path)
    let failExists = FileManager.default.fileExists(atPath: failURL.path)
    if passExists, failExists { return .conflict }
    if passExists { return .pass(try Data(contentsOf: passURL)) }
    if failExists { return .fail(try Data(contentsOf: failURL)) }
    return .missing
  }

  private static func healthyObservation(databasePresent: Bool = true)
    -> ActualMLXSmokeSuccessGate.Observation {
    ActualMLXSmokeSuccessGate.Observation(
      reportAdvanced: true,
      reportState: "ADVANCED",
      finalPosition: 1,
      finalLifecycle: "active",
      boundRepresentationTokenCount: 1,
      executionStateStatus: "ADVANCED",
      runtimeApplicationStatus: "APPLIED_SWIFT",
      settlementStates: requiredSettlements,
      pendingObligationsRead: true,
      pendingObligationCount: 0,
      carrierObjectsVerified: true,
      carrierDatabasePresent: databasePresent
    )
  }

  func testActualMLXSmokeTerminalEvidenceSelectionFailsClosed() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("actual-mlx-terminal-selection-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pass = directory.appendingPathComponent("MLX_SMOKE_PASS.json")
    let fail = directory.appendingPathComponent("MLX_SMOKE_FAIL.json")
    XCTAssertEqual(.missing, try Self.selectTerminalEvidence(passURL: pass, failURL: fail))
    try Data("pass".utf8).write(to: pass)
    XCTAssertEqual(.pass(Data("pass".utf8)), try Self.selectTerminalEvidence(passURL: pass, failURL: fail))
    try Data("fail".utf8).write(to: fail)
    XCTAssertEqual(.conflict, try Self.selectTerminalEvidence(passURL: pass, failURL: fail))
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
    let pendingObligations = executionState["pending_obligations"] as? [Any]
    let settlementStates = audit["current_settlement_states"] as? [String: String] ?? [:]
    var databaseIsDirectory: ObjCBool = false
    let databasePresent = FileManager.default.fileExists(
      atPath: evidenceRoot.appendingPathComponent("carrier.sqlite").path,
      isDirectory: &databaseIsDirectory
    ) && !databaseIsDirectory.boolValue
    let recomputed = ActualMLXSmokeSuccessGate.evaluate(
      ActualMLXSmokeSuccessGate.Observation(
        reportAdvanced: result["advanced"] as? Bool ?? false,
        reportState: result["state"] as? String ?? "",
        finalPosition: Int64(result["final_position"] as? Int ?? 0),
        finalLifecycle: result["final_lifecycle"] as? String ?? "",
        boundRepresentationTokenCount: result["bound_representation_token_count"] as? Int ?? 0,
        executionStateStatus: executionState["status"] as? String ?? "",
        runtimeApplicationStatus: executionState["runtime_application_status"] as? String ?? "",
        settlementStates: settlementStates,
        pendingObligationsRead: pendingObligations != nil,
        pendingObligationCount: pendingObligations?.count ?? 0,
        carrierObjectsVerified: audit["carrier_all_objects_verify"] as? Bool ?? false,
        carrierDatabasePresent: databasePresent
      )
    )
    guard let recordedChecks = record["success_gate_checks"] as? [String: Bool],
          recordedChecks == recomputed.checks
    else { return false }
    return recomputed.passed
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

  private static let requiredSettlements = [
    "REAL-COLLECTION": "SETTLED",
    "REAL-SEGMENT": "SETTLED",
    "REAL-1": "SETTLED",
    "REAL-2": "SETTLED",
    "REAL-3": "SETTLED",
    "REAL-4": "SETTLED",
    "REAL-5": "SETTLED",
    "REAL-6": "SETTLED",
    "REAL-7": "SETTLED",
  ]

  private static func healthyPassRecord(manifestDigest: String) -> [String: Any] {
    var record: [String: Any] = [
      "schema_id": "ACTUAL-MLX-SMOKE-RECORD-V1",
      "manifest_sha256": manifestDigest,
      "terminal_state": "MLX_SMOKE_PASS",
      "run_count": 1,
      "result": [
        "advanced": true,
        "state": "ADVANCED",
        "final_position": 1,
        "final_lifecycle": "active",
        "bound_representation_token_count": 1,
      ],
      "audit": [
        "carrier_all_objects_verify": true,
        "current_settlement_states": requiredSettlements,
        "execution_state": [
          "status": "ADVANCED",
          "runtime_application_status": "APPLIED_SWIFT",
          "pending_obligations": [Any](),
        ],
      ],
    ]
    record["success_gate_checks"] = ActualMLXSmokeSuccessGate.evaluate(healthyObservation()).checks
    return record
  }

  func testActualMLXSmokeTerminalRecordUsesSeparatedGate() throws {
    let evidenceRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("actual-mlx-terminal-gate-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: evidenceRoot, withIntermediateDirectories: true)
    let database = evidenceRoot.appendingPathComponent("carrier.sqlite")
    try Data("carrier".utf8).write(to: database)

    let digest = String(repeating: "0", count: 64)
    XCTAssertTrue(Self.validTerminalRecord(
      Self.healthyPassRecord(manifestDigest: digest),
      manifestDigest: digest,
      evidenceRoot: evidenceRoot
    ))

    var advancedRecord = Self.healthyPassRecord(manifestDigest: digest)
    var audit = advancedRecord["audit"] as! [String: Any]
    var executionState = audit["execution_state"] as! [String: Any]
    executionState["status"] = "SETTLED"
    audit["execution_state"] = executionState
    advancedRecord["audit"] = audit
    XCTAssertFalse(Self.validTerminalRecord(
      advancedRecord,
      manifestDigest: digest,
      evidenceRoot: evidenceRoot
    ))

    var missingCheckRecord = Self.healthyPassRecord(manifestDigest: digest)
    var missingChecks = missingCheckRecord["success_gate_checks"] as! [String: Bool]
    missingChecks["carrier_database_present"] = nil
    missingCheckRecord["success_gate_checks"] = missingChecks
    XCTAssertFalse(Self.validTerminalRecord(
      missingCheckRecord,
      manifestDigest: digest,
      evidenceRoot: evidenceRoot
    ))

    var extraCheckRecord = Self.healthyPassRecord(manifestDigest: digest)
    var extraChecks = extraCheckRecord["success_gate_checks"] as! [String: Bool]
    extraChecks["unexpected_check"] = true
    extraCheckRecord["success_gate_checks"] = extraChecks
    XCTAssertFalse(Self.validTerminalRecord(
      extraCheckRecord,
      manifestDigest: digest,
      evidenceRoot: evidenceRoot
    ))

    var falseCheckRecord = Self.healthyPassRecord(manifestDigest: digest)
    var falseChecks = falseCheckRecord["success_gate_checks"] as! [String: Bool]
    falseChecks["execution_state_advanced"] = false
    falseCheckRecord["success_gate_checks"] = falseChecks
    XCTAssertFalse(Self.validTerminalRecord(
      falseCheckRecord,
      manifestDigest: digest,
      evidenceRoot: evidenceRoot
    ))

    var contradictoryAuditRecord = Self.healthyPassRecord(manifestDigest: digest)
    var contradictoryAudit = contradictoryAuditRecord["audit"] as! [String: Any]
    contradictoryAudit["carrier_all_objects_verify"] = false
    contradictoryAuditRecord["audit"] = contradictoryAudit
    XCTAssertFalse(Self.validTerminalRecord(
      contradictoryAuditRecord,
      manifestDigest: digest,
      evidenceRoot: evidenceRoot
    ))

    try FileManager.default.removeItem(at: database)
    try FileManager.default.createDirectory(at: database, withIntermediateDirectories: false)
    XCTAssertFalse(Self.validTerminalRecord(
      Self.healthyPassRecord(manifestDigest: digest),
      manifestDigest: digest,
      evidenceRoot: evidenceRoot
    ))
  }

  private static func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.2)
    }
    guard process.isRunning else { return false }
    kill(-process.processIdentifier, SIGKILL)
    kill(process.processIdentifier, SIGKILL)
    process.waitUntilExit()
    return true
  }

  private static func waitForExit(_ pid: pid_t, timeout: TimeInterval) -> SpawnedChildExit {
    var status: Int32 = 0
    let deadline = Date().addingTimeInterval(timeout)
    var waited = waitpid(pid, &status, WNOHANG)
    while waited == 0, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.2)
      waited = waitpid(pid, &status, WNOHANG)
    }
    var timedOut = false
    if waited == 0 {
      timedOut = true
      kill(-pid, SIGKILL)
      kill(pid, SIGKILL)
      waited = waitpid(pid, &status, 0)
    }
    precondition(waited == pid, "failed to reap smoke child \(pid)")
    let rawStatus = UInt32(bitPattern: status)
    if rawStatus & 0xff == 0 {
      return SpawnedChildExit(
        exitCode: Int32((rawStatus >> 8) & 0xff),
        signalNumber: nil,
        timedOut: timedOut
      )
    }
    return SpawnedChildExit(
      exitCode: 0,
      signalNumber: Int32(rawStatus & 0x7f),
      timedOut: timedOut
    )
  }

  private static func spawnIsolatedChild(
    executable: URL,
    environment: [String: String],
    stdout: URL?,
    stderr: URL?
  ) throws -> pid_t {
    var attributes: posix_spawnattr_t? = nil
    posix_spawnattr_init(&attributes)
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
    posix_spawnattr_setpgroup(&attributes, 0)
    var actions: posix_spawn_file_actions_t? = nil
    posix_spawn_file_actions_init(&actions)
    if let stdout {
      posix_spawn_file_actions_addopen(&actions, 1, stdout.path, O_WRONLY, 0o644)
    } else {
      posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0o644)
    }
    if let stderr {
      posix_spawn_file_actions_addopen(&actions, 2, stderr.path, O_WRONLY, 0o644)
    } else {
      posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0o644)
    }
    let executablePath = executable.path
    var arguments: [UnsafeMutablePointer<CChar>?] = [strdup(executablePath), nil]
    var childEnvironment = ProcessInfo.processInfo.environment
    for (key, value) in environment { childEnvironment[key] = value }
    var environmentC: [UnsafeMutablePointer<CChar>?] = childEnvironment.map {
      strdup("\($0.key)=\($0.value)")
    }
    environmentC.append(nil)
    defer {
      arguments.forEach { if let pointer = $0 { free(pointer) } }
      environmentC.forEach { if let pointer = $0 { free(pointer) } }
      posix_spawn_file_actions_destroy(&actions)
      posix_spawnattr_destroy(&attributes)
    }
    var pid: pid_t = 0
    let result = posix_spawn(&pid, executablePath, &actions, &attributes, &arguments, &environmentC)
    guard result == 0 else {
      throw ActualMLXSmokeError.manifestFieldMismatch("posix_spawn failed: \(result)")
    }
    return pid
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
    guard manifest["schema_id"] as? String == "ACTUAL-MLX-SMOKE-MANIFEST-V6",
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
          let childExpected = runner["child_source_sha256"] as? String,
          let binaryPath = runner["child_binary_path"] as? String,
          let binaryExpected = runner["child_binary_sha256"] as? String else {
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
    let binaryActual = try fileDigest(labRoot.appendingPathComponent(binaryPath))
    guard binaryActual == binaryExpected else {
      throw ActualMLXSmokeError.bindingMismatch("child_binary", expected: binaryExpected, actual: binaryActual)
    }

    guard let execution = manifest["execution"] as? [String: Any] else {
      throw invalidObject()
    }
    guard execution["mode"] as? String == "ONE_FRESH_ENTRY_ACTUAL_MLX_RUN",
          execution["model_calls_authorized"] as? Int == 1,
          execution["max_tokens_upper_bound"] as? Int == 32,
          execution["wall_clock_timeout_seconds"] as? Int == 1200,
          execution["parent_process_hard_kill_on_timeout"] as? Bool == true,
          execution["child_process_group_isolation"] as? Bool == true,
          execution["timeout_kills_process_group"] as? Bool == true,
          execution["process_tree_fault_injection_precheck"] as? Bool == true else {
      throw ActualMLXSmokeError.manifestFieldMismatch("bounded execution fields")
    }

    let evidence = try Self.evidenceBinding(manifest, labRoot: labRoot)
    guard let evidenceObject = manifest["evidence"] as? [String: Any],
          evidence.relativePath == "integrated-es-palace/mlx-smoke-v1/mlx-smoke-evidence-v6",
          evidenceObject["write_once"] as? Bool == true,
          evidenceObject["must_not_exist_before_authorized_run"] as? Bool == true,
          evidenceObject["terminal_record_create_mode"] as? String == "create_exclusive_no_overwrite" else {
      throw ActualMLXSmokeError.manifestFieldMismatch("write-once evidence fields")
    }

    guard let gate = manifest["authorization_gate"] as? [String: Any] else {
      throw invalidObject()
    }
    guard gate["marker_path"] as? String == "integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_V6_AUTHORIZED",
          gate["consumption_path"] as? String == "integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_V6_AUTHORIZATION_CONSUMED",
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
    "smoke_success_gate": "simigo2-experimental/Sources/SimiGo2Experimental/ActualMLXSmokeSuccessGate.swift",
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

  private static func parseSidecar(_ text: String) throws -> ActualMLXSmokeSidecar {
    let fields = text.split(whereSeparator: \.isWhitespace)
    guard fields.count == 2,
          fields[0].count == 64,
          fields[0].allSatisfy(\.isHexDigit)
    else {
      throw ActualMLXSmokeError.manifestFieldMismatch("sidecar format")
    }
    return ActualMLXSmokeSidecar(digest: fields[0].lowercased(), filename: String(fields[1]))
  }

  private static func evidenceBinding(
    _ manifest: [String: Any],
    labRoot: URL
  ) throws -> (relativePath: String, url: URL) {
    guard manifest["evidence_root"] == nil,
          let evidence = manifest["evidence"] as? [String: Any],
          let relativePath = evidence["root"] as? String,
          !relativePath.isEmpty
    else {
      throw ActualMLXSmokeError.manifestFieldMismatch("evidence.root")
    }
    return (relativePath, labRoot.appendingPathComponent(relativePath, isDirectory: true))
  }

  private static func terminalState(_ data: Data) throws -> String {
    let record = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return record?["terminal_state"] as? String ?? ""
  }

  private static func sha256(_ data: Data) -> String {
    data.withUnsafeBytes { buffer in
      SHA256.hash(data: buffer).map { String(format: "%02x", $0) }.joined()
    }
  }
}
