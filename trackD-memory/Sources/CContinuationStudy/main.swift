import Foundation
import InformationCore
import RelationCore

enum Arm: String { case ca = "C-A", cb = "C-B", cc = "C-C" }

struct ES: Codable {
    let taskID: String
    let phase: String
    let progress: String
    let nextAction: String
}

struct Evidence: Codable {
    let command: String
    let arm: String
    let root: String
    let processID: Int32
    let carrierReads: [String]
    let persistenceSources: [String]
    let forbiddenChannelChecks: [String: Bool]
}

struct Report: Codable {
    let taskID: String?
    let beforeState: String?
    let afterState: String?
    let directionalChange: String?
    let nextAction: String?
    let success: Bool
}

struct StoredRelation: Codable {
    let id: String, subject: String, predicate: String, object: String
    let producedAt: Date, producedBy: String, source: String?, extractionMode: String?
    init(_ r: Relation) {
        id = r.identity.rawValue; subject = r.subject.rawValue; predicate = r.predicate.value; object = r.object.rawValue
        producedAt = r.provenance.producedAt; producedBy = r.provenance.producedBy
        source = r.provenance.source; extractionMode = r.provenance.extractionMode
    }
    func value() -> Relation {
        Relation(identity: RelationID(rawValue: id), subject: InformationID(rawValue: subject),
                 predicate: RelationPredicate(value: predicate), object: InformationID(rawValue: object),
                 provenance: Provenance(producedAt: producedAt, producedBy: producedBy,
                                         source: source, extractionMode: extractionMode))
    }
}

final class RelationFileStore: RelationStore {
    let url: URL
    var values: [String: StoredRelation] = [:]
    init(_ url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            values = try JSONDecoder().decode([String: StoredRelation].self, from: Data(contentsOf: url))
        }
    }
    func store(_ r: Relation) throws {
        if values[r.identity.rawValue] == nil {
            values[r.identity.rawValue] = StoredRelation(r)
            try JSONEncoder().encode(values).write(to: url, options: .atomic)
        }
    }
    func fetch(by id: RelationID) throws -> Relation? { values[id.rawValue]?.value() }
}

enum StudyError: Error, CustomStringConvertible {
    case args, forbidden(String), unsupported(String)
    var description: String {
        switch self { case .args: return "invalid arguments"; case .forbidden(let s): return s; case .unsupported(let s): return "unsupported command: \(s)" }
    }
}

final class Study {
    let root: URL
    let arm: Arm
    init(root: URL, arm: Arm) { self.root = root; self.arm = arm }
    var esURL: URL { root.appendingPathComponent("execution-state.json") }
    var infoURL: URL { root.appendingPathComponent("information.sqlite") }
    var relationURL: URL { root.appendingPathComponent("relation.json") }
    var evidenceURL: URL { root.appendingPathComponent("invocation-evidence.jsonl") }

    func prepare() throws -> Evidence {
        try dirs()
        let es = ES(taskID: "C-Q1-fixed", phase: "awaiting-continuation",
                    progress: "S0 observed; external S0→S1 change declared outside runtime",
                    nextAction: "REQUEST_HEALTH_CHECK")
        try write(es, esURL)
        if arm != .ca {
            let s = try SQLiteStore(path: infoURL.path)
            try s.store(info("task", es.taskID))
            try s.store(info("s0", "{\"entity\":\"E\",\"alpha\":17,\"mode\":\"quiet\"}"))
            try s.store(info("progress", es.progress + "|nextAction=" + es.nextAction))
        }
        return evidence("prepare", [])
    }

    func observeAfter() throws -> Evidence {
        guard arm != .ca else { throw StudyError.forbidden("C-A cannot persist Information") }
        let s = try SQLiteStore(path: infoURL.path)
        try s.store(info("s1", "{\"entity\":\"E\",\"alpha\":42,\"mode\":\"active\"}"))
        if arm == .cc {
            let pred = RelationPredicate(value: "observed-change-of")
            let r = Relation(
                identity: RelationMinter.makeRelationID(subject: InformationID(rawValue: "s1"), predicate: pred, object: InformationID(rawValue: "s0")),
                subject: InformationID(rawValue: "s1"), predicate: pred, object: InformationID(rawValue: "s0"),
                provenance: Provenance(producedAt: Date(timeIntervalSinceReferenceDate: 0),
                                        producedBy: "C-Impl-observation",
                                        source: "declared-S1-observation",
                                        extractionMode: "observation"))
            try RelationFileStore(relationURL).store(r)
        }
        return evidence("observe-after", [])
    }

