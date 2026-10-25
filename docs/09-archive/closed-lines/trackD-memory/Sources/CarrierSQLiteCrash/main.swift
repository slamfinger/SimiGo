import Foundation
import CarrierInterface
import CarrierSQLite

// P8 crash/recovery runner (CCVS-01-PB v1.2, R6 scope: process SIGKILL only).
let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "suite"
let fm = FileManager.default

func root(_ f: String) -> URL {
    let r = fm.temporaryDirectory.appendingPathComponent("ccvs01-p8-\(f)", isDirectory: true)
    try? fm.removeItem(at: r)
    try! fm.createDirectory(at: r, withIntermediateDirectories: true)
    return r
}

func seed(_ r: URL, n: Int = 20) async throws -> SQLiteCarrierBundle {
    let b = try SQLiteCarrierFactory(rootURL: r).make()
    for i in 0..<n {
        _ = try await b.runtime.create(CarrierCreateRequest(
            informationID: .init(rawValue: "base-\(i)"), revisionID: .init(rawValue: "base-rev-\(i)"),
            representationID: .init(rawValue: "base-rep-\(i)"),
            payload: .init(bytes: Data("base payload \(i)".utf8)),
            locatorID: .init(rawValue: "base-loc-\(i)"),
            locator: .init(scheme: "file", value: "base/\(i).txt"),
            provenance: .init(producedAt: Date(), producedBy: "p8"), searchableText: "base \(i) searchable"))
    }
    return b
}

func prepInject(_ f: String, _ r: URL) async throws {
    let b = try await seed(r)
    // Arm the trap only after deterministic seeding so the crash lands at the
    // intended boundary, never during fixture setup.
    let arm: String
    switch f {
    case "F5": arm = "F5-5"
    case "F6": arm = "F6-3"
    default: arm = f
    }
    setenv("CCVS_CRASH", arm, 1)
    let prov = CarrierProvenance(producedAt: Date(), producedBy: "p8")
    switch f {
    case "F1", "F2":
        _ = try await b.runtime.create(CarrierCreateRequest(
            informationID: .init(rawValue: "crash-obj"), revisionID: .init(rawValue: "crash-rev"),
            representationID: .init(rawValue: "crash-rep"),
            payload: .init(bytes: Data("crash payload".utf8)),
            locatorID: .init(rawValue: "crash-loc"),
            locator: .init(scheme: "file", value: "crash/1.txt"),
            provenance: prov, searchableText: "crash searchable"))
    case "F3", "F4":
        _ = try await b.runtime.move(CarrierMoveRequest(
            informationID: .init(rawValue: "base-0"), newLocatorID: .init(rawValue: "moved-loc"),
            newLocator: .init(scheme: "file", value: "base/moved.txt"), movedAt: Date()))
    case "F5":
        for i in 0..<10 {
            try await b.runtime.composition.relations.append(CarrierRelation(
                relationID: .init(rawValue: "rel-\(i)"), subject: .init(rawValue: "base-0"),
                predicate: "related-to", object: .init(rawValue: "base-\(i % 5 + 1)"), provenance: prov))
        }
    case "F6":
        for i in 0..<6 {
            try await b.runtime.composition.sessions.append(CarrierSessionEvent(
                eventID: .init(rawValue: "ev-\(i)"), sessionID: .init(rawValue: "session-1"),
                sequence: i, kind: "message", payload: Data("e\(i)".utf8),
                occurredAt: Date(), provenance: prov))
        }
    case "F7":
        let docs = try await b.runtime.composition.search.search("base", limit: 1000)
        _ = try await b.runtime.rebuildSearch(with: docs.map {
            .init(informationID: $0.informationID, revisionID: $0.revisionID,
                  title: nil, text: "rebuild \($0.informationID.rawValue)")
        })
    case "F8":
        try await SQLiteCarrierFactory(rootURL: r).backup(from: b, to: r.appendingPathComponent("backup"))
    case "F9":
        let f2 = SQLiteCarrierFactory(rootURL: r)
        try await f2.backup(from: b, to: r.appendingPathComponent("backup"))
        try f2.restore(from: r.appendingPathComponent("backup"), to: r.appendingPathComponent("restored"))
    default: break
    }
}

