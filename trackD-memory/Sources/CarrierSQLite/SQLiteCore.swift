import Foundation
import SQLite3
import CryptoKit
import CarrierInterface

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLiteCarrierError: Error {
    case openFailed(String)
    case sqlFailed(String)
}

/// Single actor owning the SQLite connection. All A1 registry writes are
/// serialized here; the locator retire/assign handoff keeps one IMMEDIATE
/// transaction open across the two protocol calls so a runtime MOVE commits
/// as one atomic locator transition (frozen A1 manifest, I1).
public actor SQLiteCore {
    let db: OpaquePointer
    private var inTransaction = false
    private var moveRetirePending = false

    public init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let opened = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw SQLiteCarrierError.openFailed(message)
        }
        self.db = opened
        try exec("PRAGMA journal_mode=WAL")
        try exec("PRAGMA synchronous=FULL")
        try exec("PRAGMA foreign_keys=ON")
        try createSchema()
    }

    deinit {
        sqlite3_close_v2(db)
    }

    nonisolated private func createSchema() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS revisions(
          revision_id TEXT PRIMARY KEY, information_id TEXT NOT NULL,
          label TEXT, produced_at REAL NOT NULL, produced_by TEXT NOT NULL, source TEXT)
        """)
        try exec("CREATE INDEX IF NOT EXISTS revisions_info ON revisions(information_id)")
        try exec("""
        CREATE TABLE IF NOT EXISTS representations(
          representation_id TEXT PRIMARY KEY, information_id TEXT NOT NULL,
          revision_id TEXT NOT NULL, digest TEXT NOT NULL, byte_count INTEGER NOT NULL,
          media_type TEXT, created_at REAL NOT NULL)
        """)
        try exec("CREATE INDEX IF NOT EXISTS representations_info ON representations(information_id, revision_id)")
        try exec("""
        CREATE TABLE IF NOT EXISTS locators(
          locator_id TEXT PRIMARY KEY, information_id TEXT NOT NULL,
          revision_id TEXT NOT NULL, representation_id TEXT NOT NULL,
          scheme TEXT NOT NULL, value TEXT NOT NULL,
          created_at REAL NOT NULL, retired_at REAL)
        """)
        try exec("CREATE INDEX IF NOT EXISTS locators_info ON locators(information_id)")
        try exec("""
        CREATE TABLE IF NOT EXISTS relations(
          relation_id TEXT PRIMARY KEY, subject TEXT NOT NULL, predicate TEXT NOT NULL,
          object TEXT NOT NULL, produced_at REAL NOT NULL, produced_by TEXT NOT NULL, source TEXT)
        """)
        try exec("CREATE INDEX IF NOT EXISTS relations_subject ON relations(subject)")
        try exec("CREATE INDEX IF NOT EXISTS relations_object ON relations(object)")
        try exec("""
        CREATE TABLE IF NOT EXISTS pins(
          pin_id TEXT PRIMARY KEY, information_id TEXT NOT NULL, revision_id TEXT NOT NULL,
          representation_id TEXT NOT NULL, digest TEXT NOT NULL,
          locator_scheme TEXT, locator_value TEXT, label TEXT, pinned_at REAL NOT NULL)
        """)
        try exec("CREATE INDEX IF NOT EXISTS pins_info ON pins(information_id)")
        try exec("""
        CREATE TABLE IF NOT EXISTS session_events(
          session_id TEXT NOT NULL, sequence INTEGER NOT NULL, event_id TEXT PRIMARY KEY,
          kind TEXT NOT NULL, payload BLOB NOT NULL, occurred_at REAL NOT NULL,
          produced_at REAL NOT NULL, produced_by TEXT NOT NULL, source TEXT)
        """)
        try exec("CREATE INDEX IF NOT EXISTS session_events_order ON session_events(session_id, sequence)")
        try exec("""
        CREATE TABLE IF NOT EXISTS session_summaries(
          summary_id TEXT PRIMARY KEY, session_id TEXT NOT NULL,
          through_sequence INTEGER NOT NULL, payload BLOB NOT NULL, created_at REAL NOT NULL,
          produced_at REAL NOT NULL, produced_by TEXT NOT NULL, source TEXT)
        """)
        try exec("CREATE INDEX IF NOT EXISTS session_summaries_session ON session_summaries(session_id)")
        try exec("""
        CREATE TABLE IF NOT EXISTS availability(
          seq INTEGER PRIMARY KEY AUTOINCREMENT, information_id TEXT NOT NULL,
          revision_id TEXT NOT NULL, representation_id TEXT NOT NULL,
          state TEXT NOT NULL, reason TEXT, observed_at REAL NOT NULL)
        """)
        try exec("CREATE INDEX IF NOT EXISTS availability_info ON availability(information_id)")
        try exec("""
        CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(
          information_id UNINDEXED, revision_id UNINDEXED, title, text)
        """)
    }

    // MARK: Transactions

    func beginIfNeeded() throws {
        guard !inTransaction else { return }
        try exec("BEGIN IMMEDIATE")
        inTransaction = true
    }

    func commitIfNeeded() throws {
        guard inTransaction else { return }
        try exec("COMMIT")
        inTransaction = false
        moveRetirePending = false
    }

    private func rollbackIfNeeded() {
        guard inTransaction else { return }
        try? exec("ROLLBACK")
        inTransaction = false
        moveRetirePending = false
    }

    /// Fail-safe: a move handoff interrupted by an unrelated operation commits
    /// the retirement as its own atomic step instead of dangling.
    private func closeStrayMoveHandoff() throws {
        if inTransaction && moveRetirePending {
            moveRetirePending = false
            try commitIfNeeded()
        }
    }

    func run(_ sql: String, bind: (Stmt) throws -> Void = { _ in }) throws {
        try closeStrayMoveHandoff()
        do {
            try beginIfNeeded()
            let stmt = try Stmt(db: db, sql: sql)
            defer { stmt.finalize() }
            try bind(stmt)
            _ = try stmt.step()
            try commitIfNeeded()
        } catch {
            rollbackIfNeeded()
            throw error
        }
    }

    func query<T>(_ sql: String, bind: (Stmt) throws -> Void = { _ in }, read: (Stmt) throws -> T) throws -> [T] {
        let stmt = try Stmt(db: db, sql: sql)
        defer { stmt.finalize() }
        try bind(stmt)
        var rows: [T] = []
        while try stmt.step() {
            rows.append(try read(stmt))
        }
        return rows
    }

    // MARK: Paired move handoff (one atomic locator transition)

    func retireLocator(_ locatorID: String, retiredAt: Date) throws {
        try closeStrayMoveHandoff()
        do {
            try beginIfNeeded()
            moveRetirePending = true
            let stmt = try Stmt(
                db: db,
                sql: "UPDATE locators SET retired_at=? WHERE locator_id=? AND retired_at IS NULL"
            )
            defer { stmt.finalize() }
            stmt.bindDouble(1, retiredAt.timeIntervalSince1970)
            stmt.bindText(2, locatorID)
            _ = try stmt.step()
        } catch {
            rollbackIfNeeded()
            throw error
        }
    }

    func assignLocator(_ record: CarrierLocatorRecord) throws {
        do {
            try beginIfNeeded()
            let stmt = try Stmt(db: db, sql: """
              INSERT INTO locators(locator_id, information_id, revision_id, representation_id,
                scheme, value, created_at, retired_at) VALUES (?,?,?,?,?,?,?,NULL)
            """)
            defer { stmt.finalize() }
            stmt.bindText(1, record.locatorID.rawValue)
            stmt.bindText(2, record.informationID.rawValue)
            stmt.bindText(3, record.revisionID.rawValue)
            stmt.bindText(4, record.representationID.rawValue)
            stmt.bindText(5, record.locator.scheme)
            stmt.bindText(6, record.locator.value)
            stmt.bindDouble(7, record.createdAt.timeIntervalSince1970)
            _ = try stmt.step()
            moveRetirePending = false
            try commitIfNeeded()
        } catch {
            rollbackIfNeeded()
            throw error
        }
    }

    // MARK: Raw execution

    nonisolated func exec(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorPointer)
            throw SQLiteCarrierError.sqlFailed("\(sql.prefix(60)): \(message)")
        }
    }
}

/// Prepared statement wrapper.
final class Stmt {
    private let handle: OpaquePointer?
    private var finalized = false

    init(db: OpaquePointer, sql: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let prepared = statement else {
            throw SQLiteCarrierError.sqlFailed("\(sql.prefix(60)): \(String(cString: sqlite3_errmsg(db)))")
        }
        self.handle = prepared
    }

    deinit {
        if !finalized {
            sqlite3_finalize(handle)
        }
    }

    func finalize() {
        guard !finalized else { return }
        finalized = true
        sqlite3_finalize(handle)
    }

    func step() throws -> Bool {
        guard let handle else { throw SQLiteCarrierError.sqlFailed("null statement") }
        let rc = sqlite3_step(handle)
        if rc == SQLITE_ROW { return true }
        if rc == SQLITE_DONE { return false }
        throw SQLiteCarrierError.sqlFailed(String(cString: sqlite3_errmsg(sqlite3_db_handle(handle))))
    }

    func bindText(_ index: Int32, _ value: String) {
        sqlite3_bind_text(handle, index, value, -1, SQLITE_TRANSIENT)
    }

    func bindTextOpt(_ index: Int32, _ value: String?) {
        if let value {
            bindText(index, value)
        } else {
            sqlite3_bind_null(handle, index)
        }
    }

    func bindInt(_ index: Int32, _ value: Int) {
        sqlite3_bind_int64(handle, index, Int64(value))
    }

    func bindDouble(_ index: Int32, _ value: Double) {
        sqlite3_bind_double(handle, index, value)
    }

    func bindBlob(_ index: Int32, _ value: Data) {
        _ = value.withUnsafeBytes { raw in
            sqlite3_bind_blob(handle, index, raw.baseAddress, Int32(value.count), SQLITE_TRANSIENT)
        }
    }

    private func isNull(_ column: Int32) -> Bool {
        sqlite3_column_type(handle, column) == SQLITE_NULL
    }

    func text(_ column: Int32) -> String {
        String(cString: sqlite3_column_text(handle, column))
    }

    func textOpt(_ column: Int32) -> String? {
        isNull(column) ? nil : text(column)
    }

    func int(_ column: Int32) -> Int {
        Int(sqlite3_column_int64(handle, column))
    }

    func double(_ column: Int32) -> Double {
        sqlite3_column_double(handle, column)
    }

    func blob(_ column: Int32) -> Data {
        guard !isNull(column) else { return Data() }
        guard let bytes = sqlite3_column_blob(handle, column) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(handle, column)))
    }
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

extension Stmt {
    func doubleOpt(_ column: Int32) -> Double? {
        sqlite3_column_type(handle, column) == SQLITE_NULL ? nil : double(column)
    }
}
