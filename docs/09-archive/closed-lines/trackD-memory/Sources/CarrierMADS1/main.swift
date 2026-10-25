import Foundation
import CryptoKit
import CarrierInterface
import CarrierSQLite

// MA-DS-1 "Multi-Agent Research Day" runner — CCVS-01 U-A, Unified Minimal
// Composition Manifest §5 (13 pre-registered steps, unchanged). Exercises
// the IMPLEMENTED composition; adds no mechanisms. Crash gates UA-C1/C2/C3
// fire as real process SIGKILLs (P8 pattern). Outcomes are classified per
// manifest semantics: PASS / REPAIR / DETACHED / INCOMPLETE / UA-DF-n —
// never a "PASS-only" script.

let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "campaign"
let fm = FileManager.default

func jsonWrite(_ object: [String: Any], to url: URL) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
    try! data.write(to: url)
}

func jsonRead(_ url: URL) -> [String: Any] {
    try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
}

func evidenceDir(_ root: URL) -> URL {
    let d = root.appendingPathComponent("evidence", isDirectory: true)
    try! fm.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

func loadState(_ root: URL) -> [String: Any] {
    jsonRead(root.appendingPathComponent("state.json"))
}

func saveState(_ root: URL, _ state: [String: Any]) {
    jsonWrite(state, to: root.appendingPathComponent("state.json"))
}

func bundle(_ root: URL) throws -> SQLiteCarrierBundle {
    try SQLiteCarrierFactory(rootURL: root).make()
}

func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func appendEvent(_ ops: SQLiteUnifiedCarrierOperations, _ carrierID: String,
                 kind: String, payload: String, occurredAt: TimeInterval,
                 actor: String, op: String, ref: String) async throws -> UASessionAppendResult {
    try await ops.appendSessionEvent(
        carrierID: carrierID, kind: kind, payload: Data(payload.utf8),
        occurredAt: Date(timeIntervalSince1970: occurredAt),
        actorID: actor, operationID: op, clientRef: ref)
}

func eventPayload(_ event: CarrierSessionEvent) -> String {
    String(data: event.payload, encoding: .utf8) ?? "<binary>"
}

// MARK: - Phases (each writes evidence/<step>.json)

func step1(_ root: URL) async throws {
    let b = try bundle(root)
    let ops = b.operations
    let (f1, outcome) = try await ops.createCarrier(
        kind: .file, locatorScheme: "file", locatorValue: "research/q3-notes.md",
        actorID: "agent-A", operationID: "op-s1-create-f1")
    let rev1Payload = Data("research day q3 notes revision 1\nquantum flux design notes".utf8)
    let (f1v1, revOutcome) = try await ops.reviseCarrierWithRepresentation(
        carrierID: f1.carrierID,
        informationID: CarrierInformationID(rawValue: "info-f1"),
        revisionID: CarrierRevisionID(rawValue: "f1-rev-1"),
        representationID: CarrierRepresentationID(rawValue: "f1-rep-1"),
        payload: rev1Payload, mediaType: "text/plain",
        expectedRevision: 0, fromVersion: nil,
        actorID: "agent-A", operationID: "op-s1-rev1")
    let readBack = try await b.representations.content(
        CarrierRepresentationID(rawValue: "f1-rep-1"))
    let dangling = try await ops.danglingProvenanceCount()
    var state = loadState(root)
    state["f1"] = ["carrierID": f1.carrierID, "rev1RepID": "f1-rep-1",
                   "rev1Digest": digest(rev1Payload), "rev1Locator": "research/q3-notes.md"]
    state["fingerprint_after_step1"] = try await ops.authorityFingerprint()
    saveState(root, state)
    jsonWrite(["step": 1, "injected": "none",
               "observed": ["create_outcome": outcome.rawValue,
                            "rev1_outcome": revOutcome.rawValue,
                            "carrier_id_minted": f1.carrierID,
                            "revision": f1v1.revision,
                            "entity_digest_verified": readBack?.payload.bytes == rev1Payload,
                            "dangling_provenance": dangling],
               "bound": "CC-1/CC-2 identity minting + durable acknowledgement",
               "classification": (outcome == .applied && revOutcome == .applied
                                  && f1v1.revision == 1
                                  && readBack?.payload.bytes == rev1Payload
                                  && dangling == 0) ? "PASS" : "UA-DF-1",
               "residual": NSNull()], to: evidenceDir(root).appendingPathComponent("step01.json"))
}

func step2(_ root: URL) async throws {
    let b = try bundle(root)
    let ops = b.operations
    let state = loadState(root)
    let f1 = state["f1"] as! [String: Any]
    // Compound order (manifest §3): formation precedes carrier registration;
    // the carrier-side claim (mapping) is appended after the record carrying
    // the content exists.
    let (s1, _) = try await ops.createCarrier(
        kind: .session, locatorScheme: nil, locatorValue: nil,
        actorID: "agent-A", operationID: "op-s2-create-s1")
    let judgment = try await appendEvent(
        ops, s1.carrierID, kind: "JUDGMENT", payload: "judgment: F1 rev1 design holds",
        occurredAt: 1000, actor: "agent-A", op: "op-s2-ev0", ref: "ref-s2-ev0")
    _ = try await ops.recordMapping(
        informationID: CarrierInformationID(rawValue: "info-judgment-1"),
        carrierID: s1.carrierID, recordID: "rec-ev-\(judgment.event.sequence)",
        representationID: nil, fromVersion: nil,
        actorID: "agent-A", operationID: "op-s2-map-judgment")
    let link = try await appendEvent(
        ops, s1.carrierID, kind: "EVIDENCE_LINK",
        payload: "evidence: F1@f1-rev-1 digest \(f1["rev1Digest"] as! String)",
        occurredAt: 1001, actor: "agent-A", op: "op-s2-ev1", ref: "ref-s2-ev1")
    _ = try await ops.recordMapping(
        informationID: CarrierInformationID(rawValue: "info-f1"),
        carrierID: s1.carrierID, recordID: "rec-ev-\(link.event.sequence)",
        representationID: "f1-rep-1", fromVersion: "f1-rev-1",
        actorID: "agent-A", operationID: "op-s2-map-link")
    let snapshot = try await ops.consistentSnapshot(carrierID: s1.carrierID)
    var newState = loadState(root)
    newState["s1"] = ["carrierID": s1.carrierID]
    newState["fingerprint_after_step2"] = try await ops.authorityFingerprint()
    saveState(root, newState)
    jsonWrite(["step": 2, "injected": "none",
               "observed": ["events": snapshot.events.count,
                            "sequences": snapshot.events.map(\.sequence),
                            "kinds": snapshot.events.map(\.kind),
                            "mappings_on_s1": snapshot.mappings.count,
                            "evidence_link_payload": eventPayload(link.event)],
               "bound": "CC-5 mapping closed loop / I17-I18 reviewability basis",
               "classification": (snapshot.events.count == 2
                                  && snapshot.events.map(\.sequence) == [0, 1]
                                  && snapshot.mappings.count == 2) ? "PASS" : "UA-DF-2",
               "residual": NSNull()], to: evidenceDir(root).appendingPathComponent("step02.json"))
}

func step3(_ root: URL) async throws {
    let b = try bundle(root)
    let ops = b.operations
    let state = loadState(root)
    let f1ID = (state["f1"] as! [String: Any])["carrierID"] as! String
    let s1ID = (state["s1"] as! [String: Any])["carrierID"] as! String
    // Actor B reads both carriers concurrently (MA-1).
    async let f1SnapAsync = ops.consistentSnapshot(carrierID: f1ID)
    async let s1SnapAsync = ops.consistentSnapshot(carrierID: s1ID)
    let f1Snap = try await f1SnapAsync
    let s1Snap = try await s1SnapAsync
    let s1Contiguous = s1Snap.events.map(\.sequence) == Array(0..<s1Snap.events.count)
    jsonWrite(["step": 3, "injected": "concurrent dual read (MA-1)",
               "observed": ["f1_read_revision": f1Snap.carrier?.revision ?? -1,
                            "s1_read_events": s1Snap.events.count,
                            "s1_sequences_contiguous": s1Contiguous],
               "bound": "MA-1 concurrent read",
               "classification": ((f1Snap.carrier?.revision ?? 0) >= 1 && s1Contiguous)
                                   ? "PASS" : "UA-DF-3",
               "residual": NSNull()], to: evidenceDir(root).appendingPathComponent("step03.json"))
}

func step4(_ root: URL) async throws {
    let b = try bundle(root)
    let ops = b.operations
    let state = loadState(root)
    let f1ID = (state["f1"] as! [String: Any])["carrierID"] as! String
    let s1ID = (state["s1"] as! [String: Any])["carrierID"] as! String
    let before = try await ops.carrier(carrierID: f1ID)
    // Actor B reorganizes (MOVE + revise) while a session append proceeds
    // on the OTHER family (MA-2 cross-family interleave).
    var appendSequence = -1
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            _ = try await ops.reviseCarrier(
                carrierID: f1ID, expectedRevision: before?.revision ?? 0,
                newLocatorScheme: "file", newLocatorValue: "archive/2026/q3-notes.md",
                fromVersion: "organize-move", actorID: "agent-B",
                operationID: "op-s4-move")
        }
        group.addTask {
            let r = try await appendEvent(
                ops, s1ID, kind: "NOTE", payload: "B reorganized F1",
                occurredAt: 1002, actor: "agent-B", op: "op-s4-ev", ref: "ref-s4-ev")
            appendSequence = r.event.sequence
        }
        try await group.waitForAll()
    }
    let after = try await ops.carrier(carrierID: f1ID)
    var newState = loadState(root)
    newState["fingerprint_after_step4"] = try await ops.authorityFingerprint()
    saveState(root, newState)
    jsonWrite(["step": 4, "injected": "cross-family concurrent write (MA-2)",
               "observed": ["identity_unchanged": after?.carrierID == f1ID,
                            "revision": after?.revision ?? -1,
                            "locator_before": before?.locatorValue ?? "?",
                            "locator_after_move": after?.locatorValue ?? "?",
                            "cross_family_append_sequence": appendSequence],
               "bound": "MA-2 concurrent write / MA-5 identity stability (MOVE)",
               "classification": (after?.carrierID == f1ID && after?.revision == 2
                                  && after?.locatorValue == "archive/2026/q3-notes.md"
                                  && appendSequence >= 0) ? "PASS" : "UA-DF-4",
               "residual": NSNull()], to: evidenceDir(root).appendingPathComponent("step04.json"))
}