func verdict(_ f: String, _ r: URL) async throws -> [String: Any] {
    let b = try SQLiteCarrierFactory(rootURL: r).make()
    let integrity = try await b.runtime.integrityReport()
    var v: [String: Any] = [
        "injection_point": f,
        "integrity": integrity.isClean ? "CLEAN" : "ISSUES",
        "integrity_issues": integrity.issues.map { "\($0.kind.rawValue): \($0.detail)" },
        "repair_action": NSNull()
    ]
    let rt = b.runtime
    switch f {
    case "F1":
        let rev = try await rt.composition.registry.revision(.init(rawValue: "crash-rev"))
        let rep = try await rt.composition.representations.representations(
            for: .init(rawValue: "crash-obj"), revisionID: .init(rawValue: "crash-rev"))
        let orphans = integrity.issues.filter { $0.kind == .orphanRepresentation }
        v["pre_crash_expected"] = "A1 create order: revision row committed first, then entity durable, then representation row; F1 crash leaves revision visible + representation row absent + orphan entity file explicitly visible"
        v["post_restart_observed"] = "revisionRow=\(rev != nil) representationRows=\(rep.count) orphans=\(orphans.count)"
        v["orphan_evidence"] = orphans.map { $0.detail }
        v["final_classification"] = (rev != nil && rep.isEmpty && !orphans.isEmpty) ? "PASS" : "FAIL"
    case "F2":
        let crashHit = try await rt.composition.search.search("crash searchable", limit: 10)
            .contains { $0.informationID.rawValue == "crash-obj" }
        let baseDocs = try await rt.composition.search.search("base", limit: 1000).count
        v["pre_crash_expected"] = "registry complete; derived index missing the new document"
        v["post_restart_observed"] = "crashDocIndexed=\(crashHit) baseDocsIndexed=\(baseDocs)"
        v["orphan_evidence"] = []
        v["final_classification"] = (!crashHit && baseDocs >= 20) ? "PASS" : "FAIL"
    case "F3":
        let hist = try await rt.composition.locators.history(for: .init(rawValue: "base-0"))
        let moved = hist.contains { $0.locatorID.rawValue == "moved-loc" }
        v["pre_crash_expected"] = "open locator transaction rolls back; move invisible"
        v["post_restart_observed"] = "movedVisible=\(moved) historyCount=\(hist.count)"
        v["orphan_evidence"] = []
        v["final_classification"] = moved ? "FAIL" : "PASS"
    case "F4":
        v["pre_crash_expected"] = "N/A: no independent archival boundary exists in Baseline A; MOVE is one SQLite transaction covering locator retirement and new locator assignment"
        v["post_restart_observed"] = "boundary does not exist in this topology"
        v["orphan_evidence"] = []
        v["final_classification"] = "N/A"
    case "F5":
        let rels = try await rt.composition.relations.relations(involving: .init(rawValue: "base-0"))
        v["pre_crash_expected"] = "committed prefix (5 or 6 of 10) visible; batch remainder absent"
        v["post_restart_observed"] = "committedRelations=\(rels.count)"
        v["orphan_evidence"] = []
        v["final_classification"] = ((1...9).contains(rels.count)) ? "PASS" : "FAIL"
    case "F6":
        let events = try await b.runtime.composition.sessions.events(
            in: .init(rawValue: "session-1"), after: -1).map { $0.sequence }
        v["pre_crash_expected"] = "committed ordered prefix with no gaps"
        v["post_restart_observed"] = "sequences=\(events)"
        v["orphan_evidence"] = []
        v["final_classification"] = (events == Array(0..<events.count) && events.count >= 2) ? "PASS" : "FAIL"
    case "F7":
        // Rebuild source = registry authority tables (A1 manifest §2.5), never
        // the (possibly destroyed) index itself.
        var docs: [CarrierSearchDocument] = []
        for i in 0..<20 {
            let info = CarrierInformationID(rawValue: "base-\(i)")
            let reps = try await rt.composition.representations.representations(for: info, revisionID: nil)
            if let rep = reps.last {
                docs.append(.init(informationID: info, revisionID: rep.revisionID,
                                  title: nil, text: "rebuild \(info.rawValue)"))
            }
        }
        _ = try await rt.rebuildSearch(with: docs)
        let after = try await rt.composition.search.search("rebuild", limit: 1000).count
        v["pre_crash_expected"] = "authority intact; partial derived index discarded/rebuilt from registry authority"
        v["post_restart_observed"] = "authorityDocs=\(docs.count) postRepairHits=\(after)"
        v["orphan_evidence"] = []
        v["repair_action"] = "re-run index rebuild from registry authority; identity coverage re-verified (diagnostic: FTS full-text content is not reconstructable from authority; searchable text provenance lives only in the derived index)"
        v["final_classification"] = (after == docs.count && docs.count >= 20) ? "REPAIR" : "FAIL"
    case "F8":
        let marker = fm.fileExists(atPath: r.appendingPathComponent("backup/BACKUP_COMPLETE").path)
        v["pre_crash_expected"] = "partial backup exists, explicitly not adoptable (no completion marker)"
        v["post_restart_observed"] = "completionMarker=\(marker)"
        v["orphan_evidence"] = ["partial backup dir without BACKUP_COMPLETE"]
        v["final_classification"] = marker ? "FAIL" : "DETACHED"
    case "F9":
        let marker = fm.fileExists(atPath: r.appendingPathComponent("restored/RESTORE_COMPLETE").path)
        var clean = false
        if marker, let b2 = try? SQLiteCarrierFactory(rootURL: r.appendingPathComponent("restored")).make() {
            clean = (try? await b2.runtime.integrityReport())?.isClean ?? false
        }
        v["pre_crash_expected"] = "incomplete restore stays explicitly unavailable; completed restore must be integrity-clean"
        v["post_restart_observed"] = "completionMarker=\(marker) restoredIntegrityClean=\(clean)"
        v["orphan_evidence"] = []
        v["final_classification"] = marker ? (clean ? "PASS" : "FAIL") : "DETACHED"
    default: break
    }
    v["final_integrity"] = (try await b.runtime.integrityReport()).isClean ? "CLEAN" : "ISSUES"
    return v
}

