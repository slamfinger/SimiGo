// Integration Boundary Gate — Backend-1 for the Relation persistence
// semantics contract (R1–R6): SQLite-backed RelationStore.
//
// Harness/test-side placement per gate spec: this proves contract
// conformance, not production readiness. It depends ONLY on the public
// RelationCore surface — the RelationCore module itself is untouched.
// No query, traversal, ranking, retrieval or taxonomy capability exists
// here; storage failure throws, absence is nil (R5/R6).

import Foundation
import InformationCore
import SQLite3
import RelationCore

public final class SQLiteRelationStore: RelationStore {
    private var handle: OpaquePointer?

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public init(path: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(path, &database) == SQLITE_OK else {
            let code = sqlite3_errcode(database)
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close_v2(database)
            throw RelationStorageError.sqlite(code: Int(code), message: message)
        }
        handle = database
        let statement = try prepare(
            """
            CREATE TABLE IF NOT EXISTS relation (
                identity     TEXT PRIMARY KEY,
                subject      TEXT NOT NULL,
                predicate    TEXT NOT NULL,
                object       TEXT NOT NULL,
                produced_at  TEXT NOT NULL,
                produced_by  TEXT NOT NULL
            )
            """
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw storageError(statement)
        }
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// R1/R2/R3: idempotent by identity — `INSERT OR IGNORE` on the
    /// primary key makes every re-store a successful no-op (same or
    /// conflicting Relation alike); the stored Relation is never
    /// modified (first-write-wins).
    public func store(_ relation: Relation) throws {
        let statement = try prepare(
            """
            INSERT OR IGNORE INTO relation (
                identity, subject, predicate, object, produced_at, produced_by
            ) VALUES (?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(statement, index: 1, text: relation.identity.rawValue)
        try bind(statement, index: 2, text: relation.subject.rawValue)
        try bind(statement, index: 3, text: relation.predicate.value)
        try bind(statement, index: 4, text: relation.object.rawValue)
        try bind(statement, index: 5, text: Self.iso8601.string(from: relation.provenance.producedAt))
        try bind(statement, index: 6, text: relation.provenance.producedBy)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw storageError(statement)
        }
    }

    /// R4/R5: present → Relation; absent → nil. R6: storage failure
    /// throws — never conflated with absence.
    public func fetch(by identity: RelationID) throws -> Relation? {
        let statement = try prepare(
            """
            SELECT subject, predicate, object, produced_at, produced_by
            FROM relation WHERE identity = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(statement, index: 1, text: identity.rawValue)
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            func text(_ column: Int32) -> String {
                guard let cString = sqlite3_column_text(statement, column) else { return "" }
                return String(cString: cString)
            }
            let subject = InformationID(rawValue: text(0))
            let predicate = RelationPredicate(value: text(1))
            let object = InformationID(rawValue: text(2))
            let producedAt = Self.iso8601.date(from: text(3)) ?? Date()
            let provenance = Provenance(producedAt: producedAt, producedBy: text(4))
            return Relation(
                identity: identity,
                subject: subject,
                predicate: predicate,
                object: object,
                provenance: provenance
            )
        }
        guard result == SQLITE_DONE else {
            throw storageError(statement)
        }
        return nil // absence, not failure (R5)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, statement != nil else {
            throw storageError(statement)
        }
        return statement!
    }

    private func bind(_ statement: OpaquePointer, index: Int32, text: String) throws {
        guard sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw storageError(statement)
        }
    }

    private func storageError(_ statement: OpaquePointer?) -> RelationStorageError {
        let code = sqlite3_errcode(handle)
        let message = String(cString: sqlite3_errmsg(handle))
        return RelationStorageError.sqlite(code: Int(code), message: message)
    }
}

/// Storage failure for the Relation boundary. Absence is *not*
/// represented by this type (R5).
public enum RelationStorageError: Error, Hashable {
    case sqlite(code: Int, message: String)
}

/// SQLite argument destructor: tells SQLite to copy bound text.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
