import CryptoKit
import Foundation
import SQLite3

/// Why the collector's durable state cannot be used. The cases stay distinct
/// on purpose: a missing state directory is a first start, while a damaged one
/// must stop collection instead of silently re-baselining existing transcripts.
public enum QoderCollectionStateError: Error, Equatable, CustomStringConvertible {
    case unreadableState(path: String, detail: String)
    case corruptState(path: String, detail: String)
    case unsupportedSchema(path: String, version: Int32)
    case corruptLegacyCursor(path: String, detail: String)
    case conflictingCandidate(key: String, storedDigest: String, incomingDigest: String)
    case stateAlreadyOwned(path: String, detail: String)
    case sqliteFailure(code: Int32, detail: String)
    case encoding(detail: String)

    public var description: String {
        switch self {
        case .unreadableState(let path, let detail):
            return "collection state is unreadable at \(path): \(detail)"
        case .corruptState(let path, let detail):
            return "collection state is corrupt at \(path): \(detail)"
        case .unsupportedSchema(let path, let version):
            return "collection state at \(path) has unsupported schema version \(version)"
        case .corruptLegacyCursor(let path, let detail):
            return "legacy cursor at \(path) is corrupt: \(detail)"
        case .conflictingCandidate(let key, let storedDigest, let incomingDigest):
            return
                "candidate \(key) was already recorded with different content "
                + "(stored \(storedDigest), incoming \(incomingDigest))"
        case .stateAlreadyOwned(let path, let detail):
            return "collection state at \(path) is already owned: \(detail)"
        case .sqliteFailure(let code, let detail):
            return "sqlite failure \(code): \(detail)"
        case .encoding(let detail):
            return "candidate encoding failed: \(detail)"
        }
    }
}

public enum QoderCandidateKind: String, Sendable, Equatable, Codable {
    case turn
    case closedWithoutAnswer = "closed_without_answer"
    case baseline
    case parseFailure = "parse_failure"
    case orphanAssistant = "orphan_assistant"
    case compaction
}

/// One durably recorded collection event awaiting delivery.
public struct QoderCandidate: Sendable, Equatable {
    public let key: String
    public let kind: QoderCandidateKind
    public let sequence: Int64
    public let recordedAt: Date
    public let event: QoderCollectionEvent

    public init(
        key: String, kind: QoderCandidateKind, sequence: Int64,
        recordedAt: Date, event: QoderCollectionEvent
    ) {
        self.key = key
        self.kind = kind
        self.sequence = sequence
        self.recordedAt = recordedAt
        self.event = event
    }

    public var delivery: QoderCandidateDelivery {
        QoderCandidateDelivery(
            key: key, kind: kind, sequence: sequence, event: event)
    }
}

public struct QoderCommitResult: Sendable, Equatable {
    public let insertedCandidates: Int
    /// Replayed events already present under the same key. A crash between
    /// reading and committing makes the next poll regenerate them, and these
    /// are the ones the unique key absorbed.
    public let duplicateCandidates: Int

    public init(insertedCandidates: Int, duplicateCandidates: Int) {
        self.insertedCandidates = insertedCandidates
        self.duplicateCandidates = duplicateCandidates
    }
}

/// One candidate handed to the delivery sink.
///
/// `key` is the idempotency key the inbox already persisted. Delivery is
/// at-least-once, so a consumer that receives the same key twice knows the
/// second delivery is a replay of the same durable candidate rather than a new
/// one; consumers must not have to re-derive that key themselves.
public struct QoderCandidateDelivery: Sendable, Equatable {
    public let key: String
    public let kind: QoderCandidateKind
    public let sequence: Int64
    public let event: QoderCollectionEvent

    public init(
        key: String, kind: QoderCandidateKind, sequence: Int64,
        event: QoderCollectionEvent
    ) {
        self.key = key
        self.kind = kind
        self.sequence = sequence
        self.event = event
    }
}

