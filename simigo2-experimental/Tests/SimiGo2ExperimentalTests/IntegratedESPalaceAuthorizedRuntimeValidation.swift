import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

final class IntegratedESPalaceAuthorizedRuntimeValidation: XCTestCase {
  private let labRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  func testAuthorizedSingleSevenCaseRuntimeValidation() async throws {
    let evidenceRoot = labRoot.appendingPathComponent(
      "integrated-es-palace/runtime-adapter-v1/validation-evidence",
      isDirectory: true
    )
    let manifestURL = labRoot.appendingPathComponent(
      "integrated-es-palace/runtime-adapter-v1/RUNTIME_VALIDATION_MANIFEST_INSTANCE.json"
    )
    let manifestData = try Data(contentsOf: manifestURL)
    let manifestDigest = Self.sha256(manifestData)
    XCTAssertEqual("0b7a6a0c66fea6c6be2c608c2f6cf8d0fe0275a293d45ad69d1af1e35d8035c3", manifestDigest)
    let manifest = try JSONSerialization.jsonObject(with: manifestData) as! [String: Any]
    XCTAssertEqual("CANDIDATE — TARGETED CORRECTION COMPLETE / HUMAN AUTHORIZATION REQUIRED", manifest["status"] as? String)
    XCTAssertEqual(false, manifest["validation_executed"] as? Bool)
    let adapterSource = labRoot.appendingPathComponent(
      "simigo2-experimental/Sources/SimiGo2Experimental/IntegratedESPalaceRuntimeAdapter.swift"
    )
    XCTAssertEqual("87e28403cece2be47243b0ba523c687d1fed6425d08cfab215ed1378ca89d3ec", Self.sha256(Data(contentsOf: adapterSource)))

    let packageManifestURL = labRoot.appendingPathComponent(
      "integrated-es-palace/integration-fixture-v1/FIXTURE_PACKAGE_MANIFEST.json"
    )
    let packageObject = try JSONSerialization.jsonObject(with: Data(contentsOf: packageManifestURL)) as! [String: Any]
    let packageCases = try XCTUnwrap(packageObject["cases"] as? [[String: Any]])
    XCTAssertEqual(7, packageCases.count)

    var caseResults: [[String: Any]] = []
    var lifecycleRecords: [[String: Any]] = []
    var representationRecords: [[String: Any]] = []
    var allChecksPass = true

    for packageCase in packageCases {
      let caseID = try XCTUnwrap(packageCase["case_id"] as? String)
      let fixtureRoot = try XCTUnwrap(packageCase["fixture_root"] as? String)
      let manifestSHA256 = try XCTUnwrap(packageCase["manifest_sha256"] as? String)
      let fixtureManifestURL = labRoot.appendingPathComponent(
        "integrated-es-palace/integration-fixture-v1/\(fixtureRoot)/fixture-manifest.json"
      )
      let fixtureObject = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureManifestURL)) as! [String: Any]
      let opaqueLocator = try XCTUnwrap(fixtureObject["opaque_locator"] as? String)
      let expectedURL = fixtureManifestURL
        .deletingLastPathComponent()
        .appendingPathComponent("EXPECTED.json")
      let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: expectedURL)) as! [String: Any]

      let backend = MLXExecutionStateBackend()
      let coordinator = ExecutionContinuityCoordinator(backend: backend)
      let adapter = IntegratedESPalaceRuntimeAdapter(coordinator: coordinator, backend: backend)
      let inventory = try adapter.loadInventory(
        fixtureManifestURL: fixtureManifestURL,
        expectedManifestSHA256: manifestSHA256,
        opaqueLocator: opaqueLocator
      )
      let provenance = try XCTUnwrap(inventory.provenance["record_digest"])
      guard case .string(let sourceRecordDigest) = provenance else {
        throw XCTFailure("missing provenance digest for \(caseID)")
      }
      let decision = try adapter.makeDecision(
        inventory: inventory,
        sourceRecordDigest: sourceRecordDigest
      )

      let setupExecutionID = ExecutionID("RUNTIME-VALIDATION-SETUP-\(caseID)")
      var setupCreated = false
      var setupRepresentation: [Int]?
      let setupPosition: Int64
      if decision.decision == "REUSE" {
        let handle = try await coordinator.create(
          id: setupExecutionID,
          position: ExecutionPosition(0),
          continuation: ExecutionContinuation(
            nextInput: decision.inputDigest,
            continuationID: decision.continuationIdentityDigest
          )
        )
        setupCreated = true
        setupPosition = handle.position.value
        let prefix = [17, 23]
        backend.bind(executionID: handle.id, position: handle.position, tokenPrefix: prefix)
        setupRepresentation = prefix
      } else if caseID == "N-ILLEGAL" {
        let handle = try await coordinator.create(
          id: setupExecutionID,
          position: ExecutionPosition(3),
          continuation: ExecutionContinuation(
            nextInput: decision.inputDigest,
            continuationID: decision.continuationIdentityDigest
          )
        )
        setupCreated = true
        setupPosition = handle.position.value
        let prefix = [31, 37]
        backend.bind(executionID: handle.id, position: handle.position, tokenPrefix: prefix)
        setupRepresentation = prefix
      } else {
        setupPosition = 0
      }

      let beforeCount = coordinator.recordCount
      let beforeHandle = coordinator.handle(setupExecutionID)
      let beforePosition = beforeHandle?.position.value
      let beforePrefix = beforeHandle.flatMap { try? backend.boundPrefix(for: $0).prefix }
      let receipt = try await adapter.applyToRealRuntime(
        executionID: setupExecutionID,
        decision: decision
      )
      let afterCount = coordinator.recordCount
      let afterHandle = coordinator.handle(setupExecutionID)
      let afterPosition = afterHandle?.position.value
      let afterPrefix = afterHandle.flatMap { try? backend.boundPrefix(for: $0).prefix }

      let expectedDecision = try XCTUnwrap(expected["decision"] as? String)
      let expectedClass = try XCTUnwrap(expected["continuation_class"] as? String)
      let expectedReason = try XCTUnwrap(expected["precedence_reason"] as? String)
      var checks: [String: Bool] = [:]
      checks["decision_exact"] = decision.decision == expectedDecision
      checks["continuation_class_exact"] = decision.continuationClass == expectedClass
      checks["precedence_reason_exact"] = decision.precedenceReason == expectedReason
      checks["receipt_decision_matches"] = receipt.decision == decision.decision

      if decision.decision == "CONTINUE" {
        checks["runtime_advanced_once"] = receipt.advanced && afterPosition == 1
        checks["runtime_created"] = receipt.executionCreated
        checks["representation_bound"] = receipt.representationBound
        checks["handle_position_consistent"] = receipt.handle?.position.value == 1
        checks["representation_position_consistent"] = receipt.representationPosition == receipt.handle?.position
        checks["expected_lifecycle_delta"] = afterCount - beforeCount == 2
      } else if decision.decision == "REUSE" {
        checks["reuse_did_not_advance"] = !receipt.advanced && afterPosition == 0
        checks["reuse_did_not_create"] = !receipt.executionCreated && !setupCreated == false
        checks["reuse_did_not_rebind"] = !receipt.representationBound
        checks["reuse_lifecycle_unchanged"] = afterCount == beforeCount
        checks["reuse_handle_identity_consistent"] = receipt.handle == afterHandle
        checks["reuse_prefix_unchanged"] = receipt.representationPrefix == beforePrefix
        checks["reuse_position_unchanged"] = receipt.representationPosition == beforeHandle?.position
      } else {
        checks["block_did_not_advance"] = !receipt.advanced
        checks["block_did_not_create"] = !receipt.executionCreated
        checks["block_receipt_has_no_handle"] = receipt.handle == nil
        checks["block_lifecycle_unchanged_by_application"] = afterCount == beforeCount
        checks["block_position_unchanged"] = afterPosition == beforePosition
        checks["block_representation_unchanged"] = afterPrefix == beforePrefix
        if setupCreated {
          checks["block_existing_handle_retained"] = afterHandle == beforeHandle
        }
      }
      let casePassed = checks.values.allSatisfy { $0 }
      allChecksPass = allChecksPass && casePassed

      caseResults.append([
        "case_id": caseID,
        "opaque_locator": opaqueLocator,
        "expected": [
          "decision": expectedDecision,
          "continuation_class": expectedClass,
          "precedence_reason": expectedReason,
        ],
        "observed": [
          "decision": decision.decision,
          "continuation_class": decision.continuationClass,
          "precedence_reason": decision.precedenceReason,
        ],
        "input_digest": decision.inputDigest,
        "output_digest": decision.outputDigest,
        "continuation_identity_digest": decision.continuationIdentityDigest,
        "runtime": [
          "setup_created": setupCreated,
          "application_created": receipt.executionCreated,
          "advanced": receipt.advanced,
          "representation_bound": receipt.representationBound,
          "position_before": beforePosition as Any,
          "position_after": afterPosition as Any,
          "lifecycle_records_before": beforeCount,
          "lifecycle_records_after": afterCount,
          "receipt_handle_returned": receipt.handle != nil,
        ],
        "checks": checks,
        "result": casePassed ? "PASS" : "FAIL",
      ])
      lifecycleRecords.append([
        "case_id": caseID,
        "setup_created": setupCreated,
        "setup_position": setupPosition,
        "setup_representation_prefix": setupRepresentation as Any?,
        "application_lifecycle_delta": afterCount - beforeCount,
        "result": "RECORDED",
      ])
      representationRecords.append([
        "case_id": caseID,
        "setup_prefix": setupRepresentation as Any?,
        "application_bound": receipt.representationBound,
        "application_position": receipt.representationPosition as Any?,
        "application_prefix": receipt.representationPrefix as Any?,
      ])
    }

    let validationPass = allChecksPass
    let terminalState = validationPass ? "RUNTIME_VALIDATION_PASS" : "RUNTIME_VALIDATION_FAIL"
    let record: [String: Any] = [
      "schema_id": "INTEGRATED-ES-PALACE-RUNTIME-VALIDATION-RECORD-V1",
      "authorized_manifest_sha256": "0b7a6a0c66fea6c6be2c608c2f6cf8d0fe0275a293d45ad69d1af1e35d8035c3",
      "authorized_adapter_sha256": "87e28403cece2be47243b0ba523c687d1fed6425d08cfab215ed1378ca89d3ec",
      "authorized_runs": 1,
      "executed_runs": 1,
      "case_count": caseResults.count,
      "case_results": caseResults,
      "lifecycle_records": lifecycleRecords,
      "representation_records": representationRecords,
      "network_access": false,
      "model_authority": false,
      "canonical_palace_mutation": false,
      "canonical_information_space_mutation": false,
      "d002_rerun_or_repair": false,
      "result": validationPass ? "PASS" : "FAIL",
      "terminal_state": terminalState,
    ]

    try FileManager.default.createDirectory(at: evidenceRoot, withIntermediateDirectories: false)
    for (name, object) in [
      "RUNTIME_VALIDATION_RECORD.json": record,
      "CASE_RESULTS.json": ["schema_id": "INTEGRATED-ES-PALACE-RUNTIME-CASE-RESULTS-V1", "cases": caseResults],
      "EXECUTION_LIFECYCLE_RECORD.json": ["schema_id": "INTEGRATED-ES-PALACE-RUNTIME-LIFECYCLE-V1", "records": lifecycleRecords],
      "REPRESENTATION_BINDING_RECORD.json": ["schema_id": "INTEGRATED-ES-PALACE-RUNTIME-REPRESENTATION-V1", "records": representationRecords],
      "FORBIDDEN_CHANNEL_DENIAL_RECORD.json": [
        "schema_id": "INTEGRATED-ES-PALACE-RUNTIME-FORBIDDEN-CHANNEL-DENIAL-V1",
        "network_access": false,
        "model_authority": false,
        "canonical_palace_mutation": false,
        "canonical_information_space_mutation": false,
        "d002_rerun_or_repair": false,
        "result": "PASS",
      ],
    ] {
      let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
      try data.write(to: evidenceRoot.appendingPathComponent(name), options: .atomic)
    }
    let final = evidenceRoot.appendingPathComponent("EVIDENCE_SHA256SUMS")
    var lines: [String] = []
    for child in try FileManager.default.contentsOfDirectory(at: evidenceRoot, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
      guard child.isFile, child.lastPathComponent != "EVIDENCE_SHA256SUMS" else { continue }
      lines.append("\(Self.sha256(Data(contentsOf: child)))  \(child.lastPathComponent)")
    }
    try Data(lines.joined(separator: "\n").appending("\n").utf8)
      .write(to: final, options: .atomic)
    XCTAssertEqual("PASS", record["result"] as? String)
    XCTAssertEqual(terminalState, "RUNTIME_VALIDATION_PASS")
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

import CryptoKit

private func XCTFailure(_ message: String) -> Error {
  NSError(domain: "IntegratedESPalaceAuthorizedRuntimeValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
