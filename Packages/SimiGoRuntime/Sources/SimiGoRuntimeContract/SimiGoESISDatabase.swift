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
        Self.installCarrierAuthorizer(handle)
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

    /// v11 is STAGE B: a settled unit may declare that it can be consumed
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
        if try schemaVersion() < 9 {
            try transaction {
                try Self.rawExec(handle, SimiGoESISDatabase.v9)
                for column in SimiGoESISDatabase.v9Columns
                where try !columnExists(column.table, column.column) {
                    try Self.rawExec(handle, column.sql)
                }
                try recordMigrationRow(9, "simigo-es-is-loop-v9")
            }
        }
        if try schemaVersion() < 10 {
            try transaction {
                try Self.rawExec(handle, SimiGoESISDatabase.v10)
                _ = try backfillSettlementSummariesInTransaction()
                try recordMigrationRow(10, "simigo-settlement-summaries-v10")
            }
        }
        if try schemaVersion() < 11 {
            try transaction {
                try Self.rawExec(handle, SimiGoESISDatabase.v11)
                for column in SimiGoESISDatabase.v11SummaryColumns
                where try !columnExists(column.table, column.column) {
                    try Self.rawExec(handle, column.sql)
                }
                try recordMigrationRow(11, "simigo-settlement-consumption-v11")
            }
        }
        if try schemaVersion() < 12 {
            try transaction {
                for column in SimiGoESISDatabase.v12Columns
                where try !columnExists(column.table, column.column) {
                    try Self.rawExec(handle, column.sql)
                }
                try Self.rawExec(handle, SimiGoESISDatabase.v12Indexes)
                try recordMigrationRow(12, "simigo-snapshot-reference-v12")
            }
        }
        if try schemaVersion() < 13 {
            try transaction {
                for column in SimiGoESISDatabase.v13Columns
                where try !columnExists(column.table, column.column) {
                    try Self.rawExec(handle, column.sql)
                }
                try Self.rawExec(handle, SimiGoESISDatabase.v13Indexes)
                try recordMigrationRow(13, "simigo-managed-idempotency-v13")
            }
        }
        if try schemaVersion() < 14 {
            try transaction {
                try Self.rawExec(handle, SimiGoESISDatabase.v14)
                try recordMigrationRow(14, "simigo-information-reuse-v14")
            }
        }
        if try schemaVersion() < 15 {
            try transaction {
                for column in SimiGoESISDatabase.v15Columns
                where try !columnExists(column.table, column.column) {
                    try Self.rawExec(handle, column.sql)
                }
                try Self.rawExec(handle, SimiGoESISDatabase.v15Indexes)
                try recordMigrationRow(15, "simigo-chat-turn-eligibility-v15")
            }
        }
        if try schemaVersion() < 16 {
            try transaction {
                for column in SimiGoESISDatabase.v16Columns
                where try !columnExists(column.table, column.column) {
                    try Self.rawExec(handle, column.sql)
                }
                try Self.rawExec(handle, SimiGoESISDatabase.v16Indexes)
                try recordMigrationRow(16, "simigo-external-turn-provenance-v16")
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
        public let settlementSummaries: Int
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

    /// `true` only when the stored bytes still hash to their address. A missing
    /// or corrupt object is `false`, never an empty success.
    public func verifyObject(_ objectID: String) -> Bool {
        (try? readObject(objectID)) != nil
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

    // MARK: - C-stage failure audit (append-only)

    /// Best-effort terminal audit write for one execution attempt.
    ///
    /// Never throws and never overwrites: if an entry already exists for
    /// `c-failure-audit:<execution_id>`, nothing is written and
    /// `auditPersisted` is `false`. A storage failure is reported the same way,
    /// so the caller's terminal result is unchanged either way.
    public func recordFailureAudit(_ event: SimiGoFailureAudit.Event) -> SimiGoFailureAudit.WriteResult {
        let data: Data
        do {
            data = try SimiGoFailureAudit.encoded(event)
        } catch {
            return SimiGoFailureAudit.WriteResult(
                auditPersisted: false, objectID: nil, failureClass: "unrepresentable_event")
        }
        let identity = SimiGoFailureAudit.identity(executionID: event.executionID)
        do {
            return try transactionResult {
                if try resolveIndexIdentity(identity, policy: .first) != nil {
                    return SimiGoFailureAudit.WriteResult(
                        auditPersisted: false, objectID: nil, failureClass: "duplicate_execution_id")
                }
                let objectID = try ensureObject(data)
                _ = try appendIndexEntryInTransaction(identity: identity, objectID: objectID)
                return SimiGoFailureAudit.WriteResult(
                    auditPersisted: true, objectID: objectID, failureClass: nil)
            }
        } catch {
            return SimiGoFailureAudit.WriteResult(
                auditPersisted: false, objectID: nil, failureClass: "storage_failure")
        }
    }

    /// Read back the audit record for an execution attempt, verifying both the
    /// stored bytes and the record's own schema.
    public func failureAudit(executionID: String) -> SimiGoFailureAudit.Event? {
        guard let entry = try? resolveIndexIdentity(
            SimiGoFailureAudit.identity(executionID: executionID), policy: .first),
            let data = try? readObject(entry.objectID) else { return nil }
        return try? SimiGoFailureAudit.decode(data)
    }

    /// Every audit entry ever appended for this execution id, oldest first.
    public func failureAuditHistory(executionID: String) throws -> [IndexEntry] {
        let stmt = try prepare("""
        SELECT append_order, srs_identity, record_object, recorded_at
        FROM is_index_entries WHERE srs_identity=? ORDER BY append_order;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, SimiGoFailureAudit.identity(executionID: executionID))
        var out: [IndexEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
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
                                         lifecycle: String, createdAt: Date,
                                         nextInput: String? = nil,
                                         prefixJSON: String? = nil,
                                         idempotencyKey: String? = nil) throws {
        try execBinding("""
        INSERT INTO execution_states(state_id, parent_id, model_identity, position, continuation_id, anchor, lifecycle, created_at, next_input, prefix_json, idempotency_key)
        VALUES(?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(state_id) DO UPDATE SET
            parent_id=excluded.parent_id, model_identity=excluded.model_identity, position=excluded.position,
            continuation_id=excluded.continuation_id, anchor=excluded.anchor, lifecycle=excluded.lifecycle,
            created_at=excluded.created_at,
            next_input=COALESCE(excluded.next_input, next_input),
            prefix_json=COALESCE(excluded.prefix_json, prefix_json),
            idempotency_key=COALESCE(excluded.idempotency_key, idempotency_key);
        """) { stmt in
            bind(stmt, 1, id)
            bind(stmt, 2, parentID)
            bind(stmt, 3, modelIdentity)
            bind(stmt, 4, Int64(position))
            bind(stmt, 5, continuationID)
            bind(stmt, 6, anchor)
            bind(stmt, 7, lifecycle)
            bind(stmt, 8, Self.stamp( createdAt))
            bind(stmt, 9, nextInput)
            bind(stmt, 10, prefixJSON)
            bind(stmt, 11, idempotencyKey)
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
        public let advancementID: String?
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

    @discardableResult
    public func recordNativeSettlementWithIdentity(
        _ settled: SimiGoSettlementAuthority.SettledResult,
        stateID: String,
        identity: SimiGoSettlementIdentityBinding.Identity,
        childState: ChildExecutionState? = nil,
        kvRepresentation: SimiGoSettlementKVBinding.Representation? = nil,
        inputSnapshotObjectID: String? = nil
    ) throws -> UUID {
        try recordNativeSettlementWithIdentityAndAdvancement(
            settled, stateID: stateID, identity: identity,
            childState: childState, advancement: nil,
            kvRepresentation: kvRepresentation,
            inputSnapshotObjectID: inputSnapshotObjectID
        ).settlementID
    }

    /// Atomic settlement + child state + identity bindings + advancement. The
    /// advancement is linked to the settlement row created in this transaction,
    /// so a downstream result can never claim an advancement it does not have.
    ///
    /// `kvRepresentation`, when present, is bound in the SAME transaction: a
    /// settlement can therefore never commit while claiming a prefix
    /// representation it did not also record. Only digests are stored.
    @discardableResult
    public func recordNativeSettlementWithIdentityAndAdvancement(
        _ settled: SimiGoSettlementAuthority.SettledResult,
        stateID: String,
        identity: SimiGoSettlementIdentityBinding.Identity,
        childState: ChildExecutionState? = nil,
        advancement: InformationAdvancementPlan?,
        kvRepresentation: SimiGoSettlementKVBinding.Representation? = nil,
        inputSnapshotObjectID: String? = nil,
        declaredDependencies: [DeclaredDependency] = []
    ) throws -> SettlementWithAdvancement {
        let settlementUUID = UUID()
        let settlementID = settlementUUID.uuidString
        var advancementID: String?
        try transaction {
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
                    rows: SimiGoSettlementKVBinding.bindings(for: kvRepresentation))
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
            if let advancement {
                advancementID = try insertInformationAdvancementRows(.init(
                    demandID: advancement.demandID, stateID: advancement.stateID,
                    settlementID: settlementID,
                    retrievalSettlementID: advancement.retrievalSettlementID,
                    actions: advancement.actions, result: advancement.result))
            }
        }
        return SettlementWithAdvancement(
            settlementID: settlementUUID, advancementID: advancementID)
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
        _ settled: SimiGoSettlementAuthority.SettledResult,
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
        INSERT INTO settlements(settlement_id, state_id, schema_version, payload, payload_digest, signature, contract_version, settled_at, validation_status, payload_object_id, input_snapshot_object_id)
        VALUES(?,?,?,?,?,?,?,?,?,?,?);
        """) { stmt in
            bind(stmt, 1, settlementID)
            bind(stmt, 2, stateID)
            bind(stmt, 3, settled.schemaVersion)
            bind(stmt, 4, Data())
            bind(stmt, 5, settled.payloadDigest)
            bind(stmt, 6, String?.none)
            bind(stmt, 7, NativeResultContract.supportedVersion)
            bind(stmt, 8, Self.stamp(settled.settledAt))
            bind(stmt, 9, validationStatusOverride ?? settled.trace.validationStatus)
            bind(stmt, 10, payloadObject)
            bind(stmt, 11, inputSnapshotObjectID)
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
        identity: SimiGoSettlementIdentityBinding.Identity,
        kvRepresentation: SimiGoSettlementKVBinding.Representation? = nil
    ) throws {
        try transaction {
            try insertIdentityBindingRows(settlementID: settlementID, identity: identity)
            if let kvRepresentation {
                try insertDerivedBindingRows(
                    settlementID: settlementID,
                    rows: SimiGoSettlementKVBinding.bindings(for: kvRepresentation))
            }
        }
    }

    /// Caller owns the transaction. This helper is shared by the legacy binding
    /// update and the atomic settlement+identity commit.
    private func insertIdentityBindingRows(
        settlementID: String,
        identity: SimiGoSettlementIdentityBinding.Identity
    ) throws {
        try insertDerivedBindingRows(
            settlementID: settlementID,
            rows: SimiGoSettlementIdentityBinding.bindings(for: identity))
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

    // MARK: - As-of snapshot reference (v12)

    /// The immutable `final` snapshot object this settlement committed with, or
    /// nil when the row predates snapshot capture. The value is never backfilled,
    /// so an absent reference is reported as absent rather than synthesized.
    public func settlementInputSnapshotObjectID(settlementID: String) throws -> String? {
        let stmt = try prepare("SELECT input_snapshot_object_id FROM settlements WHERE settlement_id=?;")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, settlementID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    // MARK: - Managed continuation (v13)

    /// Payload digest of a settlement row, or nil when the row does not exist.
    public func settlementPayloadDigest(_ settlementID: String) throws -> String? {
        let stmt = try prepare("SELECT payload_digest FROM settlements WHERE settlement_id=?;")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, settlementID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    /// The idempotency key an execution state was committed under, if any.
    public func executionStateIdempotencyKey(_ stateID: String) throws -> String? {
        let stmt = try prepare("SELECT idempotency_key FROM execution_states WHERE state_id=?;")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, stateID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    /// The execution state that already committed this idempotency key.
    public func executionStateID(idempotencyKey: String) throws -> String? {
        let stmt = try prepare("SELECT state_id FROM execution_states WHERE idempotency_key=?;")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, idempotencyKey)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
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
        public let settled: SimiGoSettlementAuthority.SettledResult
        public let identity: SimiGoSettlementIdentityBinding.Identity
        public let childState: ChildExecutionState
        public let preCommit: () throws -> Void

        public init(
            executionID: String, attempt: Int, idempotencyKey: String,
            fingerprint: String, finalSnapshot: Data,
            settled: SimiGoSettlementAuthority.SettledResult,
            identity: SimiGoSettlementIdentityBinding.Identity,
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
                throw SimiGoManagedRefusal.Refusal(
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
        /// True when the pass built only a physical index (locator/digest/size)
        /// and did not copy entity bytes into the object store.
        public let indexOnly: Bool
        /// Bytes read from the filesystem to compute digests / validate text.
        /// These are read-only; `bytesAddressed` stays the copy measure.
        public let entityBytesRead: Int
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
        let previous: FileContentState?
    }

    /// 结算一个工作根：逐文件计算 SHA-256，内容写入内容寻址对象库
    /// （相同字节只存一次），`file_contents` 只保留身份/摘要引用；索引与
    /// 依赖账本追加记录，历史不覆盖。删除或变为二进制/超限的文件会撤销
    /// 其内容引用并失效依赖闭包。文本判定：utf8 且 ≤ fileByteCap。
    @discardableResult
    public func settleWorkRootContents(
        rootID: String, rootURL: URL, category: String = "work",
        fileByteCap: Int = 1 << 20, maxDepth: Int = 4,
        carryText: Bool = true
    ) throws -> ContentSettleReport {
        let fm = FileManager.default
        // file_contents references roots, so the root must exist before any
        // content row is written (new roots start here, not in the index pass).
        // Recording the absolute path here is what makes the locator evidence
        // durable: later metadata-only upserts must not erase it.
        try upsertRoot(rootID: rootID, category: category,
                       displayName: rootURL.path,
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
        var entityBytesRead = 0
        var seen = Set<String>()
        var pending: [PendingSettlement] = []
        var cleared: [(relativePath: String, previous: FileContentState, missing: Bool)] = []
        var indexedFiles: [(rel: String, url: URL, size: Int64, modified: String?, digest: String?)] = []
        let modifiedFormatter = ISO8601DateFormatter()

        let scanRoot = rootURL.resolvingSymlinksInPath()
        guard let enumerator = fm.enumerator(
            at: scanRoot,
            includingPropertiesForKeys: [
                .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else {
            // Enumerating an unreadable root must not look like "every file was
            // deleted" — that would strand the carried content behind a mass
            // invalidation. Refuse and leave the previous settlement intact.
            throw DatabaseError.sql(
                "settleWorkRootContents: cannot enumerate root \(rootID)")
        }
        while let file = enumerator.nextObject() as? URL {
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
            let values = try? file.resourceValues(forKeys: [
                .fileSizeKey, .contentModificationDateKey,
            ])
            let size = Int64(values?.fileSize ?? 0)
            let modified = values?.contentModificationDate.map {
                modifiedFormatter.string(from: $0)
            }

            // Size from metadata first: a multi-GB root is mostly binaries, and
            // reading them only to discard them made a stale scan I/O bound.
            guard size <= Int64(fileByteCap),
                let data = try? Data(contentsOf: file), data.count <= fileByteCap
            else {
                skipped += 1
                indexedFiles.append((rel, file, size, modified, nil))
                if let old = previous[rel] {
                    cleared.append((rel, old, false))
                }
                continue
            }
            let digest = NativeSHA256.hexDigest(data)
            entityBytesRead += data.count
            indexedFiles.append((rel, file, size, modified, digest))
            guard String(data: data, encoding: .utf8) != nil else {
                skipped += 1
                if let old = previous[rel] {
                    cleared.append((rel, old, false))
                }
                continue
            }
            // Reuse only when the settled digest still matches AND the row is in
            // the mode being settled now. An index-only pass over a text-carrying
            // row must re-settle once to drop the copied bytes.
            if let old = previous[rel], old.digest == digest,
                carryText ? old.objectID != nil : old.objectID == nil
            {
                reused += 1
                continue
            }
            pending.append(PendingSettlement(
                relativePath: rel, url: file, data: data, digest: digest,
                size: size, modified: modified, previous: previous[rel]))
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
                try execBinding("""
                UPDATE information_items SET state='STALE', updated_at=?
                WHERE item_id=?;
                """) { stmt in
                    bind(stmt, 1, now)
                    bind(stmt, 2, "file:\(rootID)/\(item.relativePath)")
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
                    ]
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
                    bind(stmt, 1, rootID)
                    bind(stmt, 2, item.relativePath)
                    bind(stmt, 3, item.digest)
                    bind(stmt, 4, now)
                    if carryText {
                        bind(stmt, 5, indexObject.id)
                    } else {
                        sqlite3_bind_null(stmt, 5)
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
                    bind(stmt, 1, identity)
                    bind(stmt, 2, "file")
                    bind(stmt, 3, item.url.path)
                    bind(stmt, 4, item.modified ?? item.digest)
                    bind(stmt, 5, item.digest)
                    bind(stmt, 6, now)
                }
                _ = try appendIndexEntryInTransaction(
                    identity: identity, objectID: indexObject.id)
                _ = try appendDependencyInTransaction(
                    dependencyID: identity, contentAddress: indexObject.id,
                    reason: item.previous == nil ? "content-settle" : "content-update")
            }

            for file in indexedFiles {
                try indexExternalFile(
                    rootID: rootID, category: category,
                    relativePath: file.rel,
                    kind: file.url.pathExtension.isEmpty ? nil : file.url.pathExtension,
                    size: file.size, modifiedAt: file.modified,
                    contentDigest: file.digest)
            }
            try markSettlementsInvalidInTransaction(Array(invalidated))
        }
        try markRootScanned(rootID)

        return ContentSettleReport(
            scanned: scanned, reused: reused, settled: pending.count,
            skippedBinaryOrLarge: skipped,
            changed: pending.filter { $0.previous != nil }.count,
            removed: removed, invalidatedSettlements: invalidated.count,
            objectsCreated: created, deduplicated: deduplicated,
            bytesAddressed: bytesAddressed,
            indexOnly: !carryText, entityBytesRead: entityBytesRead)
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
        carryText: Bool = false
    ) throws -> RootReconcileReport {
        let fm = FileManager.default
        let stmt = try prepare("""
        SELECT root_id, display_name, last_scanned_at FROM roots
        WHERE category=? ORDER BY root_id;
        """)
        bind(stmt, 1, category)
        var rows: [(id: String, path: String?, scanned: String?)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func text(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            rows.append((text(0) ?? "", text(1), text(2)))
        }
        sqlite3_finalize(stmt)

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
                    category: category, carryText: carryText)
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
            bind(stmt, Int32(index + 1), root)
        }
        var digests: [String] = []
        var roots: [String] = []
        var entries: [CanonicalDemandInput.Entry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
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
        let canonicalInput = try canonicalDemandInput(
            query: query, rootIDs: rootID.map { [$0] })
        var inputs: [(root: String, path: String, objectID: String)] = []
        var unresolvedInputs: [(root: String, path: String)] = []
        for entry in canonicalInput.entries {
            if let objectID = entry.objectID {
                inputs.append((entry.rootID, entry.relativePath, objectID))
            } else {
                // Index-only settlement: the address is the identity record's
                // metadata object, not a copy of the entity bytes.
                unresolvedInputs.append((entry.rootID, entry.relativePath))
            }
        }
        for input in unresolvedInputs {
            if let address = try latestIndexObjectID(
                identity: "file:\(input.root)/\(input.path)")
            {
                inputs.append((input.root, input.path, address))
            }
        }
        let canonical = canonicalInput.canonical
        let demandID = canonicalInput.digest
        let roots = canonicalInput.rootIDs

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

    /// 信息拓扑检索：在已结算的文件索引上按关键词命中（行级）。索引可以
    /// 只保存定位符 + 摘要（不拷贝实体），因此文本从注册根的定位符读取，
    /// 并**逐次校验结算摘要**：磁盘内容已变而尚未重新结算 → 该行不是命中，
    /// 由 ES 侧触发再结算（IS 只存/验，不判断语义）。
    public func searchSettledContent(query: String, rootID: String? = nil, limit: Int = 200)
        throws -> [ContentHit]
    {
        guard !query.isEmpty, limit > 0 else { return [] }
        let rows = try settledFileRows(rootID: rootID)
        var hits: [ContentHit] = []
        for row in rows {
            guard let body = try searchableFileText(row) else { continue }
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
    }

    func settledFileRows(rootID: String?) throws -> [SettledFileRow] {
        var sql = """
        SELECT root_id, relative_path, content_sha256, object_id, content
        FROM file_contents
        """
        if let rootID {
            sql += " WHERE root_id='" + rootID.replacingOccurrences(of: "'", with: "''") + "'"
        }
        sql += " ORDER BY root_id, relative_path;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var rows: [SettledFileRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func text(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            let bytes = Int(sqlite3_column_bytes(stmt, 4))
            let legacy = sqlite3_column_blob(stmt, 4).map { Data(bytes: $0, count: bytes) } ?? Data()
            rows.append(SettledFileRow(
                rootID: text(0) ?? "", relativePath: text(1) ?? "",
                digest: text(2) ?? "", objectID: text(3), legacy: legacy))
        }
        return rows
    }

    /// Settled text for a row, or nil when no source produces bytes matching
    /// the settled digest. Object store first (legacy/carrier rows), then the
    /// registered root locator (index-only rows).
    func searchableFileText(_ row: SettledFileRow) throws -> String? {
        if let objectID = row.objectID, !objectID.isEmpty,
            let data = try? readObject(objectID),
            NativeSHA256.hexDigest(data) == row.digest
        {
            return String(decoding: data, as: UTF8.self)
        }
        if !row.legacy.isEmpty, NativeSHA256.hexDigest(row.legacy) == row.digest {
            return String(decoding: row.legacy, as: UTF8.self)
        }
        guard let locator = try rootLocatorPath(row.rootID) else { return nil }
        let relative = row.relativePath
        guard !relative.isEmpty,
            !relative.split(separator: "/").contains("..")
        else { return nil }
        let url = URL(fileURLWithPath: locator).appendingPathComponent(relative)
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
            NativeSHA256.hexDigest(data) == row.digest
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func rootLocatorPath(_ rootID: String) throws -> String? {
        let stmt = try prepare("""
        SELECT display_name FROM roots
        WHERE root_id=? AND locator_type='path';
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, rootID)
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0)
        else { return nil }
        let path = String(cString: c)
        return path.isEmpty ? nil : path
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
    }

    /// Who produced a chat line. Local turns are the app's own conversation;
    /// external turns arrived through an upstream provider and keep that
    /// provenance for as long as the row exists.
    public enum ChatTurnSource: String, Sendable {
        case local
        case external
    }

    /// The standings a line can hold, as stored in `turn_state`. They are
    /// distinct questions: persisted (`pending`/`recorded`/`internal`),
    /// verified (`committed`), and retrievable (ordinary retrieval reads
    /// `committed` rows only, further narrowed by request scope).
    public enum ChatTurnState: String, Sendable {
        /// Local input whose own request is still in flight.
        case pending
        /// Persisted with provenance, not yet verified: recorded only.
        case recorded
        /// Verified/settled; eligible for ordinary retrieval.
        case committed
        /// Client bookkeeping kept as a record, never ordinary memory.
        case internalOperation = "internal"
    }

    /// Append one conversation line. A user row starts `pending` and only the
    /// turn that produced it can promote it (`commitChatTurn`): ordinary
    /// retrieval must never treat another request's in-flight input as memory.
    /// Other roles are written at completion, so they are eligible at once.
    /// Internal-operation rows are written `internal` and stay there.
    ///
    /// Returns the row id. A repeated trailing user message (tool-loop retry or
    /// retry of a cancelled turn) reuses its existing row instead of appending
    /// a duplicate, and the caller can still commit exactly that row.
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
        return existing != internalState
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
        let data = Data(assistantText.utf8)
        let digest = NativeSHA256.hexDigest(data)
        return try transactionResult {
            let assistantID = try insertChatMessage(
                sessionID: sessionID, role: "assistant", data: data, digest: digest,
                model: model, createdAt: createdAt,
                state: Self.completedState(for: eligibility))
            if userMessageID > 0, eligibility == .ordinary {
                try execBinding("""
                UPDATE chat_messages SET turn_state='committed'
                WHERE id=? AND session_id=? AND role='user' AND turn_state='pending';
                """) { stmt in
                    sqlite3_bind_int64(stmt, 1, userMessageID)
                    bind(stmt, 2, sessionID)
                }
            }
            return assistantID
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
            bind(stmt, 1, sessionID)
            bind(stmt, 2, role)
            bind(stmt, 3, "")
            if let model { bind(stmt, 4, model) } else { sqlite3_bind_null(stmt, 4) }
            bind(stmt, 5, digest)
            bind(stmt, 6, Self.stamp(createdAt))
            bind(stmt, 7, objectID)
            bind(stmt, 8, state)
            bind(stmt, 9, sourceKind.rawValue)
            bind(stmt, 10, sourceProvider)
            bind(stmt, 11, requestID)
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
            bind(stmt, 1, "chat:\(sessionID)/\(rowID)")
            bind(stmt, 2, "chat")
            bind(stmt, 3, "session:\(sessionID)#\(rowID)")
            bind(stmt, 4, Self.stamp(createdAt))
            bind(stmt, 5, digest)
            bind(stmt, 6, Self.stamp(createdAt))
        }
        return rowID
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
                bind(stmt, 1, Self.stamp(verifiedAt))
                bind(stmt, 2, sessionID)
                bind(stmt, 3, requestID)
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
        bind(stmt, 1, sessionID)
        bind(stmt, 2, requestID)
        bind(stmt, 3, role)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
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
            bind(stmt, Int32(offset + 1), argument)
        }
        var rows: [ChatTurnProvenance] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
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
        bind(stmt, 1, sessionID)
        guard sqlite3_step(stmt) == SQLITE_ROW,
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
        """
        if let sessionID {
            sql += " WHERE c.session_id='" + sessionID.replacingOccurrences(of: "'", with: "''") + "'"
        }
        sql += " ORDER BY c.session_id, c.id;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var hits: [ChatHit] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
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

    /// Eligible chat messages as demand inputs, with their settled digest.
    /// Eligibility is the turn's own completion (`commitChatTurn`), not mere
    /// presence in the live table: another request's in-flight user text and a
    /// cancelled turn's input are conversation lines without semantic standing.
    func chatIndexRows(sessionIDs: [String]?) throws -> [ChatIndexRow] {
        var sql = """
        SELECT c.session_id, c.id, c.role,
               COALESCE(CAST(o.content AS TEXT), c.content),
               c.content_sha256, c.created_at
        FROM chat_messages c
        LEFT JOIN is_objects o ON o.object_id=c.content_object_id
        WHERE c.turn_state='committed'
        """
        if let sessionIDs, !sessionIDs.isEmpty {
            let quoted = sessionIDs.map {
                "'" + $0.replacingOccurrences(of: "'", with: "''") + "'"
            }
            sql += " AND c.session_id IN (\(quoted.joined(separator: ",")))"
        }
        sql += " ORDER BY c.session_id, c.id;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var rows: [ChatIndexRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
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

    /// The carrier object currently addressed by an index identity. Index-only
    /// file rows point here at their metadata record, not at file bytes.
    public func latestIndexObjectID(identity: String) throws -> String? {
        let stmt = try prepare("""
        SELECT record_object FROM is_index_entries
        WHERE srs_identity=? ORDER BY append_order DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, identity)
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0)
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
        ORDER BY a.advanced_at DESC, a.advancement_id DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, sessionID)
        bind(stmt, 2, query)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
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
        let inputDigest = NativeSHA256.hexDigest(
            Data((try Self.canonicalJSON(["query": query, "session": sessionID])).utf8))
        let actionsJSON = (try? JSONSerialization.data(
            withJSONObject: actions, options: [.sortedKeys, .withoutEscapingSlashes]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let resultJSON = String(decoding: receipt.payload, as: UTF8.self)
        let now = Self.stamp(advancedAt)
        try transaction {
            try execBinding("""
            INSERT INTO information_demands(
                demand_id, state_id, session_id, continuation_point, query,
                required_item_ids_json, pending_obligations_json,
                continuation_conditions_json, input_digest, retrieval_demand_id,
                retrieval_settlement_id, state, created_at)
            VALUES(?,?,?,'settled-answer',?,'[]','[]','[]',?,NULL,NULL,'ADVANCED',?);
            """) { stmt in
                bind(stmt, 1, demandID)
                bind(stmt, 2, stateID)
                bind(stmt, 3, sessionID)
                bind(stmt, 4, query)
                bind(stmt, 5, inputDigest)
                bind(stmt, 6, now)
            }
            try execBinding("""
            INSERT INTO information_advancements(
                advancement_id, demand_id, state_id, settlement_id,
                retrieval_settlement_id, actions_json, result_json, advanced_at)
            VALUES(?,?,?,?,NULL,?,?,?);
            """) { stmt in
                bind(stmt, 1, advancementID)
                bind(stmt, 2, demandID)
                bind(stmt, 3, stateID)
                bind(stmt, 4, settlementID)
                bind(stmt, 5, actionsJSON)
                bind(stmt, 6, resultJSON)
                bind(stmt, 7, now)
            }
        }
        return demandID
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
        guard !demandID.isEmpty else {
            throw InformationReuseError.emptyField("demand_id")
        }
        guard !sourceSettlementID.isEmpty else {
            throw InformationReuseError.emptyField("source_settlement_id")
        }
        let digest = NativeSHA256.hexDigest(Data("\(sessionID)|\(query)".utf8))
        return try transactionResult {
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
                bind(stmt, 1, reuseID)
                bind(stmt, 2, sourceSettlementID)
                bind(stmt, 3, sourceStateID)
                bind(stmt, 4, demandID)
                bind(stmt, 5, sessionID)
                if let consumerStateID {
                    bind(stmt, 6, consumerStateID)
                } else {
                    sqlite3_bind_null(stmt, 6)
                }
                bind(stmt, 7, digest)
                bind(stmt, 8, stamp)
            }
            return InformationReuseEvent(
                reuseID: reuseID, sourceSettlementID: sourceSettlementID,
                sourceStateID: sourceStateID, demandID: demandID,
                sessionID: sessionID, consumerStateID: consumerStateID,
                canonicalDigest: digest, modelCalls: 0, reusedAt: stamp)
        }
    }

    public func informationReuseEvent(demandID: String) throws -> InformationReuseEvent? {
        let stmt = try prepare("""
        SELECT reuse_id, source_settlement_id, source_state_id, demand_id,
               session_id, consumer_state_id, canonical_digest, model_calls,
               reused_at
        FROM information_reuse_events WHERE demand_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, demandID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
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
        bind(stmt, 1, demandID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
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

    public struct InformationRetrievalWrite: Sendable {
        public let demandID: String
        public let stateID: String?
        public let sessionID: String?
        public let query: String
        public let rootIDs: [String]
        public let includeChat: Bool
        public let inputDigest: String
        public let payload: Data
        public let hitCount: Int
        public let itemIDs: [String]
        public let inputs: [InformationInput]
        public let evaluatedAt: Date

        public init(demandID: String, stateID: String?, sessionID: String?,
                    query: String, rootIDs: [String], includeChat: Bool,
                    inputDigest: String, payload: Data, hitCount: Int,
                    itemIDs: [String], inputs: [InformationInput],
                    evaluatedAt: Date = Date()) {
            self.demandID = demandID; self.stateID = stateID
            self.sessionID = sessionID; self.query = query
            self.rootIDs = rootIDs; self.includeChat = includeChat
            self.inputDigest = inputDigest; self.payload = payload
            self.hitCount = hitCount; self.itemIDs = itemIDs
            self.inputs = inputs; self.evaluatedAt = evaluatedAt
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
            resultObjectID = try ensureObject(write.payload)
            try execBinding("""
            INSERT INTO settlements(settlement_id, state_id, schema_version, payload, payload_digest, signature, contract_version, settled_at, validation_status, payload_object_id)
            VALUES(?,NULL,?,?,?,NULL,?,?,?,?)
            ON CONFLICT(settlement_id) DO UPDATE SET
                schema_version=excluded.schema_version, payload_digest=excluded.payload_digest,
                settled_at=excluded.settled_at, validation_status=excluded.validation_status,
                payload_object_id=excluded.payload_object_id;
            """) { stmt in
                bind(stmt, 1, settlementID)
                bind(stmt, 2, "simigo.information-demand/v1")
                bind(stmt, 3, Data())
                bind(stmt, 4, resultSHA)
                bind(stmt, 5, "simigo.is-retrieval/v1")
                bind(stmt, 6, now)
                bind(stmt, 7, "IS_RETRIEVAL")
                bind(stmt, 8, resultObjectID)
            }
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
                bind(stmt, 1, write.demandID)
                bind(stmt, 2, write.query)
                bind(stmt, 3, write.rootIDs.joined(separator: ","))
                bind(stmt, 4, write.inputDigest)
                bind(stmt, 5, resultSHA)
                bind(stmt, 6, Int64(write.hitCount))
                bind(stmt, 7, now)
                bind(stmt, 8, resultObjectID)
                bind(stmt, 9, Int64(write.includeChat ? 1 : 0))
                bind(stmt, 10, settlementID)
            }

            let itemsJSON = (try? JSONSerialization.data(
                withJSONObject: write.itemIDs, options: [.sortedKeys, .withoutEscapingSlashes]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            try execBinding("""
            INSERT INTO information_demands(
                demand_id, state_id, session_id, continuation_point, query,
                required_item_ids_json, pending_obligations_json,
                continuation_conditions_json, input_digest, retrieval_demand_id,
                retrieval_settlement_id, state, created_at)
            VALUES(?,?,?,'information-retrieval',?,?,'[]','[]',?,?,?,'RESOLVED',?)
            ON CONFLICT(demand_id) DO UPDATE SET
                state_id=excluded.state_id, session_id=excluded.session_id,
                query=excluded.query,
                required_item_ids_json=excluded.required_item_ids_json,
                input_digest=excluded.input_digest,
                retrieval_demand_id=excluded.retrieval_demand_id,
                retrieval_settlement_id=excluded.retrieval_settlement_id,
                state='RESOLVED';
            """) { stmt in
                bind(stmt, 1, write.demandID)
                bind(stmt, 2, write.stateID)
                bind(stmt, 3, write.sessionID)
                bind(stmt, 4, write.query)
                bind(stmt, 5, itemsJSON)
                bind(stmt, 6, write.inputDigest)
                bind(stmt, 7, write.demandID)
                bind(stmt, 8, settlementID)
                bind(stmt, 9, now)
            }
            // A newer demand for the same ES state/query supersedes the old one,
            // but an already-advanced demand keeps its receipt.
            try execBinding("""
            UPDATE information_demands SET state='SUPERSEDED'
            WHERE state_id IS ? AND query=? AND demand_id<>? AND state='RESOLVED';
            """) { stmt in
                bind(stmt, 1, write.stateID)
                bind(stmt, 2, write.query)
                bind(stmt, 3, write.demandID)
            }
            for input in write.inputs {
                _ = try appendDependencyInTransaction(
                    dependencyID: "demand:\(write.demandID) -> \(input.itemID)",
                    contentAddress: input.contentAddress,
                    reason: "demand-input")
            }
        }
        return InformationRetrievalCommit(
            retrievalSettlementID: settlementID,
            resultSHA256: resultSHA, resultObjectID: resultObjectID)
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
        WHERE r.demand_id=? AND r.status='valid'
          AND s.validity='valid' AND s.invalidated_at IS NULL;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, demandID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let digest = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
        guard let objectText = sqlite3_column_text(stmt, 1) else { return nil }
        let objectID = String(cString: objectText)
        guard let data = try? readObject(objectID),
            NativeSHA256.hexDigest(data) == digest
        else { return nil }
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
        try transaction {
            try insertInformationAdvancementRows(write, advancementID: advancementID)
        }
        return advancementID
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
        try execBinding("""
        INSERT INTO information_advancements(
            advancement_id, demand_id, state_id, settlement_id,
            retrieval_settlement_id, actions_json, result_json, advanced_at)
        VALUES(?,?,?,?,?,?,?,?);
        """) { stmt in
            bind(stmt, 1, advancementID)
            bind(stmt, 2, write.demandID)
            bind(stmt, 3, write.stateID)
            bind(stmt, 4, write.settlementID)
            bind(stmt, 5, write.retrievalSettlementID)
            bind(stmt, 6, actionsJSON)
            bind(stmt, 7, resultJSON)
            bind(stmt, 8, now)
        }
        try execBinding("""
        UPDATE information_demands SET state='ADVANCED' WHERE demand_id=?;
        """) { stmt in bind(stmt, 1, write.demandID) }
        try execBinding("""
        INSERT INTO dependency_edges(from_settlement, to_settlement, kind)
        SELECT ?,?,?
        WHERE NOT EXISTS (
            SELECT 1 FROM dependency_edges
            WHERE from_settlement=? AND to_settlement=? AND kind='information-demand');
        """) { stmt in
            bind(stmt, 1, write.settlementID)
            bind(stmt, 2, write.retrievalSettlementID)
            bind(stmt, 3, "information-demand")
            bind(stmt, 4, write.settlementID)
            bind(stmt, 5, write.retrievalSettlementID)
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
    /// `SimiGoSettlementConsumption`) has already re-admitted the named source
    /// and re-checked the contract/canonical basis INSIDE the same transaction;
    /// this plan is only the set of rows to commit.
    struct SettlementConsumptionPlan {
        let consumptionID: String
        let sourceSettlementID: String
        let sourcePayloadDigest: String
        let consumerState: ChildExecutionState
        let consumerIdentity: SimiGoSettlementIdentityBinding.Identity
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
        let settled = try SimiGoSettlementAuthority.authorize(
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
            rows: SimiGoSettlementIdentityBinding.consumerBindings(
                for: plan.consumerIdentity))

        try execBinding("""
        INSERT INTO settlement_consumptions(
            consumption_id, source_settlement_id, consumer_state_id,
            consumer_settlement_id, demand_id, contract_id, demand_class,
            contract_version, canonical_digest, basis_json, model_calls, created_at)
        VALUES(?,?,?,?,?,?,?,?,?,?,0,?);
        """) { stmt in
            bind(stmt, 1, plan.consumptionID)
            bind(stmt, 2, plan.sourceSettlementID)
            bind(stmt, 3, plan.consumerState.id)
            bind(stmt, 4, consumerSettlementID)
            bind(stmt, 5, plan.demandID)
            bind(stmt, 6, plan.contractID)
            bind(stmt, 7, plan.demandClass)
            bind(stmt, 8, plan.contractVersion)
            bind(stmt, 9, plan.canonicalDigest)
            bind(stmt, 10, plan.basisJSON)
            bind(stmt, 11, Self.stamp(plan.consumedAt))
        }

        try execBinding("""
        INSERT INTO dependency_edges(from_settlement, to_settlement, kind)
        SELECT ?,?,?
        WHERE NOT EXISTS (
            SELECT 1 FROM dependency_edges
            WHERE from_settlement=? AND to_settlement=? AND kind='settlement-consumption');
        """) { stmt in
            bind(stmt, 1, consumerSettlementID)
            bind(stmt, 2, plan.sourceSettlementID)
            bind(stmt, 3, "settlement-consumption")
            bind(stmt, 4, consumerSettlementID)
            bind(stmt, 5, plan.sourceSettlementID)
        }
        if let address = try settlementPayloadObject(plan.sourceSettlementID) {
            _ = try appendDependencyInTransaction(
                dependencyID: "settlement:\(consumerSettlementID) -> settlement:\(plan.sourceSettlementID)",
                contentAddress: address,
                reason: "settlement-consumption")
        }

        let itemsJSON = "[]"
        try execBinding("""
        INSERT INTO information_demands(
            demand_id, state_id, session_id, continuation_point, query,
            required_item_ids_json, pending_obligations_json,
            continuation_conditions_json, input_digest, retrieval_demand_id,
            retrieval_settlement_id, state, created_at)
        VALUES(?,?,NULL,'settlement-consumption',?,?,'[]','[]',?,NULL,NULL,'ADVANCED',?)
        ON CONFLICT(demand_id) DO UPDATE SET
            state_id=excluded.state_id, query=excluded.query,
            input_digest=excluded.input_digest, state='ADVANCED';
        """) { stmt in
            bind(stmt, 1, plan.demandID)
            bind(stmt, 2, plan.consumerState.id)
            bind(stmt, 3, plan.query)
            bind(stmt, 4, itemsJSON)
            bind(stmt, 5, plan.canonicalDigest)
            bind(stmt, 6, Self.stamp(plan.consumedAt))
        }
        try execBinding("""
        INSERT INTO information_advancements(
            advancement_id, demand_id, state_id, settlement_id,
            retrieval_settlement_id, actions_json, result_json, advanced_at)
        VALUES(?,?,?,?,NULL,?,?,?);
        """) { stmt in
            bind(stmt, 1, advancementID)
            bind(stmt, 2, plan.demandID)
            bind(stmt, 3, plan.consumerState.id)
            bind(stmt, 4, consumerSettlementID)
            bind(stmt, 5, "[\"consume-settlement\"]")
            bind(stmt, 6, String(decoding: settled.validatedPayload, as: UTF8.self))
            bind(stmt, 7, Self.stamp(plan.consumedAt))
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
    /// the settled unit, never inferred from text similarity.
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
        declaredAt: Date = Date()
    ) throws -> SettlementReuseDeclaration {
        try transactionResult {
            guard let row = try settlementAdmissionRow(settlementID: settlementID) else {
                throw SimiGoSettlementConsumption.Refusal.unknownSource(settlementID)
            }
            guard row.validationStatus != "MIGRATED_LEGACY" else {
                throw SimiGoSettlementConsumption.Refusal.unknownSource(settlementID)
            }
            guard row.validity == "valid" else {
                throw SimiGoSettlementConsumption.Refusal.sourceNotValid(settlementID)
            }
            guard SimiGoSettlementAuthority.payloadDigestMatches(
                row.payload, recordedDigest: row.recordedPayloadDigest)
            else {
                throw SimiGoSettlementConsumption.Refusal.sourceTampered(settlementID)
            }
            let canonical = try canonicalDemandInput(query: query, rootIDs: rootIDs)
            // The declared root set is what the demand NAMED, not only the roots
            // that currently carry files: an extra empty root must still count as
            // a different demand.
            let requestedRoots = (rootIDs?.isEmpty == false)
                ? Array(Set(rootIDs!)).sorted()
                : canonical.rootIDs
            let bindings = try settlementBindings(settlementID: settlementID)
            let derived = row.validationStatus == "DERIVED_CONSUMPTION"
            let modelKey = derived
                ? SimiGoSettlementIdentityBinding.consumerModelKey
                : SimiGoSettlementIdentityBinding.modelKey
            let tokenizerKey = derived
                ? SimiGoSettlementIdentityBinding.consumerTokenizerKey
                : SimiGoSettlementIdentityBinding.tokenizerKey
            guard let model = bindings[modelKey], !model.isEmpty,
                let tokenizer = bindings[tokenizerKey], !tokenizer.isEmpty
            else {
                throw SimiGoSettlementConsumption.Refusal.identityUndeclared(settlementID)
            }
            let identityJSON = try Self.canonicalJSON([
                "kind": derived ? "consumer" : "producer",
                "model": model,
                "tokenizer": tokenizer,
            ])
            let rootsJSON = try Self.canonicalJSON(requestedRoots)

            if let existing = try settlementReuseContract(settlementID: settlementID) {
                let same = existing.contractID == contractID
                    && existing.demandClass == demandClass
                    && existing.contractVersion == contractVersion
                    && existing.query == query
                    && existing.rootIDs == requestedRoots
                    && existing.canonicalDigest == canonical.digest
                    && existing.requiredIdentityJSON == identityJSON
                    && existing.extractField == extractField
                guard same else {
                    throw SimiGoSettlementConsumption.Refusal.contractMismatch(
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
                bind(stmt, 1, settlementID)
                bind(stmt, 2, contractID)
                bind(stmt, 3, demandClass)
                bind(stmt, 4, contractVersion)
                bind(stmt, 5, query)
                bind(stmt, 6, rootsJSON)
                bind(stmt, 7, canonical.canonical)
                bind(stmt, 8, canonical.digest)
                bind(stmt, 9, identityJSON)
                bind(stmt, 10, extractField)
                bind(stmt, 11, stamp)
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
        bind(stmt, 1, settlementID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        func text(_ i: Int32) -> String {
            sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
        }
        let roots = (try? JSONDecoder().decode([String].self, from: Data(text(5).utf8))) ?? []
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
        bind(stmt, 1, sourceSettlementID)
        bind(stmt, 2, consumerStateID)
        bind(stmt, 3, demandID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
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
        bind(stmt, 1, consumerStateID)
        var out: [SettlementConsumptionRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
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
        try execBinding("""
        INSERT INTO chat_execution_links(session_id, current_state_id, model_identity, updated_at)
        VALUES(?,?,?,?)
        ON CONFLICT(session_id) DO UPDATE SET
            current_state_id=excluded.current_state_id,
            model_identity=excluded.model_identity,
            updated_at=excluded.updated_at;
        """) { stmt in
            bind(stmt, 1, sessionID)
            bind(stmt, 2, stateID)
            bind(stmt, 3, modelIdentity)
            bind(stmt, 4, Self.stamp(Date()))
        }
    }

    public func currentChatStateID(sessionID: String) throws -> String? {
        let stmt = try prepare("""
        SELECT current_state_id FROM chat_execution_links WHERE session_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, sessionID)
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0)
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
        bind(stmt, 1, stateID)
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0)
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
        bind(stmt, 1, stateID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    public func executionStatePosition(_ stateID: String) throws -> Int? {
        let stmt = try prepare("""
        SELECT position FROM execution_states WHERE state_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, stateID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
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
            bind(stmt, 1, rootID)
            bind(stmt, 2, category)
            bind(stmt, 3, displayName)
            bind(stmt, 4, locatorType)
            bind(stmt, 5, status)
            bind(stmt, 6, now)
        }
    }

    /// Record that a root has just been fully scanned. Kept separate from
    /// `upsertRoot` so metadata refreshes never claim a scan that did not run.
    public func markRootScanned(_ rootID: String, status: String = "present") throws {
        try execBinding("""
        UPDATE roots SET status=?, last_scanned_at=? WHERE root_id=?;
        """) { stmt in
            bind(stmt, 1, status)
            bind(stmt, 2, Self.stamp(Date()))
            bind(stmt, 3, rootID)
        }
    }

    /// Change a root's state without pretending it was scanned — used when the
    /// backing directory is absent, so its carried content is left untouched.
    public func markRootStatus(_ rootID: String, status: String) throws {
        try execBinding("UPDATE roots SET status=? WHERE root_id=?;") { stmt in
            bind(stmt, 1, status)
            bind(stmt, 2, rootID)
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
            // A bridged retrieval row is the demand-side view of the same
            // settlement. Leaving it 'valid' would advertise reuse to every
            // reader that keys on status alone.
            try execBinding("""
            UPDATE retrieval_settlements SET status='invalidated'
            WHERE bridged_settlement_id=? AND status='valid';
            """) { stmt in
                bind(stmt, 1, id)
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

    /// Number of MODEL-PRODUCED settlements currently valid. Derived
    /// consumption rows are valid and chainable, but counting them as model
    /// output would overstate how much work the engine actually did.
    public func validSettlementCount() throws -> Int {
        let stmt = try prepare("""
        SELECT COUNT(*) FROM settlements
        WHERE validity='valid' AND ifnull(validation_status,'')<>'DERIVED_CONSUMPTION';
        """)
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW { return Int(sqlite3_column_int64(stmt, 0)) }
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
        SELECT state_id, payload, payload_digest, validation_status, validity, payload_object_id
        FROM settlements WHERE settlement_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, settlementID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
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
        SELECT state_id, payload, schema_version, contract_version, settled_at,
               validation_status, validity, invalidated_at, payload_object_id
        FROM settlements WHERE settlement_id=?;
        """)
        bind(stmt, 1, settlementID)
        if sqlite3_step(stmt) == SQLITE_ROW {
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
        sqlite3_finalize(stmt)
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
        public let query: String
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
        bind(stmt, 1, settlementID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
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

        try execBinding("""
        INSERT INTO settlement_summaries(
            settlement_id, session_id, query, summary, summary_sha256,
            summary_object_id, source_payload_digest, created_at,
            derivation_type, provenance_settlement_id)
        VALUES(?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(settlement_id) DO UPDATE SET
            session_id=excluded.session_id, query=excluded.query,
            summary=excluded.summary, summary_sha256=excluded.summary_sha256,
            summary_object_id=excluded.summary_object_id,
            source_payload_digest=excluded.source_payload_digest,
            created_at=excluded.created_at,
            derivation_type=excluded.derivation_type,
            provenance_settlement_id=excluded.provenance_settlement_id;
        """) { stmt in
            bind(stmt, 1, settlementID)
            bind(stmt, 2, sessionID)
            bind(stmt, 3, query)
            bind(stmt, 4, text)
            bind(stmt, 5, summarySHA)
            bind(stmt, 6, objectID)
            bind(stmt, 7, payloadDigest)
            bind(stmt, 8, stamp)
            bind(stmt, 9, derived ? "DERIVED_CONSUMPTION" : nil)
            bind(stmt, 10, provenance)
        }
        _ = try appendIndexEntryInTransaction(
            identity: "settlement-summary:\(settlementID)", objectID: objectID)

        return SettlementSummaryRecord(
            settlementID: settlementID, sessionID: sessionID, query: query,
            summary: text, summarySHA256: summarySHA,
            summaryObjectID: objectID, sourcePayloadDigest: payloadDigest,
            createdAt: stamp,
            derivationType: derived ? "DERIVED_CONSUMPTION" : nil,
            sourceSettlementID: provenance)
    }

    /// Read one summary back with its object bytes verified against the address.
    public func settlementSummary(settlementID: String) throws -> SettlementSummaryRecord? {
        let stmt = try prepare("""
        SELECT settlement_id, session_id, query, summary, summary_sha256,
               summary_object_id, source_payload_digest, created_at,
               derivation_type, provenance_settlement_id
        FROM settlement_summaries WHERE settlement_id=?;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, settlementID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        func text(_ i: Int32) -> String {
            sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
        }
        let record = SettlementSummaryRecord(
            settlementID: text(0),
            sessionID: sqlite3_column_text(stmt, 1).map { String(cString: $0) },
            query: text(2), summary: text(3), summarySHA256: text(4),
            summaryObjectID: text(5), sourcePayloadDigest: text(6),
            createdAt: text(7),
            derivationType: sqlite3_column_text(stmt, 8).map { String(cString: $0) },
            sourceSettlementID: sqlite3_column_text(stmt, 9).map { String(cString: $0) })
        return try verified(record)
    }

    /// Summaries a later demand may cite: still valid, never a retrieval result
    /// or a migrated legacy row, and not the demand's own conversation. A
    /// `DERIVED_CONSUMPTION` summary IS citable, but it carries its derivation
    /// type and source settlement so a consumer cannot present it as independent
    /// generation evidence. Newest first.
    public func citableSettlementSummaries(
        sessionID: String?, limit: Int = 200
    ) throws -> [SettlementSummaryRecord] {
        let stmt = try prepare("""
        SELECT m.settlement_id, m.session_id, m.query, m.summary, m.summary_sha256,
               m.summary_object_id, m.source_payload_digest, m.created_at,
               m.derivation_type, m.provenance_settlement_id
        FROM settlement_summaries m
        JOIN settlements s ON s.settlement_id=m.settlement_id
        WHERE s.validity='valid' AND s.invalidated_at IS NULL
          AND ifnull(s.validation_status,'') NOT IN ('IS_RETRIEVAL','MIGRATED_LEGACY')
          AND (m.session_id IS NULL OR m.session_id<>?)
        ORDER BY m.created_at DESC, m.settlement_id
        LIMIT ?;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, sessionID ?? "")
        bind(stmt, 2, Int64(max(1, min(limit, 2000))))
        var out: [SettlementSummaryRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func text(_ i: Int32) -> String {
                sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
            }
            let record = SettlementSummaryRecord(
                settlementID: text(0),
                sessionID: sqlite3_column_text(stmt, 1).map { String(cString: $0) },
                query: text(2), summary: text(3), summarySHA256: text(4),
                summaryObjectID: text(5), sourcePayloadDigest: text(6),
                createdAt: text(7),
                derivationType: sqlite3_column_text(stmt, 8).map { String(cString: $0) },
                sourceSettlementID: sqlite3_column_text(stmt, 9).map { String(cString: $0) })
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
        guard sealed.settlementID == record.settlementID,
            sealed.text == record.summary,
            sealed.sourcePayloadDigest == record.sourcePayloadDigest,
            sealed.derivationType == record.derivationType,
            sealed.sourceSettlementID == record.sourceSettlementID
        else { return nil }
        return record
    }

    /// The settlement a derived consumption record consumed. Used to stamp the
    /// summary's provenance chain in the SAME transaction as the consumption.
    private func consumptionSource(consumerSettlementID: String) throws -> String? {
        let stmt = try prepare("""
        SELECT source_settlement_id FROM settlement_consumptions
        WHERE consumer_settlement_id=? ORDER BY created_at LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, consumerSettlementID)
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0)
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
        var pending: [(id: String, settledAt: String, status: String?)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let settledAt = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let status = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            if !id.isEmpty { pending.append((id, settledAt, status)) }
        }
        sqlite3_finalize(stmt)

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
            bind(ctx, 1, row.id)
            if sqlite3_step(ctx) == SQLITE_ROW {
                query = sqlite3_column_text(ctx, 0).map { String(cString: $0) } ?? ""
                sessionID = sqlite3_column_text(ctx, 1).map { String(cString: $0) }
            }
            sqlite3_finalize(ctx)
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
        bind(stmt, 1, Int64(prefix.utf8.count))
        bind(stmt, 2, prefix)
        var out: [DependencyEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
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
        var found = false

        let stmt = try prepare("""
        SELECT f.content_sha256, f.object_id, f.settled_at, f.content, e.status
        FROM file_contents f
        LEFT JOIN external_files e
          ON e.root_id=f.root_id AND e.relative_path=f.relative_path
        WHERE f.root_id=? AND f.relative_path=?;
        """)
        bind(stmt, 1, rootID)
        bind(stmt, 2, relativePath)
        if sqlite3_step(stmt) == SQLITE_ROW {
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
        }
        sqlite3_finalize(stmt)
        guard found else { return nil }

        let content: Data
        if let objectID, !objectID.isEmpty {
            content = try readObject(objectID)
        } else if !legacy.isEmpty {
            content = legacy
        } else {
            // Index-only row: the entity bytes never left the locator, so read
            // them there and verify against the settled digest (fail closed).
            guard let locator = try rootLocatorPath(rootID),
                !relativePath.split(separator: "/").contains("..")
            else { return nil }
            let url = URL(fileURLWithPath: locator).appendingPathComponent(relativePath)
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
                NativeSHA256.hexDigest(data) == digest
            else { return nil }
            content = data
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