public enum QoderCandidateKey {
    /// Turns are keyed by source identity so a replayed transcript line maps to
    /// the same candidate. Everything else is keyed by its canonical payload:
    /// diagnostics carry no semantic identity, and identical diagnostics are
    /// indistinguishable, so the first durable copy is the complete record.
    public static func make(for event: QoderCollectionEvent) throws -> String {
        if case .turn(let turn) = event { return turn.identity.operationKey }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(event)
        } catch {
            throw QoderCollectionStateError.encoding(detail: String(describing: error))
        }
        return "SIM.qoder.candidate.v1:" + QoderDigest.sha256Hex(data)
    }
}

extension QoderCollectionEvent {
    public var candidateKind: QoderCandidateKind {
        switch self {
        case .turn: return .turn
        case .closedWithoutAnswer: return .closedWithoutAnswer
        case .baseline: return .baseline
        case .parseFailure: return .parseFailure
        case .orphanAssistant: return .orphanAssistant
        case .compaction: return .compaction
        }
    }
}

/// Durable candidate inbox and cursor authority for one state directory.
///
/// Candidates and the cursor commit in a single SQLite transaction, so a crash
/// leaves either both or neither. Replaying lines whose commit never landed
/// regenerates identical keys, and the unique key absorbs them. Delivery is a
/// separate step: `pendingCandidates` hands out undelivered rows in commit
/// order, and `markDelivered` runs only after the sink accepted them. A crash
/// between acceptance and that mark redelivers the same key, which is why
/// consumers must treat candidate keys as idempotency keys.
///
/// Every method is expected to run on one queue; the runner serializes calls.
/// A missing database is a first start. A database that exists but cannot be
/// read, is damaged, or carries another schema fails closed until the caller
/// explicitly quarantines it.
public final class QoderCandidateInbox {
    public static let databaseFileName = "candidate-inbox.sqlite"
    public static let legacyCursorFileName = "cursor.json"

    private static let schemaVersion: Int32 = 2
    private static let sqliteHeader = Data("SQLite format 3\u{0}".utf8)
    private static let schema = """
        CREATE TABLE IF NOT EXISTS cursor_state (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            payload BLOB NOT NULL
        );
        CREATE TABLE IF NOT EXISTS candidates (
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            key TEXT NOT NULL UNIQUE,
            kind TEXT NOT NULL,
            recorded_at REAL NOT NULL,
            delivered_at REAL,
            payload_digest TEXT NOT NULL,
            payload BLOB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS candidates_pending_seq
            ON candidates(seq) WHERE delivered_at IS NULL;
        """

    public let directoryURL: URL
    private var connection: QoderSQLiteConnection?

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    deinit {
        connection?.close()
    }

    public var databaseURL: URL {
        directoryURL.appendingPathComponent(Self.databaseFileName)
    }

    public var legacyCursorURL: URL {
        directoryURL.appendingPathComponent(Self.legacyCursorFileName)
    }

    /// `nil` only when nothing was ever committed here: no database, no legacy
    /// cursor. Damaged state throws instead of looking like a first start.
    public func loadCursorState() throws -> QoderCursorState? {
        try openIfNeeded()
        guard let connection else {
            throw QoderCollectionStateError.unreadableState(
                path: databaseURL.path, detail: "store is not open")
        }
        guard let data = try cursorBlob(connection) else { return nil }
        do {
            return try JSONDecoder().decode(QoderCursorState.self, from: data)
        } catch {
            throw QoderCollectionStateError.corruptState(
                path: databaseURL.path, detail: "cursor state decode: \(error)")
        }
    }