    func continueRun() throws -> (Report, Evidence) {
        let es: ES = try read(esURL)
        var task: String? = es.taskID, before: String?, after: String?, direction: String?
        var reads = ["execution-state"]
        if arm != .ca {
            let s = try SQLiteStore(path: infoURL.path)
            task = try s.fetch(by: InformationID(rawValue: "task"))?.content
            _ = try s.fetch(by: InformationID(rawValue: "progress")); reads += ["information:task","information:progress"]
            before = try s.fetch(by: InformationID(rawValue: "s0"))?.content
            after = try s.fetch(by: InformationID(rawValue: "s1"))?.content
            reads += ["information:s0","information:s1"]
            if let b = before, let a = after { direction = Self.inferDirection(b, a) }
        }
        if arm == .cc {
            let pred = RelationPredicate(value: "observed-change-of")
            let id = RelationMinter.makeRelationID(subject: InformationID(rawValue: "s1"), predicate: pred, object: InformationID(rawValue: "s0"))
            if let r = try RelationFileStore(relationURL).fetch(by: id) {
                reads.append("relation:" + r.identity.rawValue)
                let s = try SQLiteStore(path: infoURL.path)
                if let a = try s.fetch(by: r.subject), let b = try s.fetch(by: r.object) {
                    after = a.content; before = b.content; direction = "after → observed-change-of → before"
                }
            }
        }
        let ok = task == "C-Q1-fixed" && before != nil && after != nil && direction != nil && es.nextAction == "REQUEST_HEALTH_CHECK"
        return (Report(taskID: task, beforeState: before, afterState: after, directionalChange: direction,
                       nextAction: es.nextAction, success: ok),
                evidence("continue", reads))
    }

    func info(_ id: String, _ content: String) -> Information {
        Information(identity: InformationID(rawValue: id), content: content,
                    provenance: Provenance(producedAt: Date(timeIntervalSinceReferenceDate: 0),
                                            producedBy: "C-Impl", source: "declared-C-carrier",
                                            extractionMode: "declared-information"))
    }
    func dirs() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func write<T: Encodable>(_ v: T, _ u: URL) throws { try JSONEncoder().encode(v).write(to: u, options: .atomic) }
    func read<T: Decodable>(_ u: URL) throws -> T { try JSONDecoder().decode(T.self, from: Data(contentsOf: u)) }
    func evidence(_ command: String, _ reads: [String]) -> Evidence {
        var sources = [esURL.path]
        if arm != .ca { sources.append(infoURL.path) }
        if arm == .cc { sources.append(relationURL.path) }
        return Evidence(command: command, arm: arm.rawValue, root: root.path,
                        processID: ProcessInfo.processInfo.processIdentifier, carrierReads: reads,
                        persistenceSources: sources,
                        forbiddenChannelChecks: [
                            "old-runtime-state": false, "model-hidden-context": false,
                            "undeclared-filesystem-scan": false, "environment-as-answer-input": false,
                            "question-answer-injection": false, "implicit-cache": false
                        ])
    }
    static func inferDirection(_ b: String, _ a: String) -> String? {
        guard let before = try? JSONSerialization.jsonObject(with: Data(b.utf8)) as? [String: Any],
              let after = try? JSONSerialization.jsonObject(with: Data(a.utf8)) as? [String: Any],
              before.description != after.description else { return nil }
        return "S0 → S1"
    }
}

@main
struct CContinuationStudy {
    static func main() throws {
        let a = Array(CommandLine.arguments.dropFirst())
        guard a.count >= 3, let arm = Arm(rawValue: a[0]) else { throw StudyError.args }
        let study = Study(root: URL(fileURLWithPath: a[2], isDirectory: true), arm: arm)
        let ev: Evidence
        switch a[1] {
        case "prepare": ev = try study.prepare()
        case "observe-after": ev = try study.observeAfter()
        case "continue":
            let x = try study.continueRun()
            print(String(data: try JSONEncoder().encode(x.0), encoding: .utf8)!)
            ev = x.1
        default: throw StudyError.unsupported(a[1])
        }
        let d = try JSONEncoder().encode(ev) + Data([10])
        if FileManager.default.fileExists(atPath: study.evidenceURL.path) {
            let h = try FileHandle(forWritingTo: study.evidenceURL); try h.seekToEnd(); try h.write(contentsOf: d); try h.close()
        } else { try d.write(to: study.evidenceURL, options: .atomic) }
        FileHandle.standardError.write(d)
    }
}