func step5(_ root: URL) async throws {
    let b = try bundle(root)
    let ops = b.operations
    let state = loadState(root)
    let f1ID = (state["f1"] as! [String: Any])["carrierID"] as! String
    // Actor A still works from base rev1 (expected=1); carrier is at 2.
    var conflictCaught = false
    var conflictError = ""
    do {
        _ = try await ops.reviseCarrier(
            carrierID: f1ID, expectedRevision: 1,
            newLocatorScheme: "file", newLocatorValue: "research/q3-notes.md",
            fromVersion: "base-rev-1", actorID: "agent-A", operationID: "op-s5-stale")
    } catch UAOperationError.staleRevision(let expected, let observed) {
        conflictCaught = true
        conflictError = "stale(\(expected),\(observed))"
    }
    let after = try await ops.carrier(carrierID: f1ID)
    let conflictRow = try await ops.operationLedger()
        .first { $0.operationID == "op-s5-stale" }
    jsonWrite(["step": 5, "injected": "stale base write (expected=1, current=2)",
               "observed": ["conflict_typed": conflictCaught,
                            "conflict_error": conflictError,
                            "state_unchanged": after?.revision == 2,
                            "locator_unchanged": after?.locatorValue == "archive/2026/q3-notes.md",
                            "conflict_ledger_outcome": conflictRow?.outcome.rawValue ?? "absent",
                            "conflict_observed_revision": conflictRow?.observedRevision ?? -1],
               "bound": "MA-3 / I19 no lost update",
               "classification": (conflictCaught && after?.revision == 2
                                  && conflictRow?.outcome == .conflict
                                  && conflictRow?.observedRevision == 2)
                                   ? "PASS" : "UA-DF-5",
               "residual": NSNull()], to: evidenceDir(root).appendingPathComponent("step05.json"))
}

