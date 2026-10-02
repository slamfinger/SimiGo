// R-B1 execution harness. Each CLI invocation is one fresh process and
// one declared run shape. It performs boundary operations only; the
// orchestration supplies declared physical observations and performs the
// actual external S0 → S1 file change between processes.

import ExecutionCore
import Foundation
import InformationCore
import RelationCore
import SQLite3

private let clock: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

private enum HarnessRelationStorageError: Error {
    case sqlite(code: Int32, message: String)
}

/// A process-local SQLite RelationStore backend outside both frozen Cores.
private final class HarnessRelationStore: RelationStore {
    private var handle: OpaquePointer?

    init(path: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(path, &database) == SQLITE_OK else {
            let code = sqlite3_errcode(database)
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close_v2(database)
            throw HarnessRelationStorageError.sqlite(code: code, message: message)
        }
        handle = database
        try execute(
            """
            CREATE TABLE IF NOT EXISTS relation (
                identity TEXT PRIMARY KEY,
                subject TEXT NOT NULL,
                predicate TEXT NOT NULL,
                object TEXT NOT NULL,
                produced_at TEXT NOT NULL,
                produced_by TEXT NOT NULL
            )
            """
        )
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    func store(_ relation: Relation) throws {
        let statement = try prepare(
            """
            INSERT OR IGNORE INTO relation (
                identity, subject, predicate, object, produced_at, produced_by
            ) VALUES (?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(statement, 1, relation.identity.rawValue)
        try bind(statement, 2, relation.subject.rawValue)
        try bind(statement, 3, relation.predicate.value)
        try bind(statement, 4, relation.object.rawValue)
        try bind(statement, 5, clock.string(from: relation.provenance.producedAt))
        try bind(statement, 6, relation.provenance.producedBy)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw error(statement)
        }
    }

    func fetch(by identity: RelationID) throws -> Relation? {
        let statement = try prepare(
            """
            SELECT subject, predicate, object, produced_at, produced_by
            FROM relation WHERE identity = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(statement, 1, identity.rawValue)
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            func text(_ column: Int32) -> String {
                guard let value = sqlite3_column_text(statement, column) else { return "" }
                return String(cString: value)
            }
            guard let producedAt = clock.date(from: text(3)) else {
                throw HarnessRelationStorageError.sqlite(code: SQLITE_MISMATCH, message: "invalid produced_at")
            }
            return Relation(
                identity: identity,
                subject: InformationID(rawValue: text(0)),
                predicate: RelationPredicate(value: text(1)),
                object: InformationID(rawValue: text(2)),
                provenance: Provenance(producedAt: producedAt, producedBy: text(4))
            )
        }
        guard result == SQLITE_DONE else {
            throw error(statement)
        }
        return nil
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw HarnessRelationStorageError.sqlite(
                code: sqlite3_errcode(handle),
                message: String(cString: sqlite3_errmsg(handle))
            )
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, statement != nil else {
            throw error(statement)
        }
        return statement
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String) throws {
        guard sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw error(statement)
        }
    }

    private func error(_ statement: OpaquePointer?) -> HarnessRelationStorageError {
        HarnessRelationStorageError.sqlite(
            code: sqlite3_errcode(handle),
            message: String(cString: sqlite3_errmsg(handle))
        )
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func escape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
}

private func emit(_ fields: [(String, String)]) {
    let body = fields
        .map { "\"\(escape($0))\":\"\(escape($1))\"" }
        .joined(separator: ",")
    print("{\(body)}")
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("HARNESS_ERROR: \(message)\n".utf8))
    exit(2)
}

private func arguments(_ expected: Int) -> [String] {
    let values = Array(CommandLine.arguments.dropFirst())
    guard values.count == expected else {
        fail("expected \(expected) arguments, got \(values.count)")
    }
    return values
}

private func makeScope(informationPath: String, relationPath: String) throws -> ExecutionScope {
    ExecutionScope(
        informationStore: try SQLiteStore(path: informationPath),
        relationStore: try HarnessRelationStore(path: relationPath)
    )
}

private let date = Date()

