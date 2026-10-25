import Foundation
import SQLite3

/// Authoritative ES/IS persistence for SimiGo, backed by the system SQLite3.
///
/// The database stores execution states, settled semantic results, their
/// bindings/dependencies, and *indexes* of external roots/files/sessions. It
/// never stores a second physical copy of an external work file or a model
/// weight — those live at their external locations and are referenced by
/// `root_id + relative path` (see `SimiGoPaths.RootReference`).
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
        /// The value the child's own IS carries (what a later admission recovers).
        public let nextInput: String
        /// Full lineage: the parent's prefix plus this child's own value. Written
        /// with the row so a reload cannot downgrade the lineage to an empty one.
        public let prefix: [String]

        public init(id: String, parentID: String, modelIdentity: String,
                    position: Int, continuationID: String, anchor: String,
                    createdAt: Date, nextInput: String, prefix: [String]) {
            self.id = id
            self.parentID = parentID
            self.modelIdentity = modelIdentity
            self.position = position
            self.continuationID = continuationID
            self.anchor = anchor
            self.createdAt = createdAt
            self.nextInput = nextInput
            self.prefix = prefix
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

    /// Insert a continuation's child ES with its FULL representation. Separate
    /// from `insertExecutionStateRow` on purpose: `recordExecutionState` mirrors a
    /// state the caller already owns and must not overwrite lineage columns it was
    /// never given, while a continuation child is authored here and must be
    /// durable exactly as the graph projects it.
    private func insertContinuationChildRow(_ child: ChildExecutionState) throws {
        let enc = JSONEncoder()
        let prefixJSON = String(
            data: (try? enc.encode(child.prefix)) ?? Data("[]".utf8),
            encoding: .utf8) ?? "[]"
        try execBinding("""
        INSERT INTO execution_states(state_id, parent_id, model_identity, position, continuation_id, anchor, lifecycle, created_at, next_input, prefix_json, checkpoint_ids_json)
        VALUES(?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(state_id) DO UPDATE SET
            parent_id=excluded.parent_id, model_identity=excluded.model_identity, position=excluded.position,
            continuation_id=excluded.continuation_id, anchor=excluded.anchor, lifecycle=excluded.lifecycle,
            created_at=excluded.created_at, next_input=excluded.next_input,
            prefix_json=excluded.prefix_json, checkpoint_ids_json=excluded.checkpoint_ids_json;
        """) { stmt in
            bind(stmt, 1, child.id)
            bind(stmt, 2, child.parentID)
            bind(stmt, 3, child.modelIdentity)
            bind(stmt, 4, Int64(child.position))
            bind(stmt, 5, child.continuationID)
            bind(stmt, 6, child.anchor)
            bind(stmt, 7, "active")
            bind(stmt, 8, Self.stamp(child.createdAt))
            bind(stmt, 9, child.nextInput)
            bind(stmt, 10, prefixJSON)
            bind(stmt, 11, "[]")
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
                try insertContinuationChildRow(childState)
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
        try execBinding("""
        INSERT INTO settlements(settlement_id, state_id, schema_version, payload, payload_digest, signature, contract_version, settled_at, validation_status)
        VALUES(?,?,?,?,?,?,?,?,?);
        """) { stmt in
            bind(stmt, 1, settlementID)
            bind(stmt, 2, stateID)
            bind(stmt, 3, settled.schemaVersion)
            bind(stmt, 4, settled.validatedPayload)
            bind(stmt, 5, settled.payloadDigest)
            bind(stmt, 6, String?.none)
            bind(stmt, 7, NativeResultContract.supportedVersion)
            bind(stmt, 8, Self.stamp(settled.settledAt))
            bind(stmt, 9, settled.trace.validationStatus)
        }
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
    // bytes. A "root" is an externally-owned directory (Hugging Face cache, a user
    // work folder, an agent-session store) tracked by root_id + relative path;
    // original work files stay where they are, with no second physical copy.

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
        try execBinding("""
        INSERT INTO settlement_bindings(settlement_id, name, value_digest, source_root_id, source_file_id)
        VALUES(?,?,'source',?,?);
        """) { stmt in
            bind(stmt, 1, settlementID)
            bind(stmt, 2, binding)
            bind(stmt, 3, rootID)
            bind(stmt, 4, fileID)
        }
    }

    /// Record that `fromSettlement` depends on `toSettlement`. Invalidating a
    /// depended-on settlement cascades to its (transitive) dependents.
    public func addDependency(fromSettlement: String, toSettlement: String,
                              kind: String = "depends") throws {
        try execBinding("INSERT INTO dependency_edges(from_settlement, to_settlement, kind) VALUES(?,?,?);") { stmt in
            bind(stmt, 1, fromSettlement)
            bind(stmt, 2, toSettlement)
            bind(stmt, 3, kind)
        }
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
            let now = Self.stamp(Date())
            for id in ids {
                try execBinding("UPDATE settlements SET validity='invalid', invalidated_at=? WHERE settlement_id=?;") { stmt in
                    bind(stmt, 1, now)
                    bind(stmt, 2, id)
                }
            }
        }
        return ids
    }

    /// Reconciliation for lost watcher events: mark indexed files under a root that
    /// were NOT observed in the latest scan as 'missing' and invalidate their
    /// dependency closures. Returns every settlement invalidated by the sweep.
    @discardableResult
    public func reconcileRoot(rootID: String, seenRelativePaths: Set<String>) throws -> [String] {
        let stmt = try prepare("SELECT relative_path FROM external_files WHERE root_id=?;")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, rootID)
        var indexed: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
            indexed.append(String(cString: c))
        }
        var invalidated: [String] = []
        for path in indexed where !seenRelativePaths.contains(path) {
            _ = try execBinding("UPDATE external_files SET status='missing' WHERE root_id=? AND relative_path=?;") { s in
                bind(s, 1, rootID); bind(s, 2, path)
            }
            invalidated += try invalidateSourceFile(rootID: rootID, relativePath: path)
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
            let now = Self.stamp(Date())
            for id in ids {
                try execBinding("UPDATE settlements SET validity='invalid', invalidated_at=? WHERE settlement_id=?;") { stmt in
                    bind(stmt, 1, now); bind(stmt, 2, id)
                }
            }
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
                try execBinding("""
                INSERT INTO settlements(settlement_id, state_id, schema_version, payload, payload_digest, signature, contract_version, settled_at, validation_status)
                VALUES(?,?,?,?,?,?,?,?,?);
                """) { stmt in
                    bind(stmt, 1, c.id.uuidString)
                    bind(stmt, 2, c.stateID)
                    bind(stmt, 3, doc.representationID)
                    bind(stmt, 4, canonical)
                    bind(stmt, 5, c.checksum)
                    bind(stmt, 6, String?.none)
                    bind(stmt, 7, doc.contractVersion)
                    bind(stmt, 8, Self.stamp( c.createdAt))
                    bind(stmt, 9, "MIGRATED_LEGACY")
                }
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
        SELECT settlement_id, state_id, schema_version, payload, payload_digest, settled_at
        FROM settlements
        WHERE validation_status IS NULL OR validation_status != 'MIGRATED_LEGACY'
        ORDER BY settled_at, settlement_id;
        """)
        defer { sqlite3_finalize(stmt) }
        func t(_ i: Int32) -> String { sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "" }
        var out: [SettlementReceiptRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let uuid = UUID(uuidString: t(0)) else { continue }
            let bytes = Int(sqlite3_column_bytes(stmt, 3))
            let payload: Data
            if let base = sqlite3_column_blob(stmt, 3), bytes > 0 {
                payload = Data(bytes: base, count: bytes)
            } else { payload = Data() }
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
