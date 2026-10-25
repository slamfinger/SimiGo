import Foundation
import CryptoKit
import CarrierInterface
import CarrierSQLite

struct FixtureSpec {
    let role: String
    let expectedC1: String
    let expectedC2: String
    let deficiency: String
    let makeEvents: (String) -> [EventPlan]
}

struct EventPlan {
    let slot: String
    let kind: String
    var content: String
    var targetEventID: String?
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func jsonEscape(_ value: String) -> String {
    var escaped = value
    escaped = escaped
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\t", with: "\\t")
    return escaped
}

func payload(slot: String, content: String, target: String? = nil) -> Data {
    let targetPart: String
    if let target {
        targetPart = ",\"target_slot\":\"\(jsonEscape(target))\""
    } else {
        targetPart = ""
    }
    let text = "{\"schema\":\"es-csp/e0-slot-v1\",\"slot\":\"\(jsonEscape(slot))\","
        + "\"content\":\"\(jsonEscape(content))\"\(targetPart)}"
    return Data(text.utf8)
}

func targetSlot(in data: Data) throws -> String? {
    let object = try JSONSerialization.jsonObject(with: data, options: [])
    guard let dictionary = object as? [String: Any] else {
        throw NSError(domain: "ESCSPPrep", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "payload is not an object"])
    }
    return dictionary["target_slot"] as? String
}

func slotName(in data: Data) throws -> String {
    let object = try JSONSerialization.jsonObject(with: data, options: [])
    guard let dictionary = object as? [String: Any],
          let slot = dictionary["slot"] as? String else {
        throw NSError(domain: "ESCSPPrep", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "payload has no slot"])
    }
    return slot
}

func runGit(_ arguments: [String], workingDirectory: URL) throws -> (exit: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = workingDirectory
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    let outData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let outText = String(data: outData, encoding: .utf8) ?? ""
    let errorText = String(data: errorData, encoding: .utf8) ?? ""
    let text = outText + errorText
    return (process.terminationStatus, text)
}

func jsonDictionary(_ value: Any, sorted: Bool = true) throws -> Data {
    var options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    if !sorted { options = [.prettyPrinted, .withoutEscapingSlashes] }
    return try JSONSerialization.data(withJSONObject: value, options: options)
}

func writeJSON(_ value: Any, to url: URL) throws -> Data {
    let data = try jsonDictionary(value)
    try data.write(to: url, options: [.atomic])
    return data
}

func operationSummary(_ record: UAOperationRecord) -> [String: Any] {
    [
        "operation_id": record.operationID,
        "actor_id": record.actorID,
        "carrier_id": record.carrierID ?? "",
        "subject_id": record.subjectID ?? "",
        "kind": record.kind,
        "base_revision": record.baseRevision as Any,
        "observed_revision": record.observedRevision as Any,
        "outcome": record.outcome.rawValue,
        "from_version": record.fromVersion ?? "",
        "resulting_version": record.resultingVersion ?? "",
        "recorded_at": ISO8601DateFormatter().string(from: record.recordedAt)
    ]
}

func mappingSummary(_ mapping: UAMappingRecord) -> [String: Any] {
    [
        "mapping_id": mapping.mappingID,
        "information_id": mapping.informationID,
        "carrier_id": mapping.carrierID,
        "record_id": mapping.recordID,
        "representation_id": mapping.representationID ?? "",
        "actor_id": mapping.actorID,
        "operation_id": mapping.operationID,
        "from_version": mapping.fromVersion ?? "",
        "mapped_at": ISO8601DateFormatter().string(from: mapping.mappedAt)
    ]
}