    @discardableResult
    public func commit(
        events: [QoderCollectionEvent], cursorState: QoderCursorState
    ) throws -> QoderCommitResult {
        try openIfNeeded()
        guard let connection else {
            throw QoderCollectionStateError.unreadableState(
                path: databaseURL.path, detail: "store is not open")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let cursorData: Data
        do {
            cursorData = try encoder.encode(cursorState)
        } catch {
            throw QoderCollectionStateError.encoding(detail: String(describing: error))
        }
        var rows: [(key: String, kind: String, digest: String, payload: Data)] = []
        rows.reserveCapacity(events.count)
        for event in events {
            let payload: Data
            do {
                payload = try encoder.encode(event)
            } catch {
                throw QoderCollectionStateError.encoding(detail: String(describing: error))
            }
            rows.append(
                (
                    try QoderCandidateKey.make(for: event),
                    event.candidateKind.rawValue,
                    QoderDigest.sha256Hex(payload),
                    payload
                ))
        }

        return try connection.withTransaction {
            var inserted = 0
            var duplicates = 0
            let recordedAt = Date().timeIntervalSince1970
            let insert = try connection.prepare(
                """
                INSERT OR IGNORE INTO candidates
                    (key, kind, recorded_at, payload_digest, payload)
                VALUES (?, ?, ?, ?, ?)
                """)
            let existing = try connection.prepare(
                "SELECT payload_digest FROM candidates WHERE key = ?")
            for row in rows {
                try insert.reset()
                try insert.bind(text: row.key, at: 1)
                try insert.bind(text: row.kind, at: 2)
                insert.bind(double: recordedAt, at: 3)
                try insert.bind(text: row.digest, at: 4)
                try insert.bind(blob: row.payload, at: 5)
                _ = try insert.step()
                if connection.changes == 1 {
                    inserted += 1
                    continue
                }
                try existing.reset()
                try existing.bind(text: row.key, at: 1)
                guard try existing.step(), let stored = existing.text(at: 0) else {
                    throw QoderCollectionStateError.corruptState(
                        path: databaseURL.path,
                        detail: "candidate row missing for \(row.key)")
                }
                // The key names a source identity, not the content. Identical
                // bytes are the replay this design already absorbs; different
                // bytes under the same identity mean the source was revised
                // without a revision change, which must not be swallowed as a
                // duplicate.
                guard stored == row.digest else {
                    throw QoderCollectionStateError.conflictingCandidate(
                        key: row.key, storedDigest: stored,
                        incomingDigest: row.digest)
                }
                duplicates += 1
            }
            let upsert = try connection.prepare(
                """
                INSERT INTO cursor_state(id, payload) VALUES (1, ?)
                ON CONFLICT(id) DO UPDATE SET payload = excluded.payload
                """)
            try upsert.bind(blob: cursorData, at: 1)
            _ = try upsert.step()
            return QoderCommitResult(
                insertedCandidates: inserted, duplicateCandidates: duplicates)
        }
    }

    public func pendingCandidates(limit: Int = 256) throws -> [QoderCandidate] {
        try openIfNeeded()
        guard let connection else {
            throw QoderCollectionStateError.unreadableState(
                path: databaseURL.path, detail: "store is not open")
        }
        let statement = try connection.prepare(
            """
            SELECT seq, key, kind, recorded_at, payload FROM candidates
            WHERE delivered_at IS NULL ORDER BY seq LIMIT ?
            """)
        statement.bind(int64: Int64(max(1, limit)), at: 1)
        var candidates: [QoderCandidate] = []
        while try statement.step() {
            guard let key = statement.text(at: 1),
                let rawKind = statement.text(at: 2),
                let kind = QoderCandidateKind(rawValue: rawKind),
                let payload = statement.blob(at: 4)
            else {
                throw QoderCollectionStateError.corruptState(
                    path: databaseURL.path, detail: "malformed candidate row")
            }
            let event: QoderCollectionEvent
            do {
                event = try JSONDecoder().decode(QoderCollectionEvent.self, from: payload)
            } catch {
                throw QoderCollectionStateError.corruptState(
                    path: databaseURL.path, detail: "candidate decode: \(error)")
            }
            candidates.append(
                QoderCandidate(
                    key: key, kind: kind, sequence: statement.int64(at: 0),
                    recordedAt: Date(timeIntervalSince1970: statement.double(at: 3)),
                    event: event))
        }
        return candidates
    }

    public func markDelivered(_ keys: [String]) throws {
        guard !keys.isEmpty else { return }
        try openIfNeeded()
        guard let connection else {
            throw QoderCollectionStateError.unreadableState(
                path: databaseURL.path, detail: "store is not open")
        }
        try connection.withTransaction {
            let deliveredAt = Date().timeIntervalSince1970
            let update = try connection.prepare(
                """
                UPDATE candidates SET delivered_at = ?
                WHERE key = ? AND delivered_at IS NULL
                """)
            for key in keys {
                try update.reset()
                update.bind(double: deliveredAt, at: 1)
                try update.bind(text: key, at: 2)
                _ = try update.step()
            }
        }
    }

    public func pendingCount() throws -> Int {
        try openIfNeeded()
        guard let connection else {
            throw QoderCollectionStateError.unreadableState(
                path: databaseURL.path, detail: "store is not open")
        }
        return Int(
            try connection.scalarInt64(
                "SELECT COUNT(*) FROM candidates WHERE delivered_at IS NULL"))
    }

    /// Moves the database, its WAL files, and any legacy cursor aside so the
    /// next open starts fresh. This is the explicit operator recovery for a
    /// damaged state: it re-baselines existing transcripts at EOF, which is
    /// why it never happens implicitly.
    @discardableResult
    public func quarantine() throws -> URL {
        connection?.close()
        connection = nil
        let fileManager = FileManager.default
        let destination = directoryURL
            .appendingPathComponent("quarantine", isDirectory: true)
            .appendingPathComponent(
                "\(Self.timestamp())-\(UUID().uuidString.prefix(8))", isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: destination, withIntermediateDirectories: true)
        } catch {
            throw QoderCollectionStateError.unreadableState(
                path: destination.path, detail: String(describing: error))
        }
        let names = [
            Self.databaseFileName,
            "\(Self.databaseFileName)-wal",
            "\(Self.databaseFileName)-shm",
            Self.legacyCursorFileName,
        ]
        for name in names {
            let source = directoryURL.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            do {
                try fileManager.moveItem(
                    at: source, to: destination.appendingPathComponent(name))
            } catch {
                throw QoderCollectionStateError.unreadableState(
                    path: source.path, detail: String(describing: error))
            }
        }
        return destination
    }

