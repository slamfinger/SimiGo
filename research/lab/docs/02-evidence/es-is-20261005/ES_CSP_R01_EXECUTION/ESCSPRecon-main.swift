import Foundation
import CryptoKit
import Darwin
import CarrierInterface
import CarrierSQLite

struct RunInput {
    let sourceBaseline: String
    let runLabel: String
    let instanceID: String
    let carrierRoot: String
    let schemaVersion: String
    let sessionLocator: String
}

struct EventObservation {
    let slot: String
    let eventID: String
    let sessionID: String
    let sequence: Int
    let kind: String
    let payload: Data
    let payloadSHA256: String
    let occurredAt: Date
    let producedBy: String
    let informationID: String?
    let mappingID: String?
    let mappingFromVersion: String?
    let targetSlot: String?
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func iso(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

func readRunInput(_ url: URL) throws -> RunInput {
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    guard let dict = object as? [String: Any] else {
        throw NSError(domain: "ESCSPRecon", code: 1)
    }
    guard let baseline = dict["source_baseline_identifier"] as? String,
          let label = dict["run_label"] as? String,
          let instance = dict["opaque_fixture_instance_id"] as? String,
          let root = dict["isolated_carrier_data_root_path"] as? String,
          let schema = dict["reconstruction_manifest_schema_version"] as? String,
          let locator = dict["opaque_stable_session_locator"] as? String else {
        throw NSError(domain: "ESCSPRecon", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "run input missing required non-semantic field"])
    }
    return RunInput(sourceBaseline: baseline, runLabel: label, instanceID: instance,
                    carrierRoot: root, schemaVersion: schema, sessionLocator: locator)
}

func resolveSessionLocator(_ locator: String) throws -> String {
    let parts = locator.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2, parts[0] == "uasession", !parts[1].isEmpty else {
        throw NSError(domain: "ESCSPRecon", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "invalid stable session locator"])
    }
    return parts[1]
}

