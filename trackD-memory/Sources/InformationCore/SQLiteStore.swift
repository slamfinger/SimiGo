// Information Core — `SQLiteStore`, the physical persistence boundary.
//
// Owns (C1/C4/A2′):
//   - the storage schema
//   - the identity recipe mechanism (mechanism-side minting)
//   - verbatim content storage (C3)
//   - physical filing metadata (wing/room — C2: filing, never semantics)
//
// Never exposes (C1/C5):
//   - WAL, transactions, connections, normalization internals

import CryptoKit
import Foundation
import SQLite3

/// Physical filing metadata (C2). Purely organizational: the service
/// files Information under wing/room drawers. These values are *not*
/// properties of Information and never surface on `Information`.
public struct PhysicalFiling: Hashable, Sendable {
    public let wing: String
    public let room: String

    public init(wing: String, room: String) {
        self.wing = wing
        self.room = room
    }
}

/// Storage failure. Absence is *not* represented by this type (B3).
public enum StorageError: Error, Hashable {
    case openFailed(code: Int32, message: String)
    case sqlite(code: Int32, message: String)
}

/// SQLite-backed `InformationStore`.
///
/// Verbatim guarantee (C3): `Information.content` goes to a TEXT column
/// and back unchanged. The store never rewrites content for
/// normalization, indexing or deduplication.
///
/// Identity recipe note (mechanism-side): the minting recipe is fixed by
/// this implementation (length-prefixed delimiter join + SHA-256, the
/// collision-safe pattern of the service tree's ids recipe) and is
/// invisible above this layer. Cross-recipe identity equivalence is a
/// registered mechanism-side legacy concern, out of Phase 1 scope.
public final class SQLiteStore: InformationStore {
    /// Opaque SQLite handle. Never exposed (C1).
    private var handle: OpaquePointer?
    private let filing: PhysicalFiling?

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Opens (creating if needed) the store at `path`.
    ///
    /// - Parameters:
    ///   - path: SQLite database file path.
    ///   - filing: optional physical filing metadata written alongside
    ///     stored Information (C2). Purely organizational.
    public init(path: String, filing: PhysicalFiling? = nil) throws {
        self.filing = filing
        var database: OpaquePointer?
        guard sqlite3_open(path, &database) == SQLITE_OK else {
            let code = sqlite3_errcode(database)
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close_v2(database)
            throw StorageError.openFailed(code: code, message: message)
        }
        handle = database
        try execute(
            """
            CREATE TABLE IF NOT EXISTS information (
                identity            TEXT PRIMARY KEY,
                content             TEXT NOT NULL,
                produced_at         TEXT NOT NULL,
                produced_by         TEXT NOT NULL,
                source              TEXT,
                source_time         TEXT,
                chunk_index         INTEGER,
                line_start          INTEGER,
                line_end            INTEGER,
                extraction_mode     TEXT,
                content_date        TEXT,
                content_date_source TEXT,
                filing_wing         TEXT,
                filing_room         TEXT
            )
            """
        )
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    // MARK: - InformationStore

    /// Idempotent by identity (B2): `INSERT OR IGNORE` on the primary
    /// key makes a re-store a successful no-op; a stored row is never
    /// modified (A1/C3).
    public func store(_ information: Information) throws {
        let statement = try prepare(
            """
            INSERT OR IGNORE INTO information (
                identity, content, produced_at, produced_by,
                source, source_time, chunk_index, line_start, line_end,
                extraction_mode, content_date, content_date_source,
                filing_wing, filing_room
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }

        let provenance = information.provenance
        try bind(statement, index: 1, text: information.identity.rawValue)
        try bind(statement, index: 2, text: information.content) // verbatim (C3)
        try bind(statement, index: 3, text: Self.iso8601.string(from: provenance.producedAt))
        try bind(statement, index: 4, text: provenance.producedBy)
        try bindOptionalText(statement, index: 5, value: provenance.source)
        try bindOptionalDate(statement, index: 6, value: provenance.sourceTime)
        if let position = provenance.position {
            sqlite3_bind_int(statement, 7, Int32(position.chunkIndex))
            bindOptionalInt(statement, index: 8, value: position.lineStart)
            bindOptionalInt(statement, index: 9, value: position.lineEnd)
        } else {
            sqlite3_bind_null(statement, 7)
            sqlite3_bind_null(statement, 8)
            sqlite3_bind_null(statement, 9)
        }
        try bindOptionalText(statement, index: 10, value: provenance.extractionMode)
        if let temporal = information.temporal {
            try bind(statement, index: 11, text: temporal.iso8601)
            try bind(statement, index: 12, text: sourceName(temporal.source))
        } else {
            sqlite3_bind_null(statement, 11)
            sqlite3_bind_null(statement, 12)
        }
        if let filing {
            try bind(statement, index: 13, text: filing.wing)
            try bind(statement, index: 14, text: filing.room)
        } else {
            sqlite3_bind_null(statement, 13)
            sqlite3_bind_null(statement, 14)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw storageError(statement)
        }
    }

    /// Absence is nil (B3); storage failure throws — the two are never
    /// conflated.
    public func fetch(by identity: InformationID) throws -> Information? {
        let statement = try prepare("SELECT * FROM information WHERE identity = ?")
        defer { sqlite3_finalize(statement) }
        try bind(statement, index: 1, text: identity.rawValue)
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            return information(from: statement)
        }
        guard result == SQLITE_DONE else {
            throw storageError(statement)
        }
        return nil // absence, not failure (B3)
    }

    // MARK: - Mechanism-side identity minting (A2′)

    /// Mints the identity for an Information being formed, from its
    /// formation facts. This is the sanctioned formation path:
    /// facts + context → InformationID → immutable Information.
    ///
    /// The recipe is mechanism; callers never see how the value is
    /// computed, only receive the resulting identity.
    public func makeInformationID(content: String, provenance: Provenance) -> InformationID {
        // Length-prefixed, delimiter-joined inputs: collision-safe by
        // construction (the same pattern the service tree adopted for
        // its v3 recipe), truncated to the drawer-hash length observed
        // in the service tree.
        let parts = [
            content,
            provenance.source ?? "",
            String(provenance.position?.chunkIndex ?? 0),
        ]
        let key = parts.map { "\($0.utf8.count):\($0)" }.joined()
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return InformationID(rawValue: String(hex.prefix(24)))
    }

    // MARK: - Internals (never part of any API surface)

    private func sourceName(_ source: ContentDateSource) -> String {
        switch source {
        case .filename: return "filename"
        case .frontmatter: return "frontmatter"
        case .body: return "body"
        case .mtime: return "mtime"
        case .unknown: return "unknown"
        }
    }

    private func sourceFrom(name: String) -> ContentDateSource {
        switch name {
        case "filename": return .filename
        case "frontmatter": return .frontmatter
        case "body": return .body
        case "mtime": return .mtime
        default: return .unknown
        }
    }

    private func execute(_ sql: String) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw storageError(statement)
        }
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

    private func bindOptionalText(_ statement: OpaquePointer, index: Int32, value: String?) throws {
        if let value {
            try bind(statement, index: index, text: value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindOptionalDate(_ statement: OpaquePointer, index: Int32, value: Date?) throws {
        if let value {
            try bind(statement, index: index, text: Self.iso8601.string(from: value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindOptionalInt(_ statement: OpaquePointer, index: Int32, value: Int?) {
        if let value {
            sqlite3_bind_int(statement, index, Int32(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func storageError(_ statement: OpaquePointer?) -> StorageError {
        let code = sqlite3_errcode(handle)
        let message = String(cString: sqlite3_errmsg(handle))
        return StorageError.sqlite(code: code, message: message)
    }

    private func information(from statement: OpaquePointer) -> Information {
        func text(_ column: Int32) -> String? {
            guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
            guard let cString = sqlite3_column_text(statement, column) else { return nil }
            return String(cString: cString)
        }
        func integer(_ column: Int32) -> Int? {
            guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
            return Int(sqlite3_column_int64(statement, column))
        }
        func date(_ column: Int32) -> Date? {
            text(column).flatMap { Self.iso8601.date(from: $0) }
        }

        let identity = InformationID(rawValue: text(0) ?? "")
        let content = text(1) ?? "" // stored verbatim; returned verbatim (C3)
        let provenance = Provenance(
            producedAt: date(2) ?? Date(),
            producedBy: text(3) ?? "",
            source: text(4),
            sourceTime: date(5),
            position: integer(6).map { chunkIndex in
                SourcePosition(chunkIndex: chunkIndex, lineStart: integer(7), lineEnd: integer(8))
            },
            extractionMode: text(9)
        )
        let temporal: ContentDate?
        if let recordedDate = text(10) {
            temporal = ContentDate(iso8601: recordedDate, source: sourceFrom(name: text(11) ?? "unknown"))
        } else {
            temporal = nil
        }
        // Filing columns (12, 13) are physical metadata only; they are
        // deliberately NOT read back onto Information (C2).
        return Information(
            identity: identity,
            content: content,
            provenance: provenance,
            temporal: temporal
        )
    }
}

/// SQLite argument destructor: tells SQLite to copy bound text.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