    private func openIfNeeded() throws {
        if connection != nil { return }
        try prepareDirectory()
        let fileManager = FileManager.default
        let databaseExists = fileManager.fileExists(atPath: databaseURL.path)
        let legacyExists = fileManager.fileExists(atPath: legacyCursorURL.path)

        if databaseExists {
            try validateHeader(at: databaseURL.path)
            let opened = try QoderSQLiteConnection.open(path: databaseURL.path)
            do {
                try configure(opened)
                try validateSchema(opened)
            } catch {
                opened.close()
                throw error
            }
            connection = opened
            if try cursorBlob(opened) == nil, legacyExists {
                // A crash during the one-time migration can leave the legacy
                // file behind with no committed row; finish the import.
                let legacyState = try loadLegacyState()
                try commit(events: [], cursorState: legacyState)
                archiveLegacyCursor()
            } else if legacyExists {
                archiveLegacyCursor()
            }
            return
        }

        // Read the legacy cursor before creating any new authoritative state:
        // a damaged legacy file must fail closed, not become a first start.
        let legacyState = legacyExists ? try loadLegacyState() : nil
        let opened = try QoderSQLiteConnection.open(path: databaseURL.path)
        do {
            try configure(opened)
            try validateSchema(opened)
        } catch {
            opened.close()
            throw error
        }
        connection = opened
        try? fileManager.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
        if let legacyState {
            try commit(events: [], cursorState: legacyState)
            archiveLegacyCursor()
        }
    }