func prepareFixture(
    spec: FixtureSpec,
    packageRoot: URL,
    externalRoot: URL
) async throws -> [String: Any] {
    let instanceID = UUID().uuidString
    let fixtureRoot = externalRoot.appendingPathComponent("data", isDirectory: true)
        .appendingPathComponent(instanceID, isDirectory: true)
    let carrierRoot = fixtureRoot.appendingPathComponent("carrier-root", isDirectory: true)
    try FileManager.default.createDirectory(at: carrierRoot, withIntermediateDirectories: true)

    // Seal control-side role and expectations before any reconstruction can
    // exist. These are never passed to reconstruction.
    let control: [String: Any] = [
        "schema_version": "es-csp/control-manifest-v1",
        "fixture_instance_id": instanceID,
        "fixture_role": spec.role,
        "expected_c1": spec.expectedC1,
        "expected_c2": spec.expectedC2,
        "deficiency": spec.deficiency,
        "sealed_at": ISO8601DateFormatter().string(from: Date())
    ]
    _ = try writeJSON(control, to: externalRoot
        .appendingPathComponent("control", isDirectory: true)
        .appendingPathComponent("\(instanceID).control.json"))

    let reconstructionInput: [String: Any] = [
        "schema_version": "es-csp/reconstruction-input-v1",
        "source_baseline_identifier": "39c1031",
        "run_label": "ES-CSP-RUN-01",
        "opaque_fixture_instance_id": instanceID,
        "isolated_carrier_data_root_path": carrierRoot.path,
        "reconstruction_manifest_schema_version": "es-csp/reconstruction-manifest-v1"
    ]
    _ = try writeJSON(reconstructionInput, to: externalRoot
        .appendingPathComponent("reconstruction-input", isDirectory: true)
        .appendingPathComponent("\(instanceID).reconstruction-input.json"))

    let factory = SQLiteCarrierFactory(rootURL: carrierRoot)
    let bundle = try factory.make()

    let createOperation = UUID().uuidString
    let created = try await bundle.operations.createCarrier(
        kind: .session,
        locatorScheme: nil,
        locatorValue: nil,
        actorID: "es-csp-fixture-preparer",
        operationID: createOperation,
        explicitCarrierID: nil
    )
    guard created.outcome == .applied else {
        throw NSError(domain: "ESCSPPrep", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "carrier creation was not APPLIED"])
    }
    let carrier = created.carrier
    let stableSessionLocator = "uasession:\(carrier.carrierID)"

    var plans: [EventPlan] = spec.makeEvents("")
    var eventRecords: [[String: Any]] = []
    var mappingRecords: [[String: Any]] = []

    // Materialize all non-pointer slots first so exact event identities can be
    // referenced without guessing. Pointers are appended last.
    for index in plans.indices where !plans[index].slot.hasPrefix("P1") {
        let plan = plans[index]
        let eventOperation = UUID().uuidString
        let clientRef = UUID().uuidString
        let payloadData = payload(slot: plan.slot, content: plan.content, target: plan.targetEventID)
        let appended = try await bundle.operations.appendSessionEvent(
            carrierID: carrier.carrierID,
            kind: plan.kind,
            payload: payloadData,
            occurredAt: Date(),
            actorID: "es-csp-fixture-preparer",
            operationID: eventOperation,
            clientRef: clientRef
        )
        guard appended.outcome == .applied else {
            throw NSError(domain: "ESCSPPrep", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "event \(plan.slot) was not APPLIED"])
        }
        let revisionAfterEvent = appended.carrierRevision
        let infoID = CarrierInformationID(rawValue: UUID().uuidString)
        let mappingOperation = UUID().uuidString
        let mapping = try await bundle.operations.recordMapping(
            informationID: infoID,
            carrierID: carrier.carrierID,
            recordID: appended.event.eventID.rawValue,
            representationID: nil,
            fromVersion: String(revisionAfterEvent),
            actorID: "es-csp-fixture-preparer",
            operationID: mappingOperation
        )
        eventRecords.append([
            "slot": plan.slot,
            "event_id": appended.event.eventID.rawValue,
            "session_id": appended.event.sessionID.rawValue,
            "sequence": appended.event.sequence,
            "record_kind": appended.event.kind,
            "payload_sha256": sha256Hex(payloadData),
            "payload_byte_count": payloadData.count,
            "payload_utf8": String(data: payloadData, encoding: .utf8) ?? "",
            "information_id": infoID.rawValue,
            "mapping_id": mapping.mappingID,
            "event_operation_id": eventOperation,
            "event_client_ref": clientRef,
            "event_outcome": appended.outcome.rawValue,
            "carrier_revision_after_event": revisionAfterEvent,
            "mapping_operation_id": mappingOperation,
            "carrier_revision_after_mapping": Int(mapping.fromVersion ?? "0") ?? 0
        ])
    }

    // Materialize pointer plans last. target_slot remains the registered
    // scalar slot label required by R01; no runtime event ID is inserted.
    for index in plans.indices where plans[index].slot.hasPrefix("P1") {
        let plan = plans[index]
        let eventOperation = UUID().uuidString
        let clientRef = UUID().uuidString
        let payloadData = payload(slot: plan.slot, content: plan.content, target: plan.targetEventID)
        let appended = try await bundle.operations.appendSessionEvent(
            carrierID: carrier.carrierID,
            kind: plan.kind,
            payload: payloadData,
            occurredAt: Date(),
            actorID: "es-csp-fixture-preparer",
            operationID: eventOperation,
            clientRef: clientRef
        )
        guard appended.outcome == .applied else {
            throw NSError(domain: "ESCSPPrep", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "pointer \(plan.slot) was not APPLIED"])
        }
        let revisionAfterEvent = appended.carrierRevision
        let infoID = CarrierInformationID(rawValue: UUID().uuidString)
        let mappingOperation = UUID().uuidString
        let mapping = try await bundle.operations.recordMapping(
            informationID: infoID,
            carrierID: carrier.carrierID,
            recordID: appended.event.eventID.rawValue,
            representationID: nil,
            fromVersion: String(revisionAfterEvent),
            actorID: "es-csp-fixture-preparer",
            operationID: mappingOperation
        )
        eventRecords.append([
            "slot": plan.slot,
            "event_id": appended.event.eventID.rawValue,
            "session_id": appended.event.sessionID.rawValue,
            "sequence": appended.event.sequence,
            "record_kind": appended.event.kind,
            "payload_sha256": sha256Hex(payloadData),
            "payload_byte_count": payloadData.count,
            "payload_utf8": String(data: payloadData, encoding: .utf8) ?? "",
            "information_id": infoID.rawValue,
            "mapping_id": mapping.mappingID,
            "event_operation_id": eventOperation,
            "event_client_ref": clientRef,
            "event_outcome": appended.outcome.rawValue,
            "carrier_revision_after_event": revisionAfterEvent,
            "mapping_operation_id": mappingOperation,
            "carrier_revision_after_mapping": Int(mapping.fromVersion ?? "0") ?? 0
        ])
    }

    // Stable-address snapshot, not search.
    let snapshot = try await bundle.operations.consistentSnapshot(carrierID: carrier.carrierID)
    let ledger = try await bundle.operations.operationLedger()
    let mappings = try await bundle.operations.mappings()
    let integrity = try await bundle.integrity.integrityReport()
    let finalCarrier = try await bundle.operations.carrier(carrierID: carrier.carrierID)
    let fingerprint = try await bundle.operations.authorityFingerprint()
    let dangling = try await bundle.operations.danglingProvenanceCount()

    // G-R checks against actual records.
    let allowedKinds: Set<String> = {
        if spec.role == "N-B" {
            return ["RAW", "EVIDENCE_LINK", "JUDGMENT", "RESULT", "NEXT_ACTION"]
        }
        return ["RAW", "EVIDENCE_LINK", "JUDGMENT", "RESULT", "NEXT_ACTION"]
    }()
    let actualKinds = Set(eventRecords.compactMap { $0["record_kind"] as? String })
    let mappedEventIDs = Set(mappings.map { $0.recordID })
    let actualEventIDs = Set(eventRecords.compactMap { $0["event_id"] as? String })
    let pointerRecords = eventRecords.filter { ($0["record_kind"] as? String) == "NEXT_ACTION" }
    var pointerTargets: [String] = []
    for record in pointerRecords {
        if let text = record["payload_utf8"] as? String,
           let data = text.data(using: .utf8),
           let target = try targetSlot(in: data) {
            pointerTargets.append(target)
        }
    }
    let grAllowedKinds = actualKinds.isSubset(of: allowedKinds)
    let grMappingsComplete = mappedEventIDs.isSuperset(of: actualEventIDs)
    let grNoRelations = !ledger.contains { $0.kind.lowercased().contains("relation") }
    let grScalarPointers = pointerRecords.allSatisfy { record in
        guard let text = record["payload_utf8"] as? String,
              let data = text.data(using: .utf8) else { return false }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let target = object["target_slot"] else { return false }
        return target is String
    }
    let grPositivePointer = spec.role != "P-POS" || (pointerTargets == ["B1"])
    let grNegativePointer = spec.role != "N-B" || (Set(pointerTargets) == ["B1", "B2"] && pointerTargets.count == 2)
    let grProvenance = !ledger.isEmpty && ledger.allSatisfy { !$0.actorID.isEmpty && !$0.operationID.isEmpty }
    let grRevision = eventRecords.allSatisfy { ($0["carrier_revision_after_event"] as? Int ?? 0) > 0 }
    let gr = grAllowedKinds && grMappingsComplete && grNoRelations && grScalarPointers
        && grPositivePointer && grNegativePointer && grProvenance && grRevision

    // G-C runtime checks.
    let gitAncestor = try runGit(["merge-base", "--is-ancestor", "39c1031", "HEAD"], workingDirectory: packageRoot)
    let gitDesignDiff = try runGit(["diff", "--exit-code", "39c1031", "HEAD", "--", "trackD-memory"], workingDirectory: packageRoot)
    let gitWorkingDiff = try runGit(["diff", "--exit-code", "--", "trackD-memory"], workingDirectory: packageRoot)
    let gitStatus = try runGit(["status", "--porcelain", "--", "trackD-memory"], workingDirectory: packageRoot)
    let gc1 = gitAncestor.exit == 0 && gitDesignDiff.exit == 0 && gitWorkingDiff.exit == 0
        && gitStatus.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let gc2 = carrier.carrierID.isEmpty == false
    let gc3 = actualKinds.contains("NEXT_ACTION")
    let gc4 = mappings.allSatisfy { !$0.actorID.isEmpty && !$0.operationID.isEmpty && !$0.recordID.isEmpty }
    let gc5 = !ledger.isEmpty && !mappings.isEmpty
    let gc6 = snapshot.events.count == eventRecords.count
    let gc7 = ledger.allSatisfy { !$0.actorID.isEmpty && !$0.operationID.isEmpty }
        && snapshot.events.allSatisfy { !$0.provenance.producedBy.isEmpty }
    let gc8 = (finalCarrier?.revision ?? 0) > 0 && mappings.allSatisfy { !( $0.fromVersion ?? "").isEmpty }
    let gc9 = dangling == 0
    let gc = gc1 && gc2 && gc3 && gc4 && gc5 && gc6 && gc7 && gc8 && gc9

    var checks: [String: Any] = [
        "gr_allowed_record_kinds": grAllowedKinds,
        "gr_every_event_has_cc5_mapping": grMappingsComplete,
        "gr_no_carrier_relation_operation": grNoRelations,
        "gr_target_slot_scalar_only": grScalarPointers,
        "gr_positive_pointer_exactly_b1": grPositivePointer,
        "gr_nb_pointer_set_p1a_b1_p1b_b2": grNegativePointer,
        "gr_provenance_present": grProvenance,
        "gr_revision_present": grRevision,
        "gr_result": gr ? "PASS" : "FAIL",
        "gc1_carrier_source_baseline": gc1,
        "gc2_accepted_factory_composition": gc2,
        "gc3_session_kinds_including_next_action": gc3,
        "gc4_cc5_mapping_provenance": gc4,
        "gc5_durable_mapping_and_ledger": gc5,
        "gc6_stable_addressing_without_search": gc6,
        "gc7_operation_and_event_provenance": gc7,
        "gc8_revision_observability": gc8,
        "gc9_integrity_and_provenance_absence": gc9,
        "gc_result": gc ? "PASS" : "FAIL",
        "gc1_git_ancestor_exit": Int(gitAncestor.exit),
        "gc1_git_design_diff_exit": Int(gitDesignDiff.exit),
        "gc1_git_working_diff_exit": Int(gitWorkingDiff.exit),
        "gc1_git_status_output": gitStatus.output,
        "authority_fingerprint_sha256": fingerprint,
        "dangling_provenance_count": dangling
    ]

    var manifest: [String: Any] = [
        "schema_version": "es-csp/fixture-manifest-v1",
        "package_baseline": "39c1031",
        "design_baseline": "Probe v0.2 / FROZEN",
        "run_label": "ES-CSP-RUN-01",
        "fixture_instance_id": instanceID,
        "fixture_role": spec.role,
        "role_mapping_location": "CONTROL-SIDE ONLY / WITHHELD FROM RECONSTRUCTION",
        "reconstruction_entry_point": stableSessionLocator,
        "canonicalization": "UTF-8; exact payload bytes; SHA-256 checksums",
        "carrier_label": "pre-registered logical label only",
        "actual_carrier_identity": carrier.carrierID,
        "actual_session_identity": carrier.carrierID,
        "carrier_kind": carrier.kind.rawValue,
        "carrier_revision": finalCarrier?.revision ?? carrier.revision,
        "carrier_created_at": ISO8601DateFormatter().string(from: carrier.createdAt),
        "carrier_created_by": carrier.createdBy,
        "event_records": eventRecords,
        "all_operation_records": ledger.map(operationSummary),
        "all_mapping_records": mappings.map(mappingSummary),
        "snapshot_event_count": snapshot.events.count,
        "snapshot_read_version": snapshot.readVersion,
        "integrity_issue_count": integrity.issues.count,
        "integrity_issues": integrity.issues.map { $0.detail },
        "checks": checks,
        "independence_declaration": "This fixture was materialized in its own isolated carrier root from its own pre-registered definition; it was not derived by runtime mutation of another materialized fixture."
    ]
    checks["pointer_targets"] = pointerTargets
    manifest["checks"] = checks

    let manifestData = try writeJSON(manifest, to: externalRoot
        .appendingPathComponent("manifests", isDirectory: true)
        .appendingPathComponent("\(instanceID).fixture-manifest.json"))
    _ = manifestData

    return [
        "fixture_instance_id": instanceID,
        "fixture_role": spec.role,
        "manifest_sha256": sha256Hex(manifestData),
        "stable_session_locator": stableSessionLocator,
        "gr_result": gr ? "PASS" : "FAIL",
        "gc_result": gc ? "PASS" : "FAIL"
    ]
}

