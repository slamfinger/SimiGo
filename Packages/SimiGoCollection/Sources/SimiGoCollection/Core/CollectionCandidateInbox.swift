import Darwin
import Foundation
import SQLite3

/// Why the collector's durable state cannot be used. The cases stay distinct
/// on purpose: a missing state directory is a first start, while a damaged one
/// must stop collection instead of silently re-baselining existing transcripts.
public enum CollectionStateError: Error, Equatable, CustomStringConvertible {
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

/// Event discriminators. The raw values are stored in the `kind` column and
/// double as the payload envelope's `kind` field, so stored rows stay
/// self-describing. They are persisted vocabulary, not labels.
public enum CollectionCandidateKind: String, Sendable, Equatable, Codable {
    case turn
    case closedWithoutAnswer = "closed_without_answer"
    case baseline
    case parseFailure = "parse_failure"
    case orphanAssistant = "orphan_assistant"
    case compaction
}

/// What the durable inbox needs from an adapter's event.
///
/// The key is the adapter's decision because only the adapter knows what makes
/// two observations the same fact. The inbox enforces the consequence: the same
/// key with different bytes is a conflict, not a duplicate.
public protocol CollectionCandidateEvent: Codable, Sendable {
    var candidateKind: CollectionCandidateKind { get }
    func candidateKey() throws -> String
}

/// One durably recorded collection event awaiting delivery.
struct CollectionCandidate<Event: CollectionCandidateEvent> {
    let key: String
    let kind: CollectionCandidateKind
    let sequence: Int64
    let recordedAt: Date
    let event: Event

    var delivery: CollectionDelivery<Event> {
        CollectionDelivery(key: key, kind: kind, sequence: sequence, event: event)
    }
}

/// One candidate handed to a delivery sink. Delivery is at-least-once, so the
/// persisted key travels with the event instead of being re-derived downstream.
struct CollectionDelivery<Event: CollectionCandidateEvent> {
    let key: String
    let kind: CollectionCandidateKind
    let sequence: Int64
    let event: Event
}

struct CollectionCommitResult: Sendable, Equatable {
    let insertedCandidates: Int
    /// Replayed events already present under the same key. A crash between
    /// reading and committing makes the next poll regenerate them, and these
    /// are the ones the unique key absorbed.
    let duplicateCandidates: Int
}

/// Durable candidate inbox and read-position authority for one state directory,
/// independent of which carrier produced the events.
///
/// Candidates and the read position commit in a single SQLite transaction, so a
/// crash leaves either both or neither. Replaying observations whose commit
/// never landed regenerates identical keys, and the unique key absorbs them.
/// Delivery is a separate step: `pendingCandidates` hands out undelivered rows in
/// commit order, and `markDelivered` runs only after the sink accepted them. A
/// crash between acceptance and that mark redelivers the same key, which is why
/// consumers must treat candidate keys as idempotency keys.
///
/// The read position is opaque bytes here. A byte offset, a snapshot digest
/// ledger, and a carrier-specific resume point are all the same thing to this
/// store: the adapter's authoritative position, committed atomically with the
/// candidates it produced.
///
/// Every method is expected to run on one queue; the caller serializes calls.
/// A missing database is a first start. A database that exists but cannot be
/// read, is damaged, or carries another schema fails closed until the caller
/// explicitly quarantines it.
final class CollectionCandidateInbox<Event: CollectionCandidateEvent> {
    static var databaseFileName: String { CollectionInboxFiles.databaseFileName }
    static var legacyCursorFileName: String { CollectionInboxFiles.legacyCursorFileName }

    private static var schemaVersion: Int32 { CollectionInboxFiles.schemaVersion }

    private(set) var directoryURL: URL
    private var connection: CollectionSQLiteConnection?

    init(directoryURL: URL) {
        // Parent aliases are resolved only after they exist in prepareDirectory.
        // The final component is kept intact for the O_NOFOLLOW directory check.
        self.directoryURL = directoryURL.standardizedFileURL
    }