    private func prepareDirectory() throws {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: directoryURL, withIntermediateDirectories: true)
            try fileManager.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        } catch {
            throw QoderCollectionStateError.unreadableState(
                path: directoryURL.path, detail: String(describing: error))
        }
    }

    /// A file that exists must be a real SQLite database. Zero bytes, foreign
    /// content, or a damaged header all mean damage, never "fresh".
    private func validateHeader(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw QoderCollectionStateError.unreadableState(
                path: path, detail: "cannot open database file")
        }
        defer { try? handle.close() }
        let header: Data
        do {
            header = try handle.read(upToCount: 16) ?? Data()
        } catch {
            throw QoderCollectionStateError.unreadableState(
                path: path, detail: String(describing: error))
        }
        guard header == Self.sqliteHeader else {
            throw QoderCollectionStateError.corruptState(
                path: path, detail: "missing SQLite header")
        }
    }

    private func configure(_ connection: QoderSQLiteConnection) throws {
        try connection.execute("PRAGMA busy_timeout = 2000")
        try connection.execute("PRAGMA journal_mode = WAL")
        try connection.execute("PRAGMA synchronous = FULL")
    }

    private func validateSchema(_ connection: QoderSQLiteConnection) throws {
        let version = Int32(try connection.scalarInt64("PRAGMA user_version"))
        switch version {
        case 0:
            try connection.withTransaction {
                try connection.execute(Self.schema)
                try connection.execute("PRAGMA user_version = \(Self.schemaVersion)")
            }
        case 1:
            try migrateVersionOne(connection)
        case Self.schemaVersion:
            break
        default:
            throw QoderCollectionStateError.unsupportedSchema(
                path: databaseURL.path, version: version)
        }
    }

    /// Slice 3 wrote candidates without a payload digest. Existing rows are
    /// kept and backfilled so the upgrade neither drops undelivered
    /// candidates nor turns a legitimate replay into a false conflict.
    private func migrateVersionOne(_ connection: QoderSQLiteConnection) throws {
        try connection.withTransaction {
            try connection.execute(
                "ALTER TABLE candidates ADD COLUMN payload_digest TEXT NOT NULL DEFAULT ''")
            var rows: [(seq: Int64, payload: Data)] = []
            do {
                let select = try connection.prepare("SELECT seq, payload FROM candidates")
                while try select.step() {
                    guard let payload = select.blob(at: 1) else {
                        throw QoderCollectionStateError.corruptState(
                            path: databaseURL.path, detail: "null candidate payload")
                    }
                    rows.append((select.int64(at: 0), payload))
                }
            }
            let update = try connection.prepare(
                "UPDATE candidates SET payload_digest = ? WHERE seq = ?")
            for row in rows {
                try update.reset()
                try update.bind(text: QoderDigest.sha256Hex(row.payload), at: 1)
                update.bind(int64: row.seq, at: 2)
                _ = try update.step()
            }
            try connection.execute("PRAGMA user_version = \(Self.schemaVersion)")
        }
    }

    private func cursorBlob(_ connection: QoderSQLiteConnection) throws -> Data? {
        let statement = try connection.prepare(
            "SELECT payload FROM cursor_state WHERE id = 1")
        guard try statement.step() else { return nil }
        guard let data = statement.blob(at: 0) else {
            throw QoderCollectionStateError.corruptState(
                path: databaseURL.path, detail: "null cursor payload")
        }
        return data
    }

    private func loadLegacyState() throws -> QoderCursorState {
        let store = QoderFileCursorStore(directoryURL: directoryURL)
        guard let state = try store.load() else {
            throw QoderCollectionStateError.corruptLegacyCursor(
                path: legacyCursorURL.path,
                detail: "legacy cursor disappeared during migration")
        }
        return state
    }

    private func archiveLegacyCursor() {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: legacyCursorURL.path) else { return }
        let destination = directoryURL.appendingPathComponent(
            "cursor.json.imported-\(Self.timestamp())-\(UUID().uuidString.prefix(8))")
        try? fileManager.moveItem(at: legacyCursorURL, to: destination)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: Date())
    }
}

private let qoderSQLiteTransient = unsafeBitCast(
    -1, to: sqlite3_destructor_type.self)

final class QoderSQLiteConnection {
    private var handle: OpaquePointer?
    let path: String

    private init(handle: OpaquePointer, path: String) {
        self.handle = handle
        self.path = path
    }

    deinit {
        close()
    }