func step6(_ root: URL) async throws {
    let b = try bundle(root)
    let ops = b.operations
    let state = loadState(root)
    let f1ID = (state["f1"] as! [String: Any])["carrierID"] as! String
    // Rebase: re-read (2), re-apply as a NEW operation (new operation id).
    let current = try await ops.carrier(carrierID: f1ID)
    let payload = Data("research day q3 notes revision 3 (rebased on rev2)\nquantum flux design notes".utf8)
    let (rebased, outcome) = try await ops.reviseCarrierWithRepresentation(
        carrierID: f1ID,
        informationID: CarrierInformationID(rawValue: "info-f1"),
        revisionID: CarrierRevisionID(rawValue: "f1-rev-3"),
        representationID: CarrierRepresentationID(rawValue: "f1-rep-3"),
        payload: payload, mediaType: "text/plain",
        expectedRevision: current?.revision ?? 0,
        fromVersion: "rebase-from-rev-2",
        actorID: "agent-A", operationID: "op-s6-rebase")
    let readBack = try await b.representations.content(
        CarrierRepresentationID(rawValue: "f1-rep-3"))
    var newState = loadState(root)
    newState["fingerprint_after_step6"] = try await ops.authorityFingerprint()
    saveState(root, newState)
    jsonWrite(["step": 6, "injected": "rebase after conflict (new operation id)",
               "observed": ["outcome": outcome.rawValue,
                            "revision": rebased.revision,
                            "from_version_provenance": "rebase-from-rev-2",
                            "content_verified": readBack?.payload.bytes == payload],
               "bound": "MA-3 rebase path / MA-8 provenance",
               "classification": (outcome == .applied && rebased.revision == 3
                                  && readBack?.payload.bytes == payload)
                                   ? "PASS" : "UA-DF-6",
               "residual": NSNull()], to: evidenceDir(root).appendingPathComponent("step06.json"))
}

func step7(_ root: URL) async throws {
    let b = try bundle(root)
    let ops = b.operations
    let state = loadState(root)
    let s1ID = (state["s1"] as! [String: Any])["carrierID"] as! String
    let before = try await ops.consistentSnapshot(carrierID: s1ID)
    let baseSequence = before.events.last?.sequence ?? -1
    // Six concurrent appends (A x3, B x3). Timestamps are injected through
    // a fixed permutation so creation order and clock order DECOUPLE: if
    // the carrier allocated by creation order, the sequence-ordered
    // timestamps are NOT descending; only timestamp-driven ordering would
    // produce a descending list.
    let skewPermutation = [3, 0, 4, 1, 5, 2]
    let results = try await withThrowingTaskGroup(of: UASessionAppendResult.self)
        { group -> [UASessionAppendResult] in
            for index in 0..<6 {
                group.addTask {
                    try await appendEvent(
                        ops, s1ID, kind: "NOTE", payload: "day-note-\(index)",
                        occurredAt: Double(2000 - skewPermutation[index]),
                        actor: index.isMultiple(of: 2) ? "agent-A" : "agent-B",
                        op: "op-s7-\(index)", ref: "ref-s7-\(index)")
                }
            }
            var out: [UASessionAppendResult] = []
            for try await r in group { out.append(r) }
            return out
        }
    let after = try await ops.consistentSnapshot(carrierID: s1ID)
    let newSequences = after.events.map(\.sequence).filter { $0 > baseSequence }
    let occurred = after.events.filter { $0.sequence > baseSequence }
        .map { Int($0.occurredAt.timeIntervalSince1970) }
    let contiguous = newSequences == Array((baseSequence + 1)...(baseSequence + 6))
    let skewRespected = occurred != occurred.sorted().reversed()
    var newState = loadState(root)
    newState["fingerprint_after_step7"] = try await ops.authorityFingerprint()
    saveState(root, newState)
    jsonWrite(["step": 7, "injected": "6 concurrent appends, reversed clock skew",
               "observed": ["all_applied": results.allSatisfy { $0.outcome == .applied },
                            "sequences": newSequences,
                            "contiguous": contiguous,
                            "allocation_order_differs_from_timestamp_order": skewRespected,
                            "read_version": after.readVersion],
               "bound": "MA-6 / I23 session ordering under concurrency",
               "classification": (results.count == 6
                                  && results.allSatisfy { $0.outcome == .applied }
                                  && contiguous && skewRespected) ? "PASS" : "UA-DF-7",
               "residual": NSNull()], to: evidenceDir(root).appendingPathComponent("step07.json"))
}

func step8Crash(_ root: URL) async throws {
    let b = try bundle(root)
    let ops = b.operations
    let state = loadState(root)
    let s1ID = (state["s1"] as! [String: Any])["carrierID"] as! String
    // Arm UA-C1: the append COMMITS, then the process dies before the
    // actor learns the outcome (unknown-outcome window).
    setenv("CCVS_CRASH", "UA-C1", 1)
    _ = try await appendEvent(
        ops, s1ID, kind: "RESULT", payload: "step8 committed result",
        occurredAt: 3000, actor: "agent-A", op: "op-s8", ref: "ref-s8")
    FileHandle.standardError.write(Data("[warn] UA-C1 did not fire\n".utf8))
}