func jsonWrite(_ value: Any, to url: URL) throws -> Data {
    let data = try JSONSerialization.data(withJSONObject: value,
                                          options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try data.write(to: url, options: [.atomic])
    return data
}

func decodePayload(_ data: Data) throws -> (schema: String, slot: String, content: String, target: String?) {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let schema = object["schema"] as? String,
          let slot = object["slot"] as? String,
          let content = object["content"] as? String else {
        throw NSError(domain: "ESCSPRecon", code: 4,
                      userInfo: [NSLocalizedDescriptionKey: "invalid E0 payload"])
    }
    let target = object["target_slot"] as? String
    return (schema, slot, content, target)
}

func eventSummary(_ observation: EventObservation) -> [String: Any] {
    var value: [String: Any] = [
        "slot": observation.slot,
        "event_id": observation.eventID,
        "session_id": observation.sessionID,
        "sequence": observation.sequence,
        "record_kind": observation.kind,
        "payload_sha256": observation.payloadSHA256,
        "payload_byte_count": observation.payload.count,
        "payload_utf8": String(data: observation.payload, encoding: .utf8) ?? "",
        "occurred_at": iso(observation.occurredAt),
        "provenance_produced_by": observation.producedBy,
        "information_id": observation.informationID ?? "",
        "mapping_id": observation.mappingID ?? "",
        "mapping_from_version": observation.mappingFromVersion ?? ""
    ]
    if let target = observation.targetSlot {
        value["target_slot"] = target
    }
    return value
}

func witness(_ input: RunInput, ackURL: URL) async throws {
    guard try resolveSessionLocator(input.sessionLocator) != nil else {
        throw NSError(domain: "ESCSPRecon", code: 5)
    }
    let factory = SQLiteCarrierFactory(rootURL: URL(fileURLWithPath: input.carrierRoot, isDirectory: true))
    let bundle = try factory.make()
    let carrierID = try resolveSessionLocator(input.sessionLocator)
    let snapshot = try await bundle.operations.consistentSnapshot(carrierID: carrierID)
    let mappings = try await bundle.operations.mappings().filter { $0.carrierID == carrierID }
    let eventIDs = Set(snapshot.events.map { $0.eventID.rawValue })
    let durable = snapshot.events.count > 0
        && carrierID.isEmpty == false
        && snapshot.readVersion > 0
        && mappings.allSatisfy { eventIDs.contains($0.recordID) }
    guard durable else {
        throw NSError(domain: "ESCSPRecon", code: 6,
                      userInfo: [NSLocalizedDescriptionKey: "durable acknowledgement failed"])
    }
    let ack: [String: Any] = [
        "schema_version": "es-csp/durable-ack-v1",
        "fixture_instance_id": input.instanceID,
        "session_locator": input.sessionLocator,
        "durable_acknowledgement": true,
        "snapshot_event_count": snapshot.events.count,
        "snapshot_mapping_count": mappings.count,
        "snapshot_read_version": snapshot.readVersion
    ]
    _ = try jsonWrite(ack, to: ackURL)
    // Remain alive long enough for the controller to observe the durable ack,
    // then suffer process loss. This process performs no mutation.
    Thread.sleep(forTimeInterval: 600)
}

func reconstruct(_ input: RunInput, interruptionKind: String, outputURL: URL) async throws {
    let carrierID = try resolveSessionLocator(input.sessionLocator)
    let factory = SQLiteCarrierFactory(rootURL: URL(fileURLWithPath: input.carrierRoot, isDirectory: true))
    let bundle = try factory.make()
    let snapshot = try await bundle.operations.consistentSnapshot(carrierID: carrierID)
    let allMappings = try await bundle.operations.mappings().filter { $0.carrierID == carrierID }
    let mappingsByRecord = Dictionary(uniqueKeysWithValues: allMappings.map { ($0.recordID, $0) })

    var observations: [EventObservation] = []
    var payloadErrors: [String] = []
    for event in snapshot.events {
        let target: String?
        do {
            target = try decodePayload(event.payload).target
        } catch {
            target = nil
            payloadErrors.append("event \(event.eventID.rawValue): invalid payload")
        }
        let slot: String
        do {
            slot = try decodePayload(event.payload).slot
        } catch {
            slot = "INVALID"
        }
        let mapping = mappingsByRecord[event.eventID.rawValue]
        observations.append(EventObservation(
            slot: slot,
            eventID: event.eventID.rawValue,
            sessionID: event.sessionID.rawValue,
            sequence: event.sequence,
            kind: event.kind,
            payload: event.payload,
            payloadSHA256: sha256Hex(event.payload),
            occurredAt: event.occurredAt,
            producedBy: event.provenance.producedBy,
            informationID: mapping?.informationID,
            mappingID: mapping?.mappingID,
            mappingFromVersion: mapping?.fromVersion,
            targetSlot: target
        ))
    }

    let eventsBySlot = Dictionary(grouping: observations, by: { $0.slot }).mapValues { $0.sorted { $0.sequence < $1.sequence } }
    let requiredBaseSlots = ["O1", "I1", "D1", "A1"]
    let boundaryEvents = observations.filter { $0.slot.hasPrefix("B") }
    let pointerEvents = observations.filter { $0.kind == "NEXT_ACTION" }

    var c1Defects: [String] = []
    for slot in requiredBaseSlots where eventsBySlot[slot]?.isEmpty != false {
        c1Defects.append("missing required slot \(slot)")
    }
    if boundaryEvents.isEmpty {
        c1Defects.append("missing boundary state")
    }
    if pointerEvents.isEmpty {
        c1Defects.append("missing continuation pointer")
    }
    for event in observations where event.producedBy.isEmpty {
        c1Defects.append("event \(event.eventID) lacks provenance")
    }
    for event in observations where event.mappingID == nil || event.informationID == nil {
        c1Defects.append("event \(event.eventID) lacks CC-5 mapping")
    }
    for event in observations where (event.mappingFromVersion ?? "").isEmpty {
        c1Defects.append("mapping \(event.eventID) lacks revision provenance")
    }
    for event in observations where event.slot.hasPrefix("I") {
        let reference = try? decodePayload(event.payload).content
        if let reference, eventsBySlot[reference]?.isEmpty != false {
            c1Defects.append("input reference \(reference) does not resolve")
        }
    }
    if snapshot.readVersion <= 0 {
        c1Defects.append("carrier read version is not positive")
    }
    let c1Pass = c1Defects.isEmpty

    var pointerTargets: [String] = []
    var scalarPointer = true
    var invalidPointerTargets: [String] = []
    for pointer in pointerEvents {
        guard let target = pointer.targetSlot else {
            scalarPointer = false
            invalidPointerTargets.append("MISSING")
            continue
        }
        pointerTargets.append(target)
        if eventsBySlot[target]?.isEmpty != false {
            invalidPointerTargets.append(target)
        }
    }

    var decision = "BLOCK_INSUFFICIENT"
    var decisionReason = ""
    var boundary = ""
    if !c1Pass {
        decisionReason = "RECONSTRUCTION_INCOMPLETE"
    } else if !scalarPointer {
        decisionReason = "NON_SCALAR_POINTER_STRUCTURE"
    } else if !invalidPointerTargets.isEmpty {
        decisionReason = "INVALID_POINTER_TARGET"
    } else if pointerTargets.isEmpty {
        decisionReason = "MISSING_POINTER"
    } else if Set(pointerTargets).count == 1, let only = pointerTargets.first {
        decision = "CONTINUE_CERTAIN"
        decisionReason = "EXACTLY_ONE_REGISTERED_BOUNDARY"
        boundary = only
    } else {
        decisionReason = "AMBIGUOUS_POINTER_SET"
    }

    let c1: [String: Any] = [
        "status": c1Pass ? "PASS" : "FAIL",
        "defects": c1Defects,
        "required_base_slots": requiredBaseSlots,
        "observed_slots": observations.map { $0.slot },
        "boundary_cardinality": boundaryEvents.count,
        "pointer_cardinality": pointerEvents.count
    ]
    let c2: [String: Any] = [
        "decision": decision,
        "reason": decisionReason,
        "boundary": boundary,
        "pointer_target_cardinality": Set(pointerTargets).count,
        "pointer_targets": pointerTargets,
        "invalid_pointer_targets": invalidPointerTargets,
        "authority": "NEXT_ACTION records only"
    ]
    let c3: [String: Any] = [
        "status": "NOT_PERFORMED",
        "role": "OBSERVATION_ONLY",
        "contributes_to_pass": false
    ]

    var payloadErrorsFinal: [String] = payloadErrors
    if !scalarPointer {
        payloadErrorsFinal.append("at least one target_slot is non-scalar")
    }

    let observed: [String: Any] = [
        "schema_version": "es-csp/reconstruction-manifest-v1",
        "source_baseline_identifier": input.sourceBaseline,
        "run_label": input.runLabel,
        "opaque_fixture_instance_id": input.instanceID,
        "interruption_kind": interruptionKind,
        "entry_point": [
            "input": input.sessionLocator,
            "resolved_carrier_id": carrierID,
            "resolution": "EXACT_NON_SEMANTIC"
        ],
        "side_channel_exclusions": [
            "fixture_role": true,
            "expected_c1": true,
            "expected_c2": true,
            "deficiency_description": true,
            "semantic_search": true,
            "embedding": true,
            "ranking": true,
            "mcp": true,
            "remote_api": true,
            "conversation_history": true,
            "agent_notes": true,
            "prior_process_memory": true
        ],
        "snapshot": [
            "event_count": snapshot.events.count,
            "mapping_count": allMappings.count,
            "read_version": snapshot.readVersion
        ],
        "events": observations.map(eventSummary),
        "payload_errors": payloadErrorsFinal,
        "c1": c1,
        "c2": c2,
        "c3": c3,
        "evidence": [
            "EV-6_reconstruction_manifest": true,
            "EV-7_c1_status": true,
            "EV-8_c2_status": true,
            "EV-9_carrier_precondition": true,
            "EV-R3_pointer_path": "NEXT_ACTION only",
            "stable_addressing_only": true
        ]
    ]

    _ = try jsonWrite(observed, to: outputURL)
}

@main struct Program {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 4 else {
            FileHandle.standardError.write(Data("usage: ESCSPRecon reconstruct|witness <run-input.json> <output.json> [interruption]\n".utf8))
            exit(2)
        }
        let mode = arguments[1]
        let inputURL = URL(fileURLWithPath: arguments[2], isDirectory: false)
        let outputURL = URL(fileURLWithPath: arguments[3], isDirectory: false)
        let input = try readRunInput(inputURL)
        switch mode {
        case "witness":
            try await witness(input, ackURL: outputURL)
        case "reconstruct":
            let interruption = arguments.count > 4 ? arguments[4] : "I-1"
            try await reconstruct(input, interruptionKind: interruption, outputURL: outputURL)
        default:
            FileHandle.standardError.write(Data("unknown mode\n".utf8))
            exit(2)
        }
    }
}