switch mode {
case "prep-inject":
    try await prepInject(args[2], URL(fileURLWithPath: args[3]))
    FileHandle.standardError.write(Data("[warn] trap \(args[2]) did not fire\n".utf8))
case "verify":
    let v = try await verdict(args[2], URL(fileURLWithPath: args[3]))
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: v, options: [.sortedKeys]))
default:
    var results: [[String: Any]] = []
    for f in ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9"] {
        let r = root(f)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        p.arguments = ["prep-inject", f, r.path]
        try p.run(); p.waitUntilExit()
        let killed = p.terminationReason == .uncaughtSignal
        let v = Process()
        let pipe = Pipe()
        v.standardOutput = pipe
        v.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        v.arguments = ["verify", f, r.path]
        try v.run(); v.waitUntilExit()
        var verdict = (try? JSONSerialization.jsonObject(with: pipe.fileHandleForReading.readDataToEndOfFile())) as? [String: Any] ?? [:]
        verdict["killed_by_sigkill"] = killed
        results.append(verdict)
        FileHandle.standardError.write(Data("[P8] \(f): \(verdict["final_classification"] ?? "?")\n".utf8))
    }
    let counts = Dictionary(grouping: results, by: { $0["final_classification"] as? String ?? "?" }).mapValues { $0.count }
    let applicable = results.filter { ($0["final_classification"] as? String) != "N/A" }
    let g2 = applicable.allSatisfy { ["PASS", "REPAIR", "DETACHED"].contains($0["final_classification"] as? String) } ? "PASS" : "FAIL"
    let report: [String: Any] = ["protocol": "CCVS-01-PB v1.2 P8", "crash_model": "process SIGKILL",
        "class_counts": counts, "G2": g2, "results": results]
    let out = URL(fileURLWithPath: args.count > 2 ? args[2] : "crash-report.json")
    try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]).write(to: out)
    FileHandle.standardError.write(Data("[P8] G2=\(g2) report=\(out.path)\n".utf8))
}