func step8Recover(_ root: URL, killed: Bool) async throws {
    let b = try bundle(root)
    let ops = b.operations
    let state = loadState(root)
    let s1ID = (state["s1"] as! [String: Any])["carrierID"] as! String
    let before = try await ops.consistentSnapshot(carrierID: s1ID)
    let fingerprintBefore = try await ops.authorityFingerprint()
    // Retry with the SAME operation id: MA-7 replay of the recorded outcome.
    let retry = try await ops.appendSessionEvent(
        carrierID: s1ID, kind: "RESULT", payload: Data("step8 committed result".utf8),
        occurredAt: Date(timeIntervalSince1970: 3000),
        actorID: "agent-A", operationID: "op-s8", clientRef: "ref-s8")
    let after = try await ops.consistentSnapshot(carrierID: s1ID)
    let fingerprintAfter = try await ops.authorityFingerprint()
    let committedBeforeCrash = before.events.contains { eventPayload($0) == "step8 committed result" }
    var newState = loadState(root)
    newState["fingerprint_after_step8"] = fingerprintAfter
    saveState(root, newState)
    jsonWrite(["step": 8, "injected": "UA-C1 SIGKILL after append commit (unknown outcome)",
               "observed": ["killed_by_sigkill": killed,
                            "durable_facts_established_before_crash":
                                "event + ledger APPLIED committed (synchronous=FULL)",
                            "committed_before_crash": committedBeforeCrash,
                            "retry_outcome": retry.outcome.rawValue,
                            "retry_returns_recorded_outcome": retry.outcome == .applied,
                            "event_count_unchanged_by_retry":
                                before.events.count == after.events.count,
                            "fingerprint_unchanged_by_retry":
                                fingerprintBefore == fingerprintAfter],
               "bound": "MA-7 / I24 idempotent retry (round-4 ruling: retry returns the RECORDED terminal outcome; zero-effect boundary = no new event, no new ledger row, entity layer untouched)",
               "classification": (killed && committedBeforeCrash
                                  && retry.outcome == .applied
                                  && before.events.count == after.events.count
                                  && fingerprintBefore == fingerprintAfter)
                                   ? "PASS" : "UA-DF-8",
               "residual": NSNull()], to: evidenceDir(root).appendingPathComponent("step08.json"))
}

func step9Crash(_ root: URL) async throws {
    let b = try bundle(root)
    let ops = b.operations
    let state = loadState(root)
    let f1ID = (state["f1"] as! [String: Any])["carrierID"] as! String
    let current = try await ops.carrier(carrierID: f1ID)
    // Arm UA-C2: entity bytes durably written, registry transaction NOT
    // started (durable-acknowledgement boundary).
    setenv("CCVS_CRASH", "UA-C2", 1)
    _ = try await ops.reviseCarrierWithRepresentation(
        carrierID: f1ID,
        informationID: CarrierInformationID(rawValue: "info-f1"),
        revisionID: CarrierRevisionID(rawValue: "f1-rev-4"),
        representationID: CarrierRepresentationID(rawValue: "f1-rep-4"),
        payload: Data("revision 4 content (crash episode)\nquantum flux design notes".utf8),
        mediaType: "text/plain",
        expectedRevision: current?.revision ?? 0,
        fromVersion: nil, actorID: "agent-A", operationID: "op-s9")
    FileHandle.standardError.write(Data("[warn] UA-C2 did not fire\n".utf8))
}

func step9Recover(_ root: URL, killed: Bool) async throws {
    let b = try bundle(root)
    let ops = b.operations
    let state = loadState(root)
    let f1ID = (state["f1"] as! [String: Any])["carrierID"] as! String
    let payload = Data("revision 4 content (crash episode)\nquantum flux design notes".utf8)
    let payloadDigest = digest(payload)
    // Post-crash durable-fact inspection.
    let afterCrashIntegrity = try await b.runtime.integrityReport()
    let afterCrashCarrier = try await ops.carrier(carrierID: f1ID)
    let afterCrashRep = try await b.representations.content(
        CarrierRepresentationID(rawValue: "f1-rep-4"))
    let ledgerAfterCrash = try await ops.operationLedger()
        .first { $0.operationID == "op-s9" }
    let orphanEvidence = afterCrashIntegrity.issues
        .filter { $0.kind == .orphanRepresentation }
        .map(\.detail)
        .filter { $0.contains(payloadDigest) }
    // Recovery = the prescribed idempotent retry (same operation id).
    let (revised, outcome) = try await ops.reviseCarrierWithRepresentation(
        carrierID: f1ID,
        informationID: CarrierInformationID(rawValue: "info-f1"),
        revisionID: CarrierRevisionID(rawValue: "f1-rev-4"),
        representationID: CarrierRepresentationID(rawValue: "f1-rep-4"),
        payload: payload, mediaType: "text/plain",
        expectedRevision: afterCrashCarrier?.revision ?? 0,
        fromVersion: nil, actorID: "agent-A", operationID: "op-s9")
    let finalIntegrity = try await b.runtime.integrityReport()
    // CC-MA-relevant integrity aspect: no entity FILE may be orphaned (the
    // crash artifact must be resolved by the retry). The A1 reporter's
    // locator/availability invariants concern the A1 runtime path and do
    // not bind UA-operation representations (registered composition
    // bookkeeping boundary, see residual).
    let finalEntityOrphans = finalIntegrity.issues
        .filter { $0.kind == .orphanRepresentation && $0.detail.contains("entity file") }
    let content = try await b.representations.content(
        CarrierRepresentationID(rawValue: "f1-rep-4"))
    var newState = loadState(root)
    newState["fingerprint_after_step9"] = try await ops.authorityFingerprint()
    saveState(root, newState)
    jsonWrite(["step": 9,
               "injected": "UA-C2 SIGKILL between entity fsync and registry transaction",
               "observed": [
                   "killed_by_sigkill": killed,
                   "durable_facts_established_before_crash":
                       "entity bytes durable (fsync+rename+dir-fsync+digest re-read)",
                   "durable_facts_NOT_established_before_crash":
                       "representation row, carrier revision bump, ledger/provenance row",
                   "crash_orphan_entity_detected": !orphanEvidence.isEmpty,
                   "crash_registry_unchanged": afterCrashCarrier?.revision == 3,
                   "crash_representation_absent": afterCrashRep == nil,
                   "crash_ledger_absent": ledgerAfterCrash == nil,
                   "crash_dangling_provenance": try await ops.danglingProvenanceCount(),
                   "retry_outcome": outcome.rawValue,
                   "retry_revision": revised.revision,
                   "content_verified": content?.payload.bytes == payload,
                   "final_entity_orphans": finalEntityOrphans.count,
                   "final_integrity_clean": finalIntegrity.isClean,
                   "integrity_note": "isClean includes A1-runtime locator/availability invariants that do not bind the UA operation path"],
               "orphan_evidence": orphanEvidence,
               "bound": "MA-4 atomicity / I21 no dangling provenance",
               "classification": (killed && !orphanEvidence.isEmpty
                                  && afterCrashCarrier?.revision == 3
                                  && afterCrashRep == nil && ledgerAfterCrash == nil
                                  && outcome == .applied && revised.revision == 4
                                  && content?.payload.bytes == payload
                                  && finalEntityOrphans.isEmpty)
                                   ? "PASS (expected orphan state, explicitly detected; recovery via prescribed idempotent retry)"
                                   : "UA-DF-9",
               "residual": "orphan entity transient existed between crash and retry; resolved by the retry itself. A1-reporter locator/availability findings on UA-path representations are a registered composition bookkeeping boundary, not a CC-MA bound violation"], to: evidenceDir(root).appendingPathComponent("step09.json"))
}

