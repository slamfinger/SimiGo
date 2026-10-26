import Foundation
import SQLite3

/// Authoritative ES/IS persistence for SimiGo, backed by the system SQLite3.
///
/// Execution State is the continuation authority. Information Space is the
/// information side of the same system: source-derived content, computation
/// results, and settled reusable results, carried by this database so a later
/// execution period can verify and reuse them.
///
/// Carrier invariants (v8):
///   * content-addressed objects: `object_id = SHA256(bytes)`, written once,
///     verified on read;
///   * append-only identities (`is_index_entries`) and dependency revisions
///     (`is_dependency_entries`);
///   * source/version/digest, settlement validity, and dependency state;
///   * fail-closed migration: an unreadable database is never recreated.
///
/// External work files and model weights are still referenced by
/// `root_id + relative path`; the carrier stores settled information objects,
/// not a filesystem mirror. It stores and verifies; it does not interpret
/// semantics or decide continuation.
///
/// All schema creation and migration run inside explicit transactions; opening a
/// file that is not a valid database fails closed rather than silently
/// recreating it.
public final class SimiGoESISDatabase {

    public enum DatabaseError: Error, Equatable {
        case cannotOpen(String)
        case notADatabase(String)
        case sql(String)
        case contractVersionMismatch(String)
        case migrationMismatch(String)
    }

    private let handle: OpaquePointer
    private let url: URL

    /// Open (and optionally create) the database at `url`, applying PRAGMAs.
    public init(url: URL, createIfNeeded: Bool = true) throws {
        self.url = url
        // First-run ordering: ensure the parent directory (the managed root) exists
        // before opening. sqlite3_open does NOT create intermediate directories, so
        // a brand-new install would otherwise fail-closed with an unwritable path.
        if createIfNeeded {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
        }
        var flags: Int32 = SQLITE_OPEN_READWRITE
        if createIfNeeded { flags |= SQLITE_OPEN_CREATE }
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(url.path, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(rc)"
            if let db { sqlite3_close_v2(db) }
            throw DatabaseError.cannotOpen(msg)
        }
        self.handle = db
        // Fail closed if an existing file is not a usable database, before we touch
        // journal mode (a non-database file otherwise surfaces a generic sql error).
        if !Self.integrityOK(handle) {
            throw DatabaseError.notADatabase("integrity_check failed for \(url.lastPathComponent)")
        }
        try Self.applyPragmas(handle)
    }

    public func close() { sqlite3_close_v2(handle) }
    deinit { sqlite3_close_v2(handle) }

    private static func applyPragmas(_ db: OpaquePointer) throws {
        for sql in [
            "PRAGMA foreign_keys = ON;",
            "PRAGMA busy_timeout = 5000;",
            "PRAGMA journal_mode = WAL;",
            "PRAGMA synchronous = FULL;"
        ] { try rawExec(db, sql) }
    }