@main struct Program {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 4 else {
            FileHandle.standardError.write(Data("usage: ESCSPPrep <SimiGo-Lab-package-root> <external-root> <manifests-dir>\n".utf8))
            exit(2)
        }
        let packageRoot = URL(fileURLWithPath: arguments[1], isDirectory: true)
        let externalRoot = URL(fileURLWithPath: arguments[2], isDirectory: true)
        let manifestsDir = URL(fileURLWithPath: arguments[3], isDirectory: true)
        try FileManager.default.createDirectory(at: manifestsDir, withIntermediateDirectories: true)

        let specs: [FixtureSpec] = [
            FixtureSpec(
                role: "P-POS",
                expectedC1: "PASS",
                expectedC2: "CONTINUE_CERTAIN",
                deficiency: "none",
                makeEvents: { _ in
                    [
                        EventPlan(slot: "O1", kind: "RAW", content: "Continue the bounded research note without adding new claims.", targetEventID: nil),
                        EventPlan(slot: "D1", kind: "JUDGMENT", content: "The bounded note is ready for boundary-registered continuation.", targetEventID: nil),
                        EventPlan(slot: "A1", kind: "RESULT", content: "Artifact reference: bounded-note-v1.", targetEventID: nil),
                        EventPlan(slot: "B1", kind: "RESULT", content: "Boundary state: prior work complete; one registered continuation remains.", targetEventID: nil),
                        EventPlan(slot: "I1", kind: "EVIDENCE_LINK", content: "A1", targetEventID: nil),
                        EventPlan(slot: "P1", kind: "NEXT_ACTION", content: "Continue at the registered boundary.", targetEventID: "B1")
                    ]
                }
            ),
            FixtureSpec(
                role: "N-A",
                expectedC1: "FAIL",
                expectedC2: "BLOCK_INSUFFICIENT",
                deficiency: "required input reference does not resolve",
                makeEvents: { _ in
                    [
                        EventPlan(slot: "O1", kind: "RAW", content: "Continue the bounded research note without adding new claims.", targetEventID: nil),
                        EventPlan(slot: "D1", kind: "JUDGMENT", content: "The bounded note is ready for boundary-registered continuation.", targetEventID: nil),
                        EventPlan(slot: "A1", kind: "RESULT", content: "Artifact reference: bounded-note-v1.", targetEventID: nil),
                        EventPlan(slot: "B1", kind: "RESULT", content: "Boundary state: prior work complete; one registered continuation remains.", targetEventID: nil),
                        EventPlan(slot: "I1", kind: "EVIDENCE_LINK", content: "CSP-MISSING-SLOT-00000000", targetEventID: nil),
                        EventPlan(slot: "P1", kind: "NEXT_ACTION", content: "Continue at the registered boundary.", targetEventID: "B1")
                    ]
                }
            ),
            FixtureSpec(
                role: "N-B",
                expectedC1: "PASS",
                expectedC2: "BLOCK_INSUFFICIENT",
                deficiency: "continuation pointer set is ambiguous with cardinality two",
                makeEvents: { _ in
                    [
                        EventPlan(slot: "O1", kind: "RAW", content: "Continue the bounded research note without adding new claims.", targetEventID: nil),
                        EventPlan(slot: "D1", kind: "JUDGMENT", content: "The bounded note is ready for boundary-registered continuation.", targetEventID: nil),
                        EventPlan(slot: "A1", kind: "RESULT", content: "Artifact reference: bounded-note-v1.", targetEventID: nil),
                        EventPlan(slot: "B1", kind: "RESULT", content: "Boundary state candidate one.", targetEventID: nil),
                        EventPlan(slot: "B2", kind: "RESULT", content: "Boundary state candidate two.", targetEventID: nil),
                        EventPlan(slot: "I1", kind: "EVIDENCE_LINK", content: "A1", targetEventID: nil),
                        EventPlan(slot: "P1a", kind: "NEXT_ACTION", content: "Continue at the registered boundary.", targetEventID: "B1"),
                        EventPlan(slot: "P1b", kind: "NEXT_ACTION", content: "Continue at the registered boundary.", targetEventID: "B2")
                    ]
                }
            )
        ]

