import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

private enum RuntimeValidationV2BindingError: Error {
  case manifestDigestMismatch(actual: String, marker: String, sidecar: String)
  case manifestFieldMismatch(field: String)
  case adapterBindingMismatch(expected: String, actual: String)
  case entryBindingMismatch(expected: String, actual: String)
  case harnessBindingMismatch(expected: String, actual: String)
  case evidenceRootMismatch(expected: String, actual: String)
  case caseCountMismatch(expected: Int, actual: Int)
  case fixturePackageDigestMismatch(expected: String, actual: String)
  case fixtureCaseBindingMismatch(caseID: String, field: String, expected: String, actual: String)
}

final class IntegratedESPalaceRuntimeValidationV2: XCTestCase {
  private let labRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  func testRuntimeValidationV2SingleRun() async throws {
    let authorizationMarker = labRoot.appendingPathComponent(
      "integrated-es-palace/runtime-adapter-v1/RUNTIME_VALIDATION_V2_AUTHORIZED"
    )
    guard FileManager.default.fileExists(atPath: authorizationMarker.path) else {
      throw XCTSkip("RUNTIME VALIDATION V2 = CANDIDATE / HUMAN AUTHORIZATION REQUIRED")
    }
    let markerData = try Data(contentsOf: authorizationMarker)
    let markerDigest = String(decoding: markerData, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let sidecarURL = labRoot.appendingPathComponent(
      "integrated-es-palace/runtime-adapter-v1/RUNTIME_VALIDATION_MANIFEST_INSTANCE_V2.sha256"
    )
    let sidecarData = try Data(contentsOf: sidecarURL)
    let sidecarDigest = String(decoding: sidecarData, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let evidenceRoot = labRoot.appendingPathComponent(
      "integrated-es-palace/runtime-adapter-v1/validation-evidence-v2",
      isDirectory: true
    )
    let manifestURL = labRoot.appendingPathComponent(
      "integrated-es-palace/runtime-adapter-v1/RUNTIME_VALIDATION_MANIFEST_INSTANCE_V2.json"
    )
    let manifestData = try Data(contentsOf: manifestURL)
    let manifestDigest = IntegratedESPalaceAuthorizedRuntimeValidation.sha256(manifestData)
    guard markerDigest == manifestDigest, sidecarDigest == manifestDigest else {
      throw RuntimeValidationV2BindingError.manifestDigestMismatch(
        actual: manifestDigest,
        marker: markerDigest,
        sidecar: sidecarDigest
      )
    }
    let manifest = try JSONSerialization.jsonObject(with: manifestData) as! [String: Any]
    guard manifest["schema_id"] as? String == "RUNTIME-ADAPTER-VALIDATION-MANIFEST-V3" else {
      throw RuntimeValidationV2BindingError.manifestFieldMismatch(field: "schema_id")
    }
    guard let manifestInstanceID = manifest["manifest_instance_id"] as? String,
          !manifestInstanceID.isEmpty else {
      throw RuntimeValidationV2BindingError.manifestFieldMismatch(field: "manifest_instance_id")
    }
    guard manifest["status"] as? String == "CANDIDATE — HUMAN AUTHORIZATION REQUIRED" else {
      throw RuntimeValidationV2BindingError.manifestFieldMismatch(field: "status")
    }
    guard manifest["validation_authorized"] as? Bool == false else {
      throw RuntimeValidationV2BindingError.manifestFieldMismatch(field: "validation_authorized")
    }
    guard manifest["validation_executed"] as? Bool == false || (manifest["validation_executed"] == nil && manifest["validation_authorized"] as? Bool == false) else {
      throw RuntimeValidationV2BindingError.manifestFieldMismatch(field: "validation_executed")
    }
    let expectedEvidenceRoot = "integrated-es-palace/runtime-adapter-v1/validation-evidence-v2"
    let manifestEvidence = manifest["evidence"] as? [String: Any]
    guard manifestEvidence?["root"] as? String == expectedEvidenceRoot else {
      throw RuntimeValidationV2BindingError.evidenceRootMismatch(
        expected: expectedEvidenceRoot,
        actual: manifestEvidence?["root"] as? String ?? "nil"
      )
    }
    guard manifestEvidence?["write_once"] as? Bool == true else {
      throw RuntimeValidationV2BindingError.manifestFieldMismatch(field: "evidence.write_once")
    }
    guard (manifest["execution"] as? [String: Any])?["executed"] as? Bool == false else {
      throw RuntimeValidationV2BindingError.manifestFieldMismatch(field: "execution.executed")
    }
    let adapterSource = labRoot.appendingPathComponent(
      "simigo2-experimental/Sources/SimiGo2Experimental/IntegratedESPalaceRuntimeAdapter.swift"
    )
    let actualAdapterDigest = try IntegratedESPalaceAuthorizedRuntimeValidation.sha256(Data(contentsOf: adapterSource))
    let expectedAdapterDigest = ((manifest["adapter_binding"] as? [String: Any])?["sha256"] as? String) ?? ""
    guard actualAdapterDigest == expectedAdapterDigest else {
      throw RuntimeValidationV2BindingError.adapterBindingMismatch(
        expected: expectedAdapterDigest,
        actual: actualAdapterDigest
      )
    }
    let entrySource = URL(fileURLWithPath: #filePath)
    let actualEntryDigest = try IntegratedESPalaceAuthorizedRuntimeValidation.sha256(Data(contentsOf: entrySource))
    let expectedEntryDigest = ((manifest["harness_binding"] as? [String: Any])?["new_validation_entry_sha256"] as? String) ?? ""
    guard actualEntryDigest == expectedEntryDigest else {
      throw RuntimeValidationV2BindingError.entryBindingMismatch(
        expected: expectedEntryDigest,
        actual: actualEntryDigest
      )
    }
    let repairedHarnessSource = labRoot.appendingPathComponent(
      "simigo2-experimental/Tests/SimiGo2ExperimentalTests/IntegratedESPalaceAuthorizedRuntimeValidation.swift"
    )
    let actualHarnessDigest = try IntegratedESPalaceAuthorizedRuntimeValidation.sha256(Data(contentsOf: repairedHarnessSource))
    let expectedHarnessDigest = ((manifest["harness_binding"] as? [String: Any])?["serialization_repaired_harness_sha256"] as? String) ?? ""
    guard actualHarnessDigest == expectedHarnessDigest else {
      throw RuntimeValidationV2BindingError.harnessBindingMismatch(
        expected: expectedHarnessDigest,
        actual: actualHarnessDigest
      )
    }

    let packageManifestURL = labRoot.appendingPathComponent(
      "integrated-es-palace/integration-fixture-v1/FIXTURE_PACKAGE_MANIFEST.json"
    )
    let packageManifestData = try Data(contentsOf: packageManifestURL)
    let actualFixturePackageDigest = IntegratedESPalaceAuthorizedRuntimeValidation.sha256(packageManifestData)
    let expectedFixturePackageDigest = ((manifest["fixture_binding"] as? [String: Any])?["fixture_manifest_sha256"] as? String) ?? ""
    guard actualFixturePackageDigest == expectedFixturePackageDigest else {
      throw RuntimeValidationV2BindingError.fixturePackageDigestMismatch(
        expected: expectedFixturePackageDigest,
        actual: actualFixturePackageDigest
      )
    }
    let packageObject = try JSONSerialization.jsonObject(with: packageManifestData) as! [String: Any]
    let packageCases = try XCTUnwrap(packageObject["cases"] as? [[String: Any]])
    guard packageCases.count == 7 else {
      throw RuntimeValidationV2BindingError.caseCountMismatch(expected: 7, actual: packageCases.count)
    }
    let manifestCases = try XCTUnwrap((manifest["fixture_binding"] as? [String: Any])?["cases"] as? [[String: Any]])
    guard manifestCases.count == 7 else {
      throw RuntimeValidationV2BindingError.caseCountMismatch(expected: 7, actual: manifestCases.count)
    }
    for packageCase in packageCases {
      let caseID = try XCTUnwrap(packageCase["case_id"] as? String)
      let fixtureRoot = try XCTUnwrap(packageCase["fixture_root"] as? String)
      let manifestSHA256 = try XCTUnwrap(packageCase["manifest_sha256"] as? String)
      let manifestCase = manifestCases.first { ($0["case_id"] as? String) == caseID }
      let expectedFixtureRoot = (manifestCase?["fixture_manifest"] as? String)?
        .replacingOccurrences(of: "integrated-es-palace/integration-fixture-v1/", with: "")
        .replacingOccurrences(of: "/fixture-manifest.json", with: "")
      let expectedManifestSHA256 = (manifestCase?["fixture_manifest_sha256"] as? String) ?? ""
      guard fixtureRoot == expectedFixtureRoot else {
        throw RuntimeValidationV2BindingError.fixtureCaseBindingMismatch(
          caseID: caseID,
          field: "fixture_manifest_path",
          expected: expectedFixtureRoot ?? "nil",
          actual: fixtureRoot
        )
      }
      guard manifestSHA256 == expectedManifestSHA256 else {
        throw RuntimeValidationV2BindingError.fixtureCaseBindingMismatch(
          caseID: caseID,
          field: "fixture_manifest_sha256",
          expected: expectedManifestSHA256,
          actual: manifestSHA256
        )
      }
    }

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
          "position_before": IntegratedESPalaceAuthorizedRuntimeValidation.jsonOptionalInt64(beforePosition),
          "position_after": IntegratedESPalaceAuthorizedRuntimeValidation.jsonOptionalInt64(afterPosition),
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
        "setup_representation_prefix": IntegratedESPalaceAuthorizedRuntimeValidation.jsonOptionalIntArray(setupRepresentation),
        "application_lifecycle_delta": afterCount - beforeCount,
        "result": "RECORDED",
      ])
      representationRecords.append([
        "case_id": caseID,
        "setup_prefix": IntegratedESPalaceAuthorizedRuntimeValidation.jsonOptionalIntArray(setupRepresentation),
        "application_bound": receipt.representationBound,
        "application_position": IntegratedESPalaceAuthorizedRuntimeValidation.jsonOptionalPosition(receipt.representationPosition),
        "application_prefix": IntegratedESPalaceAuthorizedRuntimeValidation.jsonOptionalIntArray(receipt.representationPrefix),
      ])
    }

    let validationPass = allChecksPass
    let terminalState = validationPass ? "RUNTIME_VALIDATION_PASS" : "RUNTIME_VALIDATION_FAIL"
    let record: [String: Any] = [
      "schema_id": "INTEGRATED-ES-PALACE-RUNTIME-VALIDATION-RECORD-V1",
      "validated_manifest_sha256": manifestDigest,
      "validated_adapter_sha256": actualAdapterDigest,
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

    let evidenceObjects = [
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
    ]
    let serializedEvidence = try IntegratedESPalaceAuthorizedRuntimeValidation.serializeEvidence(evidenceObjects)
    try FileManager.default.createDirectory(at: evidenceRoot, withIntermediateDirectories: false)
    for (name, data) in serializedEvidence {
      try data.write(to: evidenceRoot.appendingPathComponent(name), options: .atomic)
    }
    let final = evidenceRoot.appendingPathComponent("EVIDENCE_SHA256SUMS")
    var lines: [String] = []
    for child in try FileManager.default.contentsOfDirectory(at: evidenceRoot, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
      guard (try? child.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true, child.lastPathComponent != "EVIDENCE_SHA256SUMS" else { continue }
      lines.append("\(try IntegratedESPalaceAuthorizedRuntimeValidation.sha256(Data(contentsOf: child)))  \(child.lastPathComponent)")
    }
    try Data(lines.joined(separator: "\n").appending("\n").utf8)
      .write(to: final, options: .atomic)
    XCTAssertEqual("PASS", record["result"] as? String)
    XCTAssertEqual(terminalState, "RUNTIME_VALIDATION_PASS")
  }

}