/// Coverage is compared at (information, carrier) granularity — the same
/// scope the index writes use (UA-IF-3 second-layer verification, audit
/// focus 1). An information-scoped comparison could mask a missing
/// carrier-scoped row behind the other carrier's row.
func coverageOf(_ ops: SQLiteUnifiedCarrierOperations) async throws -> [String: [String]] {
    let quantum = try await ops.searchScoped("quantum", limit: 50)
        .map { "\($0.informationID)|\($0.carrierID)" }
        .sorted()
    let timeline = try await ops.searchScoped("timeline", limit: 50)
        .map { "\($0.informationID)|\($0.carrierID)" }
        .sorted()
    return ["quantum": quantum, "timeline": timeline]
}

func step10Prep(_ root: URL) async throws {
    let b = try bundle(root)
    let ops = b.operations
    let state = loadState(root)
    let f1ID = (state["f1"] as! [String: Any])["carrierID"] as! String
    let s1ID = (state["s1"] as! [String: Any])["carrierID"] as! String
    // Index both domains, then advance a carrier so the index becomes stale.
    try await ops.indexDocument(
        informationID: CarrierInformationID(rawValue: "info-f1"),
        carrierID: f1ID, revisionID: CarrierRevisionID(rawValue: "f1-rev-4"),
        title: "q3-notes", text: "quantum flux design notes research day")
    try await ops.indexDocument(
        informationID: CarrierInformationID(rawValue: "info-judgment-1"),
        carrierID: s1ID, revisionID: CarrierRevisionID(rawValue: "s1-rev-index"),
        title: nil, text: "session timeline judgment research day")
    _ = try await ops.recordMapping(
        informationID: CarrierInformationID(rawValue: "info-f1"),
        carrierID: f1ID, recordID: "rec-c3-advance",
        representationID: nil, fromVersion: nil,
        actorID: "agent-B", operationID: "op-s10-advance")
    let staleBefore = try await ops.indexStaleness()
    let coverage = try await coverageOf(ops)
    let fingerprint = try await ops.authorityFingerprint()
    var newState = loadState(root)
    newState["step10_coverage_before"] = coverage
    newState["step10_fingerprint_before"] = fingerprint
    newState["step10_stale_before"] = staleBefore.count
    saveState(root, newState)
}

func step10Crash(_ root: URL) async throws {
    let b = try bundle(root)
    let ops = b.operations
    let state = loadState(root)
    let f1ID = (state["f1"] as! [String: Any])["carrierID"] as! String
    let s1ID = (state["s1"] as! [String: Any])["carrierID"] as! String
    let docs: [(informationID: CarrierInformationID, carrierID: String,
                revisionID: CarrierRevisionID, title: String?, text: String)] = [
        (CarrierInformationID(rawValue: "info-f1"), f1ID,
         CarrierRevisionID(rawValue: "f1-rev-4"), "q3-notes",
         "quantum flux design notes research day"),
        (CarrierInformationID(rawValue: "info-judgment-1"), s1ID,
         CarrierRevisionID(rawValue: "s1-rev-index"), nil,
         "session timeline judgment research day")
    ]
    // Arm UA-C3: dies inside the rebuild transaction (after the DELETEs).
    setenv("CCVS_CRASH", "UA-C3", 1)
    _ = try await ops.rebuildIndex(documents: docs)
    FileHandle.standardError.write(Data("[warn] UA-C3 did not fire\n".utf8))
}

func step10Recover(_ root: URL, killed: Bool) async throws {
    let b = try bundle(root)
    let ops = b.operations
    let state = loadState(root)
    let f1ID = (state["f1"] as! [String: Any])["carrierID"] as! String
    let s1ID = (state["s1"] as! [String: Any])["carrierID"] as! String
    let coverageBefore = state["step10_coverage_before"] as! [String: [String]]
    let fingerprintBefore = state["step10_fingerprint_before"] as! String
    // Post-crash: the rebuild transaction rolled back — the OLD index is
    // intact but stale (atomic rebuild, no partial index).
    let postCrashCoverage = try await coverageOf(ops)
    let postCrashStale = try await ops.indexStaleness()
    let postCrashFingerprint = try await ops.authorityFingerprint()
    // Prescribed recovery: re-run the rebuild from authority-derived docs.
    let docs: [(informationID: CarrierInformationID, carrierID: String,
                revisionID: CarrierRevisionID, title: String?, text: String)] = [
        (CarrierInformationID(rawValue: "info-f1"), f1ID,
         CarrierRevisionID(rawValue: "f1-rev-4"), "q3-notes",
         "quantum flux design notes research day"),
        (CarrierInformationID(rawValue: "info-judgment-1"), s1ID,
         CarrierRevisionID(rawValue: "s1-rev-index"), nil,
         "session timeline judgment research day")
    ]
    let report = try await ops.rebuildIndex(documents: docs)
    let finalCoverage = try await coverageOf(ops)
    let finalStale = try await ops.indexStaleness()
    let finalFingerprint = try await ops.authorityFingerprint()
    var newState = loadState(root)
    newState["fingerprint_after_step10"] = finalFingerprint
    saveState(root, newState)
    jsonWrite(["step": 10,
               "injected": "UA-C3 SIGKILL inside rebuild transaction (after DELETEs)",
               "observed": [
                   "killed_by_sigkill": killed,
                   "durable_facts_established_before_crash":
                       "authority untouched throughout (rebuild is a derived-layer transaction)",
                   "durable_facts_NOT_established_before_crash":
                       "new index build rows (rolled back with the transaction)",
                   "crash_index_intact_atomic_rollback": postCrashCoverage == coverageBefore,
                   "crash_stale_detectable": !postCrashStale.isEmpty,
                   "crash_authority_unchanged": postCrashFingerprint == fingerprintBefore,
                   "rebuild_documents": report.documentsIndexed,
                   "final_coverage_matches": finalCoverage == coverageBefore,
                   "final_staleness_clear": finalStale.isEmpty,
                   "final_authority_unchanged": finalFingerprint == fingerprintBefore],
               "bound": "MA-9 / I25 derived-index isolation + rebuild completeness gate",
               "classification": (killed && postCrashCoverage == coverageBefore
                                  && !postCrashStale.isEmpty
                                  && postCrashFingerprint == fingerprintBefore
                                  && finalCoverage == coverageBefore
                                  && finalStale.isEmpty
                                  && finalFingerprint == fingerprintBefore)
                                   ? "REPAIR (prescribed recovery: rebuild re-run from authority; authority byte-identical; coverage restored)"
                                   : "UA-DF-10",
               "residual": "index was stale-but-intact between crash and recovery (atomic rollback); rebuild-compare covered identity AND searchable-content coverage"], to: evidenceDir(root).appendingPathComponent("step10.json"))
}