        var summaries: [[String: Any]] = []
        for spec in specs {
            let summary = try await prepareFixture(
                spec: spec,
                packageRoot: packageRoot,
                externalRoot: externalRoot
            )
            summaries.append(summary)
        }

        let result: [String: Any] = [
            "schema_version": "es-csp/fixture-preparation-result-v1",
            "run_label": "ES-CSP-RUN-01",
            "package_baseline": "39c1031",
            "stage": "S1",
            "execution_status": "NOT RUN / NOT AUTHORIZED",
            "fixtures": summaries
        ]
        let data = try writeJSON(result, to: externalRoot.appendingPathComponent("fixture-preparation-result.json"))
        try data.write(to: manifestsDir.appendingPathComponent("fixture-preparation-result.json"), options: [.atomic])
        for summary in summaries {
            guard let instance = summary["fixture_instance_id"] as? String,
                  let source = try? Data(contentsOf: externalRoot
                    .appendingPathComponent("manifests", isDirectory: true)
                    .appendingPathComponent("\(instance).fixture-manifest.json")) else { continue }
            try source.write(to: manifestsDir.appendingPathComponent("\(instance).fixture-manifest.json"), options: [.atomic])
        }
        FileHandle.standardOutput.write(Data("S1 fixture preparation complete; S3 not run\n".utf8))
    }
}