private func runBaseline() throws {
    let arguments = arguments(4)
    let database = arguments[0]
    let entitySource = arguments[1]
    let representation = arguments[2]
    let observer = arguments[3]
    let informationStore = try SQLiteStore(path: database)
    let relationStore = try HarnessRelationStore(path: database)
    let scope = ExecutionScope(informationStore: informationStore, relationStore: relationStore)
    let provenance = Provenance(
        producedAt: date,
        producedBy: observer,
        source: entitySource,
        extractionMode: "declared-baseline"
    )
    let identity = informationStore.makeInformationID(content: representation, provenance: provenance)
    let baseline = Information(
        identity: identity,
        content: representation,
        provenance: provenance
    )
    try scope.form(baseline)
    guard try scope.observe(identity) == baseline else {
        fail("baseline readback mismatch")
    }
    emit([
        ("event", "E-run"),
        ("run_id", UUID().uuidString),
        ("pid", String(ProcessInfo.processInfo.processIdentifier)),
        ("timestamp", clock.string(from: date)),
        ("database", database),
        ("before_id", identity.rawValue),
        ("before_content", representation),
        ("source", entitySource),
        ("observer", observer),
        ("boundary_operation", "InformationStore.store"),
    ])
}

private func runObservation() throws {
    let arguments = arguments(5)
    let database = arguments[0]
    let entitySource = arguments[1]
    let beforeID = arguments[2]
    let representation = arguments[3]
    let observer = arguments[4]
    let scope = try makeScope(informationPath: database, relationPath: database)
    let reference = InformationID(rawValue: beforeID)
    guard try scope.observe(reference) != nil else {
        fail("genuine before reference not found")
    }
    let formed = try scope.formObservedChange(
        entitySource: entitySource,
        before: .reference(reference),
        afterRepresentation: representation,
        observer: observer,
        observedAt: date
    )
    emit([
        ("event", "X-run"),
        ("run_id", UUID().uuidString),
        ("pid", String(ProcessInfo.processInfo.processIdentifier)),
        ("timestamp", clock.string(from: date)),
        ("database", database),
        ("before_id", formed.before.identity.rawValue),
        ("after_id", formed.after.identity.rawValue),
        ("relation_id", formed.relation.identity.rawValue),
        ("after_content", formed.after.content),
        ("predicate", formed.relation.predicate.value),
        ("observer", observer),
        ("baseline_path", "ExecutionScope.ObservationBaseline.reference"),
        ("boundary_operation", "fetch-before;store-after;store-relation"),
    ])
}

private func runVerifier() throws {
    let arguments = arguments(3)
    let database = arguments[0]
    let relationID = arguments[1]
    let question = arguments[2]
    let scope = try makeScope(informationPath: database, relationPath: database)
    var fetches: [String] = []

    guard let relation = try scope.observe(RelationID(rawValue: relationID)) else {
        emit([
            ("event", "V-run"),
            ("run_id", UUID().uuidString),
            ("pid", String(ProcessInfo.processInfo.processIdentifier)),
            ("timestamp", clock.string(from: date)),
            ("database", database),
            ("question", question),
            ("fetch_sequence", fetches.joined(separator: "->")),
            ("answer", "null"),
            ("blocker", "relation-not-found"),
        ])
        return
    }
    fetches.append("relation")
    guard relation.predicate.value == "observed-change-of" else {
        fail("unexpected relation predicate")
    }

    guard let after = try scope.observe(relation.subject) else {
        fail("after information not found")
    }
    fetches.append("after")
    guard let before = try scope.observe(relation.object) else {
        fail("before information not found")
    }
    fetches.append("before")

    emit([
        ("event", "V-run"),
        ("run_id", UUID().uuidString),
        ("pid", String(ProcessInfo.processInfo.processIdentifier)),
        ("timestamp", clock.string(from: date)),
        ("database", database),
        ("question", question),
        ("fetch_sequence", fetches.joined(separator: "->")),
        ("before_id", before.identity.rawValue),
        ("after_id", after.identity.rawValue),
        ("before_content", before.content),
        ("after_content", after.content),
        ("answer", "Entity E changed from \(before.content) to \(after.content)."),
        ("blocker", "none"),
    ])
}

do {
    guard let mode = CommandLine.arguments.dropFirst().first else {
        fail("expected mode: baseline | observe | verify")
    }
    switch mode {
    case "baseline":
        try runBaseline()
    case "observe":
        try runObservation()
    case "verify":
        try runVerifier()
    default:
        fail("unknown mode: \(mode)")
    }
} catch {
    fail(String(describing: error))
}