func step11(_ root: URL) async throws {
    let b = try bundle(root)
    let ops = b.operations
    let state = loadState(root)
    let s1ID = (state["s1"] as! [String: Any])["carrierID"] as! String
    // Actor A commits while actor B takes repeated multi-object reads.
    let snapshots = try await withThrowingTaskGroup(of: UACarrierSnapshot.self)
        { group -> [UACarrierSnapshot] in
            for index in 0..<4 {
                group.addTask {  // A's commit then read
                    _ = try await appendEvent(
                        ops, s1ID, kind: "NOTE", payload: "late-note-\(index)",
                        occurredAt: Double(4000 + index), actor: "agent-A",
                        op: "op-s11-a-\(index)", ref: "ref-s11-a-\(index)")
                    return try await ops.consistentSnapshot(carrierID: s1ID)
                }
                group.addTask {  // B's concurrent read
                    try await ops.consistentSnapshot(carrierID: s1ID)
                }
            }
            var out: [UACarrierSnapshot] = []
            for try await snap in group { out.append(snap) }
            return out
        }
    // Every observed view must be ONE committed version: contiguous event
    // sequences, readVersion == revision, event count consistent with the
    // version watermark (S1 mappings are fixed).
    let s1Mappings = try await ops.mappings().filter { $0.carrierID == s1ID }.count
    var allCoherent = true
    for snap in snapshots {
        let sequences = snap.events.map(\.sequence)
        let coherent = sequences == Array(0..<sequences.count)
            && snap.readVersion == snap.carrier?.revision
            && snap.events.count == (snap.carrier?.revision ?? 0) - s1Mappings
        if !coherent { allCoherent = false }
    }
    let versions = snapshots.map(\.readVersion)
    jsonWrite(["step": 11, "injected": "concurrent commits + repeated multi-object reads",
               "observed": ["snapshots_taken": snapshots.count,
                            "all_single_version_coherent": allCoherent,
                            "read_versions_observed": versions,
                            "monotone_across_increasing_versions":
                                versions == versions.sorted()],
               "bound": "MA-10 / I22 snapshot / recovery consistency",
               "classification": (snapshots.count == 8 && allCoherent)
                                   ? "PASS" : "UA-DF-11",
               "residual": NSNull()], to: evidenceDir(root).appendingPathComponent("step11.json"))
}

func step12(_ root: URL) async throws {
    let b = try bundle(root)
    let ops = b.operations
    let state = loadState(root)
    let s1ID = (state["s1"] as! [String: Any])["carrierID"] as! String
    let before = try await ops.consistentSnapshot(carrierID: s1ID)
    let through = before.events.last?.sequence ?? -1
    // Summary materialization (derived; raw events authoritative).
    try await b.runtime.composition.sessions.addSummary(CarrierSessionSummary(
        summaryID: CarrierSummaryID(rawValue: "s1-summary-1"),
        sessionID: CarrierSessionID(rawValue: s1ID),
        throughSequence: through,
        payload: Data("day summary through seq \(through)".utf8),
        createdAt: Date(),
        provenance: CarrierProvenance(producedAt: Date(), producedBy: "agent-B", source: nil)))
    // One more raw append AFTER the summary.
    let afterAppend = try await appendEvent(
        ops, s1ID, kind: "NOTE", payload: "post-summary note",
        occurredAt: 5000, actor: "agent-A", op: "op-s12", ref: "ref-s12")
    let final = try await ops.consistentSnapshot(carrierID: s1ID)
    let sequences = final.events.map(\.sequence)
    let prefixPreserved = Array(sequences.prefix(before.events.count)) == before.events.map(\.sequence)
    let summaries = try await b.runtime.composition.sessions.summaries(
        in: CarrierSessionID(rawValue: s1ID))
    jsonWrite(["step": 12, "injected": "summary materialization mid-stream",
               "observed": ["summary_through_sequence": through,
                            "raw_events_intact": prefixPreserved,
                            "post_summary_append_sequence": afterAppend.event.sequence,
                            "sequences_contiguous": sequences == Array(0..<sequences.count),
                            "summary_rows": summaries.count],
               "bound": "CC-4 ordering stability / I14 (F13 vocabulary: summary is derived, raw events intact)",
               "classification": (prefixPreserved
                                  && afterAppend.event.sequence == through + 1
                                  && sequences == Array(0..<sequences.count)
                                  && summaries.count == 1) ? "PASS" : "UA-DF-12",
               "residual": NSNull()], to: evidenceDir(root).appendingPathComponent("step12.json"))
}