    deinit {
        connection?.close()
    }

    var databaseURL: URL {
        directoryURL.appendingPathComponent(Self.databaseFileName)
    }

    var legacyCursorURL: URL {
        directoryURL.appendingPathComponent(Self.legacyCursorFileName)
    }

    /// `nil` only when no position was ever committed here. Damaged state throws
    /// instead of looking like a first start.
    func loadPosition() throws -> Data? {
        try openIfNeeded()
        guard let connection else {
            throw CollectionStateError.unreadableState(
                path: databaseURL.path, detail: "store is not open")
        }
        return try positionBlob(connection)
    }

    @discardableResult
    func commit(events: [Event], position: Data) throws -> CollectionCommitResult {
        try openIfNeeded()
        guard let connection else {
            throw CollectionStateError.unreadableState(
                path: databaseURL.path, detail: "store is not open")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var rows: [(key: String, kind: String, digest: String, payload: Data)] = []
        rows.reserveCapacity(events.count)
        for event in events {
            let payload: Data
            do {
                payload = try encoder.encode(event)
            } catch {
                throw CollectionStateError.encoding(detail: String(describing: error))
            }
            rows.append(
                (
                    try event.candidateKey(),
                    event.candidateKind.rawValue,
                    CollectionDigest.sha256Hex(payload),
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
                try insert.bind(double: recordedAt, at: 3)
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
                    throw CollectionStateError.corruptState(
                        path: databaseURL.path,
                        detail: "candidate row missing for \(row.key)")
                }
                // The key names a source identity, not the content. Identical
                // bytes are the replay this design already absorbs; different
                // bytes under the same identity mean the source was revised
                // without a revision change, which must not be swallowed as a
                // duplicate.
                guard stored == row.digest else {
                    throw CollectionStateError.conflictingCandidate(
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
            try upsert.bind(blob: position, at: 1)
            _ = try upsert.step()
            return CollectionCommitResult(
                insertedCandidates: inserted, duplicateCandidates: duplicates)
        }
    }

    func pendingCandidates(limit: Int = 256) throws -> [CollectionCandidate<Event>] {
        try openIfNeeded()
        guard let connection else {
            throw CollectionStateError.unreadableState(
                path: databaseURL.path, detail: "store is not open")
        }
        let statement = try connection.prepare(
            """
            SELECT seq, key, kind, recorded_at, payload_digest, payload FROM candidates
            WHERE delivered_at IS NULL ORDER BY seq LIMIT ?
            """)
        try statement.bind(int64: Int64(max(1, limit)), at: 1)
        var candidates: [CollectionCandidate<Event>] = []
        while try statement.step() {
            guard let key = statement.text(at: 1),
                let rawKind = statement.text(at: 2),
                let kind = CollectionCandidateKind(rawValue: rawKind),
                let payloadDigest = statement.text(at: 4),
                let payload = statement.blob(at: 5)
            else {
                throw CollectionStateError.corruptState(
                    path: databaseURL.path, detail: "malformed candidate row")
            }
            // Hash the exact BLOB bytes returned by SQLite. Re-encoding the
            // decoded value would hide byte-level storage corruption.
            let actualDigest = CollectionDigest.sha256Hex(payload)
            guard actualDigest == payloadDigest else {
                throw CollectionStateError.corruptState(
                    path: databaseURL.path,
                    detail: "candidate payload digest mismatch for \(key): stored \(payloadDigest), actual \(actualDigest)")
            }
            let event: Event
            do {
                event = try JSONDecoder().decode(Event.self, from: payload)
            } catch {
                throw CollectionStateError.corruptState(
                    path: databaseURL.path, detail: "candidate decode: \(error)")
            }
            candidates.append(
                CollectionCandidate(
                    key: key, kind: kind, sequence: statement.int64(at: 0),
                    recordedAt: Date(timeIntervalSince1970: statement.double(at: 3)),
                    event: event))
        }
        return candidates
    }

    func markDelivered(_ keys: [String]) throws {
        guard !keys.isEmpty else { return }
        try openIfNeeded()
        guard let connection else {
            throw CollectionStateError.unreadableState(
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
                try update.bind(double: deliveredAt, at: 1)
                try update.bind(text: key, at: 2)
                _ = try update.step()
            }
        }
    }

    func pendingCount() throws -> Int {
        try openIfNeeded()
        guard let connection else {
            throw CollectionStateError.unreadableState(
                path: databaseURL.path, detail: "store is not open")
        }
        return Int(
            try connection.scalarInt64(
                "SELECT COUNT(*) FROM candidates WHERE delivered_at IS NULL"))
    }

    /// Moves the database, its WAL files, and any legacy cursor aside so the
    /// next open starts fresh. This is the explicit operator recovery for a
    /// damaged state: it re-baselines existing transcripts, which is why it
    /// never happens implicitly.
    @discardableResult
    func quarantine() throws -> URL {
        connection?.close()
        connection = nil
        let fileManager = FileManager.default
        let destination = directoryURL
            .appendingPathComponent("quarantine", isDirectory: true)
            .appendingPathComponent(
                "\(CollectionInboxFiles.timestamp())-\(UUID().uuidString.prefix(8))",
                isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: destination, withIntermediateDirectories: true)
        } catch {
            throw CollectionStateError.unreadableState(
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
                throw CollectionStateError.unreadableState(
                    path: source.path, detail: String(describing: error))
            }
        }
        return destination
    }

    private func openIfNeeded() throws {
        if connection != nil { return }
        try prepareDirectory()
        let fileManager = FileManager.default
        let databaseExists = try validateRegularFileIfPresent(at: databaseURL)
        if databaseExists {
            try validateHeader(at: databaseURL.path)
        }
        let opened = try CollectionSQLiteConnection.open(path: databaseURL.path)
        do {
            try configure(opened)
            try validateSchema(opened)
        } catch {
            opened.close()
            throw error
        }
        connection = opened
        if !databaseExists {
            try? fileManager.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
        }
    }

    private func prepareDirectory() throws {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw CollectionStateError.unreadableState(
                path: directoryURL.path, detail: String(describing: error))
        }

        // macOS SQLite canonicalizes the entire database path before applying
        // SQLITE_OPEN_NOFOLLOW. Resolve all existing parent components now,
        // after directory creation, but preserve the final state-directory
        // component so a symlink at that boundary is still rejected below.
        let parentURL = directoryURL.deletingLastPathComponent()
        var resolvedParent = [CChar](repeating: 0, count: Int(PATH_MAX))
        let parentResolved = parentURL.path.withCString { source in
            resolvedParent.withUnsafeMutableBufferPointer { target in
                Darwin.realpath(source, target.baseAddress) != nil
            }
        }
        guard parentResolved else {
            throw CollectionStateError.unreadableState(
                path: parentURL.path,
                detail: "cannot resolve existing state parent: \(String(cString: strerror(errno)))")
        }
        let finalComponent = directoryURL.lastPathComponent
        directoryURL = URL(fileURLWithPath: String(cString: resolvedParent), isDirectory: true)
            .appendingPathComponent(finalComponent, isDirectory: true)

        let descriptor = open(
            directoryURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw CollectionStateError.unreadableState(
                path: directoryURL.path, detail: "state directory is linked or unreadable")
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == geteuid(),
              (info.st_mode & (S_IWGRP | S_IWOTH)) == 0,
              fchmod(descriptor, 0o700) == 0
        else {
            throw CollectionStateError.unreadableState(
                path: directoryURL.path,
                detail: "state directory is not a private directory owned by this user")
        }
    }

    private func validateRegularFileIfPresent(at url: URL) throws -> Bool {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == geteuid() else {
                throw CollectionStateError.unreadableState(
                    path: url.path, detail: "state entry is not a regular owned file")
            }
            return true
        }
        guard errno == ENOENT else {
            throw CollectionStateError.unreadableState(
                path: url.path, detail: String(cString: strerror(errno)))
        }
        return false
    }

    /// A file that exists must be a real SQLite database. Zero bytes, foreign
    /// content, or a damaged header all mean damage, never "fresh".
    private func validateHeader(at path: String) throws {
        // O_NONBLOCK keeps a FIFO planted between the lstat and this open from
        // blocking the caller; the type check below then rejects it.
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw CollectionStateError.unreadableState(
                path: path, detail: "cannot open database without following links")
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == geteuid(),
              info.st_nlink == 1,
              (info.st_mode & (S_IWGRP | S_IWOTH)) == 0
        else {
            throw CollectionStateError.unreadableState(
                path: path,
                detail: "database must be an owned, single-link, non-shared-writable regular file")
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        let count = bytes.withUnsafeMutableBytes {
            Darwin.read(descriptor, $0.baseAddress, $0.count)
        }
        let header = count == 16 ? Data(bytes) : Data()
        guard header == CollectionInboxFiles.sqliteHeader else {
            throw CollectionStateError.corruptState(
                path: path, detail: "missing SQLite header")
        }
    }

    private func configure(_ connection: CollectionSQLiteConnection) throws {
        try connection.execute("PRAGMA busy_timeout = 2000")
        try connection.execute("PRAGMA journal_mode = WAL")
        try connection.execute("PRAGMA synchronous = FULL")
    }

    private func validateSchema(_ connection: CollectionSQLiteConnection) throws {
        let version = Int32(try connection.scalarInt64("PRAGMA user_version"))
        switch version {
        case 0:
            try connection.withTransaction {
                try connection.execute(CollectionInboxFiles.schema)
                try connection.execute("PRAGMA user_version = \(Self.schemaVersion)")
            }
        case 1:
            try migrateVersionOne(connection)
        case Self.schemaVersion:
            break
        default:
            throw CollectionStateError.unsupportedSchema(
                path: databaseURL.path, version: version)
        }
    }

    /// Slice 3 wrote candidates without a payload digest. Existing rows are
    /// kept and backfilled so the upgrade neither drops undelivered
    /// candidates nor turns a legitimate replay into a false conflict.
    private func migrateVersionOne(_ connection: CollectionSQLiteConnection) throws {
        try connection.withTransaction {
            try connection.execute(
                "ALTER TABLE candidates ADD COLUMN payload_digest TEXT NOT NULL DEFAULT ''")
            var rows: [(seq: Int64, payload: Data)] = []
            do {
                let select = try connection.prepare("SELECT seq, payload FROM candidates")
                while try select.step() {
                    guard let payload = select.blob(at: 1) else {
                        throw CollectionStateError.corruptState(
                            path: databaseURL.path, detail: "null candidate payload")
                    }
                    rows.append((select.int64(at: 0), payload))
                }
            }
            let update = try connection.prepare(
                "UPDATE candidates SET payload_digest = ? WHERE seq = ?")
            for row in rows {
                try update.reset()
                try update.bind(text: CollectionDigest.sha256Hex(row.payload), at: 1)
                try update.bind(int64: row.seq, at: 2)
                _ = try update.step()
            }
            try connection.execute("PRAGMA user_version = \(Self.schemaVersion)")
        }
    }

    private func positionBlob(_ connection: CollectionSQLiteConnection) throws -> Data? {
        let statement = try connection.prepare(
            "SELECT payload FROM cursor_state WHERE id = 1")
        guard try statement.step() else { return nil }
        guard let data = statement.blob(at: 0) else {
            throw CollectionStateError.corruptState(
                path: databaseURL.path, detail: "null cursor payload")
        }
        return data
    }
}

/// Names and version shared by every specialization of the inbox, so a generic
/// type's static members do not have to be reached through a specialization.
enum CollectionInboxFiles {
    static let databaseFileName = "candidate-inbox.sqlite"
    static let legacyCursorFileName = "cursor.json"
    static let schemaVersion: Int32 = 2
    static let schema = """
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
    static let sqliteHeader = Data("SQLite format 3\u{0}".utf8)

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: Date())
    }
}

private let collectionSQLiteTransient = unsafeBitCast(
    -1, to: sqlite3_destructor_type.self)

final class CollectionSQLiteConnection {
    private var handle: OpaquePointer?
    let path: String

    private init(handle: OpaquePointer, path: String) {
        self.handle = handle
        self.path = path
    }

    deinit {
        close()
    }

    static func open(path: String) throws -> CollectionSQLiteConnection {
        var handle: OpaquePointer?
        let code = sqlite3_open_v2(
            path, &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
                | SQLITE_OPEN_NOFOLLOW, nil)
        guard code == SQLITE_OK, let handle else {
            let detail =
                handle.map { String(cString: sqlite3_errmsg($0)) }
                ?? "sqlite3_open_v2 returned \(code)"
            if let handle { sqlite3_close_v2(handle) }
            throw Self.error(code: code, path: path, detail: detail)
        }
        return CollectionSQLiteConnection(handle: handle, path: path)
    }

    static func error(code: Int32, path: String, detail: String) -> CollectionStateError {
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

    func prepare(_ sql: String) throws -> CollectionSQLiteStatement {
        guard let handle else {
            throw Self.error(code: SQLITE_MISUSE, path: path, detail: "connection closed")
        }
        return try CollectionSQLiteStatement(connection: handle, sql: sql, path: path)
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

final class CollectionSQLiteStatement {
    private let connection: OpaquePointer
    private let handle: OpaquePointer
    private let path: String

    init(connection: OpaquePointer, sql: String, path: String) throws {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else {
            let detail = String(cString: sqlite3_errmsg(connection))
            if let statement { sqlite3_finalize(statement) }
            throw CollectionSQLiteConnection.error(code: code, path: path, detail: detail)
        }
        self.connection = connection
        self.handle = statement
        self.path = path
    }

    deinit {
        sqlite3_finalize(handle)
    }

    func reset() throws {
        // Reset always runs before clearing bindings, even when it reports the
        // previous step error. Surface both return codes instead of allowing a
        // failed statement to be silently reused.
        let resetCode = sqlite3_reset(handle)
        let clearCode = sqlite3_clear_bindings(handle)
        try check(resetCode)
        try check(clearCode)
    }

    func bind(text: String, at index: Int32) throws {
        try check(sqlite3_bind_text(handle, index, text, -1, collectionSQLiteTransient))
    }

    func bind(blob: Data, at index: Int32) throws {
        let code: Int32
        if blob.isEmpty {
            code = sqlite3_bind_blob(handle, index, "", 0, collectionSQLiteTransient)
        } else {
            code = blob.withUnsafeBytes { buffer in
                sqlite3_bind_blob(
                    handle, index, buffer.baseAddress, Int32(buffer.count),
                    collectionSQLiteTransient)
            }
        }
        try check(code)
    }

    func bind(double: Double, at index: Int32) throws {
        try check(sqlite3_bind_double(handle, index, double))
    }

    func bind(int64: Int64, at index: Int32) throws {
        try check(sqlite3_bind_int64(handle, index, int64))
    }

    func step() throws -> Bool {
        let code = sqlite3_step(handle)
        if code == SQLITE_ROW { return true }
        if code == SQLITE_DONE { return false }
        throw CollectionSQLiteConnection.error(
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
            throw CollectionSQLiteConnection.error(
                code: code, path: path, detail: String(cString: sqlite3_errmsg(connection)))
        }
    }
}
