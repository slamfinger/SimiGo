import Darwin
import Foundation
import SQLite3

/// Carrier tables hold history, not mutable state. Triggers stop ordinary
/// UPDATE/DELETE; the authorizer additionally denies ALTER/DROP and any
/// UPDATE/DELETE that would remain after a trigger is dropped, so the
/// append-only guarantee does not depend on a trigger still being present.
private let simigoCarrierProtectedTables: Set<String> = [
    "is_objects",
    "is_index_entries",
    "is_dependency_entries",
]

private func simigoCarrierAuthorizer(
    _ userData: UnsafeMutableRawPointer?,
    _ action: Int32,
    _ arg1: UnsafePointer<CChar>?,
    _ arg2: UnsafePointer<CChar>?,
    _ dbName: UnsafePointer<CChar>?,
    _ trigger: UnsafePointer<CChar>?
) -> Int32 {
    let table: String?
    switch action {
    case SQLITE_ALTER_TABLE, SQLITE_DROP_TABLE:
        // arg1 is the database name, arg2 the table name.
        table = arg2.map { String(cString: $0) }
    case SQLITE_UPDATE, SQLITE_DELETE:
        table = arg1.map { String(cString: $0) }
    default:
        return SQLITE_OK
    }
    guard let table, simigoCarrierProtectedTables.contains(table) else {
        return SQLITE_OK
    }
    return SQLITE_DENY
}

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
public final class ESISDatabase {

    public enum DatabaseError: Error, Equatable {
        case cannotOpen(String)
        case notADatabase(String)
        case sql(String)
        /// The registered locator has changed since its last settled digest.
        case staleExternalSource(rootID: String, relativePath: String)
        /// The source path is no longer there (ENOENT/ENOTDIR). Kept distinct
        /// from a path that now leads somewhere else: a vanished source is
        /// drift the retrieval reports as stale, a redirected one is refused.
        case sourceGone(path: String)
        /// A descriptor's bytes or read-stability metadata changed during a read.
        /// Callers that can safely replay the complete read may retry a bounded number of times.
        case sourceChangedWhileBeingRead(path: String)
        case contractVersionMismatch(String)
        case migrationMismatch(String)
        /// SQLite API execution failure. Preserves primary and extended result
        /// codes (including BUSY/LOCKED, I/O, and extended constraint codes) so
        /// callers can classify without parsing localized message strings.
        case executionFailure(primary: Int32, extended: Int32, message: String)
    }

    private let handle: OpaquePointer
    private let url: URL
    private let closeLock = NSLock()
    private var handleIsClosed = false
    /// `ensureRoomSchema` 已在这个连接上跑过。见该函数的注释。
    private var roomSchemaReady = false

    /// One-shot mutation hook for the deterministic same-inode read regression.
    var beforeRootFileVerificationForTesting: (() -> Void)?
    /// Replace the path after enumeration but before removal reconciliation.
    var afterRootEnumerationForTesting: (() -> Void)?
    /// Replace the root after all scan reads but immediately before transaction commit.
    var beforeRootScanCommitForTesting: (() -> Void)?
    // Deterministic barrier for the room-rebuild read/replace concurrency test.
    var beforeRoomRebuildWriteForTesting: (() -> Void)?
    /// Deterministic failure injection for room-axis error propagation tests.
    var beforeSpaceAxisLookupForTesting: ((String) throws -> Void)?
    var beforeMergeSpaceAbsorbedCountForTesting: (() throws -> Void)?

    /// NOFOLLOW must judge the leaf, not the symlink aliases macOS uses for
    /// /var and /tmp, so resolve the parent only and keep the original leaf.
    private static func canonicalLeafPath(for url: URL) -> String {
        let parent = url.deletingLastPathComponent()
        guard let resolved = parent.path.withCString({ Darwin.realpath($0, nil) }) else {
            return url.path
        }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
            .appendingPathComponent(url.lastPathComponent).path
    }

    /// Open (and optionally create) the database at `url`, applying PRAGMAs.
    ///
    /// `busyTimeoutMS` 只为测试存在：契约测试要制造真正的 SQLITE_BUSY（锁被
    /// 另一个连接持住），默认 5000 会让每个用例白等五秒。产品路径一律默认值。
    public init(
        url: URL, createIfNeeded: Bool = true, readOnly: Bool = false,
        busyTimeoutMS: Int32 = 5000
    ) throws {
        self.url = url
        guard !(readOnly && createIfNeeded) else {
            throw DatabaseError.cannotOpen("read-only open cannot create a database")
        }
        // First-run ordering: ensure the parent directory exists before opening.
        // sqlite3_open does NOT create intermediate directories.
        if createIfNeeded {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        // NOFOLLOW judges the database leaf, not macOS aliases such as /var and
        // /tmp. Resolve the parent only and keep the original leaf name.
        let accessFlag = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
        var flags: Int32 = accessFlag | SQLITE_OPEN_NOFOLLOW
        if createIfNeeded { flags |= SQLITE_OPEN_CREATE }
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(Self.canonicalLeafPath(for: url), &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(rc)"
            if let db { sqlite3_close_v2(db) }
            throw DatabaseError.cannotOpen(msg)
        }
        self.handle = db
        // Install the busy handler before the first contended statement:
        // opening a WAL database whose last connection just closed triggers
        // recovery, and a concurrent opener contends on that recovery.
        try Self.rawExec(handle, "PRAGMA busy_timeout = \(busyTimeoutMS);")
        // Fail closed if an existing file is not a usable database. integrity_check
        // is read-only and preserves execution failures separately from corruption.
        switch Self.integrityOutcome(handle) {
        case .ok:
            break
        case .corrupted(let detail):
            throw DatabaseError.notADatabase(
                "integrity_check failed for \(url.lastPathComponent): \(detail)")
        case .executionError(let primary, let extended, let message):
            throw DatabaseError.executionFailure(
                primary: primary, extended: extended, message: message)
        }
        if readOnly {
            // Diagnostics must not switch journal mode or write the store.
            try Self.rawExec(handle, "PRAGMA foreign_keys = ON;")
            try Self.rawExec(handle, "PRAGMA query_only = ON;")
        } else {
            try Self.applyPragmas(handle)
        }
        Self.installCarrierAuthorizer(handle)
    }

    /// Explicit close and deinitialization share one serialized, one-shot close.
    /// Keep the handle retryable if SQLite reports that closing did not succeed.
    private func closeHandleIfNeeded() {
        closeLock.lock()
        defer { closeLock.unlock() }
        guard !handleIsClosed else { return }
        if sqlite3_close_v2(handle) == SQLITE_OK {
            handleIsClosed = true
        }
    }

    public func close() { closeHandleIfNeeded() }
    deinit { closeHandleIfNeeded() }

    private static func applyPragmas(_ db: OpaquePointer) throws {
        for sql in [
            "PRAGMA foreign_keys = ON;",
            "PRAGMA journal_mode = WAL;",
            "PRAGMA synchronous = FULL;"
        ] { try rawExec(db, sql) }
    }

    private static func installCarrierAuthorizer(_ db: OpaquePointer) {
        // Failure here is not fatal: the SQL triggers remain the primary guard.
        _ = sqlite3_set_authorizer(db, simigoCarrierAuthorizer, nil)
    }

    private static func rawExec(_ db: OpaquePointer, _ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let m = err.map { String(cString: $0) } ?? "code \(rc)"
            sqlite3_free(err)
            throw sqliteFailure(db, resultCode: rc, message: m)
        }
    }

    private static func sqliteFailure(
        _ db: OpaquePointer, resultCode: Int32? = nil, message: String? = nil
    ) -> DatabaseError {
        let reportedExtended = sqlite3_extended_errcode(db)
        let reportedCode = resultCode ?? reportedExtended
        let primary = reportedCode & 0xff
        let extended = reportedExtended == SQLITE_OK ? reportedCode : reportedExtended
        let detail = message ?? String(cString: sqlite3_errmsg(db))
        return .executionFailure(primary: primary, extended: extended, message: detail)
    }

    private enum IntegrityOutcome {
        case ok
        /// Diagnostic rows: the file is not a database, or integrity_check
        /// reported problems — the corruption path.
        case corrupted(String)
        /// The statement could not execute (e.g. SQLITE_BUSY /
        /// SQLITE_LOCKED). An execution condition, never a corruption
        /// verdict; the SQLite result codes travel with it.
        case executionError(primary: Int32, extended: Int32, message: String)
    }

    private static func integrityOutcome(_ db: OpaquePointer) -> IntegrityOutcome {
        var stmt: OpaquePointer?
        let prepareRC = sqlite3_prepare_v2(db, "PRAGMA integrity_check;", -1, &stmt, nil)
        guard prepareRC == SQLITE_OK else {
            let primary = sqlite3_errcode(db)
            let message = String(cString: sqlite3_errmsg(db))
            if primary == SQLITE_NOTADB {
                return .corrupted(message)
            }
            return .executionError(
                primary: primary, extended: sqlite3_extended_errcode(db), message: message)
        }
        defer { sqlite3_finalize(stmt) }
        var messages: [String] = []
        while true {
            let stepRC = sqlite3_step(stmt)
            if stepRC == SQLITE_ROW {
                messages.append(
                    sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "")
                continue
            }
            if stepRC == SQLITE_DONE { break }

            let primary = sqlite3_errcode(db)
            let message = String(cString: sqlite3_errmsg(db))
            if primary == SQLITE_NOTADB {
                return .corrupted(message)
            }
            return .executionError(
                primary: primary, extended: sqlite3_extended_errcode(db), message: message)
        }
        guard !messages.isEmpty else {
            return .corrupted("integrity_check returned no rows")
        }
        return messages == ["ok"] ? .ok : .corrupted(messages.joined(separator: "\n"))
    }

    /// Corruption is a negative integrity verdict; an SQLite execution failure
    /// is not. Preserve the latter's result codes through this throwing API so
    /// callers never mistake BUSY/LOCKED/I/O conditions for damaged storage.
    public func integrityCheck() throws -> Bool {
        switch Self.integrityOutcome(handle) {
        case .ok:
            return true
        case .corrupted(_):
            return false
        case .executionError(let primary, let extended, let message):
            throw DatabaseError.executionFailure(
                primary: primary, extended: extended, message: message)
        }
    }

    // MARK: - Migrations

    /// Highest applied schema version, or 0 if none.
    public func schemaVersion() throws -> Int {
        // Only a missing migration table identifies a fresh database. A prepare
        // or step error on an existing schema must never downgrade it to v0.
        do {
            let table = try prepare("""
            SELECT 1 FROM sqlite_master
            WHERE type='table' AND name='schema_migrations' LIMIT 1;
            """)
            defer { sqlite3_finalize(table) }
            guard try stepRowOrDone(table) else { return 0 }
        }

        let stmt = try prepare("SELECT MAX(version) FROM schema_migrations;")
        defer { sqlite3_finalize(stmt) }
        guard try stepRowOrDone(stmt) else {
            throw DatabaseError.sql("schemaVersion: MAX(version) returned no row")
        }
        return Int(sqlite3_column_int64(stmt, 0))
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

    /// v9 is the Execution/Information loop itself: an Execution State defines a
    /// demand, the Information Space settles what that demand resolves to, and an
    /// advancement records the child ES that consumed it. The tables are additive;
    /// `retrieval_settlements` gains only the two columns the bridge needs (whether
    /// chat was part of the input, and the bridged settlement id).
    private static let v9 = """
    CREATE TABLE IF NOT EXISTS information_demands(
        demand_id TEXT PRIMARY KEY,
        state_id TEXT,
        session_id TEXT,
        continuation_point TEXT NOT NULL,
        query TEXT NOT NULL,
        required_item_ids_json TEXT NOT NULL,
        pending_obligations_json TEXT NOT NULL,
        continuation_conditions_json TEXT NOT NULL,
        input_digest TEXT NOT NULL,
        retrieval_demand_id TEXT,
        retrieval_settlement_id TEXT,
        state TEXT NOT NULL,
        created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS information_advancements(
        advancement_id TEXT PRIMARY KEY,
        demand_id TEXT NOT NULL,
        state_id TEXT NOT NULL,
        settlement_id TEXT NOT NULL,
        retrieval_settlement_id TEXT,
        actions_json TEXT NOT NULL,
        result_json TEXT NOT NULL,
        advanced_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS information_items(
        item_id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        locator TEXT NOT NULL,
        source_version TEXT NOT NULL,
        source_payload_sha256 TEXT NOT NULL,
        state TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS chat_execution_links(
        session_id TEXT PRIMARY KEY,
        current_state_id TEXT NOT NULL,
        model_identity TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_information_demands_state
        ON information_demands(state_id, created_at);
    CREATE INDEX IF NOT EXISTS idx_information_advancements_demand
        ON information_advancements(demand_id);
    CREATE INDEX IF NOT EXISTS idx_information_items_kind
        ON information_items(kind, state);
    """

    private static let v9Columns: [(table: String, column: String, sql: String)] = [
        ("retrieval_settlements", "include_chat",
         "ALTER TABLE retrieval_settlements ADD COLUMN include_chat INTEGER NOT NULL DEFAULT 0;"),
        ("retrieval_settlements", "bridged_settlement_id",
         "ALTER TABLE retrieval_settlements ADD COLUMN bridged_settlement_id TEXT;"),
    ]

    /// v10 is the post-settlement distillation: every model-produced settlement
    /// gains a bounded, deterministic summary stored as a content-addressed
    /// object, so a later demand can cite a settled conclusion as information
    /// instead of re-reading the files and turns it was derived from. The row is
    /// keyed by settlement and keeps the source payload digest it distilled, so
    /// a summary can never be read as belonging to a different settlement.
    private static let v10 = """
    CREATE TABLE IF NOT EXISTS settlement_summaries(
        settlement_id TEXT PRIMARY KEY,
        session_id TEXT,
        query TEXT NOT NULL,
        summary TEXT NOT NULL,
        summary_sha256 TEXT NOT NULL,
        summary_object_id TEXT NOT NULL,
        source_payload_digest TEXT NOT NULL,
        created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_settlement_summaries_created
        ON settlement_summaries(created_at, settlement_id);
    """

    /// v11 is STAGE B: a settled result may declare that it can be consumed
    /// verbatim by a later execution state, and every consumption is recorded as
    /// its own row linked to the source it consumed. A settlement without a
    /// declaration is not consumable; a consumption never records KV bindings and
    /// carries `model_calls` as data, not as log text. Derived settlements are
    /// `DERIVED_CONSUMPTION` rows: chainable as a continuation anchor, never
    /// counted as model output.
    private static let v11 = """
    CREATE TABLE IF NOT EXISTS settlement_reuse_contracts(
        settlement_id TEXT PRIMARY KEY,
        contract_id TEXT NOT NULL,
        demand_class TEXT NOT NULL,
        contract_version TEXT NOT NULL,
        query TEXT NOT NULL,
        root_ids_json TEXT NOT NULL,
        canonical_text TEXT NOT NULL,
        canonical_digest TEXT NOT NULL,
        required_identity_json TEXT NOT NULL,
        extract_field TEXT NOT NULL,
        declared_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS settlement_consumptions(
        consumption_id TEXT PRIMARY KEY,
        source_settlement_id TEXT NOT NULL,
        consumer_state_id TEXT NOT NULL,
        consumer_settlement_id TEXT NOT NULL,
        demand_id TEXT NOT NULL,
        contract_id TEXT NOT NULL,
        demand_class TEXT NOT NULL,
        contract_version TEXT NOT NULL,
        canonical_digest TEXT NOT NULL,
        basis_json TEXT NOT NULL,
        model_calls INTEGER NOT NULL CHECK(model_calls=0),
        created_at TEXT NOT NULL,
        UNIQUE(source_settlement_id, consumer_state_id, demand_id)
    );
    CREATE INDEX IF NOT EXISTS idx_settlement_consumptions_source
        ON settlement_consumptions(source_settlement_id);
    CREATE INDEX IF NOT EXISTS idx_settlement_consumptions_consumer
        ON settlement_consumptions(consumer_settlement_id);
    """

    private static let v11SummaryColumns: [(table: String, column: String, sql: String)] = [
        ("settlement_summaries", "derivation_type",
         "ALTER TABLE settlement_summaries ADD COLUMN derivation_type TEXT;"),
        ("settlement_summaries", "provenance_settlement_id",
         "ALTER TABLE settlement_summaries ADD COLUMN provenance_settlement_id TEXT;"),
    ]

    /// v12 is STAGE C's settlement reference to its as-of snapshot: a settlement
    /// may point at the immutable `final` snapshot object written in the same
    /// commit. The column is nullable and never backfilled — NULL means the row
    /// predates snapshot capture and carries no such evidence, which must not be
    /// fabricated. Declared snapshots that never reached P2 stay as orphans by
    /// design: v1 has no TTL and no GC, and a zero reference count is not
    /// deletion authorization.
    private static let v12Columns: [(table: String, column: String, sql: String)] = [
        ("settlements", "input_snapshot_object_id",
         "ALTER TABLE settlements ADD COLUMN input_snapshot_object_id TEXT REFERENCES is_objects(object_id);"),
    ]

    private static let v12Indexes = """
    CREATE INDEX IF NOT EXISTS idx_settlements_input_snapshot
        ON settlements(input_snapshot_object_id);
    """

    /// v13: the managed-continuation idempotency key. Nullable (ordinary and
    /// B-path states carry none) and never backfilled; the partial unique index
    /// makes "one execution per fingerprint" a storage guarantee as well as a
    /// checked precondition, while leaving NULL keys unconstrained.
    private static let v13Columns: [(table: String, column: String, sql: String)] = [
        ("execution_states", "idempotency_key",
         "ALTER TABLE execution_states ADD COLUMN idempotency_key TEXT;"),
    ]

    private static let v13Indexes = """
    CREATE UNIQUE INDEX IF NOT EXISTS idx_execution_states_idempotency
        ON execution_states(idempotency_key) WHERE idempotency_key IS NOT NULL;
    """

    /// v14 is the Stage-1 answer-reuse record: a turn served from an
    /// already-settled answer instead of a model call leaves its own row. The
    /// source settlement is NOT rewritten and no consumer execution state is
    /// invented (a reuse creates none), so `consumer_state_id` stays NULL.
    /// `model_calls=0` is a column, not log text, and `canonical_digest` seals
    /// the exact (scope, user text) key the reuse was decided on.
    private static let v14 = """
    CREATE TABLE IF NOT EXISTS information_reuse_events(
        reuse_id TEXT PRIMARY KEY,
        source_settlement_id TEXT NOT NULL,
        source_state_id TEXT NOT NULL,
        demand_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        consumer_state_id TEXT,
        canonical_digest TEXT NOT NULL,
        model_calls INTEGER NOT NULL CHECK(model_calls=0),
        reused_at TEXT NOT NULL
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_information_reuse_demand
        ON information_reuse_events(demand_id);
    CREATE INDEX IF NOT EXISTS idx_information_reuse_source
        ON information_reuse_events(source_settlement_id);
    """

    /// v15 is turn eligibility for chat retrieval. A user row is written when
    /// the request starts, but it only becomes ordinary semantic memory when
    /// that same turn produces its reply. Rows written before this migration
    /// keep the default 'committed': their turns already happened and this
    /// migration must not rewrite history.
    private static let v15Columns: [(table: String, column: String, sql: String)] = [
        ("chat_messages", "turn_state",
         "ALTER TABLE chat_messages ADD COLUMN turn_state TEXT NOT NULL DEFAULT 'committed';"),
    ]

    private static let v15Indexes = """
    CREATE INDEX IF NOT EXISTS idx_chat_messages_eligible
        ON chat_messages(session_id, turn_state, id);
    """

    /// v16 is external-source provenance. Information that passed through an
    /// upstream API is kept in the same space as conversation, but its arrival
    /// is not its standing: rows are written `recorded` with the provider and
    /// the request that produced them, and only `verifyExternalTurn` — which
    /// requires that request's own question and answer to both be present —
    /// promotes them to `committed`. Rows written before this migration are
    /// local conversation and keep the defaults; history is not rewritten.
    private static let v16Columns: [(table: String, column: String, sql: String)] = [
        ("chat_messages", "source_kind",
         "ALTER TABLE chat_messages ADD COLUMN source_kind TEXT NOT NULL DEFAULT 'local';"),
        ("chat_messages", "source_provider",
         "ALTER TABLE chat_messages ADD COLUMN source_provider TEXT;"),
        ("chat_messages", "request_id",
         "ALTER TABLE chat_messages ADD COLUMN request_id TEXT;"),
        ("chat_messages", "verified_at",
         "ALTER TABLE chat_messages ADD COLUMN verified_at TEXT;"),
    ]

    private static let v16Indexes = """
    CREATE INDEX IF NOT EXISTS idx_chat_messages_request
        ON chat_messages(session_id, request_id);
    CREATE INDEX IF NOT EXISTS idx_chat_messages_source
        ON chat_messages(source_kind, turn_state, id);
    """

    /// v17 is cross-path settlement idempotency. A source identity is the
    /// producer-declared provenance of one result — type, session, turn,
    /// message, revision. One source revision settles once, and the payload
    /// digest is part of the record so a second path either returns the
    /// existing row or is refused; equal text alone never merges two writes.
    /// A new revision is explicit, links to the settlement it supersedes, and
    /// is never derived from a repeated arrival. The operation key is the
    /// same guarantee for one call that has no provable source identity.
    /// `information_demands.request_identity` keeps a retrieval demand's
    /// lifecycle with the request that raised it: a call without a session has
    /// no shared demand to supersede, while knowledge stays shared.
    private static let v17Tables = """
    CREATE TABLE IF NOT EXISTS settlement_source_identities(
        identity_id TEXT PRIMARY KEY,
        source_type TEXT NOT NULL,
        source_session_id TEXT NOT NULL,
        source_turn_id TEXT NOT NULL,
        source_message_id TEXT NOT NULL,
        source_revision INTEGER NOT NULL CHECK(source_revision>=1),
        payload_digest TEXT NOT NULL,
        settlement_id TEXT NOT NULL UNIQUE REFERENCES settlements(settlement_id),
        previous_settlement_id TEXT REFERENCES settlements(settlement_id),
        created_at TEXT NOT NULL,
        UNIQUE(source_type, source_session_id, source_turn_id, source_message_id, source_revision)
    );
    CREATE INDEX IF NOT EXISTS idx_settlement_source_chain
        ON settlement_source_identities(
            source_type, source_session_id, source_turn_id, source_message_id,
            source_revision DESC);
    CREATE TABLE IF NOT EXISTS settlement_operation_keys(
        operation_key TEXT PRIMARY KEY,
        payload_digest TEXT NOT NULL,
        settlement_id TEXT NOT NULL REFERENCES settlements(settlement_id),
        created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_settlement_operation_keys_settlement
        ON settlement_operation_keys(settlement_id);
    """

    private static let v17Columns: [(table: String, column: String, sql: String)] = [
        ("information_demands", "request_identity",
         "ALTER TABLE information_demands ADD COLUMN request_identity TEXT;"),
    ]

    private static let v17Indexes = """
    CREATE INDEX IF NOT EXISTS idx_information_demands_request
        ON information_demands(session_id, request_identity, query, state);
    """

    /// v18 binds the tokenizer identity to the ES at begin time. NULL remains
    /// meaningful for legacy/non-MCP states; MCP settlement requires a recorded
    /// begin-time tokenizer and never backfills an unverifiable identity.
    private static let v18Columns: [(table: String, column: String, sql: String)] = [
        ("execution_states", "tokenizer_identity",
         "ALTER TABLE execution_states ADD COLUMN tokenizer_identity TEXT;"),
    ]

    /// v19 distinguishes states owned by the native graph from externally begun
    /// MCP executions. A graph snapshot may reconcile only its own states; it
    /// must not erase an external, unsettled ES that has not entered that graph.
    private static let v19Columns: [(table: String, column: String, sql: String)] = [
        ("execution_states", "graph_managed",
         "ALTER TABLE execution_states ADD COLUMN graph_managed INTEGER NOT NULL DEFAULT 1;"),
    ]

    /// Apply pending migrations, each inside its own transaction. Idempotent.
    public func runMigrations() throws {
        if try schemaVersion() < 1 {
            try transaction {
                try Self.rawExec(handle, ESISDatabase.v1)
                try recordMigrationRow(1, "simigo-es-is-v1")
            }
        }
        if try schemaVersion() < 2 {
            try transaction {
                try Self.rawExec(handle, ESISDatabase.v2)
                try recordMigrationRow(2, "simigo-es-is-v2")
            }
        }
        if try schemaVersion() < 3 {
            try transaction {
                try Self.rawExec(handle, ESISDatabase.v3)
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
                try Self.rawExec(handle, ESISDatabase.v8Tables)
                for column in ESISDatabase.v8Columns
                where try !columnExists(column.table, column.column) {
                    try Self.rawExec(handle, column.sql)
                }
                try Self.rawExec(handle, ESISDatabase.v8Indexes)
                try backfillCarrierObjectsV8()
                try recordMigrationRow(8, "simigo-is-carrier-v8")
            }
        }
        if try schemaVersion() < 9 {
            try transaction {
                try Self.rawExec(handle, ESISDatabase.v9)
                for column in ESISDatabase.v9Columns
                where try !columnExists(column.table, column.column) {
                    try Self.rawExec(handle, column.sql)
                }
                try recordMigrationRow(9, "simigo-es-is-loop-v9")
            }
        }
        if try schemaVersion() < 10 {
            try transaction {
                try Self.rawExec(handle, ESISDatabase.v10)
                _ = try backfillSettlementSummariesInTransaction()
                try recordMigrationRow(10, "simigo-settlement-summaries-v10")
            }
        }
        if try schemaVersion() < 11 {
            try transaction {
                try Self.rawExec(handle, ESISDatabase.v11)
                for column in ESISDatabase.v11SummaryColumns
                where try !columnExists(column.table, column.column) {
                    try Self.rawExec(handle, column.sql)
                }
                try recordMigrationRow(11, "simigo-settlement-consumption-v11")
            }
        }
        if try schemaVersion() < 12 {
            try transaction {
                for column in ESISDatabase.v12Columns
                where try !columnExists(column.table, column.column) {
                    try Self.rawExec(handle, column.sql)
                }
                try Self.rawExec(handle, ESISDatabase.v12Indexes)
                try recordMigrationRow(12, "simigo-snapshot-reference-v12")
            }
        }
        if try schemaVersion() < 13 {
            try transaction {
                for column in ESISDatabase.v13Columns
                where try !columnExists(column.table, column.column) {
                    try Self.rawExec(handle, column.sql)
                }
                try Self.rawExec(handle, ESISDatabase.v13Indexes)
                try recordMigrationRow(13, "simigo-managed-idempotency-v13")
            }
        }
        if try schemaVersion() < 14 {
            try transaction {
                try Self.rawExec(handle, ESISDatabase.v14)
                try recordMigrationRow(14, "simigo-information-reuse-v14")
            }
        }
        if try schemaVersion() < 15 {
            try transaction {
                for column in ESISDatabase.v15Columns
                where try !columnExists(column.table, column.column) {
                    try Self.rawExec(handle, column.sql)
                }
                try Self.rawExec(handle, ESISDatabase.v15Indexes)
                try recordMigrationRow(15, "simigo-chat-turn-eligibility-v15")
            }
        }
        if try schemaVersion() < 16 {
            try transaction {
                for column in ESISDatabase.v16Columns
                where try !columnExists(column.table, column.column) {
                    try Self.rawExec(handle, column.sql)
                }
                try Self.rawExec(handle, ESISDatabase.v16Indexes)
                try recordMigrationRow(16, "simigo-external-turn-provenance-v16")
            }
        }
        if try schemaVersion() < 17 {
            try transaction {
                try Self.rawExec(handle, ESISDatabase.v17Tables)
                for column in ESISDatabase.v17Columns
                where try !columnExists(column.table, column.column) {
                    try Self.rawExec(handle, column.sql)
                }
                try Self.rawExec(handle, ESISDatabase.v17Indexes)
                try recordMigrationRow(17, "simigo-settlement-source-identity-v17")
            }
        }
        if try schemaVersion() < 18 {
            try transaction {
                for column in ESISDatabase.v18Columns
                where try !columnExists(column.table, column.column) {
                    try Self.rawExec(handle, column.sql)
                }
                try recordMigrationRow(18, "simigo-es-tokenizer-identity-v18")
            }
        }
        if try schemaVersion() < 19 {
            try transaction {
                for column in ESISDatabase.v19Columns
                where try !columnExists(column.table, column.column) {
                    try Self.rawExec(handle, column.sql)
                }
                try recordMigrationRow(19, "simigo-es-graph-ownership-v19")
            }
        }
        if try schemaVersion() < 20 {
            try transaction {
                // Historical InformationLoop rows stored an opaque demand hash,
                // so their source paths cannot be identified selectively. Mark
                // those rows for conservative invalidation; v2 rows are explicit.
                try Self.rawExec(handle, """
                UPDATE retrieval_settlements
                SET inputs_digest='legacy-v1:' || inputs_digest
                WHERE inputs_digest NOT LIKE '{%'
                  AND inputs_digest NOT LIKE 'v2:%'
                  AND inputs_digest NOT LIKE 'legacy-v1:%';
                """)
                try recordMigrationRow(20, "simigo-retrieval-input-basis-version-v20")
            }
        }
        if try schemaVersion() < 21 {
            try transaction {
                // v2 added these two columns with `ALTER TABLE ... ADD COLUMN` and
                // no DEFAULT, and `insertExecutionStateRow` never listed
                // checkpoint_ids_json, so a NULL here is a legacy write, not
                // corruption. readGraph() fails closed on NULL, so rewrite each
                // list from the authoritative `checkpoints` rows for that state and
                // fall back to the serialized empty collection. Blank or malformed
                // values are deliberately left alone: they stay corruption.
                // The ordering is explicit rather than left to the scan, so the
                // rebuilt list matches the `created_at` order readGraph() gives the
                // checkpoints it joins to, whatever physical order the rows live in.
                try Self.rawExec(handle, """
                UPDATE execution_states
                SET checkpoint_ids_json = COALESCE(
                        (SELECT json_group_array(ordered.checkpoint_id)
                           FROM (SELECT checkpoint_id, created_at
                                   FROM checkpoints
                                  WHERE checkpoints.state_id = execution_states.state_id
                                  ORDER BY created_at, checkpoint_id) AS ordered),
                        '[]')
                WHERE checkpoint_ids_json IS NULL;
                UPDATE execution_states
                SET prefix_json = '[]'
                WHERE prefix_json IS NULL;
                """)
                try recordMigrationRow(21, "simigo-es-legacy-null-graph-columns-v21")
            }
        }
        if try schemaVersion() < 22 {
            try transaction {
                // The two producers of dependency_edges (advancement and
                // consumption) already guard with NOT EXISTS; the public
                // addDependency did not, so a caller repeating a pair could
                // inflate the graph. Collapse the historical duplicates first,
                // then let the constraint hold for every future writer.
                try Self.rawExec(handle, """
                DELETE FROM dependency_edges
                WHERE edge_id NOT IN (
                    SELECT MIN(edge_id) FROM dependency_edges
                    GROUP BY from_settlement, to_settlement, kind
                );
                CREATE UNIQUE INDEX IF NOT EXISTS idx_dependency_edges_unique
                    ON dependency_edges(from_settlement, to_settlement, kind);
                """)
                // Invalidation recorded when a row stopped being eligible but
                // never why. The cause is what makes "typed invalidation" a
                // statement about the data rather than about our intentions.
                if try !columnExists("settlements", "invalidated_cause") {
                    try Self.rawExec(handle, """
                    ALTER TABLE settlements ADD COLUMN invalidated_cause TEXT;
                    """)
                }
                try recordMigrationRow(22, "simigo-dependency-edge-unique-v22")
            }
        }
        if try schemaVersion() < 23 {
            try transaction {
                // v3 put dynamic validity on the settlement row itself, so
                // "this result no longer holds" was a mutation of the result.
                // Split the two axes: a settlement row carries only sealed
                // content and provenance; validity is an append-only event
                // ledger, and the current value is derived from it. Nothing
                // rewrites a settlement to record that its evidence moved,
                // and a settlement that was never invalidated carries one
                // 'valid' event and no invalid one.
                try Self.rawExec(handle, """
                CREATE TABLE IF NOT EXISTS settlement_validity_events(
                    event_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    settlement_id TEXT NOT NULL,
                    validity TEXT NOT NULL,
                    cause TEXT,
                    recorded_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_settlement_validity_events_settlement
                    ON settlement_validity_events(settlement_id, event_id);
                INSERT INTO settlement_validity_events(
                    settlement_id, validity, cause, recorded_at)
                SELECT settlement_id, 'valid', NULL, settled_at FROM settlements
                 WHERE NOT EXISTS (
                    SELECT 1 FROM settlement_validity_events e
                     WHERE e.settlement_id = settlements.settlement_id);
                """)
                // A database whose tables were rebuilt out of order may have
                // skipped v3 and never gained the columns at all; there is
                // nothing to migrate from in that case.
                if try columnExists("settlements", "validity") {
                    let hasAt = try columnExists("settlements", "invalidated_at")
                    let hasCause = try columnExists("settlements", "invalidated_cause")
                    let at = hasAt ? "ifnull(invalidated_at, settled_at)" : "settled_at"
                    let cause = hasCause ? "invalidated_cause" : "NULL"
                    try Self.rawExec(handle, """
                    INSERT INTO settlement_validity_events(
                        settlement_id, validity, cause, recorded_at)
                    SELECT settlement_id, 'invalid', \(cause), \(at)
                      FROM settlements WHERE validity = 'invalid';
                    """)
                }
                try Self.rawExec(handle, """
                CREATE VIEW IF NOT EXISTS settlement_current_validity AS
                SELECT s.settlement_id,
                       ifnull(v.validity, 'valid') AS validity,
                       CASE WHEN v.validity = 'invalid'
                            THEN v.recorded_at END AS invalidated_at,
                       CASE WHEN v.validity = 'invalid'
                            THEN v.cause END AS invalidated_cause
                  FROM settlements s
                  LEFT JOIN settlement_validity_events v
                    ON v.event_id = (
                        SELECT MAX(e.event_id) FROM settlement_validity_events e
                         WHERE e.settlement_id = s.settlement_id);
                """)
                // No second source of truth: the columns go away once their
                // contents live in the ledger. The old index references the
                // column, so it must be dropped first.
                try Self.rawExec(handle, "DROP INDEX IF EXISTS idx_settlements_validity;")
                for column in ["validity", "invalidated_at", "invalidated_cause"] {
                    if try columnExists("settlements", column) {
                        try Self.rawExec(
                            handle, "ALTER TABLE settlements DROP COLUMN \(column);")
                    }
                }
                try recordMigrationRow(23, "simigo-settlement-validity-ledger-v23")
            }
        }
        if try schemaVersion() < 24 {
            try transaction {
                // MCP rounds arrive one call at a time and nothing in the
                // protocol forces every round to arrive: the caller decides.
                // A ledger of "which round numbers were seen" turns that from
                // an assumption into a reading — a gap is a number missing from
                // this table, not a fact nobody recorded.
                try Self.rawExec(handle, """
                CREATE TABLE IF NOT EXISTS chat_turn_ledger(
                    session_id TEXT NOT NULL,
                    turn_index INTEGER NOT NULL,
                    request_id TEXT NOT NULL,
                    seen_at TEXT NOT NULL,
                    PRIMARY KEY(session_id, turn_index)
                );
                CREATE INDEX IF NOT EXISTS idx_chat_turn_ledger_session
                    ON chat_turn_ledger(session_id, turn_index);
                """)
                try recordMigrationRow(24, "simigo-chat-turn-ledger-v24")
            }
        }
        if try schemaVersion() < 25 {
            try transaction {
                // A project brief is a judgement, not a document. Documents are
                // appended and then superseded by newer documents of the same
                // name; a judgement that is rewritten in place loses the record
                // of what was believed before. So each note is immutable, and
                // "current" is derived: the note of a kind that nothing later
                // supersedes. Nothing is overwritten and nothing is deleted.
                try Self.rawExec(handle, """
                CREATE TABLE IF NOT EXISTS project_notes(
                    note_id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,
                    claim TEXT NOT NULL,
                    supersedes TEXT,
                    object_id TEXT NOT NULL,
                    recorded_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_project_notes_kind
                    ON project_notes(kind, recorded_at);
                """)
                try recordMigrationRow(25, "simigo-project-notes-v25")
            }
        }

        if try schemaVersion() < 26 {
            try transaction {
                // 标题只是给人看的名字，不进唯一键（键是 root_id + relative_path）。
                // 默认值由文件名推导；人改过之后，重新导入不再覆盖。
                if try !columnExists("external_files", "title") {
                    try Self.rawExec(handle, "ALTER TABLE external_files ADD COLUMN title TEXT;")
                }
                try recordMigrationRow(26, "simigo-external-file-title-v26")
            }
        }

        if try schemaVersion() < 27 {
            try transaction {
                // 检索索引。正文只在 is_objects 里存一份（47 MB，最大单条 1.6 MB），
                // 按 LIKE 全扫是 0.21 s，关键词一多就线性叠上去；trigram 查询 < 0.01 s。
                // trigram 是唯一能吃中文子串的分词器——unicode61 放中文进去是
                // 0 命中且不报错，所以不能用默认分词。
                //
                // 用 external content：索引只存 3 字片段，不复制正文（复制一份
                // 实测让 47 MB 变成 84 MB）。is_objects 是只增的内容寻址表：
                // 全仓没有 UPDATE / DELETE，所以只需要一条 INSERT 触发器。
                try Self.rawExec(handle, """
                CREATE VIRTUAL TABLE IF NOT EXISTS is_objects_fts USING fts5(
                    content,
                    content='is_objects',
                    content_rowid='rowid',
                    tokenize='trigram'
                );
                CREATE TRIGGER IF NOT EXISTS is_objects_fts_ai
                AFTER INSERT ON is_objects BEGIN
                    INSERT INTO is_objects_fts(rowid, content)
                    VALUES (new.rowid, CAST(new.content AS TEXT));
                END;
                """)
                // 已有对象一次性补进索引（建表时 INSERT 触发器还不存在）。
                try Self.rawExec(handle,
                    "INSERT INTO is_objects_fts(is_objects_fts) VALUES('rebuild');")
                try recordMigrationRow(27, "simigo-object-fts-trigram-v27")
            }
        }

        if try schemaVersion() < 28 {
            try transaction {
                // v28：索引只覆盖结算产物/摘要，不再覆盖全部正文。
                //
                // v27 对 is_objects 全表建 trigram（7,098 个对象 / 45 MB 正文），
                // 索引 88 MB，比正文还大；其中绝大多数是从没进过结算的会话
                // 正文与登记文件。结算真正引用过的对象只有 714 个 / 9 MB。
                // 索引是派生物，不是历史：重建它不抹任何记录。
                //
                // 未进索引的行不丢：检索 SQL 对「不在索引里的行」回落 LIKE，
                // 两条路的并集仍是原来的命中集合。
                try Self.rawExec(handle, """
                DROP TRIGGER IF EXISTS is_objects_fts_ai;
                DROP TABLE IF EXISTS is_objects_fts;
                DROP TABLE IF EXISTS is_search_indexed;
                CREATE VIRTUAL TABLE is_objects_fts USING fts5(
                    content,
                    content='is_objects',
                    content_rowid='rowid',
                    tokenize='trigram'
                );
                -- FTS5 的 external content 表不能全表扫描（只能 MATCH 或按 rowid），
                -- 所以「这行在不在索引里」用一张小登记表回答，检索时据此决定
                -- 走索引还是回落 LIKE。
                CREATE TABLE is_search_indexed(
                    object_rowid INTEGER PRIMARY KEY,
                    object_id TEXT NOT NULL
                );
                INSERT INTO is_objects_fts(rowid, content)
                SELECT o.rowid, CAST(o.content AS TEXT) FROM is_objects o
                WHERE o.object_id IN (
                    SELECT payload_object_id FROM settlements
                     WHERE payload_object_id IS NOT NULL
                    UNION SELECT summary_object_id FROM settlement_summaries
                    UNION SELECT result_object_id FROM retrieval_settlements
                     WHERE result_object_id IS NOT NULL
                );
                INSERT INTO is_search_indexed(object_rowid, object_id)
                SELECT rowid, object_id FROM is_objects
                WHERE object_id IN (
                    SELECT payload_object_id FROM settlements
                     WHERE payload_object_id IS NOT NULL
                    UNION SELECT summary_object_id FROM settlement_summaries
                    UNION SELECT result_object_id FROM retrieval_settlements
                     WHERE result_object_id IS NOT NULL
                );
                CREATE TRIGGER IF NOT EXISTS is_fts_settlements_ai
                AFTER INSERT ON settlements BEGIN
                    INSERT INTO is_objects_fts(rowid, content)
                    SELECT o.rowid, CAST(o.content AS TEXT) FROM is_objects o
                     WHERE o.object_id = new.payload_object_id
                       AND NOT EXISTS (SELECT 1 FROM is_search_indexed s WHERE s.object_rowid = o.rowid);
                    INSERT OR IGNORE INTO is_search_indexed(object_rowid, object_id)
                    SELECT o.rowid, o.object_id FROM is_objects o
                     WHERE o.object_id = new.payload_object_id;
                END;
                CREATE TRIGGER IF NOT EXISTS is_fts_settlements_au
                AFTER UPDATE OF payload_object_id ON settlements BEGIN
                    INSERT INTO is_objects_fts(rowid, content)
                    SELECT o.rowid, CAST(o.content AS TEXT) FROM is_objects o
                     WHERE o.object_id = new.payload_object_id
                       AND NOT EXISTS (SELECT 1 FROM is_search_indexed s WHERE s.object_rowid = o.rowid);
                    INSERT OR IGNORE INTO is_search_indexed(object_rowid, object_id)
                    SELECT o.rowid, o.object_id FROM is_objects o
                     WHERE o.object_id = new.payload_object_id;
                END;
                CREATE TRIGGER IF NOT EXISTS is_fts_summaries_ai
                AFTER INSERT ON settlement_summaries BEGIN
                    INSERT INTO is_objects_fts(rowid, content)
                    SELECT o.rowid, CAST(o.content AS TEXT) FROM is_objects o
                     WHERE o.object_id = new.summary_object_id
                       AND NOT EXISTS (SELECT 1 FROM is_search_indexed s WHERE s.object_rowid = o.rowid);
                    INSERT OR IGNORE INTO is_search_indexed(object_rowid, object_id)
                    SELECT o.rowid, o.object_id FROM is_objects o
                     WHERE o.object_id = new.summary_object_id;
                END;
                CREATE TRIGGER IF NOT EXISTS is_fts_retrieval_ai
                AFTER INSERT ON retrieval_settlements BEGIN
                    INSERT INTO is_objects_fts(rowid, content)
                    SELECT o.rowid, CAST(o.content AS TEXT) FROM is_objects o
                     WHERE o.object_id = new.result_object_id
                       AND NOT EXISTS (SELECT 1 FROM is_search_indexed s WHERE s.object_rowid = o.rowid);
                    INSERT OR IGNORE INTO is_search_indexed(object_rowid, object_id)
                    SELECT o.rowid, o.object_id FROM is_objects o
                     WHERE o.object_id = new.result_object_id;
                END;
                CREATE TRIGGER IF NOT EXISTS is_fts_retrieval_au
                AFTER UPDATE OF result_object_id ON retrieval_settlements BEGIN
                    INSERT INTO is_objects_fts(rowid, content)
                    SELECT o.rowid, CAST(o.content AS TEXT) FROM is_objects o
                     WHERE o.object_id = new.result_object_id
                       AND NOT EXISTS (SELECT 1 FROM is_search_indexed s WHERE s.object_rowid = o.rowid);
                    INSERT OR IGNORE INTO is_search_indexed(object_rowid, object_id)
                    SELECT o.rowid, o.object_id FROM is_objects o
                     WHERE o.object_id = new.result_object_id;
                END;
                """)
                try recordMigrationRow(28, "simigo-object-fts-settled-only-v28")
            }
        }

        if try schemaVersion() < 29 {
            // 清理要绕过两层保护：append-only 触发器，和 authorizer 对受保护表
            // 的 DELETE 拒绝。两者都只在这一次迁移里摘掉，跑完立刻装回。
            _ = sqlite3_set_authorizer(handle, nil, nil)
            do {
                try transaction {
                // v29：一次性清掉 demand-input 历史。
                //
                // v28 起不再写这类行，但库里已有 184,512 条——388 个 demand，
                // 每个约 475 条候选，同一份候选清单被重复抄了一遍。它们不是
                // 历史事实：query、时间、状态都在 information_demands 里，
                // 依赖表里这些行只是检索过程的副本。
                //
                // append-only 触发器是给常规写入用的保护；这里是显式维护，
                // 所以先把触发器摘掉、删完再装回去，并把删除行数写进迁移记录。
                let candidates: Int = try {
                    let stmt = try prepare(
                        "SELECT COUNT(*) FROM is_dependency_entries WHERE reason='demand-input';")
                    defer { sqlite3_finalize(stmt) }
                    return try stepRowOrDone(stmt) ? Int(sqlite3_column_int64(stmt, 0)) : 0
                }()
                try Self.rawExec(handle, """
                DROP TRIGGER IF EXISTS is_dependency_entries_append_only_update;
                DROP TRIGGER IF EXISTS is_dependency_entries_append_only_delete;
                DELETE FROM is_dependency_entries WHERE reason='demand-input';
                CREATE TRIGGER is_dependency_entries_append_only_update
                    BEFORE UPDATE ON is_dependency_entries BEGIN
                        SELECT RAISE(ABORT, 'is_dependency_entries is append-only');
                    END;
                CREATE TRIGGER is_dependency_entries_append_only_delete
                    BEFORE DELETE ON is_dependency_entries BEGIN
                        SELECT RAISE(ABORT, 'is_dependency_entries is append-only');
                    END;
                """)
                    try recordMigrationRow(
                        29, "simigo-drop-demand-input-candidates-v29: deleted \(candidates) rows")
                }
            } catch {
                _ = sqlite3_set_authorizer(handle, simigoCarrierAuthorizer, nil)
                throw error
            }
            _ = sqlite3_set_authorizer(handle, simigoCarrierAuthorizer, nil)
        }

        if try schemaVersion() < 30 {
            try transaction {
                // v30：settlement_summaries.query 只留问题开头，全文留在摘要对象里。
                //
                // 这一列原本是第二份全文：184 行 3.2 MB，而 96k 压测把同一份
                // 384 KB 文本在对象、这一列、FTS 三处各存了一遍。摘要对象是
                // 权威副本，每次读 summary 都要解开它并校验（verified(_:)），
                // 所以这一列不必再存全文。
                //
                // query_truncated 记住这一行存的是前缀还是全文：读的时候全文
                // 必须逐字相等、前缀必须 hasPrefix，校验通过再把对象里的全文
                // 还给调用方——对外拿到的仍是完整问题，只有落盘的行变短了。
                if try !columnExists("settlement_summaries", "query_truncated") {
                    try Self.rawExec(
                        handle,
                        """
                        ALTER TABLE settlement_summaries
                        ADD COLUMN query_truncated INTEGER NOT NULL DEFAULT 0;
                        """)
                }
                let limit = Int64(SettlementSummaryPolicy.queryExcerptCharacters)
                let shortened: Int = try {
                    let stmt = try prepare("""
                    SELECT COUNT(*) FROM settlement_summaries WHERE LENGTH(query) > ?;
                    """)
                    defer { sqlite3_finalize(stmt) }
                    try bind(stmt, 1, limit)
                    return try stepRowOrDone(stmt) ? Int(sqlite3_column_int64(stmt, 0)) : 0
                }()
                try execBinding("""
                UPDATE settlement_summaries
                   SET query = substr(query, 1, ?), query_truncated = 1
                 WHERE LENGTH(query) > ?;
                """) { stmt in
                    try bind(stmt, 1, limit)
                    try bind(stmt, 2, limit)
                }
                try recordMigrationRow(
                    30,
                    "simigo-settlement-query-excerpt-v30: shortened \(shortened) rows "
                        + "to \(limit) chars")
            }
        }

        if try schemaVersion() < 31 {
            try transaction {
                // v31：轮次摘要 + 关键字索引，另加 external_files.title_source。
                //
                // 三张表都是辅助层：删掉整张表，ES/IS 照常工作——摘要对应的
                // 问题与回答正文在 is_objects 里，经 chat_messages.content_object_id
                // 取回，这里不再存第二份指针。v30 刚因为「同一事实存两处」把
                // query 列截短，这张表不重犯。
                //
                // 主键用 (session_id, turn_index) 而不是 answer_message_id：
                // turn_index 就是 chat_turn_ledger 的编号，「摘要缺哪轮」和
                // 「轮号缺口」是同一件事，一次对齐即可核。同一轮再摘要一次
                // 是覆盖（派生内容可重建），不是写第二行。
                try Self.rawExec(handle, """
                CREATE TABLE IF NOT EXISTS turn_digests(
                    session_id TEXT NOT NULL,
                    turn_index INTEGER NOT NULL,
                    question_message_id INTEGER REFERENCES chat_messages(id) ON DELETE SET NULL,
                    answer_message_id INTEGER REFERENCES chat_messages(id) ON DELETE SET NULL,
                    digest TEXT NOT NULL,
                    keywords TEXT NOT NULL,
                    model TEXT,
                    created_at TEXT NOT NULL,
                    PRIMARY KEY(session_id, turn_index)
                );
                CREATE INDEX IF NOT EXISTS turn_digests_answer
                    ON turn_digests(answer_message_id);
                CREATE TABLE IF NOT EXISTS keywords(
                    keyword_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    term TEXT NOT NULL UNIQUE,
                    created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS turn_keywords(
                    session_id TEXT NOT NULL,
                    turn_index INTEGER NOT NULL,
                    keyword_id INTEGER NOT NULL
                        REFERENCES keywords(keyword_id) ON DELETE CASCADE,
                    PRIMARY KEY(session_id, turn_index, keyword_id),
                    FOREIGN KEY(session_id, turn_index)
                        REFERENCES turn_digests(session_id, turn_index) ON DELETE CASCADE
                );
                """)
                // 标题的来源。人整理文件时文件名常常就是标题，这种行标
                // 'filename'；标题从文内读出的是 'document'，人改过的是
                // 'human'。有了这一列，占位标题和真标题才分得开：以后文内
                // 标题补上了，只换 'filename' 那些行，人定的不被覆盖。
                //
                // 目录不另建节点表：人按类别分文件夹，就是先定了粗身份，
                // 那个身份就在 relative_path 的前缀里，derive 得出来。
                if try !columnExists("external_files", "title_source") {
                    try Self.rawExec(handle, """
                    ALTER TABLE external_files ADD COLUMN title_source TEXT;
                    UPDATE external_files SET title_source='filename'
                     WHERE title IS NOT NULL AND title<>'';
                    """)
                }
                try recordMigrationRow(31, "simigo-turn-digests-v31")
            }
        }

        if try schemaVersion() < 32 {
            try transaction {
                // v32：空间（归集键）。
                //
                // 身份和位置分开：space_id 是身份，root 是它今天落在哪个目录。
                // 空间只做归集、只用来把检索范围先切小，绝不进 object_id、
                // canonical_digest、dependency_id、复用判据——一旦进去，同一份
                // 内容放在两个空间下就会被认成两条依赖，复用就失效了。
                try Self.rawExec(handle, """
                CREATE TABLE IF NOT EXISTS spaces(
                    space_id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    title_source TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    parent_space_id TEXT REFERENCES spaces(space_id),
                    created_at TEXT NOT NULL
                );
                """)
                if try !columnExists("roots", "space_id") {
                    try Self.rawExec(handle, """
                    ALTER TABLE roots ADD COLUMN space_id TEXT REFERENCES spaces(space_id);
                    ALTER TABLE agent_sessions ADD COLUMN space_id TEXT REFERENCES spaces(space_id);
                    CREATE INDEX IF NOT EXISTS roots_space ON roots(space_id);
                    CREATE INDEX IF NOT EXISTS agent_sessions_space
                        ON agent_sessions(space_id);
                    """)
                }
                // 回填：现有每个 root 一个空间，标题取路径最后一段，标成占位
                // （'filename'），人改过就是 'human'。space_id 不从路径算：这几个
                // 空间是此刻建的，跟它今天待在哪个目录无关，以后搬家也不变。
                var pending: [(rootID: String, title: String, kind: String)] = []
                let listing = try prepare("""
                SELECT root_id, COALESCE(display_name,''), COALESCE(locator_type,'')
                  FROM roots WHERE space_id IS NULL ORDER BY root_id;
                """)
                defer { sqlite3_finalize(listing) }
                while try stepRowOrDone(listing) {
                    let rootID = sqlite3_column_text(listing, 0).map { String(cString: $0) } ?? ""
                    let display = sqlite3_column_text(listing, 1).map { String(cString: $0) } ?? ""
                    let locator = sqlite3_column_text(listing, 2).map { String(cString: $0) } ?? ""
                    let last = (display as NSString).lastPathComponent
                    pending.append((
                        rootID,
                        last.isEmpty ? rootID : last,
                        locator == "path" ? "directory" : "collection"))
                }
                let now = Self.stamp(Date())
                for entry in pending {
                    let spaceID = "space-" + UUID().uuidString.lowercased()
                    try execBinding("""
                    INSERT INTO spaces(space_id, title, title_source, kind,
                                       parent_space_id, created_at)
                    VALUES(?,?,'filename',?,NULL,?);
                    """) { stmt in
                        try bind(stmt, 1, spaceID)
                        try bind(stmt, 2, entry.title)
                        try bind(stmt, 3, entry.kind)
                        try bind(stmt, 4, now)
                    }
                    try execBinding("UPDATE roots SET space_id=? WHERE root_id=?;") { stmt in
                        try bind(stmt, 1, spaceID)
                        try bind(stmt, 2, entry.rootID)
                    }
                }
                try recordMigrationRow(
                    32, "simigo-spaces-v32: \(pending.count) spaces")
            }
        }

        if try schemaVersion() < 33 {
            try transaction {
                // v33：root 所在目录的 inode。
                //
                // 路径只是名字。同一个名字可以是另一个目录——挂载被替换、
                // bind mount、整个卷换掉——这时候「看不到文件」不是删除。
                // MemPalace 的 source_identity.py 把这几种形状写全了，并且
                // 解释为什么只能靠目录自己的 inode：st_dev 分不开 bind mount
                // （两边同设备），而目录的 inode 属于文件系统结构。
                // 取不到就存 NULL：没建立过身份，绝不当成「变了」。
                if try !columnExists("roots", "locator_inode") {
                    try Self.rawExec(
                        handle, "ALTER TABLE roots ADD COLUMN locator_inode INTEGER;")
                }
                try recordMigrationRow(33, "simigo-root-locator-inode-v33")
            }
        }

        if try schemaVersion() < 34 {
            // 受保护表的 ALTER 会被 authorizer 拒（is_dependency_entries 在
            // 保护名单里）。和 v29 一样，只在这一次迁移里摘掉，跑完立刻装回。
            //
            // v34：依赖有了两个时钟。
            //
            //   valid_from / valid_to  世界时间——这份字节从哪里到什么时候为真
            //   known_from / known_to  记录时间——ES 从哪里到哪里这么认为
            //
            // 只用一个时钟会出错：拿「上一版的 ES 时间」当 valid_to，而
            // valid_from 用文件自己的修改时间，两个版本之间就会重叠（内容
            // 早就变了，我们才在几小时后发现）。两个时钟分开，区间就不重叠，
            // 也仍然答得出「那天这个文件是什么」。
            _ = sqlite3_set_authorizer(handle, nil, nil)
            do {
                try transaction {
                    if try !columnExists("is_dependency_entries", "source_time") {
                        try Self.rawExec(handle, """
                        ALTER TABLE is_dependency_entries ADD COLUMN source_time TEXT;
                        """)
                    }
                    try Self.rawExec(handle, """
                    DROP VIEW IF EXISTS is_dependency_intervals;
                    CREATE VIEW is_dependency_intervals AS
                    SELECT dependency_id,
                           content_address,
                           revision,
                           recorded_at AS known_from,
                           LEAD(recorded_at) OVER (
                               PARTITION BY dependency_id ORDER BY revision) AS known_to,
                           COALESCE(source_time, recorded_at) AS valid_from,
                           LEAD(COALESCE(source_time, recorded_at)) OVER (
                               PARTITION BY dependency_id ORDER BY revision) AS valid_to,
                           CASE WHEN source_time IS NULL THEN 'es-time'
                                ELSE 'source-time' END AS valid_from_source
                      FROM is_dependency_entries;
                    """)
                    try recordMigrationRow(34, "simigo-dependency-intervals-v34")
                }
            } catch {
                _ = sqlite3_set_authorizer(handle, simigoCarrierAuthorizer, nil)
                throw error
            }
            _ = sqlite3_set_authorizer(handle, simigoCarrierAuthorizer, nil)
        }

        if try schemaVersion() < 35 {
            try transaction {
                // v35：轮次账要写清「谁的轮号」。
                //
                // chat_turn_ledger 原本只记 MCP 的 chat_round：轮号是调用方
                // 自己选的，缺号就是漏写——这个判断只对调用方成立。
                //
                // 采集桥导入的历史没有调用方编号，轮序只能由到达序排出来。
                // 这种行的轮号必然连续，「缺号」对它不成立。两种行混在一起
                // 读，缺号会被当成漏写去补，所以 origin 写进行里，不靠
                // session 前缀去猜。
                if try !columnExists("chat_turn_ledger", "origin") {
                    try Self.rawExec(handle, """
                    ALTER TABLE chat_turn_ledger
                      ADD COLUMN origin TEXT NOT NULL DEFAULT 'mcp';
                    """)
                }
                try recordMigrationRow(35, "simigo-turn-ledger-origin-v35")
            }
        }

        if try schemaVersion() < 36 {
            try transaction {
                // v36：结算行要落「哪一版任务级结果契约授权了它」。
                //
                // 放开派生后，同一份输入可以被不同任务契约结算成不同结果。
                // 只记 payload 摘要分不清这是复述还是某个派生任务的产物，也
                // 审计不到它依据的契约版本。所以把契约 id 与契约内容摘要写进
                // 行里：id 命名契约，摘要钉住那一版的确切字节。旧行没有这两列，
                // 留 NULL——不回填、不猜历史契约。
                if try !columnExists("settlements", "result_contract_id") {
                    try Self.rawExec(handle, """
                    ALTER TABLE settlements ADD COLUMN result_contract_id TEXT;
                    """)
                }
                if try !columnExists("settlements", "result_contract_digest") {
                    try Self.rawExec(handle, """
                    ALTER TABLE settlements ADD COLUMN result_contract_digest TEXT;
                    """)
                }
                try recordMigrationRow(36, "simigo-result-contract-identity-v36")
            }
        }

        // 已释放的页不会自己还给文件系统：v28 收窄索引、v29 清候选各留下几万页
        // freelist（实测 38,732 页 / 158 MB）。打开时看一眼，超过阈值就 VACUUM。
        //
        // 不能写成「只在跨过某个版本时做一次」：真机上那次 VACUUM 撞上另一个
        // 连接会失败，而迁移已经提交，于是文件永远停在 258 MB，再也没人回收。
        // 所以判据是实际状态（freelist），不是版本号；失败也不阻断启动，
        // 下次打开再试。
        let freedPages: Int = try {
            let stmt = try prepare("PRAGMA freelist_count;")
            defer { sqlite3_finalize(stmt) }
            return try stepRowOrDone(stmt) ? Int(sqlite3_column_int64(stmt, 0)) : 0
        }()
        // 门槛 400 页（1.6 MB）：v30 只把 query 列截短，实测释放 783 页。
        // 门槛定在 2000 的话这次回收永远够不着，文件就停在原大小——和上面
        // 那个「一次性判据」是同一类错。400 页以下不值得一次全库重写。
        if freedPages > 400 {
            do {
                try Self.rawExec(handle, "VACUUM;")
                clearVacuumFailure()
            } catch {
                recordVacuumFailure(freedPages: freedPages, error: "\(error)")
            }
        }

        // The declared head and the applied head must agree. A migration gate
        // that was written but never reached, or a version bumped in the
        // constant but not in a gate, otherwise shows up as a store that is
        // simply one version behind — quiet, and indistinguishable from an old
        // file. This turns both directions into a failure at open time.
        let head = try schemaVersion()
        guard head == Self.currentSchemaVersion else {
            throw DatabaseError.sql(
                "migration head \(head) != declared \(Self.currentSchemaVersion)")
        }
    }

    /// The version `runMigrations` brings a store to.
    public static let currentSchemaVersion = 36

    /// Last VACUUM failure, if the previous attempt left one behind.
    ///
    /// Two releases in a row hit this: v28/v29 freed 38,732 pages but the
    /// threshold was 2,000 pages *of freelist at open* and the migration that
    /// freed them committed before the threshold was ever consulted; v30 freed
    /// 772 pages, crossed the new threshold, and then the VACUUM itself lost a
    /// race with another connection. Both times `try?` swallowed it, the file
    /// stayed at its old size, and the only way to notice was comparing
    /// `freelist_count` by hand. A silent failure to reclaim space is not a
    /// detail — it is the difference between a store that shrinks and one that
    /// never does.
    public var lastVacuumFailure: String? {
        guard let data = try? Data(contentsOf: maintenanceURL),
            let raw = try? JSONSerialization.jsonObject(with: data),
            let object = raw as? [String: Any],
            let reason = object["reason"] as? String
        else { return nil }
        let at = object["at"] as? String ?? "unknown time"
        let pages = object["freedPages"] as? Int ?? 0
        return "\(at) VACUUM failed, \(pages) pages unreclaimed: \(reason)"
    }

    /// Sits next to the store it describes, so a copy of the directory keeps
    /// the diagnosis with the data.
    private var maintenanceURL: URL {
        url.deletingLastPathComponent().appendingPathComponent("simigo.maintenance.json")
    }

    private func recordVacuumFailure(freedPages: Int, error: String) {
        let payload: [String: Any] = [
            "at": ISO8601DateFormatter().string(from: Date()),
            "freedPages": freedPages,
            "reason": error,
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys])
        else { return }
        try? data.write(to: maintenanceURL, options: .atomic)
    }

    private func clearVacuumFailure() {
        try? FileManager.default.removeItem(at: maintenanceURL)
    }

    private func columnExists(_ table: String, _ column: String) throws -> Bool {
        let stmt = try prepare("PRAGMA table_info(\(table));")
        defer { sqlite3_finalize(stmt) }
        while try stepRowOrDone(stmt) {
            if let c = sqlite3_column_text(stmt, 1), String(cString: c) == column {
                return true
            }
        }
        return false
    }

    /// 表在不在。用于外部工具建的附属表（如 `space_turns`）：新库上没有它们，
    /// 读状态与房间维护必须照常可用。
    private func tableExists(_ table: String) throws -> Bool {
        let stmt = try prepare("PRAGMA table_info(\(table));")
        defer { sqlite3_finalize(stmt) }
        return try stepRowOrDone(stmt)
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
        public let settlementSummaries: Int
        public let danglingReferences: Int
        public let corruptObjects: Int
        public let inlineLegacyPayloads: Int
        public let deepVerified: Bool
        /// 空间（人给的分类）有几行。
        public let spaces: Int
        /// 依赖区间：闭合几段、还开着几段、世界时间轴上相邻两版接不上的有几处。
        /// 断点正常应当恒为 0——不是 0 就说明有一版的诞生时间早于上一版。
        public let dependencyIntervalsClosed: Int
        public let dependencyIntervalsOpen: Int
        public let dependencyIntervalBreaks: Int
        /// 轮次摘要覆盖：有摘要几轮、账本里有、摘要里没有几轮。
        public let turnDigests: Int
        public let turnsWithoutDigest: Int
        /// Set when the last startup VACUUM failed and the space it would have
        /// reclaimed is still on disk. Nil when the last attempt succeeded or
        /// was not needed.
        public let vacuumFailure: String?
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
        try bind(stmt, 1, objectID)
        guard try stepRowOrDone(stmt) else {
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
        try bind(stmt, 1, objectID)
        guard try stepRowOrDone(stmt) else { return nil }
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

    /// `true` only when the stored bytes still hash to their address. A missing
    /// or corrupt object is `false`, never an empty success.
    /// Verify an object without confusing storage execution failures with corruption.
    /// Missing or byte/address-mismatched objects are a negative verdict; SQLite
    /// prepare/bind/step failures remain typed errors for the caller.
    public func verifyObject(_ objectID: String) throws -> Bool {
        do {
            _ = try readObject(objectID)
            return true
        } catch let error as DatabaseError {
            if case .executionFailure = error { throw error }
            return false
        } catch {
            return false
        }
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
        try bind(stmt, 1, identity)
        guard try stepRowOrDone(stmt) else { return nil }
        return IndexEntry(
            appendOrder: Int(sqlite3_column_int64(stmt, 0)),
            identity: sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "",
            objectID: sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "",
            recordedAt: sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? "")
    }

    // MARK: - 依赖的区间（两个时钟）

    /// 一条依赖的一段有效期。
    ///
    /// `validFrom/validTo` 是世界时间：这份字节从哪里到什么时候为真。
    /// `knownFrom/knownTo` 是记录时间：ES 从哪里到哪里这么认为。两者分开，
    /// 因为文件可能早就改了、我们几小时后才发现——合成一个时钟，区间就会重叠。
    public struct DependencyInterval: Equatable, Sendable {
        public let dependencyID: String
        public let contentAddress: String
        public let validFrom: String
        public let validTo: String?
        public let knownFrom: String
        public let knownTo: String?
        /// `false` 表示这一版的 validFrom 没有源时间可用，回落到 ES 时间
        /// （v34 之前写下的行都是这样）。
        public let validFromIsSourceTime: Bool
    }

    public func dependencyIntervals(dependencyID: String) throws -> [DependencyInterval] {
        let stmt = try prepare("""
        SELECT dependency_id, content_address, valid_from, valid_to,
               known_from, known_to, valid_from_source
          FROM is_dependency_intervals
         WHERE dependency_id=? ORDER BY revision;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, dependencyID)
        var rows: [DependencyInterval] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String {
                sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
            }
            rows.append(DependencyInterval(
                dependencyID: text(0),
                contentAddress: text(1),
                validFrom: text(2),
                validTo: sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : text(3),
                knownFrom: text(4),
                knownTo: sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : text(5),
                validFromIsSourceTime: text(6) == "source-time"))
        }
        return rows
    }

    /// 某一时刻（世界时间）为真的地址。`nil` 表示那一刻没有记录在案的版本。
    ///
    /// 比较按数值走，不按文本：时间戳是 `%.17g`（`date.timeIntervalSinceReferenceDate`），
    /// 文本序和数值序在 2001 年之前（负值）和 1e9 之后（位数变多）不一致。
    public func dependencyAddress(dependencyID: String, validAt date: Date) throws -> String? {
        let moment = Self.stamp(date)
        let stmt = try prepare("""
        SELECT content_address FROM is_dependency_intervals
         WHERE dependency_id=?
           AND CAST(valid_from AS REAL) <= CAST(? AS REAL)
           AND (valid_to IS NULL OR CAST(valid_to AS REAL) > CAST(? AS REAL))
         ORDER BY CAST(valid_from AS REAL) DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, dependencyID)
        try bind(stmt, 2, moment)
        try bind(stmt, 3, moment)
        guard try stepRowOrDone(stmt) else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    // MARK: - C-stage failure audit (append-only)

    /// Best-effort terminal audit write for one execution attempt.
    ///
    /// Never throws and never overwrites: if an entry already exists for
    /// `c-failure-audit:<execution_id>`, nothing is written and
    /// `auditPersisted` is `false`. A storage failure is reported the same way,
    /// so the caller's terminal result is unchanged either way.
    public func recordFailureAudit(_ event: FailureAudit.Event) -> FailureAudit.WriteResult {
        let data: Data
        do {
            data = try FailureAudit.encoded(event)
        } catch {
            return FailureAudit.WriteResult(
                auditPersisted: false, objectID: nil, failureClass: "unrepresentable_event")
        }
        let identity = FailureAudit.identity(executionID: event.executionID)
        do {
            return try transactionResult {
                if try resolveIndexIdentity(identity, policy: .first) != nil {
                    return FailureAudit.WriteResult(
                        auditPersisted: false, objectID: nil, failureClass: "duplicate_execution_id")
                }
                let objectID = try ensureObject(data)
                _ = try appendIndexEntryInTransaction(identity: identity, objectID: objectID)
                return FailureAudit.WriteResult(
                    auditPersisted: true, objectID: objectID, failureClass: nil)
            }
        } catch {
            return FailureAudit.WriteResult(
                auditPersisted: false, objectID: nil, failureClass: "storage_failure")
        }
    }

    /// Read back the audit record for an execution attempt, verifying both the
    /// stored bytes and the record's own schema.
    public func failureAudit(executionID: String) -> FailureAudit.Event? {
        guard let entry = try? resolveIndexIdentity(
            FailureAudit.identity(executionID: executionID), policy: .first),
            let data = try? readObject(entry.objectID) else { return nil }
        return try? FailureAudit.decode(data)
    }

    /// Every audit entry ever appended for this execution id, oldest first.
    public func failureAuditHistory(executionID: String) throws -> [IndexEntry] {
        let stmt = try prepare("""
        SELECT append_order, srs_identity, record_object, recorded_at
        FROM is_index_entries WHERE srs_identity=? ORDER BY append_order;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, FailureAudit.identity(executionID: executionID))
        var out: [IndexEntry] = []
        while try stepRowOrDone(stmt) {
            out.append(IndexEntry(
                appendOrder: Int(sqlite3_column_int64(stmt, 0)),
                identity: sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "",
                objectID: sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "",
                recordedAt: sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""))
        }
        return out
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
        try bind(stmt, 1, dependencyID)
        var out: [DependencyEntry] = []
        while try stepRowOrDone(stmt) {
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
        defer { sqlite3_finalize(obj) }
        if try stepRowOrDone(obj) {
            objectCount = Int(sqlite3_column_int64(obj, 0))
            objectBytes = sqlite3_column_int64(obj, 1)
        }
        try reset(obj)

        var corrupt = 0
        if deepVerify {
            let all = try prepare("SELECT object_id FROM is_objects;")
            defer { sqlite3_finalize(all) }
            var ids: [String] = []
            while try stepRowOrDone(all) {
                guard let c = sqlite3_column_text(all, 0) else {
                    throw DatabaseError.sql("carrierReport: NULL object_id in object inventory")
                }
                ids.append(String(cString: c))
            }
            for id in ids {
                do {
                    _ = try readObject(id)
                } catch let error as DatabaseError {
                    if case .executionFailure = error { throw error }
                    corrupt += 1
                } catch {
                    corrupt += 1
                }
            }
        }

        func scalar(_ sql: String) throws -> Int {
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            return try stepRowOrDone(stmt) ? Int(sqlite3_column_int64(stmt, 0)) : 0
        }

        return CarrierReport(
            schemaVersion: try schemaVersion(),
            objectCount: objectCount,
            objectBytes: objectBytes,
            indexEntries: try scalar("SELECT COUNT(*) FROM is_index_entries;"),
            dependencyEntries: try scalar("SELECT COUNT(*) FROM is_dependency_entries;"),
            unaddressedFileContents: try scalar("""
                SELECT COUNT(*) FROM file_contents f
                WHERE f.object_id IS NULL
                  AND NOT EXISTS (
                    SELECT 1 FROM is_index_entries e
                    WHERE e.srs_identity =
                      'file:' || f.root_id || '/' || f.relative_path);
                """),
            unaddressedChatMessages: try scalar(
                "SELECT COUNT(*) FROM chat_messages WHERE content_object_id IS NULL;"),
            unaddressedRetrievalResults: try scalar(
                "SELECT COUNT(*) FROM retrieval_settlements WHERE result_object_id IS NULL;"),
            unaddressedSettlements: try scalar(
                "SELECT COUNT(*) FROM settlements WHERE payload_object_id IS NULL;"),
            settlementSummaries: try scalar(
                "SELECT COUNT(*) FROM settlement_summaries;"),
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
            deepVerified: deepVerify,
            spaces: try scalar("SELECT COUNT(*) FROM spaces;"),
            dependencyIntervalsClosed: try scalar(
                "SELECT COUNT(*) FROM is_dependency_intervals WHERE valid_to IS NOT NULL;"),
            dependencyIntervalsOpen: try scalar(
                "SELECT COUNT(*) FROM is_dependency_intervals WHERE valid_to IS NULL;"),
            dependencyIntervalBreaks: try scalar("""
                SELECT COUNT(*) FROM is_dependency_intervals a
                  JOIN is_dependency_intervals b
                    ON b.dependency_id=a.dependency_id AND b.revision=a.revision+1
                 WHERE a.valid_to IS NOT b.valid_from;
                """),
            turnDigests: try scalar("SELECT COUNT(*) FROM turn_digests;"),
            turnsWithoutDigest: try scalar("""
                SELECT COUNT(*) FROM chat_turn_ledger l
                 WHERE NOT EXISTS (SELECT 1 FROM turn_digests d
                                    WHERE d.session_id=l.session_id
                                      AND d.turn_index=l.turn_index);
                """),
            vacuumFailure: lastVacuumFailure)
    }

    private func ensureObject(_ data: Data) throws -> String {
        try ensureObjectWithStatus(data).id
    }

    private func ensureObjectWithStatus(_ data: Data) throws -> (id: String, created: Bool) {
        let objectID = NativeSHA256.hexDigest(data)
        let existing = try prepare("SELECT byte_size, content FROM is_objects WHERE object_id=?;")
        defer { sqlite3_finalize(existing) }
        try bind(existing, 1, objectID)
        if try stepRowOrDone(existing) {
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
        defer { sqlite3_finalize(orderStmt) }
        let nextOrder: Int
        if try stepRowOrDone(orderStmt) {
            nextOrder = Int(sqlite3_column_int64(orderStmt, 0))
        } else {
            nextOrder = 1
        }
        try reset(orderStmt)
        try execBinding("""
        INSERT INTO is_objects(object_id, byte_size, content, created_order, created_at)
        VALUES(?,?,?,?,?);
        """) { stmt in
            try bind(stmt, 1, objectID)
            try bind(stmt, 2, Int64(data.count))
            try bind(stmt, 3, data)
            try bind(stmt, 4, Int64(nextOrder))
            try bind(stmt, 5, Self.stamp(Date()))
        }
        return (objectID, true)
    }

    private func appendIndexEntryInTransaction(identity: String, objectID: String) throws -> Int {
        try execBinding("""
        INSERT INTO is_index_entries(srs_identity, record_object, recorded_at)
        VALUES(?,?,?);
        """) { stmt in
            try bind(stmt, 1, identity)
            try bind(stmt, 2, objectID)
            try bind(stmt, 3, Self.stamp(Date()))
        }
        return Int(sqlite3_last_insert_rowid(handle))
    }

    private func appendDependencyInTransaction(
        dependencyID: String, contentAddress: String, reason: String,
        sourceTime: String? = nil
    ) throws -> Int {
        let revisionStmt = try prepare("""
        SELECT COALESCE(MAX(revision),0)+1 FROM is_dependency_entries WHERE dependency_id=?;
        """)
        defer { sqlite3_finalize(revisionStmt) }
        try bind(revisionStmt, 1, dependencyID)
        let revision: Int
        if try stepRowOrDone(revisionStmt) {
            revision = Int(sqlite3_column_int64(revisionStmt, 0))
        } else {
            revision = 1
        }
        try reset(revisionStmt)
        try execBinding("""
        INSERT INTO is_dependency_entries(
            dependency_id, content_address, revision, reason, recorded_at, source_time)
        VALUES(?,?,?,?,?,?);
        """) { stmt in
            try bind(stmt, 1, dependencyID)
            try bind(stmt, 2, contentAddress)
            try bind(stmt, 3, Int64(revision))
            try bind(stmt, 4, reason)
            try bind(stmt, 5, Self.stamp(Date()))
            try bind(stmt, 6, sourceTime)
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
        defer { sqlite3_finalize(fileStmt) }
        while try stepRowOrDone(fileStmt) {
            files.append(InlineFile(
                root: sqlite3_column_text(fileStmt, 0).map { String(cString: $0) } ?? "",
                path: sqlite3_column_text(fileStmt, 1).map { String(cString: $0) } ?? "",
                content: sqlite3_column_text(fileStmt, 2).map { String(cString: $0) } ?? ""))
        }
        try reset(fileStmt)
        for file in files {
            let objectID = try ensureObject(Data(file.content.utf8))
            try execBinding("""
            UPDATE file_contents SET object_id=?, content_sha256=?, content=''
            WHERE root_id=? AND relative_path=?;
            """) { stmt in
                try bind(stmt, 1, objectID)
                try bind(stmt, 2, objectID)
                try bind(stmt, 3, file.root)
                try bind(stmt, 4, file.path)
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
                try bind(stmt, 1, objectID)
                try bind(stmt, 2, file.root)
                try bind(stmt, 3, file.path)
            }
        }

        struct InlineChat {
            let id: Int64; let session: String; let content: String
        }
        var chats: [InlineChat] = []
        let chatStmt = try prepare("""
        SELECT id, session_id, content FROM chat_messages WHERE content_object_id IS NULL;
        """)
        defer { sqlite3_finalize(chatStmt) }
        while try stepRowOrDone(chatStmt) {
            chats.append(InlineChat(
                id: sqlite3_column_int64(chatStmt, 0),
                session: sqlite3_column_text(chatStmt, 1).map { String(cString: $0) } ?? "",
                content: sqlite3_column_text(chatStmt, 2).map { String(cString: $0) } ?? ""))
        }
        try reset(chatStmt)
        for chat in chats {
            let objectID = try ensureObject(Data(chat.content.utf8))
            try execBinding("""
            UPDATE chat_messages SET content_object_id=?, content_sha256=?, content=''
            WHERE id=?;
            """) { stmt in
                try bind(stmt, 1, objectID)
                try bind(stmt, 2, objectID)
                try bind(stmt, 3, chat.id)
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
        defer { sqlite3_finalize(retrievalStmt) }
        while try stepRowOrDone(retrievalStmt) {
            retrievals.append(InlineRetrieval(
                demandID: sqlite3_column_text(retrievalStmt, 0).map { String(cString: $0) } ?? "",
                resultJSON: sqlite3_column_text(retrievalStmt, 1).map { String(cString: $0) } ?? ""))
        }
        try reset(retrievalStmt)
        for retrieval in retrievals {
            let objectID = try ensureObject(Data(retrieval.resultJSON.utf8))
            try execBinding("""
            UPDATE retrieval_settlements SET result_object_id=?, result_sha256=?, result_json=''
            WHERE demand_id=?;
            """) { stmt in
                try bind(stmt, 1, objectID)
                try bind(stmt, 2, objectID)
                try bind(stmt, 3, retrieval.demandID)
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
        defer { sqlite3_finalize(settlementStmt) }
        while try stepRowOrDone(settlementStmt) {
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
        try reset(settlementStmt)
        for settlement in settlements {
            let objectID = try ensureObject(settlement.payload)
            try execBinding("""
            UPDATE settlements SET payload_object_id=?, payload_digest=?, payload=X''
            WHERE settlement_id=?;
            """) { stmt in
                try bind(stmt, 1, objectID)
                try bind(stmt, 2, objectID)
                try bind(stmt, 3, settlement.id)
            }
            _ = try appendIndexEntryInTransaction(
                identity: "settlement:\(settlement.id)", objectID: objectID)
        }
    }

    private func recordMigrationRow(_ version: Int, _ checksum: String) throws {
        try execBinding("INSERT INTO schema_migrations(version, applied_at, checksum) VALUES(?,?,?);") { stmt in
            try bind(stmt, 1, Int64(version))
            try bind(stmt, 2, Self.stamp( Date()))
            try bind(stmt, 3, checksum)
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

    /// Value-returning variant. The value is only produced after COMMIT
    /// succeeds, so callers cannot observe a result whose writes rolled back.
    public func transactionResult<T>(_ body: () throws -> T) throws -> T {
        try begin("IMMEDIATE")
        do {
            let value = try body()
            try commit()
            return value
        } catch {
            rollback()
            throw error
        }
    }

    public func count(_ table: String) throws -> Int {
        // Table names are internal constants only, never user input.
        let stmt = try prepare("SELECT COUNT(*) FROM \(table);")
        defer { sqlite3_finalize(stmt) }
        guard try stepRowOrDone(stmt) else {
            throw DatabaseError.sql("count: SELECT COUNT(*) returned no row")
        }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    // MARK: - Statement binding helpers

    private static let transient: sqlite3_destructor_type? = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Advance a SELECT statement without confusing SQLITE_DONE with an
    /// execution failure. All row collections must consume through SQLITE_DONE.
    private func stepRowOrDone(_ stmt: OpaquePointer) throws -> Bool {
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW { return true }
        if rc == SQLITE_DONE { return false }
        throw Self.sqliteFailure(handle, resultCode: rc)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let prepared = stmt else {
            let message = String(cString: sqlite3_errmsg(handle))
            if let stmt { sqlite3_finalize(stmt) }
            throw Self.sqliteFailure(handle, resultCode: rc, message: message)
        }
        return prepared
    }

    private static func sqliteFailure(
        _ db: OpaquePointer, resultCode: Int32, message: String? = nil
    ) -> DatabaseError {
        let reportedExtended = sqlite3_extended_errcode(db)
        let primary = resultCode & 0xff
        let extended = reportedExtended == SQLITE_OK ? resultCode : reportedExtended
        let detail = message ?? String(cString: sqlite3_errmsg(db))
        return .executionFailure(primary: primary, extended: extended, message: detail)
    }

    private func checkStatementResult(_ resultCode: Int32, stmt: OpaquePointer) throws {
        guard resultCode == SQLITE_OK else {
            throw Self.sqliteFailure(sqlite3_db_handle(stmt), resultCode: resultCode)
        }
    }

    private func bind(_ stmt: OpaquePointer, _ i: Int32, _ text: String) throws {
        try checkStatementResult(
            sqlite3_bind_text(stmt, i, text, -1, Self.transient), stmt: stmt)
    }
    private func bind(_ stmt: OpaquePointer, _ i: Int32, _ value: Int64) throws {
        try checkStatementResult(sqlite3_bind_int64(stmt, i, value), stmt: stmt)
    }
    private func bind(_ stmt: OpaquePointer, _ i: Int32, _ blob: Data) throws {
        guard blob.count <= Int(Int32.max) else {
            throw DatabaseError.executionFailure(
                primary: SQLITE_TOOBIG, extended: SQLITE_TOOBIG,
                message: "SQLite blob binding exceeds the Int32 byte limit")
        }
        let resultCode: Int32
        if blob.isEmpty {
            // sqlite3_bind_blob(nil, 0) binds NULL; a zero blob must stay NOT NULL.
            resultCode = sqlite3_bind_zeroblob(stmt, i, 0)
        } else {
            resultCode = blob.withUnsafeBytes {
                sqlite3_bind_blob(stmt, i, $0.baseAddress, Int32(blob.count), Self.transient)
            }
        }
        try checkStatementResult(resultCode, stmt: stmt)
    }
    private func bindNull(_ stmt: OpaquePointer, _ i: Int32) throws {
        try checkStatementResult(sqlite3_bind_null(stmt, i), stmt: stmt)
    }
    private func bind(_ stmt: OpaquePointer, _ i: Int32, _ optional: String?) throws {
        if let optional { try bind(stmt, i, optional) } else { try bindNull(stmt, i) }
    }
    private func bind(_ stmt: OpaquePointer, _ i: Int32, _ optional: Int64?) throws {
        if let optional { try bind(stmt, i, optional) } else { try bindNull(stmt, i) }
    }
    private func reset(_ stmt: OpaquePointer) throws {
        try checkStatementResult(sqlite3_reset(stmt), stmt: stmt)
    }

    /// Test seam for deterministic SQLite bind failures; not part of the public API.
    func setSQLiteLengthLimitForTesting(_ limit: Int32) -> Int32 {
        sqlite3_limit(handle, SQLITE_LIMIT_LENGTH, limit)
    }

    /// Run a single write statement with bindings applied by `apply` before the step.
    @discardableResult
    private func execBinding(_ sql: String, _ apply: (OpaquePointer) throws -> Void) throws -> Int {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
try apply(stmt)
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE {
            let m = sqlite3_errmsg(handle).map { String(cString: $0) } ?? "step failed"
            throw Self.sqliteFailure(handle, resultCode: rc, message: m)
        }
        return Int(sqlite3_changes(handle))
    }

    // MARK: - Execution state write

    /// A child Execution State recorded in the SAME authoritative transaction as
    /// its settlement (continuation path). Fields mirror `recordExecutionState`.
    public struct ChildExecutionState: Sendable {
        public let id: String
        public let parentID: String?
        public let modelIdentity: String
        public let position: Int
        public let continuationID: String
        public let anchor: String
        public let createdAt: Date
        /// Durable continuation payload. A child state that survives a restart
        /// must carry the input its successor will resume from, otherwise the
        /// graph round-trips without the settlement it was created for.
        public let nextInput: String?
        public let prefixJSON: String?

        public init(id: String, parentID: String?, modelIdentity: String,
                    position: Int, continuationID: String, anchor: String,
                    createdAt: Date, nextInput: String? = nil,
                    prefixJSON: String? = nil) {
            self.id = id
            self.parentID = parentID
            self.modelIdentity = modelIdentity
            self.position = position
            self.continuationID = continuationID
            self.anchor = anchor
            self.createdAt = createdAt
            self.nextInput = nextInput
            self.prefixJSON = prefixJSON
        }
    }

    /// Upsert an execution state into the authoritative store. Used by the app to
    /// mirror its execution graph into SQLite and to satisfy settlement FKs.
    public func recordExecutionState(id: String, parentID: String?, modelIdentity: String,
                                     tokenizerIdentity: String? = nil,
                                     graphManaged: Bool = true,
                                     position: Int, continuationID: String, anchor: String,
                                     lifecycle: String, createdAt: Date) throws {
        try insertExecutionStateRow(
            id: id, parentID: parentID, modelIdentity: modelIdentity,
            tokenizerIdentity: tokenizerIdentity, graphManaged: graphManaged,
            position: position, continuationID: continuationID, anchor: anchor,
            lifecycle: lifecycle, createdAt: createdAt)
    }

    /// Caller owns the transaction. Shared by the standalone upsert and the
    /// atomic child-state + settlement commit, so a continuation can create its
    /// child ES and settle it as one authoritative unit.
    ///
    /// `tokenizerIdentity` is written only by the insert that creates the row;
    /// the conflict update leaves any existing value (including NULL) untouched.
    /// `checkpoint_ids_json` follows the same rule, but always serializes: a
    /// state this writer creates owns an explicit empty list, never SQL NULL, and
    /// an existing list is left to the graph writer that owns it.
    private func insertExecutionStateRow(id: String, parentID: String?, modelIdentity: String,
                                         tokenizerIdentity: String? = nil,
                                         graphManaged: Bool = true,
                                         position: Int, continuationID: String, anchor: String,
                                         lifecycle: String, createdAt: Date,
                                         nextInput: String? = nil,
                                         prefixJSON: String? = nil,
                                         checkpointIDsJSON: String? = nil,
                                         idempotencyKey: String? = nil) throws {
        try execBinding("""
        INSERT INTO execution_states(state_id, parent_id, model_identity, position, continuation_id, anchor, lifecycle, created_at, next_input, prefix_json, checkpoint_ids_json, idempotency_key, tokenizer_identity, graph_managed)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(state_id) DO UPDATE SET
            parent_id=excluded.parent_id, model_identity=excluded.model_identity, position=excluded.position,
            continuation_id=excluded.continuation_id, anchor=excluded.anchor, lifecycle=excluded.lifecycle,
            created_at=excluded.created_at,
            next_input=COALESCE(excluded.next_input, next_input),
            prefix_json=COALESCE(excluded.prefix_json, prefix_json),
            idempotency_key=COALESCE(excluded.idempotency_key, idempotency_key),
            graph_managed=excluded.graph_managed;
        """) { stmt in
            try bind(stmt, 1, id)
            try bind(stmt, 2, parentID)
            try bind(stmt, 3, modelIdentity)
            try bind(stmt, 4, Int64(position))
            try bind(stmt, 5, continuationID)
            try bind(stmt, 6, anchor)
            try bind(stmt, 7, lifecycle)
            try bind(stmt, 8, Self.stamp( createdAt))
            try bind(stmt, 9, nextInput)
            try bind(stmt, 10, prefixJSON ?? "[]")
            try bind(stmt, 11, checkpointIDsJSON ?? "[]")
            try bind(stmt, 12, idempotencyKey)
            try bind(stmt, 13, tokenizerIdentity)
            try bind(stmt, 14, Int64(graphManaged ? 1 : 0))
        }
    }

    // MARK: - Native-authorized settlement (write authority)

    /// Commit a native-authorized settlement into the authoritative store, together
    /// with one binding row per satisfied constraint. Callers must only pass a
    /// `SettledResult` produced by `SettlementAuthority` (the gate already
    /// ran); this performs no contract validation of its own.
    @discardableResult
    public func recordNativeSettlement(_ settled: SettlementAuthority.SettledResult, stateID: String?) throws -> String {
        let settlementID = UUID().uuidString
        try transaction {
            try insertNativeSettlementRows(settled, settlementID: settlementID, stateID: stateID)
        }
        return settlementID
    }

    /// Atomically mirror the current reference ES snapshot and commit its native
    /// settlement. This is deliberately separate from the identity-bearing
    /// continuation API: the reference UI path has no producer identity rows,
    /// but it must not publish a receipt if either the state upsert or settlement
    /// insertion fails.
    @discardableResult
    public func recordNativeSettlementWithExecutionState(
        _ settled: SettlementAuthority.SettledResult,
        state: GraphState
    ) throws -> UUID {
        let settlementID = UUID()
        let encoder = JSONEncoder()
        let prefixJSON = String(decoding: try encoder.encode(state.prefix), as: UTF8.self)
        let checkpointIDsJSON = String(
            decoding: try encoder.encode(state.checkpointIDs.map { $0.uuidString }),
            as: UTF8.self
        )
        try transaction {
            try insertExecutionStateRow(
                id: state.id,
                parentID: state.parentID,
                modelIdentity: state.modelIdentity,
                position: state.position,
                continuationID: state.continuationID,
                anchor: state.anchor,
                lifecycle: state.lifecycle,
                createdAt: state.createdAt,
                nextInput: state.nextInput,
                prefixJSON: prefixJSON,
                checkpointIDsJSON: checkpointIDsJSON
            )
            try insertNativeSettlementRows(
                settled,
                settlementID: settlementID.uuidString,
                stateID: state.id
            )
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
    public struct InformationAdvancementPlan: Sendable {
        public let demandID: String
        public let stateID: String
        public let retrievalSettlementID: String
        public let actions: [String]
        public let result: Data

        public init(demandID: String, stateID: String,
                    retrievalSettlementID: String, actions: [String],
                    result: Data) {
            self.demandID = demandID
            self.stateID = stateID
            self.retrievalSettlementID = retrievalSettlementID
            self.actions = actions
            self.result = result
        }
    }

    public struct SettlementWithAdvancement: Sendable {
        public let settlementID: UUID
        /// The execution state the settlement belongs to. On a reuse this is
        /// the state of the existing settlement, not the state the caller
        /// asked to settle.
        public let stateID: String
        public let advancementID: String?
        /// True when this call returned an already-recorded settlement. A reuse
        /// writes no state, settlement, object, index entry, or summary.
        public let reused: Bool
    }

    /// How a settlement write is identified across paths.
    ///
    /// A source identity is only usable when the producer declares all five
    /// fields: type, session, turn, message and revision. Naming some of them
    /// has not proven which source message the result belongs to, so the write
    /// is refused instead of merged by text. The operation key carries the same
    /// guarantee for one call whose source identity is unavailable.
    public struct SettlementSourceIdentity: Sendable, Equatable, Hashable {
        public let sourceType: String
        public let sourceSessionID: String
        public let sourceTurnID: String
        public let sourceMessageID: String
        public let revision: Int

        public init(sourceType: String, sourceSessionID: String,
                    sourceTurnID: String, sourceMessageID: String,
                    revision: Int) {
            self.sourceType = sourceType
            self.sourceSessionID = sourceSessionID
            self.sourceTurnID = sourceTurnID
            self.sourceMessageID = sourceMessageID
            self.revision = revision
        }
    }

    /// A raw declaration as it arrived on the wire. Fields are optional because
    /// "not declared" and "declared empty" must be distinguishable from a
    /// complete identity; `sourceRevision` stays text so a malformed revision
    /// is a refusal rather than a silently missing field.
    public struct DeclaredSourceIdentity: Sendable, Equatable {
        public let sourceType: String?
        public let sourceSessionID: String?
        public let sourceTurnID: String?
        public let sourceMessageID: String?
        public let sourceRevision: String?

        public init(sourceType: String? = nil, sourceSessionID: String? = nil,
                    sourceTurnID: String? = nil, sourceMessageID: String? = nil,
                    sourceRevision: String? = nil) {
            self.sourceType = sourceType
            self.sourceSessionID = sourceSessionID
            self.sourceTurnID = sourceTurnID
            self.sourceMessageID = sourceMessageID
            self.sourceRevision = sourceRevision
        }

        private static func cleaned(_ raw: String?) -> String? {
            guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty
            else { return nil }
            return value
        }

        /// True when nothing was declared: the write follows the ordinary path.
        public var isAbsent: Bool {
            Self.cleaned(sourceType) == nil && Self.cleaned(sourceSessionID) == nil
                && Self.cleaned(sourceTurnID) == nil
                && Self.cleaned(sourceMessageID) == nil
                && Self.cleaned(sourceRevision) == nil
        }

        /// A complete declaration, or a refusal. `nil` means no identity was
        /// declared at all (an absent declaration is not an error).
        public func normalized() throws -> SettlementSourceIdentity? {
            let type = Self.cleaned(sourceType)
            let session = Self.cleaned(sourceSessionID)
            let turn = Self.cleaned(sourceTurnID)
            let message = Self.cleaned(sourceMessageID)
            let revisionText = Self.cleaned(sourceRevision)
            guard type != nil || session != nil || turn != nil || message != nil
                || revisionText != nil
            else { return nil }
            var missing: [String] = []
            if type == nil { missing.append("source_type") }
            if session == nil { missing.append("source_session_id") }
            if turn == nil { missing.append("source_turn_id") }
            if message == nil { missing.append("source_message_id") }
            if revisionText == nil { missing.append("source_revision") }
            guard missing.isEmpty else {
                throw SettlementIdentityError.incompleteSourceIdentity(missing: missing)
            }
            guard let revision = Int(revisionText ?? ""), revision >= 1 else {
                throw SettlementIdentityError.invalidRevision(revisionText ?? "")
            }
            return SettlementSourceIdentity(
                sourceType: type ?? "", sourceSessionID: session ?? "",
                sourceTurnID: turn ?? "", sourceMessageID: message ?? "",
                revision: revision)
        }
    }

    /// Why a settlement write was refused at the identity layer. A refusal is
    /// atomic: the settlement, its constraints, identity bindings, declared
    /// dependencies and advancement all roll back together.
    public enum SettlementIdentityError: Error, Equatable, Sendable,
        CustomStringConvertible
    {
        case incompleteSourceIdentity(missing: [String])
        case invalidRevision(String)
        case identityConflict(String)
        case revisionConflict(String)
        case operationKeyConflict(String)
        case stateAlreadySettled(String)

        public var description: String {
            switch self {
            case .incompleteSourceIdentity(let missing):
                return "incomplete source identity declaration; missing: "
                    + missing.joined(separator: ", ")
            case .invalidRevision(let value):
                return "source_revision must be an integer >= 1, got '\(value)'"
            case .identityConflict(let detail):
                return "source identity conflict: \(detail)"
            case .revisionConflict(let detail):
                return "source revision conflict: \(detail)"
            case .operationKeyConflict(let detail):
                return "operation key conflict: \(detail)"
            case .stateAlreadySettled(let detail):
                return "execution state already settled: \(detail)"
            }
        }
    }

    /// A source the producer declares this result drew on. The address must
    /// already be a sealed carrier object, so a dependency can only cite content
    /// the carrier holds — never an arbitrary string.
    public struct DeclaredDependency: Sendable {
        public let dependencyID: String
        public let contentAddress: String
        public let reason: String

        public init(dependencyID: String, contentAddress: String, reason: String) {
            self.dependencyID = dependencyID
            self.contentAddress = contentAddress
            self.reason = reason
        }
    }

    /// A settled result that another settlement must remain valid with.
    /// Persisted as a dependency edge and content-address ledger entry in the
    /// same transaction as the consumer settlement.
    public struct SettlementDependency: Sendable, Equatable, Hashable {
        public let settlementID: String
        public let kind: String

        public init(settlementID: String, kind: String = "depends") {
            self.settlementID = settlementID
            self.kind = kind
        }
    }

    @discardableResult
    public func recordNativeSettlementWithIdentity(
        _ settled: SettlementAuthority.SettledResult,
        stateID: String,
        identity: SettlementIdentityBinding.Identity,
        childState: ChildExecutionState? = nil,
        kvRepresentation: SettlementKVBinding.Representation? = nil,
        inputSnapshotObjectID: String? = nil,
        settlementDependencies: [SettlementDependency] = []
    ) throws -> UUID {
        try recordNativeSettlementWithIdentityAndAdvancement(
            settled, stateID: stateID, identity: identity,
            childState: childState, advancement: nil,
            kvRepresentation: kvRepresentation,
            inputSnapshotObjectID: inputSnapshotObjectID,
            settlementDependencies: settlementDependencies
        ).settlementID
    }

    /// Atomic settlement + child state + identity bindings + advancement. The
    /// advancement is linked to the settlement row created in this transaction,
    /// so a downstream result can never claim an advancement it does not have.
    ///
    /// `kvRepresentation`, when present, is bound in the SAME transaction: a
    /// settlement can therefore never commit while claiming a prefix
    /// representation it did not also record. Only digests are stored.
    ///
    /// `sourceIdentity` and `operationKey` are the cross-path idempotency
    /// declarations. Resolution happens inside the same `BEGIN IMMEDIATE`
    /// transaction as the write, so two submissions of one declaration
    /// serialize: the second observes the first and returns it as `reused`.
    /// Only an exact same-source/same-revision/same-digest submission reuses;
    /// everything else is refused or becomes an explicitly declared new
    /// revision. A declaration never merges two submissions by text alone.
    @discardableResult
    public func recordNativeSettlementWithIdentityAndAdvancement(
        _ settled: SettlementAuthority.SettledResult,
        stateID: String,
        identity: SettlementIdentityBinding.Identity,
        childState: ChildExecutionState? = nil,
        advancement: InformationAdvancementPlan?,
        kvRepresentation: SettlementKVBinding.Representation? = nil,
        inputSnapshotObjectID: String? = nil,
        declaredDependencies: [DeclaredDependency] = [],
        settlementDependencies: [SettlementDependency] = [],
        sourceIdentity: DeclaredSourceIdentity? = nil,
        operationKey: String? = nil,
        chatTurn: ChatTurnCommit? = nil,
        chatSessionID: String? = nil,
        chatModelIdentity: String? = nil
    ) throws -> SettlementWithAdvancement {
        let declared = try sourceIdentity?.normalized()
        let key = Self.cleanedOperationKey(operationKey)
        let normalizedSettlementDependencies = Array(Set(settlementDependencies)).sorted {
            if $0.kind != $1.kind { return $0.kind < $1.kind }
            return $0.settlementID < $1.settlementID
        }
        let settlementUUID = UUID()
        let settlementID = settlementUUID.uuidString
        var advancementID: String?
        var reuse: StoredSettlementReuse?
        var predecessorSettlementID: String?
        try transaction {
            if declared != nil || key != nil {
                if let hit = try settlementReuse(
                    declared: declared, operationKey: key,
                    payloadDigest: settled.payloadDigest,
                    requestedStateID: stateID,
                    declaredDependencies: declaredDependencies,
                    settlementEdges: normalizedSettlementDependencies)
                {
                    reuse = hit
                    if let chatTurn { _ = try insertChatTurnRows(chatTurn) }
                    if let chatSessionID, let chatModelIdentity {
                        try insertChatSessionLink(
                            sessionID: chatSessionID, stateID: hit.stateID,
                            modelIdentity: chatModelIdentity)
                    }
                    return
                }
                if let declared {
                    predecessorSettlementID = try assertRevisionTransition(
                        declared, payloadDigest: settled.payloadDigest)
                }
                if let existing = try settlementForState(stateID) {
                    throw SettlementIdentityError.stateAlreadySettled(
                        "state \(stateID) already carries settlement \(existing)")
                }
            }
            // Validate every upstream settlement while this BEGIN IMMEDIATE
            // writer lock is held. If its source invalidation commits first, the
            // child is refused; if it commits later, the edge below makes the
            // invalidation cascade to this child.
            var settlementDependencyObjectIDs: [SettlementDependency: String] = [:]
            for dependency in normalizedSettlementDependencies {
                guard dependency.settlementID != settlementID,
                      !dependency.settlementID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !dependency.kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw DatabaseError.sql("settlement dependency requires a distinct settlement id and kind")
                }
                settlementDependencyObjectIDs[dependency] =
                    try validatedSettlementDependencyObjectID(dependency.settlementID)
            }
            // The conversation row and its standing share the settlement transaction.
            if let chatTurn { _ = try insertChatTurnRows(chatTurn) }
            if let childState {
                try insertExecutionStateRow(
                    id: childState.id, parentID: childState.parentID,
                    modelIdentity: childState.modelIdentity, position: childState.position,
                    continuationID: childState.continuationID, anchor: childState.anchor,
                    lifecycle: "active", createdAt: childState.createdAt,
                    nextInput: childState.nextInput, prefixJSON: childState.prefixJSON)
            }
            try insertNativeSettlementRows(
                settled, settlementID: settlementID, stateID: stateID,
                inputSnapshotObjectID: inputSnapshotObjectID)
            try insertIdentityBindingRows(
                settlementID: settlementID, identity: identity)
            if let kvRepresentation {
                try insertDerivedBindingRows(
                    settlementID: settlementID,
                    rows: SettlementKVBinding.bindings(for: kvRepresentation))
            }
            // Declared sources commit with the result: a settlement can never
            // become authoritative while silently dropping a source it claims,
            // and a dependency that cannot be recorded rolls the settle back.
            for dependency in declaredDependencies {
                try appendDependencyInTransaction(
                    dependencyID: Self.settlementDependencyID(
                        settlementID: settlementID, dependencyID: dependency.dependencyID),
                    contentAddress: dependency.contentAddress,
                    reason: dependency.reason)
            }
            for dependency in normalizedSettlementDependencies {
                try execBinding("""
                INSERT INTO dependency_edges(from_settlement, to_settlement, kind)
                SELECT ?,?,?
                WHERE NOT EXISTS (
                    SELECT 1 FROM dependency_edges
                    WHERE from_settlement=? AND to_settlement=? AND kind=?);
                """) { stmt in
                    try bind(stmt, 1, settlementID)
                    try bind(stmt, 2, dependency.settlementID)
                    try bind(stmt, 3, dependency.kind)
                    try bind(stmt, 4, settlementID)
                    try bind(stmt, 5, dependency.settlementID)
                    try bind(stmt, 6, dependency.kind)
                }
                guard let address = settlementDependencyObjectIDs[dependency] else {
                    throw DatabaseError.sql(
                        "settlement dependency object address missing for \(dependency.settlementID)")
                }
                _ = try appendDependencyInTransaction(
                    dependencyID: "settlement:\(settlementID) -> settlement:\(dependency.settlementID)",
                    contentAddress: address,
                    reason: dependency.kind)
            }
            if let advancement {
                advancementID = try insertInformationAdvancementRows(.init(
                    demandID: advancement.demandID, stateID: advancement.stateID,
                    settlementID: settlementID,
                    retrievalSettlementID: advancement.retrievalSettlementID,
                    actions: advancement.actions, result: advancement.result))
            }
            if let declared {
                try insertSourceIdentityRow(
                    declared, payloadDigest: settled.payloadDigest,
                    settlementID: settlementID,
                    previousSettlementID: predecessorSettlementID)
            }
            if let key {
                try insertOperationKeyRow(
                    key, payloadDigest: settled.payloadDigest,
                    settlementID: settlementID)
            }
            if let chatSessionID, let chatModelIdentity {
                try insertChatSessionLink(
                    sessionID: chatSessionID, stateID: stateID,
                    modelIdentity: chatModelIdentity)
            }
        }
        if let reuse {
            return SettlementWithAdvancement(
                settlementID: reuse.settlementID, stateID: reuse.stateID,
                advancementID: reuse.advancementID, reused: true)
        }
        return SettlementWithAdvancement(
            settlementID: settlementUUID, stateID: stateID,
            advancementID: advancementID, reused: false)
    }

    // MARK: - Source identity resolution (v17)

    private struct StoredSettlementReuse {
        let settlementID: UUID
        let stateID: String
        let advancementID: String?
    }

    private struct StoredSourceIdentityRow {
        let settlementID: String
        let payloadDigest: String
        let revision: Int
        let previousSettlementID: String?
    }

    static func cleanedOperationKey(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return nil }
        return value
    }

    private static func sourceLabel(_ identity: SettlementSourceIdentity) -> String {
        "\(identity.sourceType)/\(identity.sourceSessionID)"
            + "/\(identity.sourceTurnID)/\(identity.sourceMessageID)"
    }

    /// Resolve a declared submission against what the carrier already holds.
    /// Returns a hit only for an exact identity (and, when present, operation
    /// key) match with the same payload digest; every other overlap throws.
    /// Caller owns the transaction, so the read and the later insert cannot be
    /// interleaved with a competing submission on another connection.
    private func settlementReuse(
        declared: SettlementSourceIdentity?,
        operationKey: String?,
        payloadDigest: String,
        requestedStateID: String,
        declaredDependencies: [DeclaredDependency],
        settlementEdges: [SettlementDependency]
    ) throws -> StoredSettlementReuse? {
        var identityHit: StoredSourceIdentityRow?
        if let declared, let stored = try storedSourceIdentity(declared) {
            guard stored.payloadDigest == payloadDigest else {
                throw SettlementIdentityError.identityConflict(
                    "source \(Self.sourceLabel(declared)) revision \(declared.revision) "
                        + "already carries a different payload digest")
            }
            identityHit = stored
        }
        if let operationKey, let stored = try storedOperationKey(operationKey) {
            guard stored.payloadDigest == payloadDigest else {
                throw SettlementIdentityError.operationKeyConflict(
                    "operation key '\(operationKey)' already carries a different payload digest")
            }
            if let identityHit, identityHit.settlementID != stored.settlementID {
                throw SettlementIdentityError.operationKeyConflict(
                    "operation key '\(operationKey)' settled a different submission "
                        + "than the declared source identity")
            }
            if declared != nil, identityHit == nil {
                // The key settled a submission that declared no source; attaching
                // this declaration afterwards would merge two distinct sources.
                throw SettlementIdentityError.operationKeyConflict(
                    "operation key '\(operationKey)' was settled without the declared source identity")
            }
            return try settlementReuseOf(
                settlementID: stored.settlementID,
                requestedStateID: requestedStateID,
                declaredDependencies: declaredDependencies,
                settlementEdges: settlementEdges)
        }
        if let identityHit {
            let hit = try settlementReuseOf(
                settlementID: identityHit.settlementID,
                requestedStateID: requestedStateID,
                declaredDependencies: declaredDependencies,
                settlementEdges: settlementEdges)
            if let operationKey {
                // The identity is the authority; the key only makes this call
                // replayable. It is bound to the identity's settlement, never
                // to a new one.
                try insertOperationKeyRow(
                    operationKey, payloadDigest: payloadDigest,
                    settlementID: identityHit.settlementID)
            }
            return hit
        }
        return nil
    }

    private func settlementReuseOf(
        settlementID: String,
        requestedStateID: String,
        declaredDependencies: [DeclaredDependency],
        settlementEdges: [SettlementDependency]
    ) throws -> StoredSettlementReuse {
        guard let uuid = UUID(uuidString: settlementID) else {
            throw DatabaseError.sql("stored settlement id is not a UUID: \(settlementID)")
        }
        if !declaredDependencies.isEmpty {
            let recorded = try settlementDependencies(settlementID: settlementID)
            for dependency in declaredDependencies {
                let expectedID = Self.settlementDependencyID(
                    settlementID: settlementID, dependencyID: dependency.dependencyID)
                let address = recorded.last { $0.dependencyID == expectedID }?.contentAddress
                guard address == dependency.contentAddress else {
                    throw SettlementIdentityError.identityConflict(
                        "reused settlement does not carry declared dependency "
                            + "'\(dependency.dependencyID)'")
                }
            }
        }
        for dependency in settlementEdges {
            let stmt = try prepare("""
            SELECT 1 FROM dependency_edges
            WHERE from_settlement=? AND to_settlement=? AND kind=? LIMIT 1;
            """)
            defer { sqlite3_finalize(stmt) }
            try bind(stmt, 1, settlementID)
            try bind(stmt, 2, dependency.settlementID)
            try bind(stmt, 3, dependency.kind)
            guard try stepRowOrDone(stmt) else {
                throw SettlementIdentityError.identityConflict(
                    "reused settlement does not carry settlement dependency "
                        + "\(dependency.settlementID) (\(dependency.kind))")
            }
        }
        return StoredSettlementReuse(
            settlementID: uuid,
            stateID: try settlementStateID(settlementID) ?? requestedStateID,
            advancementID: try latestAdvancementID(settlementID: settlementID))
    }

    /// Enforce explicit version transitions: the first declared revision is 1,
    /// every later one is exactly the next revision of the same source, and a
    /// new revision must carry new content. A retry can never be mistaken for
    /// an update, and a version can never be skipped or overwritten.
    private func assertRevisionTransition(
        _ identity: SettlementSourceIdentity, payloadDigest: String
    ) throws -> String? {
        let newest = try newestSourceRevision(identity)
        let label = Self.sourceLabel(identity)
        guard let newest else {
            guard identity.revision == 1 else {
                throw SettlementIdentityError.revisionConflict(
                    "source \(label) has no settled predecessor; the first declared revision is 1, got \(identity.revision)")
            }
            return nil
        }
        guard identity.revision == newest.revision + 1 else {
            throw SettlementIdentityError.revisionConflict(
                "source \(label) is settled at revision \(newest.revision); "
                    + "the next declared revision is \(newest.revision + 1), got \(identity.revision)")
        }
        guard newest.payloadDigest != payloadDigest else {
            throw SettlementIdentityError.revisionConflict(
                "source \(label) revision \(identity.revision) repeats the content of "
                    + "revision \(newest.revision); a new version must change the result")
        }
        return newest.settlementID
    }

    private func storedSourceIdentity(
        _ identity: SettlementSourceIdentity
    ) throws -> StoredSourceIdentityRow? {
        let stmt = try prepare("""
        SELECT settlement_id, payload_digest, source_revision, previous_settlement_id
        FROM settlement_source_identities
        WHERE source_type=? AND source_session_id=? AND source_turn_id=?
          AND source_message_id=? AND source_revision=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, identity.sourceType)
        try bind(stmt, 2, identity.sourceSessionID)
        try bind(stmt, 3, identity.sourceTurnID)
        try bind(stmt, 4, identity.sourceMessageID)
        try bind(stmt, 5, Int64(identity.revision))
        guard try stepRowOrDone(stmt) else { return nil }
        return StoredSourceIdentityRow(
            settlementID: sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "",
            payloadDigest: sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "",
            revision: Int(sqlite3_column_int64(stmt, 2)),
            previousSettlementID: sqlite3_column_text(stmt, 3).map { String(cString: $0) })
    }

    private func newestSourceRevision(
        _ identity: SettlementSourceIdentity
    ) throws -> StoredSourceIdentityRow? {
        let stmt = try prepare("""
        SELECT settlement_id, payload_digest, source_revision, previous_settlement_id
        FROM settlement_source_identities
        WHERE source_type=? AND source_session_id=? AND source_turn_id=?
          AND source_message_id=?
        ORDER BY source_revision DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, identity.sourceType)
        try bind(stmt, 2, identity.sourceSessionID)
        try bind(stmt, 3, identity.sourceTurnID)
        try bind(stmt, 4, identity.sourceMessageID)
        guard try stepRowOrDone(stmt) else { return nil }
        return StoredSourceIdentityRow(
            settlementID: sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "",
            payloadDigest: sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "",
            revision: Int(sqlite3_column_int64(stmt, 2)),
            previousSettlementID: sqlite3_column_text(stmt, 3).map { String(cString: $0) })
    }

    private func storedOperationKey(
        _ key: String
    ) throws -> (payloadDigest: String, settlementID: String)? {
        let stmt = try prepare("""
        SELECT payload_digest, settlement_id FROM settlement_operation_keys
        WHERE operation_key=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, key)
        guard try stepRowOrDone(stmt) else { return nil }
        return (
            sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "",
            sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "")
    }

    /// Caller owns the transaction.
    private func insertSourceIdentityRow(
        _ identity: SettlementSourceIdentity,
        payloadDigest: String,
        settlementID: String,
        previousSettlementID: String?
    ) throws {
        try execBinding("""
        INSERT INTO settlement_source_identities(
            identity_id, source_type, source_session_id, source_turn_id,
            source_message_id, source_revision, payload_digest, settlement_id,
            previous_settlement_id, created_at)
        VALUES(?,?,?,?,?,?,?,?,?,?);
        """) { stmt in
            try bind(stmt, 1, UUID().uuidString)
            try bind(stmt, 2, identity.sourceType)
            try bind(stmt, 3, identity.sourceSessionID)
            try bind(stmt, 4, identity.sourceTurnID)
            try bind(stmt, 5, identity.sourceMessageID)
            try bind(stmt, 6, Int64(identity.revision))
            try bind(stmt, 7, payloadDigest)
            try bind(stmt, 8, settlementID)
            try bind(stmt, 9, previousSettlementID)
            try bind(stmt, 10, Self.stamp(Date()))
        }
    }

    /// Caller owns the transaction.
    private func insertOperationKeyRow(
        _ key: String, payloadDigest: String, settlementID: String
    ) throws {
        try execBinding("""
        INSERT INTO settlement_operation_keys(
            operation_key, payload_digest, settlement_id, created_at)
        VALUES(?,?,?,?);
        """) { stmt in
            try bind(stmt, 1, key)
            try bind(stmt, 2, payloadDigest)
            try bind(stmt, 3, settlementID)
            try bind(stmt, 4, Self.stamp(Date()))
        }
    }

    private func settlementStateID(_ settlementID: String) throws -> String? {
        let stmt = try prepare("SELECT state_id FROM settlements WHERE settlement_id=?;")
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, settlementID)
        guard try stepRowOrDone(stmt) else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    private func settlementForState(_ stateID: String) throws -> String? {
        let stmt = try prepare("""
        SELECT settlement_id FROM settlements
        WHERE state_id=? AND state_id IS NOT NULL LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, stateID)
        guard try stepRowOrDone(stmt) else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    private func latestAdvancementID(settlementID: String) throws -> String? {
        let stmt = try prepare("""
        SELECT advancement_id FROM information_advancements
        WHERE settlement_id=?
        ORDER BY advanced_at DESC, rowid DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, settlementID)
        guard try stepRowOrDone(stmt) else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    static func settlementDependencyID(
        settlementID: String, dependencyID: String
    ) -> String {
        "settlement:\(settlementID) -> \(dependencyID)"
    }

    /// Insert the settlement row and the native gate's constraint-binding rows.
    /// Caller owns the transaction so this can participate in the atomic identity
    /// commit without opening a nested transaction.
    private func insertNativeSettlementRows(
        _ settled: SettlementAuthority.SettledResult,
        settlementID: String,
        stateID: String?,
        validationStatusOverride: String? = nil,
        inputSnapshotObjectID: String? = nil
    ) throws {
        let payloadObject = try ensureObject(settled.validatedPayload)
        if let inputSnapshotObjectID {
            // The referenced object must already exist in this transaction
            // (the FK enforces it); a settlement never references a snapshot it
            // did not also write before commit.
            guard try objectRow(inputSnapshotObjectID) != nil else {
                throw DatabaseError.sql("input snapshot object missing: \(inputSnapshotObjectID)")
            }
        }
        try execBinding("""
        INSERT INTO settlements(settlement_id, state_id, schema_version, payload, payload_digest, signature, contract_version, settled_at, validation_status, payload_object_id, input_snapshot_object_id, result_contract_id, result_contract_digest)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?);
        """) { stmt in
            try bind(stmt, 1, settlementID)
            try bind(stmt, 2, stateID)
            try bind(stmt, 3, settled.schemaVersion)
            try bind(stmt, 4, Data())
            try bind(stmt, 5, settled.payloadDigest)
            try bind(stmt, 6, String?.none)
            try bind(stmt, 7, NativeResultContract.supportedVersion)
            try bind(stmt, 8, Self.stamp(settled.settledAt))
            try bind(stmt, 9, validationStatusOverride ?? settled.trace.validationStatus)
            try bind(stmt, 10, payloadObject)
            try bind(stmt, 11, inputSnapshotObjectID)
            try bind(stmt, 12, settled.contractID)
            try bind(stmt, 13, settled.contractDigest)
        }
        try recordSettlementValidityEventInTransaction(
            settlementID: settlementID, validity: "valid", cause: nil,
            at: Self.stamp(settled.settledAt))
        _ = try appendIndexEntryInTransaction(
            identity: "settlement:\(settlementID)", objectID: payloadObject)
        for ct in settled.trace.constraintChecks {
            try execBinding("INSERT INTO settlement_bindings(settlement_id, name, value_digest, source_root_id, source_file_id) VALUES(?,?,?,?,?);") { stmt in
                try bind(stmt, 1, settlementID)
                try bind(stmt, 2, ct.binding ?? ct.field)
                try bind(stmt, 3, ct.kind)
                try bind(stmt, 4, String?.none)
                try bind(stmt, 5, nil as Int64?)
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
        identity: SettlementIdentityBinding.Identity,
        kvRepresentation: SettlementKVBinding.Representation? = nil
    ) throws {
        try transaction {
            try insertIdentityBindingRows(settlementID: settlementID, identity: identity)
            if let kvRepresentation {
                try insertDerivedBindingRows(
                    settlementID: settlementID,
                    rows: SettlementKVBinding.bindings(for: kvRepresentation))
            }
        }
    }

    /// Caller owns the transaction. This helper is shared by the legacy binding
    /// update and the atomic settlement+identity commit.
    private func insertIdentityBindingRows(
        settlementID: String,
        identity: SettlementIdentityBinding.Identity
    ) throws {
        try insertDerivedBindingRows(
            settlementID: settlementID,
            rows: SettlementIdentityBinding.bindings(for: identity))
    }

    /// Persist derived (producer-written) binding digests for one settlement,
    /// replacing any previous row with the same name. Shared by the producer
    /// identity binding and the prefix-representation binding so both use the
    /// same idempotent replace and the same digest-only storage rule.
    ///
    /// Names are the producer's own namespace keys (`producer.*`, `kv.*`); a
    /// name collision with a native gate constraint row would replace it, which
    /// is the same pre-existing tradeoff the identity binding already makes.
    private func insertDerivedBindingRows(
        settlementID: String,
        rows: [String: String]
    ) throws {
        for name in rows.keys.sorted() {
            guard let digest = rows[name] else { continue }
            try execBinding("DELETE FROM settlement_bindings WHERE settlement_id=? AND name=?;") { stmt in
                try bind(stmt, 1, settlementID)
                try bind(stmt, 2, name)
            }
            try execBinding("""
            INSERT INTO settlement_bindings(settlement_id, name, value_digest, source_root_id, source_file_id)
            VALUES(?,?,?,?,?);
            """) { stmt in
                try bind(stmt, 1, settlementID)
                try bind(stmt, 2, name)
                try bind(stmt, 3, digest)
                try bind(stmt, 4, String?.none)
                try bind(stmt, 5, nil as Int64?)
            }
        }
    }

    // MARK: - As-of snapshot reference (v12)

    /// The immutable `final` snapshot object this settlement committed with, or
    /// nil when the row predates snapshot capture. The value is never backfilled,
    /// so an absent reference is reported as absent rather than synthesized.
    public func settlementInputSnapshotObjectID(settlementID: String) throws -> String? {
        let stmt = try prepare("SELECT input_snapshot_object_id FROM settlements WHERE settlement_id=?;")
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, settlementID)
        guard try stepRowOrDone(stmt) else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    // MARK: - Managed continuation (v13)

    /// Payload digest of a settlement row, or nil when the row does not exist.
    public func settlementPayloadDigest(_ settlementID: String) throws -> String? {
        let stmt = try prepare("SELECT payload_digest FROM settlements WHERE settlement_id=?;")
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, settlementID)
        guard try stepRowOrDone(stmt) else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    /// The idempotency key an execution state was committed under, if any.
    public func executionStateIdempotencyKey(_ stateID: String) throws -> String? {
        let stmt = try prepare("SELECT idempotency_key FROM execution_states WHERE state_id=?;")
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, stateID)
        guard try stepRowOrDone(stmt) else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    /// The execution state that already committed this idempotency key.
    public func executionStateID(idempotencyKey: String) throws -> String? {
        let stmt = try prepare("SELECT state_id FROM execution_states WHERE idempotency_key=?;")
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, idempotencyKey)
        guard try stepRowOrDone(stmt) else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    /// Everything P2 writes for one managed continuation, committed as a single
    /// unit: the `final` snapshot object, the child execution state carrying the
    /// idempotency key, the settlement that references that snapshot, and the
    /// producer identity bindings.
    ///
    /// `preCommit` runs FIRST, while the write lock is held, and is where the
    /// caller re-verifies the pinned anchor, the dependency closure and the
    /// captured inputs. Throwing from it rolls everything back, so a recheck
    /// failure can never leave a partial settlement behind.
    public struct ManagedContinuationPlan {
        public let executionID: String
        public let attempt: Int
        public let idempotencyKey: String
        public let fingerprint: String
        public let finalSnapshot: Data
        public let settled: SettlementAuthority.SettledResult
        public let identity: SettlementIdentityBinding.Identity
        public let childState: ChildExecutionState
        public let preCommit: () throws -> Void

        public init(
            executionID: String, attempt: Int, idempotencyKey: String,
            fingerprint: String, finalSnapshot: Data,
            settled: SettlementAuthority.SettledResult,
            identity: SettlementIdentityBinding.Identity,
            childState: ChildExecutionState,
            preCommit: @escaping () throws -> Void
        ) {
            self.executionID = executionID
            self.attempt = attempt
            self.idempotencyKey = idempotencyKey
            self.fingerprint = fingerprint
            self.finalSnapshot = finalSnapshot
            self.settled = settled
            self.identity = identity
            self.childState = childState
            self.preCommit = preCommit
        }
    }

    public struct ManagedContinuationCommit {
        public let finalSnapshotObjectID: String
        public let settlementID: String
        public let executionID: String
    }

    public func commitManagedContinuation(
        _ plan: ManagedContinuationPlan
    ) throws -> ManagedContinuationCommit {
        try transactionResult {
            try plan.preCommit()
            if let owner = try executionStateID(idempotencyKey: plan.idempotencyKey),
               owner != plan.childState.id {
                throw ManagedRefusal.Refusal(
                    cause: .idempotencyConflict, origin: .idempotency, phase: .p2,
                    evidence: [
                        "execution_id": plan.executionID,
                        "fingerprint": plan.fingerprint,
                        "existing_state_id": owner,
                    ])
            }
            let finalObjectID = try ensureObject(plan.finalSnapshot)
            try insertExecutionStateRow(
                id: plan.childState.id, parentID: plan.childState.parentID,
                modelIdentity: plan.childState.modelIdentity,
                position: plan.childState.position,
                continuationID: plan.childState.continuationID,
                anchor: plan.childState.anchor, lifecycle: "active",
                createdAt: plan.childState.createdAt,
                nextInput: plan.childState.nextInput,
                prefixJSON: plan.childState.prefixJSON,
                idempotencyKey: plan.idempotencyKey)
            let settlementID = UUID().uuidString
            try insertNativeSettlementRows(
                plan.settled, settlementID: settlementID, stateID: plan.childState.id,
                inputSnapshotObjectID: finalObjectID)
            try insertIdentityBindingRows(settlementID: settlementID, identity: plan.identity)
            return ManagedContinuationCommit(
                finalSnapshotObjectID: finalObjectID,
                settlementID: settlementID,
                executionID: plan.executionID)
        }
    }

    /// Binding rows recorded for one settlement, as name -> digest. Constraint
    /// bindings from the native gate live in the same table, so callers must look
    /// up the `producer.` keys rather than assume the dictionary is exhaustive.
    public func settlementBindings(settlementID: String) throws -> [String: String] {        let stmt = try prepare("""
        SELECT name, value_digest FROM settlement_bindings WHERE settlement_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, settlementID)
        var out: [String: String] = [:]
        while try stepRowOrDone(stmt) {
            let name = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let value = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            if !name.isEmpty { out[name] = value }
        }
        return out
    }

    /// Newest settlement recorded for a state, or nil when the state never settled.
    ///
    /// This is a recency pointer inside ONE state's own lifecycle. It never
    /// ranks two settlements of the same question against each other: those
    /// live under different states and different settlement ids, and retrieval
    /// (`citableSettlementSummaries`) returns all of them. The IS holds both;
    /// it does not pick which one is right.
    public func latestSettlementID(forStateID stateID: String) throws -> String? {
        let stmt = try prepare("""
        SELECT settlement_id FROM settlements WHERE state_id=?
        ORDER BY settled_at DESC, settlement_id DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, stateID)
        if try stepRowOrDone(stmt), let c = sqlite3_column_text(stmt, 0) {
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
            try bind(stmt, 1, rootID)
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
        while try stepRowOrDone(stmt) {
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

    public struct RootLocatorSnapshot: Equatable, Sendable {
        public let path: String
        public let device: Int64
        public let inode: UInt64
    }

    public struct RootFileSnapshot: Equatable, Sendable {
        public let relativePath: String
        public let data: Data
        public let size: Int64
        public let modificationDate: Date?
        public let statIdentity: SnapshotContract.StatIdentity
    }

    /// Read-only root identity check for callers that must not bypass the
    /// explicit adoption path. A registered non-zero inode must still match.
    /// Roots on filesystems reporting inode 0 have no persistent inode identity,
    /// but the returned device/inode pair still pins this individual capture.
    public func rootLocatorSnapshot(rootID: String) throws -> RootLocatorSnapshot {
        guard let registeredPath = try rootLocatorPath(rootID) else {
            throw DatabaseError.sql("rootLocatorSnapshot: no path locator for \(rootID)")
        }
        let canonicalPath = try canonicalDirectoryPath(atPath: registeredPath)
        var info = stat()
        let result = canonicalPath.withCString { Darwin.lstat($0, &info) }
        guard result == 0, (info.st_mode & S_IFMT) == S_IFDIR else {
            let code = errno
            throw DatabaseError.sql(
                "rootLocatorSnapshot: cannot inspect directory: \(String(cString: strerror(code)))")
        }

        let stmt = try prepare("""
        SELECT locator_inode FROM roots WHERE root_id=? AND locator_type='path';
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, rootID)
        guard try stepRowOrDone(stmt) else {
            throw DatabaseError.sql("rootLocatorSnapshot: unknown root \(rootID)")
        }
        let registeredInode: Int64? = sqlite3_column_type(stmt, 0) == SQLITE_NULL
            ? nil : sqlite3_column_int64(stmt, 0)
        let currentInode = Int64(info.st_ino)
        if let registeredInode {
            guard currentInode != 0, registeredInode == currentInode else {
                throw DatabaseError.sql(
                    "rootLocatorSnapshot: root identity changed; explicit adoption is required")
            }
        } else if currentInode != 0 {
            throw DatabaseError.sql(
                "rootLocatorSnapshot: root identity is not established; settle or adopt it first")
        }

        return RootLocatorSnapshot(
            path: canonicalPath, device: Int64(info.st_dev), inode: UInt64(info.st_ino))
    }

    /// Read a bounded set of regular files through a pinned root descriptor.
    /// The expected snapshot is captured before path enumeration; both the
    /// opened descriptor and the path at the end must still identify that root.
    public func captureRootFiles(
        rootID: String,
        expected: RootLocatorSnapshot,
        relativePaths: [String],
        maximumFiles: Int,
        maximumBytesPerFile: Int,
        maximumTotalBytesRead: Int
    ) throws -> [RootFileSnapshot] {
        guard maximumFiles >= 0, maximumBytesPerFile >= 0,
              maximumTotalBytesRead >= 0 else {
            throw DatabaseError.sql("captureRootFiles: negative resource limit")
        }
        guard relativePaths.count <= maximumFiles else {
            throw DatabaseError.sql("captureRootFiles: maximum file count exceeded")
        }
        guard Set(relativePaths).count == relativePaths.count else {
            throw DatabaseError.sql("captureRootFiles: duplicate relative path")
        }
        let current = try rootLocatorSnapshot(rootID: rootID)
        guard current == expected else {
            throw DatabaseError.sql("captureRootFiles: root changed during enumeration")
        }

        let rootFD = try openDirectoryNoFollow(atPath: expected.path)
        defer { Darwin.close(rootFD) }
        var openedInfo = stat()
        guard Darwin.fstat(rootFD, &openedInfo) == 0,
              Int64(openedInfo.st_dev) == expected.device,
              UInt64(openedInfo.st_ino) == expected.inode else {
            throw DatabaseError.sql("captureRootFiles: opened root differs from captured identity")
        }

        var totalBytesRead = 0
        var snapshots: [RootFileSnapshot] = []
        snapshots.reserveCapacity(relativePaths.count)
        for relativePath in relativePaths.sorted() {
            try Task.checkCancellation()
            let remaining = maximumTotalBytesRead - totalBytesRead
            let read = try readRootFileNoFollow(
                rootDirectoryFD: rootFD,
                relativePath: relativePath,
                maximumBytes: maximumBytesPerFile,
                maximumTotalBytesRead: remaining)
            guard let data = read.data else {
                // A file larger than the per-file policy is deliberately not
                // embedded, matching the IS scanner's text-capture policy.
                continue
            }
            guard data.count <= remaining else {
                throw DatabaseError.sql("captureRootFiles: aggregate byte budget exceeded")
            }
            totalBytesRead += data.count
            snapshots.append(RootFileSnapshot(
                relativePath: relativePath, data: data, size: read.size,
                modificationDate: read.modificationDate,
                statIdentity: SnapshotContract.StatIdentity(
                    device: String(read.device),
                    inode: String(read.inode),
                    modificationNanoseconds: String(read.modificationNanoseconds))))
        }
        try verifyRootDescriptorStillNamed(rootFD, path: expected.path)
        return snapshots
    }

    // MARK: - Spaces（归集键：只缩范围，不参与任何身份计算）

    public struct SpaceRow: Equatable, Sendable {
        public let spaceID: String
        public let title: String
        public let titleSource: String
        public let kind: String
        public let parentSpaceID: String?
        public let createdAt: String
    }

    private static let spaceColumns =
        "space_id, title, title_source, kind, parent_space_id, created_at"

    private func spaceRow(_ stmt: OpaquePointer) -> SpaceRow {
        func text(_ i: Int32) -> String {
            sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
        }
        return SpaceRow(
            spaceID: text(0), title: text(1), titleSource: text(2), kind: text(3),
            parentSpaceID: sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : text(4),
            createdAt: text(5))
    }

    /// 建一个空间。`title` 就是身份，`titleSource` 记它是怎么来的：
    /// 文件夹名占位（'filename'）、文内标题（'document'）、人写的（'human'）。
    @discardableResult
    public func createSpace(
        title: String, kind: String = "collection", titleSource: String = "human",
        parentSpaceID: String? = nil
    ) throws -> SpaceRow {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw DatabaseError.sql("createSpace: empty title")
        }
        let spaceID = "space-" + UUID().uuidString.lowercased()
        try execBinding("""
        INSERT INTO spaces(space_id, title, title_source, kind, parent_space_id, created_at)
        VALUES(?,?,?,?,?,?);
        """) { stmt in
            try bind(stmt, 1, spaceID)
            try bind(stmt, 2, name)
            try bind(stmt, 3, titleSource)
            try bind(stmt, 4, kind)
            try bind(stmt, 5, parentSpaceID)
            try bind(stmt, 6, Self.stamp(Date()))
        }
        guard let row = try space(id: spaceID) else {
            throw DatabaseError.sql("createSpace: row missing after write")
        }
        return row
    }

    public func space(id spaceID: String) throws -> SpaceRow? {
        let stmt = try prepare("SELECT \(Self.spaceColumns) FROM spaces WHERE space_id=?;")
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, spaceID)
        guard try stepRowOrDone(stmt) else { return nil }
        return spaceRow(stmt)
    }

    /// 一个 root 今天挂在哪个空间下。
    public func space(forRoot rootID: String) throws -> SpaceRow? {
        let stmt = try prepare("""
        SELECT s.space_id, s.title, s.title_source, s.kind,
               s.parent_space_id, s.created_at
          FROM roots r JOIN spaces s ON s.space_id = r.space_id
         WHERE r.root_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, rootID)
        guard try stepRowOrDone(stmt) else { return nil }
        return spaceRow(stmt)
    }

    /// 把 root 挂到空间下。人确认「这是搬家」时用它——同一个空间换一个新
    /// 目录，身份、标题、历史都留在原处。
    public func setRootSpace(rootID: String, spaceID: String?) throws {
        let changed = try execBinding("UPDATE roots SET space_id=? WHERE root_id=?;") { stmt in
            try bind(stmt, 1, spaceID)
            try bind(stmt, 2, rootID)
        }
        guard changed == 1 else {
            throw DatabaseError.sql("setRootSpace: no root \(rootID)")
        }
    }

    public func listSpaces() throws -> [SpaceRow] {
        let stmt = try prepare(
            "SELECT \(Self.spaceColumns) FROM spaces ORDER BY title, space_id;")
        defer { sqlite3_finalize(stmt) }
        var rows: [SpaceRow] = []
        while try stepRowOrDone(stmt) { rows.append(spaceRow(stmt)) }
        return rows
    }

    // MARK: - 房间维护（人工操作）

    /// 一个房间今天挂着什么：外部目录、轮次归属、会话归属。
    /// 删除前先看这张账——房间是「归属」，不是内容，所以删房间绝不连带删内容。
    public struct SpaceOccupancy: Equatable, Sendable {
        public let roots: Int
        public let turns: Int
        public let sessions: Int
        public var total: Int { roots + turns + sessions }
    }

    public func spaceOccupancy(_ spaceID: String) throws -> SpaceOccupancy {
        func count(_ sql: String) throws -> Int {
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            try bind(stmt, 1, spaceID)
            guard try stepRowOrDone(stmt) else {
                throw DatabaseError.sql("spaceOccupancy: SELECT COUNT(*) returned no row")
            }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        // `space_turns` 不是本模块建的表——它由 tools/assign_turn_spaces.py
        // 维护。没跑过那个工具的新库上这张表不存在，此时「轮次归属」这本账
        // 就是 0，不能因此让读状态或删空房间失败。
        let hasTurnLedger = try tableExists("space_turns")
        return SpaceOccupancy(
            roots: try count("SELECT COUNT(*) FROM roots WHERE space_id=?;"),
            turns: hasTurnLedger
                ? try count("SELECT COUNT(*) FROM space_turns WHERE space_id=?;") : 0,
            sessions: try count("SELECT COUNT(*) FROM agent_sessions WHERE space_id=?;"))
    }

    /// 只删空房间。非空时抛错并带上占用数——界面据此说清「为什么删不了」。
    /// 不做级联：把「删房间」解释成「删内容」是一次不可逆的语义跳跃。
    public func deleteEmptySpace(_ spaceID: String) throws {
        try transaction {
            let occupancy = try spaceOccupancy(spaceID)
            guard occupancy.total == 0 else {
                throw DatabaseError.sql(
                    "deleteEmptySpace: \(spaceID) still holds roots=\(occupancy.roots) "
                        + "turns=\(occupancy.turns) sessions=\(occupancy.sessions)")
            }
            let changed = try execBinding("DELETE FROM spaces WHERE space_id=?;") {
                try bind($0, 1, spaceID)
            }
            guard changed == 1 else {
                throw DatabaseError.sql("deleteEmptySpace: no space \(spaceID)")
            }
        }
    }

    /// 改房间名。房间是标签，改名就是改标签；`titleSource` 跟着标成人写的，
    /// 免得以后自动命名再把它盖掉。
    public func renameSpace(_ spaceID: String, title: String, titleSource: String = "human")
        throws
    {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw DatabaseError.sql("renameSpace: empty title")
        }
        let changed = try execBinding(
            "UPDATE spaces SET title=?, title_source=? WHERE space_id=?;"
        ) {
            try bind($0, 1, name)
            try bind($0, 2, titleSource)
            try bind($0, 3, spaceID)
        }
        guard changed == 1 else {
            throw DatabaseError.sql("renameSpace: no space \(spaceID)")
        }
    }

    /// 删掉一个房间名之前，谁接管它的归属。
    ///
    /// 顺序是「已有的名字」优先：同轴房间（库里标过 axis 时）→「其他」→ 成员最多
    /// 的那个。都不合适就返回 nil——界面据此提示「新建房间」或「这个名字留着改个名」，
    /// 而不是把归属悬在半空。
    public func spaceDeletionTarget(for spaceID: String) throws -> SpaceRow? {
        let others = try listSpaces().filter { $0.spaceID != spaceID }
        guard !others.isEmpty else { return nil }

        // 同轴：axis 是外部归类工具加的列，没有这一列时这一步自然跳过。
        if try columnExists("spaces", "axis"), let axis = try spaceAxis(spaceID),
            !axis.isEmpty
        {
            for candidate in others {
                if try spaceAxis(candidate.spaceID) == axis {
                    return candidate
                }
            }
        }
        if let fallback = others.first(where: { $0.spaceID == "space-room-other" }) {
            return fallback
        }
        var best: (row: SpaceRow, total: Int)?
        for candidate in others {
            let total = try spaceOccupancy(candidate.spaceID).total
            if best == nil || total > best!.total {
                best = (candidate, total)
            }
        }
        // 全员皆空时也要给一个：名字总得落在一个房间上，选名单里的第一个。
        return best?.row ?? others.first
    }

    /// `spaces.axis` 的当前取值。列不存在（外部归类工具还没跑过）时返回 nil。
    public func spaceAxis(_ spaceID: String) throws -> String? {
        try beforeSpaceAxisLookupForTesting?(spaceID)
        guard try columnExists("spaces", "axis") else { return nil }
        let stmt = try prepare("SELECT axis FROM spaces WHERE space_id=?;")
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, spaceID)
        guard try stepRowOrDone(stmt) else { return nil }
        guard sqlite3_column_type(stmt, 0) != SQLITE_NULL else { return nil }
        return String(cString: sqlite3_column_text(stmt, 0))
    }

    public struct SpaceMergeReport: Equatable, Sendable {
        public let movedRoots: Int
        public let movedTurns: Int
        public let movedSessions: Int
        /// 本来就已经挂在目标房间里、不需要再搬的轮次。
        public let absorbedTurns: Int
    }

    /// 把 source 的归属整体搬到 target，再删掉已经空掉的 source。
    /// `space_turns` 的主键含 `space_id`，同一个轮次可以同时属于两个房间，
    /// 所以先 `INSERT OR IGNORE` 再 `DELETE`：不撞键，也不丢归属。
    /// 搬完复查 source 的占用必须归零，否则整笔回滚——宁可留着让人看见。
    @discardableResult
    public func mergeSpace(source sourceID: String, into targetID: String) throws
        -> SpaceMergeReport
    {
        guard sourceID != targetID else {
            throw DatabaseError.sql("mergeSpace: source and target are the same space")
        }
        guard try space(id: sourceID) != nil else {
            throw DatabaseError.sql("mergeSpace: no source \(sourceID)")
        }
        guard try space(id: targetID) != nil else {
            throw DatabaseError.sql("mergeSpace: no target \(targetID)")
        }
        try ensureRoomSchema()
        return try transactionResult {
            try beforeMergeSpaceAbsorbedCountForTesting?()
            let absorbed: Int
            do {
                let stmt = try prepare("""
                SELECT COUNT(*) FROM space_turns s
                 WHERE s.space_id=?
                   AND EXISTS (SELECT 1 FROM space_turns t
                                WHERE t.space_id=?
                                  AND t.session_id=s.session_id
                                  AND t.turn_index=s.turn_index);
                """)
                defer { sqlite3_finalize(stmt) }
                try bind(stmt, 1, sourceID)
                try bind(stmt, 2, targetID)
                absorbed = try stepRowOrDone(stmt)
                    ? Int(sqlite3_column_int64(stmt, 0)) : 0
            }
            let copied = try execBinding("""
                INSERT OR IGNORE INTO space_turns(
                    session_id, turn_index, space_id, assigned_by, assigned_at)
                SELECT session_id, turn_index, ?, assigned_by, assigned_at
                  FROM space_turns WHERE space_id=?;
                """) {
                    try bind($0, 1, targetID)
                    try bind($0, 2, sourceID)
            }
            _ = try execBinding("DELETE FROM space_turns WHERE space_id=?;") {
                try bind($0, 1, sourceID)
            }
            let roots = try execBinding("UPDATE roots SET space_id=? WHERE space_id=?;") {
                try bind($0, 1, targetID)
                try bind($0, 2, sourceID)
            }
            let sessions = try execBinding(
                "UPDATE agent_sessions SET space_id=? WHERE space_id=?;"
            ) {
                try bind($0, 1, targetID)
                try bind($0, 2, sourceID)
            }
            let leftover = try spaceOccupancy(sourceID)
            guard leftover.total == 0 else {
                throw DatabaseError.sql(
                    "mergeSpace: source still holds \(leftover.total) after move")
            }
            // 名字和判据一起交给目标。不记别名的话，下一次全量判断会照原判据
            // 把源房间再造回来——人看到的就是「合并了又长出来」。
            // 已经指向源房间的别名也一并转到目标，合并链不留悬空。
            _ = try execBinding("""
            UPDATE space_room_aliases SET target_space_id=? WHERE target_space_id=?;
            """) {
                try bind($0, 1, targetID)
                try bind($0, 2, sourceID)
            }
            if let rule = try roomRulePattern(forSpaceID: sourceID) {
                try execBinding("""
                INSERT INTO space_room_aliases(
                    source_id, target_space_id, axis, pattern, merged_at)
                VALUES(?,?,?,?,?)
                ON CONFLICT(source_id) DO UPDATE SET
                    target_space_id=excluded.target_space_id,
                    axis=excluded.axis, pattern=excluded.pattern,
                    merged_at=excluded.merged_at;
                """) {
                    try bind($0, 1, sourceID)
                    try bind($0, 2, targetID)
                    try bind($0, 3, rule.axis)
                    try bind($0, 4, rule.pattern)
                    try bind($0, 5, Self.stamp(Date()))
                }
            }
            _ = try execBinding("DELETE FROM spaces WHERE space_id=?;") {
                try bind($0, 1, sourceID)
            }
            return SpaceMergeReport(
                movedRoots: roots, movedTurns: copied, movedSessions: sessions,
                absorbedTurns: absorbed)
        }
    }

    // MARK: - 前期一次性收口：轮次进房间 / 来源时间回填
    //
    // 这两件事原来是 tools/assign_turn_spaces.py 与 tools/backfill_source_time.py
    // 手工跑的。规则写在脚本里，App 就做不到——「刷新状态」按下去只能摊手。
    // 脚本没退役：`tools/` 下那两个仍然能用，云端代理那条路就靠它们跑。
    // 这里这一份是 App 自己跑的路——人不在终端前面时，按钮得有人接。
    //
    // 边界：这里补的是**历史**（一次性收口）。新轮次进库时由
    // `TurnDigestScheduler.schedule` 当场补摘要与关键词，那是增量，不走这条路。

    /// 会话型房间的判据。产品自己的轴写在这里；客户/项目目录的判据**不写死**，
    /// 从库里 `kind='directory' AND axis IS NOT NULL` 读——目录名进代码就是泄露，
    /// 而且每加一个目录就得改一次代码。
    private static let contentRoomRules:
        [(id: String, title: String, axis: String, pattern: String)] = [
            ("space-room-simigo", "SimiGo", "project",
             #"simigo|SettingsView|HTTPServer|McpClient|chat_round"#),
            ("space-room-local-inference", "本地推理", "nature",
             #"NativeMLX|^MLX$|mlx-swift|GGUF|llama|量化|显存|KVCache|^KV$|MoE|^MTP$"#),
            ("space-room-is", "信息空间", "nature",
             #"信息空间|拓扑|结算|is_objects|turn_digests|检索"#),
        ]
    private static let directoryBusinessWords = "合同|招标|考核|造价"
    /// 一个会话要有这么多条命中，才有资格给同会话「没命中的轮次」当默认房间；
    /// 还要占本会话轮数的 10%。否则 475 轮里提了 17 次 SimiGo，整场都会被划进去
    /// ——那是顺带提了一句，不是内容归属。
    private static let roomMajorityMinHits = 3
    private static let roomMajorityMinShare = 0.10

    private struct RoomRule {
        let id: String
        let title: String
        let axis: String
        let regex: NSRegularExpression
    }

    private struct TurnKey: Hashable {
        let session: String
        let turn: Int
    }

    public struct TurnSpaceReport: Equatable, Sendable {
        public let turns: Int
        public let keywordHits: Int
        public let rowsWritten: Int
        public let byRoom: [String: Int]
        public let bySource: [String: Int]
        public let dryRun: Bool
    }

    private static func compileRoomRule(_ pattern: String) throws -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            throw DatabaseError.sql("房间判据不是合法正则：\(pattern)")
        }
    }

    private static func ruleMatches(_ regex: NSRegularExpression, _ term: String) -> Bool {
        regex.firstMatch(in: term, range: NSRange(term.startIndex..., in: term)) != nil
    }

    /// 目录型房间的判据：标题去掉序号前缀与扩展名，再加一组通用业务词。
    /// 通用词是「合同」「招标」这类词，不是身份，换个项目也成立，所以留在代码里。
    private func directoryRoomRules() throws -> [(id: String, title: String, axis: String)] {
        let stmt = try prepare("""
        SELECT space_id, title, axis FROM spaces
         WHERE kind='directory' AND axis IS NOT NULL
         ORDER BY created_at, space_id;
        """)
        defer { sqlite3_finalize(stmt) }
        var rows: [(String, String, String)] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String {
                sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
            }
            rows.append((text(0), text(1), text(2)))
        }
        return rows
    }

    /// 「26.秦沈项目.md」→「秦沈项目」。序号和扩展名不是内容，是书的页码。
    private static func directoryRoomPattern(_ title: String) -> String {
        var core = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = core.range(
            of: #"^\s*\d+\s*[.、．_\-]\s*"#, options: .regularExpression) {
            core.removeSubrange(r)
        }
        if let r = core.range(of: #"\.[A-Za-z0-9]{1,5}$"#, options: .regularExpression) {
            core.removeSubrange(r)
        }
        core = core.trimmingCharacters(in: .whitespacesAndNewlines)
        return [NSRegularExpression.escapedPattern(for: core), directoryBusinessWords]
            .filter { !$0.isEmpty }
            .joined(separator: "|")
    }

    /// 按 id、再按标题复用已有房间（目录型房间也是房间，可以接轮次），
    /// 都没有才新建。新建的标 `title_source='content'`——它来自内容判定，不是人起的。
    private func resolveRoom(id: String, title: String, axis: String) throws -> String {
        if try space(id: id) != nil {
            _ = try execBinding("UPDATE spaces SET axis=COALESCE(axis,?) WHERE space_id=?;") {
                try bind($0, 1, axis)
                try bind($0, 2, id)
            }
            return id
        }
        let byTitle = try prepare("SELECT space_id FROM spaces WHERE title=? LIMIT 1;")
        try bind(byTitle, 1, title)
        if try stepRowOrDone(byTitle), let c = sqlite3_column_text(byTitle, 0) {
            let existing = String(cString: c)
            sqlite3_finalize(byTitle)
            _ = try execBinding("UPDATE spaces SET axis=COALESCE(axis,?) WHERE space_id=?;") {
                try bind($0, 1, axis)
                try bind($0, 2, existing)
            }
            return existing
        }
        sqlite3_finalize(byTitle)
        _ = try execBinding("""
        INSERT INTO spaces(
            space_id, title, title_source, kind, parent_space_id, created_at, axis)
        VALUES(?,?,'content','session',NULL,?,?);
        """) {
            try bind($0, 1, id)
            try bind($0, 2, title)
            try bind($0, 3, Self.stamp(Date()))
            try bind($0, 4, axis)
        }
        return id
    }

    /// 把每一轮按**内容**归进房间（不是按来源、不是按 agent：谁写的不重要，
    /// 写的是什么才决定进哪个房间）。每轴每轮最多一个房间——一轮可以同时在
    /// 「项目」轴和「性质」轴各挂一个，这是平铺加轴，不是单路径嵌套。
    ///
    /// 「每轴一个」由写入方保证：这一轮先清空，再按本次判断重写。`assigned_by`
    /// 只记这次判断怎么来的（content / inherit / other）。人的操作在房间这一层
    /// （建 / 改名 / 合并 / 删名 / 挂目录），轮次进哪个房间没有人工入口——它由
    /// 这里的判据决定，不是谁手工指定的。
    /// `space_turns` 与 `spaces.axis` 原本都归外部脚本管。判据现在也住在这里，
    /// 表和列一起归这里建；脚本那边是 `CREATE IF NOT EXISTS`，两边都跑不打架。
    private func ensureRoomSchema() throws {
        // 建表是写操作：连接缓存住「已经建过」，重放路径才能在别人持锁时
        // 只读不写——否则每次重放都先撞一次 DDL 的锁，退避逻辑根本没机会跑。
        if roomSchemaReady { return }
        try Self.rawExec(handle, """
        CREATE TABLE IF NOT EXISTS space_turns(
            session_id TEXT NOT NULL,
            turn_index INTEGER NOT NULL,
            space_id TEXT NOT NULL REFERENCES spaces(space_id),
            assigned_by TEXT NOT NULL,
            assigned_at TEXT NOT NULL,
            PRIMARY KEY(session_id, turn_index, space_id));
        CREATE INDEX IF NOT EXISTS idx_space_turns_space
            ON space_turns(space_id, session_id, turn_index);

        -- 合并过的房间：源房间没了，但它的判据词不能跟着没。若下一次判断
        -- 还按源的原判据跑，源就会被原样再造出来，合并等于没做。这里把源
        -- 的判据记成目标的别名：这些词的命中仍算在目标头上。
        CREATE TABLE IF NOT EXISTS space_room_aliases(
            source_id TEXT PRIMARY KEY,
            target_space_id TEXT NOT NULL,
            axis TEXT NOT NULL,
            pattern TEXT NOT NULL,
            merged_at TEXT NOT NULL);

        -- 增量归属失败的持久化待重试记录（#187）：`assignTurnSpace` 撞上
        -- SQLITE_BUSY 时摘要已落库、归属没写上，这里记一行，任何一次后续
        -- 写入/启动都会重放。PRIMARY KEY 天然去重：同一轮反复失败只累计
        -- attempts，不积行。
        CREATE TABLE IF NOT EXISTS space_assignment_retry(
            session_id TEXT NOT NULL,
            turn_index INTEGER NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            failed_at TEXT NOT NULL,
            next_attempt_at TEXT,
            PRIMARY KEY(session_id, turn_index));
        """)
        if try !columnExists("spaces", "axis") {
            try Self.rawExec(handle, "ALTER TABLE spaces ADD COLUMN axis TEXT;")
        }
        if try !columnExists("space_assignment_retry", "next_attempt_at") {
            // 老库的表是上一版建的，没有这一列：退避要靠它，缺了就补上。
            try Self.rawExec(
                handle, "ALTER TABLE space_assignment_retry ADD COLUMN next_attempt_at TEXT;")
        }
        roomSchemaReady = true
    }

    /// 当前该用哪几条判据：产品自己的轴 + 库里标了轴的目录房间。
    private func roomRules() throws -> (rules: [RoomRule], titles: [String: String]) {
        let aliases = try roomAliases()
        let mergedAway = Set(aliases.map(\.source))
        // 同一个房间在一条轴上的词并成一条规则再打分。拆成两条会各算各的，
        // 合并来的词与自己的词就要分开去和第三个房间比，谁都不够。
        var words: [String: (id: String, title: String, axis: String,
                             patterns: [String])] = [:]
        var order: [String] = []
        func add(_ id: String, _ title: String, _ axis: String, _ pattern: String) {
            let key = id + "\u{1}" + axis
            if var entry = words[key] {
                entry.patterns.append(pattern)
                words[key] = entry
            } else {
                words[key] = (id, title, axis, [pattern])
                order.append(key)
            }
        }
        for r in Self.contentRoomRules where !mergedAway.contains(r.id) {
            add(r.id, r.title, r.axis, r.pattern)
        }
        for room in try directoryRoomRules() where !mergedAway.contains(room.id) {
            add(room.id, room.title, room.axis, Self.directoryRoomPattern(room.title))
        }
        // 并掉的房间，判据词交给目标。
        for alias in aliases {
            add(alias.target, alias.title, alias.axis, alias.pattern)
        }

        var rules: [RoomRule] = []
        var titles: [String: String] = [:]
        // 顺序按先来后到：打分平手时先出场者胜，顺序一变平手就跟着漂。
        for key in order {
            guard let entry = words[key] else { continue }
            let pattern = entry.patterns.count == 1
                ? entry.patterns[0]
                : entry.patterns.map { "(\($0))" }.joined(separator: "|")
            rules.append(RoomRule(id: entry.id, title: entry.title, axis: entry.axis,
                                  regex: try Self.compileRoomRule(pattern)))
            titles[entry.id] = entry.title
        }
        titles["space-room-other"] = "其他"
        return (rules, titles)
    }

    private struct RoomAlias {
        let source: String
        let target: String
        let title: String
        let axis: String
        let pattern: String
    }

    /// 合并过的房间：源 → 目标 + 源当时的判据词。目标已不存在的别名不再参与
    /// 判断（正常情况下 mergeSpace 会把它转到新目标，这里是兜底）。
    private func roomAliases() throws -> [RoomAlias] {
        guard try tableExists("space_room_aliases") else { return [] }
        let stmt = try prepare("""
        SELECT a.source_id, a.target_space_id, s.title, a.axis, a.pattern
          FROM space_room_aliases a JOIN spaces s ON s.space_id=a.target_space_id
         ORDER BY a.merged_at, a.source_id;
        """)
        defer { sqlite3_finalize(stmt) }
        var out: [RoomAlias] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String {
                sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
            }
            out.append(RoomAlias(source: text(0), target: text(1), title: text(2),
                                 axis: text(3), pattern: text(4)))
        }
        return out
    }

    /// 这个房间靠什么词被选中。没有判据的房间（人新建的会话房间）返回 nil：
    /// 删掉它不会影响下一次判断，也就不需要记别名。
    private func roomRulePattern(forSpaceID id: String) throws
        -> (axis: String, pattern: String)?
    {
        if let builtin = Self.contentRoomRules.first(where: { $0.id == id }) {
            return (builtin.axis, builtin.pattern)
        }
        let stmt = try prepare("""
        SELECT title, axis FROM spaces
         WHERE space_id=? AND kind='directory' AND axis IS NOT NULL;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, id)
        guard try stepRowOrDone(stmt),
              let title = sqlite3_column_text(stmt, 0),
              let axis = sqlite3_column_text(stmt, 1) else { return nil }
        return (String(cString: axis),
                Self.directoryRoomPattern(String(cString: title)))
    }

    /// 一轮的关键词，一条一个词。
    private func turnKeywords(sessionID: String, turnIndex: Int) throws -> [String] {
        guard try tableExists("turn_keywords") else { return [] }
        let stmt = try prepare("""
        SELECT k.term FROM turn_keywords tk JOIN keywords k USING(keyword_id)
         WHERE tk.session_id=? AND tk.turn_index=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, Int64(turnIndex))
        var terms: [String] = []
        while try stepRowOrDone(stmt) {
            if let c = sqlite3_column_text(stmt, 0) { terms.append(String(cString: c)) }
        }
        return terms
    }

    /// 每轴挑一个赢家：命中条数最多者。一条都没命中的轴不返回。
    private func bestRooms(
        for terms: [String], rules: [RoomRule]
    ) -> [String: RoomRule] {
        var perAxis: [String: (n: Int, rule: RoomRule)] = [:]
        for rule in rules {
            var n = 0
            for term in terms where Self.ruleMatches(rule.regex, term) { n += 1 }
            guard n > 0 else { continue }
            if let best = perAxis[rule.axis], best.n >= n { continue }
            perAxis[rule.axis] = (n, rule)
        }
        return perAxis.mapValues { $0.rule }
    }

    /// 与全量重算相同的会话多数判定。直接从每轮关键词重新计算命中轴，
    /// 不读取已落库的继承行，避免合并房间跨轴以及继承自我强化。
    private func sessionMajorityRooms(sessionID: String) throws -> [String: String] {
        let (rules, _) = try roomRules()
        let turnsStmt = try prepare("""
        SELECT turn_index FROM turn_digests
         WHERE session_id=? ORDER BY turn_index;
        """)
        defer { sqlite3_finalize(turnsStmt) }
        try bind(turnsStmt, 1, sessionID)

        var turns: [Int] = []
        while try stepRowOrDone(turnsStmt) {
            turns.append(Int(sqlite3_column_int64(turnsStmt, 0)))
        }
        guard !turns.isEmpty else { return [:] }

        // Fetch the entire session keyword set in one pass. A per-turn query here
        // would make each incremental assignment O(session turns) SQL round trips.
        var keywordsByTurn: [Int: [String]] = [:]
        if try tableExists("turn_keywords") {
            let keywordsStmt = try prepare("""
            SELECT tk.turn_index, k.term
              FROM turn_keywords tk
              JOIN keywords k USING(keyword_id)
             WHERE tk.session_id=?
             ORDER BY tk.turn_index, k.term;
            """)
            defer { sqlite3_finalize(keywordsStmt) }
            try bind(keywordsStmt, 1, sessionID)
            while try stepRowOrDone(keywordsStmt) {
                let turn = Int(sqlite3_column_int64(keywordsStmt, 0))
                let term = sqlite3_column_text(keywordsStmt, 1)
                    .map { String(cString: $0) } ?? ""
                keywordsByTurn[turn, default: []].append(term)
            }
        }

        var counters: [String: [String: Int]] = [:]
        for turnIndex in turns {
            for (axis, rule) in bestRooms(
                for: keywordsByTurn[turnIndex] ?? [], rules: rules)
            {
                counters[axis, default: [:]][rule.id, default: 0] += 1
            }
        }

        var inherited: [String: String] = [:]
        for (axis, counter) in counters {
            let ranked = counter.sorted {
                $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
            }
            guard let top = ranked.first,
                  top.value >= Self.roomMajorityMinHits,
                  Double(top.value) >= Self.roomMajorityMinShare * Double(turns.count),
                  let rule = rules.first(where: { $0.id == top.key && $0.axis == axis })
            else { continue }
            inherited[axis] = try resolveRoom(
                id: rule.id, title: rule.title, axis: rule.axis)
        }
        return inherited
    }

    /// 增量：一轮刚写下摘要与关键词，立刻把它放进房间。
    ///
    /// 新轮次不归属，等于素材进来了但没人认识它——下一轮检索就找不到它。
    /// 判据与全量同一套；本轮一条都没命中时，仅在同会话该轴的直接内容命中
    /// 达到全量多数门槛（至少 3 轮且占比不低于 10%）时继承，否则落「其他」。
    /// 返回 axis → space_id。
    @discardableResult
    public func assignTurnSpace(sessionID: String, turnIndex: Int) throws -> [String: String] {
        try ensureRoomSchema()
        return try transactionResult {
            let (rules, _) = try roomRules()
            let picks = bestRooms(for: try turnKeywords(sessionID: sessionID,
                                                        turnIndex: turnIndex),
                                  rules: rules)
            var chosen: [String: String] = [:]
            var provenance: [String: String] = [:]
            var resolved: [String: String] = [:]
            for (axis, rule) in picks {
                if resolved[rule.id] == nil {
                    resolved[rule.id] = try resolveRoom(
                        id: rule.id, title: rule.title, axis: rule.axis)
                }
                chosen[axis] = resolved[rule.id]
                provenance[axis] = "content"
            }
            if ["project", "nature"].contains(where: { chosen[$0] == nil }) {
                let inheritedRooms = try sessionMajorityRooms(sessionID: sessionID)
                for axis in ["project", "nature"] where chosen[axis] == nil {
                    if let room = inheritedRooms[axis] {
                        chosen[axis] = room
                        provenance[axis] = "inherit"
                    }
                }
            }
            if chosen.isEmpty {
                if resolved["space-room-other"] == nil {
                    resolved["space-room-other"] = try resolveRoom(
                        id: "space-room-other", title: "其他", axis: "fallback")
                }
                chosen["fallback"] = resolved["space-room-other"]
                provenance["fallback"] = "other"
            }

            // 落表。先清空这一轮：词后来补过，房间就可能换，旧行留着等于同一轮
            // 在同一轴挂着两个。清完再按本次判断写，每轴最多一行由这里保证。
            let stamp = Self.stamp(Date())
            _ = try execBinding("""
            DELETE FROM space_turns WHERE session_id=? AND turn_index=?;
            """) {
                try bind($0, 1, sessionID)
                try bind($0, 2, Int64(turnIndex))
            }
            let insert = try prepare("""
            INSERT INTO space_turns(
                session_id, turn_index, space_id, assigned_by, assigned_at)
            VALUES(?,?,?,?,?)
            ON CONFLICT(session_id, turn_index, space_id) DO UPDATE SET
                assigned_by=excluded.assigned_by, assigned_at=excluded.assigned_at;
            """)
            let byRank = ["content": 3, "other": 2, "inherit": 1]
            var rows: [String: String] = [:]
            for (axis, spaceID) in chosen {
                let by = provenance[axis] ?? "content"
                if rows[spaceID] == nil
                    || (byRank[by] ?? 0) > (byRank[rows[spaceID] ?? ""] ?? 0) {
                    rows[spaceID] = by
                }
            }
            for (spaceID, by) in rows {
                sqlite3_reset(insert)
                sqlite3_clear_bindings(insert)
                try bind(insert, 1, sessionID)
                try bind(insert, 2, Int64(turnIndex))
                try bind(insert, 3, spaceID)
                try bind(insert, 4, by)
                try bind(insert, 5, stamp)
                guard sqlite3_step(insert) == SQLITE_DONE else {
                    sqlite3_finalize(insert)
                    throw DatabaseError.sql("assignTurnSpace: INSERT 未完成")
                }
            }
            sqlite3_finalize(insert)
            return chosen
        }
    }


    // MARK: - Space-assignment retry queue (#187)

    /// 一轮重放的结果。`retried` 是本次真正发起尝试的轮数；`deferred` 是还
    /// 没到退避时间、这次先不碰的轮；`stillPending` 含本次又失败的轮；
    /// `abandoned` 是达到重试上限、不再自动重试的轮——它不消失，留在表里，
    /// 由设置页的「重放」重新武装。
    public struct SpaceAssignmentRetryReport: Equatable, Sendable {
        public let retried: Int
        public let succeeded: Int
        public let stillPending: Int
        public let deferred: Int
        public let abandoned: Int

        public var isEmpty: Bool {
            retried == 0 && stillPending == 0 && deferred == 0 && abandoned == 0
        }
    }

    /// 队列现状（诊断与设置页用）。
    public struct SpaceAssignmentRetryStatus: Equatable, Sendable {
        /// 还在队列里的轮数（含已放弃的）。
        public let pending: Int
        /// 达到重试上限、不再自动重试的轮数。
        public let abandoned: Int
        /// 最近一次失败的原因；没失败过为 nil。
        public let lastError: String?
    }

    /// 第 n 次失败之后该等多久再试：base、2×base、4×base……封顶 30 分钟。
    /// 上限要「次数」和「时间」两道：只有次数时，连续几次摘要写入就能把额度
    /// 一口气耗光，那不是给锁竞争留的恢复时间（#187 审核 2026-11-13）。
    public static func assignmentRetryDelay(
        attempts: Int, base: TimeInterval = 30
    ) -> TimeInterval {
        let step = pow(2.0, Double(max(0, attempts - 1)))
        return min(base * step, 1800)
    }

    /// 「这一轮还欠一次归属判断」——和摘要写在同一个事务里（#187）。撞锁时
    /// 摘要已经落库、归属没写上，待办必须先落；写完再判，判失败也已有据可查。
    /// 已在队列里的行不重置：attempts 与退避时间都还算数。
    private func markSpaceAssignmentPending(
        sessionID: String, turnIndex: Int, now: Date
    ) throws {
        try execBinding("""
        INSERT INTO space_assignment_retry(
            session_id, turn_index, attempts, last_error, failed_at, next_attempt_at)
        VALUES(?,?,0,NULL,?,?)
        ON CONFLICT(session_id, turn_index) DO NOTHING;
        """) { stmt in
            try bind(stmt, 1, sessionID)
            try bind(stmt, 2, Int64(turnIndex))
            let nowText = Self.stamp(now)
            try bind(stmt, 3, nowText)
            try bind(stmt, 4, nowText)
        }
    }

    /// 归属已经写上，欠账销掉。删失败不是数据问题：重放会再判一次，而
    /// `assignTurnSpace` 对自己那一轮先删后写，重放是幂等的。
    public func clearSpaceAssignmentPending(sessionID: String, turnIndex: Int) throws {
        try ensureRoomSchema()
        try transactionResult {
            try execBinding("""
            DELETE FROM space_assignment_retry
             WHERE session_id=? AND turn_index=?;
            """) { stmt in
                try bind(stmt, 1, sessionID)
                try bind(stmt, 2, Int64(turnIndex))
            }
        }
    }

    /// 增量归属失败的持久化记录：attempts 加一，并按 `assignmentRetryDelay`
    /// 定下一次最早什么时候再试。写在独立的小事务里：调用方刚从一次锁竞争
    /// 里退出来，这里若再撞锁，`busy_timeout` 会等——记录本身丢不起。
    public func recordSpaceAssignmentFailure(
        sessionID: String, turnIndex: Int, error: Error, now: Date = Date()
    ) throws {
        try ensureRoomSchema()
        let message = String(describing: error).prefix(500)
        try transactionResult {
            // 两个重放可以同时认领同一行：先到的那次判上了并销掉欠账，后到的那次
            // 还在自己的失败分支里，会把这一行又写回来——判上了却挂着欠账，之后
            // 每次心跳都重判一遍，队列也永远清不空。判上就不再记欠账，这条不变量
            // 写在这里，所有写入口都一样。
            if try turnHasRoomAssignment(sessionID: sessionID, turnIndex: turnIndex) {
                try execBinding("""
                DELETE FROM space_assignment_retry
                 WHERE session_id=? AND turn_index=?;
                """) { stmt in
                    try bind(stmt, 1, sessionID)
                    try bind(stmt, 2, Int64(turnIndex))
                }
                return
            }
            let attempts = try spaceAssignmentAttempts(
                sessionID: sessionID, turnIndex: turnIndex)
            let next = attempts + 1
            let retryAt = Self.stamp(
                now.addingTimeInterval(Self.assignmentRetryDelay(attempts: next)))
            try execBinding("""
            INSERT INTO space_assignment_retry(
                session_id, turn_index, attempts, last_error, failed_at, next_attempt_at)
            VALUES(?,?,?,?,?,?)
            ON CONFLICT(session_id, turn_index) DO UPDATE SET
                attempts=excluded.attempts, last_error=excluded.last_error,
                failed_at=excluded.failed_at, next_attempt_at=excluded.next_attempt_at;
            """) { stmt in
                try bind(stmt, 1, sessionID)
                try bind(stmt, 2, Int64(turnIndex))
                try bind(stmt, 3, Int64(next))
                try bind(stmt, 4, String(message))
                try bind(stmt, 5, Self.stamp(now))
                try bind(stmt, 6, retryAt)
            }
        }
    }

    private func spaceAssignmentAttempts(sessionID: String, turnIndex: Int) throws -> Int {
        let stmt = try prepare("""
        SELECT attempts FROM space_assignment_retry
         WHERE session_id=? AND turn_index=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, Int64(turnIndex))
        return try stepRowOrDone(stmt) ? Int(sqlite3_column_int64(stmt, 0)) : 0
    }

    /// 这一轮现在有没有房间归属。欠账只在「没判上」时才有意义。
    private func turnHasRoomAssignment(sessionID: String, turnIndex: Int) throws -> Bool {
        let stmt = try prepare("""
        SELECT 1 FROM space_turns
         WHERE session_id=? AND turn_index=? LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, Int64(turnIndex))
        return try stepRowOrDone(stmt)
    }

    /// 当前待重试的归属轮数（含已放弃；诊断用，补完归零）。
    public func pendingSpaceAssignmentRetries() throws -> Int {
        try ensureRoomSchema()
        return try scalarCount("SELECT COUNT(*) FROM space_assignment_retry;")
    }

    /// 队列现状：待办多少、多少已经放弃、最近一次为什么失败。
    public func spaceAssignmentRetryStatus(maxAttempts: Int = 5) throws
        -> SpaceAssignmentRetryStatus
    {
        try ensureRoomSchema()
        let pending = try pendingSpaceAssignmentRetries()
        var abandoned = 0
        var lastError: String?
        let stmt = try prepare("""
        SELECT attempts, last_error FROM space_assignment_retry
         ORDER BY failed_at;
        """)
        defer { sqlite3_finalize(stmt) }
        while try stepRowOrDone(stmt) {
            if Int(sqlite3_column_int64(stmt, 0)) >= maxAttempts { abandoned += 1 }
            if let text = sqlite3_column_text(stmt, 1).map({ String(cString: $0) }) {
                lastError = text
            }
        }
        return SpaceAssignmentRetryStatus(
            pending: pending, abandoned: abandoned, lastError: lastError)
    }

    /// 有摘要、没归属、也不在队列里的轮，补进队列（#188 第五项的口子）。
    /// 队列只记得住「记下来过的失败」；工具补的摘要、早于队列存在的轮、
    /// 断电丢掉的那一行都不在队列里——只重放队列，等于永远补不上它们。
    /// One recovery enqueue is capped even when a caller supplies a very large limit.
    private static let maxOrphanEnqueueBatch = 4_096

    @discardableResult
    public func enqueueDigestsWithoutRoom(limit: Int = 2000) throws -> Int {
        guard limit >= 0 else {
            throw DatabaseError.sql("enqueueDigestsWithoutRoom: limit must be non-negative")
        }
        let boundedLimit = min(limit, Self.maxOrphanEnqueueBatch)
        try ensureRoomSchema()
        var added = 0
        try transactionResult {
            let before = try scalarCount("SELECT COUNT(*) FROM space_assignment_retry;")
            try execBinding("""
            INSERT INTO space_assignment_retry(
                session_id, turn_index, attempts, last_error, failed_at, next_attempt_at)
            SELECT d.session_id, d.turn_index, 0, NULL, ?, ?
              FROM turn_digests d
             WHERE NOT EXISTS (SELECT 1 FROM space_turns st
                                WHERE st.session_id=d.session_id
                                  AND st.turn_index=d.turn_index)
               AND NOT EXISTS (SELECT 1 FROM space_assignment_retry r
                                WHERE r.session_id=d.session_id
                                  AND r.turn_index=d.turn_index)
             ORDER BY d.session_id, d.turn_index
             LIMIT ?
            ON CONFLICT(session_id, turn_index) DO NOTHING;
            """) { stmt in
                let nowText = Self.stamp(Date())
                try bind(stmt, 1, nowText)
                try bind(stmt, 2, nowText)
                try bind(stmt, 3, Int64(boundedLimit))
            }
            let after = try scalarCount("SELECT COUNT(*) FROM space_assignment_retry;")
            added = max(0, after - before)
        }
        return added
    }

    /// 把放弃的轮重新武装：attempts 归零、退避清掉，下一次重放就再试。
    /// 人按「重放」是明确表态——锁的问题已经过去了，值得再给一轮。
    ///
    /// 重放之前先 `enqueueDigestsWithoutRoom`：有摘要、没归属、又不在队列里的
    /// 轮（工具补的摘要、早于这个队列写入的轮、断电丢掉的那一行）只有那一步
    /// 才捞得回来——队列再重试也不会凭空长出它们。
    @discardableResult
    public func resetSpaceAssignmentRetries(now: Date = Date()) throws -> Int {

        try ensureRoomSchema()
        let pending = try pendingSpaceAssignmentRetries()
        guard pending > 0 else { return 0 }
        try transactionResult {
            try execBinding("""
            UPDATE space_assignment_retry
               SET attempts=0, last_error=NULL, next_attempt_at=?;
            """) { stmt in
                try bind(stmt, 1, Self.stamp(now))
            }
        }
        return pending
    }

    /// 重放一遍待重试的归属。归属判断只吃关键词与判据词（不碰模型），所以
    /// 重放可以在任何时刻跑：下一次摘要写入、补录收尾、进程启动。每行一次
    /// 尝试：成功删行；失败 `attempts+1` 并按退避定下一次；没到时间的这次不碰
    /// （`deferred`）；`attempts >= maxAttempts` 的行跳过并计入 `abandoned`。
    @discardableResult
    public func retryPendingSpaceAssignments(
        maxAttempts: Int = 5, maxRows: Int = 64, now: Date = Date()
    ) throws -> SpaceAssignmentRetryReport {
        try ensureRoomSchema()
        var retried = 0, succeeded = 0, stillPending = 0
        let boundedLimit = min(max(1, maxRows), 256)
        let nowText = Self.stamp(now)

        // deferred / abandoned 用两条 COUNT 数全表：报数要覆盖整个队列，
        // 但不该为了报数把整张队列读进内存。每条语句读完就 finalize，
        // 不把活动游标带进后面的队列删除/更新。
        let deferred: Int
        do {
            let stmt = try prepare("""
            SELECT COUNT(*) FROM space_assignment_retry
             WHERE attempts < ?
               AND next_attempt_at IS NOT NULL
               AND CAST(next_attempt_at AS REAL) > CAST(? AS REAL);
            """)
            defer { sqlite3_finalize(stmt) }
            try bind(stmt, 1, Int64(maxAttempts))
            try bind(stmt, 2, nowText)
            guard try stepRowOrDone(stmt) else {
                throw DatabaseError.sql("retryPendingSpaceAssignments: deferred count returned no row")
            }
            deferred = Int(sqlite3_column_int64(stmt, 0))
        }

        // 一次只处理有限批次。已放弃与未到点的行必须在 LIMIT **之前**就排掉，
        // 否则它们占满窗口，后面真正到期的轮永远轮不到。排序按存进去的
        // reference-date 数值比，不按字符串比。
        var rows: [(session: String, turn: Int)] = []
        do {
            let stmt = try prepare("""
            SELECT session_id, turn_index
              FROM space_assignment_retry
             WHERE attempts < ?
               AND (next_attempt_at IS NULL
                    OR CAST(next_attempt_at AS REAL) <= CAST(? AS REAL))
             ORDER BY CAST(failed_at AS REAL), session_id, turn_index
             LIMIT ?;
            """)
            defer { sqlite3_finalize(stmt) }
            try bind(stmt, 1, Int64(maxAttempts))
            try bind(stmt, 2, nowText)
            try bind(stmt, 3, Int64(boundedLimit))
            while try stepRowOrDone(stmt) {
                let session = sqlite3_column_text(stmt, 0)
                    .map { String(cString: $0) } ?? ""
                rows.append((session, Int(sqlite3_column_int64(stmt, 1))))
            }
        }

        for row in rows {
            retried += 1
            do {
                _ = try assignTurnSpace(sessionID: row.session, turnIndex: row.turn)
                try clearSpaceAssignmentPending(sessionID: row.session, turnIndex: row.turn)
                succeeded += 1
            } catch {
                // 同一个队行可能被两路重放同时认领：另一路已经判上并销账，
                // 这一路才撞上锁退出来。判上了就算成，别再记一笔欠账。
                if try turnHasRoomAssignment(sessionID: row.session, turnIndex: row.turn) {
                    try clearSpaceAssignmentPending(
                        sessionID: row.session, turnIndex: row.turn)
                    succeeded += 1
                    continue
                }
                stillPending += 1
                do {
                    try recordSpaceAssignmentFailure(
                        sessionID: row.session, turnIndex: row.turn, error: error, now: now)
                } catch {
                    // 连失败也记不下：锁还在别人手上。这一轮的次数**不涨**——
                    // 没记下来的失败不算一次尝试，额度留给真正能记的时候。
                    // 剩下的行这一轮也不再碰，免得空转。
                    break
                }
            }
        }
        // Count after processing so a row that fails its final allowed attempt
        // is reported as abandoned in this same run (and the scheduler can warn).
        let abandoned: Int
        do {
            let stmt = try prepare("""
            SELECT COUNT(*) FROM space_assignment_retry WHERE attempts>=?;
            """)
            defer { sqlite3_finalize(stmt) }
            try bind(stmt, 1, Int64(maxAttempts))
            guard try stepRowOrDone(stmt) else {
                throw DatabaseError.sql("retryPendingSpaceAssignments: abandoned count returned no row")
            }
            abandoned = Int(sqlite3_column_int64(stmt, 0))
        }

        return SpaceAssignmentRetryReport(
            retried: retried, succeeded: succeeded, stillPending: stillPending,
            deferred: deferred, abandoned: abandoned)
    }

    @discardableResult
    public func assignTurnSpaces(dryRun: Bool = false) throws -> TurnSpaceReport {
        try ensureRoomSchema()
        return try transactionResult {
            let (rules, titles) = try roomRules()

            var keywords: [TurnKey: [String]] = [:]
            if try tableExists("turn_keywords") {
                let stmt = try prepare("""
                SELECT tk.session_id, tk.turn_index, k.term
                  FROM turn_keywords tk JOIN keywords k USING(keyword_id);
                """)
                defer { sqlite3_finalize(stmt) }
                while try stepRowOrDone(stmt) {
                    func text(_ i: Int32) -> String {
                        sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
                    }
                    let key = TurnKey(session: text(0),
                                      turn: Int(sqlite3_column_int64(stmt, 1)))
                    keywords[key, default: []].append(text(2))
                }
            }

            var turns: [TurnKey] = []
            if try tableExists("turn_digests") {
                let stmt = try prepare("""
                SELECT session_id, turn_index FROM turn_digests
                 ORDER BY session_id, turn_index;
                """)
                defer { sqlite3_finalize(stmt) }
                while try stepRowOrDone(stmt) {
                    let session = sqlite3_column_text(stmt, 0)
                        .map { String(cString: $0) } ?? ""
                    turns.append(TurnKey(session: session,
                                         turn: Int(sqlite3_column_int64(stmt, 1))))
                }
            }

            var chosen: [TurnKey: [String: (room: String, by: String)]] = [:]
            var hits = 0
            for key in turns {
                let terms = keywords[key] ?? []
                var perAxis: [String: (n: Int, rule: RoomRule)] = [:]
                for rule in rules {
                    var n = 0
                    for term in terms where Self.ruleMatches(rule.regex, term) { n += 1 }
                    guard n > 0 else { continue }
                    if let best = perAxis[rule.axis], best.n >= n { continue }
                    perAxis[rule.axis] = (n, rule)
                }
                guard !perAxis.isEmpty else { continue }
                chosen[key] = perAxis.mapValues { ($0.rule.id, "content") }
                hits += 1
            }

            // 会话多数：给「本轮在该轴没命中」的轮次继承。按轴各算一份。
            var counters: [String: [String: Int]] = [:]
            for (key, perAxis) in chosen {
                for (axis, pick) in perAxis {
                    counters[key.session + "\u{1}" + axis, default: [:]][pick.room, default: 0] += 1
                }
            }
            var turnsPerSession: [String: Int] = [:]
            for key in turns { turnsPerSession[key.session, default: 0] += 1 }
            var majority: [String: String] = [:]
            for (key, counter) in counters {
                let ranked = counter.sorted {
                    $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
                }
                guard let top = ranked.first else { continue }
                let parts = key.split(separator: "\u{1}", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let session = String(parts[0])
                let share = Self.roomMajorityMinShare * Double(turnsPerSession[session] ?? 0)
                guard top.value >= Self.roomMajorityMinHits, Double(top.value) >= share else {
                    continue
                }
                majority[key] = top.key
            }

            for key in turns {
                var perAxis = chosen[key] ?? [:]
                for axis in ["project", "nature"] where perAxis[axis] == nil {
                    if let room = majority[key.session + "\u{1}" + axis] {
                        perAxis[axis] = (room, "inherit")
                    }
                }
                if perAxis.isEmpty {
                    perAxis["fallback"] = ("space-room-other", "other")
                }
                chosen[key] = perAxis
            }

            func tally() -> (rooms: [String: Int], sources: [String: Int]) {
                var rooms: [String: Int] = [:]
                var sources: [String: Int] = [:]
                for perAxis in chosen.values {
                    // 合并过的房间会同时占两条轴，落表时按 space_id 去重；
                    // 统计也按同一口径，否则报表比实际行数多。
                    var seen = Set<String>()
                    for pick in perAxis.values where seen.insert(pick.room).inserted {
                        rooms[titles[pick.room] ?? pick.room, default: 0] += 1
                        sources[pick.by, default: 0] += 1
                    }
                }
                return (rooms, sources)
            }

            if dryRun {
                let sum = tally()
                return TurnSpaceReport(
                    turns: turns.count, keywordHits: hits, rowsWritten: 0,
                    byRoom: sum.rooms, bySource: sum.sources, dryRun: true)
            }

            var ids: [String: String] = [:]
            for rule in rules where ids[rule.id] == nil {
                ids[rule.id] = try resolveRoom(id: rule.id, title: rule.title, axis: rule.axis)
            }
            ids["space-room-other"] = try resolveRoom(
                id: "space-room-other", title: "其他", axis: "fallback")

            let stamp = Self.stamp(Date())
            var written = 0
            // 有摘要的轮次全部先清空再重写：一轮的房间只由这一次判断决定，
            // 上一次的行（哪怕词变了、房间换了）不能并排留着。没有摘要的
            // 轮次不动——这一次判断不到它们，删了就是丢归属。
            beforeRoomRebuildWriteForTesting?()
            _ = try execBinding("""
            DELETE FROM space_turns
             WHERE EXISTS (SELECT 1 FROM turn_digests d
                            WHERE d.session_id=space_turns.session_id
                              AND d.turn_index=space_turns.turn_index);
            """) { _ in }
            let insert = try prepare("""
            INSERT INTO space_turns(
                session_id, turn_index, space_id, assigned_by, assigned_at)
            VALUES(?,?,?,?,?)
            ON CONFLICT(session_id, turn_index, space_id) DO UPDATE SET
                assigned_by=excluded.assigned_by, assigned_at=excluded.assigned_at;
            """)
            let byRank = ["content": 3, "other": 2, "inherit": 1]
            for (key, perAxis) in chosen {
                // 合并过的房间会同时占两条轴：一轮在同一房间只能有一行，
                // provenance 也只有一个——保留最硬的那个（content > other > inherit）。
                var rows: [String: String] = [:]
                for pick in perAxis.values {
                    let spaceID = ids[pick.room] ?? pick.room
                    if rows[spaceID] == nil
                        || (byRank[pick.by] ?? 0) > (byRank[rows[spaceID] ?? ""] ?? 0) {
                        rows[spaceID] = pick.by
                    }
                }
                for (spaceID, by) in rows {
                    sqlite3_reset(insert)
                    sqlite3_clear_bindings(insert)
                    try bind(insert, 1, key.session)
                    try bind(insert, 2, Int64(key.turn))
                    try bind(insert, 3, spaceID)
                    try bind(insert, 4, by)
                    try bind(insert, 5, stamp)
                    guard sqlite3_step(insert) == SQLITE_DONE else {
                        sqlite3_finalize(insert)
                        throw DatabaseError.sql("assignTurnSpaces: INSERT 未完成")
                    }
                    written += 1
                }
            }
            sqlite3_finalize(insert)

            // 全量重建已给每条带摘要的轮写过归属（#187）：待重试队列里的行
            // 全部过时，清空。重放上限不再是唯一的出队口，补录也是。
            let clear = try prepare("DELETE FROM space_assignment_retry;")
            defer { sqlite3_finalize(clear) }
            guard sqlite3_step(clear) == SQLITE_DONE else {
                throw DatabaseError.sql("assignTurnSpaces: 清空重试队列未完成")
            }

            let sum = tally()
            return TurnSpaceReport(
                turns: turns.count, keywordHits: hits, rowsWritten: written,
                byRoom: sum.rooms, bySource: sum.sources, dryRun: false)
        }
    }

    // MARK: - 来源时间回填

    /// `seen_at` 是导入批次时间（实测整库只差几分钟），排不出「7 月→8 月→…→11 月」
    /// 这条线。原始时间在源文件或会话 id 里。只写 `source_time`，不碰其他列。
    public struct SourceTimeReport: Equatable, Sendable {
        public let updated: Int
        public let missing: Int
        public let hitByPrefix: [String: Int]
        public let missByPrefix: [String: Int]
        /// 缺口的会话（前缀 + id → 缺几轮），够人说清「哪一批没对上」。
        public let missingSessions: [String: Int]
    }

    private static let cst = TimeZone(secondsFromGMT: 8 * 3600) ?? .current

    private static func isoUTC(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: date)
    }

    /// 本地（东八区）时刻 → UTC ISO。兼容 `2026-11-03T19-13-50`（rollout 文件名）
    /// 与 `2026-08-02T20:59:12`。只有日期（`2026-07-29`）时原样保留：那天是本地那天。
    private static func localToUTC(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = text.range(of: #"T(\d{2})-(\d{2})-(\d{2})$"#, options: .regularExpression) {
            let fixed = text[r].replacingOccurrences(of: "-", with: ":")
            text.replaceSubrange(r, with: fixed)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = cst
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = formatter.date(from: text) { return isoUTC(date) }
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: text) {
            _ = date
            return String(text.prefix(10))
        }
        return nil
    }

    /// Core Data 时间戳（2001-01-01 起秒，`seen_at` 就是这种）→ UTC ISO。
    private static func coreDataToUTC(_ raw: String) -> String? {
        guard let seconds = Double(raw) else { return nil }
        return isoUTC(Date(timeIntervalSinceReferenceDate: seconds))
    }

    /// 深寻的 `inserted_at`（`2025-01-28T02:17:33.787000+08:00`）→ UTC ISO。
    private static func offsetISOToUTC(_ raw: String) -> String? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return isoUTC(date) }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) { return isoUTC(date) }
        return nil
    }

    /// 深寻：`{会话 id: [每轮 REQUEST 的 inserted_at，按主链顺序]}`。
    private static func deepseekTimes(_ url: URL) -> [String: [String]] {
        guard let data = try? Data(contentsOf: url),
            let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [:] }
        var out: [String: [String]] = [:]
        for conversation in list {
            guard let id = conversation["id"] as? String,
                let mapping = conversation["mapping"] as? [String: [String: Any]]
            else { continue }
            var node = "root"
            var times: [String] = []
            while true {
                let children = (mapping[node]?["children"] as? [String] ?? [])
                    .filter { mapping[$0] != nil }
                guard let next = children.last else { break }
                node = next
                guard let message = mapping[node]?["message"] as? [String: Any] else {
                    continue
                }
                for fragment in message["fragments"] as? [[String: Any]] ?? []
                where fragment["type"] as? String == "REQUEST" {
                    if let stamp = fragment["content"] as? String, !stamp.isEmpty,
                        let when = message["inserted_at"] as? String,
                        let utc = offsetISOToUTC(when) {
                        times.append(utc)
                    }
                    break
                }
            }
            out[id] = times
        }
        return out
    }

    /// AI Studio：`chunkedPrompt.chunks[]` 里第 N 个带 text 的 user chunk 的 createTime。
    private static func aistudioTimes(_ url: URL) -> [String]? {
        guard let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let chunked = object["chunkedPrompt"] as? [String: Any],
            let chunks = chunked["chunks"] as? [[String: Any]]
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        var times: [String] = []
        for chunk in chunks where chunk["role"] as? String == "user" {
            guard let text = chunk["text"] as? String, !text.isEmpty,
                let created = chunk["createTime"] as? String,
                let date = formatter.date(from: String(created.prefix(19)))
            else { continue }
            times.append(isoUTC(date))
        }
        return times
    }

    /// codex rollout 文件名里的本地时刻：`rollout-2026-11-03T19-13-50-<uuid>.jsonl`。
    private static func codexRolloutTimes(_ roots: [URL]) -> [String: String] {
        var out: [String: String] = [:]
        let regex = try? NSRegularExpression(
            pattern: #"rollout-(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2})-(.+)\.jsonl(?:\.zst)?$"#)
        for root in roots {
            guard let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker {
                let name = url.lastPathComponent
                guard name.hasPrefix("rollout-"), let regex,
                    let match = regex.firstMatch(
                        in: name, range: NSRange(name.startIndex..., in: name)),
                    match.numberOfRanges == 3,
                    let when = Range(match.range(at: 1), in: name),
                    let key = Range(match.range(at: 2), in: name)
                else { continue }
                if out[String(name[key])] == nil { out[String(name[key])] = String(name[when]) }
            }
        }
        return out
    }

    /// 逐条轮账回填 `source_time`。六条来源：aistudio / deepseek / codex / qoder /
    /// flat-export / zcode。前两条要读源文件（导出目录是外部选择，不由这里猜），
    /// 没给目录就记成缺口，不假装对上。
    @discardableResult
    public func backfillSourceTimes(
        deepseekJSON: URL? = nil,
        aistudioDirectories: [URL] = [],
        codexSessionDirectories: [URL]? = nil
    ) throws -> SourceTimeReport {
        if try !columnExists("chat_turn_ledger", "source_time") {
            try Self.rawExec(
                handle, "ALTER TABLE chat_turn_ledger ADD COLUMN source_time TEXT;")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexRoots = codexSessionDirectories ?? [
            home.appendingPathComponent(".codex/sessions"),
            home.appendingPathComponent(".codex/archived_sessions"),
        ]
        let deepseek = deepseekJSON.map { Self.deepseekTimes($0) } ?? [:]
        let rollouts = Self.codexRolloutTimes(codexRoots)

        var ledger: [(session: String, turn: Int, seenAt: String)] = []
        do {
            let stmt = try prepare("""
            SELECT session_id, turn_index, COALESCE(seen_at,'')
              FROM chat_turn_ledger ORDER BY session_id, turn_index;
            """)
            defer { sqlite3_finalize(stmt) }
            while try stepRowOrDone(stmt) {
                ledger.append((
                    sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "",
                    Int(sqlite3_column_int64(stmt, 1)),
                    sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""))
            }
        }

        let dateRegex = try NSRegularExpression(pattern: #"codex-(\d{4}-\d{2}-\d{2})-"#)
        let compactRegex = try NSRegularExpression(
            pattern: #"codex-\S*?(\d{4})(\d{2})(\d{2})\b"#)
        let qoderRegex = try NSRegularExpression(pattern: #"-Qoder-(\d{4}-\d{2}-\d{2})-"#)
        let flatRegex = try NSRegularExpression(
            pattern: #"flat-export:(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})"#)

        func group(_ regex: NSRegularExpression, _ text: String, _ index: Int) -> String? {
            guard let match = regex.firstMatch(
                in: text, range: NSRange(text.startIndex..., in: text)),
                match.numberOfRanges > index,
                let r = Range(match.range(at: index), in: text) else { return nil }
            return String(text[r])
        }

        var hits: [String: Int] = [:]
        var misses: [String: Int] = [:]
        var missingSessions: [String: Int] = [:]
        var cache: [String: [String]?] = [:]
        var cursor: String?

        for row in ledger {
            let prefix: String
            if let colon = row.session.firstIndex(of: ":") {
                prefix = String(row.session[row.session.startIndex..<colon])
            } else if let dash = row.session.firstIndex(of: "-") {
                prefix = String(row.session[row.session.startIndex..<dash])
            } else {
                prefix = row.session
            }
            var when: String?
            switch prefix {
            case "aistudio":
                let parts = row.session.split(separator: ":", maxSplits: 1)
                let title = parts.count > 1 ? String(parts[1]) : ""
                if row.session != cursor {
                    cursor = row.session
                }
                guard !title.isEmpty else { break }
                let times: [String]?
                if let cached = cache[title] {
                    times = cached
                } else if aistudioDirectories.isEmpty {
                    times = nil
                } else {
                    var found: [String]?
                    for dir in aistudioDirectories {
                        let path = dir.appendingPathComponent(title)
                        if FileManager.default.fileExists(atPath: path.path) {
                            found = Self.aistudioTimes(path)
                            break
                        }
                    }
                    cache[title] = found
                    times = found
                }
                if let times, row.turn >= 1, row.turn - 1 < times.count {
                    when = times[row.turn - 1]
                }
            case "deepseek":
                let parts = row.session.split(separator: ":", maxSplits: 1)
                let key = parts.count > 1 ? String(parts[1]) : ""
                if let times = deepseek[key], row.turn >= 1, row.turn - 1 < times.count {
                    when = times[row.turn - 1]
                }
            case "codex":
                if let day = group(dateRegex, row.session, 1) {
                    when = day
                } else if let match = rollouts.first(where: {
                    !$0.key.isEmpty && row.session.contains($0.key)
                }) {
                    when = Self.localToUTC(match.value)
                } else if let y = group(compactRegex, row.session, 1),
                    let m = group(compactRegex, row.session, 2),
                    let d = group(compactRegex, row.session, 3) {
                    when = Self.localToUTC("\(y)-\(m)-\(d)")
                }
                if when == nil { when = Self.coreDataToUTC(row.seenAt) }
            case "qoder":
                when = group(qoderRegex, row.session, 1)
                    ?? Self.coreDataToUTC(row.seenAt)
            case "flat-export":
                if let y = group(flatRegex, row.session, 1),
                    let mo = group(flatRegex, row.session, 2),
                    let d = group(flatRegex, row.session, 3),
                    let h = group(flatRegex, row.session, 4),
                    let mi = group(flatRegex, row.session, 5),
                    let s = group(flatRegex, row.session, 6) {
                    when = Self.localToUTC("\(y)-\(mo)-\(d)T\(h):\(mi):\(s)")
                }
            case "zcode":
                when = Self.coreDataToUTC(row.seenAt)
            default:
                when = nil
            }

            if let when {
                _ = try execBinding("""
                UPDATE chat_turn_ledger SET source_time=?
                 WHERE session_id=? AND turn_index=?;
                """) {
                    try bind($0, 1, when)
                    try bind($0, 2, row.session)
                    try bind($0, 3, Int64(row.turn))
                }
                hits[prefix, default: 0] += 1
            } else {
                misses[prefix, default: 0] += 1
                missingSessions["\(prefix)·\(row.session)", default: 0] += 1
            }
        }

        return SourceTimeReport(
            updated: hits.values.reduce(0, +),
            missing: misses.values.reduce(0, +),
            hitByPrefix: hits, missByPrefix: misses,
            missingSessions: missingSessions)
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
        /// True when the pass built only a physical index (locator/digest/size)
        /// and did not copy entity bytes into the object store.
        public let indexOnly: Bool
        /// Bytes read from the filesystem to compute digests / validate text.
        /// These are read-only; `bytesAddressed` stays the copy measure.
        public let entityBytesRead: Int
        /// The path still exists but answers with a different directory inode:
        /// a mount was replaced, a bind mount appeared, or the volume changed.
        /// Nothing was removed or invalidated on this pass — the inventory was
        /// not trusted as evidence of absence.
        public let locatorIdentityChanged: Bool
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
        let size: Int64
        let modified: String?
        /// The source's own timestamp for this version. This is the world clock
        /// the interval is expressed in; `recorded_at` is when ES saw it.
        let modifiedDate: Date?
        let previous: FileContentState?
        /// Raw bytes read for a tail-window digest, before dropping a partial line.
        let tailWindowBytes: Int?
    }

    /// 结算一个工作根：逐文件计算 SHA-256，内容写入内容寻址对象库
    /// （相同字节只存一次），`file_contents` 只保留身份/摘要引用；索引与
    /// 依赖账本追加记录，历史不覆盖。删除或变为二进制/超限的文件会撤销
    /// 其内容引用并失效依赖闭包。文本判定：utf8 且 ≤ fileByteCap。
    /// Root-wide guards default to 16,384 visited entries, 4,096 regular files,
    /// and 64 MiB of bytes read. The aggregate read cap also bounds Data retained
    /// in pending settlements.
    @discardableResult
    public func settleWorkRootContents(
        rootID: String, rootURL: URL, category: String = "work",
        fileByteCap: Int = 1 << 20, tailBytes: Int = 256 << 10, maxDepth: Int = 4,
        maxObservedFiles: Int = 4_096,
        maxVisitedEntries: Int = 16_384,
        maxTotalBytesRead: Int = 64 * 1024 * 1024,
        carryText: Bool = true
    ) throws -> ContentSettleReport {
        // Serialize the baseline snapshot, filesystem observation and all index
        // mutations. Otherwise two overlapping scans can commit in reverse order
        // and let an older observation overwrite a newer settlement.
        return try transactionResult {
        let fm = FileManager.default
        guard fileByteCap >= 0, tailBytes >= 0, maxDepth > 0,
              maxObservedFiles >= 0, maxObservedFiles < Int.max,
              maxVisitedEntries >= 0, maxTotalBytesRead >= 0 else {
            throw DatabaseError.sql("settleWorkRootContents: invalid scan limits")
        }
        let inventoryRowLimit = Int64(maxObservedFiles) + 1
        let requestedRootPath = try canonicalDirectoryPath(atPath: rootURL.path)
        let requestedRoot = URL(fileURLWithPath: requestedRootPath, isDirectory: true)
        let scanRoot: URL
        if let registeredPath = try rootLocatorPath(rootID) {
            let registeredRoot = URL(fileURLWithPath: registeredPath).standardizedFileURL
            guard registeredRoot.path == requestedRoot.path else {
                throw DatabaseError.sql(
                    "settleWorkRootContents: registered root locator changed for \(rootID)")
            }
            scanRoot = registeredRoot
        } else {
            scanRoot = requestedRoot
        }
        let rootDirectoryFD = try openDirectoryNoFollow(atPath: scanRoot.path)
        defer { Darwin.close(rootDirectoryFD) }
        // file_contents references roots, so the root must exist before any
        // content row is written (new roots start here, not in the index pass).
        // Recording the absolute path here is what makes the locator evidence
        // durable: later metadata-only upserts must not erase it.
        try upsertRoot(rootID: rootID, category: category,
                       displayName: scanRoot.path,
                       locatorType: "path", status: "present")
        // 同一个路径换了目录：挂载被替换、bind mount、整个卷换掉，都会长这样。
        // 这时「看不到文件」不是删除，后面的清账一步都不许做。
        let locatorIdentityChanged = try noteLocatorIdentity(
            rootID: rootID, path: scanRoot.path)
        if locatorIdentityChanged {
            // The caller must explicitly adopt this physical directory with
            // adoptRootLocatorIdentity before any bytes can be settled under
            // the existing root ID. Merely suppressing removals is insufficient:
            // a same-relative-path file could otherwise overwrite the old
            // digest and invalidate the old root's dependent settlements.
            return ContentSettleReport(
                scanned: 0, reused: 0, settled: 0,
                skippedBinaryOrLarge: 0, changed: 0, removed: 0,
                invalidatedSettlements: 0, objectsCreated: 0,
                deduplicated: 0, bytesAddressed: 0,
                indexOnly: !carryText, entityBytesRead: 0,
                locatorIdentityChanged: true)
        }
        var previous: [String: FileContentState] = [:]
        let prevStmt = try prepare("""
        SELECT relative_path, content_sha256, object_id FROM file_contents
        WHERE root_id=? ORDER BY relative_path LIMIT ?;
        """)
        defer { sqlite3_finalize(prevStmt) }
try bind(prevStmt, 1, rootID)
        try bind(prevStmt, 2, inventoryRowLimit)
        while try stepRowOrDone(prevStmt) {
            func text(_ i: Int32) -> String {
                sqlite3_column_text(prevStmt, i).map { String(cString: $0) } ?? ""
            }
            previous[text(0)] = FileContentState(
                digest: text(1),
                objectID: sqlite3_column_type(prevStmt, 2) == SQLITE_NULL ? nil : text(2))
        }
        guard previous.count <= maxObservedFiles else {
            throw DatabaseError.sql(
                "settleWorkRootContents: prior file_contents inventory exceeds maxObservedFiles (\(maxObservedFiles))")
        }

        // Some indexed files (binary, oversized, or non-UTF8) intentionally
        // have no file_contents row. Keep their external-file inventory too,
        // otherwise a later root scan cannot detect their disappearance.
        var previousExternalFiles: [String: String] = [:]
        do {
            let externalStmt = try prepare("""
            SELECT relative_path, content_digest FROM external_files
            WHERE root_id=? AND COALESCE(status,'present')<>'missing'
            ORDER BY relative_path LIMIT ?;
            """)
            defer { sqlite3_finalize(externalStmt) }
try bind(externalStmt, 1, rootID)
            try bind(externalStmt, 2, inventoryRowLimit)
            while true {
                let rc = sqlite3_step(externalStmt)
                if rc == SQLITE_ROW {
                    guard let path = sqlite3_column_text(externalStmt, 0) else {
                        throw DatabaseError.sql("external_files contains a NULL relative_path")
                    }
                    let relativePath = String(cString: path)
                    let digest = sqlite3_column_text(externalStmt, 1)
                        .map { String(cString: $0) } ?? ""
                    previousExternalFiles[relativePath] = digest
                    continue
                }
                guard rc == SQLITE_DONE else {
                    throw Self.sqliteFailure(handle, resultCode: rc)
                }
                break
            }
            guard previousExternalFiles.count <= maxObservedFiles else {
                throw DatabaseError.sql(
                    "settleWorkRootContents: prior external_files inventory exceeds maxObservedFiles (\(maxObservedFiles))")
            }
        }

        var scanned = 0, reused = 0, skipped = 0
        var visitedEntries = 0
        var entityBytesRead = 0
        var seen = Set<String>()
        var pending: [PendingSettlement] = []
        var cleared: [(relativePath: String, previous: FileContentState, missing: Bool)] = []
        var indexedFiles: [(rel: String, url: URL, size: Int64, modified: String?, digest: String?)] = []
        let modifiedFormatter = ISO8601DateFormatter()

        var enumerationFailure: (path: String, message: String)?
        guard let enumerator = fm.enumerator(
            at: scanRoot,
            includingPropertiesForKeys: [
                .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, error in
                if enumerationFailure == nil {
                    enumerationFailure = (url.path, error.localizedDescription)
                }
                // A skipped subtree would make the observed path set incomplete.
                return false
            })
        else {
            // Enumerating an unreadable root must not look like "every file was
            // deleted" — that would strand the carried content behind a mass
            // invalidation. Refuse and leave the previous settlement intact.
            throw DatabaseError.sql(
                "settleWorkRootContents: cannot enumerate root \(rootID)")
        }
        while let file = enumerator.nextObject() as? URL {
            visitedEntries += 1
            guard visitedEntries <= maxVisitedEntries else {
                throw DatabaseError.sql(
                    "settleWorkRootContents: maxVisitedEntries exceeded (\(maxVisitedEntries))")
            }
            var enumeratedInfo = stat()
            let lstatResult = file.path.withCString { Darwin.lstat($0, &enumeratedInfo) }
            guard lstatResult == 0 else {
                throw DatabaseError.sql(
                    "settleWorkRootContents: cannot inspect \(file.path): \(String(cString: strerror(errno)))")
            }
            let relative = relativePath(of: file, under: scanRoot)
            let fileType = enumeratedInfo.st_mode & S_IFMT
            if fileType == S_IFDIR {
                if !relative.isEmpty,
                   relative.split(separator: "/").count >= maxDepth {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard !relative.isEmpty,
                  relative.split(separator: "/").count <= maxDepth else { continue }
            guard fileType == S_IFREG else {
                throw DatabaseError.sql(
                    "settleWorkRootContents: refuses symbolic or non-regular source \(relative)")
            }
            guard scanned < maxObservedFiles else {
                throw DatabaseError.sql(
                    "settleWorkRootContents: maxObservedFiles exceeded (\(maxObservedFiles))")
            }
            let enumeratedSize = Int64(enumeratedInfo.st_size)
            guard enumeratedSize >= 0 else {
                throw DatabaseError.sql(
                    "settleWorkRootContents: negative source size for \(relative)")
            }
            let remainingBytes = maxTotalBytesRead - entityBytesRead
            if enumeratedSize <= Int64(fileByteCap) {
                guard enumeratedSize <= Int64(remainingBytes) else {
                    throw DatabaseError.sql(
                        "settleWorkRootContents: maxTotalBytesRead exceeded (\(maxTotalBytesRead))")
                }
            }

            // Every component is opened relative to the pinned root FD; no
            // symlink can redirect either an intermediate directory or the leaf.
            // The helper also checks the opened file's fstat size against the
            // remaining aggregate budget, not only this earlier lstat snapshot.
            let read = try readRootFileNoFollow(
                rootDirectoryFD: rootDirectoryFD,
                relativePath: relative,
                maximumBytes: fileByteCap,
                tailBytes: tailBytes,
                maximumTotalBytesRead: remainingBytes)
            guard read.device == Int64(enumeratedInfo.st_dev),
                  read.inode == UInt64(enumeratedInfo.st_ino) else {
                throw DatabaseError.sql(
                    "settleWorkRootContents: source changed during scan: \(relative)")
            }

            scanned += 1
            seen.insert(relative)
            let size = read.size
            let modified = read.modificationDate.map {
                modifiedFormatter.string(from: $0)
            }
            guard let data = read.data else {
                skipped += 1
                indexedFiles.append((relative, file, size, modified, nil))
                if let old = previous[relative] {
                    cleared.append((relative, old, false))
                }
                continue
            }

            // A tail window is not the whole document: bind the digest to the
            // file's size so an append always reads as a change, and so a tail
            // digest can never collide with a whole-file digest of the same
            // bytes.
            let indexedData = read.isTail ? Self.indexedTailData(data) : data
            let digest = read.isTail
                ? NativeSHA256.hexDigest(Data("tail:\(size):".utf8) + indexedData)
                : NativeSHA256.hexDigest(indexedData)
            let nextEntityBytesRead = entityBytesRead.addingReportingOverflow(data.count)
            guard !nextEntityBytesRead.overflow,
                  nextEntityBytesRead.partialValue <= maxTotalBytesRead else {
                throw DatabaseError.sql(
                    "settleWorkRootContents: maxTotalBytesRead exceeded (\(maxTotalBytesRead))")
            }
            entityBytesRead = nextEntityBytesRead.partialValue
            indexedFiles.append((relative, file, size, modified, digest))
            guard String(data: indexedData, encoding: .utf8) != nil else {
                skipped += 1
                if let old = previous[relative] {
                    cleared.append((relative, old, false))
                }
                continue
            }
            if let old = previous[relative], old.digest == digest,
                carryText ? old.objectID != nil : old.objectID == nil
            {
                reused += 1
                continue
            }
            pending.append(PendingSettlement(
                relativePath: relative, url: file, data: indexedData, digest: digest,
                size: size, modified: modified, modifiedDate: read.modificationDate,
                previous: previous[relative],
                tailWindowBytes: read.isTail ? data.count : nil))
        }

        // Enumeration errors can occur after some descendants were yielded.
        // Abort before computing removals or opening the settlement transaction.
        if let failure = enumerationFailure {
            throw DatabaseError.sql(
                "settleWorkRootContents: cannot enumerate \(failure.path): \(failure.message)")
        }

        // Enumeration uses the canonical path while file reads use the pinned
        // descriptor. If that path was replaced after the initial identity
        // check, an empty successor directory could otherwise look like every
        // old file disappeared. Verify the path still names the pinned root
        // before interpreting the observed set as an inventory.
        let afterEnumerationHook = afterRootEnumerationForTesting
        afterRootEnumerationForTesting = nil
        afterEnumerationHook?()
        try verifyRootDescriptorStillNamed(rootDirectoryFD, path: scanRoot.path)

        // Indexed rows whose file disappeared from the latest scan. The
        // file_contents snapshot misses intentionally uncarried files, so also
        // reconcile every previously-present external_files path.
        var removed = 0
        var clearedPaths = Set<String>()
        for (rel, old) in previous where !seen.contains(rel) {
            cleared.append((rel, old, true))
            clearedPaths.insert(rel)
            removed += 1
        }
        for (rel, digest) in previousExternalFiles
        where !seen.contains(rel) && !clearedPaths.contains(rel) {
            cleared.append((
                rel, FileContentState(digest: digest, objectID: nil), true))
            clearedPaths.insert(rel)
            removed += 1
        }
        // 不是这个目录了：整份旧清单都不作数。不删 file_contents、不标
        // missing、不作废结算，只把这件事报出去，等人确认。
        if locatorIdentityChanged {
            cleared.removeAll()
            removed = 0
        }

        var invalidated = Set<String>()
        var created = 0, deduplicated = 0, bytesAddressed = 0
        let now = Self.stamp(Date())

            for item in cleared {
                invalidated.formUnion(try affectedClosure(
                    rootID: rootID, relativePath: item.relativePath))
                try invalidateRetrievalSettlementsInTransaction(
                    rootID: rootID, relativePath: item.relativePath,
                    oldDigest: item.previous.digest)
                // The carried content is kept on purpose: a cleared path means
                // the source was not observed, not that the information never
                // existed. Deleting it would erase the only read path retrieval
                // has (see `reconcileRoot`).
                try execBinding("""
                UPDATE information_items SET state='STALE', updated_at=?
                WHERE item_id=?;
                """) { stmt in
                    try bind(stmt, 1, now)
                    try bind(stmt, 2, "file:\(rootID)/\(item.relativePath)")
                }
                if item.missing {
                    try execBinding("""
                    UPDATE external_files SET status='missing'
                    WHERE root_id=? AND relative_path=?;
                    """) { stmt in
                        try bind(stmt, 1, rootID)
                        try bind(stmt, 2, item.relativePath)
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
                // Index-only mode stores a locator/digest/size record, never the
                // entity bytes. The object appended to the carrier ledger is that
                // metadata record, so the physical file stays the single copy of
                // its own content. carryText keeps the explicit carrier mode.
                let identity = "file:\(rootID)/\(item.relativePath)"
                let indexObject: (id: String, created: Bool)
                if carryText {
                    indexObject = try ensureObjectWithStatus(item.data)
                    bytesAddressed += item.data.count
                } else {
                    var metadata: [String: Any] = [
                        "locator": identity,
                        "sha256": item.digest,
                        "size": item.size,
                        "is_tail": item.tailWindowBytes != nil,
                    ]
                    if let tailWindowBytes = item.tailWindowBytes {
                        metadata["tail_bytes"] = tailWindowBytes
                    }
                    if let modified = item.modified { metadata["modified"] = modified }
                    let encoded = try JSONSerialization.data(
                        withJSONObject: metadata,
                        options: [.sortedKeys, .withoutEscapingSlashes])
                    indexObject = try ensureObjectWithStatus(encoded)
                }
                if indexObject.created { created += 1 } else { deduplicated += 1 }
                try execBinding("""
                INSERT INTO file_contents(
                    root_id, relative_path, content_sha256, content, settled_at, object_id)
                VALUES(?,?,?,'',?,?)
                ON CONFLICT(root_id, relative_path) DO UPDATE SET
                    content_sha256=excluded.content_sha256, content='',
                    settled_at=excluded.settled_at, object_id=excluded.object_id;
                """) { stmt in
                    try bind(stmt, 1, rootID)
                    try bind(stmt, 2, item.relativePath)
                    try bind(stmt, 3, item.digest)
                    try bind(stmt, 4, now)
                    if carryText {
                        try bind(stmt, 5, indexObject.id)
                    } else {
                        try bindNull(stmt, 5)
                    }
                }
                try execBinding("""
                INSERT INTO information_items(
                    item_id, kind, locator, source_version, source_payload_sha256, state, updated_at)
                VALUES(?,?,?,?,?,'AVAILABLE',?)
                ON CONFLICT(item_id) DO UPDATE SET
                    source_version=excluded.source_version,
                    source_payload_sha256=excluded.source_payload_sha256,
                    state='AVAILABLE', updated_at=excluded.updated_at;
                """) { stmt in
                    try bind(stmt, 1, identity)
                    try bind(stmt, 2, "file")
                    try bind(stmt, 3, item.url.path)
                    try bind(stmt, 4, item.modified ?? item.digest)
                    try bind(stmt, 5, item.digest)
                    try bind(stmt, 6, now)
                }
                _ = try appendIndexEntryInTransaction(
                    identity: identity, objectID: indexObject.id)
                _ = try appendDependencyInTransaction(
                    dependencyID: identity, contentAddress: indexObject.id,
                    reason: item.previous == nil ? "content-settle" : "content-update",
                    sourceTime: item.modifiedDate.map(Self.stamp))
            }

            for file in indexedFiles {
                try indexExternalFile(
                    rootID: rootID, category: category,
                    relativePath: file.rel,
                    kind: file.url.pathExtension.isEmpty ? nil : file.url.pathExtension,
                    size: file.size, modifiedAt: file.modified,
                    contentDigest: file.digest)
            }
            try markSettlementsInvalidInTransaction(
                Array(invalidated), cause: "source-changed:\(rootID)")
            try markRootScanned(rootID)

            // Recheck after all source reads and writes, not only after
            // enumeration. A path replacement in the reconciliation window
            // must roll back the entire inventory publication as well.
            let beforeCommitHook = beforeRootScanCommitForTesting
            beforeRootScanCommitForTesting = nil
            beforeCommitHook?()
            try verifyDirectoryPathMatchesDescriptor(rootDirectoryFD, atPath: scanRoot.path)

        return ContentSettleReport(
            scanned: scanned, reused: reused, settled: pending.count,
            skippedBinaryOrLarge: skipped,
            changed: pending.filter { $0.previous != nil }.count,
            removed: removed, invalidatedSettlements: invalidated.count,
            objectsCreated: created, deduplicated: deduplicated,
            bytesAddressed: bytesAddressed,
            indexOnly: !carryText, entityBytesRead: entityBytesRead,
            locatorIdentityChanged: locatorIdentityChanged)
        }
    }

    private struct NoFollowFileRead {
        let data: Data?
        let size: Int64
        let modificationDate: Date?
        let modificationNanoseconds: Int64
        let device: Int64
        let inode: UInt64
        /// True when `data` is the last `tailBytes` of a file that exceeded
        /// the whole-file cap. The digest then covers (size, tail), so an
        /// append still changes it.
        var isTail: Bool = false
    }

    /// The tail index discards its first possibly partial line identically
    /// during settlement and later source revalidation.
    private static func indexedTailData(_ rawData: Data) -> Data {
        guard let firstBreak = rawData.firstIndex(of: 0x0A) else { return rawData }
        return rawData[rawData.index(after: firstBreak)...]
    }

    private func canonicalDirectoryPath(atPath path: String) throws -> String {
        let resolved = path.withCString { Darwin.realpath($0, nil) }
        guard let resolved else {
            let code = errno
            if code == ENOENT || code == ENOTDIR {
                throw DatabaseError.sourceGone(path: path)
            }
            throw DatabaseError.sql(
                "canonicalDirectoryPath: \(String(cString: strerror(code)))")
        }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
            .standardizedFileURL.path
    }

    private func openDirectoryNoFollow(atPath path: String) throws -> Int32 {
        let canonicalPath = try canonicalDirectoryPath(atPath: path)
        guard canonicalPath == URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL.path else {
            throw DatabaseError.sql(
                "openDirectoryNoFollow: registered directory path now resolves elsewhere")
        }

        // macOS temporary roots can traverse APFS firmlink/alias components
        // which are canonicalized by realpath but are not all traversable via
        // a strict component-by-component O_NOFOLLOW walk. Resolve once, then
        // bind the opened directory descriptor to the exact lstat identity of
        // that canonical leaf. Descendant paths remain component-wise no-follow.
        var pathInfo = stat()
        let statResult = canonicalPath.withCString { Darwin.lstat($0, &pathInfo) }
        guard statResult == 0, (pathInfo.st_mode & S_IFMT) == S_IFDIR else {
            let code = errno
            throw DatabaseError.sql(
                "openDirectoryNoFollow: canonical root is not a directory: \(String(cString: strerror(code)))")
        }
        let descriptor = canonicalPath.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            let code = errno
            throw DatabaseError.sql(
                "openDirectoryNoFollow: canonical root open failed: \(String(cString: strerror(code)))")
        }
        var openedInfo = stat()
        guard Darwin.fstat(descriptor, &openedInfo) == 0,
              (openedInfo.st_mode & S_IFMT) == S_IFDIR,
              openedInfo.st_dev == pathInfo.st_dev,
              openedInfo.st_ino == pathInfo.st_ino else {
            let code = errno
            Darwin.close(descriptor)
            throw DatabaseError.sql(
                "openDirectoryNoFollow: canonical root identity changed: \(String(cString: strerror(code)))")
        }
        return descriptor
    }

    private func verifyRootDescriptorStillNamed(_ descriptor: Int32, path: String) throws {
        var opened = stat()
        guard Darwin.fstat(descriptor, &opened) == 0 else {
            let code = errno
            throw DatabaseError.sql(
                "verifyRootDescriptorStillNamed: fstat failed: \(String(cString: strerror(code)))")
        }
        var current = stat()
        let result = path.withCString { Darwin.lstat($0, &current) }
        guard result == 0 else {
            let code = errno
            throw DatabaseError.sql(
                "verifyRootDescriptorStillNamed: lstat failed: \(String(cString: strerror(code)))")
        }
        guard (current.st_mode & S_IFMT) == S_IFDIR,
              opened.st_dev == current.st_dev,
              opened.st_ino == current.st_ino else {
            throw DatabaseError.sql(
                "verifyRootDescriptorStillNamed: root path changed during capture")
        }
    }

    private func readRootFileNoFollow(
        rootDirectoryFD: Int32,
        relativePath: String,
        maximumBytes: Int?,
        tailBytes: Int? = nil,
        maximumTotalBytesRead: Int = Int.max
    ) throws -> NoFollowFileRead {
        if let maximumBytes, maximumBytes < 0 {
            throw DatabaseError.sql("readRootFileNoFollow: negative byte limit")
        }
        guard maximumTotalBytesRead >= 0 else {
            throw DatabaseError.sql("readRootFileNoFollow: negative aggregate byte limit")
        }
        let components = relativePath.split(
            separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw DatabaseError.sql("readRootFileNoFollow: invalid relative path")
        }

        var parentFD = Darwin.dup(rootDirectoryFD)
        guard parentFD >= 0 else {
            throw DatabaseError.sql(
                "readRootFileNoFollow: dup failed: \(String(cString: strerror(errno)))")
        }
        for component in components.dropLast() {
            let next = String(component).withCString {
                Darwin.openat(
                    parentFD, $0,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            }
            guard next >= 0 else {
                let code = errno
                Darwin.close(parentFD)
                if code == ENOENT || code == ENOTDIR {
                    throw DatabaseError.sourceGone(path: relativePath)
                }
                throw DatabaseError.sql(
                    "readRootFileNoFollow: parent is unavailable or symlinked: \(String(cString: strerror(code)))")
            }
            Darwin.close(parentFD)
            parentFD = next
        }

        let leaf = String(components[components.count - 1])
        let fileFD = leaf.withCString {
            Darwin.openat(
                parentFD, $0,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        }
        let openError = errno
        Darwin.close(parentFD)
        guard fileFD >= 0 else {
            if openError == ENOENT || openError == ENOTDIR {
                throw DatabaseError.sourceGone(path: relativePath)
            }
            throw DatabaseError.sql(
                "readRootFileNoFollow: leaf is unavailable or symlinked: \(String(cString: strerror(openError)))")
        }
        defer { Darwin.close(fileFD) }

        var initial = stat()
        guard Darwin.fstat(fileFD, &initial) == 0,
              (initial.st_mode & S_IFMT) == S_IFREG,
              initial.st_size >= 0 else {
            throw DatabaseError.sql("readRootFileNoFollow: source is not a regular file")
        }
        let device = Int64(initial.st_dev)
        let inode = UInt64(initial.st_ino)
        let modificationDate = Date(
            timeIntervalSince1970: Double(initial.st_mtimespec.tv_sec)
                + Double(initial.st_mtimespec.tv_nsec) / 1_000_000_000)
        let initialSize = Int64(initial.st_size)
        let modificationNanoseconds =
            Int64(initial.st_mtimespec.tv_sec) * 1_000_000_000
            + Int64(initial.st_mtimespec.tv_nsec)

        func rereadWindow(
            from offset: off_t, byteCount: Int) -> Data? {
            var fresh = Data()
            fresh.reserveCapacity(byteCount)
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while fresh.count < byteCount {
                let requestCount = min(buffer.count, byteCount - fresh.count)
                let amount = buffer.withUnsafeMutableBytes { raw -> Int in
                    guard let base = raw.baseAddress else { return -1 }
                    return Darwin.pread(fileFD, base, requestCount, offset + off_t(fresh.count))
                }
                if amount < 0 && errno == EINTR { continue }
                guard amount > 0 else { return nil }
                fresh.append(contentsOf: buffer.prefix(amount))
            }
            return fresh
        }

        func verifyUnchanged(
            recheck readBytes: Data? = nil,
            windowStart: off_t = 0) throws {
            // 挂牌（过渡措施，非契约）：本校验只在「结算仍要读盘」时成立——它守的是
            // 这次 read 的字节没被并发改写，不回答「这条值现在还可不可信」。等结算
            // 不再读盘（内容进对象库、依赖按内容判同）时，verifyUnchanged 与
            // rereadWindow 一并删除。见 #147。
            if let hook = beforeRootFileVerificationForTesting {
                beforeRootFileVerificationForTesting = nil
                hook()
            }
            var finalInfo = stat()
            guard Darwin.fstat(fileFD, &finalInfo) == 0 else {
                throw DatabaseError.sql(
                    "readRootFileNoFollow: final fstat failed: \(String(cString: strerror(errno)))")
            }
            guard finalInfo.st_dev == initial.st_dev,
                  finalInfo.st_ino == initial.st_ino,
                  finalInfo.st_size == initial.st_size,
                  finalInfo.st_mtimespec.tv_sec == initial.st_mtimespec.tv_sec,
                  finalInfo.st_mtimespec.tv_nsec == initial.st_mtimespec.tv_nsec else {
                throw DatabaseError.sourceChangedWhileBeingRead(path: relativePath)
            }
            let ctOK = finalInfo.st_ctimespec.tv_sec == initial.st_ctimespec.tv_sec
                && finalInfo.st_ctimespec.tv_nsec == initial.st_ctimespec.tv_nsec
            if ctOK { return }
            // ctime moves for metadata too — rename, link, chmod — so a bare
            // ctime change cannot tell a same-size rewrite (mtime restored, the
            // #146 case) from an untouched file whose inode was merely renamed.
            // Decide on bytes: re-read this exact window and require the content
            // we indexed, then require ctime to have held across that re-read.
            guard let readBytes, let fresh = rereadWindow(
                from: windowStart, byteCount: readBytes.count), fresh == readBytes else {
                throw DatabaseError.sourceChangedWhileBeingRead(path: relativePath)
            }
            var afterReread = stat()
            guard Darwin.fstat(fileFD, &afterReread) == 0 else {
                throw DatabaseError.sql(
                    "readRootFileNoFollow: post-reread fstat failed: \(String(cString: strerror(errno)))")
            }
            guard afterReread.st_ctimespec.tv_sec == finalInfo.st_ctimespec.tv_sec,
                  afterReread.st_ctimespec.tv_nsec == finalInfo.st_ctimespec.tv_nsec else {
                throw DatabaseError.sourceChangedWhileBeingRead(path: relativePath)
            }
        }

        if let maximumBytes, initialSize > Int64(maximumBytes) {
            // Append-only logs (agent session transcripts) grow past any cap;
            // the last window still answers "what was said recently", and the
            // ledger keeps its own full-size + digest bookkeeping. Callers that
            // do not ask for a tail window index the file without its bytes.
            guard let tailBytes, tailBytes > 0 else {
                try verifyUnchanged()
                return NoFollowFileRead(
                    data: nil, size: initialSize,
                    modificationDate: modificationDate, modificationNanoseconds: modificationNanoseconds, device: device, inode: inode)
            }
            let expectedByteCount = Int(min(initialSize, Int64(tailBytes)))
            guard expectedByteCount <= maximumTotalBytesRead else {
                throw DatabaseError.sql(
                    "settleWorkRootContents: maxTotalBytesRead exceeded (\(maximumTotalBytesRead))")
            }
            let start = initialSize - Int64(expectedByteCount)
            guard Darwin.lseek(fileFD, off_t(start), SEEK_SET) == off_t(start) else {
                throw DatabaseError.sql(
                    "readRootFileNoFollow: seek failed: \(String(cString: strerror(errno)))")
            }
            var tail = Data()
            tail.reserveCapacity(expectedByteCount)
            var tailBuffer = [UInt8](repeating: 0, count: 64 * 1024)
            while tail.count < expectedByteCount {
                let requestCount = min(tailBuffer.count, expectedByteCount - tail.count)
                let amount = tailBuffer.withUnsafeMutableBytes { raw -> Int in
                    guard let base = raw.baseAddress else { return -1 }
                    return Darwin.read(fileFD, base, requestCount)
                }
                if amount < 0 && errno == EINTR { continue }
                guard amount >= 0 else {
                    throw DatabaseError.sql(
                        "readRootFileNoFollow: read failed: \(String(cString: strerror(errno)))")
                }
                if amount == 0 {
                    try verifyUnchanged()
                    throw DatabaseError.sql(
                        "readRootFileNoFollow: short or inconsistent tail read")
                }
                tail.append(contentsOf: tailBuffer.prefix(amount))
            }
            try verifyUnchanged(recheck: tail, windowStart: off_t(start))
            guard tail.count == expectedByteCount else {
                throw DatabaseError.sql(
                    "readRootFileNoFollow: short or inconsistent tail read")
            }
            return NoFollowFileRead(
                data: tail, size: initialSize,
                modificationDate: modificationDate, modificationNanoseconds: modificationNanoseconds, device: device, inode: inode,
                isTail: true)
        }
        guard initialSize <= Int64(maximumTotalBytesRead) else {
            throw DatabaseError.sql(
                "settleWorkRootContents: maxTotalBytesRead exceeded (\(maximumTotalBytesRead))")
        }

        // Read exactly the size observed by fstat. Reading until EOF can consume
        // unbounded extra bytes if a file grows concurrently; the final fstat
        // rejects that mutation after at most the budgeted initial size is read.
        let expectedByteCount = Int(initialSize)
        var data = Data()
        data.reserveCapacity(expectedByteCount)
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count < expectedByteCount {
            let requestCount = min(buffer.count, expectedByteCount - data.count)
            let amount = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.read(fileFD, base, requestCount)
            }
            if amount < 0 && errno == EINTR { continue }
            guard amount >= 0 else {
                throw DatabaseError.sql(
                    "readRootFileNoFollow: read failed: \(String(cString: strerror(errno)))")
            }
            if amount == 0 {
                try verifyUnchanged()
                throw DatabaseError.sql("readRootFileNoFollow: short or inconsistent file read")
            }
            data.append(contentsOf: buffer.prefix(amount))
        }
        try verifyUnchanged(recheck: data)
        guard Int64(data.count) == initialSize else {
            throw DatabaseError.sql("readRootFileNoFollow: short or inconsistent file read")
        }
        return NoFollowFileRead(
            data: data, size: initialSize,
            modificationDate: modificationDate, modificationNanoseconds: modificationNanoseconds, device: device, inode: inode)
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

    public struct RootReconcileReport: Equatable, Sendable {
        public let rootCount: Int
        public let settledRoots: Int
        public let freshRoots: Int
        public let missingRoots: Int
        /// Registered before the locator was retained and therefore not
        /// re-scannable until registered again. Not a scan failure.
        public let unlocatableRoots: Int
        public let failedRoots: Int
        public let scanned: Int
        public let reused: Int
        public let changed: Int
        public let removed: Int
        public let invalidatedSettlements: Int
    }

    /// Scan budget for one registered root: the file cap (4,096) times the
    /// per-file tail window (256 KB). Used by reconcile and by launch bootstrap
    /// instead of the conservative 64 MiB single-settlement ceiling, which made
    /// real desktop roots fail every launch (measured: 2.0 GB and 17.6 GB).
    public static let rootScanReadBudget = 4_096 * (256 << 10)

    /// Re-derive validity for every registered root of `category` so carried
    /// results stay trustworthy across execution periods. A root whose directory
    /// is absent is marked `missing` and its content is NOT cleared; an
    /// unreadable root is counted as failed. `minAgeSeconds` skips roots that
    /// were scanned recently, which bounds launch-time work.
    ///
    /// `carryText` defaults to index-only: the product keeps a locator + digest
    /// per file and never copies entity bytes into the store.
    @discardableResult
    public func reconcileRegisteredRoots(
        category: String = "work", minAgeSeconds: TimeInterval = 0,
        carryText: Bool = false,
        maxTotalBytesRead: Int = ESISDatabase.rootScanReadBudget
    ) throws -> RootReconcileReport {
        let fm = FileManager.default
        let stmt = try prepare("""
        SELECT root_id, display_name, last_scanned_at FROM roots
        WHERE category=? ORDER BY root_id;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, category)
        var rows: [(id: String, path: String?, scanned: String?)] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            rows.append((text(0) ?? "", text(1), text(2)))
        }
        try reset(stmt)

        var settledRoots = 0, freshRoots = 0, missingRoots = 0, failedRoots = 0
        var unlocatableRoots = 0
        var scanned = 0, reused = 0, changed = 0, removed = 0, invalidated = 0
        let now = Date()

        for row in rows {
            guard let path = row.path, !path.isEmpty else {
                unlocatableRoots += 1
                continue
            }
            if minAgeSeconds > 0, let scannedAt = row.scanned.flatMap(parseISO8601),
                now.timeIntervalSince(scannedAt) < minAgeSeconds
            {
                freshRoots += 1
                continue
            }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                // An unmounted or moved root must not read as mass deletion.
                try markRootStatus(row.id, status: "missing")
                missingRoots += 1
                continue
            }
            do {
                let result = try settleWorkRootContents(
                    rootID: row.id, rootURL: URL(fileURLWithPath: path),
                    category: category,
                    maxTotalBytesRead: maxTotalBytesRead,
                    carryText: carryText)
                settledRoots += 1
                scanned += result.scanned
                reused += result.reused
                changed += result.changed
                removed += result.removed
                invalidated += result.invalidatedSettlements
            } catch {
                failedRoots += 1
            }
        }

        return RootReconcileReport(
            rootCount: rows.count, settledRoots: settledRoots,
            freshRoots: freshRoots, missingRoots: missingRoots,
            unlocatableRoots: unlocatableRoots,
            failedRoots: failedRoots, scanned: scanned, reused: reused,
            changed: changed, removed: removed,
            invalidatedSettlements: invalidated)
    }

    // MARK: - Demand 驱动的信息检索（原研究 execute_demand 语义）

    public struct DemandRetrieval: Equatable, Sendable {
        public let demandID: String
        public let reused: Bool
        public let hits: [ContentHit]
        public let resultSHA256: String
        public let status: String
    }

    /// The canonical input basis of a demand: the query plus every settled
    /// file-content digest under the requested roots, in `root/path=sha` form,
    /// ordered by `(root_id, relative_path)`. One helper serves both the
    /// retrieval demand (`executeInformationDemand`) and settlement consumption,
    /// so both compare the SAME input basis. Passing nil or an empty root list
    /// means every registered root.
    public struct CanonicalDemandInput: Equatable, Sendable {
        public struct Entry: Equatable, Sendable {
            public let rootID: String
            public let relativePath: String
            public let contentSHA256: String
            public let objectID: String?

            public init(rootID: String, relativePath: String,
                        contentSHA256: String, objectID: String?) {
                self.rootID = rootID
                self.relativePath = relativePath
                self.contentSHA256 = contentSHA256
                self.objectID = objectID
            }
        }

        public let query: String
        public let rootIDs: [String]
        public let entries: [Entry]
        public let canonical: String
        public let digest: String

        public init(query: String, rootIDs: [String], entries: [Entry],
                    canonical: String, digest: String) {
            self.query = query
            self.rootIDs = rootIDs
            self.entries = entries
            self.canonical = canonical
            self.digest = digest
        }
    }

    /// Caller owns any transaction; the query reads the current settled content
    /// index, so a consumption computing this inside `BEGIN IMMEDIATE` cannot
    /// race a content settlement (which also opens a write transaction).
    public func canonicalDemandInput(
        query: String, rootIDs: [String]? = nil
    ) throws -> CanonicalDemandInput {
        var sql = "SELECT root_id, relative_path, content_sha256, object_id FROM file_contents"
        var bound: [String] = []
        if let rootIDs, !rootIDs.isEmpty {
            bound = Array(Set(rootIDs)).sorted()
            sql += " WHERE root_id IN ("
                + Array(repeating: "?", count: bound.count).joined(separator: ",") + ")"
        }
        sql += " ORDER BY root_id, relative_path;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        for (index, root) in bound.enumerated() {
            try bind(stmt, Int32(index + 1), root)
        }
        var digests: [String] = []
        var roots: [String] = []
        var entries: [CanonicalDemandInput.Entry] = []
        while try stepRowOrDone(stmt) {
            func col(_ i: Int32) -> String {
                sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
            }
            let root = col(0)
            let path = col(1)
            let sha = col(2)
            digests.append("\(root)/\(path)=\(sha)")
            if !roots.contains(root) { roots.append(root) }
            let objectID = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : col(3)
            entries.append(.init(rootID: root, relativePath: path,
                                 contentSHA256: sha, objectID: objectID))
        }
        let canonical = query + "|" + digests.joined(separator: ";")
        return CanonicalDemandInput(
            query: query, rootIDs: roots, entries: entries,
            canonical: canonical,
            digest: NativeSHA256.hexDigest(Data(canonical.utf8)))
    }

    /// Legacy demand resolution. No production caller remains: the live path is
    /// `InformationLoop.resolve`, which adds the source bindings this
    /// function does not write. Kept because the tests and the stored-basis
    /// format (see `invalidateRetrievalSettlementsInTransaction`) still refer to
    /// it; do not wire new callers to it.
    ///
    /// 执行一次信息需求（demand）：
    ///   demand_id = SHA256(query + 注册根集合 + 全部已结算内容摘要的规范串联)
    /// 同一 demand 且结算有效 → 直接返回已结算结果（**不再重复计算**，即
    /// ES₁ 已结算关系对 ES₂ 合法复用）；任一输入摘要变化 → 新 demand，重算
    /// 并落新结算，旧结算置 invalidated。结果逐项摘要绑定，确定性 consumer
    /// 不造内容。
    public func executeInformationDemand(
        query: String, rootID: String? = nil, limit: Int = 200
    ) throws -> DemandRetrieval {
        // The input basis, cache check, result scan and publication must observe
        // one database revision. BEGIN IMMEDIATE also prevents a competing root
        // settlement from changing file_contents between these stages.
        return try transactionResult {
            // 1) 输入摘要：查询 + 相关根的已结算内容摘要（规范排序串联）
            let canonicalInput = try canonicalDemandInput(
                query: query, rootIDs: rootID.map { [$0] })
            // 候选文件的地址必须可解析，缺了就报错。但候选不等于依赖：
            // 一次 demand 的 canonical input 是整个根的文件清单（实测一条
            // demand 带回约 700 个候选），把它们逐条写成依赖边，184k 条
            // 里 99% 都是候选清单，不是被引用的信息。
            for entry in canonicalInput.entries where entry.objectID == nil {
                // Index-only settlement: the address is the identity record's
                // metadata object, not a copy of the entity bytes.
                let identity = "file:\(entry.rootID)/\(entry.relativePath)"
                guard try latestIndexObjectID(identity: identity) != nil else {
                    throw DatabaseError.sql(
                        "executeInformationDemand: missing metadata object address for \(identity)")
                }
            }
            let canonical = canonicalInput.canonical
            // The result limit and filename-index matches both change the
            // persisted hit set, so they are part of retrieval identity.
            let effectiveLimit = max(0, limit)
            let filenameHits = try fileNameHits(
                query: query, rootID: rootID, limit: effectiveLimit)
            let demandBasis = try Self.canonicalJSON([
                "canonical_input": canonical,
                "root_scope": rootID.map { $0 as Any } ?? NSNull(),
                "result_limit": effectiveLimit,
                "filename_hits": filenameHits.map {
                    ["root_id": $0.rootID, "relative_path": $0.relativePath]
                },
            ])
            let demandID = NativeSHA256.hexDigest(Data(demandBasis.utf8))
            let roots = canonicalInput.rootIDs

            // Validate locator-backed bytes before considering a cached result:
            // settled database rows can be unchanged while physical files move.
            var currentHits = try searchSettledContent(
                query: query, rootID: rootID, limit: effectiveLimit,
                strictSourceValidation: true)
            if currentHits.isEmpty { currentHits = filenameHits }

            // 2) 复用检查：同 demand 且结算有效 → 读回已结算对象
            let settled = try prepare("""
            SELECT result_object_id, result_sha256, result_json FROM retrieval_settlements
            WHERE demand_id=? AND status='valid';
            """)
            try bind(settled, 1, demandID)
            let settledRC = sqlite3_step(settled)
            if settledRC == SQLITE_ROW {
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
                    NativeSHA256.hexDigest(data) == storedSHA,
                    let rows = try? JSONDecoder().decode([ContentHit].self, from: data),
                    rows == currentHits
                {
                    return DemandRetrieval(
                        demandID: demandID, reused: true, hits: rows,
                        resultSHA256: storedSHA, status: "reused")
                }
            } else {
                sqlite3_finalize(settled)
                guard settledRC == SQLITE_DONE else {
                    throw Self.sqliteFailure(handle, resultCode: settledRC)
                }
            }

            // 3) 重算：在同一数据库快照上、逐一校验 locator 后的检索结果
            let hits = currentHits
            let resultData = try JSONEncoder().encode(hits)
            let resultSHA = NativeSHA256.hexDigest(resultData)

            // 4) 结果写入对象库，结算行只保留引用；索引追加 demand 身份
            let objectID = try ensureObject(resultData)
            try execBinding("""
            UPDATE retrieval_settlements SET status='invalidated'
            WHERE query=? AND demand_id<>?;
            """) { stmt in
                try bind(stmt, 1, query)
                try bind(stmt, 2, demandID)
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
                try bind(stmt, 1, demandID)
                try bind(stmt, 2, query)
                try bind(stmt, 3, roots.joined(separator: ","))
                try bind(stmt, 4, demandBasis)
                try bind(stmt, 5, resultSHA)
                try bind(stmt, 6, Int64(hits.count))
                try bind(stmt, 7, "valid")
                try bind(stmt, 8, Self.stamp(Date()))
                try bind(stmt, 9, objectID)
            }
            _ = try appendIndexEntryInTransaction(
                identity: "demand:\(demandID)", objectID: objectID)

            return DemandRetrieval(
                demandID: demandID, reused: false, hits: hits,
                resultSHA256: resultSHA, status: "settled")
        }
    }

    /// 文件名/路径命中的确定性 consumer（demand 结果的一部分）。
    private func fileNameHits(query: String, rootID: String?, limit: Int) throws -> [ContentHit] {
        guard limit > 0 else { return [] }
        var sql = """
        SELECT root_id, relative_path FROM external_files
        WHERE relative_path LIKE ? AND COALESCE(status,'present')='present'
        """
        if rootID != nil { sql += " AND root_id='" + rootID!.replacingOccurrences(of: "'", with: "''") + "'" }
        sql += " ORDER BY relative_path LIMIT \(limit);"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, "%" + query + "%")
        guard limit > 0 else { return [] }
        var hits: [ContentHit] = []
        while hits.count < limit {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                func col(_ i: Int32) -> String {
                    guard let c = sqlite3_column_text(stmt, i) else { return "" }
                    return String(cString: c)
                }
                hits.append(ContentHit(
                    rootID: col(0), relativePath: col(1), lineNo: 0,
                    lineText: col(1)))
                continue
            }
            guard rc == SQLITE_DONE else {
                throw Self.sqliteFailure(handle, resultCode: rc)
            }
            return hits
        }
        // The SQL query has the same LIMIT, so reaching this count is a
        // deliberate bounded completion rather than a partial error result.
        return hits
    }

    public struct ContentHit: Equatable, Sendable, Codable {
        public let rootID: String
        public let relativePath: String
        public let lineNo: Int
        public let lineText: String
    }

    /// 信息拓扑检索：在已结算的文件索引上按关键词命中（行级）。索引可以
    /// 只保存定位符 + 摘要（不拷贝实体），因此文本从注册根的定位符读取，
    /// 并**逐次校验结算摘要**：磁盘内容已变而尚未重新结算 → 该行不是命中，
    /// 由 ES 侧触发再结算（IS 只存/验，不判断语义）。
    public func searchSettledContent(query: String, rootID: String? = nil, limit: Int = 200)
        throws -> [ContentHit]
    {
        // Interactive search keeps its historical best-effort behavior: a
        // source whose bytes no longer match the settled digest is not a hit.
        // Demand settlement uses the strict overload below because publishing
        // a partial result from an incomplete source basis would be unsound.
        try searchSettledContent(
            query: query, rootID: rootID, limit: limit,
            strictSourceValidation: false)
    }

    private func searchSettledContent(
        query: String, rootID: String?, limit: Int,
        strictSourceValidation: Bool
    ) throws -> [ContentHit] {
        guard !query.isEmpty, limit > 0 else { return [] }
        let rows = try settledFileRows(rootID: rootID)
        var hits: [ContentHit] = []
        for row in rows {
            let body: String
            do {
                body = try searchableFileText(row)
            } catch let error as DatabaseError {
                if case .staleExternalSource = error, !strictSourceValidation {
                    continue
                }
                throw error
            }
            for (idx, line) in body.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.localizedCaseInsensitiveContains(query) {
                hits.append(ContentHit(
                    rootID: row.rootID, relativePath: row.relativePath,
                    lineNo: idx + 1, lineText: String(line.prefix(200))))
                if hits.count >= limit { return hits }
            }
        }
        return hits
    }

    struct SettledFileRow {
        let rootID: String
        let relativePath: String
        let digest: String
        let objectID: String?
        let legacy: Data
        let indexedSize: Int64?
    }

    func settledFileRows(rootID: String?) throws -> [SettledFileRow] {
        try settledFileRows(rootIDs: rootID.map { [$0] })
    }

    /// Materialize only the requested roots. An empty or nil scope retains the
    /// historical all-roots behavior; non-empty scopes are pushed into SQLite
    /// before carried content blobs are copied into Swift values.
    func settledFileRows(rootIDs: [String]?) throws -> [SettledFileRow] {
        let scopedRootIDs = Array(Set(rootIDs ?? [])).sorted()
        var sql = """
        SELECT f.root_id, f.relative_path, f.content_sha256, f.object_id, f.content, e.size
        FROM file_contents f
        LEFT JOIN external_files e
          ON e.root_id=f.root_id AND e.relative_path=f.relative_path
        """
        if !scopedRootIDs.isEmpty {
            let placeholders = Array(repeating: "?", count: scopedRootIDs.count)
                .joined(separator: ",")
            sql += " WHERE f.root_id IN (\(placeholders))"
        }
        sql += " ORDER BY f.root_id, f.relative_path;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        for (index, rootID) in scopedRootIDs.enumerated() {
            try bind(stmt, Int32(index + 1), rootID)
        }
        var rows: [SettledFileRow] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                func text(_ i: Int32) -> String? {
                    sqlite3_column_text(stmt, i).map { String(cString: $0) }
                }
                let bytes = Int(sqlite3_column_bytes(stmt, 4))
                let legacy = sqlite3_column_blob(stmt, 4).map { Data(bytes: $0, count: bytes) } ?? Data()
                let indexedSize: Int64? = sqlite3_column_type(stmt, 5) == SQLITE_NULL
                    ? nil : sqlite3_column_int64(stmt, 5)
                rows.append(SettledFileRow(
                    rootID: text(0) ?? "", relativePath: text(1) ?? "",
                    digest: text(2) ?? "", objectID: text(3),
                    legacy: legacy, indexedSize: indexedSize))
                continue
            }
            guard rc == SQLITE_DONE else {
                throw Self.sqliteFailure(handle, resultCode: rc)
            }
            return rows
        }
    }

    /// Resolve and verify every settled text row. Missing, unreadable or changed
    /// index-only sources are errors, not ordinary no-match results: silently
    /// skipping one would let a partial retrieval be persisted under a full basis.
    func searchableFileText(_ row: SettledFileRow) throws -> String {
        if let objectID = row.objectID, !objectID.isEmpty {
            let data = try readObject(objectID)
            if NativeSHA256.hexDigest(data) == row.digest {
                return String(decoding: data, as: UTF8.self)
            }
            // A carried tail is stored as the indexed text window, while its
            // content digest is framed with the full source size. Verify that
            // representation instead of comparing it to a whole-file digest.
            if let indexedSize = row.indexedSize, indexedSize >= 0,
               NativeSHA256.hexDigest(Data("tail:\(indexedSize):".utf8) + data) == row.digest {
                return String(decoding: data, as: UTF8.self)
            }
            throw DatabaseError.sql(
                "searchableFileText: carried object digest mismatch for \(row.rootID)/\(row.relativePath)")
        }
        if !row.legacy.isEmpty {
            if NativeSHA256.hexDigest(row.legacy) == row.digest {
                return String(decoding: row.legacy, as: UTF8.self)
            }
            if let indexedSize = row.indexedSize, indexedSize >= 0,
               NativeSHA256.hexDigest(Data("tail:\(indexedSize):".utf8) + row.legacy) == row.digest {
                return String(decoding: row.legacy, as: UTF8.self)
            }
            throw DatabaseError.sql(
                "searchableFileText: legacy content digest mismatch for \(row.rootID)/\(row.relativePath)")
        }
        guard let locator = try rootLocatorPath(row.rootID) else {
            throw DatabaseError.sql(
                "searchableFileText: no locator for settled file \(row.rootID)/\(row.relativePath)")
        }
        let relative = row.relativePath
        guard !relative.isEmpty,
            !relative.split(separator: "/").contains("..")
        else {
            throw DatabaseError.sql(
                "searchableFileText: invalid relative path for \(row.rootID)/\(row.relativePath)")
        }
        // A vanished source is drift, not carrier failure: the resolve keeps
        // every other source and reports this one stale. A path that now leads
        // elsewhere (symlink) still refuses loudly — that is what the no-follow
        // reader is for, so `sourceGone` is deliberately narrower than it.
        func mapGone<T>(_ body: () throws -> T) throws -> T {
            do {
                return try body()
            } catch ESISDatabase.DatabaseError.sourceGone {
                throw DatabaseError.staleExternalSource(
                    rootID: row.rootID, relativePath: row.relativePath)
            }
        }
        let rootDirectoryFD = try mapGone { try openDirectoryNoFollow(atPath: locator) }
        defer { Darwin.close(rootDirectoryFD) }

        // Index-only metadata is itself a content-addressed object. It records
        // whether the settled digest covers the whole file or a tail window and
        // the exact raw window size needed to reproduce that digest.
        let identity = "file:\(row.rootID)/\(row.relativePath)"
        guard let metadataObjectID = try latestIndexObjectID(identity: identity),
              !metadataObjectID.isEmpty else {
            throw DatabaseError.sql(
                "searchableFileText: missing index-only metadata object for \(row.rootID)/\(row.relativePath)")
        }
        let metadataData = try readObject(metadataObjectID)
        guard let metadata = try JSONSerialization.jsonObject(with: metadataData)
                as? [String: Any],
              let metadataLocator = metadata["locator"] as? String,
              let metadataDigest = metadata["sha256"] as? String,
              let indexedSize = metadata["size"] as? Int64,
              indexedSize >= 0 else {
            throw DatabaseError.sql(
                "searchableFileText: malformed index-only metadata for \(row.rootID)/\(row.relativePath)")
        }
        guard metadataLocator == identity, metadataDigest == row.digest,
              row.indexedSize == nil || row.indexedSize == indexedSize else {
            throw DatabaseError.staleExternalSource(
                rootID: row.rootID, relativePath: row.relativePath)
        }

        if metadata["is_tail"] as? Bool == true {
            let maximumTailReadBytes = 64 * 1024 * 1024
            guard let tailWindowBytes = metadata["tail_bytes"] as? Int,
                  tailWindowBytes > 0, tailWindowBytes <= maximumTailReadBytes,
                  indexedSize > 0, indexedSize <= Int64(Int.max) else {
                throw DatabaseError.staleExternalSource(
                    rootID: row.rootID, relativePath: row.relativePath)
            }
            let read = try mapGone { try readRootFileNoFollow(
                rootDirectoryFD: rootDirectoryFD,
                relativePath: relative,
                // Force the bounded tail path based on the read window, not
                // the original full source size. If the source shrank but is
                // still larger than the tail budget, a size-based threshold
                // would try to read the whole changed file and throw a generic
                // budget error instead of classifying it as stale.
                maximumBytes: tailWindowBytes - 1,
                tailBytes: tailWindowBytes,
                maximumTotalBytesRead: tailWindowBytes) }
            guard read.isTail, read.size == indexedSize, let rawTail = read.data else {
                throw DatabaseError.staleExternalSource(
                    rootID: row.rootID, relativePath: row.relativePath)
            }
            let indexedData = Self.indexedTailData(rawTail)
            let digest = NativeSHA256.hexDigest(
                Data("tail:\(indexedSize):".utf8) + indexedData)
            guard digest == row.digest else {
                throw DatabaseError.staleExternalSource(
                    rootID: row.rootID, relativePath: row.relativePath)
            }
            return String(decoding: indexedData, as: UTF8.self)
        }

        // Full-file index-only revalidation is bounded independently of the
        // caller's custom scan limits; larger sources require a tail marker.
        let maximumFullReadBytes = 64 * 1024 * 1024
        guard indexedSize <= Int64(maximumFullReadBytes) else {
            throw DatabaseError.staleExternalSource(
                rootID: row.rootID, relativePath: row.relativePath)
        }
        let read = try mapGone { try readRootFileNoFollow(
            rootDirectoryFD: rootDirectoryFD,
            relativePath: relative,
            maximumBytes: Int(indexedSize),
            maximumTotalBytesRead: maximumFullReadBytes) }
        guard !read.isTail, read.size == indexedSize, let data = read.data,
              NativeSHA256.hexDigest(data) == row.digest else {
            throw DatabaseError.staleExternalSource(
                rootID: row.rootID, relativePath: row.relativePath)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func rootLocatorPath(_ rootID: String) throws -> String? {
        let stmt = try prepare("""
        SELECT display_name FROM roots
        WHERE root_id=? AND locator_type='path';
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, rootID)
        guard try stepRowOrDone(stmt), let c = sqlite3_column_text(stmt, 0)
        else { return nil }
        let path = String(cString: c)
        return path.isEmpty ? nil : URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// 目录自己的 inode。inode 为 0（FAT/exFAT 一类）时返回 nil；
    /// lstat 失败或路径不再指向目录时抛错，不能把「读不到身份」伪装成「没有身份」。
    static func directoryINode(atPath path: String) throws -> Int64? {
        var info = stat()
        // lstat, 不是 stat: 调用方给的是已解析（canonical）的路径，这里要的是
        // 这个路径本身指向的目录。符号链接已经被解析掉了。
        let result = path.withCString { Darwin.lstat($0, &info) }
        guard result == 0 else {
            let code = errno
            throw DatabaseError.sql(
                "directoryINode: cannot inspect \(path): \(String(cString: strerror(code)))")
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR else {
            throw DatabaseError.sql("directoryINode: not a directory: \(path)")
        }
        let inode = Int64(info.st_ino)
        return inode == 0 ? nil : inode
    }

    /// 记下或比对 root 所在目录的 inode。返回 true 表示「还是这个路径，但
    /// 不是这个目录了」。第一次见到就记下来；README 里那三种挂载形状都靠
    /// 它分开。
    @discardableResult
    private func noteLocatorIdentity(rootID: String, path: String) throws -> Bool {
        guard let current = try Self.directoryINode(atPath: path) else { return false }
        let stmt = try prepare("SELECT locator_inode FROM roots WHERE root_id=?;")
        try bind(stmt, 1, rootID)
        let found = try stepRowOrDone(stmt)
        let stored: Int64? = found && sqlite3_column_type(stmt, 0) != SQLITE_NULL
            ? sqlite3_column_int64(stmt, 0) : nil
        sqlite3_finalize(stmt)
        guard let stored else {
            try execBinding("UPDATE roots SET locator_inode=? WHERE root_id=?;") { s in
                try bind(s, 1, current)
                try bind(s, 2, rootID)
            }
            return false
        }
        return stored != current
    }

    /// 人确认「还是同一个目录，只是换了挂载」之后调用：把当前 inode 收作它的。
    public func adoptRootLocatorIdentity(rootID: String) throws {
        guard let path = try rootLocatorPath(rootID),
            let inode = try Self.directoryINode(atPath: path)
        else {
            throw DatabaseError.sql(
                "adoptRootLocatorIdentity: no directory behind \(rootID)")
        }
        try execBinding("UPDATE roots SET locator_inode=? WHERE root_id=?;") { stmt in
            try bind(stmt, 1, inode)
            try bind(stmt, 2, rootID)
        }
    }

    // MARK: - 对话落库（Information Space：会话即信息）

    /// Semantic standing of a chat turn. `ordinary` is the user's conversation;
    /// `internalOperation` is client bookkeeping (rollout analysis, title
    /// generation, memory extraction) that is kept as a record but never
    /// becomes a retrieval source or a settled result. Arriving on a wire is
    /// not what grants ordinary standing — the request declares it.
    public enum ChatTurnEligibility: String, Sendable {
        case ordinary
        case internalOperation = "internal"

        /// 记账类请求问的是「这段文本说了什么」，不是「空间里有什么」，所以
        /// 不装配上下文（不检索、不注入、不结算、不记轮次），直接按它带来的
        /// 文本作答。
        ///
        /// 只有 HTTP 会话路径看这个属性。同名的 standing 出现在导入路径上时
        /// （`ExternalTurnSink`、`MultiFormatCollection`）只表示审计存档，那些
        /// 行是直写库的，本来就不经过上下文装配——两处不要互相推断。
        public var skipsContextAssembly: Bool { self == .internalOperation }
    }

    /// Who produced a chat line. Local turns are the app's own conversation;
    /// external turns arrived through an upstream provider and keep that
    /// provenance for as long as the row exists.
    public enum ChatTurnSource: String, Sendable {
        case local
        case external
    }

    /// The standings a line can hold, as stored in `turn_state`. They are
    /// distinct questions: in flight (`pending`), externally recorded
    /// (`recorded`), ended without completion (`failed`/`cancelled`/`detached`),
    /// internal bookkeeping (`internal`), and verified/retrievable
    /// (`committed`; ordinary retrieval reads
    /// `committed` rows only, further narrowed by request scope).
    public enum ChatTurnState: String, Sendable {
        /// Local input whose own request is still in flight.
        case pending
        /// Persisted with provenance, not yet verified: recorded only.
        case recorded
        /// Verified/settled; eligible for ordinary retrieval.
        case committed
        /// The request ended before the turn completed; never retrieval eligible.
        case failed
        /// The request was cancelled before the turn completed; never retrieval eligible.
        case cancelled
        /// The client detached while generation continued; never retrieval eligible.
        case detached
        /// Client bookkeeping kept as a record, never ordinary memory.
        case internalOperation = "internal"
    }

    /// Terminal standing for a local request that did not complete.
    public enum ChatTurnTerminal: String, Sendable {
        case failed
        case cancelled
        case detached
    }

    /// Chat write set to commit with an authoritative model settlement.
    public struct ChatTurnCommit: Sendable {
        public let sessionID: String
        public let userMessageID: Int64
        public let assistantText: String
        public let model: String?
        public let createdAt: Date
        public let eligibility: ChatTurnEligibility

        public init(sessionID: String, userMessageID: Int64, assistantText: String,
                    model: String?, createdAt: Date,
                    eligibility: ChatTurnEligibility = .ordinary) {
            self.sessionID = sessionID
            self.userMessageID = userMessageID
            self.assistantText = assistantText
            self.model = model
            self.createdAt = createdAt
            self.eligibility = eligibility
        }
    }

    /// Append one conversation line. A user row starts `pending` and only the
    /// turn that produced it can promote it (`commitChatTurn`): ordinary
    /// retrieval must never treat another request's in-flight input as memory.
    /// Other roles are written at completion, so they are eligible at once.
    /// Internal-operation rows are written `internal` and stay there.
    ///
    /// Returns the row id. A same-text retry reuses the trailing row only
    /// while that local user row is still pending. A completed, failed or
    /// cancelled turn stays in history and the next request receives a new row.
    @discardableResult
    public func appendChatMessage(
        sessionID: String, role: String, content: String, model: String?, createdAt: Date,
        eligibility: ChatTurnEligibility = .ordinary
    ) throws -> Int64 {
        let data = Data(content.utf8)
        let digest = NativeSHA256.hexDigest(data)
        let state = role == "user"
            ? Self.pendingState(for: eligibility) : Self.completedState(for: eligibility)
        if role == "user", let existing = try lastUserMessage(sessionID: sessionID),
            existing.digest == digest,
            Self.sameEligibilityClass(existing.state, state) {
            return existing.messageID
        }
        return try transactionResult {
            try insertChatMessage(
                sessionID: sessionID, role: role, data: data, digest: digest,
                model: model, createdAt: createdAt, state: state)
        }
    }

    private static func pendingState(for eligibility: ChatTurnEligibility) -> String {
        eligibility == .internalOperation
            ? eligibility.rawValue : ChatTurnState.pending.rawValue
    }

    private static func completedState(for eligibility: ChatTurnEligibility) -> String {
        eligibility == .internalOperation
            ? eligibility.rawValue : ChatTurnState.committed.rawValue
    }

    /// A retry may reuse a row only of the same standing: an ordinary turn must
    /// never adopt an internal-operation row (that would promote client
    /// bookkeeping into ordinary memory), and an internal operation must never
    /// adopt a conversation row.
    private static func sameEligibilityClass(_ existing: String, _ target: String) -> Bool {
        let internalState = ChatTurnEligibility.internalOperation.rawValue
        if target == internalState { return existing == internalState }
        // Only an in-flight local retry may adopt the existing row. A completed,
        // failed or cancelled turn is a distinct historical event even when the
        // next request repeats the exact same words.
        return existing == ChatTurnState.pending.rawValue
    }

    /// Commit this turn: store the reply and promote the user row that started
    /// the turn in one transaction, so a reader never sees the answer without
    /// the question it answers, nor the question before the turn is done.
    @discardableResult
    public func commitChatTurn(
        sessionID: String, userMessageID: Int64, assistantText: String,
        model: String?, createdAt: Date,
        eligibility: ChatTurnEligibility = .ordinary
    ) throws -> Int64 {
        try transactionResult {
            try insertChatTurnRows(.init(
                sessionID: sessionID, userMessageID: userMessageID,
                assistantText: assistantText, model: model, createdAt: createdAt,
                eligibility: eligibility))
        }
    }

    /// Caller owns the transaction.
    @discardableResult
    private func insertChatTurnRows(_ write: ChatTurnCommit) throws -> Int64 {
        let data = Data(write.assistantText.utf8)
        let digest = NativeSHA256.hexDigest(data)
        let assistantID = try insertChatMessage(
            sessionID: write.sessionID, role: "assistant", data: data, digest: digest,
            model: write.model, createdAt: write.createdAt,
            state: Self.completedState(for: write.eligibility))
        if write.eligibility == .ordinary {
            guard write.userMessageID > 0 else {
                throw DatabaseError.sql(
                    "commitChatTurn: ordinary turn requires a pending local user row")
            }
            let promotedRows = try execBinding("""
            UPDATE chat_messages SET turn_state='committed'
            WHERE id=? AND session_id=? AND role='user'
              AND source_kind='local' AND turn_state='pending';
            """) { stmt in
                try bind(stmt, 1, write.userMessageID)
                try bind(stmt, 2, write.sessionID)
            }
            guard promotedRows == 1 else {
                throw DatabaseError.sql(
                    "commitChatTurn: expected one pending local user row; updated \(promotedRows)")
            }
        }
        return assistantID
    }

    /// Close an uncompleted local user row without promoting it into retrieval
    /// history. This is idempotent and touches only the exact pending user row.
    @discardableResult
    public func closePendingChatTurn(
        sessionID: String,
        userMessageID: Int64,
        terminal: ChatTurnTerminal
    ) throws -> Bool {
        guard userMessageID > 0 else { return false }
        return try transactionResult {
            let changed = try execBinding("""
            UPDATE chat_messages SET turn_state=?
            WHERE id=? AND session_id=? AND role='user' AND source_kind='local'
              AND turn_state='pending';
            """) { stmt in
                try bind(stmt, 1, terminal.rawValue)
                try bind(stmt, 2, userMessageID)
                try bind(stmt, 3, sessionID)
            }
            return changed == 1
        }
    }

    private func insertChatMessage(
        sessionID: String, role: String, data: Data, digest: String,
        model: String?, createdAt: Date, state: String,
        sourceKind: ChatTurnSource = .local, sourceProvider: String? = nil,
        requestID: String? = nil
    ) throws -> Int64 {
        let objectID = try ensureObject(data)
        try execBinding("""
        INSERT INTO chat_messages(
            session_id, role, content, model, content_sha256, created_at,
            content_object_id, turn_state, source_kind, source_provider, request_id)
        VALUES(?,?,?,?,?,?,?,?,?,?,?);
        """) { stmt in
            try bind(stmt, 1, sessionID)
            try bind(stmt, 2, role)
            try bind(stmt, 3, "")
            if let model { try bind(stmt, 4, model) } else { try bindNull(stmt, 4) }
            try bind(stmt, 5, digest)
            try bind(stmt, 6, Self.stamp(createdAt))
            try bind(stmt, 7, objectID)
            try bind(stmt, 8, state)
            try bind(stmt, 9, sourceKind.rawValue)
            try bind(stmt, 10, sourceProvider)
            try bind(stmt, 11, requestID)
        }
        let rowID = sqlite3_last_insert_rowid(handle)
        _ = try appendIndexEntryInTransaction(
            identity: "chat:\(sessionID)/\(rowID)", objectID: objectID)
        // Chat is information in the same space as files: one item registry,
        // one content-addressed payload, no second copy.
        try execBinding("""
        INSERT INTO information_items(
            item_id, kind, locator, source_version, source_payload_sha256, state, updated_at)
        VALUES(?,?,?,?,?,'AVAILABLE',?)
        ON CONFLICT(item_id) DO UPDATE SET
            source_version=excluded.source_version,
            source_payload_sha256=excluded.source_payload_sha256,
            state='AVAILABLE', updated_at=excluded.updated_at;
        """) { stmt in
            try bind(stmt, 1, "chat:\(sessionID)/\(rowID)")
            try bind(stmt, 2, "chat")
            try bind(stmt, 3, "session:\(sessionID)#\(rowID)")
            try bind(stmt, 4, Self.stamp(createdAt))
            try bind(stmt, 5, digest)
            try bind(stmt, 6, Self.stamp(createdAt))
        }
        return rowID
    }

    // MARK: - Turn digests（每轮问了什么、答出什么，供以后直接读）

    /// 一轮会话的精编结果。正文不在这里：问题与回答在 `is_objects` 里，
    /// 经 `chat_messages.content_object_id` 取回。
    public struct TurnDigestRecord: Equatable, Sendable {
        public let sessionID: String
        public let turnIndex: Int
        public let questionMessageID: Int64?
        public let answerMessageID: Int64?
        public let digest: String
        public let keywords: [String]
        public let model: String?
        public let createdAt: String
    }

    /// 写一轮摘要，同时把关键字拆进 `keywords` / `turn_keywords`。
    ///
    /// 同一轮重复写是覆盖，不是新增：摘要是派生内容（模型再跑一次结果不同），
    /// 只留一行最新那次，才核得上 `chat_turn_ledger` 的轮号账。
    @discardableResult
    public func recordTurnDigest(
        sessionID: String, turnIndex: Int,
        questionMessageID: Int64? = nil, answerMessageID: Int64? = nil,
        digest: String, keywords: String, model: String? = nil,
        createdAt: Date = Date(),
        requestSpaceAssignment: Bool = false
    ) throws -> TurnDigestRecord {
        let text = digest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw DatabaseError.sql("recordTurnDigest: digest is empty")
        }
        var seen = Set<String>()
        let terms = keywords.split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        let now = Self.stamp(createdAt)

        // 建表放在事务外：DDL 回滚了却记着「已建好」，这个连接后面每次
        // 查房间表都会撞「no such table」。已在连接上建过时这一步是空的。
        if requestSpaceAssignment { try ensureRoomSchema() }

        return try transactionResult {
            try execBinding("""
            INSERT INTO turn_digests(
                session_id, turn_index, question_message_id, answer_message_id,
                digest, keywords, model, created_at)
            VALUES(?,?,?,?,?,?,?,?)
            ON CONFLICT(session_id, turn_index) DO UPDATE SET
                question_message_id=excluded.question_message_id,
                answer_message_id=excluded.answer_message_id,
                digest=excluded.digest, keywords=excluded.keywords,
                model=COALESCE(excluded.model, turn_digests.model),
                created_at=excluded.created_at;
            """) { stmt in
                try bind(stmt, 1, sessionID)
                try bind(stmt, 2, Int64(turnIndex))
                try bind(stmt, 3, questionMessageID)
                try bind(stmt, 4, answerMessageID)
                try bind(stmt, 5, text)
                try bind(stmt, 6, terms.joined(separator: " "))
                try bind(stmt, 7, model)
                try bind(stmt, 8, now)
            }
            try storeKeywordTerms(
                terms, sessionID: sessionID, turnIndex: turnIndex, now: now)
            if requestSpaceAssignment {
                // 待判归属与摘要同生共死（#187）：摘要落了、归属没落是常态
                // （撞锁），但「摘要落了、连待办都没有」不该存在——那条路
                // 上没人会再来判这一轮。
                try markSpaceAssignmentPending(
                    sessionID: sessionID, turnIndex: turnIndex, now: createdAt)
            }
            // 返回落盘的那一行，而不是入参：覆盖写之后调用方看到的应当
            // 就是库里现在的内容。
            guard let stored = try turnDigest(sessionID: sessionID, turnIndex: turnIndex)
            else { throw DatabaseError.sql("recordTurnDigest: row missing after write") }
            return stored
        }
    }

    /// 一轮的词表落盘：先摘旧关联，再把词写进 `keywords` 并挂回这一轮。
    /// 词只增不删——`turn_keywords` 对 `keywords` 是级联删除，删词会牵连别的轮。
    private func storeKeywordTerms(
        _ terms: [String], sessionID: String, turnIndex: Int, now: String
    ) throws {
        // 这一轮的词换过一次，旧关联就得摘掉：否则改过摘要之后，旧词
        // 还能把这一轮捞出来。
        try execBinding("""
        DELETE FROM turn_keywords WHERE session_id=? AND turn_index=?;
        """) { stmt in
            try bind(stmt, 1, sessionID)
            try bind(stmt, 2, Int64(turnIndex))
        }
        for term in terms {
            try execBinding("""
            INSERT INTO keywords(term, created_at) VALUES(?,?)
            ON CONFLICT(term) DO NOTHING;
            """) { stmt in
                try bind(stmt, 1, term)
                try bind(stmt, 2, now)
            }
            let keywordID: Int64 = try {
                let stmt = try prepare("SELECT keyword_id FROM keywords WHERE term=?;")
                defer { sqlite3_finalize(stmt) }
                try bind(stmt, 1, term)
                guard try stepRowOrDone(stmt) else {
                    throw DatabaseError.sql("recordTurnDigest: keyword row missing")
                }
                return sqlite3_column_int64(stmt, 0)
            }()
            try execBinding("""
            INSERT OR IGNORE INTO turn_keywords(session_id, turn_index, keyword_id)
            VALUES(?,?,?);
            """) { stmt in
                try bind(stmt, 1, sessionID)
                try bind(stmt, 2, Int64(turnIndex))
                try bind(stmt, 3, keywordID)
            }
        }
    }

    /// 只换关键词：`digest`、`model`、`created_at` 一个字都不动。
    ///
    /// 为什么不复用 `recordTurnDigest`：那是整轮覆盖，换一套词会把「谁写的、
    /// 什么时候写的」一并抹掉，事后分不清这批词是原摘要作者给的还是后来补的。
    @discardableResult
    public func replaceTurnKeywords(
        sessionID: String, turnIndex: Int, keywords: [String],
        createdAt: Date = Date()
    ) throws -> [String] {
        var seen = Set<String>()
        let terms = keywords
            .flatMap { $0.split(whereSeparator: { $0.isWhitespace }).map(String.init) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !terms.isEmpty else {
            throw DatabaseError.sql("replaceTurnKeywords: keywords is empty")
        }
        let now = Self.stamp(createdAt)
        return try transactionResult {
            guard try turnDigest(sessionID: sessionID, turnIndex: turnIndex) != nil else {
                throw DatabaseError.sql("replaceTurnKeywords: no digest row for this turn")
            }
            try execBinding("""
            UPDATE turn_digests SET keywords=? WHERE session_id=? AND turn_index=?;
            """) { stmt in
                try bind(stmt, 1, terms.joined(separator: " "))
                try bind(stmt, 2, sessionID)
                try bind(stmt, 3, Int64(turnIndex))
            }
            try storeKeywordTerms(
                terms, sessionID: sessionID, turnIndex: turnIndex, now: now)
            return terms
        }
    }

    /// 已经有摘要、但词不够的轮次，只带「修词」要的东西。
    public struct DigestTurnText: Sendable {
        public let sessionID: String
        public let turnIndex: Int
        public let keywords: [String]
        public let question: String
        public let answer: String
    }

    /// 词不够的轮次。`minimum` 是「一行少于几个词就该补」，与缺摘要那本账
    /// 无关——缺摘要由 `undigestedTurns()` 报。
    ///
    /// 计数版给状态刷新用。判定必须与挑选版同一口径（含「正文为空就不算」），
    /// 否则按钮上的数字会和真正要修的轮数对不上——所以直接复用挑选版。
    public func turnsWithThinKeywordsCount(minimum: Int = 5) throws -> Int {
        try turnsWithThinKeywords(minimum: minimum).count
    }

    public func turnsWithThinKeywords(
        minimum: Int = 5, limit: Int? = nil
    ) throws -> [DigestTurnText] {
        let stmt = try prepare("""
        SELECT d.session_id, d.turn_index, d.keywords,
               (SELECT CAST(o.content AS TEXT) FROM chat_messages m
                  JOIN is_objects o ON o.object_id=m.content_object_id
                 WHERE m.id=d.question_message_id),
               (SELECT CAST(o.content AS TEXT) FROM chat_messages m
                  JOIN is_objects o ON o.object_id=m.content_object_id
                 WHERE m.id=d.answer_message_id)
          FROM turn_digests d
         ORDER BY d.session_id, d.turn_index;
        """)
        defer { sqlite3_finalize(stmt) }
        var rows: [DigestTurnText] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            let words = (text(2) ?? "").split(whereSeparator: { $0.isWhitespace })
            guard words.count < minimum else { continue }
            let question = text(3) ?? ""
            let answer = text(4) ?? ""
            if question.isEmpty && answer.isEmpty { continue }
            rows.append(DigestTurnText(
                sessionID: text(0) ?? "",
                turnIndex: Int(sqlite3_column_int64(stmt, 1)),
                keywords: words.map(String.init),
                question: question, answer: answer))
            if let limit, rows.count >= limit { break }
        }
        return rows
    }

    private static let turnDigestColumns = """
    session_id, turn_index, question_message_id, answer_message_id,
    digest, keywords, model, created_at
    """

    private func turnDigestRecord(_ stmt: OpaquePointer) -> TurnDigestRecord {
        TurnDigestRecord(
            sessionID: sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "",
            turnIndex: Int(sqlite3_column_int64(stmt, 1)),
            questionMessageID: sqlite3_column_type(stmt, 2) == SQLITE_NULL
                ? nil : sqlite3_column_int64(stmt, 2),
            answerMessageID: sqlite3_column_type(stmt, 3) == SQLITE_NULL
                ? nil : sqlite3_column_int64(stmt, 3),
            digest: sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "",
            keywords: (sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? "")
                .split(whereSeparator: { $0.isWhitespace }).map(String.init),
            model: sqlite3_column_text(stmt, 6).map { String(cString: $0) },
            createdAt: sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? "")
    }

    public func turnDigest(sessionID: String, turnIndex: Int) throws -> TurnDigestRecord? {
        let stmt = try prepare("""
        SELECT \(Self.turnDigestColumns) FROM turn_digests
         WHERE session_id=? AND turn_index=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, Int64(turnIndex))
        guard try stepRowOrDone(stmt) else { return nil }
        return turnDigestRecord(stmt)
    }

    /// 最近的摘要，`sessionID` 传 nil 就是全库。按写入时间倒序：检索要的是
    /// 最新那一版说法。
    public func recentTurnDigests(sessionID: String? = nil, limit: Int = 50)
        throws -> [TurnDigestRecord]
    {
        let stmt = try prepare("""
        SELECT \(Self.turnDigestColumns) FROM turn_digests
         WHERE (? IS NULL OR session_id = ?)
         ORDER BY created_at DESC, session_id DESC, turn_index DESC
         LIMIT ?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, sessionID)
        try bind(stmt, 3, Int64(limit))
        var rows: [TurnDigestRecord] = []
        while try stepRowOrDone(stmt) { rows.append(turnDigestRecord(stmt)) }
        return rows
    }

    /// 轮号有、摘要没有的轮次。和菜单栏的轮号缺口是同一份账：一处漏写，
    /// 另一处就能看见。
    /// 补一轮摘要要的全部东西：轮号、那两行消息的 id、问题与回答的正文。
    public struct UndigestedTurn: Sendable {
        public let sessionID: String
        public let turnIndex: Int
        public let questionMessageID: Int64?
        public let answerMessageID: Int64?
        public let question: String
        public let answer: String
    }

    /// 全库口径的「轮号有、摘要没有」。补摘要按这个跑，跑完再看
    /// `carrierReport().turnsWithoutDigest` 是否归零。
    public func undigestedTurns() throws -> [UndigestedTurn] {
        let stmt = try prepare("""
        SELECT l.session_id, l.turn_index,
               (SELECT m.id FROM chat_messages m
                 WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                   AND m.role='user' LIMIT 1),
               (SELECT m.id FROM chat_messages m
                 WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                   AND m.role='assistant' LIMIT 1),
               (SELECT CAST(o.content AS TEXT) FROM chat_messages m
                  JOIN is_objects o ON o.object_id=m.content_object_id
                 WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                   AND m.role='user' LIMIT 1),
               (SELECT CAST(o.content AS TEXT) FROM chat_messages m
                  JOIN is_objects o ON o.object_id=m.content_object_id
                 WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                   AND m.role='assistant' LIMIT 1)
          FROM chat_turn_ledger l
         WHERE NOT EXISTS (SELECT 1 FROM turn_digests d
                            WHERE d.session_id=l.session_id
                              AND d.turn_index=l.turn_index)
         ORDER BY l.session_id, l.turn_index;
        """)
        defer { sqlite3_finalize(stmt) }
        var rows: [UndigestedTurn] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            let question = text(4) ?? ""
            let answer = text(5) ?? ""
            if question.isEmpty && answer.isEmpty { continue }
            rows.append(UndigestedTurn(
                sessionID: text(0) ?? "",
                turnIndex: Int(sqlite3_column_int64(stmt, 1)),
                questionMessageID: sqlite3_column_type(stmt, 2) == SQLITE_NULL
                    ? nil : sqlite3_column_int64(stmt, 2),
                answerMessageID: sqlite3_column_type(stmt, 3) == SQLITE_NULL
                    ? nil : sqlite3_column_int64(stmt, 3),
                question: question, answer: answer))
        }
        return rows
    }

    public func turnsWithoutDigest(sessionID: String) throws -> [Int] {
        let stmt = try prepare("""
        SELECT l.turn_index FROM chat_turn_ledger l
         WHERE l.session_id=?
           AND NOT EXISTS (SELECT 1 FROM turn_digests d
                            WHERE d.session_id=l.session_id
                              AND d.turn_index=l.turn_index)
         ORDER BY l.turn_index;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        var rows: [Int] = []
        while try stepRowOrDone(stmt) { rows.append(Int(sqlite3_column_int64(stmt, 0))) }
        return rows
    }

    /// 「缺什么」的五个数。它是**动作的入口**，不是报表：每个数都对应一次补录，
    /// 补完归零；没有对应动作的数（对象数、未寻址、损坏数）不放这里——那些要
    /// 看就去问代理，摆在按钮旁边只会让人以为按钮干完了这件事。
    public struct TurnGapCounts: Equatable, Sendable {
        /// 采集桥导进来了，但一行轮次账都没有的会话数。
        public let ledgerSessions: Int
        /// 账上有、摘要没有的轮数。
        public let digests: Int
        /// 有摘要、词不够的轮数。
        public let keywords: Int
        /// 账上有、来源时间为空的轮数。
        public let times: Int
        /// 有摘要、但没有任何房间归属的轮数。归属完整性是独立缺口：增量
        /// `assignTurnSpace` 撞锁失败时摘要已经落库，四项都看不到这次失败
        /// （#188）。口径排除「既无摘要也无归属」的轮次——那种轮次该由
        /// `digests` 说话。
        public let rooms: Int

        public var total: Int { ledgerSessions + digests + keywords + times + rooms }
    }

    private func scalarCount(_ sql: String) throws -> Int {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        return try stepRowOrDone(stmt) ? Int(sqlite3_column_int64(stmt, 0)) : 0
    }

    public func turnGapCounts() throws -> TurnGapCounts {
        var ledgerSessions = 0
        var digests = 0
        var times = 0
        if try tableExists("chat_turn_ledger") {
            ledgerSessions = try scalarCount("""
            SELECT COUNT(DISTINCT session_id) FROM chat_messages
             WHERE request_id IS NOT NULL
               AND session_id NOT IN (SELECT session_id FROM chat_turn_ledger);
            """)
            digests = try scalarCount("""
            SELECT COUNT(*) FROM chat_turn_ledger l
             WHERE NOT EXISTS (SELECT 1 FROM turn_digests d
                                WHERE d.session_id=l.session_id
                                  AND d.turn_index=l.turn_index);
            """)
            if try columnExists("chat_turn_ledger", "source_time") {
                times = try scalarCount(
                    "SELECT COUNT(*) FROM chat_turn_ledger WHERE source_time IS NULL;")
            } else {
                // 列都没有，就是一条都没回填过——这本身就是要补的那一格。
                times = try scalarCount("SELECT COUNT(*) FROM chat_turn_ledger;")
            }
        }
        return TurnGapCounts(
            ledgerSessions: ledgerSessions, digests: digests,
            keywords: try turnsWithThinKeywordsCount(), times: times,
            rooms: try digestsWithoutRoomCount())
    }

    /// 有摘要、但没有任何房间归属的轮数（#188 的第五项）。
    /// 口径与人工对照 SQL 一致：既无摘要也无归属的轮次不进这个数。
    private func digestsWithoutRoomCount() throws -> Int {
        // 摘要表都没有，就没有「有摘要无归属」这回事。
        guard try tableExists("turn_digests") else { return 0 }
        // 房间表是惰性建的。它还没建出来，不等于「归属都齐了」——恰恰相反：
        // 每条带摘要的轮都还没有归属。这里数全部摘要轮，不数 0（#188）。
        guard try tableExists("space_turns") else {
            return try scalarCount("SELECT COUNT(*) FROM turn_digests;")
        }
        return try scalarCount("""
        SELECT COUNT(*) FROM turn_digests d
         WHERE NOT EXISTS (SELECT 1 FROM space_turns st
                            WHERE st.session_id=d.session_id
                              AND st.turn_index=d.turn_index);
        """)
    }

    // MARK: - External-provider turns (recorded → verified → retrievable)

    /// Record an upstream-API turn's question as soon as its request arrives.
    /// The row keeps its provenance but stays `recorded`: an in-flight external
    /// request is information the space holds, not history another request may
    /// retrieve. Repeating the same request id returns the row already written
    /// instead of appending a duplicate.
    @discardableResult
    public func recordExternalTurn(
        sessionID: String, provider: String, requestID: String,
        userText: String, model: String?, createdAt: Date,
        eligibility: ChatTurnEligibility = .ordinary
    ) throws -> Int64 {
        let data = Data(userText.utf8)
        let digest = NativeSHA256.hexDigest(data)
        return try transactionResult {
            if let existing = try externalRowID(
                sessionID: sessionID, requestID: requestID, role: "user")
            {
                return existing
            }
            return try insertChatMessage(
                sessionID: sessionID, role: "user", data: data, digest: digest,
                model: model, createdAt: createdAt,
                state: Self.externalState(for: eligibility),
                sourceKind: .external, sourceProvider: provider, requestID: requestID)
        }
    }

    /// Record the upstream reply under the same provenance. Still `recorded`:
    /// a complete-looking body is evidence about the turn, not yet standing.
    @discardableResult
    public func recordExternalResponse(
        sessionID: String, provider: String, requestID: String,
        assistantText: String, model: String?, createdAt: Date,
        eligibility: ChatTurnEligibility = .ordinary
    ) throws -> Int64 {
        let data = Data(assistantText.utf8)
        let digest = NativeSHA256.hexDigest(data)
        return try transactionResult {
            if let existing = try externalRowID(
                sessionID: sessionID, requestID: requestID, role: "assistant")
            {
                return existing
            }
            return try insertChatMessage(
                sessionID: sessionID, role: "assistant", data: data, digest: digest,
                model: model, createdAt: createdAt,
                state: Self.externalState(for: eligibility),
                sourceKind: .external, sourceProvider: provider, requestID: requestID)
        }
    }

    /// A client that declares its call an internal operation keeps that status
    /// across the external path too: the turn is recorded for audit and no
    /// later verification can promote it.
    private static func externalState(for eligibility: ChatTurnEligibility) -> String {
        eligibility == .internalOperation
            ? eligibility.rawValue : ChatTurnState.recorded.rawValue
    }

    /// Promote one external turn from `recorded` to `committed`. Verification is
    /// keyed by (session, request id) and requires both sides of that request to
    /// be present, so an answer never becomes memory without the question it
    /// answers (nor the reverse). Rows of every other request are untouched.
    /// Returns the number of rows promoted; 0 means the turn is incomplete or
    /// already verified.
    @discardableResult
    public func verifyExternalTurn(
        sessionID: String, requestID: String, verifiedAt: Date
    ) throws -> Int {
        try transactionResult {
            guard try externalRowID(
                sessionID: sessionID, requestID: requestID, role: "user") != nil,
                try externalRowID(
                    sessionID: sessionID, requestID: requestID, role: "assistant") != nil
            else { return 0 }
            return try execBinding("""
            UPDATE chat_messages SET turn_state='committed', verified_at=?
            WHERE session_id=? AND request_id=? AND source_kind='external'
              AND turn_state='recorded';
            """) { stmt in
                try bind(stmt, 1, Self.stamp(verifiedAt))
                try bind(stmt, 2, sessionID)
                try bind(stmt, 3, requestID)
            }
        }
    }

    private func externalRowID(
        sessionID: String, requestID: String, role: String
    ) throws -> Int64? {
        let stmt = try prepare("""
        SELECT id FROM chat_messages
        WHERE session_id=? AND request_id=? AND source_kind='external' AND role=?
        ORDER BY id DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, requestID)
        try bind(stmt, 3, role)
        guard try stepRowOrDone(stmt) else { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    public struct ChatTurnProvenance: Equatable, Sendable {
        public let messageID: Int64
        public let sessionID: String
        public let role: String
        public let turnState: String
        public let sourceKind: String
        public let sourceProvider: String?
        public let requestID: String?
        public let verifiedAt: String?
        public let contentSHA256: String
        /// Ordinary standing is this row's own fact; whether a given request
        /// may consume it also depends on that request's scope.
        public var isEligible: Bool { turnState == "committed" }
    }

    /// Read back every line a request produced, with provenance and standing.
    /// Recorded rows are readable here without being eligible anywhere else.
    public func chatTurnProvenance(
        sessionID: String, requestID: String
    ) throws -> [ChatTurnProvenance] {
        try provenanceRows(
            where: "session_id=? AND request_id=?", sessionID, requestID)
    }

    /// Every line of a session in arrival order. Audit surfaces use this when
    /// the request id is not known in advance.
    public func chatTurnProvenance(
        sessionID: String
    ) throws -> [ChatTurnProvenance] {
        try provenanceRows(where: "session_id=?", sessionID)
    }

    private func provenanceRows(
        where clause: String, _ arguments: String...
    ) throws -> [ChatTurnProvenance] {
        let stmt = try prepare("""
        SELECT id, session_id, role, turn_state, source_kind, source_provider,
               request_id, verified_at, content_sha256
        FROM chat_messages
        WHERE \(clause) ORDER BY id;
        """)
        defer { sqlite3_finalize(stmt) }
        for (offset, argument) in arguments.enumerated() {
            try bind(stmt, Int32(offset + 1), argument)
        }
        var rows: [ChatTurnProvenance] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            rows.append(ChatTurnProvenance(
                messageID: sqlite3_column_int64(stmt, 0),
                sessionID: text(1) ?? "", role: text(2) ?? "",
                turnState: text(3) ?? "", sourceKind: text(4) ?? "",
                sourceProvider: text(5), requestID: text(6),
                verifiedAt: text(7), contentSHA256: text(8) ?? ""))
        }
        return rows
    }

    /// One completed external turn as text, for cross-carrier content dedupe.
    public struct ExternalTurnText: Sendable, Equatable {
        public let sessionID: String
        public let prompt: String
        public let answer: String
    }

    /// Whether this (session, request) pair already has its user row. The
    /// recorder is idempotent, so the caller needs this only to report an
    /// existing row as skipped rather than as newly written.
    public func externalTurnExists(sessionID: String, requestID: String) throws -> Bool {
        try externalRowID(sessionID: sessionID, requestID: requestID, role: "user") != nil
    }

    /// Every completed external turn whose session id begins with one of
    /// `prefixes`. The body is read back through `is_objects` because a
    /// committed row's inline `content` is emptied once it is object-addressed;
    /// comparing the emptied column would make every turn look different.
    ///
    /// This is a read-only aid for a carrier that re-describes history another
    /// carrier already delivered (an export of a session the native collector
    /// owns): identity by request id cannot see that duplication, only content
    /// can.
    public func externalTurnTexts(sessionPrefixes: [String]) throws -> [ExternalTurnText] {
        guard !sessionPrefixes.isEmpty else { return [] }
        let clause = sessionPrefixes.map { _ in "u.session_id LIKE ?" }
            .joined(separator: " OR ")
        let stmt = try prepare("""
        SELECT u.session_id,
               COALESCE(CAST(ou.content AS TEXT), u.content),
               COALESCE(CAST(oa.content AS TEXT), a.content)
        FROM chat_messages u
        JOIN chat_messages a
          ON a.session_id=u.session_id AND a.request_id=u.request_id
         AND a.role='assistant'
        LEFT JOIN is_objects ou ON ou.object_id=u.content_object_id
        LEFT JOIN is_objects oa ON oa.object_id=a.content_object_id
        WHERE u.role='user' AND u.source_kind='external' AND (\(clause));
        """)
        defer { sqlite3_finalize(stmt) }
        for (offset, prefix) in sessionPrefixes.enumerated() {
            try bind(stmt, Int32(offset + 1), prefix + "%")
        }
        var rows: [ExternalTurnText] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String {
                sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
            }
            rows.append(
                ExternalTurnText(sessionID: text(0), prompt: text(1), answer: text(2)))
        }
        return rows
    }

    // MARK: - MCP turn ledger

    /// What the ledger knows after recording one round number.
    ///
    /// `missing` is the number of round indices below the highest seen index
    /// that never arrived. It is a fact about calls, not about the agent's
    /// internals: a gap means the caller skipped a number it itself chose.
    public struct TurnLedgerReport: Sendable, Equatable {
        public let sessionID: String
        public let turnIndex: Int
        public let entered: Int
        public let highest: Int
        public let missing: [Int]
        /// Set when this round number already belongs to a different request.
        /// The ledger keeps the first owner; the second one is not silently
        /// merged, because two agents sharing a session id would otherwise
        /// lose a round each time their numbers collided.
        public let conflict: String?

        public var isContinuous: Bool { missing.isEmpty }

        func withConflict(_ owner: String) -> TurnLedgerReport {
            TurnLedgerReport(
                sessionID: sessionID, turnIndex: turnIndex, entered: entered,
                highest: highest, missing: missing, conflict: owner)
        }
    }

    /// Record that `turnIndex` arrived for `sessionID`, then report the ledger.
    /// Re-recording the same index is a no-op; the request id is kept from the
    /// first arrival so a retry cannot rewrite the round it named.
    public func recordTurnIndex(
        sessionID: String, turnIndex: Int, requestID: String, at: Date = Date()
    ) throws -> TurnLedgerReport {
        try transactionResult {
            if let owner = try turnLedgerOwner(sessionID: sessionID, turnIndex: turnIndex),
                owner != requestID
            {
                // Same slot, different owner. Refusing is the only honest
                // outcome: overwriting would rewrite history, and ignoring
                // would drop a round while the count still looked right.
                return try turnLedger(sessionID: sessionID, turnIndex: turnIndex)
                    .withConflict(owner)
            }
            try execBinding("""
            INSERT OR IGNORE INTO chat_turn_ledger(
                session_id, turn_index, request_id, seen_at) VALUES(?,?,?,?);
            """) { stmt in
                try bind(stmt, 1, sessionID)
                try bind(stmt, 2, Int64(turnIndex))
                try bind(stmt, 3, requestID)
                try bind(stmt, 4, Self.stamp(at))
            }
            return try turnLedger(sessionID: sessionID, turnIndex: turnIndex)
        }
    }

    private func turnLedgerOwner(sessionID: String, turnIndex: Int) throws -> String? {
        let stmt = try prepare("""
        SELECT request_id FROM chat_turn_ledger
        WHERE session_id=? AND turn_index=? LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, Int64(turnIndex))
        guard try stepRowOrDone(stmt), let text = sqlite3_column_text(stmt, 0)
        else { return nil }
        return String(cString: text)
    }

    /// Read-only ledger state for one session and the round just recorded.
    public func turnLedger(
        sessionID: String, turnIndex: Int = 0
    ) throws -> TurnLedgerReport {
        let stmt = try prepare("""
        SELECT turn_index FROM chat_turn_ledger
        WHERE session_id=? ORDER BY turn_index;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        var seen: [Int] = []
        while try stepRowOrDone(stmt) {
            seen.append(Int(sqlite3_column_int64(stmt, 0)))
        }
        let highest = seen.last ?? 0
        let present = Set(seen)
        let missing = (1...max(highest, 1)).filter { !present.contains($0) }
        return TurnLedgerReport(
            sessionID: sessionID, turnIndex: turnIndex, entered: seen.count,
            highest: highest, missing: missing, conflict: nil)
    }

    /// 导入的会话补轮次账的结果。
    public struct ImportedLedgerReport: Sendable, Equatable {
        /// 这次补进去的会话数（有候选、补之前一行账都没有的）。
        public let sessionsFilled: Int
        /// 这次补进去的轮数。
        public let turnsInserted: Int
        /// 已经有轮号、整会话跳过的外部会话数。
        public let sessionsKept: Int
        /// 没有 request_id、这次补不了的会话数与消息数。
        public let sessionsUnkeyed: Int
        public let messagesUnkeyed: Int
        /// 补完之后导入轮的总数（不只这次）。
        public let importedTurnsTotal: Int
    }

    /// 采集桥导入的历史会话，按到达序补一本轮次账。
    ///
    /// 只补「一行账都没有」的外部会话。已经有轮号的会话整会话跳过：MCP 的
    /// 轮号是调用方自己选的，导入的轮号是排出来的，两种编号混在一个 session
    /// 里，缺号就不再表示漏写。这条规矩靠 origin 列写进数据，不靠前缀去猜。
    ///
    /// 轮号 = 同一 request_id 的首条消息按 (时间, id) 排出的序。写在事务里，
    /// 重复调用是空操作。
    @discardableResult
    public func backfillImportedTurnLedger() throws -> ImportedLedgerReport {
        try transactionResult {
            func count(_ sql: String) throws -> Int {
                let stmt = try prepare(sql)
                defer { sqlite3_finalize(stmt) }
                return try stepRowOrDone(stmt) ? Int(sqlite3_column_int64(stmt, 0)) : 0
            }
            let kept = try count("""
            SELECT COUNT(DISTINCT m.session_id) FROM chat_messages m
             WHERE m.source_kind='external'
               AND EXISTS (SELECT 1 FROM chat_turn_ledger l
                            WHERE l.session_id=m.session_id);
            """)
            let unkeyedSessions = try count("""
            SELECT COUNT(DISTINCT session_id) FROM chat_messages
             WHERE request_id IS NULL
               AND session_id NOT IN (SELECT session_id FROM chat_turn_ledger);
            """)
            let unkeyedMessages = try count("""
            SELECT COUNT(*) FROM chat_messages
             WHERE request_id IS NULL
               AND session_id NOT IN (SELECT session_id FROM chat_turn_ledger);
            """)
            let fillable = try count("""
            SELECT COUNT(DISTINCT session_id) FROM chat_messages
             WHERE source_kind='external' AND request_id IS NOT NULL
               AND session_id NOT IN (SELECT session_id FROM chat_turn_ledger);
            """)
            try Self.rawExec(handle, """
            INSERT INTO chat_turn_ledger(
                session_id, turn_index, request_id, seen_at, origin)
            SELECT b.session_id,
                   ROW_NUMBER() OVER (
                       PARTITION BY b.session_id ORDER BY b.first_at, b.first_id),
                   b.request_id,
                   (SELECT m.created_at FROM chat_messages m WHERE m.id=b.first_id),
                   'import'
              FROM (SELECT session_id, request_id,
                           MIN(CAST(created_at AS REAL)) AS first_at,
                           MIN(id) AS first_id
                      FROM chat_messages
                     WHERE source_kind='external' AND request_id IS NOT NULL
                       AND session_id NOT IN (SELECT session_id FROM chat_turn_ledger)
                     GROUP BY session_id, request_id) b;
            """)
            return ImportedLedgerReport(
                sessionsFilled: fillable,
                turnsInserted: Int(sqlite3_changes(handle)),
                sessionsKept: kept,
                sessionsUnkeyed: unkeyedSessions,
                messagesUnkeyed: unkeyedMessages,
                importedTurnsTotal: try count(
                    "SELECT COUNT(*) FROM chat_turn_ledger WHERE origin='import';"))
        }
    }

    /// 某轮在账上记的 request id。导入的轮和 MCP 的轮都从这里读，
    /// 调用方不需要知道它是怎么排出来的。
    public func turnLedgerRequestID(sessionID: String, turnIndex: Int) throws -> String? {
        let stmt = try prepare("""
        SELECT request_id FROM chat_turn_ledger
         WHERE session_id=? AND turn_index=? LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, Int64(turnIndex))
        guard try stepRowOrDone(stmt), let c = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: c)
    }

    /// The session whose round arrived most recently, for a status display.
    public func latestTurnLedgerSessionID() throws -> String? {
        let stmt = try prepare("""
        SELECT session_id FROM chat_turn_ledger ORDER BY seen_at DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        guard try stepRowOrDone(stmt), let text = sqlite3_column_text(stmt, 0)
        else { return nil }
        return String(cString: text)
    }

    // MARK: - Project notes

    /// One recorded judgement. The row is immutable: a later note may supersede
    /// it, but nothing edits it, so the claim that was believed at a time stays
    /// readable after that time has passed.
    public struct ProjectNote: Equatable, Sendable {
        public let noteID: String
        public let kind: String
        public let claim: String
        public let supersedes: String?
        public let objectID: String
        public let recordedAt: String
    }

    /// Append a judgement of `kind` and supersede the current one of the same
    /// kind. "Current" is derived from the supersede pointers, never stored as a
    /// flag: a status bit is a second place that can disagree with the history.
    ///
    /// Recording a byte-identical claim again is a no-op — the object is already
    /// the current answer, so a second pointer would add history without adding
    /// a claim.
    @discardableResult
    public func recordProjectNote(
        kind: String, claim: String, at: Date = Date()
    ) throws -> (note: ProjectNote, superseded: String?, created: Bool) {
        let text = claim.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw DatabaseError.sql("project note claim is empty")
        }
        let trimmedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKind.isEmpty else {
            throw DatabaseError.sql("project note kind is empty")
        }
        return try transactionResult {
            let current = try currentProjectNote(kind: trimmedKind)
            let objectID = try ensureObject(Data(text.utf8))
            if let current, current.objectID == objectID {
                return (current, nil, false)
            }
            let noteID = UUID().uuidString
            let recordedAt = Self.stamp(at)
            try execBinding("""
            INSERT INTO project_notes(
                note_id, kind, claim, supersedes, object_id, recorded_at)
            VALUES(?,?,?,?,?,?);
            """) { stmt in
                try bind(stmt, 1, noteID)
                try bind(stmt, 2, trimmedKind)
                try bind(stmt, 3, text)
                try bind(stmt, 4, current?.noteID)
                try bind(stmt, 5, objectID)
                try bind(stmt, 6, recordedAt)
            }
            let note = ProjectNote(
                noteID: noteID, kind: trimmedKind, claim: text,
                supersedes: current?.noteID, objectID: objectID,
                recordedAt: recordedAt)
            return (note, current?.noteID, true)
        }
    }

    /// The note of `kind` that nothing later supersedes, if one was recorded.
    public func currentProjectNote(kind: String) throws -> ProjectNote? {
        let stmt = try prepare("""
        SELECT note_id, kind, claim, supersedes, object_id, recorded_at
          FROM project_notes
         WHERE kind = ?
           AND note_id NOT IN (
               SELECT supersedes FROM project_notes WHERE supersedes IS NOT NULL)
         ORDER BY rowid DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, kind)
        guard try stepRowOrDone(stmt) else { return nil }
        return projectNote(from: stmt)
    }

    /// Newest first. The whole history of a kind is what makes a changed
    /// judgement visible as a change instead of as a fact that was always so.
    public func projectNoteHistory(
        kind: String, limit: Int = 20
    ) throws -> [ProjectNote] {
        let stmt = try prepare("""
        SELECT note_id, kind, claim, supersedes, object_id, recorded_at
          FROM project_notes WHERE kind = ? ORDER BY rowid DESC LIMIT ?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, kind)
        try bind(stmt, 2, Int64(max(limit, 1)))
        var notes: [ProjectNote] = []
        while try stepRowOrDone(stmt) { notes.append(projectNote(from: stmt)) }
        return notes
    }

    public func projectNoteCount(kind: String) throws -> Int {
        let stmt = try prepare("SELECT COUNT(*) FROM project_notes WHERE kind = ?;")
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, kind)
        guard try stepRowOrDone(stmt) else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func projectNote(from stmt: OpaquePointer) -> ProjectNote {
        func text(_ i: Int32) -> String {
            sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
        }
        let supersedes = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
        return ProjectNote(
            noteID: text(0), kind: text(1), claim: text(2), supersedes: supersedes,
            objectID: text(4), recordedAt: text(5))
    }

    /// Most recent user row of a session, if it has one. Only local rows take
    /// part in retry reuse: an external row belongs to another producer's
    /// request and must never be adopted (or promoted) by a local turn.
    private func lastUserMessage(
        sessionID: String
    ) throws -> (messageID: Int64, digest: String, state: String)? {
        let stmt = try prepare("""
        SELECT id, content_sha256, turn_state FROM chat_messages
        WHERE session_id=? AND role='user' AND source_kind='local'
        ORDER BY id DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        guard try stepRowOrDone(stmt),
            let text = sqlite3_column_text(stmt, 1)
        else { return nil }
        let state = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
        return (sqlite3_column_int64(stmt, 0), String(cString: text), state)
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
        while try stepRowOrDone(stmt) {
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

    public struct ChatHit: Equatable, Sendable, Codable {
        public let sessionID: String
        public let messageID: Int64
        public let role: String
        public let lineNo: Int
        public let lineText: String
        public let contentSHA256: String
        public let createdAt: String
    }

    /// 对话检索：聊天信息一经落库即属信息空间，可按关键词作为 demand 的
    /// 一项输入被检索、结算与复用。只读已落库消息，不回放模型。
    public func searchChatMessages(
        query: String, sessionID: String? = nil, limit: Int = 200
    ) throws -> [ChatHit] {
        guard !query.isEmpty, limit > 0 else { return [] }
        var sql = """
        SELECT c.session_id, c.id, c.role,
               COALESCE(CAST(o.content AS TEXT), c.content),
               c.content_sha256, c.created_at
        FROM chat_messages c
        LEFT JOIN is_objects o ON o.object_id=c.content_object_id
        WHERE c.turn_state='committed'
        """
        if let sessionID {
            sql += " AND c.session_id='" + sessionID.replacingOccurrences(of: "'", with: "''") + "'"
        }
        sql += " ORDER BY c.session_id, c.id;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var hits: [ChatHit] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            let session = text(0) ?? ""
            let messageID = sqlite3_column_int64(stmt, 1)
            let role = text(2) ?? ""
            guard let body = text(3),
                NativeSHA256.hexDigest(Data(body.utf8)) == (text(4) ?? "")
            else { continue }
            for (idx, line) in body.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.localizedCaseInsensitiveContains(query) {
                hits.append(ChatHit(
                    sessionID: session, messageID: messageID, role: role,
                    lineNo: idx + 1, lineText: String(line.prefix(200)),
                    contentSHA256: text(4) ?? "", createdAt: text(5) ?? ""))
                if hits.count >= limit { return hits }
            }
        }
        return hits
    }

    public struct ChatIndexRow: Equatable, Sendable {
        public let sessionID: String
        public let messageID: Int64
        public let role: String
        public let content: String
        public let contentSHA256: String
        public let createdAt: String
        public var itemID: String { "chat:\(sessionID)/\(messageID)" }
    }

    /// Session scoping shared by every chat projection below. Ids are inlined
    /// as quoted literals, matching the rest of this file.
    private func sessionClause(_ sessionIDs: [String]?) -> String {
        guard let sessionIDs, !sessionIDs.isEmpty else { return "" }
        let quoted = sessionIDs.map {
            "'" + $0.replacingOccurrences(of: "'", with: "''") + "'"
        }
        return " AND c.session_id IN (\(quoted.joined(separator: ",")))"
    }

    /// Eligible chat messages as demand inputs, with their settled digest.
    /// Eligibility is the turn's own completion (`commitChatTurn`), not mere
    /// presence in the live table: another request's in-flight user text and a
    /// cancelled turn's input are conversation lines without semantic standing.
    ///
    /// `matchingAny` is a prefilter, never a filter: it drops rows that cannot
    /// mention any term, so every row kept here still has to survive the
    /// per-line `citationSnippet` byte scan. SQLite's default LIKE folds
    /// exactly the ASCII bytes `foldedASCII` folds and leaves every other byte
    /// alone, so the dropped set is provably empty of citations. It exists
    /// because materializing the space's 39.9 MB (5,720 rows over 806k lines)
    /// into Swift strings to find a few hundred hits costs 0.85 s, and the same
    /// predicate in C costs 0.02 s — measured 2026-11-09, 6 keywords,
    /// set-equal to the byte scan on the live space.
    ///
    /// 3 字以上的词走 `is_objects_fts`（trigram）索引；1–2 字的词 trigram 建不出
    /// 片段，回落原来的 LIKE 全扫。两条路的命中集合相同：索引只覆盖挂在
    /// is_objects 上的行，没有对象的行仍走 LIKE，两者的并集就是原来的 LIKE 结果。
    /// trigram 索引吃得下的关键词：至少 3 个字符（trigram 按 3 字片段建索引，
    /// 「合同」两个字的片段根本不存在）。按 Character 计，一个汉字算一个字符。
    static func isFTSEligible(_ term: String) -> Bool {
        term.count >= 3
    }

    /// FTS5 的字符串字面量：整串加双引号 = 短语，内部双引号翻倍。
    /// 加了引号，`%`、`_`、括号、冒号都只是普通字符，不会被当成查询语法。
    static func ftsPhrase(_ term: String) -> String {
        "\"" + term.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// LIKE 的转义（配合 `ESCAPE '\'`）。通配符在这里只是字面量。
    static func likeEscaped(_ term: String) -> String {
        term
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    /// 一轮摘要的检索行。摘要是索引、不是原文：命中之后用来定位的是
    /// `sessionID + turnIndex`，引用的字节仍是那一轮的原文对象
    /// （`answerObjectID`），给人看的那一行是摘要本身。
    struct TurnDigestIndexRow: Sendable {
        let sessionID: String
        let turnIndex: Int
        let digest: String
        let keywords: String
        let answerObjectID: String?
    }

    /// 摘要与关键词都参与匹配。行数是个人的轮次量级（今天 382 行），
    /// 所以走 LIKE，不另建索引——真上到十万轮再谈。
    func turnDigestRows(matchingAny: [String]?) throws -> [TurnDigestIndexRow] {
        let terms = (matchingAny ?? []).filter { !$0.isEmpty }
        var sql = """
        SELECT d.session_id, d.turn_index, d.digest, d.keywords, c.content_object_id
        FROM turn_digests d
        LEFT JOIN chat_messages c ON c.id = d.answer_message_id
        """
        var binds: [String] = []
        if !terms.isEmpty {
            var alternatives: [String] = []
            for term in terms {
                alternatives.append(
                    "(d.digest LIKE ? ESCAPE '\\' OR d.keywords LIKE ? ESCAPE '\\')")
                binds.append("%" + Self.likeEscaped(term) + "%")
                binds.append("%" + Self.likeEscaped(term) + "%")
            }
            sql += " WHERE " + alternatives.joined(separator: " OR ")
        }
        sql += " ORDER BY d.session_id, d.turn_index;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        for (idx, value) in binds.enumerated() {
            try bind(stmt, Int32(idx + 1), value)
        }
        var rows: [TurnDigestIndexRow] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            rows.append(TurnDigestIndexRow(
                sessionID: text(0) ?? "",
                turnIndex: Int(sqlite3_column_int64(stmt, 1)),
                digest: text(2) ?? "",
                keywords: text(3) ?? "",
                answerObjectID: text(4)))
        }
        return rows
    }

    /// 已提交的对话行（只读）。App 侧的回归要断言「结算失败之后没有留下 assistant
    /// 行」，用的就是这条读口；它返回的类型已经是 public，方法本身也一并公开。
    public func chatIndexRows(
        sessionIDs: [String]?, matchingAny: [String]? = nil
    ) throws -> [ChatIndexRow] {
        var sql = """
        SELECT c.session_id, c.id, c.role,
               COALESCE(CAST(o.content AS TEXT), c.content),
               c.content_sha256, c.created_at
        FROM chat_messages c
        LEFT JOIN is_objects o ON o.object_id=c.content_object_id
        WHERE c.turn_state='committed'
        """
        sql += sessionClause(sessionIDs)
        let terms = (matchingAny ?? []).filter { !$0.isEmpty }
        var binds: [String] = []
        if !terms.isEmpty {
            var alternatives: [String] = []
            for term in terms {
                if Self.isFTSEligible(term) {
                    // 索引命中的对象，加上没进索引的行（v28 起只索引结算产物，
                    // 其余行——没有对象的、没被结算引用过的——回落 LIKE）。
                    alternatives.append(
                        "(o.rowid IN (SELECT rowid FROM is_objects_fts"
                            + " WHERE is_objects_fts MATCH ?)"
                            + " OR ((o.rowid IS NULL"
                            + " OR o.rowid NOT IN (SELECT object_rowid FROM is_search_indexed))"
                            + " AND CAST(COALESCE(o.content, c.content) AS TEXT)"
                            + " LIKE ? ESCAPE '\\'))")
                    binds.append(Self.ftsPhrase(term))
                    binds.append("%" + Self.likeEscaped(term) + "%")
                } else {
                    alternatives.append(
                        "CAST(COALESCE(o.content, c.content) AS TEXT) LIKE ? ESCAPE '\\'")
                    binds.append("%" + Self.likeEscaped(term) + "%")
                }
            }
            sql += " AND (" + alternatives.joined(separator: " OR ") + ")"
        }
        sql += " ORDER BY c.session_id, c.id;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        for (idx, value) in binds.enumerated() {
            try bind(stmt, Int32(idx + 1), value)
        }
        var rows: [ChatIndexRow] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            rows.append(ChatIndexRow(
                sessionID: text(0) ?? "", messageID: sqlite3_column_int64(stmt, 1),
                role: text(2) ?? "", content: text(3) ?? "",
                contentSHA256: text(4) ?? "", createdAt: text(5) ?? ""))
        }
        return rows
    }

    public struct ChatScopeRow: Equatable, Sendable {
        public let sessionID: String
        public let messageID: Int64
        public let contentSHA256: String
        public var itemID: String { "chat:\(sessionID)/\(messageID)" }
    }

    /// The same rows `chatIndexRows` selects, reduced to identity and digest.
    /// A demand fingerprint built from these is byte-identical to one built
    /// from the full rows — same WHERE, same ORDER BY, same digest column — so
    /// scoping still sees every committed line while the chat bytes stay in
    /// SQLite.
    func chatScopeRows(sessionIDs: [String]?) throws -> [ChatScopeRow] {
        var sql = """
        SELECT c.session_id, c.id, c.content_sha256
        FROM chat_messages c
        WHERE c.turn_state='committed'
        """
        sql += sessionClause(sessionIDs)
        sql += " ORDER BY c.session_id, c.id;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var rows: [ChatScopeRow] = []
        while try stepRowOrDone(stmt) {
            rows.append(ChatScopeRow(
                sessionID: sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "",
                messageID: sqlite3_column_int64(stmt, 1),
                contentSHA256: sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""))
        }
        return rows
    }

    /// The carrier object currently addressed by an index identity. Index-only
    /// file rows point here at their metadata record, not at file bytes.
    public func latestIndexObjectID(identity: String) throws -> String? {
        let stmt = try prepare("""
        SELECT record_object FROM is_index_entries
        WHERE srs_identity=? ORDER BY append_order DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, identity)
        guard try stepRowOrDone(stmt), let c = sqlite3_column_text(stmt, 0)
        else { return nil }
        return String(cString: c)
    }

    // MARK: - ES demand / IS settlement seam

    public struct InformationDemandRow: Equatable, Sendable {
        public let demandID: String
        public let stateID: String?
        public let sessionID: String?
        public let query: String
        public let inputDigest: String
        public let retrievalSettlementID: String?
        public let state: String
    }

    public enum InformationDemandError: Error, Equatable {
        case missingDemand(String)
        case invalidTransition(demandID: String, from: String, to: String)
        case retrievalBindingMismatch(demandID: String, expected: String, actual: String)
        case retrievalSettlementUnavailable(String)
        /// The source a retrieval read is no longer the source the index holds:
        /// a root settlement committed between the read and this write. Nothing
        /// from the stale read is persisted; the caller must resolve again
        /// against the new revision.
        case sourceRevisionChanged(rootID: String, relativePath: String,
                                   expectedDigest: String, actualDigest: String?)
        case producerSettlementUnavailable(String)
        case advancementConflict(
            demandID: String, existingSettlementID: String, requestedSettlementID: String)
    }

    /// The settlement that most recently answered this exact question in this
    /// information scope, together with the retrieval settlement the demand was
    /// resolved against. Read-only: the protocol-layer gate decides whether the
    /// answer may be served without a model call.
    public struct AnsweredDemand: Equatable, Sendable {
        public let demandID: String
        public let answerSettlementID: String
        public let retrievalSettlementID: String?
        public let stateID: String
        public let advancedAt: String
    }

    public func answeredDemand(sessionID: String, query: String) throws -> AnsweredDemand? {
        let stmt = try prepare("""
        SELECT d.demand_id, a.settlement_id, d.retrieval_settlement_id,
               a.state_id, a.advanced_at
        FROM information_demands d
        JOIN information_advancements a ON a.demand_id=d.demand_id
        WHERE d.session_id=? AND d.query=? AND d.state='ADVANCED'
        ORDER BY a.rowid DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, query)
        guard try stepRowOrDone(stmt) else { return nil }
        func text(_ i: Int32) -> String? {
            sqlite3_column_text(stmt, i).map { String(cString: $0) }
        }
        let settlementID = text(1) ?? ""
        guard !settlementID.isEmpty else { return nil }
        return AnsweredDemand(
            demandID: text(0) ?? "", answerSettlementID: settlementID,
            retrievalSettlementID: text(2), stateID: text(3) ?? "",
            advancedAt: text(4) ?? "")
    }

    /// Every published answer for one exact session/question pair, in
    /// advancement order. Answer-reuse freshness excludes all of these
    /// answer summaries and their exact question/answer chat rows: after a
    /// replacement answer is committed, older answers must remain excluded too.
    public func answeredDemands(
        sessionID: String, query: String
    ) throws -> [AnsweredDemand] {
        let stmt = try prepare("""
        SELECT d.demand_id, a.settlement_id, d.retrieval_settlement_id,
               a.state_id, a.advanced_at
        FROM information_demands d
        JOIN information_advancements a ON a.demand_id=d.demand_id
        WHERE d.session_id=? AND d.query=? AND d.state='ADVANCED'
        ORDER BY a.rowid DESC;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, query)
        var rows: [AnsweredDemand] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            let settlementID = text(1) ?? ""
            guard !settlementID.isEmpty else {
                throw DatabaseError.sql(
                    "answeredDemands: published answer has an empty settlement identifier")
            }
            rows.append(AnsweredDemand(
                demandID: text(0) ?? "",
                answerSettlementID: settlementID,
                retrievalSettlementID: text(2),
                stateID: text(3) ?? "",
                advancedAt: text(4) ?? ""))
        }
        return rows
    }

    /// Publish the demand a settlement answers, so an exact repeat of the same
    /// question in the same session is serveable from the settlement without a
    /// model call. The advancement names the answer settlement and no retrieval
    /// settlement: a result produced without retrieval has no retrieval row, and
    /// the answer's own validity is then the whole dependency check.
    ///
    /// An invalid settlement is never published — a demand row must not outlive
    /// the validity of the result it points at.
    @discardableResult
    public func recordAnsweredDemand(
        stateID: String,
        sessionID: String,
        query: String,
        settlementID: String,
        actions: [String],
        advancedAt: Date = Date()
    ) throws -> String {
        guard let receipt = try settlementReceipt(settlementID),
            receipt.validity == "valid"
        else {
            throw DatabaseError.sql(
                "settlement \(settlementID) is not valid; a demand cannot be published for it")
        }
        let demandID = UUID().uuidString
        let advancementID = UUID().uuidString
        let requestIdentity = "session:\(sessionID)"
        let inputDigest = NativeSHA256.hexDigest(
            Data((try Self.canonicalJSON(["query": query, "session": sessionID])).utf8))
        let actionsJSON = (try? JSONSerialization.data(
            withJSONObject: actions, options: [.sortedKeys, .withoutEscapingSlashes]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let resultJSON = String(decoding: receipt.payload, as: UTF8.self)
        let now = Self.stamp(advancedAt)
        var publishedDemandID = demandID
        try transaction {
            // Re-publishing the same answer is a retry of one write, not a
            // second answer: the demand already published for this settlement
            // is returned instead of inserting a duplicate.
            let existing = try prepare("""
            SELECT d.demand_id FROM information_demands d
            JOIN information_advancements a ON a.demand_id=d.demand_id
            WHERE d.session_id=? AND d.query=? AND d.state='ADVANCED'
              AND a.settlement_id=?
            ORDER BY a.advanced_at DESC, a.advancement_id DESC LIMIT 1;
            """)
            defer { sqlite3_finalize(existing) }
            try bind(existing, 1, sessionID)
            try bind(existing, 2, query)
            try bind(existing, 3, settlementID)
            let found = try stepRowOrDone(existing)
            let existingDemandID = found
                ? sqlite3_column_text(existing, 0).map { String(cString: $0) } : nil
            try reset(existing)
            if let existingDemandID {
                publishedDemandID = existingDemandID
                return
            }
            try execBinding("""
            INSERT INTO information_demands(
                demand_id, state_id, session_id, continuation_point, query,
                required_item_ids_json, pending_obligations_json,
                continuation_conditions_json, input_digest, retrieval_demand_id,
                retrieval_settlement_id, state, created_at, request_identity)
            VALUES(?,?,?,'settled-answer',?,'[]','[]','[]',?,NULL,NULL,'ADVANCED',?,?);
            """) { stmt in
                try bind(stmt, 1, demandID)
                try bind(stmt, 2, stateID)
                try bind(stmt, 3, sessionID)
                try bind(stmt, 4, query)
                try bind(stmt, 5, inputDigest)
                try bind(stmt, 6, now)
                try bind(stmt, 7, requestIdentity)
            }
            try execBinding("""
            INSERT INTO information_advancements(
                advancement_id, demand_id, state_id, settlement_id,
                retrieval_settlement_id, actions_json, result_json, advanced_at)
            VALUES(?,?,?,?,NULL,?,?,?);
            """) { stmt in
                try bind(stmt, 1, advancementID)
                try bind(stmt, 2, demandID)
                try bind(stmt, 3, stateID)
                try bind(stmt, 4, settlementID)
                try bind(stmt, 5, actionsJSON)
                try bind(stmt, 6, resultJSON)
                try bind(stmt, 7, now)
            }
        }
        return publishedDemandID
    }

    // MARK: - Answer reuse record (zero-model-call turn)

    public struct InformationReuseEvent: Equatable, Sendable {
        public let reuseID: String
        public let sourceSettlementID: String
        public let sourceStateID: String
        public let demandID: String
        public let sessionID: String
        public let consumerStateID: String?
        public let canonicalDigest: String
        public let modelCalls: Int
        public let reusedAt: String
    }

    public enum InformationReuseError: Error, Equatable {
        case emptyField(String)
        case sourceNotValid(String)
    }

    /// Commit the reused assistant transcript and the zero-model-call reuse
    /// event together. A reader cannot observe one without the other.
    @discardableResult
    public func commitReusedChatTurn(
        _ chatTurn: ChatTurnCommit,
        sourceSettlementID: String,
        sourceStateID: String,
        demandID: String,
        query: String,
        reusedAt: Date = Date()
    ) throws -> Int64 {
        try transactionResult {
            let assistantID = try insertChatTurnRows(chatTurn)
            _ = try insertInformationReuseEvent(
                sourceSettlementID: sourceSettlementID,
                sourceStateID: sourceStateID,
                demandID: demandID,
                sessionID: chatTurn.sessionID,
                query: query,
                consumerStateID: nil,
                reusedAt: reusedAt)
            return assistantID
        }
    }

    /// Record that `demandID` was answered by an ALREADY-SETTLED result with zero
    /// model calls. The lookup gate ran before generation; validity is re-read
    /// inside this write, so a settlement invalidated in between can never be
    /// recorded as reused. `(sessionID, query)` is the exact key the lookup used;
    /// only its digest is stored because the demand row already carries the text.
    /// Re-recording the same demand returns the existing row unchanged.
    @discardableResult
    public func recordInformationReuse(
        sourceSettlementID: String,
        sourceStateID: String,
        demandID: String,
        sessionID: String,
        query: String,
        consumerStateID: String? = nil,
        reusedAt: Date = Date()
    ) throws -> InformationReuseEvent {
        try transactionResult {
            try insertInformationReuseEvent(
                sourceSettlementID: sourceSettlementID,
                sourceStateID: sourceStateID,
                demandID: demandID,
                sessionID: sessionID,
                query: query,
                consumerStateID: consumerStateID,
                reusedAt: reusedAt)
        }
    }

    /// Caller owns the transaction, allowing a reuse event to commit together
    /// with the chat transcript that records the answer being served.
    private func insertInformationReuseEvent(
        sourceSettlementID: String,
        sourceStateID: String,
        demandID: String,
        sessionID: String,
        query: String,
        consumerStateID: String?,
        reusedAt: Date
    ) throws -> InformationReuseEvent {
        guard !demandID.isEmpty else {
            throw InformationReuseError.emptyField("demand_id")
        }
        guard !sourceSettlementID.isEmpty else {
            throw InformationReuseError.emptyField("source_settlement_id")
        }
        let digest = NativeSHA256.hexDigest(Data("\(sessionID)|\(query)".utf8))
        if let existing = try informationReuseEvent(demandID: demandID) {
            return existing
        }
        guard let receipt = try settlementReceipt(sourceSettlementID),
            receipt.validity == "valid"
        else {
            throw InformationReuseError.sourceNotValid(sourceSettlementID)
        }
        let reuseID = UUID().uuidString
        let stamp = Self.stamp(reusedAt)
        try execBinding("""
        INSERT INTO information_reuse_events(
            reuse_id, source_settlement_id, source_state_id, demand_id,
            session_id, consumer_state_id, canonical_digest, model_calls,
            reused_at)
        VALUES(?,?,?,?,?,?,?,0,?);
        """) { stmt in
            try bind(stmt, 1, reuseID)
            try bind(stmt, 2, sourceSettlementID)
            try bind(stmt, 3, sourceStateID)
            try bind(stmt, 4, demandID)
            try bind(stmt, 5, sessionID)
            if let consumerStateID {
                try bind(stmt, 6, consumerStateID)
            } else {
                try bindNull(stmt, 6)
            }
            try bind(stmt, 7, digest)
            try bind(stmt, 8, stamp)
        }
        return InformationReuseEvent(
            reuseID: reuseID, sourceSettlementID: sourceSettlementID,
            sourceStateID: sourceStateID, demandID: demandID,
            sessionID: sessionID, consumerStateID: consumerStateID,
            canonicalDigest: digest, modelCalls: 0, reusedAt: stamp)
    }

    public func informationReuseEvent(demandID: String) throws -> InformationReuseEvent? {
        let stmt = try prepare("""
        SELECT reuse_id, source_settlement_id, source_state_id, demand_id,
               session_id, consumer_state_id, canonical_digest, model_calls,
               reused_at
        FROM information_reuse_events WHERE demand_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, demandID)
        guard try stepRowOrDone(stmt) else { return nil }
        func text(_ i: Int32) -> String {
            sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
        }
        return InformationReuseEvent(
            reuseID: text(0), sourceSettlementID: text(1), sourceStateID: text(2),
            demandID: text(3), sessionID: text(4),
            consumerStateID: sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : text(5),
            canonicalDigest: text(6),
            modelCalls: Int(sqlite3_column_int64(stmt, 7)),
            reusedAt: text(8))
    }

    public func informationDemand(demandID: String) throws -> InformationDemandRow? {
        let stmt = try prepare("""
        SELECT demand_id, state_id, session_id, query, input_digest,
               retrieval_settlement_id, state
        FROM information_demands WHERE demand_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, demandID)
        guard try stepRowOrDone(stmt) else { return nil }
        func text(_ i: Int32) -> String? {
            sqlite3_column_text(stmt, i).map { String(cString: $0) }
        }
        return InformationDemandRow(
            demandID: text(0) ?? "", stateID: text(1), sessionID: text(2),
            query: text(3) ?? "", inputDigest: text(4) ?? "",
            retrievalSettlementID: text(5), state: text(6) ?? "")
    }

    public struct InformationInput: Sendable {
        public let itemID: String
        public let contentAddress: String
        public init(itemID: String, contentAddress: String) {
            self.itemID = itemID
            self.contentAddress = contentAddress
        }
    }

    /// One physical source a retrieval actually read, with the digest that read
    /// was verified against. The digest is what makes the binding a claim about
    /// a *revision*: if the index has moved on by commit time, the claim is no
    /// longer true and the whole retrieval is refused rather than recorded.
    public struct SourceBinding: Sendable, Equatable {
        public let rootID: String
        public let relativePath: String
        public let binding: String
        public let expectedDigest: String
        public init(rootID: String, relativePath: String, binding: String = "content",
                    expectedDigest: String) {
            self.rootID = rootID
            self.relativePath = relativePath
            self.binding = binding
            self.expectedDigest = expectedDigest
        }
    }

    public struct InformationRetrievalWrite: Sendable {
        public let demandID: String
        public let stateID: String?
        public let sessionID: String?
        /// The demand's lifecycle identity. Two requests asking the same
        /// question share knowledge but never share request state, so this is
        /// what scopes the supersede rule below.
        public let requestIdentity: String?
        public let query: String
        public let rootIDs: [String]
        public let includeChat: Bool
        public let inputDigest: String
        public let payload: Data
        public let hitCount: Int
        public let itemIDs: [String]
        public let inputs: [InformationInput]
        /// Physical sources cited by this result. They are written inside the
        /// same transaction as the settlement, and each one is re-verified
        /// against `expectedDigest` first: a root settlement that committed
        /// between the read and this write invalidates the read, and an
        /// invalidation pass that ran in that gap would never see a binding
        /// written afterwards.
        public let sourceBindings: [SourceBinding]
        /// Settlements cited by this result. Each is validated (own validity,
        /// payload digest, upstream closure) inside the write transaction, so
        /// the edge cannot be added after its dependency was invalidated.
        public let citedSettlements: [String]
        public let evaluatedAt: Date

        public init(demandID: String, stateID: String?, sessionID: String?,
                    requestIdentity: String? = nil,
                    query: String, rootIDs: [String], includeChat: Bool,
                    inputDigest: String, payload: Data, hitCount: Int,
                    itemIDs: [String], inputs: [InformationInput],
                    sourceBindings: [SourceBinding] = [],
                    citedSettlements: [String] = [],
                    evaluatedAt: Date = Date()) {
            self.demandID = demandID; self.stateID = stateID
            self.sessionID = sessionID; self.requestIdentity = requestIdentity
            self.query = query
            self.rootIDs = rootIDs; self.includeChat = includeChat
            self.inputDigest = inputDigest; self.payload = payload
            self.hitCount = hitCount; self.itemIDs = itemIDs
            self.inputs = inputs
            self.sourceBindings = sourceBindings
            self.citedSettlements = citedSettlements
            self.evaluatedAt = evaluatedAt
        }
    }

    public struct InformationRetrievalCommit: Equatable, Sendable {
        public let retrievalSettlementID: String
        public let resultSHA256: String
        public let resultObjectID: String
    }

    /// Record one demand resolution as BOTH the IS retrieval settlement and the
    /// ES-visible settlement row, in a single transaction. The settlement row is
    /// `IS_RETRIEVAL` and carries no state: it is an IS-produced fact referenced
    /// by downstream model settlements through `dependency_edges`, never admitted
    /// as if a model had produced it.
    @discardableResult
    public func recordInformationRetrieval(
        _ write: InformationRetrievalWrite
    ) throws -> InformationRetrievalCommit {
        let resultSHA = NativeSHA256.hexDigest(write.payload)
        let settlementID = "is-retrieval:\(write.demandID)"
        var resultObjectID = ""
        let now = Self.stamp(write.evaluatedAt)
        try transaction {
            if let existing = try informationDemand(demandID: write.demandID) {
                guard existing.state == "RESOLVED" else {
                    throw InformationDemandError.invalidTransition(
                        demandID: write.demandID, from: existing.state, to: "RESOLVED")
                }
                guard existing.retrievalSettlementID == settlementID else {
                    throw InformationDemandError.retrievalBindingMismatch(
                        demandID: write.demandID,
                        expected: settlementID,
                        actual: existing.retrievalSettlementID ?? "")
                }
                // An invalidated or corrupt retrieval is not revived by writing
                // the same demand key again. A changed basis must get a new id.
                guard try informationRetrievalPayload(demandID: write.demandID) != nil else {
                    throw InformationDemandError.retrievalSettlementUnavailable(settlementID)
                }
            }
            resultObjectID = try ensureObject(write.payload)
            try execBinding("""
            INSERT INTO settlements(settlement_id, state_id, schema_version, payload, payload_digest, signature, contract_version, settled_at, validation_status, payload_object_id)
            VALUES(?,NULL,?,?,?,NULL,?,?,?,?)
            ON CONFLICT(settlement_id) DO UPDATE SET
                schema_version=excluded.schema_version, payload_digest=excluded.payload_digest,
                settled_at=excluded.settled_at, validation_status=excluded.validation_status,
                payload_object_id=excluded.payload_object_id;
            """) { stmt in
                try bind(stmt, 1, settlementID)
                try bind(stmt, 2, "simigo.information-demand/v1")
                try bind(stmt, 3, Data())
                try bind(stmt, 4, resultSHA)
                try bind(stmt, 5, "simigo.is-retrieval/v1")
                try bind(stmt, 6, now)
                try bind(stmt, 7, "IS_RETRIEVAL")
                try bind(stmt, 8, resultObjectID)
            }
            try recordSettlementValidityEventInTransaction(
                settlementID: settlementID, validity: "valid", cause: nil, at: now)
            _ = try appendIndexEntryInTransaction(
                identity: "settlement:\(settlementID)", objectID: resultObjectID)
            _ = try appendIndexEntryInTransaction(
                identity: "demand:\(write.demandID)", objectID: resultObjectID)

            try execBinding("""
            INSERT INTO retrieval_settlements(
                demand_id, query, root_ids, inputs_digest, result_sha256, result_json,
                hit_count, status, settled_at, result_object_id, include_chat, bridged_settlement_id)
            VALUES(?,?,?,?,?,'',?, 'valid',?,?,?,?)
            ON CONFLICT(demand_id) DO UPDATE SET
                query=excluded.query, root_ids=excluded.root_ids,
                inputs_digest=excluded.inputs_digest, result_sha256=excluded.result_sha256,
                result_json='', hit_count=excluded.hit_count, status='valid',
                settled_at=excluded.settled_at, result_object_id=excluded.result_object_id,
                include_chat=excluded.include_chat,
                bridged_settlement_id=excluded.bridged_settlement_id;
            """) { stmt in
                try bind(stmt, 1, write.demandID)
                try bind(stmt, 2, write.query)
                try bind(stmt, 3, write.rootIDs.joined(separator: ","))
                try bind(stmt, 4, "v2:\(write.inputDigest)")
                try bind(stmt, 5, resultSHA)
                try bind(stmt, 6, Int64(write.hitCount))
                try bind(stmt, 7, now)
                try bind(stmt, 8, resultObjectID)
                try bind(stmt, 9, Int64(write.includeChat ? 1 : 0))
                try bind(stmt, 10, settlementID)
            }

            let itemsJSON = (try? JSONSerialization.data(
                withJSONObject: write.itemIDs, options: [.sortedKeys, .withoutEscapingSlashes]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            let demandRows = try execBinding("""
            INSERT INTO information_demands(
                demand_id, state_id, session_id, continuation_point, query,
                required_item_ids_json, pending_obligations_json,
                continuation_conditions_json, input_digest, retrieval_demand_id,
                retrieval_settlement_id, state, created_at, request_identity)
            VALUES(?,?,?,'information-retrieval',?,?,'[]','[]',?,?,?,'RESOLVED',?,?)
            ON CONFLICT(demand_id) DO UPDATE SET
                state_id=excluded.state_id, session_id=excluded.session_id,
                query=excluded.query,
                required_item_ids_json=excluded.required_item_ids_json,
                input_digest=excluded.input_digest,
                retrieval_demand_id=excluded.retrieval_demand_id,
                retrieval_settlement_id=excluded.retrieval_settlement_id,
                request_identity=excluded.request_identity,
                state='RESOLVED'
            WHERE information_demands.state='RESOLVED';
            """) { stmt in
                try bind(stmt, 1, write.demandID)
                try bind(stmt, 2, write.stateID)
                try bind(stmt, 3, write.sessionID)
                try bind(stmt, 4, write.query)
                try bind(stmt, 5, itemsJSON)
                try bind(stmt, 6, write.inputDigest)
                try bind(stmt, 7, write.demandID)
                try bind(stmt, 8, settlementID)
                try bind(stmt, 9, now)
                try bind(stmt, 10, write.requestIdentity)
            }
            guard demandRows == 1 else {
                let current = try informationDemand(demandID: write.demandID)?.state ?? "missing"
                throw InformationDemandError.invalidTransition(
                    demandID: write.demandID, from: current, to: "RESOLVED")
            }
            // A newer resolution of the same question IN THE SAME REQUEST
            // supersedes the old one. Knowledge is shared across sessions, but
            // request state is not: another request — including a no-session
            // call — must never supersede this demand.
            try execBinding("""
            UPDATE information_demands SET state='SUPERSEDED'
            WHERE session_id IS ? AND request_identity IS ? AND query=?
              AND demand_id<>? AND state='RESOLVED';
            """) { stmt in
                try bind(stmt, 1, write.sessionID)
                try bind(stmt, 2, write.requestIdentity)
                try bind(stmt, 3, write.query)
                try bind(stmt, 4, write.demandID)
            }
            // 候选不写依赖表：write.inputs 是这次检索的候选集，不是结果依赖的
            // 信息。依赖边由 settlement_bindings 与 content-settle 那条路记，
            // 这里再记一遍只会让每次检索多出几百行路径。
            // Sources and cited settlements are part of the same atomic claim
            // as the result itself. Writing them after COMMIT left a window in
            // which the source update could invalidate the (empty) closure and
            // then the bindings would land behind the invalidation, leaving a
            // stale answer advertised as valid forever.
            for binding in write.sourceBindings {
                try insertVerifiedSourceBindingInTransaction(
                    settlementID: settlementID, binding: binding)
            }
            for cited in write.citedSettlements {
                try insertCitedSettlementEdgeInTransaction(
                    fromSettlement: settlementID, toSettlement: cited)
            }
        }
        return InformationRetrievalCommit(
            retrievalSettlementID: settlementID,
            resultSHA256: resultSHA, resultObjectID: resultObjectID)
    }

    /// Caller owns the transaction. Inserts one source binding only after the
    /// indexed revision still matches the digest the retrieval actually read.
    private func insertVerifiedSourceBindingInTransaction(
        settlementID: String, binding: SourceBinding
    ) throws {
        let stmt = try prepare("""
        SELECT e.file_id, COALESCE(e.status,'present'), c.content_sha256
        FROM external_files e
        LEFT JOIN file_contents c
          ON c.root_id=e.root_id AND c.relative_path=e.relative_path
        WHERE e.root_id=? AND e.relative_path=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, binding.rootID)
        try bind(stmt, 2, binding.relativePath)
        guard try stepRowOrDone(stmt) else {
            throw DatabaseError.sql(
                "recordInformationRetrieval: source file not indexed: "
                    + "\(binding.rootID)/\(binding.relativePath)")
        }
        let fileID = sqlite3_column_int64(stmt, 0)
        let status = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "present"
        let digest = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
        // A vanished or re-indexed source is a moved revision, not a result to
        // record: the retrieval described bytes that are no longer what this
        // path holds, and no later invalidation can reach a binding that has
        // not been written yet.
        guard status != "missing", digest == binding.expectedDigest else {
            throw InformationDemandError.sourceRevisionChanged(
                rootID: binding.rootID, relativePath: binding.relativePath,
                expectedDigest: binding.expectedDigest, actualDigest: digest)
        }
        try execBinding("""
        INSERT INTO settlement_bindings(settlement_id, name, value_digest, source_root_id, source_file_id)
        VALUES(?,?,'source',?,?);
        """) { stmt in
            try bind(stmt, 1, settlementID)
            try bind(stmt, 2, binding.binding)
            try bind(stmt, 3, binding.rootID)
            try bind(stmt, 4, fileID)
        }
        if let address = try fileContentObject(
            rootID: binding.rootID, relativePath: binding.relativePath)
        {
            _ = try appendDependencyInTransaction(
                dependencyID: "settlement:\(settlementID) -> "
                    + "file:\(binding.rootID)/\(binding.relativePath)",
                contentAddress: address,
                reason: "source-binding:\(binding.binding)")
        }
    }

    /// Caller owns the transaction. Validates the cited settlement under the
    /// same write lock that records the edge, so an upstream invalidation can
    /// neither precede the check nor slip in before the edge exists.
    private func insertCitedSettlementEdgeInTransaction(
        fromSettlement: String, toSettlement: String, kind: String = "citation"
    ) throws {
        let address = try validatedSettlementDependencyObjectID(toSettlement)
        try execBinding("""
        INSERT INTO dependency_edges(from_settlement, to_settlement, kind)
        SELECT ?,?,?
        WHERE NOT EXISTS (
            SELECT 1 FROM dependency_edges
            WHERE from_settlement=? AND to_settlement=? AND kind=?);
        """) { stmt in
            try bind(stmt, 1, fromSettlement)
            try bind(stmt, 2, toSettlement)
            try bind(stmt, 3, kind)
            try bind(stmt, 4, fromSettlement)
            try bind(stmt, 5, toSettlement)
            try bind(stmt, 6, kind)
        }
        _ = try appendDependencyInTransaction(
            dependencyID: "settlement:\(fromSettlement) -> settlement:\(toSettlement)",
            contentAddress: address, reason: kind)
    }

    /// The verified result payload of a recorded demand, or nil when the demand
    /// or its payload object is missing. Digest is re-checked against the row.
    /// A settlement invalidated by an upstream source change is never returned:
    /// the reader must re-execute against the new content revision.
    public func informationRetrievalPayload(demandID: String) throws -> Data? {
        let stmt = try prepare("""
        SELECT s.payload_digest, s.payload_object_id
        FROM retrieval_settlements r
        JOIN settlements s ON s.settlement_id=r.bridged_settlement_id
        JOIN settlement_current_validity v ON v.settlement_id=s.settlement_id
        WHERE r.demand_id=? AND r.status='valid'
          AND v.validity='valid' AND v.invalidated_at IS NULL;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, demandID)
        guard try stepRowOrDone(stmt) else { return nil }
        let digest = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
        guard let objectText = sqlite3_column_text(stmt, 1) else { return nil }
        let objectID = String(cString: objectText)
        let data = try readObject(objectID)
        guard NativeSHA256.hexDigest(data) == digest else {
            throw DatabaseError.sql(
                "informationRetrievalPayload: payload digest mismatch for demand \\(demandID)")
        }
        return data
    }

    public struct InformationAdvancementWrite: Sendable {
        public let demandID: String
        public let stateID: String
        public let settlementID: String
        public let retrievalSettlementID: String
        public let actions: [String]
        public let result: Data
        public let advancedAt: Date

        public init(demandID: String, stateID: String, settlementID: String,
                    retrievalSettlementID: String, actions: [String],
                    result: Data, advancedAt: Date = Date()) {
            self.demandID = demandID; self.stateID = stateID
            self.settlementID = settlementID
            self.retrievalSettlementID = retrievalSettlementID
            self.actions = actions; self.result = result
            self.advancedAt = advancedAt
        }
    }

    /// Mark a demand advanced by a settled model result: links the settlement to
    /// the retrieval settlement it depends on, so invalidating retrieved inputs
    /// cascades into every result derived from them.
    @discardableResult
    public func recordInformationAdvancement(
        _ write: InformationAdvancementWrite
    ) throws -> String {
        let advancementID = UUID().uuidString
        return try transactionResult {
            try insertInformationAdvancementRows(write, advancementID: advancementID)
        }
    }

    /// Commit a Responses continuation whose child settlement already exists.
    /// Chat, advancement, the session link and summary are committed together
    /// against that exact valid settlement.
    @discardableResult
    public func commitChatTurnWithExistingSettlement(
        _ chatTurn: ChatTurnCommit, settlementID: String, stateID: String,
        modelIdentity: String, demandID: String, retrievalSettlementID: String,
        actions: [String], query: String
    ) throws -> Int64 {
        guard !settlementID.isEmpty, !stateID.isEmpty,
              !demandID.isEmpty, !retrievalSettlementID.isEmpty else {
            throw DatabaseError.sql("existing-settlement chat commit requires complete identity")
        }
        return try transactionResult {
            guard let producer = try settlementReceipt(settlementID),
                  producer.validity == "valid", producer.stateID == stateID else {
                throw DatabaseError.sql("existing Responses settlement is missing, invalid or bound to another state")
            }
            guard let retrieval = try settlementReceipt(retrievalSettlementID),
                  retrieval.validity == "valid",
                  retrieval.validationStatus == "IS_RETRIEVAL" else {
                throw DatabaseError.sql("Responses retrieval settlement is missing, invalid or not an IS retrieval")
            }
            let assistantID = try insertChatTurnRows(chatTurn)
            _ = try insertInformationAdvancementRows(.init(
                demandID: demandID, stateID: stateID, settlementID: settlementID,
                retrievalSettlementID: retrievalSettlementID,
                actions: actions, result: producer.payload))
            try insertChatSessionLink(
                sessionID: chatTurn.sessionID, stateID: stateID, modelIdentity: modelIdentity)
            _ = try recordSettlementSummaryInTransaction(
                settlementID: settlementID, sessionID: chatTurn.sessionID,
                query: query, settledAt: chatTurn.createdAt)
            return assistantID
        }
    }

    /// Caller owns the transaction so advancement can commit atomically with the
    /// settlement and child state that produced it.
    @discardableResult
    func insertInformationAdvancementRows(
        _ write: InformationAdvancementWrite,
        advancementID: String = UUID().uuidString
    ) throws -> String {
        let actionsJSON = (try? JSONSerialization.data(
            withJSONObject: write.actions, options: [.sortedKeys, .withoutEscapingSlashes]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let resultJSON = String(decoding: write.result, as: UTF8.self)
        let now = Self.stamp(write.advancedAt)

        guard let demand = try informationDemand(demandID: write.demandID) else {
            throw InformationDemandError.missingDemand(write.demandID)
        }
        guard demand.retrievalSettlementID == write.retrievalSettlementID else {
            throw InformationDemandError.retrievalBindingMismatch(
                demandID: write.demandID,
                expected: demand.retrievalSettlementID ?? "",
                actual: write.retrievalSettlementID)
        }
        guard let retrieval = try settlementReceipt(write.retrievalSettlementID),
              retrieval.validity == "valid",
              retrieval.validationStatus == "IS_RETRIEVAL",
              try informationRetrievalPayload(demandID: write.demandID) != nil else {
            throw InformationDemandError.retrievalSettlementUnavailable(
                write.retrievalSettlementID)
        }
        guard let producer = try settlementReceipt(write.settlementID),
              producer.validity == "valid",
              producer.stateID == write.stateID else {
            throw InformationDemandError.producerSettlementUnavailable(write.settlementID)
        }

        // A retry of the same answer is idempotent. A different answer cannot
        // take over a demand that has already advanced.
        let existing = try prepare("""
        SELECT advancement_id, state_id, settlement_id,
               retrieval_settlement_id, actions_json, result_json
        FROM information_advancements
        WHERE demand_id=? ORDER BY rowid DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(existing) }
        try bind(existing, 1, write.demandID)
        if try stepRowOrDone(existing) {
            func text(_ index: Int32) -> String {
                sqlite3_column_text(existing, index)
                    .map { String(cString: $0) } ?? ""
            }
            let existingID = text(0)
            let existingState = text(1)
            let existingSettlement = text(2)
            let existingRetrieval = text(3)
            let existingActions = text(4)
            let existingResult = text(5)
            guard demand.state == "ADVANCED",
                  existingState == write.stateID,
                  existingSettlement == write.settlementID,
                  existingRetrieval == write.retrievalSettlementID,
                  existingActions == actionsJSON,
                  existingResult == resultJSON else {
                throw InformationDemandError.advancementConflict(
                    demandID: write.demandID,
                    existingSettlementID: existingSettlement,
                    requestedSettlementID: write.settlementID)
            }
            return existingID
        }
        guard demand.state == "RESOLVED" else {
            throw InformationDemandError.invalidTransition(
                demandID: write.demandID, from: demand.state, to: "ADVANCED")
        }
        let changed = try execBinding("""
        UPDATE information_demands SET state='ADVANCED'
        WHERE demand_id=? AND state='RESOLVED' AND retrieval_settlement_id=?;
        """) { stmt in
            try bind(stmt, 1, write.demandID)
            try bind(stmt, 2, write.retrievalSettlementID)
        }
        guard changed == 1 else {
            let current = try informationDemand(demandID: write.demandID)?.state ?? "missing"
            throw InformationDemandError.invalidTransition(
                demandID: write.demandID, from: current, to: "ADVANCED")
        }
        try execBinding("""
        INSERT INTO information_advancements(
            advancement_id, demand_id, state_id, settlement_id,
            retrieval_settlement_id, actions_json, result_json, advanced_at)
        VALUES(?,?,?,?,?,?,?,?);
        """) { stmt in
            try bind(stmt, 1, advancementID)
            try bind(stmt, 2, write.demandID)
            try bind(stmt, 3, write.stateID)
            try bind(stmt, 4, write.settlementID)
            try bind(stmt, 5, write.retrievalSettlementID)
            try bind(stmt, 6, actionsJSON)
            try bind(stmt, 7, resultJSON)
            try bind(stmt, 8, now)
        }
        try execBinding("""
        INSERT INTO dependency_edges(from_settlement, to_settlement, kind)
        SELECT ?,?,?
        WHERE NOT EXISTS (
            SELECT 1 FROM dependency_edges
            WHERE from_settlement=? AND to_settlement=? AND kind='information-demand');
        """) { stmt in
            try bind(stmt, 1, write.settlementID)
            try bind(stmt, 2, write.retrievalSettlementID)
            try bind(stmt, 3, "information-demand")
            try bind(stmt, 4, write.settlementID)
            try bind(stmt, 5, write.retrievalSettlementID)
        }
        if let address = try settlementPayloadObject(write.retrievalSettlementID) {
            _ = try appendDependencyInTransaction(
                dependencyID: "settlement:\(write.settlementID) -> settlement:\(write.retrievalSettlementID)",
                contentAddress: address,
                reason: "information-demand")
        }
        return advancementID
    }

    // MARK: - Settlement consumption (Stage B)

    /// Everything the write half of a consumption needs. The caller (see
    /// `SettlementConsumption`) has already re-admitted the named source
    /// and re-checked the contract/canonical basis INSIDE the same transaction;
    /// this plan is only the set of rows to commit.
    struct SettlementConsumptionPlan {
        let consumptionID: String
        let sourceSettlementID: String
        let sourcePayloadDigest: String
        let consumerState: ChildExecutionState
        let consumerIdentity: SettlementIdentityBinding.Identity
        let consumerResultContractJSON: Data
        let consumedValue: String
        let demandID: String
        let query: String
        let rootIDs: [String]
        let canonicalText: String
        let canonicalDigest: String
        let contractID: String
        let demandClass: String
        let contractVersion: String
        let requiredIdentityJSON: String
        let extractField: String
        let basisJSON: Data
        let consumedAt: Date
    }

    struct SettlementConsumptionCommit: Equatable, Sendable {
        let consumptionID: String
        let consumerSettlementID: String
        let advancementID: String
        let demandID: String
    }

    /// Write one consumption as a single authoritative unit. Caller owns the
    /// transaction, so the source re-admission and every row below either commit
    /// together or roll back together.
    ///
    /// The consumer settlement is `DERIVED_CONSUMPTION`: it carries the consumed
    /// value sealed under the consumer's result contract, binds the CONSUMER's
    /// identity (never the producer's), records no KV representation, and is
    /// linked to the source through both `dependency_edges` and the append-only
    /// dependency ledger. It is therefore chainable but never mistakable for a
    /// model generation.
    func recordSettlementConsumption(
        _ plan: SettlementConsumptionPlan
    ) throws -> SettlementConsumptionCommit {
        let settled = try SettlementAuthority.authorize(
            generatedText: plan.consumedValue,
            contractJSON: plan.consumerResultContractJSON,
            verifiedBindings: [:],
            settledAt: plan.consumedAt)
        let consumerSettlementID = UUID().uuidString
        let advancementID = UUID().uuidString

        try insertExecutionStateRow(
            id: plan.consumerState.id, parentID: plan.consumerState.parentID,
            modelIdentity: plan.consumerState.modelIdentity,
            position: plan.consumerState.position,
            continuationID: plan.consumerState.continuationID,
            anchor: plan.consumerState.anchor,
            lifecycle: "active", createdAt: plan.consumerState.createdAt,
            nextInput: plan.consumerState.nextInput,
            prefixJSON: plan.consumerState.prefixJSON)

        try insertNativeSettlementRows(
            settled, settlementID: consumerSettlementID,
            stateID: plan.consumerState.id,
            validationStatusOverride: "DERIVED_CONSUMPTION")
        try insertDerivedBindingRows(
            settlementID: consumerSettlementID,
            rows: SettlementIdentityBinding.consumerBindings(
                for: plan.consumerIdentity))

        try execBinding("""
        INSERT INTO settlement_consumptions(
            consumption_id, source_settlement_id, consumer_state_id,
            consumer_settlement_id, demand_id, contract_id, demand_class,
            contract_version, canonical_digest, basis_json, model_calls, created_at)
        VALUES(?,?,?,?,?,?,?,?,?,?,0,?);
        """) { stmt in
            try bind(stmt, 1, plan.consumptionID)
            try bind(stmt, 2, plan.sourceSettlementID)
            try bind(stmt, 3, plan.consumerState.id)
            try bind(stmt, 4, consumerSettlementID)
            try bind(stmt, 5, plan.demandID)
            try bind(stmt, 6, plan.contractID)
            try bind(stmt, 7, plan.demandClass)
            try bind(stmt, 8, plan.contractVersion)
            try bind(stmt, 9, plan.canonicalDigest)
            try bind(stmt, 10, plan.basisJSON)
            try bind(stmt, 11, Self.stamp(plan.consumedAt))
        }

        try execBinding("""
        INSERT INTO dependency_edges(from_settlement, to_settlement, kind)
        SELECT ?,?,?
        WHERE NOT EXISTS (
            SELECT 1 FROM dependency_edges
            WHERE from_settlement=? AND to_settlement=? AND kind='settlement-consumption');
        """) { stmt in
            try bind(stmt, 1, consumerSettlementID)
            try bind(stmt, 2, plan.sourceSettlementID)
            try bind(stmt, 3, "settlement-consumption")
            try bind(stmt, 4, consumerSettlementID)
            try bind(stmt, 5, plan.sourceSettlementID)
        }
        if let address = try settlementPayloadObject(plan.sourceSettlementID) {
            _ = try appendDependencyInTransaction(
                dependencyID: "settlement:\(consumerSettlementID) -> settlement:\(plan.sourceSettlementID)",
                contentAddress: address,
                reason: "settlement-consumption")
        }

        let itemsJSON = "[]"
        let demandRows = try execBinding("""
        INSERT INTO information_demands(
            demand_id, state_id, session_id, continuation_point, query,
            required_item_ids_json, pending_obligations_json,
            continuation_conditions_json, input_digest, retrieval_demand_id,
            retrieval_settlement_id, state, created_at)
        VALUES(?,?,NULL,'settlement-consumption',?,?,'[]','[]',?,NULL,NULL,'ADVANCED',?)
        ON CONFLICT(demand_id) DO UPDATE SET
            state_id=excluded.state_id, query=excluded.query,
            input_digest=excluded.input_digest, state='ADVANCED'
        WHERE information_demands.state='ADVANCED';
        """) { stmt in
            try bind(stmt, 1, plan.demandID)
            try bind(stmt, 2, plan.consumerState.id)
            try bind(stmt, 3, plan.query)
            try bind(stmt, 4, itemsJSON)
            try bind(stmt, 5, plan.canonicalDigest)
            try bind(stmt, 6, Self.stamp(plan.consumedAt))
        }
        guard demandRows == 1 else {
            let current = try informationDemand(demandID: plan.demandID)?.state ?? "missing"
            throw InformationDemandError.invalidTransition(
                demandID: plan.demandID, from: current, to: "ADVANCED")
        }
        try execBinding("""
        INSERT INTO information_advancements(
            advancement_id, demand_id, state_id, settlement_id,
            retrieval_settlement_id, actions_json, result_json, advanced_at)
        VALUES(?,?,?,?,NULL,?,?,?);
        """) { stmt in
            try bind(stmt, 1, advancementID)
            try bind(stmt, 2, plan.demandID)
            try bind(stmt, 3, plan.consumerState.id)
            try bind(stmt, 4, consumerSettlementID)
            try bind(stmt, 5, "[\"consume-settlement\"]")
            try bind(stmt, 6, String(decoding: settled.validatedPayload, as: UTF8.self))
            try bind(stmt, 7, Self.stamp(plan.consumedAt))
        }

        // A derived result is citable downstream, but only with its provenance.
        // The summary reads the consumption row written above.
        _ = try recordSettlementSummaryInTransaction(
            settlementID: consumerSettlementID, sessionID: nil,
            query: plan.query, settledAt: plan.consumedAt)

        return SettlementConsumptionCommit(
            consumptionID: plan.consumptionID,
            consumerSettlementID: consumerSettlementID,
            advancementID: advancementID,
            demandID: plan.demandID)
    }

    // MARK: - Settlement reuse declaration (Stage B)

    /// The reuse terms a settlement publishes at settlement time. A settlement
    /// without this row is NOT consumable: reusability is a declared property of
    /// the settled result, never inferred from text similarity.
    public struct SettlementReuseDeclaration: Equatable, Sendable {
        public let settlementID: String
        public let contractID: String
        public let demandClass: String
        public let contractVersion: String
        public let query: String
        public let rootIDs: [String]
        public let canonicalText: String
        public let canonicalDigest: String
        public let requiredIdentityJSON: String
        public let extractField: String
        public let declaredAt: String
    }

    /// Declare that `settlementID` may be consumed verbatim for exactly the
    /// canonical input basis computed here. Runs in its own write transaction,
    /// so the recorded basis is the basis at declaration time. Re-declaring the
    /// same terms is idempotent; changing them is refused rather than silently
    /// rewriting terms a consumer may already have relied on.
    @discardableResult
    public func declareSettlementReuseContract(
        settlementID: String,
        contractID: String,
        demandClass: String,
        contractVersion: String,
        query: String,
        rootIDs: [String]? = nil,
        extractField: String = "content",
        requiredConsumerIdentity: SettlementIdentityBinding.Identity? = nil,
        declaredAt: Date = Date()
    ) throws -> SettlementReuseDeclaration {
        try transactionResult {
            guard let row = try settlementAdmissionRow(settlementID: settlementID) else {
                throw SettlementConsumption.Refusal.unknownSource(settlementID)
            }
            guard row.validationStatus != "MIGRATED_LEGACY" else {
                throw SettlementConsumption.Refusal.unknownSource(settlementID)
            }
            guard row.validity == "valid" else {
                throw SettlementConsumption.Refusal.sourceNotValid(settlementID)
            }
            guard SettlementAuthority.payloadDigestMatches(
                row.payload, recordedDigest: row.recordedPayloadDigest)
            else {
                throw SettlementConsumption.Refusal.sourceTampered(settlementID)
            }
            let canonical = try canonicalDemandInput(query: query, rootIDs: rootIDs)
            // The declared root set is what the demand NAMED, not only the roots
            // that currently carry files: an extra empty root must still count as
            // a different demand.
            let requestedRoots = (rootIDs?.isEmpty == false)
                ? Array(Set(rootIDs!)).sorted()
                : canonical.rootIDs
            // Engine identity is provenance by default. It becomes a reuse
            // restriction only when the task explicitly declares the consumer
            // identity as semantically material.
            let identityJSON: String
            if let requiredConsumerIdentity {
                guard requiredConsumerIdentity.isSpecified else {
                    throw SettlementConsumption.Refusal.identityUndeclared(settlementID)
                }
                identityJSON = try Self.canonicalJSON([
                    "kind": "consumer",
                    "model": SettlementIdentityBinding.digest(requiredConsumerIdentity.model),
                    "tokenizer": SettlementIdentityBinding.digest(requiredConsumerIdentity.tokenizer),
                ])
            } else {
                identityJSON = "{}"
            }
            let rootsJSON = try Self.canonicalJSON(requestedRoots)

            if let existing = try settlementReuseContract(settlementID: settlementID) {
                let same = existing.contractID == contractID
                    && existing.demandClass == demandClass
                    && existing.contractVersion == contractVersion
                    && existing.query == query
                    && existing.rootIDs == requestedRoots
                    && existing.canonicalDigest == canonical.digest
                    // Omitting an option preserves an existing declaration's
                    // identity constraint; only an explicit replacement is compared.
                    && (requiredConsumerIdentity == nil
                        || existing.requiredIdentityJSON == identityJSON)
                    && existing.extractField == extractField
                guard same else {
                    throw SettlementConsumption.Refusal.contractMismatch(
                        field: "declaration", expected: existing.contractID,
                        actual: contractID)
                }
                return existing
            }

            let stamp = Self.stamp(declaredAt)
            try execBinding("""
            INSERT INTO settlement_reuse_contracts(
                settlement_id, contract_id, demand_class, contract_version,
                query, root_ids_json, canonical_text, canonical_digest,
                required_identity_json, extract_field, declared_at)
            VALUES(?,?,?,?,?,?,?,?,?,?,?);
            """) { stmt in
                try bind(stmt, 1, settlementID)
                try bind(stmt, 2, contractID)
                try bind(stmt, 3, demandClass)
                try bind(stmt, 4, contractVersion)
                try bind(stmt, 5, query)
                try bind(stmt, 6, rootsJSON)
                try bind(stmt, 7, canonical.canonical)
                try bind(stmt, 8, canonical.digest)
                try bind(stmt, 9, identityJSON)
                try bind(stmt, 10, extractField)
                try bind(stmt, 11, stamp)
            }
            return SettlementReuseDeclaration(
                settlementID: settlementID, contractID: contractID,
                demandClass: demandClass, contractVersion: contractVersion,
                query: query, rootIDs: requestedRoots,
                canonicalText: canonical.canonical,
                canonicalDigest: canonical.digest,
                requiredIdentityJSON: identityJSON,
                extractField: extractField, declaredAt: stamp)
        }
    }

    public func settlementReuseContract(
        settlementID: String
    ) throws -> SettlementReuseDeclaration? {
        let stmt = try prepare("""
        SELECT settlement_id, contract_id, demand_class, contract_version, query,
               root_ids_json, canonical_text, canonical_digest,
               required_identity_json, extract_field, declared_at
        FROM settlement_reuse_contracts WHERE settlement_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, settlementID)
        guard try stepRowOrDone(stmt) else { return nil }
        func text(_ i: Int32) -> String {
            sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
        }
        let roots = try JSONDecoder().decode([String].self, from: Data(text(5).utf8))
        guard roots == Array(Set(roots)).sorted() else {
            throw DatabaseError.sql(
                "settlementReuseContract: root_ids_json is not a canonical sorted unique array")
        }
        return SettlementReuseDeclaration(
            settlementID: text(0), contractID: text(1), demandClass: text(2),
            contractVersion: text(3), query: text(4), rootIDs: roots,
            canonicalText: text(6), canonicalDigest: text(7),
            requiredIdentityJSON: text(8), extractField: text(9),
            declaredAt: text(10))
    }

    public struct SettlementConsumptionRow: Equatable, Sendable {
        public let consumptionID: String
        public let sourceSettlementID: String
        public let consumerStateID: String
        public let consumerSettlementID: String
        public let demandID: String
        public let contractID: String
        public let demandClass: String
        public let contractVersion: String
        public let canonicalDigest: String
        public let basisJSON: Data
        public let modelCalls: Int
        public let createdAt: String
    }

    public func settlementConsumption(
        sourceSettlementID: String, consumerStateID: String, demandID: String
    ) throws -> SettlementConsumptionRow? {
        let stmt = try prepare("""
        SELECT consumption_id, source_settlement_id, consumer_state_id,
               consumer_settlement_id, demand_id, contract_id, demand_class,
               contract_version, canonical_digest, basis_json, model_calls, created_at
        FROM settlement_consumptions
        WHERE source_settlement_id=? AND consumer_state_id=? AND demand_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sourceSettlementID)
        try bind(stmt, 2, consumerStateID)
        try bind(stmt, 3, demandID)
        guard try stepRowOrDone(stmt) else { return nil }
        return Self.consumptionRow(stmt)
    }

    public func settlementConsumptions(
        consumerStateID: String
    ) throws -> [SettlementConsumptionRow] {
        let stmt = try prepare("""
        SELECT consumption_id, source_settlement_id, consumer_state_id,
               consumer_settlement_id, demand_id, contract_id, demand_class,
               contract_version, canonical_digest, basis_json, model_calls, created_at
        FROM settlement_consumptions WHERE consumer_state_id=?
        ORDER BY created_at, consumption_id;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, consumerStateID)
        var out: [SettlementConsumptionRow] = []
        while try stepRowOrDone(stmt) {
            out.append(Self.consumptionRow(stmt))
        }
        return out
    }

    private static func consumptionRow(
        _ stmt: OpaquePointer
    ) -> SettlementConsumptionRow {
        func text(_ i: Int32) -> String {
            sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
        }
        let bytes = Int(sqlite3_column_bytes(stmt, 9))
        let basis = sqlite3_column_blob(stmt, 9).map {
            Data(bytes: $0, count: bytes)
        } ?? Data()
        return SettlementConsumptionRow(
            consumptionID: text(0), sourceSettlementID: text(1),
            consumerStateID: text(2), consumerSettlementID: text(3),
            demandID: text(4), contractID: text(5), demandClass: text(6),
            contractVersion: text(7), canonicalDigest: text(8),
            basisJSON: basis, modelCalls: Int(sqlite3_column_int64(stmt, 10)),
            createdAt: text(11))
    }

    private static func canonicalJSON(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Chat session ↔ ES link

    public func linkChatSession(sessionID: String, stateID: String,
                                modelIdentity: String) throws {
        try insertChatSessionLink(sessionID: sessionID, stateID: stateID, modelIdentity: modelIdentity)
    }

    /// Caller owns the transaction when this helper is part of a larger write.
    private func insertChatSessionLink(
        sessionID: String, stateID: String, modelIdentity: String
    ) throws {
        try execBinding("""
        INSERT INTO chat_execution_links(session_id, current_state_id, model_identity, updated_at)
        VALUES(?,?,?,?)
        ON CONFLICT(session_id) DO UPDATE SET
            current_state_id=excluded.current_state_id,
            model_identity=excluded.model_identity,
            updated_at=excluded.updated_at;
        """) { stmt in
            try bind(stmt, 1, sessionID)
            try bind(stmt, 2, stateID)
            try bind(stmt, 3, modelIdentity)
            try bind(stmt, 4, Self.stamp(Date()))
        }
    }

    public func currentChatStateID(sessionID: String) throws -> String? {
        let stmt = try prepare("""
        SELECT current_state_id FROM chat_execution_links WHERE session_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        guard try stepRowOrDone(stmt), let c = sqlite3_column_text(stmt, 0)
        else { return nil }
        return String(cString: c)
    }

    /// The engine an execution state was begun under, or nil when no such state
    /// exists. A settle submitted later can only match it: replacing the engine
    /// mid-execution is a new state, not an identity swap on the same one.
    public func executionStateModelIdentity(_ stateID: String) throws -> String? {
        let stmt = try prepare("""
        SELECT model_identity FROM execution_states WHERE state_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, stateID)
        guard try stepRowOrDone(stmt), let c = sqlite3_column_text(stmt, 0)
        else { return nil }
        return String(cString: c)
    }

    /// Tokenizer identity fixed when an MCP execution state is first begun.
    /// Nil means legacy or non-MCP state; MCP settle/resume must fail closed.
    public func executionStateTokenizerIdentity(_ stateID: String) throws -> String? {
        let stmt = try prepare("""
        SELECT tokenizer_identity FROM execution_states WHERE state_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, stateID)
        guard try stepRowOrDone(stmt), let c = sqlite3_column_text(stmt, 0)
        else { return nil }
        return String(cString: c)
    }

    /// The parent edge a state was begun with, or nil for a root state / an
    /// unknown state. Read back so a settle cannot silently drop the edge.
    public func executionStateParentID(_ stateID: String) throws -> String? {
        let stmt = try prepare("""
        SELECT parent_id FROM execution_states WHERE state_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, stateID)
        guard try stepRowOrDone(stmt) else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    public func executionStatePosition(_ stateID: String) throws -> Int? {
        let stmt = try prepare("""
        SELECT position FROM execution_states WHERE state_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, stateID)
        guard try stepRowOrDone(stmt) else { return nil }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    /// Register or refresh an external root. Idempotent upsert keyed on root_id.
    public func upsertRoot(rootID: String, category: String, displayName: String?,
                           locatorType: String?, status: String) throws {
        let now = Self.stamp( Date())
        try execBinding("""
        INSERT INTO roots(root_id, category, display_name, locator_type, status, created_at, last_scanned_at)
        VALUES(?,?,?,?,?,?,NULL)
        ON CONFLICT(root_id) DO UPDATE SET
            category=excluded.category,
            display_name=COALESCE(excluded.display_name, display_name),
            locator_type=COALESCE(excluded.locator_type, locator_type),
            status=excluded.status;
        """) { stmt in
            try bind(stmt, 1, rootID)
            try bind(stmt, 2, category)
            try bind(stmt, 3, displayName)
            try bind(stmt, 4, locatorType)
            try bind(stmt, 5, status)
            try bind(stmt, 6, now)
        }
    }

    /// Record that a root has just been fully scanned. Kept separate from
    /// `upsertRoot` so metadata refreshes never claim a scan that did not run.
    public func markRootScanned(_ rootID: String, status: String = "present") throws {
        try execBinding("""
        UPDATE roots SET status=?, last_scanned_at=? WHERE root_id=?;
        """) { stmt in
            try bind(stmt, 1, status)
            try bind(stmt, 2, Self.stamp(Date()))
            try bind(stmt, 3, rootID)
        }
    }

    /// Change a root's state without pretending it was scanned — used when the
    /// backing directory is absent, so its carried content is left untouched.
    public func markRootStatus(_ rootID: String, status: String) throws {
        try execBinding("UPDATE roots SET status=? WHERE root_id=?;") { stmt in
            try bind(stmt, 1, status)
            try bind(stmt, 2, rootID)
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
            try bind(stmt, 1, rootID)
            try bind(stmt, 2, relativePath)
            try bind(stmt, 3, kind)
            try bind(stmt, 4, size)
            try bind(stmt, 5, modifiedAt)
            try bind(stmt, 6, contentDigest)
            try bind(stmt, 7, now)
            try bind(stmt, 8, now)
            try bind(stmt, 9, status)
        }
    }

    /// 目录导入（复核）：把选定目录里每个文件按（目录，文件名）落一行，标题从文件名推。
    ///
    /// 这就是「目录内文件路径和文件名复核」：磁盘上有的都有一行（二进制也一样，
    /// 内容为空、只落档）；库里有的、磁盘上没了，标 `missing`，**不删**——来源消失
    /// 不改历史。人改过的标题不覆盖：标题是显示名，重新导入只复核路径与文件名。
    ///
    /// 幂等：同名同路径重复导入只是刷新 size / modified / last_seen_at。
    @discardableResult
    public func importDirectoryNames(
        rootID: String, rootURL: URL, maxDepth: Int = 64,
        maxObservedFiles: Int = 4_096, maxVisitedEntries: Int = 16_384
    ) throws -> DirectoryNameImportReport {
        let root = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let scanRootInode = try Self.directoryINode(atPath: root.path)
        let entries = try Self.manifestWalk(
            root: root, maxDepth: maxDepth, skipping: nil,
            maxObservedFiles: maxObservedFiles, maxVisitedEntries: maxVisitedEntries)
        if let scanRootInode,
           try Self.directoryINode(atPath: root.path) != scanRootInode {
            throw DatabaseError.sql(
                "importDirectoryNames: root directory changed during enumeration")
        }
        let mainStems = Self.mainStemsByDirectory(entries)
        let stamp = Self.manifestFormatter()

        return try transactionResult {
            if let scanRootInode,
               try Self.directoryINode(atPath: root.path) != scanRootInode {
                throw DatabaseError.sql(
                    "importDirectoryNames: root directory changed before inventory commit")
            }
            // Root ID is a stable locator identity, not a reusable bucket for
            // whichever directory the caller selected most recently.
            let rootRecord: (locatorType: String, displayName: String)?
            do {
                let probe = try prepare("""
                SELECT locator_type, display_name FROM roots WHERE root_id=?;
                """)
                defer { sqlite3_finalize(probe) }
                try bind(probe, 1, rootID)
                if try stepRowOrDone(probe) {
                    let locatorType = sqlite3_column_text(probe, 0)
                        .map { String(cString: $0) } ?? ""
                    let displayName = sqlite3_column_text(probe, 1)
                        .map { String(cString: $0) } ?? ""
                    rootRecord = (locatorType, displayName)
                } else {
                    rootRecord = nil
                }
            }
            if let rootRecord {
                guard rootRecord.locatorType == "path", !rootRecord.displayName.isEmpty else {
                    throw DatabaseError.sql(
                        "importDirectoryNames: root \(rootID) has no path locator")
                }
                let registeredPath = URL(fileURLWithPath: rootRecord.displayName)
                    .resolvingSymlinksInPath().standardizedFileURL.path
                guard registeredPath == root.path else {
                    throw DatabaseError.sql(
                        "importDirectoryNames: registered root locator changed for \(rootID)")
                }
            } else {
                try upsertRoot(rootID: rootID, category: "work", displayName: root.path,
                               locatorType: "path", status: "registered")
            }
            // 甲：加目录这个人的动作顺带定下空间的身份。已经有空间就不动——
            // 重新导入只复核路径与文件名，人改过的标题不会被覆盖。
            try ensureSpaceForRoot(rootID: rootID, folderName: root.lastPathComponent)
            // 同一个路径换了目录（挂载被替换 / bind mount / 换卷）：这份
            // 清单证明不了旧文件已经不在，不许据此标 missing。
            let identityChanged = try noteLocatorIdentity(
                rootID: rootID, path: root.path)
            guard !identityChanged else {
                throw DatabaseError.sql(
                    "importDirectoryNames: root directory identity changed; "
                        + "adoptRootLocatorIdentity must be called before importing")
            }

            var known: [String: String] = [:]
            let select = try prepare(
                "SELECT relative_path, COALESCE(title,'') FROM external_files WHERE root_id=?;")
            defer { sqlite3_finalize(select) }
            try bind(select, 1, rootID)
            while try stepRowOrDone(select) {
                let path = sqlite3_column_text(select, 0).map { String(cString: $0) } ?? ""
                let title = sqlite3_column_text(select, 1).map { String(cString: $0) } ?? ""
                known[path] = title
            }

            var inserted = 0
            var refreshed = 0
            for (relative, url) in entries {
                let directory = (relative as NSString).deletingLastPathComponent
                let (derived, _) = Self.manifestTitle(
                    ofFile: url.lastPathComponent, mainStem: mainStems[directory])
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attributes[.size] as? NSNumber)?.int64Value
                let modified = (attributes[.modificationDate] as? Date)
                    .map { stamp.string(from: $0) }
                let previous = known.removeValue(forKey: relative)
                let title = (previous?.isEmpty == false) ? previous! : derived
                let now = Self.stamp(Date())
                try execBinding("""
                INSERT INTO external_files(root_id, relative_path, kind, size, modified_at,
                    content_digest, indexed_at, last_seen_at, status, title, title_source)
                VALUES(?,?,NULL,?,?,NULL,?,?,'present',?,'filename')
                ON CONFLICT(root_id, relative_path) DO UPDATE SET
                    size=excluded.size, modified_at=excluded.modified_at,
                    last_seen_at=excluded.last_seen_at, status='present',
                    title=excluded.title;
                """) { stmt in
                    try bind(stmt, 1, rootID)
                    try bind(stmt, 2, relative)
                    try bind(stmt, 3, size)
                    try bind(stmt, 4, modified)
                    try bind(stmt, 5, now)
                    try bind(stmt, 6, now)
                    try bind(stmt, 7, title)
                }
                if previous == nil { inserted += 1 } else { refreshed += 1 }
            }

            if !identityChanged {
                for relative in known.keys {
                    try execBinding("""
                    UPDATE external_files SET status='missing'
                     WHERE root_id=? AND relative_path=?;
                    """) { stmt in
                        try bind(stmt, 1, rootID)
                        try bind(stmt, 2, relative)
                    }
                }
            }

            if let scanRootInode,
               try Self.directoryINode(atPath: root.path) != scanRootInode {
                throw DatabaseError.sql(
                    "importDirectoryNames: root directory changed during inventory commit")
            }
            return DirectoryNameImportReport(
                files: entries.count, inserted: inserted, refreshed: refreshed,
                missing: known.count)
        }
    }

    /// 目录第一次进来时给它一个空间：标题取文件夹名，标成占位（'filename'）。
    /// 已有空间就什么都不做——重新导入是复核路径，不是重新定身份。
    private func ensureSpaceForRoot(rootID: String, folderName: String) throws {
        guard !folderName.isEmpty else { return }
        let probe = try prepare("SELECT space_id FROM roots WHERE root_id=?;")
        try bind(probe, 1, rootID)
        let found = try stepRowOrDone(probe)
        let alreadySet = found && sqlite3_column_type(probe, 0) != SQLITE_NULL
        sqlite3_finalize(probe)
        guard found, !alreadySet else { return }
        let space = try createSpace(
            title: folderName, kind: "directory", titleSource: "filename")
        try setRootSpace(rootID: rootID, spaceID: space.spaceID)
    }

    /// 人改标题：只改给人看的名字，不动唯一键（root_id + relative_path）。
    /// 改过之后重新导入目录不会覆盖它。
    public func updateExternalFileTitle(
        rootID: String, relativePath: String, title: String
    ) throws {
        try execBinding("""
        UPDATE external_files SET title=?, title_source='human'
         WHERE root_id=? AND relative_path=?;
        """) { stmt in
            try bind(stmt, 1, title)
            try bind(stmt, 2, rootID)
            try bind(stmt, 3, relativePath)
        }
    }

    /// 读一行的标题（复核用）。
    public func externalFileTitle(rootID: String, relativePath: String) throws -> String? {
        let stmt = try prepare(
            "SELECT title FROM external_files WHERE root_id=? AND relative_path=?;")
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, rootID)
        try bind(stmt, 2, relativePath)
        guard try stepRowOrDone(stmt), let c = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: c)
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
            try bind(stmt, 1, sessionID)
            try bind(stmt, 2, adapterID)
            try bind(stmt, 3, sourceRootID)
            try bind(stmt, 4, metadataDigest)
            try bind(stmt, 5, syncStatus)
            try bind(stmt, 6, now)
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
        while try stepRowOrDone(stmt) {
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
        try bind(stmt, 1, rootID)
        try bind(stmt, 2, relativePath)
        if try stepRowOrDone(stmt) { return sqlite3_column_int64(stmt, 0) }
        return nil
    }

    /// Read the stored content digest for an indexed external file (nil if absent).
    public func externalFileDigest(rootID: String, relativePath: String) throws -> String? {
        let stmt = try prepare("SELECT content_digest FROM external_files WHERE root_id=? AND relative_path=?;")
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, rootID)
        try bind(stmt, 2, relativePath)
        if try stepRowOrDone(stmt), let c = sqlite3_column_text(stmt, 0) {
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
                try bind(stmt, 1, settlementID)
                try bind(stmt, 2, binding)
                try bind(stmt, 3, rootID)
                try bind(stmt, 4, fileID)
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
    ///
    /// Low-level entry: it performs no lifecycle check, so prefer the two
    /// internal writers (`insertInformationAdvancementRows` for
    /// information-demand, `recordSettlementConsumption` for
    /// settlement-consumption) on the paths they own. Repeating the same
    /// (from, to, kind) is a no-op, which keeps in-degree equal to the number of
    /// distinct dependencies.
    public func addDependency(fromSettlement: String, toSettlement: String,
                              kind: String = "depends") throws {
        try transaction {
            try execBinding("""
            INSERT INTO dependency_edges(from_settlement, to_settlement, kind)
            SELECT ?,?,?
            WHERE NOT EXISTS (
                SELECT 1 FROM dependency_edges
                WHERE from_settlement=? AND to_settlement=? AND kind=?);
            """) { stmt in
                try bind(stmt, 1, fromSettlement)
                try bind(stmt, 2, toSettlement)
                try bind(stmt, 3, kind)
                try bind(stmt, 4, fromSettlement)
                try bind(stmt, 5, toSettlement)
                try bind(stmt, 6, kind)
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
        try bind(stmt, 1, settlementID)
        guard try stepRowOrDone(stmt), let c = sqlite3_column_text(stmt, 0) else {
            return nil
        }
        return String(cString: c)
    }

    /// Validate an upstream settlement under the caller's write transaction and
    /// return its content-addressed payload object. This closes the admission /
    /// child-commit race: invalidation cannot slip between this check and edge
    /// insertion, and a later invalidation follows the persisted edge.
    private func validatedSettlementDependencyObjectID(_ settlementID: String) throws -> String {
        guard let row = try settlementAdmissionRow(settlementID: settlementID),
              row.validationStatus != "MIGRATED_LEGACY" else {
            throw DatabaseError.sql("settlement dependency is unavailable: \(settlementID)")
        }
        guard SettlementAuthority.payloadDigestMatches(
            row.payload, recordedDigest: row.recordedPayloadDigest) else {
            throw DatabaseError.sql("settlement dependency payload digest mismatch: \(settlementID)")
        }
        guard row.validity == "valid" else {
            throw DatabaseError.sql("settlement dependency is invalid: \(settlementID)")
        }
        for upstream in try upstreamDependencyClosure(ofSettlement: settlementID) {
            guard try settlementValidity(upstream) == "valid" else {
                throw DatabaseError.sql(
                    "settlement dependency closure contains invalid member: \(upstream)")
            }
        }
        guard let objectID = try settlementPayloadObject(settlementID),
              !objectID.isEmpty, try objectRow(objectID) != nil else {
            throw DatabaseError.sql("settlement dependency payload object is missing: \(settlementID)")
        }
        return objectID
    }

    /// Content address of a settled file, when its bytes are carried.
    private func fileContentObject(rootID: String, relativePath: String) throws -> String? {
        let stmt = try prepare("""
        SELECT object_id FROM file_contents WHERE root_id=? AND relative_path=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, rootID)
        try bind(stmt, 2, relativePath)
        guard try stepRowOrDone(stmt), let c = sqlite3_column_text(stmt, 0) else {
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
        try bind(stmt, 1, rootID)
        try bind(stmt, 2, relativePath)
        var out: [String] = []
        while try stepRowOrDone(stmt) {
            guard let c = sqlite3_column_text(stmt, 0) else {
                throw DatabaseError.sql("affectedClosure: NULL identifier")
            }
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
        // Acquire the writer lock before reading the dependency closure. Otherwise
        // a concurrent binding/edge can be committed after the snapshot and remain
        // valid even though its source is being invalidated.
        return try transactionResult {
            let ids = try affectedClosure(rootID: rootID, relativePath: relativePath)
            try markSettlementsInvalidInTransaction(
                ids, cause: "source-file:\(rootID)/\(relativePath)")
            return ids
        }
    }

    /// Caller owns the transaction. Flips only valid rows so repeated
    /// invalidation is idempotent and never rewrites an earlier timestamp.
    private func markSettlementsInvalidInTransaction(_ ids: [String],
                                                     cause: String) throws {
        guard !ids.isEmpty else { return }
        let now = Self.stamp(Date())
        for id in ids {
            try recordSettlementValidityEventInTransaction(
                settlementID: id, validity: "invalid", cause: cause, at: now)
            // A bridged retrieval row is the demand-side view of the same
            // settlement. Leaving it 'valid' would advertise reuse to every
            // reader that keys on status alone.
            try execBinding("""
            UPDATE retrieval_settlements SET status='invalidated'
            WHERE bridged_settlement_id=? AND status='valid';
            """) { stmt in
                try bind(stmt, 1, id)
            }
        }
    }

    /// Append one validity event unless the settlement is already in that
    /// state. This is the only way validity changes; the settlement row itself
    /// is never rewritten for it. The ledger is the record and
    /// `settlement_current_validity` is the derived read.
    private func recordSettlementValidityEventInTransaction(
        settlementID: String, validity: String, cause: String?, at stamp: String
    ) throws {
        try execBinding("""
        INSERT INTO settlement_validity_events(
            settlement_id, validity, cause, recorded_at)
        SELECT ?,?,?,?
         WHERE NOT EXISTS (
            SELECT 1 FROM settlement_validity_events
             WHERE settlement_id=? AND validity=?);
        """) { stmt in
            try bind(stmt, 1, settlementID)
            try bind(stmt, 2, validity)
            try bind(stmt, 3, cause)
            try bind(stmt, 4, stamp)
            try bind(stmt, 5, settlementID)
            try bind(stmt, 6, validity)
        }
    }

    /// Caller owns the transaction. A demand is stale when its recorded input
    /// basis contains the changed file's previous address. The demand id itself
    /// will differ after the change; this only makes the recorded state honest.
    ///
    /// The two needles below match only rows whose basis is stored in the
    /// legacy shape — the canonical string and filename list written by
    /// `executeInformationDemand`. Rows written by `recordInformationRetrieval`
    /// carry `v2:<demand hash>`, which contains neither needle, so they are
    /// invalidated through their bridged settlement instead (see
    /// `markSettlementsInvalidInTransaction`). Both routes are needed while
    /// legacy databases exist; neither is a substitute for the other.
    private func invalidateRetrievalSettlementsInTransaction(
        rootID: String, relativePath: String, oldDigest: String
    ) throws {
        // File-content rows contribute their previous digest to the canonical
        // input string. Filename-only candidates (binary/oversized files) have
        // no such digest, so their canonical root/path token must also invalidate
        // the retrieval that cited the filename.
        if !oldDigest.isEmpty {
            let digestNeedle = "\(rootID)/\(relativePath)=\(oldDigest)"
            try execBinding("""
            UPDATE retrieval_settlements SET status='invalidated'
            WHERE status='valid' AND instr(inputs_digest, ?) > 0;
            """) { stmt in
                try bind(stmt, 1, digestNeedle)
            }
        }
        let filenameNeedle = try Self.canonicalJSON([
            "root_id": rootID,
            "relative_path": relativePath,
        ])
        try execBinding("""
        UPDATE retrieval_settlements SET status='invalidated'
        WHERE status='valid' AND instr(inputs_digest, ?) > 0;
        """) { stmt in
            try bind(stmt, 1, filenameNeedle)
        }
        // Legacy v1 demand rows stored only the content digest string and did
        // not persist filename-only candidates or explicit root scope. Their
        // provenance cannot prove that a filename-only source was absent, so
        // invalidate these legacy rows on any source-path change rather than
        // leaving an unverifiable retrieval advertised as valid.
        try execBinding("""
        UPDATE retrieval_settlements SET status='invalidated'
        WHERE status='valid' AND inputs_digest LIKE 'legacy-v1:%';
        """) { _ in }
    }

    /// Reconciliation for lost watcher events: mark indexed files under a root
    /// that were NOT observed in the latest scan as 'missing' and invalidate
    /// their dependency closures. Returns every settlement invalidated by the
    /// sweep.
    ///
    /// The carried content is deliberately kept. A vanished source makes the
    /// original unreachable, not the information gone: `file_contents` is what
    /// retrieval reads from, so deleting it would turn "temporarily unreachable"
    /// into "no longer exists" and erase history the store is supposed to keep.
    /// Only the file's status changes.
    @discardableResult
    public func reconcileRoot(rootID: String, seenRelativePaths: Set<String>) throws -> [String] {
        // Hold the write lock for both the inventory snapshot and the missing-path
        // mutations. A root settlement cannot update this inventory between them.
        return try transactionResult {
            let stmt = try prepare("""
            SELECT relative_path FROM external_files
            WHERE root_id=? AND COALESCE(status,'present')<>'missing';
            """)
            defer { sqlite3_finalize(stmt) }
            try bind(stmt, 1, rootID)
            var indexed: [String] = []
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_ROW {
                    guard let c = sqlite3_column_text(stmt, 0) else {
                        throw DatabaseError.sql(
                            "reconcileRoot: NULL relative_path for root \(rootID)")
                    }
                    indexed.append(String(cString: c))
                    continue
                }
                guard rc == SQLITE_DONE else {
                    throw Self.sqliteFailure(handle, resultCode: rc)
                }
                break
            }

            let existing = indexed.filter { !seenRelativePaths.contains($0) }
            guard !existing.isEmpty else { return [] }

            var invalidated = Set<String>()
            for path in existing {
                let oldDigest: String
                do {
                    let digestStmt = try prepare("""
                    SELECT content_sha256 FROM file_contents
                    WHERE root_id=? AND relative_path=?;
                    """)
                    defer { sqlite3_finalize(digestStmt) }
                    try bind(digestStmt, 1, rootID)
                    try bind(digestStmt, 2, path)
                    let rc = sqlite3_step(digestStmt)
                    if rc == SQLITE_ROW {
                        guard let c = sqlite3_column_text(digestStmt, 0) else {
                            throw DatabaseError.sql(
                                "reconcileRoot: NULL content digest for \(rootID)/\(path)")
                        }
                        oldDigest = String(cString: c)
                    } else if rc == SQLITE_DONE {
                        // An external-file-only row (binary/oversized/non-UTF8)
                        // legitimately has no carried file_contents digest.
                        oldDigest = ""
                    } else {
                        throw Self.sqliteFailure(handle, resultCode: rc)
                    }
                }

                invalidated.formUnion(try affectedClosure(
                    rootID: rootID, relativePath: path))
                try invalidateRetrievalSettlementsInTransaction(
                    rootID: rootID, relativePath: path, oldDigest: oldDigest)
                try execBinding("""
                UPDATE external_files SET status='missing'
                WHERE root_id=? AND relative_path=?;
                """) { updateStmt in
                    try bind(updateStmt, 1, rootID)
                    try bind(updateStmt, 2, path)
                }
            }
            let invalidatedIDs = invalidated.sorted()
            try markSettlementsInvalidInTransaction(
                invalidatedIDs, cause: "reconcile-missing:\(rootID)")
            return invalidatedIDs
        }
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
        while try stepRowOrDone(stmt) {
            guard let c = sqlite3_column_text(stmt, 0) else {
                throw DatabaseError.sql("transitiveDependents: NULL identifier")
            }
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
        // The dependency closure and validity updates are one serialized unit,
        // matching reconcileRoot and preventing a new dependent edge from racing
        // between the closure read and BEGIN IMMEDIATE.
        return try transactionResult {
            let ids = try transitiveDependents(seeds: [settlementID])
            try markSettlementsInvalidInTransaction(
                ids, cause: "upstream:\(settlementID)")
            return ids
        }
    }

    /// Data-ownership introspection: does the given table store any BLOB column?
    /// The external-file index must hold only digest + metadata — NEVER the file
    /// bytes — so this must be false for `external_files`.
    public func tableHasBlobColumn(_ table: String) throws -> Bool {
        let stmt = try prepare("SELECT type FROM pragma_table_info(?);")
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, table)
        while try stepRowOrDone(stmt) {
            guard let c = sqlite3_column_text(stmt, 0) else {
                throw DatabaseError.sql("tableHasBlobColumn: NULL column type")
            }
            if String(cString: c).uppercased().contains("BLOB") { return true }
        }
        return false
    }

    /// Current validity of a settlement ('valid' or 'invalid'), derived from the
    /// append-only validity ledger. The settlement row carries no mutable
    /// validity state of its own.
    /// Current validity when the settlement exists. A missing row is nil;
    /// prepare/bind/step failures remain typed SQLite errors.
    func settlementValidityIfPresent(_ settlementID: String) throws -> String? {
        let stmt = try prepare("""
        SELECT validity FROM settlement_current_validity WHERE settlement_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, settlementID)
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_DONE { return nil }
        guard rc == SQLITE_ROW else {
            throw Self.sqliteFailure(handle, resultCode: rc)
        }
        guard let c = sqlite3_column_text(stmt, 0) else {
            throw DatabaseError.sql("settlementValidity: NULL validity for \(settlementID)")
        }
        return String(cString: c)
    }

    public func settlementValidity(_ settlementID: String) throws -> String {
        guard let validity = try settlementValidityIfPresent(settlementID) else {
            throw DatabaseError.sql("settlementValidity: unknown settlement \(settlementID)")
        }
        return validity
    }

    /// Number of MODEL-PRODUCED settlements currently valid. Derived
    /// consumption rows are valid and chainable, but counting them as model
    /// output would overstate how much work the engine actually did.
    public func validSettlementCount() throws -> Int {
        let stmt = try prepare("""
        SELECT COUNT(*) FROM settlements s
        JOIN settlement_current_validity v ON v.settlement_id=s.settlement_id
        WHERE v.validity='valid'
          AND ifnull(s.validation_status,'')<>'DERIVED_CONSUMPTION';
        """)
        defer { sqlite3_finalize(stmt) }
        if try stepRowOrDone(stmt) { return Int(sqlite3_column_int64(stmt, 0)) }
        return 0
    }

    /// The minimal row admission-by-id needs: sealed payload, recorded digest,
    /// validity and producer/derivation status. Targeted so an admission inside
    /// a consumption transaction does not read every settlement payload.
    public struct SettlementAdmissionRow: Equatable, Sendable {
        public let settlementID: String
        public let stateID: String?
        public let payload: Data
        public let recordedPayloadDigest: String
        public let validationStatus: String?
        public let validity: String
    }

    public func settlementAdmissionRow(
        settlementID: String
    ) throws -> SettlementAdmissionRow? {
        let stmt = try prepare("""
        SELECT s.state_id, s.payload, s.payload_digest, s.validation_status,
               v.validity, s.payload_object_id
        FROM settlements s
        JOIN settlement_current_validity v ON v.settlement_id=s.settlement_id
        WHERE s.settlement_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, settlementID)
        guard try stepRowOrDone(stmt) else { return nil }
        func text(_ i: Int32) -> String? {
            sqlite3_column_text(stmt, i).map { String(cString: $0) }
        }
        let objectID = text(5) ?? ""
        let payload: Data
        if !objectID.isEmpty {
            payload = try readObject(objectID)
        } else {
            let bytes = Int(sqlite3_column_bytes(stmt, 1))
            if let base = sqlite3_column_blob(stmt, 1), bytes > 0 {
                payload = Data(bytes: base, count: bytes)
            } else {
                payload = Data()
            }
        }
        return SettlementAdmissionRow(
            settlementID: settlementID,
            stateID: text(0),
            payload: payload,
            recordedPayloadDigest: text(2) ?? "",
            validationStatus: text(3),
            validity: text(4) ?? "valid")
    }

    /// A settlement read back from Information Space: the verified payload
    /// object, its producer/constraint bindings, and every dependency revision
    /// recorded for it. This is what an execution period consumes when it
    /// re-uses a settled result.
    public struct SettlementReceiptRecord: Equatable, Sendable {
        public let settlementID: String
        public let stateID: String?
        public let payloadObjectID: String?
        public let payloadSHA256: String
        public let payload: Data
        public let schemaVersion: String?
        public let contractVersion: String?
        public let settledAt: String?
        public let validationStatus: String?
        public let validity: String
        public let invalidatedAt: String?
        public let bindings: [String: String]
        public let dependencies: [DependencyEntry]
        /// Distilled, reusable projection of this settlement, when one exists.
        public let summary: SettlementSummaryRecord?
    }

    public func settlementReceipt(_ settlementID: String) throws -> SettlementReceiptRecord? {
        var stateID: String?
        var payloadLegacy = Data()
        var payloadObjectID: String?
        var schemaVersion: String?
        var contractVersion: String?
        var settledAt: String?
        var validationStatus: String?
        var validity = "valid"
        var invalidatedAt: String?
        var found = false

        let stmt = try prepare("""
        SELECT s.state_id, s.payload, s.schema_version, s.contract_version,
               s.settled_at, s.validation_status, v.validity, v.invalidated_at,
               s.payload_object_id
        FROM settlements s
        JOIN settlement_current_validity v ON v.settlement_id=s.settlement_id
        WHERE s.settlement_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, settlementID)
        if try stepRowOrDone(stmt) {
            found = true
            func text(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            stateID = text(0)
            let bytes = Int(sqlite3_column_bytes(stmt, 1))
            if let base = sqlite3_column_blob(stmt, 1), bytes > 0 {
                payloadLegacy = Data(bytes: base, count: bytes)
            }
            schemaVersion = text(2)
            contractVersion = text(3)
            settledAt = text(4)
            validationStatus = text(5)
            validity = text(6) ?? "valid"
            invalidatedAt = text(7)
            payloadObjectID = text(8)
        }
        try reset(stmt)
        guard found else { return nil }

        let payload: Data
        if let payloadObjectID, !payloadObjectID.isEmpty {
            // Throws on a corrupt object: a receipt must not be handed out with
            // bytes that no longer match their address.
            payload = try readObject(payloadObjectID)
        } else {
            payload = payloadLegacy
        }

        return SettlementReceiptRecord(
            settlementID: settlementID,
            stateID: stateID,
            payloadObjectID: payloadObjectID,
            payloadSHA256: NativeSHA256.hexDigest(payload),
            payload: payload,
            schemaVersion: schemaVersion,
            contractVersion: contractVersion,
            settledAt: settledAt,
            validationStatus: validationStatus,
            validity: validity,
            invalidatedAt: invalidatedAt,
            bindings: try settlementBindings(settlementID: settlementID),
            dependencies: try settlementDependencies(settlementID: settlementID),
            summary: try settlementSummary(settlementID: settlementID))
    }

    // MARK: - Settlement summaries (post-settlement distillation)

    /// One distilled settlement. `summarySHA256` is the digest of `summary`
    /// itself, and `summaryObjectID` carries the sealed `Summary` JSON. Reads
    /// re-verify object bytes against that address, so a summary is only ever
    /// handed out with the bytes it was sealed with.
    public struct SettlementSummaryRecord: Equatable, Sendable {
        public let settlementID: String
        public let sessionID: String?
        /// Only the head of the question (see
        /// `SettlementSummaryPolicy.queryExcerptCharacters`); the full text is
        /// in the summary object and is restored by `verified(_:)`.
        public let query: String
        /// True when `query` is an excerpt. A non-excerpt row must match the
        /// object byte for byte; an excerpt must be a prefix of it.
        public let queryTruncated: Bool
        public let summary: String
        public let summarySHA256: String
        public let summaryObjectID: String
        public let sourcePayloadDigest: String
        public let createdAt: String
        /// `DERIVED_CONSUMPTION` when the summary describes a consumed value
        /// rather than model output; nil for a model-produced settlement.
        public let derivationType: String?
        /// The settlement this derived summary ultimately came from.
        public let sourceSettlementID: String?
    }

    /// Distill the settlement's own sealed payload and record the result. The
    /// caller passes only the settlement identity plus the query it answered;
    /// text always comes from the stored payload, never from a second copy.
    /// Returns nil when the settlement is unknown or has nothing to distill.
    @discardableResult
    public func recordSettlementSummary(
        settlementID: String,
        sessionID: String?,
        query: String,
        settledAt: Date = Date()
    ) throws -> SettlementSummaryRecord? {
        var record: SettlementSummaryRecord?
        try transaction {
            record = try recordSettlementSummaryInTransaction(
                settlementID: settlementID, sessionID: sessionID,
                query: query, settledAt: settledAt)
        }
        return record
    }

    /// Caller owns the transaction.
    private func recordSettlementSummaryInTransaction(
        settlementID: String,
        sessionID: String?,
        query: String,
        settledAt: Date
    ) throws -> SettlementSummaryRecord? {
        var payloadDigest = ""
        var payload = Data()
        var validationStatus: String?
        let stmt = try prepare("""
        SELECT payload_digest, payload, payload_object_id, validation_status
        FROM settlements WHERE settlement_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, settlementID)
        guard try stepRowOrDone(stmt) else { return nil }
        if let c = sqlite3_column_text(stmt, 0) { payloadDigest = String(cString: c) }
        if let object = sqlite3_column_text(stmt, 2).map({ String(cString: $0) }),
            !object.isEmpty {
            payload = try readObject(object)
        } else {
            let bytes = Int(sqlite3_column_bytes(stmt, 1))
            if let base = sqlite3_column_blob(stmt, 1), bytes > 0 {
                payload = Data(bytes: base, count: bytes)
            }
        }
        validationStatus = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
        guard !payloadDigest.isEmpty else { return nil }

        let text = SettlementSummaryPolicy.distill(
            SettlementSummaryPolicy.text(fromPayload: payload))
        guard !text.isEmpty else { return nil }

        let derived = validationStatus == "DERIVED_CONSUMPTION"
        let provenance = derived ? try consumptionSource(
            consumerSettlementID: settlementID) : nil
        let sealed = SettlementSummaryPolicy.Summary(
            settlementID: settlementID, sessionID: sessionID,
            query: query, text: text, sourcePayloadDigest: payloadDigest,
            derivationType: derived ? "DERIVED_CONSUMPTION" : nil,
            sourceSettlementID: provenance)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(sealed)
        let objectID = try ensureObject(bytes)
        let summarySHA = NativeSHA256.hexDigest(Data(text.utf8))
        let stamp = Self.stamp(settledAt)
        let storedQuery = SettlementSummaryPolicy.queryExcerpt(query)
        let queryTruncated = storedQuery != query

        try execBinding("""
        INSERT INTO settlement_summaries(
            settlement_id, session_id, query, query_truncated, summary, summary_sha256,
            summary_object_id, source_payload_digest, created_at,
            derivation_type, provenance_settlement_id)
        VALUES(?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(settlement_id) DO UPDATE SET
            session_id=excluded.session_id, query=excluded.query,
            query_truncated=excluded.query_truncated,
            summary=excluded.summary, summary_sha256=excluded.summary_sha256,
            summary_object_id=excluded.summary_object_id,
            source_payload_digest=excluded.source_payload_digest,
            created_at=excluded.created_at,
            derivation_type=excluded.derivation_type,
            provenance_settlement_id=excluded.provenance_settlement_id;
        """) { stmt in
            try bind(stmt, 1, settlementID)
            try bind(stmt, 2, sessionID)
            try bind(stmt, 3, storedQuery)
            try bind(stmt, 4, queryTruncated ? 1 : 0)
            try bind(stmt, 5, text)
            try bind(stmt, 6, summarySHA)
            try bind(stmt, 7, objectID)
            try bind(stmt, 8, payloadDigest)
            try bind(stmt, 9, stamp)
            try bind(stmt, 10, derived ? "DERIVED_CONSUMPTION" : nil)
            try bind(stmt, 11, provenance)
        }
        _ = try appendIndexEntryInTransaction(
            identity: "settlement-summary:\(settlementID)", objectID: objectID)

        return SettlementSummaryRecord(
            settlementID: settlementID, sessionID: sessionID, query: query,
            queryTruncated: queryTruncated, summary: text, summarySHA256: summarySHA,
            summaryObjectID: objectID, sourcePayloadDigest: payloadDigest,
            createdAt: stamp,
            derivationType: derived ? "DERIVED_CONSUMPTION" : nil,
            sourceSettlementID: provenance)
    }

    /// Read one summary back with its object bytes verified against the address.
    public func settlementSummary(settlementID: String) throws -> SettlementSummaryRecord? {
        let stmt = try prepare("""
        SELECT settlement_id, session_id, query, query_truncated, summary, summary_sha256,
               summary_object_id, source_payload_digest, created_at,
               derivation_type, provenance_settlement_id
        FROM settlement_summaries WHERE settlement_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, settlementID)
        guard try stepRowOrDone(stmt) else { return nil }
        func text(_ i: Int32) -> String {
            sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
        }
        let record = SettlementSummaryRecord(
            settlementID: text(0),
            sessionID: sqlite3_column_text(stmt, 1).map { String(cString: $0) },
            query: text(2), queryTruncated: sqlite3_column_int(stmt, 3) != 0,
            summary: text(4), summarySHA256: text(5),
            summaryObjectID: text(6), sourcePayloadDigest: text(7),
            createdAt: text(8),
            derivationType: sqlite3_column_text(stmt, 9).map { String(cString: $0) },
            sourceSettlementID: sqlite3_column_text(stmt, 10).map { String(cString: $0) })
        return try verified(record)
    }

    /// Summaries a later demand may cite: still valid, never a retrieval result
    /// or a migrated legacy row, and not the demand's own conversation. A
    /// `DERIVED_CONSUMPTION` summary IS citable, but it carries its derivation
    /// type and source settlement so a consumer cannot present it as independent
    /// generation evidence. Newest first.
    /// Every valid, model-produced settlement summary in scope. There is no
    /// per-question dedup: two mutually exclusive answers to the same question
    /// are returned side by side, each under its own `settlement:<id>`. Picking
    /// one would be a truth judgement, which the IS does not make.
    public func citableSettlementSummaries(
        sessionID: String?, limit: Int = 200
    ) throws -> [SettlementSummaryRecord] {
        let stmt = try prepare("""
        SELECT m.settlement_id, m.session_id, m.query, m.query_truncated,
               m.summary, m.summary_sha256,
               m.summary_object_id, m.source_payload_digest, m.created_at,
               m.derivation_type, m.provenance_settlement_id
        FROM settlement_summaries m
        JOIN settlements s ON s.settlement_id=m.settlement_id
        JOIN settlement_current_validity v ON v.settlement_id=s.settlement_id
        WHERE v.validity='valid' AND v.invalidated_at IS NULL
          AND ifnull(s.validation_status,'') NOT IN ('IS_RETRIEVAL','MIGRATED_LEGACY')
          AND (m.session_id IS NULL OR m.session_id<>?)
        ORDER BY m.created_at DESC, m.settlement_id
        LIMIT ?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID ?? "")
        try bind(stmt, 2, Int64(max(1, min(limit, 2000))))
        var out: [SettlementSummaryRecord] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String {
                sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
            }
            let record = SettlementSummaryRecord(
                settlementID: text(0),
                sessionID: sqlite3_column_text(stmt, 1).map { String(cString: $0) },
                query: text(2), queryTruncated: sqlite3_column_int(stmt, 3) != 0,
                summary: text(4), summarySHA256: text(5),
                summaryObjectID: text(6), sourcePayloadDigest: text(7),
                createdAt: text(8),
                derivationType: sqlite3_column_text(stmt, 9).map { String(cString: $0) },
                sourceSettlementID: sqlite3_column_text(stmt, 10).map { String(cString: $0) })
            if let verified = try? verified(record) { out.append(verified) }
        }
        return out
    }

    /// A summary is usable only when its text still hashes to the recorded
    /// digest, its object decodes, and it names the settlement it is filed
    /// under. Any drift disqualifies it instead of being cited.
    private func verified(
        _ record: SettlementSummaryRecord
    ) throws -> SettlementSummaryRecord? {
        guard NativeSHA256.hexDigest(Data(record.summary.utf8)) == record.summarySHA256
        else { return nil }
        let data = try readObject(record.summaryObjectID)
        guard let sealed = try? JSONDecoder().decode(
            SettlementSummaryPolicy.Summary.self, from: data)
        else { return nil }
        // The column holds either the whole question or its head. Both are
        // checked against the object, so a rewritten or swapped excerpt is
        // refused instead of being cited as the question that was asked.
        let queryIntact = record.queryTruncated
            ? sealed.query.hasPrefix(record.query)
            : sealed.query == record.query
        guard queryIntact,
            sealed.settlementID == record.settlementID,
            sealed.text == record.summary,
            sealed.sourcePayloadDigest == record.sourcePayloadDigest,
            sealed.derivationType == record.derivationType,
            sealed.sourceSettlementID == record.sourceSettlementID
        else { return nil }
        // Callers get the question in full; only the stored row is shortened.
        guard record.queryTruncated else { return record }
        return SettlementSummaryRecord(
            settlementID: record.settlementID, sessionID: record.sessionID,
            query: sealed.query, queryTruncated: true, summary: record.summary,
            summarySHA256: record.summarySHA256,
            summaryObjectID: record.summaryObjectID,
            sourcePayloadDigest: record.sourcePayloadDigest,
            createdAt: record.createdAt, derivationType: record.derivationType,
            sourceSettlementID: record.sourceSettlementID)
    }

    /// The settlement a derived consumption record consumed. Used to stamp the
    /// summary's provenance chain in the SAME transaction as the consumption.
    private func consumptionSource(consumerSettlementID: String) throws -> String? {
        let stmt = try prepare("""
        SELECT source_settlement_id FROM settlement_consumptions
        WHERE consumer_settlement_id=? ORDER BY created_at LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, consumerSettlementID)
        guard try stepRowOrDone(stmt), let c = sqlite3_column_text(stmt, 0)
        else { return nil }
        return String(cString: c)
    }

    /// Summarize model-produced settlements that predate v10 (or that were
    /// written by a path which had no query to record). Idempotent.
    @discardableResult
    public func backfillSettlementSummaries() throws -> Int {
        var count = 0
        try transaction {
            count = try backfillSettlementSummariesInTransaction()
        }
        return count
    }

    /// Caller owns the transaction.
    private func backfillSettlementSummariesInTransaction() throws -> Int {
        let stmt = try prepare("""
        SELECT s.settlement_id, s.settled_at, s.validation_status
        FROM settlements s
        LEFT JOIN settlement_summaries m ON m.settlement_id=s.settlement_id
        WHERE m.settlement_id IS NULL
          AND ifnull(s.validation_status,'') NOT IN ('IS_RETRIEVAL','MIGRATED_LEGACY')
        ORDER BY s.settled_at, s.settlement_id;
        """)
        defer { sqlite3_finalize(stmt) }
        var pending: [(id: String, settledAt: String, status: String?)] = []
        while try stepRowOrDone(stmt) {
            let id = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let settledAt = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let status = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            if !id.isEmpty { pending.append((id, settledAt, status)) }
        }
        try reset(stmt)

        var written = 0
        for row in pending {
            var query = ""
            var sessionID: String?
            let ctx = try prepare("""
            SELECT d.query, d.session_id
            FROM information_advancements a
            JOIN information_demands d ON d.demand_id=a.demand_id
            WHERE a.settlement_id=?
            ORDER BY a.advanced_at DESC LIMIT 1;
            """)
            defer { sqlite3_finalize(ctx) }
            try bind(ctx, 1, row.id)
            if try stepRowOrDone(ctx) {
                query = sqlite3_column_text(ctx, 0).map { String(cString: $0) } ?? ""
                sessionID = sqlite3_column_text(ctx, 1).map { String(cString: $0) }
            }
            try reset(ctx)
            if let record = try recordSettlementSummaryInTransaction(
                settlementID: row.id, sessionID: sessionID, query: query,
                settledAt: parseISO8601(row.settledAt) ?? Date()),
                record.summary.isEmpty == false {
                written += 1
            }
        }
        return written
    }

    /// Every dependency revision whose identity starts with
    /// `settlement:<id> -> ` (sources and downstream results), oldest first.
    public func settlementDependencies(settlementID: String) throws -> [DependencyEntry] {
        let prefix = "settlement:\(settlementID) -> "
        let stmt = try prepare("""
        SELECT append_order, dependency_id, content_address, revision, reason, recorded_at
        FROM is_dependency_entries
        WHERE substr(dependency_id, 1, ?) = ?
        ORDER BY append_order ASC;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, Int64(prefix.utf8.count))
        try bind(stmt, 2, prefix)
        var out: [DependencyEntry] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String {
                sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
            }
            out.append(DependencyEntry(
                appendOrder: Int(sqlite3_column_int64(stmt, 0)),
                dependencyID: text(1),
                contentAddress: text(2),
                revision: Int(sqlite3_column_int64(stmt, 3)),
                reason: text(4),
                recordedAt: text(5)))
        }
        return out
    }

    /// A settled file's carried bytes, read back and verified through its
    /// object. Legacy rows without an object fall back to their inline text.
    public struct CarriedFileContent: Equatable, Sendable {
        public let rootID: String
        public let relativePath: String
        public let contentSHA256: String
        public let objectID: String?
        public let settledAt: String
        public let content: Data
        public let status: String?
    }

    public func carriedFileContent(
        rootID: String, relativePath: String
    ) throws -> CarriedFileContent? {
        var digest = ""
        var objectID: String?
        var settledAt = ""
        var legacy = Data()
        var status: String?
        var indexedSize: Int64?
        var found = false

        let stmt = try prepare("""
        SELECT f.content_sha256, f.object_id, f.settled_at, f.content, e.status, e.size
        FROM file_contents f
        LEFT JOIN external_files e
          ON e.root_id=f.root_id AND e.relative_path=f.relative_path
        WHERE f.root_id=? AND f.relative_path=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, rootID)
        try bind(stmt, 2, relativePath)
        if try stepRowOrDone(stmt) {
            found = true
            func text(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            digest = text(0) ?? ""
            objectID = text(1)
            settledAt = text(2) ?? ""
            let bytes = Int(sqlite3_column_bytes(stmt, 3))
            if let base = sqlite3_column_blob(stmt, 3), bytes > 0 {
                legacy = Data(bytes: base, count: bytes)
            }
            status = text(4)
            indexedSize = sqlite3_column_type(stmt, 5) == SQLITE_NULL
                ? nil : sqlite3_column_int64(stmt, 5)
        }
        try reset(stmt)
        guard found else { return nil }

        func matchesIndexedDigest(_ data: Data) -> Bool {
            if NativeSHA256.hexDigest(data) == digest { return true }
            guard let indexedSize, indexedSize >= 0 else { return false }
            return NativeSHA256.hexDigest(
                Data("tail:\(indexedSize):".utf8) + data) == digest
        }

        let content: Data
        if let objectID, !objectID.isEmpty {
            content = try readObject(objectID)
            guard matchesIndexedDigest(content) else {
                throw DatabaseError.sql(
                    "carriedFileContent: stored object digest mismatch for \(rootID)/\(relativePath)")
            }
        } else if !legacy.isEmpty {
            content = legacy
            guard matchesIndexedDigest(content) else {
                throw DatabaseError.sql(
                    "carriedFileContent: legacy content digest mismatch for \(rootID)/\(relativePath)")
            }
        } else {
            // Index-only rows carry a metadata object describing whether the
            // digest covers the whole file or a bounded tail window. Never read
            // an arbitrarily large source merely to answer this content query.
            guard let locator = try rootLocatorPath(rootID),
                !relativePath.isEmpty,
                !relativePath.split(separator: "/").contains("..")
            else { return nil }
            let rootDirectoryFD: Int32
            do {
                rootDirectoryFD = try openDirectoryNoFollow(atPath: locator)
            } catch let error as DatabaseError {
                if case .sourceGone = error { return nil }
                throw error
            }
            defer { Darwin.close(rootDirectoryFD) }

            let identity = "file:\(rootID)/\(relativePath)"
            guard let metadataObjectID = try latestIndexObjectID(identity: identity),
                  !metadataObjectID.isEmpty else {
                throw DatabaseError.sql(
                    "carriedFileContent: missing index-only metadata for \(rootID)/\(relativePath)")
            }
            let metadataData = try readObject(metadataObjectID)
            guard let metadata = try JSONSerialization.jsonObject(with: metadataData)
                    as? [String: Any],
                  let metadataLocator = metadata["locator"] as? String,
                  let metadataDigest = metadata["sha256"] as? String,
                  let metadataSize = metadata["size"] as? Int64,
                  metadataSize >= 0 else {
                throw DatabaseError.sql(
                    "carriedFileContent: malformed index-only metadata for \(rootID)/\(relativePath)")
            }
            guard metadataLocator == identity, metadataDigest == digest,
                  indexedSize == nil || indexedSize == metadataSize else {
                throw DatabaseError.staleExternalSource(
                    rootID: rootID, relativePath: relativePath)
            }

            func readSource(
                maximumBytes: Int?, tailBytes: Int? = nil,
                maximumTotalBytesRead: Int
            ) throws -> NoFollowFileRead? {
                do {
                    return try readRootFileNoFollow(
                        rootDirectoryFD: rootDirectoryFD,
                        relativePath: relativePath,
                        maximumBytes: maximumBytes,
                        tailBytes: tailBytes,
                        maximumTotalBytesRead: maximumTotalBytesRead)
                } catch let error as DatabaseError {
                    if case .sourceGone = error { return nil }
                    throw error
                }
            }

            if metadata["is_tail"] as? Bool == true {
                let maximumTailReadBytes = 64 * 1024 * 1024
                guard let tailWindowBytes = metadata["tail_bytes"] as? Int,
                      tailWindowBytes > 0, tailWindowBytes <= maximumTailReadBytes,
                      metadataSize > 0, metadataSize <= Int64(Int.max) else {
                    throw DatabaseError.staleExternalSource(
                        rootID: rootID, relativePath: relativePath)
                }
                guard let read = try readSource(
                    maximumBytes: tailWindowBytes - 1,
                    tailBytes: tailWindowBytes,
                    maximumTotalBytesRead: tailWindowBytes) else { return nil }
                guard read.isTail, read.size == metadataSize, let rawTail = read.data else {
                    throw DatabaseError.staleExternalSource(
                        rootID: rootID, relativePath: relativePath)
                }
                let indexedData = Self.indexedTailData(rawTail)
                let tailDigest = NativeSHA256.hexDigest(
                    Data("tail:\(metadataSize):".utf8) + indexedData)
                guard tailDigest == digest else {
                    throw DatabaseError.staleExternalSource(
                        rootID: rootID, relativePath: relativePath)
                }
                content = indexedData
            } else {
                let maximumFullReadBytes = 64 * 1024 * 1024
                guard metadataSize <= Int64(maximumFullReadBytes) else {
                    throw DatabaseError.staleExternalSource(
                        rootID: rootID, relativePath: relativePath)
                }
                guard let read = try readSource(
                    maximumBytes: Int(metadataSize),
                    maximumTotalBytesRead: maximumFullReadBytes) else { return nil }
                guard !read.isTail, read.size == metadataSize, let data = read.data,
                      NativeSHA256.hexDigest(data) == digest else {
                    throw DatabaseError.staleExternalSource(
                        rootID: rootID, relativePath: relativePath)
                }
                content = data
            }
        }
        return CarriedFileContent(
            rootID: rootID, relativePath: relativePath,
            contentSHA256: digest, objectID: objectID,
            settledAt: settledAt, content: content, status: status)
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
        try bind(stmt, 1, settlementID)
        var out: [String] = []
        while try stepRowOrDone(stmt) {
            guard let c = sqlite3_column_text(stmt, 0) else {
                throw DatabaseError.sql("upstreamDependencyClosure: NULL identifier")
            }
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
                    try bind(stmt, 1, s.id)
                    try bind(stmt, 2, s.parentID)
                    try bind(stmt, 3, s.modelIdentity)
                    try bind(stmt, 4, Int64(s.position))
                    try bind(stmt, 5, s.continuationID)
                    try bind(stmt, 6, s.anchor)
                    try bind(stmt, 7, s.lifecycle)
                    try bind(stmt, 8, Self.stamp( s.createdAt))
                    try bind(stmt, 9, s.nextInput)
                    try bind(stmt, 10, jsonText(s.prefix))
                    try bind(stmt, 11, jsonText(s.checkpointIDs.map { $0.uuidString }))
                }
            }
            for c in doc.checkpoints {
                let canonical = (try? enc.encode(c.prefix)) ?? Data()
                let payloadObject = try ensureObject(canonical)
                try execBinding("""
                INSERT INTO settlements(settlement_id, state_id, schema_version, payload, payload_digest, signature, contract_version, settled_at, validation_status, payload_object_id)
                VALUES(?,?,?,?,?,?,?,?,?,?);
                """) { stmt in
                    try bind(stmt, 1, c.id.uuidString)
                    try bind(stmt, 2, c.stateID)
                    try bind(stmt, 3, doc.representationID)
                    try bind(stmt, 4, Data())
                    try bind(stmt, 5, c.checksum)
                    try bind(stmt, 6, String?.none)
                    try bind(stmt, 7, doc.contractVersion)
                    try bind(stmt, 8, Self.stamp( c.createdAt))
                    try bind(stmt, 9, "MIGRATED_LEGACY")
                    try bind(stmt, 10, payloadObject)
                }
                try recordSettlementValidityEventInTransaction(
                    settlementID: c.id.uuidString, validity: "valid", cause: nil,
                    at: Self.stamp(c.createdAt))
                _ = try appendIndexEntryInTransaction(
                    identity: "settlement:\(c.id.uuidString)", objectID: payloadObject)
                // Also land the checkpoint in the ES-owned checkpoints table so a
                // post-retirement readGraph() reproduces the graph, not only the
                // settlement receipts.
                try execBinding("""
                INSERT INTO checkpoints(checkpoint_id, state_id, model_identity, position, continuation_id, next_input, anchor, prefix_json, created_at, checksum)
                VALUES(?,?,?,?,?,?,?,?,?,?);
                """) { stmt in
                    try bind(stmt, 1, c.id.uuidString)
                    try bind(stmt, 2, c.stateID)
                    try bind(stmt, 3, c.modelIdentity)
                    try bind(stmt, 4, Int64(c.position))
                    try bind(stmt, 5, c.continuationID)
                    try bind(stmt, 6, c.nextInput)
                    try bind(stmt, 7, c.anchor)
                    try bind(stmt, 8, jsonText(c.prefix))
                    try bind(stmt, 9, Self.stamp( c.createdAt))
                    try bind(stmt, 10, c.checksum)
                }
            }

            // Read-back verification, field by field.
            try verifyReadBack(doc: doc)

            try execBinding("INSERT INTO migration_receipts(source_kind, source_digest, result, rows_imported, completed_at) VALUES(?,?,?,?,?);") { stmt in
                try bind(stmt, 1, "legacy_execution_graph")
                try bind(stmt, 2, sourceLabel)
                try bind(stmt, 3, "ok")
                try bind(stmt, 4, Int64(doc.states.count + doc.checkpoints.count))
                try bind(stmt, 5, Self.stamp( Date()))
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
            try bind(stmt, 1, s.id)
            guard try stepRowOrDone(stmt) else {
                throw DatabaseError.migrationMismatch("state not read back: \(s.id)")
            }
            let pos = Int(sqlite3_column_int64(stmt, 0))
            let cont = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let anchor = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let nextInput = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
            let prefixText = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? "[]"
            let cpText = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? "[]"
            let prefixRead = try dec.decode([String].self, from: Data(prefixText.utf8))
            let cpStrings = try dec.decode([String].self, from: Data(cpText.utf8))
            let cpRead = try cpStrings.map { value -> UUID in
                guard let id = UUID(uuidString: value) else {
                    throw DatabaseError.migrationMismatch(
                        "invalid checkpoint UUID in state \(s.id): \(value)")
                }
                return id
            }
            guard pos == s.position, cont == s.continuationID, anchor == s.anchor,
                  nextInput == s.nextInput, prefixRead == s.prefix,
                  cpRead == s.checkpointIDs else {
                throw DatabaseError.migrationMismatch("state field drift: \(s.id)")
            }
        }
        // Checkpoints must also be present in the ES-owned table for a loss-free
        // post-retirement graph read, not only as settlement receipts.
        for c in doc.checkpoints {
            let stmt = try prepare("SELECT checksum, state_id, prefix_json FROM checkpoints WHERE checkpoint_id=?;")
            defer { sqlite3_finalize(stmt) }
            try bind(stmt, 1, c.id.uuidString)
            guard try stepRowOrDone(stmt) else {
                throw DatabaseError.migrationMismatch("checkpoint not read back: \(c.id)")
            }
            let sum = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let state = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let prefixText = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "[]"
            let prefixRead = try dec.decode([String].self, from: Data(prefixText.utf8))
            guard sum == c.checksum, state == c.stateID, prefixRead == c.prefix else {
                throw DatabaseError.migrationMismatch("checkpoint field drift: \(c.id)")
            }
        }
        for c in doc.checkpoints {
            let stmt = try prepare("SELECT payload_digest, state_id FROM settlements WHERE settlement_id=?;")
            defer { sqlite3_finalize(stmt) }
            try bind(stmt, 1, c.id.uuidString)
            guard try stepRowOrDone(stmt) else {
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
                INSERT INTO execution_states(state_id, parent_id, model_identity, position, continuation_id, anchor, lifecycle, created_at, next_input, prefix_json, checkpoint_ids_json, graph_managed)
                VALUES(?,?,?,?,?,?,?,?,?,?,?,1)
                ON CONFLICT(state_id) DO UPDATE SET
                    parent_id=excluded.parent_id, model_identity=excluded.model_identity, position=excluded.position,
                    continuation_id=excluded.continuation_id, anchor=excluded.anchor, lifecycle=excluded.lifecycle,
                    created_at=excluded.created_at, next_input=excluded.next_input,
                    prefix_json=excluded.prefix_json, checkpoint_ids_json=excluded.checkpoint_ids_json,
                    graph_managed=1;
                """) { stmt in
                    try bind(stmt, 1, st.id)
                    try bind(stmt, 2, st.parentID)
                    try bind(stmt, 3, st.modelIdentity)
                    try bind(stmt, 4, Int64(st.position))
                    try bind(stmt, 5, st.continuationID)
                    try bind(stmt, 6, st.anchor)
                    try bind(stmt, 7, st.lifecycle)
                    try bind(stmt, 8, Self.stamp( st.createdAt))
                    try bind(stmt, 9, st.nextInput)
                    try bind(stmt, 10, prefixJSON ?? "[]")
                    try bind(stmt, 11, cpJSON)
                }
            }
            // Reconcile removals: delete states absent from the incoming set, but
            // only those not referenced by any settlement (protect IS authority).
            let keep = Set(states.map { $0.id })
            let existing = try fetchColumn(
                "SELECT state_id FROM execution_states WHERE graph_managed=1;")
            for sid in existing where !keep.contains(sid) {
                let ref = try isReferencedBySettlement(sid)
                if !ref {
                    try execBinding("DELETE FROM execution_states WHERE state_id=?;") { try bind($0, 1, sid) }
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
                    try bind(stmt, 1, cp.id.uuidString)
                    try bind(stmt, 2, cp.stateID)
                    try bind(stmt, 3, cp.modelIdentity)
                    try bind(stmt, 4, Int64(cp.position))
                    try bind(stmt, 5, cp.continuationID)
                    try bind(stmt, 6, cp.nextInput)
                    try bind(stmt, 7, cp.anchor)
                    try bind(stmt, 8, prefixJSON)
                    try bind(stmt, 9, Self.stamp( cp.createdAt))
                    try bind(stmt, 10, cp.checksum)
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
        while try stepRowOrDone(sstmt) {
            let stateID = txt(sstmt, 0)
            let prefixJSON = txt(sstmt, 9)
            let checkpointJSON = txt(sstmt, 10)
            // These columns are authoritative serialized state. An empty,
            // NULL, or malformed value is corruption; never reconstruct an
            // apparently complete graph by silently substituting empty arrays.
            let prefix = try dec.decode([String].self, from: Data(prefixJSON.utf8))
            let checkpointStrings = try dec.decode(
                [String].self, from: Data(checkpointJSON.utf8))
            let checkpointIDs = try checkpointStrings.map { value -> UUID in
                guard let id = UUID(uuidString: value) else {
                    throw DatabaseError.sql(
                        "readGraph: invalid checkpoint UUID '\(value)' for state \(stateID)")
                }
                return id
            }
            guard let created = parseISO8601(txt(sstmt, 3)) else {
                throw DatabaseError.sql("readGraph: invalid created_at for state \(stateID)")
            }
            states.append(GraphState(
                id: stateID, parentID: opt(sstmt, 1), modelIdentity: txt(sstmt, 2),
                createdAt: created, position: Int(sqlite3_column_int64(sstmt, 4)),
                continuationID: txt(sstmt, 5), nextInput: txt(sstmt, 8),
                anchor: txt(sstmt, 6), prefix: prefix, lifecycle: txt(sstmt, 7),
                checkpointIDs: checkpointIDs))
        }
        var cps: [GraphCheckpoint] = []
        let cstmt = try prepare("""
        SELECT checkpoint_id, state_id, model_identity, position, continuation_id,
               next_input, anchor, prefix_json, created_at, checksum
        FROM checkpoints ORDER BY created_at;
        """)
        defer { sqlite3_finalize(cstmt) }
        while try stepRowOrDone(cstmt) {
            let checkpointIDText = txt(cstmt, 0)
            guard let uuid = UUID(uuidString: checkpointIDText) else {
                throw DatabaseError.sql(
                    "readGraph: invalid checkpoint identifier '\(checkpointIDText)'")
            }
            let prefix = try dec.decode([String].self, from: Data(txt(cstmt, 7).utf8))
            guard let created = parseISO8601(txt(cstmt, 8)) else {
                throw DatabaseError.sql(
                    "readGraph: invalid created_at for checkpoint \(checkpointIDText)")
            }
            cps.append(GraphCheckpoint(
                id: uuid, stateID: txt(cstmt, 1), modelIdentity: txt(cstmt, 2),
                position: Int(sqlite3_column_int64(cstmt, 3)), continuationID: txt(cstmt, 4),
                nextInput: txt(cstmt, 5), anchor: txt(cstmt, 6), prefix: prefix,
                createdAt: created, checksum: txt(cstmt, 9)))
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
        WHERE validation_status IS NULL
           OR validation_status NOT IN ('MIGRATED_LEGACY','IS_RETRIEVAL')
        ORDER BY settled_at, settlement_id;
        """)
        defer { sqlite3_finalize(stmt) }
        func t(_ i: Int32) -> String { sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "" }
        var out: [SettlementReceiptRow] = []
        while try stepRowOrDone(stmt) {
            guard let uuid = UUID(uuidString: t(0)) else {
                throw DatabaseError.sql("readSettlementReceipts: invalid settlement UUID '\(t(0))'")
            }
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
            guard NativeSHA256.hexDigest(payload) == t(4) else {
                throw DatabaseError.sql(
                    "readSettlementReceipts: payload digest mismatch for \(uuid)")
            }
            guard let settledAt = parseISO8601(t(5)) else {
                throw DatabaseError.sql(
                    "readSettlementReceipts: invalid settled_at for \(uuid)")
            }
            out.append(SettlementReceiptRow(
                id: uuid, stateID: t(1), schemaVersion: t(2), payload: payload,
                payloadDigest: t(4), settledAt: settledAt))
        }
        return out
    }

    private func fetchColumn(_ sql: String) throws -> [String] {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var out: [String] = []
        while try stepRowOrDone(stmt) {
            if let c = sqlite3_column_text(stmt, 0) { out.append(String(cString: c)) }
        }
        return out
    }

    private func isReferencedBySettlement(_ stateID: String) throws -> Bool {
        let stmt = try prepare("SELECT 1 FROM settlements WHERE state_id=? LIMIT 1;")
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, stateID)
        return try stepRowOrDone(stmt)
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