    static func open(path: String) throws -> QoderSQLiteConnection {
        var handle: OpaquePointer?
        let code = sqlite3_open_v2(
            path, &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard code == SQLITE_OK, let handle else {
            let detail =
                handle.map { String(cString: sqlite3_errmsg($0)) }
                ?? "sqlite3_open_v2 returned \(code)"
            if let handle { sqlite3_close_v2(handle) }
            throw Self.error(code: code, path: path, detail: detail)
        }
        return QoderSQLiteConnection(handle: handle, path: path)
    }

    static func error(code: Int32, path: String, detail: String) -> QoderCollectionStateError {
        switch code & 0xFF {
        case SQLITE_CORRUPT, SQLITE_NOTADB:
            return .corruptState(path: path, detail: detail)
        case SQLITE_CANTOPEN, SQLITE_PERM, SQLITE_READONLY, SQLITE_IOERR:
            return .unreadableState(path: path, detail: detail)
        default:
            return .sqliteFailure(code: code, detail: detail)
        }
    }

    var changes: Int32 {
        guard let handle else { return 0 }
        return sqlite3_changes(handle)
    }

    func close() {
        guard let handle else { return }
        sqlite3_close_v2(handle)
        self.handle = nil
    }

    func execute(_ sql: String) throws {
        guard let handle else {
            throw Self.error(code: SQLITE_MISUSE, path: path, detail: "connection closed")
        }
        var message: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(handle, sql, nil, nil, &message)
        guard code == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(message)
            throw Self.error(code: code, path: path, detail: detail)
        }
    }

    func prepare(_ sql: String) throws -> QoderSQLiteStatement {
        guard let handle else {
            throw Self.error(code: SQLITE_MISUSE, path: path, detail: "connection closed")
        }
        return try QoderSQLiteStatement(connection: handle, sql: sql, path: path)
    }

    func scalarInt64(_ sql: String) throws -> Int64 {
        let statement = try prepare(sql)
        guard try statement.step() else { return 0 }
        return statement.int64(at: 0)
    }

    func withTransaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
}

final class QoderSQLiteStatement {
    private let connection: OpaquePointer
    private let handle: OpaquePointer
    private let path: String

    init(connection: OpaquePointer, sql: String, path: String) throws {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else {
            let detail = String(cString: sqlite3_errmsg(connection))
            if let statement { sqlite3_finalize(statement) }
            throw QoderSQLiteConnection.error(code: code, path: path, detail: detail)
        }
        self.connection = connection
        self.handle = statement
        self.path = path
    }

    deinit {
        sqlite3_finalize(handle)
    }

    func reset() throws {
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
    }

    func bind(text: String, at index: Int32) throws {
        try check(sqlite3_bind_text(handle, index, text, -1, qoderSQLiteTransient))
    }

    func bind(blob: Data, at index: Int32) throws {
        let code: Int32
        if blob.isEmpty {
            code = sqlite3_bind_blob(handle, index, "", 0, qoderSQLiteTransient)
        } else {
            code = blob.withUnsafeBytes { buffer in
                sqlite3_bind_blob(
                    handle, index, buffer.baseAddress, Int32(buffer.count),
                    qoderSQLiteTransient)
            }
        }
        try check(code)
    }

    func bind(double: Double, at index: Int32) {
        sqlite3_bind_double(handle, index, double)
    }

    func bind(int64: Int64, at index: Int32) {
        sqlite3_bind_int64(handle, index, int64)
    }

    func step() throws -> Bool {
        let code = sqlite3_step(handle)
        if code == SQLITE_ROW { return true }
        if code == SQLITE_DONE { return false }
        throw QoderSQLiteConnection.error(
            code: code, path: path, detail: String(cString: sqlite3_errmsg(connection)))
    }

    func int64(at index: Int32) -> Int64 {
        sqlite3_column_int64(handle, index)
    }

    func double(at index: Int32) -> Double {
        sqlite3_column_double(handle, index)
    }

    func text(at index: Int32) -> String? {
        guard sqlite3_column_type(handle, index) != SQLITE_NULL,
            let pointer = sqlite3_column_text(handle, index)
        else { return nil }
        return String(cString: pointer)
    }

    func blob(at index: Int32) -> Data? {
        guard sqlite3_column_type(handle, index) != SQLITE_NULL else { return nil }
        let count = Int(sqlite3_column_bytes(handle, index))
        guard count > 0, let bytes = sqlite3_column_blob(handle, index) else {
            return Data()
        }
        return Data(bytes: bytes, count: count)
    }

    private func check(_ code: Int32) throws {
        guard code == SQLITE_OK else {
            throw QoderSQLiteConnection.error(
                code: code, path: path, detail: String(cString: sqlite3_errmsg(connection)))
        }
    }
}