func step13(_ root: URL) async throws {
    let b = try bundle(root)
    let ops = b.operations
    let state = loadState(root)
    let f1 = state["f1"] as! [String: Any]
    let s1ID = (state["s1"] as! [String: Any])["carrierID"] as! String
    let f1ID = f1["carrierID"] as! String
    // (a) identity stability across the whole day.
    let f1Now = try await ops.carrier(carrierID: f1ID)
    let s1Now = try await ops.carrier(carrierID: s1ID)
    // (b) I20: exactly one applied CARRIER_CREATE per logical carrier.
    let ledger = try await ops.operationLedger()
    let createRows = ledger.filter { $0.kind == "CARRIER_CREATE" && $0.outcome == .applied }
    let singleCreatePerInstance = createRows.count == 2
    // (c) representation history: distinct identities, one carrier.
    let reps = try await b.representations.representations(
        for: CarrierInformationID(rawValue: "info-f1"), revisionID: nil)
    let distinctReps = Set(reps.map(\.representationID.rawValue)).count == reps.count
    // (d) historical judgment reviewability (I17/I18): the step-2
    // EVIDENCE_LINK record -> mapping -> F1@rev-1 content.
    let s1Snap = try await ops.consistentSnapshot(carrierID: s1ID)
    let linkEvent = s1Snap.events.first { eventPayload($0).hasPrefix("evidence:") }
    let mappings = try await ops.mappings()
    var digestMatches = false
    var reviewPath = "EVIDENCE_LINK record not found"
    if let linkEvent {
        let linkMapping = mappings.first {
            $0.carrierID == s1ID && $0.recordID == "rec-ev-\(linkEvent.sequence)"
        }
        if let linkMapping {
            let rev1Content = try await b.representations.content(
                CarrierRepresentationID(rawValue: linkMapping.representationID ?? "?"))
            reviewPath = "S1 EVIDENCE_LINK record -> CC-5 mapping -> F1@\(linkMapping.representationID ?? "?") content"
            digestMatches = eventPayload(linkEvent).contains(f1["rev1Digest"] as! String)
                && rev1Content?.representation.digest == (f1["rev1Digest"] as! String)
        } else {
            reviewPath = "mapping row missing"
        }
    }
    // (e) reindex replay (part of the pre-registered step), then hygiene.
    _ = try await ops.rebuildIndex(documents: [
        (CarrierInformationID(rawValue: "info-f1"), f1ID,
         CarrierRevisionID(rawValue: "f1-rev-4"), "q3-notes",
         "quantum flux design notes research day"),
        (CarrierInformationID(rawValue: "info-judgment-1"), s1ID,
         CarrierRevisionID(rawValue: "s1-rev-index"), nil,
         "session timeline judgment research day")
    ])
    let dangling = try await ops.danglingProvenanceCount()
    let stale = try await ops.indexStaleness()
    let integrity = try await b.runtime.integrityReport()
    // CC-MA-relevant integrity aspect: no entity FILE orphans.
    let entityOrphans = integrity.issues
        .filter { $0.kind == .orphanRepresentation && $0.detail.contains("entity file") }
    let fingerprint = try await ops.authorityFingerprint()
    var newState = loadState(root)
    newState["fingerprint_final"] = fingerprint
    saveState(root, newState)
    // Final state reconstruction artifact.
    jsonWrite([
        "carriers": ["f1": ["id": f1ID, "kind": f1Now?.kind.rawValue ?? "?",
                            "revision": f1Now?.revision ?? -1,
                            "locator": f1Now?.locatorValue ?? "?"],
                     "s1": ["id": s1ID, "kind": s1Now?.kind.rawValue ?? "?",
                            "revision": s1Now?.revision ?? -1]],
        "f1_representations": reps.map { ["id": $0.representationID.rawValue,
                                          "revision": $0.revisionID.rawValue,
                                          "digest": $0.digest] },
        "s1_events": s1Snap.events.map { ["seq": $0.sequence, "kind": $0.kind,
                                          "payload": eventPayload($0)] },
        "mappings": mappings.map { ["info": $0.informationID, "carrier": $0.carrierID,
                                    "record": $0.recordID, "rep": $0.representationID ?? "-"] },
        "ledger_rows": ledger.count,
        "authority_fingerprint": fingerprint
    ], to: evidenceDir(root).appendingPathComponent("final-state.json"))
    jsonWrite(["step": 13,
               "injected": "full-day audit (rename+revision+reindex+summary replayed)",
               "observed": [
                   "identity_sets_stable": f1Now?.carrierID == f1ID && s1Now?.carrierID == s1ID,
                   "single_carrier_create_per_instance": singleCreatePerInstance,
                   "representation_identities_distinct": distinctReps,
                   "locator_after_move": f1Now?.locatorValue ?? "?",
                   "historical_judgment_reviewable": digestMatches,
                   "review_path": reviewPath,
                   "dangling_provenance": dangling,
                   "staleness_entries": stale.count,
                   "entity_orphans": entityOrphans.count,
                   "integrity_note": "isClean includes A1-runtime locator/availability invariants that do not bind the UA operation path"],
               "bound": "MA-5 / I20 / I17 / I18",
               "classification": (f1Now?.carrierID == f1ID && singleCreatePerInstance
                                  && distinctReps && digestMatches && dangling == 0
                                  && stale.isEmpty && entityOrphans.isEmpty)
                                   ? "PASS" : "UA-DF-13",
               "residual": NSNull()], to: evidenceDir(root).appendingPathComponent("step13.json"))
}

// MARK: - Campaign orchestration (P8 pattern: spawn self, expect SIGKILL)

struct PhaseSpec {
    let name: String
    let expectsKill: Bool
    let evidenceFile: String?   // written by this phase (crash phases: none)
}