    private static func rawExec(_ db: OpaquePointer, _ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let m = err.map { String(cString: $0) } ?? "code \(rc)"
            sqlite3_free(err)
            throw DatabaseError.sql(m)
        }
    }

    private static func integrityOK(_ db: OpaquePointer) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA integrity_check;", -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else { return false }
        return String(cString: c) == "ok"
    }

    public func integrityCheck() throws -> Bool { Self.integrityOK(handle) }

    // MARK: - Migrations

    /// Highest applied schema version, or 0 if none.
    public func schemaVersion() throws -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT MAX(version) FROM schema_migrations;", -1, &stmt, nil) == SQLITE_OK else {
            // Table absent → version 0 (fresh DB).
            sqlite3_finalize(stmt)
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW { return Int(sqlite3_column_int64(stmt, 0)) }
        return 0
    }

    private static let v1 = """
    CREATE TABLE schema_migrations(version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL, checksum TEXT);
    CREATE TABLE roots(root_id TEXT PRIMARY KEY, category TEXT NOT NULL, display_name TEXT,
                       locator_type TEXT, status TEXT NOT NULL DEFAULT 'present',
                       created_at TEXT, last_scanned_at TEXT);
    CREATE TABLE external_files(file_id INTEGER PRIMARY KEY AUTOINCREMENT,
                       root_id TEXT NOT NULL REFERENCES roots(root_id) ON DELETE CASCADE,
                       relative_path TEXT NOT NULL, kind TEXT, size INTEGER, modified_at TEXT,
                       content_digest TEXT, indexed_at TEXT, last_seen_at TEXT, status TEXT,
                       UNIQUE(root_id, relative_path));
    CREATE TABLE agent_sessions(session_id TEXT PRIMARY KEY, adapter_id TEXT,
                       source_root_id TEXT REFERENCES roots(root_id), parent_session_id TEXT,
                       source_cursor TEXT, metadata_digest TEXT, sync_status TEXT, created_at TEXT);
    CREATE TABLE execution_states(state_id TEXT PRIMARY KEY, parent_id TEXT, model_identity TEXT,
                       position INTEGER, continuation_id TEXT, anchor TEXT, lifecycle TEXT, created_at TEXT);
    CREATE TABLE settlements(settlement_id TEXT PRIMARY KEY, state_id TEXT REFERENCES execution_states(state_id),
                       schema_version TEXT, payload BLOB, payload_digest TEXT, signature TEXT,
                       contract_version TEXT, settled_at TEXT, validation_status TEXT);
    CREATE TABLE settlement_bindings(binding_id INTEGER PRIMARY KEY AUTOINCREMENT,
                       settlement_id TEXT REFERENCES settlements(settlement_id) ON DELETE CASCADE,
                       name TEXT, value_digest TEXT, source_root_id TEXT, source_file_id INTEGER);
    CREATE TABLE dependency_edges(edge_id INTEGER PRIMARY KEY AUTOINCREMENT,
                       from_settlement TEXT, to_settlement TEXT, kind TEXT);
    CREATE TABLE migration_receipts(receipt_id INTEGER PRIMARY KEY AUTOINCREMENT,
                       source_kind TEXT, source_digest TEXT, result TEXT,
                       rows_imported INTEGER, completed_at TEXT);
    CREATE TABLE install_receipts(receipt_id INTEGER PRIMARY KEY AUTOINCREMENT,
                       step_id TEXT, recipe_id TEXT, revision TEXT, output_digest TEXT,
                       status TEXT, started_at TEXT, finished_at TEXT, error_class TEXT);
    CREATE TABLE bootstrap_runs(run_id INTEGER PRIMARY KEY AUTOINCREMENT,
                       step_id TEXT, status TEXT, fingerprint TEXT, detail TEXT, at TEXT);
    """

    /// v2 is purely additive: it lets the live execution graph (ES) round-trip
    /// through SQLite as the authoritative read/write store, without touching the
    /// settlement (IS) tables owned by the native gate. checkpoint state_id carries
    /// no FK so reconciling states can never cascade into settlements.
    private static let v2 = """
    ALTER TABLE execution_states ADD COLUMN next_input TEXT;
    ALTER TABLE execution_states ADD COLUMN prefix_json TEXT;
    ALTER TABLE execution_states ADD COLUMN checkpoint_ids_json TEXT;
    CREATE TABLE checkpoints(checkpoint_id TEXT PRIMARY KEY, state_id TEXT, model_identity TEXT,
                       position INTEGER, continuation_id TEXT, next_input TEXT, anchor TEXT,
                       prefix_json TEXT, created_at TEXT, checksum TEXT);
    """

    /// v3 is purely additive: it gives each settlement a per-row validity flag so
    /// the Information Space can express LOCAL dynamic invalidation. When an
    /// external work file (or its transitive dependency closure) changes, only the
    /// affected settlements flip to 'invalid'; unrelated valid results are kept.
    /// It never rewrites a settlement payload and stores no external file bytes —
    /// validity is metadata only, distinct from the native gate's validation_status.
    private static let v3 = """
    ALTER TABLE settlements ADD COLUMN validity TEXT NOT NULL DEFAULT 'valid';
    ALTER TABLE settlements ADD COLUMN invalidated_at TEXT;
    CREATE INDEX idx_settlements_validity ON settlements(validity);
    """

    /// v8 is the Information-Space physical carrier adopted from the Lab
    /// database-carrier replication design. It adds the content-addressed object
    /// store, append-only identity index, and dependency revision ledger, then
    /// links each existing IS table to an object instead of keeping inline bytes.
    /// The legacy inline columns stay (NOT NULL) but become empty for addressed
    /// rows, so old readers fail closed rather than silently reading stale
    /// copies.
    private static let v8Tables = """
    CREATE TABLE IF NOT EXISTS is_objects(
        object_id TEXT PRIMARY KEY,
        byte_size INTEGER NOT NULL,
        content BLOB NOT NULL,
        created_order INTEGER NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        CHECK(length(object_id)=64),
        CHECK(object_id=lower(object_id)),
        CHECK(byte_size>=0),
        CHECK(byte_size=length(content)),
        CHECK(created_order>0)
    );
    CREATE TABLE IF NOT EXISTS is_index_entries(
        append_order INTEGER PRIMARY KEY AUTOINCREMENT,
        srs_identity TEXT NOT NULL,
        record_object TEXT NOT NULL REFERENCES is_objects(object_id),
        recorded_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS is_dependency_entries(
        append_order INTEGER PRIMARY KEY AUTOINCREMENT,
        dependency_id TEXT NOT NULL,
        content_address TEXT NOT NULL REFERENCES is_objects(object_id),
        revision INTEGER NOT NULL CHECK(revision>0),
        reason TEXT NOT NULL,
        recorded_at TEXT NOT NULL
    );
    CREATE TRIGGER IF NOT EXISTS is_objects_append_only_update
        BEFORE UPDATE ON is_objects BEGIN
            SELECT RAISE(ABORT, 'is_objects is write-once');
        END;
    CREATE TRIGGER IF NOT EXISTS is_objects_append_only_delete
        BEFORE DELETE ON is_objects BEGIN
            SELECT RAISE(ABORT, 'is_objects is write-once');
        END;
    CREATE TRIGGER IF NOT EXISTS is_index_entries_append_only_update
        BEFORE UPDATE ON is_index_entries BEGIN
            SELECT RAISE(ABORT, 'is_index_entries is append-only');
        END;
    CREATE TRIGGER IF NOT EXISTS is_index_entries_append_only_delete
        BEFORE DELETE ON is_index_entries BEGIN
            SELECT RAISE(ABORT, 'is_index_entries is append-only');
        END;
    CREATE TRIGGER IF NOT EXISTS is_dependency_entries_append_only_update
        BEFORE UPDATE ON is_dependency_entries BEGIN
            SELECT RAISE(ABORT, 'is_dependency_entries is append-only');
        END;
    CREATE TRIGGER IF NOT EXISTS is_dependency_entries_append_only_delete
        BEFORE DELETE ON is_dependency_entries BEGIN
            SELECT RAISE(ABORT, 'is_dependency_entries is append-only');
        END;
    """

    /// Columns that attach existing IS rows to objects. Guarded individually so
    /// re-running v8 after a partial repair never tries to add them twice.
    private static let v8Columns: [(table: String, column: String, sql: String)] = [
        ("file_contents", "object_id",
         "ALTER TABLE file_contents ADD COLUMN object_id TEXT REFERENCES is_objects(object_id);"),
        ("chat_messages", "content_object_id",
         "ALTER TABLE chat_messages ADD COLUMN content_object_id TEXT REFERENCES is_objects(object_id);"),
        ("retrieval_settlements", "result_object_id",
         "ALTER TABLE retrieval_settlements ADD COLUMN result_object_id TEXT REFERENCES is_objects(object_id);"),
        ("settlements", "payload_object_id",
         "ALTER TABLE settlements ADD COLUMN payload_object_id TEXT REFERENCES is_objects(object_id);"),
    ]

    private static let v8Indexes = """
    CREATE INDEX IF NOT EXISTS idx_is_objects_created ON is_objects(created_order);
    CREATE INDEX IF NOT EXISTS idx_is_index_identity ON is_index_entries(srs_identity, append_order);
    CREATE INDEX IF NOT EXISTS idx_is_dependency_current
        ON is_dependency_entries(dependency_id, append_order);
    CREATE INDEX IF NOT EXISTS idx_file_contents_object ON file_contents(object_id);
    CREATE INDEX IF NOT EXISTS idx_chat_messages_object ON chat_messages(content_object_id);
    CREATE INDEX IF NOT EXISTS idx_retrieval_settlements_object ON retrieval_settlements(result_object_id);
    CREATE INDEX IF NOT EXISTS idx_settlements_object ON settlements(payload_object_id);
    """

    /// Apply pending migrations, each inside its own transaction. Idempotent.
    public func runMigrations() throws {
        if try schemaVersion() < 1 {
            try transaction {
                try Self.rawExec(handle, SimiGoESISDatabase.v1)
                try recordMigrationRow(1, "simigo-es-is-v1")
            }
        }
        if try schemaVersion() < 2 {
            try transaction {
                try Self.rawExec(handle, SimiGoESISDatabase.v2)
                try recordMigrationRow(2, "simigo-es-is-v2")
            }
        }
        if try schemaVersion() < 3 {
            try transaction {
                try Self.rawExec(handle, SimiGoESISDatabase.v3)
                try recordMigrationRow(3, "simigo-es-is-v3")
            }
        }
        if try schemaVersion() < 4 {
            try transaction {
                try Self.rawExec(handle, """
                CREATE TABLE chat_messages(
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    session_id TEXT NOT NULL,
                    role TEXT NOT NULL,
                    content TEXT NOT NULL,
                    model TEXT,
                    content_sha256 TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                CREATE INDEX idx_chat_messages_session ON chat_messages(session_id, id);
                """)
                try recordMigrationRow(4, "simigo-chat-persistence-v4")
            }
        }
        if try schemaVersion() < 5 {
            try transaction {
                try Self.rawExec(handle, """
                CREATE TABLE file_contents(
                    root_id TEXT NOT NULL REFERENCES roots(root_id) ON DELETE CASCADE,
                    relative_path TEXT NOT NULL,
                    content_sha256 TEXT NOT NULL,
                    content TEXT NOT NULL,
                    settled_at TEXT NOT NULL,
                    PRIMARY KEY(root_id, relative_path)
                );
                """)
                try recordMigrationRow(5, "simigo-file-content-settle-v5")
            }
        }
        if try schemaVersion() < 6 {
            try transaction {
                try Self.rawExec(handle, """
                CREATE TABLE retrieval_settlements(
                    demand_id TEXT PRIMARY KEY,
                    query TEXT NOT NULL,
                    root_ids TEXT NOT NULL,
                    inputs_digest TEXT NOT NULL,
                    result_sha256 TEXT NOT NULL,
                    result_json TEXT NOT NULL,
                    hit_count INTEGER NOT NULL,
                    status TEXT NOT NULL,
                    settled_at TEXT NOT NULL
                );
                """)
                try recordMigrationRow(6, "simigo-demand-retrieval-settlement-v6")
            }
        }
        // Repair pass: a build shipped with the v4/v5/v6 gates out of order, so
        // MAX(version) moved straight to 6 and skipped the table creation for
        // chat_messages and file_contents. Those databases report v6 while the
        // tables are absent. Re-assert every later table idempotently.
        if try schemaVersion() < 7 {
            try transaction {
                try Self.rawExec(handle, """
                CREATE TABLE IF NOT EXISTS chat_messages(
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    session_id TEXT NOT NULL,
                    role TEXT NOT NULL,
                    content TEXT NOT NULL,
                    model TEXT,
                    content_sha256 TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_chat_messages_session
                    ON chat_messages(session_id, id);
                CREATE TABLE IF NOT EXISTS file_contents(
                    root_id TEXT NOT NULL REFERENCES roots(root_id) ON DELETE CASCADE,
                    relative_path TEXT NOT NULL,
                    content_sha256 TEXT NOT NULL,
                    content TEXT NOT NULL,
                    settled_at TEXT NOT NULL,
                    PRIMARY KEY(root_id, relative_path)
                );
                CREATE TABLE IF NOT EXISTS retrieval_settlements(
                    demand_id TEXT PRIMARY KEY,
                    query TEXT NOT NULL,
                    root_ids TEXT NOT NULL,
                    inputs_digest TEXT NOT NULL,
                    result_sha256 TEXT NOT NULL,
                    result_json TEXT NOT NULL,
                    hit_count INTEGER NOT NULL,
                    status TEXT NOT NULL,
                    settled_at TEXT NOT NULL
                );
                """)
                try recordMigrationRow(7, "simigo-schema-repair-v7")
            }
        }
        if try schemaVersion() < 8 {
            try transaction {
                try Self.rawExec(handle, SimiGoESISDatabase.v8Tables)
                for column in SimiGoESISDatabase.v8Columns
                where try !columnExists(column.table, column.column) {
                    try Self.rawExec(handle, column.sql)
                }
                try Self.rawExec(handle, SimiGoESISDatabase.v8Indexes)
                try backfillCarrierObjectsV8()
                try recordMigrationRow(8, "simigo-is-carrier-v8")
            }
        }
    }

    private func columnExists(_ table: String, _ column: String) throws -> Bool {
        let stmt = try prepare("PRAGMA table_info(\(table));")
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 1), String(cString: c) == column {
                return true
            }
        }
        return false
    }

    // MARK: - Information-Space physical carrier

    /// Hash-verified immutable object. `object_id` is the lowercase SHA-256 of
    /// `content`; the database is only a carrier, so it never reinterprets the
    /// bytes.
    public struct CarrierObject: Equatable, Sendable {
        public let objectID: String
        public let byteSize: Int
        public let content: Data
        public let createdOrder: Int
    }

    public struct CarrierReport: Equatable, Sendable {
        public let schemaVersion: Int
        public let objectCount: Int
        public let objectBytes: Int64
        public let indexEntries: Int
        public let dependencyEntries: Int
        public let unaddressedFileContents: Int
        public let unaddressedChatMessages: Int
        public let unaddressedRetrievalResults: Int
        public let unaddressedSettlements: Int
        public let danglingReferences: Int
        public let corruptObjects: Int
        public let inlineLegacyPayloads: Int
        public let deepVerified: Bool
    }

    public enum IndexResolutionPolicy: Sendable {
        /// First matching entry, per the Lab design for ordinary SRS identities.
        case first
        /// Last matching entry, for mutable product identities (file/demand/...).
        case last
    }

    public struct IndexEntry: Equatable, Sendable {
        public let appendOrder: Int
        public let identity: String
        public let objectID: String
        public let recordedAt: String
    }

    public struct DependencyEntry: Equatable, Sendable {
        public let appendOrder: Int
        public let dependencyID: String
        public let contentAddress: String
        public let revision: Int
        public let reason: String
        public let recordedAt: String
    }

    /// Write bytes once and return their content address. Re-writing identical
    /// bytes is a verified no-op; a hash collision with different bytes fails
    /// closed.
    @discardableResult
    public func writeObject(_ data: Data) throws -> String {
        var objectID = ""
        try transaction {
            objectID = try ensureObject(data)
        }
        return objectID
    }

    /// Read an object and verify that its bytes still hash to its address.
    public func readObject(_ objectID: String) throws -> Data {
        let stmt = try prepare("SELECT byte_size, content FROM is_objects WHERE object_id=?;")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, objectID)
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw DatabaseError.sql("readObject: missing object \(objectID)")
        }
        let size = Int(sqlite3_column_int64(stmt, 0))
        let bytes = Int(sqlite3_column_bytes(stmt, 1))
        let data: Data
        if let base = sqlite3_column_blob(stmt, 1), bytes > 0 {
            data = Data(bytes: base, count: bytes)
        } else {
            data = Data()
        }
        guard data.count == size, NativeSHA256.hexDigest(data) == objectID else {
            throw DatabaseError.sql("readObject: byte/address mismatch for \(objectID)")
        }
        return data
    }

    public func objectRow(_ objectID: String) throws -> CarrierObject? {
        let stmt = try prepare("""
        SELECT object_id, byte_size, content, created_order FROM is_objects WHERE object_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, objectID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let bytes = Int(sqlite3_column_bytes(stmt, 2))
        let data: Data
        if let base = sqlite3_column_blob(stmt, 2), bytes > 0 {
            data = Data(bytes: base, count: bytes)
        } else {
            data = Data()
        }
        return CarrierObject(
            objectID: sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "",
            byteSize: Int(sqlite3_column_int64(stmt, 1)),
            content: data,
            createdOrder: Int(sqlite3_column_int64(stmt, 3)))
    }

    /// Append an identity → object entry. History is never overwritten; callers
    /// choose first/last resolution when reading.
    @discardableResult
    public func appendIndexEntry(identity: String, objectID: String) throws -> Int {
        var order = 0
        try transaction {
            order = try appendIndexEntryInTransaction(identity: identity, objectID: objectID)
        }
        return order
    }

    /// Resolve an identity from the append-only index.
    public func resolveIndexIdentity(
        _ identity: String, policy: IndexResolutionPolicy = .last
    ) throws -> IndexEntry? {
        let direction = policy == .first ? "ASC" : "DESC"
        let stmt = try prepare("""
        SELECT append_order, srs_identity, record_object, recorded_at
        FROM is_index_entries WHERE srs_identity=?
        ORDER BY append_order \(direction) LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, identity)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return IndexEntry(
            appendOrder: Int(sqlite3_column_int64(stmt, 0)),
            identity: sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "",
            objectID: sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "",
            recordedAt: sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? "")
    }

    /// Append the next explicit revision for a dependency identity.
    @discardableResult
    public func appendDependency(
        dependencyID: String, contentAddress: String, reason: String
    ) throws -> Int {
        var revision = 0
        try transaction {
            revision = try appendDependencyInTransaction(
                dependencyID: dependencyID, contentAddress: contentAddress, reason: reason)
        }
        return revision
    }

    /// Current dependency by LAST entry per dependency_id.
    public func currentDependency(_ dependencyID: String) throws -> DependencyEntry? {
        let history = try dependencyHistory(dependencyID)
        return history.last
    }

    /// Full append-only history for a dependency identity.
    public func dependencyHistory(_ dependencyID: String) throws -> [DependencyEntry] {
        let stmt = try prepare("""
        SELECT append_order, dependency_id, content_address, revision, reason, recorded_at
        FROM is_dependency_entries WHERE dependency_id=? ORDER BY append_order;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, dependencyID)
        var out: [DependencyEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func text(_ i: Int32) -> String {
                sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
            }
            out.append(DependencyEntry(
                appendOrder: Int(sqlite3_column_int64(stmt, 0)),
                dependencyID: text(1), contentAddress: text(2),
                revision: Int(sqlite3_column_int64(stmt, 3)),
                reason: text(4), recordedAt: text(5)))
        }
        return out
    }

    /// Carrier health. `deepVerify` re-hashes every object; the cheap form only
    /// checks structural links and legacy inline residue.
    public func carrierReport(deepVerify: Bool = false) throws -> CarrierReport {
        var objectCount = 0, objectBytes: Int64 = 0
        let obj = try prepare("SELECT COUNT(*), COALESCE(SUM(byte_size),0) FROM is_objects;")
        if sqlite3_step(obj) == SQLITE_ROW {
            objectCount = Int(sqlite3_column_int64(obj, 0))
            objectBytes = sqlite3_column_int64(obj, 1)
        }
        sqlite3_finalize(obj)

        var corrupt = 0
        if deepVerify {
            let all = try prepare("SELECT object_id FROM is_objects;")
            defer { sqlite3_finalize(all) }
            var ids: [String] = []
            while sqlite3_step(all) == SQLITE_ROW, let c = sqlite3_column_text(all, 0) {
                ids.append(String(cString: c))
            }
            for id in ids {
                if (try? readObject(id)) == nil { corrupt += 1 }
            }
        }

        func scalar(_ sql: String) throws -> Int {
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
        }

        return CarrierReport(
            schemaVersion: try schemaVersion(),
            objectCount: objectCount,
            objectBytes: objectBytes,
            indexEntries: try scalar("SELECT COUNT(*) FROM is_index_entries;"),
            dependencyEntries: try scalar("SELECT COUNT(*) FROM is_dependency_entries;"),
            unaddressedFileContents: try scalar(
                "SELECT COUNT(*) FROM file_contents WHERE object_id IS NULL;"),
            unaddressedChatMessages: try scalar(
                "SELECT COUNT(*) FROM chat_messages WHERE content_object_id IS NULL;"),
            unaddressedRetrievalResults: try scalar(
                "SELECT COUNT(*) FROM retrieval_settlements WHERE result_object_id IS NULL;"),
            unaddressedSettlements: try scalar(
                "SELECT COUNT(*) FROM settlements WHERE payload_object_id IS NULL;"),
            danglingReferences: try scalar("""
                SELECT
                  (SELECT COUNT(*) FROM file_contents f LEFT JOIN is_objects o
                     ON o.object_id=f.object_id WHERE f.object_id IS NOT NULL AND o.object_id IS NULL)
                + (SELECT COUNT(*) FROM chat_messages c LEFT JOIN is_objects o
                     ON o.object_id=c.content_object_id
                   WHERE c.content_object_id IS NOT NULL AND o.object_id IS NULL)
                + (SELECT COUNT(*) FROM retrieval_settlements r LEFT JOIN is_objects o
                     ON o.object_id=r.result_object_id
                   WHERE r.result_object_id IS NOT NULL AND o.object_id IS NULL)
                + (SELECT COUNT(*) FROM settlements s LEFT JOIN is_objects o
                     ON o.object_id=s.payload_object_id
                   WHERE s.payload_object_id IS NOT NULL AND o.object_id IS NULL);
                """),
            corruptObjects: corrupt,
            inlineLegacyPayloads: try scalar("""
                SELECT (SELECT COUNT(*) FROM file_contents WHERE length(content)>0)
                     + (SELECT COUNT(*) FROM chat_messages WHERE length(content)>0)
                     + (SELECT COUNT(*) FROM retrieval_settlements WHERE length(result_json)>0)
                     + (SELECT COUNT(*) FROM settlements WHERE length(payload)>0);
                """),
            deepVerified: deepVerify)
    }

    private func ensureObject(_ data: Data) throws -> String {
        try ensureObjectWithStatus(data).id
    }

    private func ensureObjectWithStatus(_ data: Data) throws -> (id: String, created: Bool) {
        let objectID = NativeSHA256.hexDigest(data)
        let existing = try prepare("SELECT byte_size, content FROM is_objects WHERE object_id=?;")
        defer { sqlite3_finalize(existing) }
        bind(existing, 1, objectID)
        if sqlite3_step(existing) == SQLITE_ROW {
            let size = Int(sqlite3_column_int64(existing, 0))
            let bytes = Int(sqlite3_column_bytes(existing, 1))
            let stored: Data
            if let base = sqlite3_column_blob(existing, 1), bytes > 0 {
                stored = Data(bytes: base, count: bytes)
            } else {
                stored = Data()
            }
            guard size == data.count, stored == data else {
                throw DatabaseError.sql("object \(objectID) already exists with different bytes")
            }
            return (objectID, false)
        }
        let orderStmt = try prepare("SELECT COALESCE(MAX(created_order),0)+1 FROM is_objects;")
        let nextOrder: Int
        if sqlite3_step(orderStmt) == SQLITE_ROW {
            nextOrder = Int(sqlite3_column_int64(orderStmt, 0))
        } else {
            nextOrder = 1
        }
        sqlite3_finalize(orderStmt)
        try execBinding("""
        INSERT INTO is_objects(object_id, byte_size, content, created_order, created_at)
        VALUES(?,?,?,?,?);
        """) { stmt in
            bind(stmt, 1, objectID)
            bind(stmt, 2, Int64(data.count))
            bind(stmt, 3, data)
            bind(stmt, 4, Int64(nextOrder))
            bind(stmt, 5, Self.stamp(Date()))
        }
        return (objectID, true)
    }

    private func appendIndexEntryInTransaction(identity: String, objectID: String) throws -> Int {
        try execBinding("""
        INSERT INTO is_index_entries(srs_identity, record_object, recorded_at)
        VALUES(?,?,?);
        """) { stmt in
            bind(stmt, 1, identity)
            bind(stmt, 2, objectID)
            bind(stmt, 3, Self.stamp(Date()))
        }
        return Int(sqlite3_last_insert_rowid(handle))
    }

    private func appendDependencyInTransaction(
        dependencyID: String, contentAddress: String, reason: String
    ) throws -> Int {
        let revisionStmt = try prepare("""
        SELECT COALESCE(MAX(revision),0)+1 FROM is_dependency_entries WHERE dependency_id=?;
        """)
        bind(revisionStmt, 1, dependencyID)
        let revision: Int
        if sqlite3_step(revisionStmt) == SQLITE_ROW {
            revision = Int(sqlite3_column_int64(revisionStmt, 0))
        } else {
            revision = 1
        }
        sqlite3_finalize(revisionStmt)
        try execBinding("""
        INSERT INTO is_dependency_entries(
            dependency_id, content_address, revision, reason, recorded_at)
        VALUES(?,?,?,?,?);
        """) { stmt in
            bind(stmt, 1, dependencyID)
            bind(stmt, 2, contentAddress)
            bind(stmt, 3, Int64(revision))
            bind(stmt, 4, reason)
            bind(stmt, 5, Self.stamp(Date()))
        }
        return revision
    }

    /// One-time v8 backfill: move every inline IS payload into the object store,
    /// append its identity, and empty the legacy inline column. Runs inside the
    /// migration transaction; a failure rolls the whole v8 step back.
    private func backfillCarrierObjectsV8() throws {
        struct InlineFile {
            let root: String; let path: String; let content: String
        }
        var files: [InlineFile] = []
        let fileStmt = try prepare("""
        SELECT root_id, relative_path, content FROM file_contents WHERE object_id IS NULL;
        """)
        while sqlite3_step(fileStmt) == SQLITE_ROW {
            files.append(InlineFile(
                root: sqlite3_column_text(fileStmt, 0).map { String(cString: $0) } ?? "",
                path: sqlite3_column_text(fileStmt, 1).map { String(cString: $0) } ?? "",
                content: sqlite3_column_text(fileStmt, 2).map { String(cString: $0) } ?? ""))
        }
        sqlite3_finalize(fileStmt)
        for file in files {
            let objectID = try ensureObject(Data(file.content.utf8))
            try execBinding("""
            UPDATE file_contents SET object_id=?, content_sha256=?, content=''
            WHERE root_id=? AND relative_path=?;
            """) { stmt in
                bind(stmt, 1, objectID)
                bind(stmt, 2, objectID)
                bind(stmt, 3, file.root)
                bind(stmt, 4, file.path)
            }
            _ = try appendIndexEntryInTransaction(
                identity: "file:\(file.root)/\(file.path)", objectID: objectID)
            _ = try appendDependencyInTransaction(
                dependencyID: "file:\(file.root)/\(file.path)",
                contentAddress: objectID, reason: "v8-backfill")
            try execBinding("""
            UPDATE external_files SET content_digest=?
            WHERE root_id=? AND relative_path=?;
            """) { stmt in
                bind(stmt, 1, objectID)
                bind(stmt, 2, file.root)
                bind(stmt, 3, file.path)
            }
        }

        struct InlineChat {
            let id: Int64; let session: String; let content: String
        }
        var chats: [InlineChat] = []
        let chatStmt = try prepare("""
        SELECT id, session_id, content FROM chat_messages WHERE content_object_id IS NULL;
        """)
        while sqlite3_step(chatStmt) == SQLITE_ROW {
            chats.append(InlineChat(
                id: sqlite3_column_int64(chatStmt, 0),
                session: sqlite3_column_text(chatStmt, 1).map { String(cString: $0) } ?? "",
                content: sqlite3_column_text(chatStmt, 2).map { String(cString: $0) } ?? ""))
        }
        sqlite3_finalize(chatStmt)
        for chat in chats {
            let objectID = try ensureObject(Data(chat.content.utf8))
            try execBinding("""
            UPDATE chat_messages SET content_object_id=?, content_sha256=?, content=''
            WHERE id=?;
            """) { stmt in
                bind(stmt, 1, objectID)
                bind(stmt, 2, objectID)
                bind(stmt, 3, chat.id)
            }
            _ = try appendIndexEntryInTransaction(
                identity: "chat:\(chat.session)/\(chat.id)", objectID: objectID)
        }

        struct InlineRetrieval {
            let demandID: String; let resultJSON: String
        }
        var retrievals: [InlineRetrieval] = []
        let retrievalStmt = try prepare("""
        SELECT demand_id, result_json FROM retrieval_settlements WHERE result_object_id IS NULL;
        """)
        while sqlite3_step(retrievalStmt) == SQLITE_ROW {
            retrievals.append(InlineRetrieval(
                demandID: sqlite3_column_text(retrievalStmt, 0).map { String(cString: $0) } ?? "",
                resultJSON: sqlite3_column_text(retrievalStmt, 1).map { String(cString: $0) } ?? ""))
        }
        sqlite3_finalize(retrievalStmt)
        for retrieval in retrievals {
            let objectID = try ensureObject(Data(retrieval.resultJSON.utf8))
            try execBinding("""
            UPDATE retrieval_settlements SET result_object_id=?, result_sha256=?, result_json=''
            WHERE demand_id=?;
            """) { stmt in
                bind(stmt, 1, objectID)
                bind(stmt, 2, objectID)
                bind(stmt, 3, retrieval.demandID)
            }
            _ = try appendIndexEntryInTransaction(
                identity: "demand:\(retrieval.demandID)", objectID: objectID)
        }

        struct InlineSettlement {
            let id: String; let payload: Data
        }
        var settlements: [InlineSettlement] = []
        let settlementStmt = try prepare("""
        SELECT settlement_id, payload FROM settlements WHERE payload_object_id IS NULL;
        """)
        while sqlite3_step(settlementStmt) == SQLITE_ROW {
            let bytes = Int(sqlite3_column_bytes(settlementStmt, 1))
            let payload: Data
            if let base = sqlite3_column_blob(settlementStmt, 1), bytes > 0 {
                payload = Data(bytes: base, count: bytes)
            } else {
                payload = Data()
            }
            settlements.append(InlineSettlement(
                id: sqlite3_column_text(settlementStmt, 0).map { String(cString: $0) } ?? "",
                payload: payload))
        }
        sqlite3_finalize(settlementStmt)
        for settlement in settlements {
            let objectID = try ensureObject(settlement.payload)
            try execBinding("""
            UPDATE settlements SET payload_object_id=?, payload=X'' WHERE settlement_id=?;
            """) { stmt in
                bind(stmt, 1, objectID)
                bind(stmt, 2, settlement.id)
            }
            _ = try appendIndexEntryInTransaction(
                identity: "settlement:\(settlement.id)", objectID: objectID)
        }
    }

    private func recordMigrationRow(_ version: Int, _ checksum: String) throws {
        try execBinding("INSERT INTO schema_migrations(version, applied_at, checksum) VALUES(?,?,?);") { stmt in
            bind(stmt, 1, Int64(version))
            bind(stmt, 2, Self.stamp( Date()))
            bind(stmt, 3, checksum)
        }
    }

    // MARK: - Transaction helpers

    private func begin(_ mode: String) throws { try Self.rawExec(handle, "BEGIN \(mode);") }
    private func commit() throws { try Self.rawExec(handle, "COMMIT;") }
    private func rollback() { _ = sqlite3_exec(handle, "ROLLBACK;", nil, nil, nil) }

    /// Run `body` inside a transaction; roll back and rethrow on any error.
    public func transaction(_ body: () throws -> Void) throws {
        try begin("IMMEDIATE")
        do { try body(); try commit() }
        catch { rollback(); throw error }
    }

    public func count(_ table: String) throws -> Int {
        var stmt: OpaquePointer?
        // table name is internal constant only, never user input.
        guard sqlite3_prepare_v2(handle, "SELECT COUNT(*) FROM \(table);", -1, &stmt, nil) == SQLITE_OK
        else { sqlite3_finalize(stmt); throw DatabaseError.sql("count prepare failed") }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW { return Int(sqlite3_column_int64(stmt, 0)) }
        return 0
    }

    // MARK: - Statement binding helpers

    private static let transient: sqlite3_destructor_type? = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) != SQLITE_OK || stmt == nil {
            let m = sqlite3_errmsg(handle).map { String(cString: $0) } ?? "prepare failed"
            throw DatabaseError.sql(m)
        }
        return stmt!
    }

    private func bind(_ stmt: OpaquePointer, _ i: Int32, _ text: String) {
        sqlite3_bind_text(stmt, i, text, -1, Self.transient)
    }
    private func bind(_ stmt: OpaquePointer, _ i: Int32, _ value: Int64) {
        sqlite3_bind_int64(stmt, i, value)
    }
    private func bind(_ stmt: OpaquePointer, _ i: Int32, _ blob: Data) {
        if blob.isEmpty {
            // sqlite3_bind_blob(nil, 0) binds NULL; a zero blob must stay NOT NULL.
            _ = sqlite3_bind_zeroblob(stmt, i, 0)
            return
        }
        blob.withUnsafeBytes { _ = sqlite3_bind_blob(stmt, i, $0.baseAddress, Int32(blob.count), Self.transient) }
    }
    private func bind(_ stmt: OpaquePointer, _ i: Int32, _ optional: String?) {
        if let optional { bind(stmt, i, optional) } else { sqlite3_bind_null(stmt, i) }
    }
    private func bind(_ stmt: OpaquePointer, _ i: Int32, _ optional: Int64?) {
        if let optional { bind(stmt, i, optional) } else { sqlite3_bind_null(stmt, i) }
    }

    /// Run a single write statement with bindings applied by `apply` before the step.
    @discardableResult
    private func execBinding(_ sql: String, _ apply: (OpaquePointer) -> Void) throws -> Int {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        apply(stmt)
        if sqlite3_step(stmt) != SQLITE_DONE {
            let m = sqlite3_errmsg(handle).map { String(cString: $0) } ?? "step failed"
            throw DatabaseError.sql(m)
        }
        return Int(sqlite3_changes(handle))
    }

    // MARK: - Execution state write

    /// A child Execution State recorded in the SAME authoritative transaction as
    /// its settlement (continuation path). Fields mirror `recordExecutionState`.
    public struct ChildExecutionState: Sendable {
        public let id: String
        public let parentID: String
        public let modelIdentity: String
        public let position: Int
        public let continuationID: String
        public let anchor: String
        public let createdAt: Date

        public init(id: String, parentID: String, modelIdentity: String,
                    position: Int, continuationID: String, anchor: String,
                    createdAt: Date) {
            self.id = id
            self.parentID = parentID
            self.modelIdentity = modelIdentity
            self.position = position
            self.continuationID = continuationID
            self.anchor = anchor
            self.createdAt = createdAt
        }
    }

    /// Upsert an execution state into the authoritative store. Used by the app to
    /// mirror its execution graph into SQLite and to satisfy settlement FKs.
    public func recordExecutionState(id: String, parentID: String?, modelIdentity: String,
                                     position: Int, continuationID: String, anchor: String,
                                     lifecycle: String, createdAt: Date) throws {
        try insertExecutionStateRow(
            id: id, parentID: parentID, modelIdentity: modelIdentity,
            position: position, continuationID: continuationID, anchor: anchor,
            lifecycle: lifecycle, createdAt: createdAt)
    }

    /// Caller owns the transaction. Shared by the standalone upsert and the
    /// atomic child-state + settlement commit, so a continuation can create its
    /// child ES and settle it as one authoritative unit.
    private func insertExecutionStateRow(id: String, parentID: String?, modelIdentity: String,
                                         position: Int, continuationID: String, anchor: String,
                                         lifecycle: String, createdAt: Date) throws {
        try execBinding("""
        INSERT INTO execution_states(state_id, parent_id, model_identity, position, continuation_id, anchor, lifecycle, created_at)
        VALUES(?,?,?,?,?,?,?,?)
        ON CONFLICT(state_id) DO UPDATE SET
            parent_id=excluded.parent_id, model_identity=excluded.model_identity, position=excluded.position,
            continuation_id=excluded.continuation_id, anchor=excluded.anchor, lifecycle=excluded.lifecycle,
            created_at=excluded.created_at;
        """) { stmt in
            bind(stmt, 1, id)
            bind(stmt, 2, parentID)
            bind(stmt, 3, modelIdentity)
            bind(stmt, 4, Int64(position))
            bind(stmt, 5, continuationID)
            bind(stmt, 6, anchor)
            bind(stmt, 7, lifecycle)
            bind(stmt, 8, Self.stamp( createdAt))
        }
    }

    // MARK: - Native-authorized settlement (write authority)

    /// Commit a native-authorized settlement into the authoritative store, together
    /// with one binding row per satisfied constraint. Callers must only pass a
    /// `SettledResult` produced by `SimiGoSettlementAuthority` (the gate already
    /// ran); this performs no contract validation of its own.
    @discardableResult
    public func recordNativeSettlement(_ settled: SimiGoSettlementAuthority.SettledResult, stateID: String?) throws -> String {
        let settlementID = UUID().uuidString
        try transaction {
            try insertNativeSettlementRows(settled, settlementID: settlementID, stateID: stateID)
        }
        return settlementID
    }

    /// Atomically record a native-authorized settlement and both producer-identity
    /// bindings. The returned UUID is the ID created by THIS transaction; callers
    /// must not query "latest for state" to guess which row their write created.
    ///
    /// If any identity-binding insert fails, SQLite rolls the settlement row and
    /// all contract-binding rows back with it. Success therefore means the complete
    /// settlement + producer identity record committed as one authoritative unit.
    ///
    /// `childState`, when present, is inserted INSIDE the same transaction: a
    /// continuation therefore cannot commit a settlement without its child ES,
    /// and cannot leave a child ES behind when the settlement fails.
    @discardableResult
    public func recordNativeSettlementWithIdentity(
        _ settled: SimiGoSettlementAuthority.SettledResult,
        stateID: String,
        identity: SimiGoSettlementIdentityBinding.Identity,
        childState: ChildExecutionState? = nil
    ) throws -> UUID {
        let settlementUUID = UUID()
        let settlementID = settlementUUID.uuidString
        try transaction {
            if let childState {
                try insertExecutionStateRow(
                    id: childState.id, parentID: childState.parentID,
                    modelIdentity: childState.modelIdentity, position: childState.position,
                    continuationID: childState.continuationID, anchor: childState.anchor,
                    lifecycle: "active", createdAt: childState.createdAt)
            }
            try insertNativeSettlementRows(
                settled, settlementID: settlementID, stateID: stateID)
            try insertIdentityBindingRows(
                settlementID: settlementID, identity: identity)
        }
        return settlementUUID
    }

    /// Insert the settlement row and the native gate's constraint-binding rows.
    /// Caller owns the transaction so this can participate in the atomic identity
    /// commit without opening a nested transaction.
    private func insertNativeSettlementRows(
        _ settled: SimiGoSettlementAuthority.SettledResult,
        settlementID: String,
        stateID: String?
    ) throws {
        let payloadObject = try ensureObject(settled.validatedPayload)
        try execBinding("""
        INSERT INTO settlements(settlement_id, state_id, schema_version, payload, payload_digest, signature, contract_version, settled_at, validation_status, payload_object_id)
        VALUES(?,?,?,?,?,?,?,?,?,?);
        """) { stmt in
            bind(stmt, 1, settlementID)
            bind(stmt, 2, stateID)
            bind(stmt, 3, settled.schemaVersion)
            bind(stmt, 4, Data())
            bind(stmt, 5, settled.payloadDigest)
            bind(stmt, 6, String?.none)
            bind(stmt, 7, NativeResultContract.supportedVersion)
            bind(stmt, 8, Self.stamp(settled.settledAt))
            bind(stmt, 9, settled.trace.validationStatus)
            bind(stmt, 10, payloadObject)
        }
        _ = try appendIndexEntryInTransaction(
            identity: "settlement:\(settlementID)", objectID: payloadObject)
        for ct in settled.trace.constraintChecks {
            try execBinding("INSERT INTO settlement_bindings(settlement_id, name, value_digest, source_root_id, source_file_id) VALUES(?,?,?,?,?);") { stmt in
                bind(stmt, 1, settlementID)
                bind(stmt, 2, ct.binding ?? ct.field)
                bind(stmt, 3, ct.kind)
                bind(stmt, 4, String?.none)
                bind(stmt, 5, nil as Int64?)
            }
        }
    }

    // MARK: - Producer identity binding (settlement <-> engine identity)

    /// Persist the producer's identity digests alongside an existing settlement.
    /// Re-running replaces the same two rows instead of appending duplicates, and
    /// only digests are stored (never the model path or any weight bytes). This is
    /// a binding written by the producer itself; it is not an attestation.
    public func recordIdentityBindings(
        settlementID: String,
        identity: SimiGoSettlementIdentityBinding.Identity
    ) throws {
        try transaction {
            try insertIdentityBindingRows(settlementID: settlementID, identity: identity)
        }
    }

    /// Caller owns the transaction. This helper is shared by the legacy binding
    /// update and the atomic settlement+identity commit.
    private func insertIdentityBindingRows(
        settlementID: String,
        identity: SimiGoSettlementIdentityBinding.Identity
    ) throws {
        let rows = SimiGoSettlementIdentityBinding.bindings(for: identity)
        for name in rows.keys.sorted() {
            guard let digest = rows[name] else { continue }
            try execBinding("DELETE FROM settlement_bindings WHERE settlement_id=? AND name=?;") { stmt in
                bind(stmt, 1, settlementID)
                bind(stmt, 2, name)
            }
            try execBinding("""
            INSERT INTO settlement_bindings(settlement_id, name, value_digest, source_root_id, source_file_id)
            VALUES(?,?,?,?,?);
            """) { stmt in
                bind(stmt, 1, settlementID)
                bind(stmt, 2, name)
                bind(stmt, 3, digest)
                bind(stmt, 4, String?.none)
                bind(stmt, 5, nil as Int64?)
            }
        }
    }

    /// Binding rows recorded for one settlement, as name -> digest. Constraint
    /// bindings from the native gate live in the same table, so callers must look
    /// up the `producer.` keys rather than assume the dictionary is exhaustive.
    public func settlementBindings(settlementID: String) throws -> [String: String] {
        let stmt = try prepare("""
        SELECT name, value_digest FROM settlement_bindings WHERE settlement_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, settlementID)
        var out: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let value = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            if !name.isEmpty { out[name] = value }
        }
        return out
    }

    /// Newest settlement recorded for a state, or nil when the state never settled.
    public func latestSettlementID(forStateID stateID: String) throws -> String? {
        let stmt = try prepare("""
        SELECT settlement_id FROM settlements WHERE state_id=?
        ORDER BY settled_at DESC, settlement_id DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, stateID)
        if sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
            return String(cString: c)
        }
        return nil
    }

    // MARK: - External roots / work-file / agent-session indexing
    //
    // The database stores INDEXES and metadata only — NEVER the external file
    /// Remove a registered root (cascades its indexed files). Idempotent.
    public func removeRoot(rootID: String) throws {
        try execBinding("DELETE FROM roots WHERE root_id = ?;") { stmt in
            bind(stmt, 1, rootID)
        }
    }

    public struct RootRow: Equatable, Sendable {
        public let rootID: String
        public let category: String
        public let displayName: String?
        public let locatorType: String?
        public let status: String
    }

    /// List registered external roots (optionally one category), read-only.
    /// Same index-read pattern as ``listExternalFiles(rootID:)``.
    public func listRoots(category: String? = nil) throws -> [RootRow] {
        let sql = category == nil
            ? "SELECT root_id, category, display_name, locator_type, status FROM roots ORDER BY root_id;"
            : "SELECT root_id, category, display_name, locator_type, status FROM roots WHERE category='"
                + category!.replacingOccurrences(of: "'", with: "''") + "' ORDER BY root_id;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var rows: [RootRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func col(_ i: Int32) -> String {
                guard let c = sqlite3_column_text(stmt, i) else { return "" }
                return String(cString: c)
            }
            rows.append(RootRow(
                rootID: col(0), category: col(1), displayName: col(2),
                locatorType: col(3), status: col(4)))
        }
        return rows
    }

    // MARK: - 工作目录内容结算（ES/IS：索引执行的结果落库，Δ 复用）

    public struct ContentSettleReport: Equatable, Sendable {
        public let scanned: Int
        public let reused: Int
        public let settled: Int
        public let skippedBinaryOrLarge: Int
        public let changed: Int
        public let removed: Int
        public let invalidatedSettlements: Int
        public let objectsCreated: Int
        public let deduplicated: Int
        public let bytesAddressed: Int
    }

    private struct FileContentState {
        let digest: String
        let objectID: String?
    }

    private struct PendingSettlement {
        let relativePath: String
        let url: URL
        let data: Data
        let digest: String
        let previous: FileContentState?
    }

    /// 结算一个工作根：逐文件计算 SHA-256，内容写入内容寻址对象库
    /// （相同字节只存一次），`file_contents` 只保留身份/摘要引用；索引与
    /// 依赖账本追加记录，历史不覆盖。删除或变为二进制/超限的文件会撤销
    /// 其内容引用并失效依赖闭包。文本判定：utf8 且 ≤ fileByteCap。
    @discardableResult
    public func settleWorkRootContents(
        rootID: String, rootURL: URL, category: String = "work",
        fileByteCap: Int = 1 << 20, maxDepth: Int = 4
    ) throws -> ContentSettleReport {
        let fm = FileManager.default
        // file_contents references roots, so the root must exist before any
        // content row is written (new roots start here, not in the index pass).
        try upsertRoot(rootID: rootID, category: category, displayName: nil,
                       locatorType: "path", status: "present")
        var previous: [String: FileContentState] = [:]
        let prevStmt = try prepare("""
        SELECT relative_path, content_sha256, object_id FROM file_contents WHERE root_id=?;
        """)
        bind(prevStmt, 1, rootID)
        while sqlite3_step(prevStmt) == SQLITE_ROW {
            func text(_ i: Int32) -> String {
                sqlite3_column_text(prevStmt, i).map { String(cString: $0) } ?? ""
            }
            previous[text(0)] = FileContentState(
                digest: text(1),
                objectID: sqlite3_column_type(prevStmt, 2) == SQLITE_NULL ? nil : text(2))
        }
        sqlite3_finalize(prevStmt)

        var scanned = 0, reused = 0, skipped = 0
        var seen = Set<String>()
        var pending: [PendingSettlement] = []
        var cleared: [(relativePath: String, previous: FileContentState, missing: Bool)] = []
        var indexedFiles: [(rel: String, url: URL, size: Int64, digest: String?)] = []

        let scanRoot = rootURL.resolvingSymlinksInPath()
        let enumerator = fm.enumerator(
            at: scanRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let file = enumerator?.nextObject() as? URL {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: file.path, isDirectory: &isDir),
                !isDir.boolValue
            else { continue }
            let rel = relativePath(of: file, under: scanRoot)
            guard !rel.isEmpty,
                rel.split(separator: "/").count <= maxDepth
            else { continue }
            scanned += 1
            seen.insert(rel)
            let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)

            guard let data = try? Data(contentsOf: file), data.count <= fileByteCap else {
                skipped += 1
                indexedFiles.append((rel, file, size, nil))
                if let old = previous[rel] {
                    cleared.append((rel, old, false))
                }
                continue
            }
            let digest = NativeSHA256.hexDigest(data)
            indexedFiles.append((rel, file, size, digest))
            guard String(data: data, encoding: .utf8) != nil else {
                skipped += 1
                if let old = previous[rel] {
                    cleared.append((rel, old, false))
                }
                continue
            }
            if let old = previous[rel], old.digest == digest, old.objectID != nil {
                reused += 1
                continue
            }
            pending.append(PendingSettlement(
                relativePath: rel, url: file, data: data, digest: digest,
                previous: previous[rel]))
        }

        // Indexed rows whose file disappeared from the latest scan.
        var removed = 0
        for (rel, old) in previous where !seen.contains(rel) {
            cleared.append((rel, old, true))
            removed += 1
        }

        var invalidated = Set<String>()
        var created = 0, deduplicated = 0, bytesAddressed = 0
        let now = Self.stamp(Date())

        try transaction {
            for item in cleared {
                invalidated.formUnion(try affectedClosure(
                    rootID: rootID, relativePath: item.relativePath))
                try invalidateRetrievalSettlementsInTransaction(
                    rootID: rootID, relativePath: item.relativePath,
                    oldDigest: item.previous.digest)
                try execBinding("""
                DELETE FROM file_contents WHERE root_id=? AND relative_path=?;
                """) { stmt in
                    bind(stmt, 1, rootID)
                    bind(stmt, 2, item.relativePath)
                }
                if item.missing {
                    try execBinding("""
                    UPDATE external_files SET status='missing'
                    WHERE root_id=? AND relative_path=?;
                    """) { stmt in
                        bind(stmt, 1, rootID)
                        bind(stmt, 2, item.relativePath)
                    }
                }
            }

            for item in pending {
                if let old = item.previous {
                    invalidated.formUnion(try affectedClosure(
                        rootID: rootID, relativePath: item.relativePath))
                    try invalidateRetrievalSettlementsInTransaction(
                        rootID: rootID, relativePath: item.relativePath,
                        oldDigest: old.digest)
                }
                let object = try ensureObjectWithStatus(item.data)
                if object.created { created += 1 } else { deduplicated += 1 }
                bytesAddressed += item.data.count
                let identity = "file:\(rootID)/\(item.relativePath)"
                try execBinding("""
                INSERT INTO file_contents(
                    root_id, relative_path, content_sha256, content, settled_at, object_id)
                VALUES(?,?,?,'',?,?)
                ON CONFLICT(root_id, relative_path) DO UPDATE SET
                    content_sha256=excluded.content_sha256, content='',
                    settled_at=excluded.settled_at, object_id=excluded.object_id;
                """) { stmt in
                    bind(stmt, 1, rootID)
                    bind(stmt, 2, item.relativePath)
                    bind(stmt, 3, item.digest)
                    bind(stmt, 4, now)
                    bind(stmt, 5, object.id)
                }
                _ = try appendIndexEntryInTransaction(
                    identity: identity, objectID: object.id)
                _ = try appendDependencyInTransaction(
                    dependencyID: identity, contentAddress: object.id,
                    reason: item.previous == nil ? "content-settle" : "content-update")
            }

            for file in indexedFiles {
                try indexExternalFile(
                    rootID: rootID, category: category,
                    relativePath: file.rel,
                    kind: file.url.pathExtension.isEmpty ? nil : file.url.pathExtension,
                    size: file.size, modifiedAt: nil,
                    contentDigest: file.digest)
            }
            try markSettlementsInvalidInTransaction(Array(invalidated))
        }

        return ContentSettleReport(
            scanned: scanned, reused: reused, settled: pending.count,
            skippedBinaryOrLarge: skipped,
            changed: pending.filter { $0.previous != nil }.count,
            removed: removed, invalidatedSettlements: invalidated.count,
            objectsCreated: created, deduplicated: deduplicated,
            bytesAddressed: bytesAddressed)
    }

    /// Component-aligned relative path. The enumerator can hand back a
    /// canonicalized path (`/private/var/...`) while the caller supplied
    /// `/var/...`; string-prefix matching would silently skip every file.
    private func relativePath(of file: URL, under root: URL) -> String {
        let rootParts = Array(root.pathComponents.dropFirst())
        let fileParts = Array(file.pathComponents.dropFirst())
        guard !rootParts.isEmpty, fileParts.count >= rootParts.count else {
            return rootParts.isEmpty ? fileParts.joined(separator: "/") : ""
        }
        for start in 0...(fileParts.count - rootParts.count)
        where Array(fileParts[start..<(start + rootParts.count)]) == rootParts {
            return fileParts[(start + rootParts.count)...].joined(separator: "/")
        }
        return ""
    }

    // MARK: - Demand 驱动的信息检索（原研究 execute_demand 语义）

    public struct DemandRetrieval: Equatable, Sendable {
        public let demandID: String
        public let reused: Bool
        public let hits: [ContentHit]
        public let resultSHA256: String
        public let status: String
    }

    /// 执行一次信息需求（demand）：
    ///   demand_id = SHA256(query + 注册根集合 + 全部已结算内容摘要的规范串联)
    /// 同一 demand 且结算有效 → 直接返回已结算结果（**不再重复计算**，即
    /// ES₁ 已结算关系对 ES₂ 合法复用）；任一输入摘要变化 → 新 demand，重算
    /// 并落新结算，旧结算置 invalidated。结果逐项摘要绑定，确定性 consumer
    /// 不造内容。
    public func executeInformationDemand(
        query: String, rootID: String? = nil, limit: Int = 200
    ) throws -> DemandRetrieval {
        // 1) 输入摘要：查询 + 相关根的已结算内容摘要（规范排序串联）
        var digests: [String] = []
        var roots: [String] = []
        var inputs: [(root: String, path: String, objectID: String)] = []
        let digestSQL = rootID == nil
            ? "SELECT root_id, relative_path, content_sha256, object_id FROM file_contents ORDER BY root_id, relative_path;"
            : "SELECT root_id, relative_path, content_sha256, object_id FROM file_contents WHERE root_id='"
                + rootID!.replacingOccurrences(of: "'", with: "''")
                + "' ORDER BY root_id, relative_path;"
        let dstmt = try prepare(digestSQL)
        while sqlite3_step(dstmt) == SQLITE_ROW {
            func col(_ i: Int32) -> String {
                guard let c = sqlite3_column_text(dstmt, i) else { return "" }
                return String(cString: c)
            }
            digests.append("\(col(0))/\(col(1))=\(col(2))")
            if !roots.contains(col(0)) { roots.append(col(0)) }
            if sqlite3_column_type(dstmt, 3) != SQLITE_NULL {
                inputs.append((col(0), col(1), col(3)))
            }
        }
        sqlite3_finalize(dstmt)
        let canonical = query + "|" + digests.joined(separator: ";")
        let demandID = NativeSHA256.hexDigest(Data(canonical.utf8))

        // 2) 复用检查：同 demand 且结算有效 → 读回已结算对象
        let settled = try prepare("""
        SELECT result_object_id, result_sha256, result_json FROM retrieval_settlements
        WHERE demand_id=? AND status='valid';
        """)
        bind(settled, 1, demandID)
        if sqlite3_step(settled) == SQLITE_ROW {
            func col(_ i: Int32) -> String {
                sqlite3_column_text(settled, i).map { String(cString: $0) } ?? ""
            }
            let objectID = col(0)
            let storedSHA = col(1)
            let legacyJSON = col(2)
            sqlite3_finalize(settled)
            let data: Data?
            if !objectID.isEmpty {
                data = try? readObject(objectID)
            } else {
                data = Data(legacyJSON.utf8)
            }
            if let data,
                let rows = try? JSONDecoder().decode([ContentHit].self, from: data)
            {
                return DemandRetrieval(
                    demandID: demandID, reused: true, hits: rows,
                    resultSHA256: storedSHA, status: "reused")
            }
        } else {
            sqlite3_finalize(settled)
        }

        // 3) 重算：在已结算内容索引上检索（确定性 consumer：只绑定摘要与原文行）
        var hits = try searchSettledContent(query: query, rootID: rootID, limit: limit)
        if hits.isEmpty {
            // 文件名命中（external_files 路径匹配）也纳入 demand 结果
            hits = try fileNameHits(query: query, rootID: rootID, limit: limit)
        }
        let resultData = try JSONEncoder().encode(hits)
        let resultSHA = NativeSHA256.hexDigest(resultData)

        // 4) 结果写入对象库，结算行只保留引用；索引追加 demand 身份
        try transaction {
            let objectID = try ensureObject(resultData)
            try execBinding("""
            UPDATE retrieval_settlements SET status='invalidated'
            WHERE query=? AND demand_id<>?;
            """) { stmt in
                bind(stmt, 1, query)
                bind(stmt, 2, demandID)
            }
            try execBinding("""
            INSERT INTO retrieval_settlements(
                demand_id, query, root_ids, inputs_digest, result_sha256, result_json,
                hit_count, status, settled_at, result_object_id)
            VALUES(?,?,?,?,?,'',?,?,?,?)
            ON CONFLICT(demand_id) DO UPDATE SET
                result_sha256=excluded.result_sha256, result_json='',
                hit_count=excluded.hit_count, status='valid',
                settled_at=excluded.settled_at, result_object_id=excluded.result_object_id;
            """) { stmt in
                bind(stmt, 1, demandID)
                bind(stmt, 2, query)
                bind(stmt, 3, roots.joined(separator: ","))
                bind(stmt, 4, canonical)
                bind(stmt, 5, resultSHA)
                bind(stmt, 6, Int64(hits.count))
                bind(stmt, 7, "valid")
                bind(stmt, 8, Self.stamp(Date()))
                bind(stmt, 9, objectID)
            }
            _ = try appendIndexEntryInTransaction(
                identity: "demand:\(demandID)", objectID: objectID)
            for input in inputs {
                _ = try appendDependencyInTransaction(
                    dependencyID: "demand:\(demandID) -> file:\(input.root)/\(input.path)",
                    contentAddress: input.objectID,
                    reason: "demand-input")
            }
        }
        return DemandRetrieval(
            demandID: demandID, reused: false, hits: hits,
            resultSHA256: resultSHA, status: "settled")
    }

    /// 文件名/路径命中的确定性 consumer（demand 结果的一部分）。
    private func fileNameHits(query: String, rootID: String?, limit: Int) throws -> [ContentHit] {
        var sql = "SELECT root_id, relative_path FROM external_files WHERE relative_path LIKE ?"
        if rootID != nil { sql += " AND root_id='" + rootID!.replacingOccurrences(of: "'", with: "''") + "'" }
        sql += " ORDER BY relative_path LIMIT \(limit);"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, "%" + query.replacingOccurrences(of: "'", with: "''") + "%")
        var hits: [ContentHit] = []
        while sqlite3_step(stmt) == SQLITE_ROW, hits.count < limit {
            func col(_ i: Int32) -> String {
                guard let c = sqlite3_column_text(stmt, i) else { return "" }
                return String(cString: c)
            }
            hits.append(ContentHit(
                rootID: col(0), relativePath: col(1), lineNo: 0,
                lineText: col(1)))
        }
        return hits
    }

    public struct ContentHit: Equatable, Sendable, Codable {
        public let rootID: String
        public let relativePath: String
        public let lineNo: Int
        public let lineText: String
    }

    /// 信息拓扑检索：在已结算的内容索引上按关键词命中（文件名 + 行级），
    /// 不重扫文件系统——结算过的结果直接使用。
    public func searchSettledContent(query: String, rootID: String? = nil, limit: Int = 200)
        throws -> [ContentHit]
    {
        guard !query.isEmpty else { return [] }
        var hits: [ContentHit] = []
        var sql = """
        SELECT f.root_id, f.relative_path, CAST(o.content AS TEXT)
        FROM file_contents f JOIN is_objects o ON o.object_id=f.object_id
        WHERE CAST(o.content AS TEXT) LIKE ?
        """
        if rootID != nil { sql += " AND f.root_id='" + rootID!.replacingOccurrences(of: "'", with: "''") + "'" }
        sql += ";"
        let pattern = "%" + query.replacingOccurrences(of: "'", with: "''") + "%"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, pattern)
        while sqlite3_step(stmt) == SQLITE_ROW, hits.count < limit {
            func col(_ i: Int32) -> String {
                guard let c = sqlite3_column_text(stmt, i) else { return "" }
                return String(cString: c)
            }
            let rootIDv = col(0), rel = col(1), content = col(2)
            for (idx, line) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.localizedCaseInsensitiveContains(query) {
                hits.append(ContentHit(
                    rootID: rootIDv, relativePath: rel, lineNo: idx + 1,
                    lineText: String(line.prefix(200))))
                if hits.count >= limit { break }
            }
        }
        return hits
    }

    // MARK: - 对话落库（Information Space：会话即信息）

    public func appendChatMessage(
        sessionID: String, role: String, content: String, model: String?, createdAt: Date
    ) throws {
        let data = Data(content.utf8)
        let digest = NativeSHA256.hexDigest(data)
        try transaction {
            let objectID = try ensureObject(data)
            try execBinding("""
            INSERT INTO chat_messages(session_id, role, content, model, content_sha256, created_at, content_object_id)
            VALUES(?,?,?,?,?,?,?);
            """) { stmt in
                bind(stmt, 1, sessionID)
                bind(stmt, 2, role)
                bind(stmt, 3, "")
                if let model { bind(stmt, 4, model) } else { sqlite3_bind_null(stmt, 4) }
                bind(stmt, 5, digest)
                bind(stmt, 6, Self.stamp(createdAt))
                bind(stmt, 7, objectID)
            }
            let rowID = sqlite3_last_insert_rowid(handle)
            _ = try appendIndexEntryInTransaction(
                identity: "chat:\(sessionID)/\(rowID)", objectID: objectID)
        }
    }

    public struct ChatMessageRow: Equatable, Sendable {
        public let sessionID: String
        public let role: String
        public let content: String
        public let model: String?
        public let contentSHA256: String
        public let createdAt: String
    }

    public func listChatMessages(sessionID: String? = nil, limit: Int = 500) throws -> [ChatMessageRow] {
        let base = """
        SELECT c.session_id, c.role,
               COALESCE(CAST(o.content AS TEXT), c.content),
               c.model, c.content_sha256, c.created_at
        FROM chat_messages c
        LEFT JOIN is_objects o ON o.object_id=c.content_object_id
        """
        let sql = sessionID == nil
            ? base + " ORDER BY c.id DESC LIMIT \(limit);"
            : base + " WHERE c.session_id='"
                + sessionID!.replacingOccurrences(of: "'", with: "''")
                + "' ORDER BY c.id ASC LIMIT \(limit);"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var rows: [ChatMessageRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func col(_ i: Int32) -> String {
                guard let c = sqlite3_column_text(stmt, i) else { return "" }
                return String(cString: c)
            }
            rows.append(ChatMessageRow(
                sessionID: col(0), role: col(1), content: col(2),
                model: col(3).isEmpty ? nil : col(3),
                contentSHA256: col(4), createdAt: col(5)))
        }
        return rows
    }

    /// Register or refresh an external root. Idempotent upsert keyed on root_id.
    public func upsertRoot(rootID: String, category: String, displayName: String?,
                           locatorType: String?, status: String) throws {
        let now = Self.stamp( Date())
        try execBinding("""
        INSERT INTO roots(root_id, category, display_name, locator_type, status, created_at, last_scanned_at)
        VALUES(?,?,?,?,?,?,?)
        ON CONFLICT(root_id) DO UPDATE SET
            category=excluded.category, display_name=excluded.display_name,
            locator_type=excluded.locator_type, status=excluded.status,
            last_scanned_at=excluded.last_scanned_at;
        """) { stmt in
            bind(stmt, 1, rootID)
            bind(stmt, 2, category)
            bind(stmt, 3, displayName)
            bind(stmt, 4, locatorType)
            bind(stmt, 5, status)
            bind(stmt, 6, now)
            bind(stmt, 7, now)
        }
    }

    /// Index one external file by root + relative path. Ensures the parent root
    /// exists (FK), then UPSERTs on UNIQUE(root_id, relative_path). Idempotent.
    public func indexExternalFile(rootID: String, category: String = "work",
                                  relativePath: String, kind: String?, size: Int64?,
                                  modifiedAt: String?, contentDigest: String?,
                                  status: String = "present") throws {
        try upsertRoot(rootID: rootID, category: category, displayName: nil,
                       locatorType: "path", status: status)
        let now = Self.stamp( Date())
        try execBinding("""
        INSERT INTO external_files(root_id, relative_path, kind, size, modified_at, content_digest, indexed_at, last_seen_at, status)
        VALUES(?,?,?,?,?,?,?,?,?)
        ON CONFLICT(root_id, relative_path) DO UPDATE SET
            kind=excluded.kind, size=excluded.size, modified_at=excluded.modified_at,
            content_digest=excluded.content_digest, last_seen_at=excluded.last_seen_at, status=excluded.status;
        """) { stmt in
            bind(stmt, 1, rootID)
            bind(stmt, 2, relativePath)
            bind(stmt, 3, kind)
            bind(stmt, 4, size)
            bind(stmt, 5, modifiedAt)
            bind(stmt, 6, contentDigest)
            bind(stmt, 7, now)
            bind(stmt, 8, now)
            bind(stmt, 9, status)
        }
    }

    /// Index an agent session, referencing its source root by id only.
    public func indexAgentSession(sessionID: String, adapterID: String?,
                                  sourceRootID: String?, metadataDigest: String?,
                                  syncStatus: String = "indexed") throws {
        let now = Self.stamp( Date())
        try execBinding("""
        INSERT INTO agent_sessions(session_id, adapter_id, source_root_id, metadata_digest, sync_status, created_at)
        VALUES(?,?,?,?,?,?)
        ON CONFLICT(session_id) DO UPDATE SET
            adapter_id=excluded.adapter_id, source_root_id=excluded.source_root_id,
            metadata_digest=excluded.metadata_digest, sync_status=excluded.sync_status;
        """) { stmt in
            bind(stmt, 1, sessionID)
            bind(stmt, 2, adapterID)
            bind(stmt, 3, sourceRootID)
            bind(stmt, 4, metadataDigest)
            bind(stmt, 5, syncStatus)
            bind(stmt, 6, now)
        }
    }

    public struct ExternalFileRow: Equatable {
        public let rootID: String
        public let relativePath: String
        public let status: String
    }

    /// Step a SELECT and collect the first three TEXT columns as rows (index reads
    /// only; used for verification and reporting).
    public func listExternalFiles(rootID: String? = nil) throws -> [ExternalFileRow] {
        let sql = rootID == nil
            ? "SELECT root_id, relative_path, status FROM external_files ORDER BY root_id, relative_path;"
            : "SELECT root_id, relative_path, status FROM external_files WHERE root_id='" + rootID!.replacingOccurrences(of: "'", with: "''") + "' ORDER BY relative_path;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var rows: [ExternalFileRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func col(_ i: Int32) -> String {
                guard let c = sqlite3_column_text(stmt, i) else { return "" }
                return String(cString: c)
            }
            rows.append(ExternalFileRow(rootID: col(0), relativePath: col(1), status: col(2)))
        }
        return rows
    }

    // MARK: - G2 dual-source dependency + local invalidation behavior
    //
    // The IS layer must do more than pass integrity_check: it has to carry TWO
    // information sources (external work files + agent sessions), link settled
    // information objects to their sources and to each other, and support LOCAL
    // dynamic invalidation — when a source changes, only the affected dependency
    // closure is invalidated and unrelated valid results are preserved. Nothing
    // here copies external file bytes; the DB stores digests and references only.

    /// Resolve an indexed external file row id by root + relative path (nil if absent).
    private func externalFileID(rootID: String, relativePath: String) throws -> Int64? {
        let stmt = try prepare("SELECT file_id FROM external_files WHERE root_id=? AND relative_path=?;")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, rootID)
        bind(stmt, 2, relativePath)
        if sqlite3_step(stmt) == SQLITE_ROW { return sqlite3_column_int64(stmt, 0) }
        return nil
    }

    /// Read the stored content digest for an indexed external file (nil if absent).
    public func externalFileDigest(rootID: String, relativePath: String) throws -> String? {
        let stmt = try prepare("SELECT content_digest FROM external_files WHERE root_id=? AND relative_path=?;")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, rootID)
        bind(stmt, 2, relativePath)
        if sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
            return String(cString: c)
        }
        return nil
    }

    /// Re-index an external file, reporting whether its content digest CHANGED.
    /// Callers invalidate only on a real change, which is what keeps updates local
    /// (proportional) rather than a full re-scan rebuild. Re-scanning an unchanged
    /// file returns false and touches no validity state (idempotent).
    @discardableResult
    public func reindexExternalFile(rootID: String, category: String = "work",
                                    relativePath: String, kind: String?, size: Int64?,
                                    modifiedAt: String?, contentDigest: String?,
                                    status: String = "present") throws -> Bool {
        let previous = try externalFileDigest(rootID: rootID, relativePath: relativePath)
        try indexExternalFile(rootID: rootID, category: category, relativePath: relativePath,
                              kind: kind, size: size, modifiedAt: modifiedAt,
                              contentDigest: contentDigest, status: status)
        return previous != contentDigest
    }

    /// Link a settlement to the external work file its IS value was derived from,
    /// resolving the source_file_id from the index. The DB still stores only the
    /// reference + digest, never the file bytes.
    public func linkSettlementToExternalFile(settlementID: String, binding: String,
                                             rootID: String, relativePath: String) throws {
        guard let fileID = try externalFileID(rootID: rootID, relativePath: relativePath) else {
            throw DatabaseError.sql("linkSettlementToExternalFile: source file not indexed: \(relativePath)")
        }
        try transaction {
            try execBinding("""
            INSERT INTO settlement_bindings(settlement_id, name, value_digest, source_root_id, source_file_id)
            VALUES(?,?,'source',?,?);
            """) { stmt in
                bind(stmt, 1, settlementID)
                bind(stmt, 2, binding)
                bind(stmt, 3, rootID)
                bind(stmt, 4, fileID)
            }
            // Ledger the dependency only when the source content is actually
            // carried: a metadata-only index has nothing to point at.
            if let address = try fileContentObject(rootID: rootID, relativePath: relativePath) {
                _ = try appendDependencyInTransaction(
                    dependencyID: "settlement:\(settlementID) -> file:\(rootID)/\(relativePath)",
                    contentAddress: address,
                    reason: "source-binding:\(binding)")
            }
        }
    }

    /// Record that `fromSettlement` depends on `toSettlement`. Invalidating a
    /// depended-on settlement cascades to its (transitive) dependents.
    public func addDependency(fromSettlement: String, toSettlement: String,
                              kind: String = "depends") throws {
        try transaction {
            try execBinding("INSERT INTO dependency_edges(from_settlement, to_settlement, kind) VALUES(?,?,?);") { stmt in
                bind(stmt, 1, fromSettlement)
                bind(stmt, 2, toSettlement)
                bind(stmt, 3, kind)
            }
            if let address = try settlementPayloadObject(toSettlement) {
                _ = try appendDependencyInTransaction(
                    dependencyID: "settlement:\(fromSettlement) -> settlement:\(toSettlement)",
                    contentAddress: address,
                    reason: kind)
            }
        }
    }

    /// Content address of a settlement's payload, when the settlement is carried.
    private func settlementPayloadObject(_ settlementID: String) throws -> String? {
        let stmt = try prepare("SELECT payload_object_id FROM settlements WHERE settlement_id=?;")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, settlementID)
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else {
            return nil
        }
        return String(cString: c)
    }

    /// Content address of a settled file, when its bytes are carried.
    private func fileContentObject(rootID: String, relativePath: String) throws -> String? {
        let stmt = try prepare("""
        SELECT object_id FROM file_contents WHERE root_id=? AND relative_path=?;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, rootID)
        bind(stmt, 2, relativePath)
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else {
            return nil
        }
        return String(cString: c)
    }

    /// The transitive closure of settlements affected by a source-file change:
    /// settlements directly bound to the file, plus everything that (transitively)
    /// depends on them via dependency_edges.
    private func affectedClosure(rootID: String, relativePath: String) throws -> [String] {
        let stmt = try prepare("""
        WITH RECURSIVE closure(id) AS (
            SELECT DISTINCT b.settlement_id
              FROM settlement_bindings b
              JOIN external_files f ON f.file_id=b.source_file_id AND f.root_id=b.source_root_id
             WHERE b.source_root_id=? AND f.relative_path=?
            UNION
            SELECT d.from_settlement
              FROM dependency_edges d
              JOIN closure c ON d.to_settlement=c.id
        )
        SELECT id FROM closure;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, rootID)
        bind(stmt, 2, relativePath)
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
            out.append(String(cString: c))
        }
        return out
    }

    /// Invalidate the transitive dependency closure rooted at settlements bound to
    /// the given external file, flipping only those rows to 'invalid' in a single
    /// transaction. Returns the invalidated settlement ids. Unrelated settlements
    /// keep validity='valid'. A change with no dependents invalidates nothing.
    @discardableResult
    public func invalidateSourceFile(rootID: String, relativePath: String) throws -> [String] {
        let ids = try affectedClosure(rootID: rootID, relativePath: relativePath)
        guard !ids.isEmpty else { return [] }
        try transaction {
            try markSettlementsInvalidInTransaction(ids)
            try invalidateRetrievalSettlementsInTransaction(
                rootID: rootID, relativePath: relativePath, oldDigest: "")
        }
        return ids
    }

    /// Caller owns the transaction. Flips only valid rows so repeated
    /// invalidation is idempotent and never rewrites an earlier timestamp.
    private func markSettlementsInvalidInTransaction(_ ids: [String]) throws {
        guard !ids.isEmpty else { return }
        let now = Self.stamp(Date())
        for id in ids {
            try execBinding("""
            UPDATE settlements SET validity='invalid', invalidated_at=?
            WHERE settlement_id=? AND validity<>'invalid';
            """) { stmt in
                bind(stmt, 1, now)
                bind(stmt, 2, id)
            }
        }
    }

    /// Caller owns the transaction. A demand is stale when its recorded input
    /// basis contains the changed file's previous address. The demand id itself
    /// will differ after the change; this only makes the recorded state honest.
    private func invalidateRetrievalSettlementsInTransaction(
        rootID: String, relativePath: String, oldDigest: String
    ) throws {
        guard !oldDigest.isEmpty else { return }
        let needle = "\(rootID)/\(relativePath)=\(oldDigest)"
        try execBinding("""
        UPDATE retrieval_settlements SET status='invalidated'
        WHERE status='valid' AND instr(inputs_digest, ?) > 0;
        """) { stmt in
            bind(stmt, 1, needle)
        }
    }

    /// Reconciliation for lost watcher events: mark indexed files under a root
    /// that were NOT observed in the latest scan as 'missing', drop their content
    /// references, and invalidate their dependency closures. Returns every
    /// settlement invalidated by the sweep.
    @discardableResult
    public func reconcileRoot(rootID: String, seenRelativePaths: Set<String>) throws -> [String] {
        let stmt = try prepare("SELECT relative_path FROM external_files WHERE root_id=?;")
        bind(stmt, 1, rootID)
        var indexed: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
            indexed.append(String(cString: c))
        }
        sqlite3_finalize(stmt)
        let existing = indexed.filter { !seenRelativePaths.contains($0) }
        guard !existing.isEmpty else { return [] }

        var invalidated: [String] = []
        try transaction {
            for path in existing {
                let digestStmt = try prepare("""
                SELECT content_sha256 FROM file_contents WHERE root_id=? AND relative_path=?;
                """)
                var oldDigest = ""
                if sqlite3_step(digestStmt) == SQLITE_ROW,
                    let c = sqlite3_column_text(digestStmt, 0)
                {
                    oldDigest = String(cString: c)
                }
                sqlite3_finalize(digestStmt)
                invalidated += try affectedClosure(rootID: rootID, relativePath: path)
                try invalidateRetrievalSettlementsInTransaction(
                    rootID: rootID, relativePath: path, oldDigest: oldDigest)
                try execBinding("""
                DELETE FROM file_contents WHERE root_id=? AND relative_path=?;
                """) { s in
                    bind(s, 1, rootID); bind(s, 2, path)
                }
                try execBinding("""
                UPDATE external_files SET status='missing'
                WHERE root_id=? AND relative_path=?;
                """) { s in
                    bind(s, 1, rootID); bind(s, 2, path)
                }
            }
            try markSettlementsInvalidInTransaction(invalidated)
        }
        return invalidated
    }

    /// Transitive dependents of a seed settlement set: the seeds themselves plus
    /// every settlement that (directly or indirectly) depends on them.
    private func transitiveDependents(seeds: [String]) throws -> [String] {
        guard !seeds.isEmpty else { return [] }
        let joined = seeds
            .map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }
            .joined(separator: ",")
        let stmt = try prepare("""
        WITH RECURSIVE closure(id) AS (
            SELECT settlement_id FROM settlements WHERE settlement_id IN (\(joined))
            UNION
            SELECT d.from_settlement FROM dependency_edges d JOIN closure c ON d.to_settlement=c.id
        )
        SELECT id FROM closure;
        """)
        defer { sqlite3_finalize(stmt) }
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
            out.append(String(cString: c))
        }
        return out
    }

    /// Invalidate a settlement and everything that (transitively) depends on it.
    /// This is the source-change path for information that is NOT an external file
    /// row — e.g. an agent session version change invalidates the settlement
    /// derived from that session and cascades to its dependents, while unrelated
    /// valid results are preserved.
    @discardableResult
    public func invalidateSettlement(_ settlementID: String) throws -> [String] {
        let ids = try transitiveDependents(seeds: [settlementID])
        guard !ids.isEmpty else { return [] }
        try transaction {
            try markSettlementsInvalidInTransaction(ids)
        }
        return ids
    }

    /// Data-ownership introspection: does the given table store any BLOB column?
    /// The external-file index must hold only digest + metadata — NEVER the file
    /// bytes — so this must be false for `external_files`.
    public func tableHasBlobColumn(_ table: String) throws -> Bool {
        let stmt = try prepare("SELECT type FROM pragma_table_info(?);")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, table)
        while sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
            if String(cString: c).uppercased().contains("BLOB") { return true }
        }
        return false
    }

    /// Current validity of a settlement ('valid' or 'invalid').
    public func settlementValidity(_ settlementID: String) throws -> String {
        let stmt = try prepare("SELECT validity FROM settlements WHERE settlement_id=?;")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, settlementID)
        if sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
            return String(cString: c)
        }
        throw DatabaseError.sql("settlementValidity: unknown settlement \(settlementID)")
    }

    /// Number of settlements currently marked valid (unaffected by invalidation).
    public func validSettlementCount() throws -> Int {
        let stmt = try prepare("SELECT COUNT(*) FROM settlements WHERE validity='valid';")
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW { return Int(sqlite3_column_int64(stmt, 0)) }
        return 0
    }

    /// The transitive UPSTREAM dependency closure of a settlement: every
    /// settlement it depends on, directly (dependency_edges.from_settlement =
    /// seed) or through the chain, excluding the seed itself.
    ///
    /// `affectedClosure` and `transitiveDependents` only walk the DOWNSTREAM
    /// (dependents) direction, so this is the missing half required by IS
    /// admission: before a consumer trusts a settled value it must confirm the
    /// whole closure the value was derived from is still present and valid.
    /// Returns an empty array when the settlement has no dependencies.
    public func upstreamDependencyClosure(ofSettlement settlementID: String) throws -> [String] {
        let stmt = try prepare("""
        WITH RECURSIVE upstream(id) AS (
            SELECT d.to_settlement FROM dependency_edges d WHERE d.from_settlement=?
            UNION
            SELECT d.to_settlement FROM dependency_edges d JOIN upstream u ON d.from_settlement=u.id
        )
        SELECT id FROM upstream;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, settlementID)
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
            out.append(String(cString: c))
        }
        return out
    }

    // MARK: - Legacy JSON graph migration

    /// Mirror of the app's persisted `ExecutionGraphDocument`. Decoded directly so
    /// the database layer stays independent of SwiftUI/app types.
    private struct LegacyGraphDocument: Codable {
        struct State: Codable {
            let id: String; let parentID: String?; let modelIdentity: String
            let createdAt: Date; var position: Int; var continuationID: String
            var nextInput: String; var anchor: String; var prefix: [String]
            var lifecycle: String; let checkpointIDs: [UUID]
        }
        struct Checkpoint: Codable {
            let id: UUID; let stateID: String; let modelIdentity: String; let position: Int
            let continuationID: String; let nextInput: String; let anchor: String
            let prefix: [String]; let createdAt: Date; let checksum: String
        }
        let contractVersion: String
        let representationID: String
        let states: [State]
        let checkpoints: [Checkpoint]
    }

    public struct LegacyImportOutcome: Equatable {
        public let statesImported: Int
        public let settlementsImported: Int
        public let contractVersion: String
    }

    /// Import a legacy JSON execution graph into SQLite inside ONE transaction,
    /// validate it field-by-field on read-back, then write a migration receipt.
    /// On any failure the transaction rolls back and the source file is untouched,
    /// so no half-written authority remains and nothing is double-written.
    @discardableResult
    public func importLegacyGraph(jsonData: Data, sourceLabel: String, contractVersion expected: String = "v1.0-amended") throws -> LegacyImportOutcome {
        let decoder = JSONDecoder()
        let doc: LegacyGraphDocument
        do { doc = try decoder.decode(LegacyGraphDocument.self, from: jsonData) }
        catch { throw DatabaseError.notADatabase("legacy graph decode failed: \(error)") }

        guard doc.contractVersion == expected else {
            throw DatabaseError.contractVersionMismatch(doc.contractVersion)
        }

        var outcome = LegacyImportOutcome(statesImported: 0, settlementsImported: 0, contractVersion: doc.contractVersion)

        let enc = JSONEncoder()
        func jsonText(_ value: some Encodable) -> String {
            String(data: (try? enc.encode(value)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
        }
        try transaction {
            // Import the FULL representation so retiring the legacy JSON after a
            // validated hand-off is loss-free: next_input, prefix and checkpoint
            // links land in the same v2 columns `writeGraph` uses.
            for s in doc.states {
                try execBinding("""
                INSERT INTO execution_states(state_id, parent_id, model_identity, position, continuation_id, anchor, lifecycle, created_at, next_input, prefix_json, checkpoint_ids_json)
                VALUES(?,?,?,?,?,?,?,?,?,?,?);
                """) { stmt in
                    bind(stmt, 1, s.id)
                    bind(stmt, 2, s.parentID)
                    bind(stmt, 3, s.modelIdentity)
                    bind(stmt, 4, Int64(s.position))
                    bind(stmt, 5, s.continuationID)
                    bind(stmt, 6, s.anchor)
                    bind(stmt, 7, s.lifecycle)
                    bind(stmt, 8, Self.stamp( s.createdAt))
                    bind(stmt, 9, s.nextInput)
                    bind(stmt, 10, jsonText(s.prefix))
                    bind(stmt, 11, jsonText(s.checkpointIDs.map { $0.uuidString }))
                }
            }
            for c in doc.checkpoints {
                let canonical = (try? enc.encode(c.prefix)) ?? Data()
                let payloadObject = try ensureObject(canonical)
                try execBinding("""
                INSERT INTO settlements(settlement_id, state_id, schema_version, payload, payload_digest, signature, contract_version, settled_at, validation_status, payload_object_id)
                VALUES(?,?,?,?,?,?,?,?,?,?);
                """) { stmt in
                    bind(stmt, 1, c.id.uuidString)
                    bind(stmt, 2, c.stateID)
                    bind(stmt, 3, doc.representationID)
                    bind(stmt, 4, Data())
                    bind(stmt, 5, c.checksum)
                    bind(stmt, 6, String?.none)
                    bind(stmt, 7, doc.contractVersion)
                    bind(stmt, 8, Self.stamp( c.createdAt))
                    bind(stmt, 9, "MIGRATED_LEGACY")
                    bind(stmt, 10, payloadObject)
                }
                _ = try appendIndexEntryInTransaction(
                    identity: "settlement:\(c.id.uuidString)", objectID: payloadObject)
                // Also land the checkpoint in the ES-owned checkpoints table so a
                // post-retirement readGraph() reproduces the graph, not only the
                // settlement receipts.
                try execBinding("""
                INSERT INTO checkpoints(checkpoint_id, state_id, model_identity, position, continuation_id, next_input, anchor, prefix_json, created_at, checksum)
                VALUES(?,?,?,?,?,?,?,?,?,?);
                """) { stmt in
                    bind(stmt, 1, c.id.uuidString)
                    bind(stmt, 2, c.stateID)
                    bind(stmt, 3, c.modelIdentity)
                    bind(stmt, 4, Int64(c.position))
                    bind(stmt, 5, c.continuationID)
                    bind(stmt, 6, c.nextInput)
                    bind(stmt, 7, c.anchor)
                    bind(stmt, 8, jsonText(c.prefix))
                    bind(stmt, 9, Self.stamp( c.createdAt))
                    bind(stmt, 10, c.checksum)
                }
            }

            // Read-back verification, field by field.
            try verifyReadBack(doc: doc)

            try execBinding("INSERT INTO migration_receipts(source_kind, source_digest, result, rows_imported, completed_at) VALUES(?,?,?,?,?);") { stmt in
                bind(stmt, 1, "legacy_execution_graph")
                bind(stmt, 2, sourceLabel)
                bind(stmt, 3, "ok")
                bind(stmt, 4, Int64(doc.states.count + doc.checkpoints.count))
                bind(stmt, 5, Self.stamp( Date()))
            }
            outcome = LegacyImportOutcome(statesImported: doc.states.count,
                                          settlementsImported: doc.checkpoints.count,
                                          contractVersion: doc.contractVersion)
        }
        return outcome
    }

    private func verifyReadBack(doc: LegacyGraphDocument) throws {
        let dec = JSONDecoder()
        for s in doc.states {
            let stmt = try prepare("SELECT position, continuation_id, anchor, lifecycle, next_input, prefix_json, checkpoint_ids_json FROM execution_states WHERE state_id=?;")
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, s.id)
            guard sqlite3_step(stmt) == SQLITE_ROW else {
                throw DatabaseError.migrationMismatch("state not read back: \(s.id)")
            }
            let pos = Int(sqlite3_column_int64(stmt, 0))
            let cont = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let anchor = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let nextInput = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
            let prefixText = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? "[]"
            let cpText = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? "[]"
            let prefixRead = (try? dec.decode([String].self, from: Data(prefixText.utf8))) ?? []
            let cpRead = (try? dec.decode([String].self, from: Data(cpText.utf8))) ?? []
            guard pos == s.position, cont == s.continuationID, anchor == s.anchor,
                  nextInput == s.nextInput, prefixRead == s.prefix,
                  cpRead == s.checkpointIDs.map({ $0.uuidString }) else {
                throw DatabaseError.migrationMismatch("state field drift: \(s.id)")
            }
        }
        // Checkpoints must also be present in the ES-owned table for a loss-free
        // post-retirement graph read, not only as settlement receipts.
        for c in doc.checkpoints {
            let stmt = try prepare("SELECT checksum, state_id, prefix_json FROM checkpoints WHERE checkpoint_id=?;")
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, c.id.uuidString)
            guard sqlite3_step(stmt) == SQLITE_ROW else {
                throw DatabaseError.migrationMismatch("checkpoint not read back: \(c.id)")
            }
            let sum = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let state = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let prefixText = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "[]"
            let prefixRead = (try? dec.decode([String].self, from: Data(prefixText.utf8))) ?? []
            guard sum == c.checksum, state == c.stateID, prefixRead == c.prefix else {
                throw DatabaseError.migrationMismatch("checkpoint field drift: \(c.id)")
            }
        }
        for c in doc.checkpoints {
            let stmt = try prepare("SELECT payload_digest, state_id FROM settlements WHERE settlement_id=?;")
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, c.id.uuidString)
            guard sqlite3_step(stmt) == SQLITE_ROW else {
                throw DatabaseError.migrationMismatch("settlement not read back: \(c.id)")
            }
            let digest = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let state = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            guard digest == c.checksum, state == c.stateID else {
                throw DatabaseError.migrationMismatch("settlement field drift: \(c.id)")
            }
        }
    }

    // MARK: - Authoritative graph round-trip (ES read/write authority)

    /// A full execution state, including the representation fields (nextInput,
    /// prefix, checkpoint links) needed to rebuild the app's live graph from
    /// SQLite alone. This is the read-authority shape.
    public struct GraphState {
        public let id: String
        public let parentID: String?
        public let modelIdentity: String
        public let createdAt: Date
        public let position: Int
        public let continuationID: String
        public let nextInput: String
        public let anchor: String
        public let prefix: [String]
        public let lifecycle: String
        public let checkpointIDs: [UUID]
        public init(id: String, parentID: String?, modelIdentity: String, createdAt: Date,
                    position: Int, continuationID: String, nextInput: String, anchor: String,
                    prefix: [String], lifecycle: String, checkpointIDs: [UUID]) {
            self.id = id; self.parentID = parentID; self.modelIdentity = modelIdentity
            self.createdAt = createdAt; self.position = position
            self.continuationID = continuationID; self.nextInput = nextInput
            self.anchor = anchor; self.prefix = prefix; self.lifecycle = lifecycle
            self.checkpointIDs = checkpointIDs
        }
    }

    /// A durable checkpoint (representation closure) of a state.
    public struct GraphCheckpoint {
        public let id: UUID
        public let stateID: String
        public let modelIdentity: String
        public let position: Int
        public let continuationID: String
        public let nextInput: String
        public let anchor: String
        public let prefix: [String]
        public let createdAt: Date
        public let checksum: String
        public init(id: UUID, stateID: String, modelIdentity: String, position: Int,
                    continuationID: String, nextInput: String, anchor: String,
                    prefix: [String], createdAt: Date, checksum: String) {
            self.id = id; self.stateID = stateID; self.modelIdentity = modelIdentity
            self.position = position; self.continuationID = continuationID
            self.nextInput = nextInput; self.anchor = anchor; self.prefix = prefix
            self.createdAt = createdAt; self.checksum = checksum
        }
    }

    /// Rewrite the live execution graph (states + checkpoints) into the
    /// authoritative store inside ONE transaction. Settlements are NEVER touched —
    /// they belong to the native settlement gate. States that are still referenced
    /// by a settlement are kept (no cascade into IS); genuinely-removed states are
    /// deleted only when nothing references them. Idempotent and crash-safe: a
    /// failure rolls the whole transaction back and leaves the prior graph intact.
    public func writeGraph(states: [GraphState], checkpoints: [GraphCheckpoint]) throws {
        let enc = JSONEncoder()
        let dec = JSONDecoder()
        try transaction {
            // Upsert every incoming state with the full representation.
            for st in states {
                let prefixJSON = String(data: (try? enc.encode(st.prefix)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
                let cpJSON = String(data: (try? enc.encode(st.checkpointIDs.map { $0.uuidString })) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
                try execBinding("""
                INSERT INTO execution_states(state_id, parent_id, model_identity, position, continuation_id, anchor, lifecycle, created_at, next_input, prefix_json, checkpoint_ids_json)
                VALUES(?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(state_id) DO UPDATE SET
                    parent_id=excluded.parent_id, model_identity=excluded.model_identity, position=excluded.position,
                    continuation_id=excluded.continuation_id, anchor=excluded.anchor, lifecycle=excluded.lifecycle,
                    created_at=excluded.created_at, next_input=excluded.next_input,
                    prefix_json=excluded.prefix_json, checkpoint_ids_json=excluded.checkpoint_ids_json;
                """) { stmt in
                    bind(stmt, 1, st.id)
                    bind(stmt, 2, st.parentID)
                    bind(stmt, 3, st.modelIdentity)
                    bind(stmt, 4, Int64(st.position))
                    bind(stmt, 5, st.continuationID)
                    bind(stmt, 6, st.anchor)
                    bind(stmt, 7, st.lifecycle)
                    bind(stmt, 8, Self.stamp( st.createdAt))
                    bind(stmt, 9, st.nextInput)
                    bind(stmt, 10, prefixJSON)
                    bind(stmt, 11, cpJSON)
                }
            }
            // Reconcile removals: delete states absent from the incoming set, but
            // only those not referenced by any settlement (protect IS authority).
            let keep = Set(states.map { $0.id })
            let existing = try fetchColumn("SELECT state_id FROM execution_states;")
            for sid in existing where !keep.contains(sid) {
                let ref = try isReferencedBySettlement(sid)
                if !ref {
                    try execBinding("DELETE FROM execution_states WHERE state_id=?;") { bind($0, 1, sid) }
                }
            }
            // Checkpoints own table (no FK): rebuild it wholesale for the kept set.
            try Self.rawExec(handle, "DELETE FROM checkpoints;")
            for cp in checkpoints {
                let prefixJSON = String(data: (try? enc.encode(cp.prefix)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
                try execBinding("""
                INSERT INTO checkpoints(checkpoint_id, state_id, model_identity, position, continuation_id, next_input, anchor, prefix_json, created_at, checksum)
                VALUES(?,?,?,?,?,?,?,?,?,?);
                """) { stmt in
                    bind(stmt, 1, cp.id.uuidString)
                    bind(stmt, 2, cp.stateID)
                    bind(stmt, 3, cp.modelIdentity)
                    bind(stmt, 4, Int64(cp.position))
                    bind(stmt, 5, cp.continuationID)
                    bind(stmt, 6, cp.nextInput)
                    bind(stmt, 7, cp.anchor)
                    bind(stmt, 8, prefixJSON)
                    bind(stmt, 9, Self.stamp( cp.createdAt))
                    bind(stmt, 10, cp.checksum)
                }
            }
            _ = dec // decoder used on read side only; silence unused in write path
        }
    }

    /// Rebuild the live execution graph (states + checkpoints) from the
    /// authoritative store. This is the read path that makes SQLite, not JSON,
    /// the source of truth for the app on open.
    public func readGraph() throws -> (states: [GraphState], checkpoints: [GraphCheckpoint]) {
        let enc = JSONEncoder()
        let dec = JSONDecoder()
        _ = enc
        var states: [GraphState] = []
        let sstmt = try prepare("""
        SELECT state_id, parent_id, model_identity, created_at, position, continuation_id,
               anchor, lifecycle, next_input, prefix_json, checkpoint_ids_json
        FROM execution_states ORDER BY created_at, state_id;
        """)
        defer { sqlite3_finalize(sstmt) }
        func txt(_ stmt: OpaquePointer, _ i: Int32) -> String {
            sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
        }
        func opt(_ stmt: OpaquePointer, _ i: Int32) -> String? {
            sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : txt(stmt, i)
        }
        while sqlite3_step(sstmt) == SQLITE_ROW {
            let prefix = (try? dec.decode([String].self, from: Data(txt(sstmt, 9).utf8))) ?? []
            let cpStrings = (try? dec.decode([String].self, from: Data(txt(sstmt, 10).utf8))) ?? []
            let created = parseISO8601(txt(sstmt, 3)) ?? Date(timeIntervalSince1970: 0)
            states.append(GraphState(
                id: txt(sstmt, 0), parentID: opt(sstmt, 1), modelIdentity: txt(sstmt, 2),
                createdAt: created, position: Int(sqlite3_column_int64(sstmt, 4)),
                continuationID: txt(sstmt, 5), nextInput: txt(sstmt, 8),
                anchor: txt(sstmt, 6), prefix: prefix, lifecycle: txt(sstmt, 7),
                checkpointIDs: cpStrings.compactMap { UUID(uuidString: $0) }))
        }
        var cps: [GraphCheckpoint] = []
        let cstmt = try prepare("""
        SELECT checkpoint_id, state_id, model_identity, position, continuation_id,
               next_input, anchor, prefix_json, created_at, checksum
        FROM checkpoints ORDER BY created_at;
        """)
        defer { sqlite3_finalize(cstmt) }
        while sqlite3_step(cstmt) == SQLITE_ROW {
            let prefix = (try? dec.decode([String].self, from: Data(txt(cstmt, 7).utf8))) ?? []
            guard let uuid = UUID(uuidString: txt(cstmt, 0)) else { continue }
            cps.append(GraphCheckpoint(
                id: uuid, stateID: txt(cstmt, 1), modelIdentity: txt(cstmt, 2),
                position: Int(sqlite3_column_int64(cstmt, 3)), continuationID: txt(cstmt, 4),
                nextInput: txt(cstmt, 5), anchor: txt(cstmt, 6), prefix: prefix,
                createdAt: parseISO8601(txt(cstmt, 8)) ?? Date(timeIntervalSince1970: 0),
                checksum: txt(cstmt, 9)))
        }
        return (states, cps)
    }

    public func hasExecutionStates() throws -> Bool { try count("execution_states") > 0 }

    /// A durable settlement (IS) read back for the app's UI projection. Excludes
    /// `MIGRATED_LEGACY` rows (legacy checkpoints imported into the settlement
    /// table by the v1 path) so they never surface as live receipts.
    public struct SettlementReceiptRow {
        public let id: UUID
        public let stateID: String
        public let schemaVersion: String
        public let payload: Data
        public let payloadDigest: String
        public let settledAt: Date
    }

    public func readSettlementReceipts() throws -> [SettlementReceiptRow] {
        let stmt = try prepare("""
        SELECT settlement_id, state_id, schema_version, payload, payload_digest, settled_at,
               payload_object_id
        FROM settlements
        WHERE validation_status IS NULL OR validation_status != 'MIGRATED_LEGACY'
        ORDER BY settled_at, settlement_id;
        """)
        defer { sqlite3_finalize(stmt) }
        func t(_ i: Int32) -> String { sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "" }
        var out: [SettlementReceiptRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let uuid = UUID(uuidString: t(0)) else { continue }
            let objectID = t(6)
            let payload: Data
            if !objectID.isEmpty {
                payload = try readObject(objectID)
            } else {
                let bytes = Int(sqlite3_column_bytes(stmt, 3))
                if let base = sqlite3_column_blob(stmt, 3), bytes > 0 {
                    payload = Data(bytes: base, count: bytes)
                } else { payload = Data() }
            }
            out.append(SettlementReceiptRow(
                id: uuid, stateID: t(1), schemaVersion: t(2), payload: payload,
                payloadDigest: t(4), settledAt: parseISO8601(t(5)) ?? Date(timeIntervalSince1970: 0)))
        }
        return out
    }

    private func fetchColumn(_ sql: String) throws -> [String] {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) { out.append(String(cString: c)) }
        }
        return out
    }

    private func isReferencedBySettlement(_ stateID: String) throws -> Bool {
        let stmt = try prepare("SELECT 1 FROM settlements WHERE state_id=? LIMIT 1;")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, stateID)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    /// Lossless timestamp codec for the authoritative store. The legacy JSON graph
    /// round-tripped `Date` exactly (its `Codable` form stores the raw reference-date
    /// double); making SQLite the authority must NOT lose sub-second precision, or a
    /// graph rebuilt via `readGraph()` would drift from the live in-memory document
    /// (the durable-persist contract). We persist `timeIntervalSinceReferenceDate` —
    /// the exact value `Date.==` compares — as a 17-significant-digit string and
    /// reconstruct via `Date(timeIntervalSinceReferenceDate:)`, so the round-trip is
    /// bit-identical. (Using 1970-relative seconds is NOT safe: the constant epoch
    /// offset is not bit-exact for ~1.7e9 values, so equal 1970 seconds can hide
    /// unequal reference bits and `Date ==` fails.) Legacy ISO-8601 rows written
    /// before this codec still parse, so existing databases keep loading.
    private static func stamp(_ date: Date) -> String {
        String(format: "%.17g", date.timeIntervalSinceReferenceDate)
    }

    private func parseISO8601(_ text: String) -> Date? {
        if let t = Double(text) { return Date(timeIntervalSinceReferenceDate: t) }
        return ISO8601DateFormatter().date(from: text)
    }
}