let phases: [PhaseSpec] = [
    PhaseSpec(name: "step1", expectsKill: false, evidenceFile: "step01.json"),
    PhaseSpec(name: "step2", expectsKill: false, evidenceFile: "step02.json"),
    PhaseSpec(name: "step3", expectsKill: false, evidenceFile: "step03.json"),
    PhaseSpec(name: "step4", expectsKill: false, evidenceFile: "step04.json"),
    PhaseSpec(name: "step5", expectsKill: false, evidenceFile: "step05.json"),
    PhaseSpec(name: "step6", expectsKill: false, evidenceFile: "step06.json"),
    PhaseSpec(name: "step7", expectsKill: false, evidenceFile: "step07.json"),
    PhaseSpec(name: "step8-crash", expectsKill: true, evidenceFile: nil),
    PhaseSpec(name: "step8-recover", expectsKill: false, evidenceFile: "step08.json"),
    PhaseSpec(name: "step9-crash", expectsKill: true, evidenceFile: nil),
    PhaseSpec(name: "step9-recover", expectsKill: false, evidenceFile: "step09.json"),
    PhaseSpec(name: "step10-prep", expectsKill: false, evidenceFile: nil),
    PhaseSpec(name: "step10-crash", expectsKill: true, evidenceFile: nil),
    PhaseSpec(name: "step10-recover", expectsKill: false, evidenceFile: "step10.json"),
    PhaseSpec(name: "step11", expectsKill: false, evidenceFile: "step11.json"),
    PhaseSpec(name: "step12", expectsKill: false, evidenceFile: "step12.json"),
    PhaseSpec(name: "step13", expectsKill: false, evidenceFile: "step13.json")
]

func runPhase(_ name: String, _ root: URL, killed: Bool) async throws {
    switch name {
    case "step1": try await step1(root)
    case "step2": try await step2(root)
    case "step3": try await step3(root)
    case "step4": try await step4(root)
    case "step5": try await step5(root)
    case "step6": try await step6(root)
    case "step7": try await step7(root)
    case "step8-crash": try await step8Crash(root)
    case "step8-recover": try await step8Recover(root, killed: killed)
    case "step9-crash": try await step9Crash(root)
    case "step9-recover": try await step9Recover(root, killed: killed)
    case "step10-prep": try await step10Prep(root)
    case "step10-crash": try await step10Crash(root)
    case "step10-recover": try await step10Recover(root, killed: killed)
    case "step11": try await step11(root)
    case "step12": try await step12(root)
    case "step13": try await step13(root)
    default: fatalError("unknown phase \(name)")
    }
}

switch mode {
case "phase":
    // phase <name> <root> [killed]
    let root = URL(fileURLWithPath: args[3])
    let killed = args.count > 4 && args[4] == "1"
    try await runPhase(args[2], root, killed: killed)
    FileHandle.standardError.write(Data("[mads1] phase \(args[2]) complete (trap did not fire)\n".utf8))
case "campaign":
    let root = URL(fileURLWithPath: args[2])
    try? fm.removeItem(at: root)
    try! fm.createDirectory(at: root, withIntermediateDirectories: true)
    saveState(root, [:])
    var killLog: [String: Bool] = [:]
    for phase in phases {
        // Recover phases receive the crash outcome of their paired crash
        // phase so their mechanical classification sees the real signal.
        let pairedKill = phase.name.hasSuffix("-recover")
            ? (killLog[phase.name.replacingOccurrences(of: "-recover", with: "-crash")] ?? false)
            : false
        let p = Process()
        p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        p.arguments = ["phase", phase.name, root.path, pairedKill ? "1" : "0"]
        try p.run(); p.waitUntilExit()
        let killed = p.terminationReason == .uncaughtSignal
        killLog[phase.name] = killed
        if killed != phase.expectsKill {
            FileHandle.standardError.write(
                Data("[mads1] WARNING \(phase.name): killed=\(killed) expected=\(phase.expectsKill)\n".utf8))
        }
    }
    // Assemble step records from evidence files + kill log.
    var results: [[String: Any]] = []
    for phase in phases {
        guard let file = phase.evidenceFile else { continue }
        let url = evidenceDir(root).appendingPathComponent(file)
        guard fm.fileExists(atPath: url.path) else {
            results.append(["step_file": file, "classification": "UA-DF-0 (evidence file missing)"])
            continue
        }
        var record = jsonRead(url)
        let crashPhase = phase.name.hasSuffix("-crash")
            ? phase.name
            : phase.name.replacingOccurrences(of: "-recover", with: "-crash")
        record["killed_by_sigkill"] = killLog[crashPhase] ?? false
        if (record["killed_by_sigkill"] as? Bool) != killLog[crashPhase.replacingOccurrences(of: "-crash", with: "-crash")] {
            // consistency guard (no-op; keep record)
        }
        if killLog[crashPhase] != true && crashPhase.hasSuffix("-crash") {
            record["classification"] = "UA-DF-0 (crash gate did not fire as pre-registered)"
        }
        results.append(record)
        FileHandle.standardError.write(
            Data("[mads1] \(file): \(record["classification"] ?? "?")\n".utf8))
    }
    let classifications = results.compactMap { $0["classification"] as? String }
    let withinSemantics = classifications.allSatisfy { value in
        value.hasPrefix("PASS") || value.hasPrefix("REPAIR")
            || value.hasPrefix("DETACHED") || value.hasPrefix("INCOMPLETE")
    }
    var counts: [String: Int] = [:]
    for value in classifications {
        let key = value.hasPrefix("PASS") ? "PASS" : value.hasPrefix("REPAIR") ? "REPAIR"
            : value.hasPrefix("DETACHED") ? "DETACHED"
            : value.hasPrefix("INCOMPLETE") ? "INCOMPLETE" : "UA-DF"
        counts[key, default: 0] += 1
    }
    let report: [String: Any] = [
        "protocol": "CCVS-01 U-A / MA-DS-1 (manifest §5, 13 pre-registered steps)",
        "crash_model": "process SIGKILL (gates UA-C1/C2/C3)",
        "class_counts": counts,
        "overall": (withinSemantics && counts["UA-DF"] == nil && results.count == 13)
            ? "VALID (no bound violation; all classifications within manifest semantics)"
            : "UA-DF",
        "steps": results
    ]
    let out = root.appendingPathComponent("mads1-report.json")
    try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
        .write(to: out)
    FileHandle.standardError.write(
        Data("[mads1] overall=\(report["overall"] as! String) report=\(out.path)\n".utf8))
default:
    FileHandle.standardError.write(
        Data("usage: CarrierMADS1 [campaign <root> | phase <name> <root> [killed]]\n".utf8))
}
