import Foundation
import SQLite3
import XCTest
@testable import SimiGoRuntimeContract

final class ESISDatabaseTests: XCTestCase {

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-esis-\(UUID().uuidString)-\(name).sqlite3")
    }
    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func legacyGraphJSON(contractVersion: String = "v1.0-amended", checkpointStateID: String = "S-0001") -> Data {
        let json = """
        {
          "contractVersion":"\(contractVersion)",
          "representationID":"R_Reference_v1",
          "states":[
            {"id":"S-0001","parentID":null,"modelIdentity":"reference-model","createdAt":700000000,
             "position":1,"continuationID":"C-1","nextInput":"hello","anchor":"a1","prefix":["hello"],
             "lifecycle":"saved","checkpointIDs":["11111111-1111-1111-1111-111111111111"]}
          ],
          "checkpoints":[
            {"id":"11111111-1111-1111-1111-111111111111","stateID":"\(checkpointStateID)","modelIdentity":"reference-model",
             "position":1,"continuationID":"C-1","nextInput":"hello","anchor":"a1","prefix":["hello"],
             "createdAt":700000000,"checksum":"sha256-abc"}
          ]
        }
        """
        return Data(json.utf8)
    }

    func testOpenResolvesParentSymlinkAliasButStillRejectsSymlinkedLeaf() throws {
        let fm = FileManager.default
        let realParent = fm.temporaryDirectory
            .appendingPathComponent("simigo-db-parent-\(UUID().uuidString)", isDirectory: true)
        let aliasParent = fm.temporaryDirectory
            .appendingPathComponent("simigo-db-parent-alias-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = aliasParent.appendingPathComponent("store.sqlite3")
        let targetURL = realParent.appendingPathComponent("target.sqlite3")
        let leafAlias = aliasParent.appendingPathComponent("leaf.sqlite3")
        defer {
            cleanup(databaseURL)
            cleanup(targetURL)
            cleanup(leafAlias)
            try? fm.removeItem(at: aliasParent)
            try? fm.removeItem(at: realParent)
        }

        try fm.createDirectory(at: realParent, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: aliasParent, withDestinationURL: realParent)

        let database = try ESISDatabase(url: databaseURL)
        try database.runMigrations()
        database.close()
        XCTAssertTrue(fm.fileExists(atPath: databaseURL.path),
                      "a parent alias must resolve to its real directory")

        let target = try ESISDatabase(url: targetURL)
        target.close()
        try fm.createSymbolicLink(at: leafAlias, withDestinationURL: targetURL)
        XCTAssertThrowsError(
            try ESISDatabase(url: leafAlias, createIfNeeded: false),
            "NOFOLLOW must still reject a symlink at the database leaf")
        XCTAssertTrue(fm.fileExists(atPath: targetURL.path),
                      "the symlink target must remain directly openable")
    }

    func testOpenRefusesSymlinkedDatabaseLeafWithoutTouchingTarget() throws {
        let target = tempURL("symlink-target")
        let alias = target.deletingLastPathComponent()
            .appendingPathComponent("symlink-alias.sqlite3")
        defer {
            cleanup(alias)
            cleanup(target)
        }

        do {
            let database = try ESISDatabase(url: target)
            try database.runMigrations()
        }
        try FileManager.default.createSymbolicLink(
            at: alias, withDestinationURL: target)

        XCTAssertThrowsError(
            try ESISDatabase(url: alias, createIfNeeded: false)
        ) { error in
            guard let databaseError = error as? ESISDatabase.DatabaseError,
                  case .cannotOpen = databaseError else {
                return XCTFail("expected symlinked database open to fail closed, got \(error)")
            }
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: alias.path))
        do {
            let direct = try ESISDatabase(url: target, createIfNeeded: false)
            XCTAssertTrue(try direct.integrityCheck())
        }
    }

    func testCloseIsIdempotentAcrossConcurrentCallsAndDeinit() throws {
        let url = tempURL("close-once")
        do {
            let db = try ESISDatabase(url: url)
            try db.runMigrations()
            DispatchQueue.concurrentPerform(iterations: 16) { _ in
                db.close()
            }
            db.close()
        }

        // The prior instance has deinitialized after the concurrent explicit
        // closes. Reopening must recover the same persisted database cleanly.
        let reopened = try ESISDatabase(url: url, createIfNeeded: false)
        defer { reopened.close(); cleanup(url) }
        try reopened.runMigrations()
        XCTAssertTrue(try reopened.integrityCheck())
    }

    func testStatementFailurePreservesPrimaryAndExtendedSQLiteCodes() throws {
        let url = tempURL("statement-error")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()

        try rawExec(url, """
        CREATE TRIGGER reject_execution_state_insert
        BEFORE INSERT ON execution_states
        BEGIN
            SELECT RAISE(ABORT, 'forced statement failure');
        END;
        """)

        XCTAssertThrowsError(
            try db.recordExecutionState(
                id: "forced-failure", parentID: nil, modelIdentity: "test-model",
                position: 0, continuationID: "C-1", anchor: "a",
                lifecycle: "active", createdAt: Date())
        ) { error in
            guard let databaseError = error as? ESISDatabase.DatabaseError,
                  case .executionFailure(let primary, let extended, _) = databaseError else {
                return XCTFail("expected preserved SQLite execution failure, got \(error)")
            }
            XCTAssertEqual(primary, SQLITE_CONSTRAINT)
            // SQLITE_CONSTRAINT_TRIGGER is not exported by every system SQLite module map.
            XCTAssertEqual(extended, SQLITE_CONSTRAINT | (7 << 8))
        }
        XCTAssertEqual(try db.count("execution_states"), 0)
    }

    func testIntegrityCheckExecutionFailurePreservesSQLiteCodes() throws {
        let url = tempURL("integrity-execution-failure")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()

        // The schema's SQL and integrity_check result exceed this deliberately
        // tiny value, forcing SQLite to report SQLITE_TOOBIG while executing
        // PRAGMA integrity_check rather than returning a corruption row.
        let previousLimit = db.setSQLiteLengthLimitForTesting(1)
        defer { _ = db.setSQLiteLengthLimitForTesting(previousLimit) }

        XCTAssertThrowsError(try db.integrityCheck()) { error in
            guard let databaseError = error as? ESISDatabase.DatabaseError,
                  case .executionFailure(let primary, let extended, let message) = databaseError
            else {
                return XCTFail("expected a typed integrity-check execution failure, got: \(error)")
            }
            XCTAssertEqual(primary, SQLITE_TOOBIG)
            XCTAssertEqual(extended, SQLITE_TOOBIG)
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testFreshDatabaseMigratesAndPassesIntegrity() throws {
        let url = tempURL("fresh")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        XCTAssertEqual(try db.schemaVersion(), 0)
        try db.runMigrations()
        XCTAssertEqual(try db.schemaVersion(), ESISDatabase.currentSchemaVersion)
        XCTAssertTrue(try db.integrityCheck())
        XCTAssertEqual(try db.count("chat_messages"), 0)
        XCTAssertEqual(try db.count("file_contents"), 0)
        XCTAssertEqual(try db.count("retrieval_settlements"), 0)
        // Idempotent: re-running does not error or double-apply.
        try db.runMigrations()
        XCTAssertEqual(try db.schemaVersion(), ESISDatabase.currentSchemaVersion)
    }

    func testBindFailurePreservesSQLiteCodesAndDoesNotCommit() throws {
        let url = tempURL("bind-failure")
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        let previousLimit = db.setSQLiteLengthLimitForTesting(64)
        defer {
            _ = db.setSQLiteLengthLimitForTesting(previousLimit)
            db.close()
            cleanup(url)
        }
        XCTAssertGreaterThan(previousLimit, 64)

        var captured: Error?
        XCTAssertThrowsError(try db.recordExecutionState(
            id: "bind-failure-state", parentID: nil,
            modelIdentity: String(repeating: "m", count: 256),
            position: 1, continuationID: "C-bind-failure", anchor: "a",
            lifecycle: "active", createdAt: Date()
        )) { captured = $0 }

        guard let databaseError = captured as? ESISDatabase.DatabaseError else {
            XCTFail("expected a typed SQLite execution failure, got: \(String(describing: captured))")
            return
        }
        guard case .executionFailure(let primary, let extended, _) = databaseError else {
            XCTFail("expected executionFailure, got: \(databaseError)")
            return
        }
        XCTAssertEqual(primary, SQLITE_TOOBIG)
        XCTAssertEqual(extended, SQLITE_TOOBIG)
        XCTAssertEqual(
            try db.count("execution_states"), 0,
            "a failed bind must not reach sqlite3_step or commit a row")
    }

    /// A database stamped v6 by the old out-of-order gates reports the head
    /// version while `chat_messages` and `file_contents` are absent. The v7
    /// repair pass must recreate them without touching existing rows.
    func testRepairsTablesSkippedByOutOfOrderGates() throws {
        let url = tempURL("repair")
        defer { cleanup(url) }
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        XCTAssertEqual(try db.schemaVersion(), ESISDatabase.currentSchemaVersion)
        db.close()

        try rawExec(url, """
        DROP TABLE file_contents;
        DROP TABLE chat_messages;
        DROP TABLE retrieval_settlements;
        DELETE FROM schema_migrations WHERE version >= 4;
        INSERT INTO schema_migrations(version, applied_at, checksum)
            VALUES(6, '2026-10-26T00:00:00Z', 'simigo-demand-retrieval-settlement-v6');
        """)

        let repaired = try ESISDatabase(url: url)
        defer { repaired.close() }
        XCTAssertEqual(try repaired.schemaVersion(), 6)
        try repaired.runMigrations()
        XCTAssertEqual(try repaired.schemaVersion(), ESISDatabase.currentSchemaVersion)
        XCTAssertEqual(try repaired.count("chat_messages"), 0)
        XCTAssertEqual(try repaired.count("file_contents"), 0)
        XCTAssertEqual(try repaired.count("retrieval_settlements"), 0)
        try repaired.runMigrations()
        XCTAssertEqual(try repaired.schemaVersion(), ESISDatabase.currentSchemaVersion)
    }

    /// A project note is a judgement, not a document: the new note becomes
    /// current by being the one nothing supersedes, and the old wording stays
    /// readable. Re-recording the same claim adds no pointer.
    func testProjectNotesSupersedeWithoutRewriting() throws {
        let url = tempURL("project-notes")
        defer { cleanup(url) }
        let db = try ESISDatabase(url: url)
        defer { db.close() }
        try db.runMigrations()

        let first = try db.recordProjectNote(kind: "brief", claim: "v1")
        XCTAssertTrue(first.created)
        XCTAssertNil(first.superseded)
        XCTAssertEqual(try db.currentProjectNote(kind: "brief")?.claim, "v1")

        let second = try db.recordProjectNote(kind: "brief", claim: "v2")
        XCTAssertEqual(second.superseded, first.note.noteID)
        XCTAssertEqual(try db.currentProjectNote(kind: "brief")?.claim, "v2")
        XCTAssertEqual(
            try db.projectNoteHistory(kind: "brief").map(\.claim), ["v2", "v1"],
            "the superseded note is still there, in time order")

        let again = try db.recordProjectNote(kind: "brief", claim: "v2")
        XCTAssertFalse(again.created, "an identical claim is already current")
        XCTAssertEqual(try db.projectNoteCount(kind: "brief"), 2)

        try db.recordProjectNote(kind: "status", claim: "open")
        XCTAssertEqual(
            try db.currentProjectNote(kind: "brief")?.claim, "v2",
            "superseding one kind leaves the others alone")
    }

    private func rawExec(_ url: URL, _ sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            sqlite3_close(handle)
            throw ESISDatabase.DatabaseError.cannotOpen(url.path)
        }
        defer { sqlite3_close(handle) }
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &message) == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(message)
            throw ESISDatabase.DatabaseError.sql(detail)
        }
    }

    private func rawText(_ url: URL, _ sql: String) throws -> String {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            sqlite3_close(handle)
            throw ESISDatabase.DatabaseError.cannotOpen(url.path)
        }
        defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ESISDatabase.DatabaseError.sql(sql)
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return "" }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
    }

    /// An existing v17 store must upgrade in place through v20: tokenizer
    /// identity remains NULL for historical states, graph ownership defaults
    /// to native-managed, and both migration rows land exactly once.
    func testV17UpgradeAddsTokenizerIdentityAndGraphOwnership() throws {
        let url = tempURL("v17-upgrade")
        defer { cleanup(url) }
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        try db.recordExecutionState(
            id: "legacy-state", parentID: nil, modelIdentity: "m",
            position: 1, continuationID: "C-1", anchor: "a1",
            lifecycle: "active", createdAt: Date())
        db.close()

        // Roll the store back to the exact v17 shape this change upgrades from.
        try rawExec(url, """
        ALTER TABLE execution_states DROP COLUMN graph_managed;
        ALTER TABLE execution_states DROP COLUMN tokenizer_identity;
        DELETE FROM schema_migrations WHERE version >= 18;
        """)

        let upgraded = try ESISDatabase(url: url, createIfNeeded: false)
        defer { upgraded.close() }
        XCTAssertEqual(try upgraded.schemaVersion(), 17)
        try upgraded.runMigrations()
        XCTAssertEqual(try upgraded.schemaVersion(), ESISDatabase.currentSchemaVersion)
        XCTAssertNil(
            try upgraded.executionStateTokenizerIdentity("legacy-state"),
            "a pre-v18 state carries no claim and must keep failing closed")
        XCTAssertEqual(
            try rawText(url, "SELECT graph_managed FROM execution_states WHERE state_id='legacy-state';"),
            "1", "legacy rows default to native graph ownership")
        // One migration row per version from 18 to the declared head — derived,
        // so adding a migration does not turn this into a stale literal.
        XCTAssertEqual(
            try rawText(url, "SELECT COUNT(*) FROM schema_migrations WHERE version >= 18;"),
            "\(ESISDatabase.currentSchemaVersion - 17)")
    }

    /// v23 把结算行上的 validity 三列拆进只追加的事件账本。已经在 v22 库里
    /// 失效过的行必须带着原因迁过去，而不是被当成“从未失效”；行上也不再
    /// 保留第二份 validity。
    func testV23MovesRowValidityIntoAppendOnlyLedger() throws {
        let url = tempURL("v23-validity-ledger")
        defer { cleanup(url) }
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        let id = UUID().uuidString
        try rawExec(url, """
        INSERT INTO settlements(settlement_id, state_id, schema_version, payload,
            payload_digest, signature, contract_version, settled_at, validation_status)
        VALUES('\(id)', NULL, 's', X'', 'd', NULL, 'c', '2026-01-01T00:00:00Z', 'MODEL');
        """)
        db.close()

        // 回到 v22 的形状：三列在行上，账本不存在。
        try rawExec(url, """
        DROP VIEW settlement_current_validity;
        DROP TABLE settlement_validity_events;
        ALTER TABLE settlements ADD COLUMN validity TEXT NOT NULL DEFAULT 'valid';
        ALTER TABLE settlements ADD COLUMN invalidated_at TEXT;
        ALTER TABLE settlements ADD COLUMN invalidated_cause TEXT;
        UPDATE settlements SET validity='invalid',
               invalidated_at='2026-01-02T00:00:00Z',
               invalidated_cause='source-changed:work'
         WHERE settlement_id='\(id)';
        DELETE FROM schema_migrations WHERE version >= 23;
        """)

        let upgraded = try ESISDatabase(url: url, createIfNeeded: false)
        defer { upgraded.close() }
        XCTAssertEqual(try upgraded.schemaVersion(), 22)
        try upgraded.runMigrations()
        XCTAssertEqual(try upgraded.schemaVersion(), ESISDatabase.currentSchemaVersion)

        XCTAssertEqual(try upgraded.settlementValidity(id), "invalid")
        XCTAssertEqual(try rawText(url, """
        SELECT cause FROM settlement_validity_events
         WHERE settlement_id='\(id)' AND validity='invalid';
        """), "source-changed:work")
        XCTAssertEqual(try rawText(url, """
        SELECT COUNT(*) FROM pragma_table_info('settlements')
         WHERE name IN ('validity','invalidated_at','invalidated_cause');
        """), "0", "the row keeps no second copy of the validity axis")
    }

    /// Re-running the v19 migration — including after reopening the store —
    /// must not duplicate version rows or re-add either column.
    func testV19MigrationIsIdempotentAcrossReopens() throws {
        let url = tempURL("v18-idempotent")
        defer { cleanup(url) }
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        try db.runMigrations()
        db.close()

        let reopened = try ESISDatabase(url: url, createIfNeeded: false)
        try reopened.runMigrations()
        XCTAssertEqual(try reopened.schemaVersion(), ESISDatabase.currentSchemaVersion)
        reopened.close()

        XCTAssertEqual(
            try rawText(url, "SELECT COUNT(*) FROM schema_migrations WHERE version = 19;"), "1")
        XCTAssertEqual(
            try rawText(url, """
            SELECT COUNT(*) FROM pragma_table_info('execution_states')
            WHERE name IN ('tokenizer_identity', 'graph_managed');
            """), "2")
    }

    /// The tokenizer is fixed by the insert that creates the state. A later
    /// upsert may refresh other fields but must not replace a recorded
    /// tokenizer, even with another non-empty value.
    func testExistingTokenizerIdentityCannotBeOverwrittenByUpsert() throws {
        let url = tempURL("tokenizer-immutable")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        try db.recordExecutionState(
            id: "tokenizer-state", parentID: nil, modelIdentity: "m",
            tokenizerIdentity: "tokenizer-a", position: 0,
            continuationID: "C-1", anchor: "a1",
            lifecycle: "active", createdAt: Date())
        try db.recordExecutionState(
            id: "tokenizer-state", parentID: nil, modelIdentity: "m",
            tokenizerIdentity: "tokenizer-b", position: 1,
            continuationID: "C-2", anchor: "a2",
            lifecycle: "active", createdAt: Date())
        XCTAssertEqual(
            try db.executionStateTokenizerIdentity("tokenizer-state"), "tokenizer-a")
        XCTAssertEqual(
            try db.executionStatePosition("tokenizer-state"), 1,
            "the conflict update must still refresh non-identity fields")
    }

    /// A legacy row whose tokenizer is NULL must stay unbound: a later write
    /// cannot turn an unverifiable state into an apparently verified one.
    func testLegacyNullTokenizerIdentityIsNotBackfilledByUpsert() throws {
        let url = tempURL("tokenizer-null")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        try db.recordExecutionState(
            id: "legacy-null", parentID: nil, modelIdentity: "m",
            position: 0, continuationID: "C-1", anchor: "a1",
            lifecycle: "active", createdAt: Date())
        XCTAssertNil(try db.executionStateTokenizerIdentity("legacy-null"))
        try db.recordExecutionState(
            id: "legacy-null", parentID: nil, modelIdentity: "m",
            tokenizerIdentity: "caller-asserted", position: 1,
            continuationID: "C-2", anchor: "a2",
            lifecycle: "active", createdAt: Date())
        XCTAssertNil(
            try db.executionStateTokenizerIdentity("legacy-null"),
            "a NULL begin-time tokenizer is not a slot to backfill")
        XCTAssertEqual(
            try db.executionStatePosition("legacy-null"), 1,
            "the conflict update must still refresh non-identity fields")
    }

    func testLegacyImportWithReadBackAndReceipt() throws {
        let url = tempURL("import")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        let outcome = try db.importLegacyGraph(jsonData: legacyGraphJSON(), sourceLabel: "reference-graph-v1.json")
        XCTAssertEqual(outcome.statesImported, 1)
        XCTAssertEqual(outcome.settlementsImported, 1)
        XCTAssertEqual(try db.count("execution_states"), 1)
        XCTAssertEqual(try db.count("settlements"), 1)
        XCTAssertEqual(try db.count("migration_receipts"), 1)
    }

    /// A validated legacy import must be LOSS-FREE: rebuilding the graph from
    /// SQLite alone (the read authority used after JSON retirement) reproduces
    /// the full representation — nextInput, prefix, checkpoint links — not just
    /// the eight legacy columns. This is what makes retire-after-verify safe.
    func testLegacyImportIsLosslessForGraphRebuild() throws {
        let url = tempURL("import-lossless")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        _ = try db.importLegacyGraph(jsonData: legacyGraphJSON(), sourceLabel: "reference-graph-v1.json")
        XCTAssertEqual(try db.count("checkpoints"), 1)

        let g = try db.readGraph()
        XCTAssertEqual(g.states.count, 1)
        let st = g.states[0]
        XCTAssertEqual(st.id, "S-0001")
        XCTAssertEqual(st.nextInput, "hello")
        XCTAssertEqual(st.prefix, ["hello"])                                  // representation survived
        XCTAssertEqual(st.checkpointIDs, [UUID(uuidString: "11111111-1111-1111-1111-111111111111")!])
        XCTAssertEqual(st.lifecycle, "saved")
        XCTAssertEqual(g.checkpoints.count, 1)
        XCTAssertEqual(g.checkpoints[0].prefix, ["hello"])
        XCTAssertEqual(g.checkpoints[0].checksum, "sha256-abc")
        XCTAssertTrue(try db.integrityCheck())
    }

    func testContractVersionMismatchRollsBackEntirely() throws {
        let url = tempURL("ver")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        XCTAssertThrowsError(try db.importLegacyGraph(jsonData: legacyGraphJSON(contractVersion: "v9.9"), sourceLabel: "bad.json")) { e in
            XCTAssertEqual(e as? ESISDatabase.DatabaseError,
                           .contractVersionMismatch("v9.9"))
        }
        // No half-written authority survives the rollback.
        XCTAssertEqual(try db.count("execution_states"), 0)
        XCTAssertEqual(try db.count("settlements"), 0)
    }

    func testForeignKeyViolationRollsBackEntirely() throws {
        let url = tempURL("fk")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        // checkpoint references a state id that does not exist → FK violation → rollback.
        XCTAssertThrowsError(try db.importLegacyGraph(jsonData: legacyGraphJSON(checkpointStateID: "S-MISSING"), sourceLabel: "fk.json"))
        XCTAssertEqual(try db.count("execution_states"), 0)
        XCTAssertEqual(try db.count("settlements"), 0)
    }

    func testCorruptFileFailsClosed() throws {
        let url = tempURL("corrupt")
        try Data("this is definitely not a sqlite database file".utf8).write(to: url)
        defer { cleanup(url) }
        XCTAssertThrowsError(try ESISDatabase(url: url)) { e in
            guard case ESISDatabase.DatabaseError.notADatabase = e as! ESISDatabase.DatabaseError else {
                return XCTFail("expected notADatabase, got \(e)")
            }
        }
    }
}

extension ESISDatabaseTests {
    func testRecordNativeSettlementAsWriteAuthority() throws {
        let url = tempURL("native-settle")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        try db.recordExecutionState(id: "S-0001", parentID: nil, modelIdentity: "m", position: 1, continuationID: "C-1", anchor: "a1", lifecycle: "saved", createdAt: Date())
        let route = #"{"schema_version":"simigo.result-contract/v1","fields":{"secret":{"pattern":"^SECRET=(.+)$","type":"string"}},"constraints":[{"kind":"digest_equals_binding","field":"secret","binding":"secret_commitment"}]}"#
        let settled = try SettlementAuthority.authorize(
            generatedText: "SECRET=NORTH>EAST", contractJSON: Data(route.utf8),
            verifiedBindings: ["secret_commitment": .string("2b1a5d9f0a1183c966ce8325a252424579a625c1b2314654dd6aaebaf9c334a8")]
        )
        let id = try db.recordNativeSettlement(settled, stateID: "S-0001")
        XCTAssertFalse(id.isEmpty)
        XCTAssertEqual(try db.count("settlements"), 1)
        XCTAssertEqual(try db.count("settlement_bindings"), 1)
        XCTAssertTrue(try db.integrityCheck())
    }

    /// Mirrors the app's `settleProducerResult` production sequence end to end in a
    /// runnable package test: the native gate authorizes a result that commits to an
    /// IS binding, the validated payload is recorded as the authoritative write, then
    /// read back. A non-committing producer text must refuse BEFORE any write, so the
    /// settlement count stays unchanged (fail-closed — no partially settled record).
    func testSettlementGateCommitsToAuthorityAndFailsClosedOnReadBack() throws {
        let url = tempURL("gate-authority")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        try db.recordExecutionState(id: "S-GATE", parentID: nil, modelIdentity: "reference-model",
                                    position: 1, continuationID: "C-1", anchor: "a1",
                                    lifecycle: "active", createdAt: Date())

        // Same contract the production UI installs: a RESULT= field bound via
        // equals_binding to the state's IS next-input value.
        let contract = #"{"schema_version":"simigo.result-contract/v1","fields":{"content":{"pattern":"^RESULT=(.+)$","capture_group":1,"type":"string","normalize":"trim","nonempty":true}},"constraints":[{"kind":"equals_binding","field":"content","binding":"next_input"}]}"#
        let isNextInput = "shared"
        let bindings: [String: NativeContractValue] = ["next_input": .string(isNextInput)]

        // Fail-closed first: a producer result that does NOT commit must refuse and
        // write nothing.
        XCTAssertThrowsError(try SettlementAuthority.authorize(
            generatedText: "RESULT=tampered", contractJSON: Data(contract.utf8), verifiedBindings: bindings
        )) { e in
            XCTAssertEqual((e as? NativeResultContractError)?.code, "PRODUCER_RESULT_BINDING_MISMATCH")
        }
        XCTAssertEqual(try db.count("settlements"), 0, "refusal must not write any settlement")

        // Authorized path: commit to the authoritative store, then read it back.
        let settled = try SettlementAuthority.authorize(
            generatedText: "RESULT=\(isNextInput)", contractJSON: Data(contract.utf8), verifiedBindings: bindings
        )
        XCTAssertEqual(settled.trace.validationStatus, "VALID")
        _ = try db.recordNativeSettlement(settled, stateID: "S-GATE")
        XCTAssertEqual(try db.count("settlements"), 1)

        let receipts = try db.readSettlementReceipts()
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts.first?.stateID, "S-GATE")
        XCTAssertEqual(receipts.first?.payloadDigest, settled.payloadDigest)
        let decoded = try JSONDecoder().decode([String: NativeContractValue].self, from: receipts[0].payload)
        XCTAssertEqual(decoded["content"], .string(isNextInput))
        XCTAssertTrue(try db.integrityCheck())
    }

    // MARK: - ES authoritative graph round-trip (v2 read/write authority)

    func testWriteGraphThenReadBackPreservesFullRepresentation() throws {
        let url = tempURL("roundtrip")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        let cpID = UUID()
        let state = ESISDatabase.GraphState(
            id: "S-0001", parentID: nil, modelIdentity: "reference-model",
            createdAt: Date(timeIntervalSince1970: 700000000), position: 2,
            continuationID: "C-1", nextInput: "east", anchor: "a1",
            prefix: ["hello", "east"], lifecycle: "active", checkpointIDs: [cpID])
        let cp = ESISDatabase.GraphCheckpoint(
            id: cpID, stateID: "S-0001", modelIdentity: "reference-model", position: 1,
            continuationID: "C-1", nextInput: "hello", anchor: "a0",
            prefix: ["hello"], createdAt: Date(timeIntervalSince1970: 700000001), checksum: "sha-abc")
        try db.writeGraph(states: [state], checkpoints: [cp])

        let back = try db.readGraph()
        XCTAssertEqual(back.states.count, 1)
        let r = back.states[0]
        XCTAssertEqual(r.id, "S-0001")
        XCTAssertNil(r.parentID)
        XCTAssertEqual(r.position, 2)
        XCTAssertEqual(r.nextInput, "east")
        XCTAssertEqual(r.prefix, ["hello", "east"])   // representation preserved
        XCTAssertEqual(r.checkpointIDs, [cpID])
        XCTAssertEqual(r.lifecycle, "active")
        XCTAssertEqual(back.checkpoints.count, 1)
        XCTAssertEqual(back.checkpoints[0].prefix, ["hello"])
        XCTAssertEqual(back.checkpoints[0].checksum, "sha-abc")
        XCTAssertTrue(try db.hasExecutionStates())
    }

    func testWriteGraphIdempotentAndReconcilesRemovals() throws {
        let url = tempURL("reconcile")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        func st(_ id: String) -> ESISDatabase.GraphState {
            ESISDatabase.GraphState(id: id, parentID: nil, modelIdentity: "m",
                createdAt: Date(timeIntervalSince1970: 700000000), position: 0,
                continuationID: "C", nextInput: "", anchor: "a", prefix: [], lifecycle: "active", checkpointIDs: [])
        }
        try db.writeGraph(states: [st("A"), st("B")], checkpoints: [])
        XCTAssertEqual(try db.count("execution_states"), 2)
        // Re-write same set: no duplication.
        try db.writeGraph(states: [st("A"), st("B")], checkpoints: [])
        XCTAssertEqual(try db.count("execution_states"), 2)
        // Now only A remains in the live graph → B is removed (nothing references it).
        try db.writeGraph(states: [st("A")], checkpoints: [])
        XCTAssertEqual(try db.count("execution_states"), 1)
        XCTAssertEqual(try db.readGraph().states.map { $0.id }, ["A"])
    }

    func testWriteGraphKeepsStatesReferencedBySettlements() throws {
        let url = tempURL("protect-is")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        func st(_ id: String) -> ESISDatabase.GraphState {
            ESISDatabase.GraphState(id: id, parentID: nil, modelIdentity: "m",
                createdAt: Date(timeIntervalSince1970: 700000000), position: 0,
                continuationID: "C", nextInput: "", anchor: "a", prefix: [], lifecycle: "active", checkpointIDs: [])
        }
        try db.writeGraph(states: [st("A"), st("B")], checkpoints: [])
        // B has an authoritative settlement; removing it from the live graph must NOT
        // cascade-delete it, so the IS record stays resolvable.
        try db.recordExecutionState(id: "B", parentID: nil, modelIdentity: "m", position: 0,
                                    continuationID: "C", anchor: "a", lifecycle: "saved", createdAt: Date())
        let route = #"{"schema_version":"simigo.result-contract/v1","fields":{"secret":{"pattern":"^SECRET=(.+)$","type":"string"}},"constraints":[{"kind":"digest_equals_binding","field":"secret","binding":"secret_commitment"}]}"#
        let settled = try SettlementAuthority.authorize(
            generatedText: "SECRET=NORTH>EAST", contractJSON: Data(route.utf8),
            verifiedBindings: ["secret_commitment": .string("2b1a5d9f0a1183c966ce8325a252424579a625c1b2314654dd6aaebaf9c334a8")])
        _ = try db.recordNativeSettlement(settled, stateID: "B")
        try db.writeGraph(states: [st("A")], checkpoints: [])   // drop B from live graph
        XCTAssertEqual(try db.count("settlements"), 1)          // settlement survives
        XCTAssertTrue(try db.readGraph().states.contains { $0.id == "B" })  // B kept (referenced)
    }
}

extension ESISDatabaseTests {

    private func settleSource(_ db: ESISDatabase, stateID: String) throws -> String {
        try db.recordExecutionState(
            id: stateID, parentID: nil, modelIdentity: "reference-model",
            position: 1, continuationID: "C-1", anchor: "a1",
            lifecycle: "saved", createdAt: Date())
        let route = #"{"schema_version":"simigo.result-contract/v1","fields":{"secret":{"pattern":"^SECRET=(.+)$","type":"string"}},"constraints":[{"kind":"digest_equals_binding","field":"secret","binding":"secret_commitment"}]}"#
        let settled = try SettlementAuthority.authorize(
            generatedText: "SECRET=NORTH>EAST", contractJSON: Data(route.utf8),
            verifiedBindings: ["secret_commitment": .string("2b1a5d9f0a1183c966ce8325a252424579a625c1b2314654dd6aaebaf9c334a8")])
        return try db.recordNativeSettlement(settled, stateID: stateID)
    }

    /// Serving an already-settled answer must be verifiable from the database
    /// alone, not from trace text: the reuse row carries `model_calls=0`, the
    /// source settlement it consumed, and the digest of the exact lookup key.
    func testAnswerReuseIsRecordedAsZeroModelCallRow() throws {
        let url = tempURL("reuse-row")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        let source = try settleSource(db, stateID: "S-SRC")

        let stamped = try db.recordInformationReuse(
            sourceSettlementID: source, sourceStateID: "S-SRC",
            demandID: "D-1", sessionID: "info-a", query: "where is the exit",
            reusedAt: Date(timeIntervalSince1970: 700000010))

        let back = try XCTUnwrap(try db.informationReuseEvent(demandID: "D-1"))
        XCTAssertEqual(back, stamped)
        XCTAssertEqual(back.sourceSettlementID, source)
        XCTAssertEqual(back.sourceStateID, "S-SRC")
        XCTAssertEqual(back.sessionID, "info-a")
        XCTAssertEqual(back.modelCalls, 0)
        XCTAssertNil(back.consumerStateID, "a reuse creates no consumer ES state")
        XCTAssertEqual(
            back.canonicalDigest,
            NativeSHA256.hexDigest(Data("info-a|where is the exit".utf8)))
        XCTAssertEqual(try db.count("information_reuse_events"), 1)
        XCTAssertEqual(try db.count("settlements"), 1, "reuse reads the source, never rewrites it")
    }

    /// The demand id is content-addressed, so a repeated identical question is
    /// one consumption edge, not one row per request.
    func testAnswerReuseIsIdempotentPerDemand() throws {
        let url = tempURL("reuse-idem")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        let source = try settleSource(db, stateID: "S-SRC")

        let first = try db.recordInformationReuse(
            sourceSettlementID: source, sourceStateID: "S-SRC",
            demandID: "D-1", sessionID: "info-a", query: "q")
        let second = try db.recordInformationReuse(
            sourceSettlementID: source, sourceStateID: "S-SRC",
            demandID: "D-1", sessionID: "info-a", query: "q")

        XCTAssertEqual(second, first)
        XCTAssertEqual(try db.count("information_reuse_events"), 1)
    }

    /// Fail-closed: a settlement invalidated after the lookup gate ran can never
    /// be recorded as reused, and a refusal writes nothing.
    func testAnswerReuseRefusesInvalidSource() throws {
        let url = tempURL("reuse-invalid")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        let source = try settleSource(db, stateID: "S-SRC")
        _ = try db.invalidateSettlement(source)

        XCTAssertThrowsError(try db.recordInformationReuse(
            sourceSettlementID: source, sourceStateID: "S-SRC",
            demandID: "D-1", sessionID: "info-a", query: "q"
        )) { e in
            XCTAssertEqual(
                e as? ESISDatabase.InformationReuseError, .sourceNotValid(source))
        }
        XCTAssertEqual(try db.count("information_reuse_events"), 0)

        XCTAssertThrowsError(try db.recordInformationReuse(
            sourceSettlementID: source, sourceStateID: "S-SRC",
            demandID: "", sessionID: "info-a", query: "q"
        )) { e in
            XCTAssertEqual(
                e as? ESISDatabase.InformationReuseError, .emptyField("demand_id"))
        }
    }
}

// MARK: - #223-A regression: init-time lock contention is an execution
// condition, never a corruption diagnostic

extension ESISDatabaseTests {

    /// Races two real `ESISDatabase` opens on a closed WAL carrier.
    /// The first opener after "all connections closed" performs WAL recovery;
    /// a concurrent opener contends on that recovery and — without a busy
    /// handler — `PRAGMA integrity_check` fails with SQLITE_BUSY. The old
    /// init path misclassified that as `notADatabase` ("integrity_check
    /// failed"), a corruption diagnostic. Lock contention is an execution
    /// condition: every open must either succeed (busy handler waits) or
    /// surface a classified execution failure that preserves the SQLite
    /// result codes — never a code-less corruption verdict.
    func testInitUnderConcurrentReopenNeverMisclassifiesLockContention() throws {
        let url = tempURL("concurrent-reopen")
        defer { cleanup(url) }
        // Seed through the real init path so the file is a genuine WAL
        // carrier, then close every connection.
        do {
            let seed = try ESISDatabase(url: url)
            try seed.runMigrations()
            seed.close()
        }

        let outcomeLock = NSLock()
        var outcomes: [Result<ESISDatabase, Error>] = []
        var misclassifiedRounds = 0

        for round in 0..<40 {
            outcomes.removeAll(keepingCapacity: true)
            let gate = DispatchSemaphore(value: 0)
            let workers = DispatchGroup()
            for _ in 0..<2 {
                workers.enter()
                DispatchQueue.global().async {
                    gate.wait()
                    defer { workers.leave() }
                    do {
                        let db = try ESISDatabase(url: url, createIfNeeded: false)
                        outcomeLock.lock()
                        outcomes.append(.success(db))
                        outcomeLock.unlock()
                    } catch {
                        outcomeLock.lock()
                        outcomes.append(.failure(error))
                        outcomeLock.unlock()
                    }
                }
            }
            gate.signal()
            gate.signal()
            workers.wait()

            for outcome in outcomes {
                switch outcome {
                case .success(let db):
                    db.close()
                case .failure(let error):
                    guard let dbError = error as? ESISDatabase.DatabaseError else {
                        XCTFail("round \(round): unexpected error type: \(error)")
                        return
                    }
                    switch dbError {
                    case .notADatabase(let detail):
                        misclassifiedRounds += 1
                        if misclassifiedRounds == 1 {
                            XCTFail(
                                "round \(round): lock contention misclassified as corruption: \(detail)")
                        }
                    case .executionFailure(let primary, let extended, let message):
                        // Classified execution failure: the primary and
                        // extended SQLite result codes must be preserved.
                        XCTAssertTrue(
                            primary == SQLITE_BUSY || primary == SQLITE_LOCKED,
                            "round \(round): unexpected primary code \(primary) "
                                + "(extended \(extended)): \(message)")
                        XCTAssertNotEqual(
                            extended, 0,
                            "round \(round): extended result code lost: \(message)")
                    default:
                        XCTFail("round \(round): unexpected DatabaseError: \(dbError)")
                        return
                    }
                }
            }
        }
        XCTAssertEqual(
            misclassifiedRounds, 0,
            "\(misclassifiedRounds) of 40 rounds misclassified lock contention as corruption")

        // The carrier is still fully usable afterwards.
        let final = try ESISDatabase(url: url, createIfNeeded: false)
        XCTAssertTrue(try final.integrityCheck())
        final.close()
    }

    /// Captures the ACTUAL SQLite result codes through the real init path:
    /// a rollback-mode database held by an exclusive writer forces the init
    /// `integrity_check` to contend. The busy handler waits (observable as
    /// elapsed time — the wait/retry policy) and the surfaced failure must
    /// carry primary == SQLITE_BUSY with the extended code SQLite actually
    /// reports for this busy-timeout path (SQLITE_BUSY on this platform —
    /// see the assertion comment), never a code-less corruption verdict.
    func testInitBusyFailureCarriesPrimaryAndExtendedResultCodes() throws {
        let url = tempURL("busy-codes")
        defer { cleanup(url) }

        var blocker: OpaquePointer?
        guard sqlite3_open(url.path, &blocker) == SQLITE_OK, let blocker else {
            XCTFail("could not open blocker connection")
            return
        }
        defer {
            sqlite3_exec(blocker, "ROLLBACK;", nil, nil, nil)
            sqlite3_close(blocker)
        }
        func blockerExec(_ sql: String) throws {
            var message: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(blocker, sql, nil, nil, &message) == SQLITE_OK else {
                let detail = message.map { String(cString: $0) } ?? "unknown error"
                sqlite3_free(message)
                throw ESISDatabase.DatabaseError.sql(detail)
            }
        }
        try blockerExec("PRAGMA journal_mode = DELETE;")
        try blockerExec("CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT);")
        try blockerExec("BEGIN EXCLUSIVE;")
        try blockerExec("INSERT INTO t(v) VALUES('held');")

        let start = Date()
        do {
            _ = try ESISDatabase(url: url, createIfNeeded: false)
            XCTFail("init should have failed while an exclusive writer held the database")
        } catch let error as ESISDatabase.DatabaseError {
            guard case .executionFailure(let primary, let extended, let message) = error else {
                XCTFail("expected a classified execution failure with codes, got \(error)")
                return
            }
            XCTAssertEqual(primary, SQLITE_BUSY, "primary code: \(message)")
            // Ground truth on this platform (system SQLite 3.54.0, probed
            // 2026-11-01 with raw sqlite3 on both the prepare and the step
            // path): a busy-timeout failure reports extended == primary ==
            // SQLITE_BUSY, not SQLITE_BUSY_TIMEOUT (773). The contract is
            // verbatim pass-through of sqlite3_extended_errcode; this pin
            // captures the actually-reported code, so a future SQLite that
            // starts reporting 773 here fails loudly and the capture above
            // must be re-verified.
            XCTAssertEqual(
                extended, SQLITE_BUSY,
                "extended code must match the platform capture (SQLITE_BUSY on "
                    + "this system SQLite), got \(extended) (\(message))")
            // The busy handler actually waited before giving up (the
            // wait/retry policy), instead of failing instantly.
            let elapsed = Date().timeIntervalSince(start)
            XCTAssertGreaterThanOrEqual(
                elapsed, 4.0, "busy handler did not wait (elapsed \(elapsed)s)")
            XCTAssertLessThan(
                elapsed, 15.0, "busy wait exceeded expectations (elapsed \(elapsed)s)")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testReadGraphRejectsMalformedAuthoritativePrefixJSON() throws {
        let url = tempURL("malformed-graph")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()

        let state = ESISDatabase.GraphState(
            id: "malformed-state", parentID: nil, modelIdentity: "test-model",
            createdAt: Date(timeIntervalSince1970: 700000000), position: 1,
            continuationID: "C-1", nextInput: "continue", anchor: "a1",
            prefix: ["complete-prefix"], lifecycle: "active", checkpointIDs: [])
        try db.writeGraph(states: [state], checkpoints: [])

        var writer: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &writer), SQLITE_OK)
        guard let writer else {
            XCTFail("could not open SQLite corruption-test connection")
            return
        }
        defer { sqlite3_close(writer) }
        XCTAssertEqual(
            sqlite3_exec(
                writer,
                "UPDATE execution_states SET prefix_json='not-json' WHERE state_id='malformed-state';",
                nil, nil, nil),
            SQLITE_OK)

        XCTAssertThrowsError(try db.readGraph())
    }


    func testReadGraphRejectsEmptyAuthoritativeGraphJSON() throws {
        let url = tempURL("empty-graph-json")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()

        let state = ESISDatabase.GraphState(
            id: "empty-json-state", parentID: nil, modelIdentity: "test-model",
            createdAt: Date(timeIntervalSince1970: 700000000), position: 1,
            continuationID: "C-1", nextInput: "continue", anchor: "a1",
            prefix: ["complete-prefix"], lifecycle: "active", checkpointIDs: [])
        try db.writeGraph(states: [state], checkpoints: [])

        // Empty TEXT is not a valid serialized empty collection. Treating it
        // as [] would silently turn corrupt authoritative state into a graph.
        try rawExec(url, "UPDATE execution_states SET prefix_json='' WHERE state_id='empty-json-state';")
        XCTAssertThrowsError(try db.readGraph(), "empty prefix_json must be corruption")

        try rawExec(url, "UPDATE execution_states SET prefix_json='[\"complete-prefix\"]', checkpoint_ids_json='' WHERE state_id='empty-json-state';")
        XCTAssertThrowsError(try db.readGraph(), "empty checkpoint_ids_json must be corruption")
    }
    func testInformationDemandCacheIdentityIncludesResultLimit() throws {
        let databaseURL = tempURL("demand-limit")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-demand-limit-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: rootURL) }

        try Data("needle first\n".utf8)
            .write(to: rootURL.appendingPathComponent("a.txt"))
        try Data("needle second\n".utf8)
            .write(to: rootURL.appendingPathComponent("b.txt"))

        let db = try ESISDatabase(url: databaseURL)
        defer { db.close(); cleanup(databaseURL) }
        try db.runMigrations()
        _ = try db.settleWorkRootContents(rootID: "limit-root", rootURL: rootURL)

        let one = try db.executeInformationDemand(
            query: "needle", rootID: "limit-root", limit: 1)
        XCTAssertEqual(one.hits.count, 1)
        XCTAssertFalse(one.reused)

        let two = try db.executeInformationDemand(
            query: "needle", rootID: "limit-root", limit: 2)
        XCTAssertEqual(two.hits.count, 2)
        XCTAssertNotEqual(two.demandID, one.demandID)
        XCTAssertFalse(two.reused)

        let twoAgain = try db.executeInformationDemand(
            query: "needle", rootID: "limit-root", limit: 2)
        XCTAssertTrue(twoAgain.reused)
        XCTAssertEqual(twoAgain.hits, two.hits)
    }

    func testInformationDemandCacheIdentityIncludesRequestedRootScope() throws {
        let databaseURL = tempURL("demand-root-scope")
        let rootA = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-demand-root-a-\(UUID().uuidString)", isDirectory: true)
        let rootB = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-demand-root-b-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: rootA, withIntermediateDirectories: true)
        try fm.createDirectory(at: rootB, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: rootA)
            try? fm.removeItem(at: rootB)
        }

        // Binary files create filename-index rows but no settled text-content rows.
        try Data([0xFF, 0xFE]).write(to: rootA.appendingPathComponent("needle-alpha.bin"))
        try Data([0xFF, 0xFE]).write(to: rootB.appendingPathComponent("needle-beta.bin"))

        let db = try ESISDatabase(url: databaseURL)
        defer { db.close(); cleanup(databaseURL) }
        try db.runMigrations()
        _ = try db.settleWorkRootContents(rootID: "root-a", rootURL: rootA)
        _ = try db.settleWorkRootContents(rootID: "root-b", rootURL: rootB)

        let a = try db.executeInformationDemand(
            query: "needle", rootID: "root-a", limit: 10)
        XCTAssertEqual(a.hits.map(\.relativePath), ["needle-alpha.bin"])

        let b = try db.executeInformationDemand(
            query: "needle", rootID: "root-b", limit: 10)
        XCTAssertEqual(b.hits.map(\.relativePath), ["needle-beta.bin"])
        XCTAssertNotEqual(a.demandID, b.demandID)
        XCTAssertFalse(b.reused)
    }

    func testRootSettlementMarksRemovedNonTextFilesMissing() throws {
        let databaseURL = tempURL("missing-nontext")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-missing-nontext-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileURL = rootURL.appendingPathComponent("binary.dat")
        try Data([0xFF, 0xFE]).write(to: fileURL)
        defer { try? fm.removeItem(at: rootURL) }

        let db = try ESISDatabase(url: databaseURL)
        defer { db.close(); cleanup(databaseURL) }
        try db.runMigrations()

        _ = try db.settleWorkRootContents(rootID: "nontext-root", rootURL: rootURL)
        let present = try db.listExternalFiles(rootID: "nontext-root")
        XCTAssertEqual(present.first(where: { $0.relativePath == "binary.dat" })?.status, "present")
        XCTAssertEqual(try db.count("file_contents"), 0)

        try fm.removeItem(at: fileURL)
        let report = try db.settleWorkRootContents(rootID: "nontext-root", rootURL: rootURL)
        XCTAssertEqual(report.removed, 1)
        let afterRemoval = try db.listExternalFiles(rootID: "nontext-root")
        XCTAssertEqual(
            afterRemoval.first(where: { $0.relativePath == "binary.dat" })?.status,
            "missing")
    }

    func testRegisteredRootRefusesRootDirectoryReplacementWithSymlink() throws {
        let databaseURL = tempURL("symlink-root-replacement")
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-root-replacement-\(UUID().uuidString)", isDirectory: true)
        let rootURL = parent.appendingPathComponent("registered-root", isDirectory: true)
        let movedRoot = parent.appendingPathComponent("original-root", isDirectory: true)
        let externalRoot = parent.appendingPathComponent("external-root", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: externalRoot, withIntermediateDirectories: true)
        let original = Data("same settled bytes".utf8)
        try original.write(to: rootURL.appendingPathComponent("source.txt"))
        try original.write(to: externalRoot.appendingPathComponent("source.txt"))
        defer { try? fm.removeItem(at: parent) }

        let db = try ESISDatabase(url: databaseURL)
        defer { db.close(); cleanup(databaseURL) }
        try db.runMigrations()
        _ = try db.settleWorkRootContents(
            rootID: "root-identity", rootURL: rootURL, carryText: false)

        try fm.moveItem(at: rootURL, to: movedRoot)
        try fm.createSymbolicLink(at: rootURL, withDestinationURL: externalRoot)

        XCTAssertThrowsError(
            try db.searchSettledContent(
                query: "same settled bytes", rootID: "root-identity", limit: 10),
            "a registered root replaced by a symlink must not redirect retrieval")
        XCTAssertThrowsError(
            try db.settleWorkRootContents(
                rootID: "root-identity", rootURL: rootURL, carryText: false),
            "a rootID must not silently rebind to the symlink target")
        XCTAssertEqual(try db.count("file_contents"), 1)
        XCTAssertEqual(
            try db.listExternalFiles(rootID: "root-identity")
                .first(where: { $0.relativePath == "source.txt" })?.status,
            "present")
    }

    func testRegisteredRootRefusesSymlinkedSourceForRetrievalAndSettlement() throws {
        let databaseURL = tempURL("symlink-source")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-symlink-root-\(UUID().uuidString)", isDirectory: true)
        let outsideURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-symlink-outside-\(UUID().uuidString).txt")
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let sourceURL = rootURL.appendingPathComponent("source.txt")
        let original = Data("unique protected source token".utf8)
        try original.write(to: sourceURL)
        try original.write(to: outsideURL)
        defer {
            try? fm.removeItem(at: rootURL)
            try? fm.removeItem(at: outsideURL)
        }

        let db = try ESISDatabase(url: databaseURL)
        defer { db.close(); cleanup(databaseURL) }
        try db.runMigrations()
        _ = try db.settleWorkRootContents(
            rootID: "symlink-source-root", rootURL: rootURL, carryText: false)

        try fm.removeItem(at: sourceURL)
        try fm.createSymbolicLink(at: sourceURL, withDestinationURL: outsideURL)

        XCTAssertThrowsError(
            try db.searchSettledContent(
                query: "unique protected source token",
                rootID: "symlink-source-root", limit: 10),
            "a settled locator replaced by a symlink must not be read")
        XCTAssertThrowsError(
            try db.settleWorkRootContents(
                rootID: "symlink-source-root", rootURL: rootURL, carryText: false),
            "a root scan containing a symlink must abort rather than follow it")

        XCTAssertEqual(try db.count("file_contents"), 1)
        XCTAssertEqual(
            try db.listExternalFiles(rootID: "symlink-source-root")
                .first(where: { $0.relativePath == "source.txt" })?.status,
            "present",
            "the failed scan must preserve the previous settled inventory")
        XCTAssertEqual(try db.count("retrieval_settlements"), 0)
    }

    func testIndexOnlySearchBoundsChangedSourceReadToIndexedSize() throws {
        let databaseURL = tempURL("index-only-growth-bound")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-index-only-growth-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileURL = rootURL.appendingPathComponent("source.txt")
        try Data("bounded source token".utf8).write(to: fileURL)
        defer { try? fm.removeItem(at: rootURL) }

        let db = try ESISDatabase(url: databaseURL)
        defer { db.close(); cleanup(databaseURL) }
        try db.runMigrations()
        _ = try db.settleWorkRootContents(
            rootID: "bounded-growth-root", rootURL: rootURL,
            fileByteCap: 128, carryText: false)
        XCTAssertEqual(try db.count("file_contents"), 1)

        // Grow the locator after settlement. The search must compare its
        // current stat size with the committed index size and refuse before
        // reading the newly-grown source into memory.
        try Data(repeating: 0x78, count: 4 * 1024 * 1024).write(to: fileURL)
        XCTAssertTrue(try db.searchSettledContent(
            query: "bounded source token", rootID: "bounded-growth-root", limit: 10).isEmpty)
        XCTAssertThrowsError(try db.executeInformationDemand(
            query: "bounded source token", rootID: "bounded-growth-root", limit: 10))
        XCTAssertEqual(
            try db.count("retrieval_settlements"), 0,
            "a changed oversized source must not create a partial retrieval settlement")
    }

    func testIndexOnlyOversizedTailIsSearchableWithoutReadingWholeSource() throws {
        let databaseURL = tempURL("index-only-tail")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-index-only-tail-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileURL = rootURL.appendingPathComponent("source.txt")
        let source = Data(repeating: 0x78, count: 2 * 1024 * 1024)
            + Data("\nneedle in tail\n".utf8)
        try source.write(to: fileURL)
        defer { try? fm.removeItem(at: rootURL) }

        let db = try ESISDatabase(url: databaseURL)
        defer { db.close(); cleanup(databaseURL) }
        try db.runMigrations()
        let report = try db.settleWorkRootContents(
            rootID: "index-only-tail-root", rootURL: rootURL,
            fileByteCap: 128, tailBytes: 256, maxTotalBytesRead: 512,
            carryText: false)
        XCTAssertTrue(report.indexOnly)
        XCTAssertEqual(report.entityBytesRead, 256)
        XCTAssertEqual(report.bytesAddressed, 0)
        XCTAssertEqual(try db.count("file_contents"), 1)

        let hits = try db.searchSettledContent(
            query: "needle", rootID: "index-only-tail-root", limit: 10)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.lineNo, 1)

        let demand = try db.executeInformationDemand(
            query: "needle", rootID: "index-only-tail-root", limit: 10)
        XCTAssertEqual(demand.hits.count, 1)
        XCTAssertFalse(demand.reused)
        let demandAgain = try db.executeInformationDemand(
            query: "needle", rootID: "index-only-tail-root", limit: 10)
        XCTAssertTrue(demandAgain.reused)
        XCTAssertEqual(demandAgain.hits, demand.hits)

        // A shrink that remains larger than the tail window must fail closed
        // as a stale locator, not attempt an unbounded full-source read.
        let settledRow = try XCTUnwrap(
            db.settledFileRows(rootID: "index-only-tail-root").first)
        try Data(repeating: 0x79, count: 1 * 1024 * 1024).write(to: fileURL)
        XCTAssertThrowsError(try db.searchableFileText(settledRow)) { error in
            XCTAssertEqual(
                error as? ESISDatabase.DatabaseError,
                .staleExternalSource(rootID: "index-only-tail-root", relativePath: "source.txt"))
        }
    }

    func testCarriedOversizedTailDigestIsVerifiedAndSearchable() throws {
        let databaseURL = tempURL("carried-tail")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-carried-tail-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileURL = rootURL.appendingPathComponent("source.txt")
        let source = Data(repeating: 0x78, count: 2 * 1024 * 1024)
            + Data("\nneedle in tail\n".utf8)
        try source.write(to: fileURL)
        defer { try? fm.removeItem(at: rootURL) }

        let db = try ESISDatabase(url: databaseURL)
        defer { db.close(); cleanup(databaseURL) }
        try db.runMigrations()
        let report = try db.settleWorkRootContents(
            rootID: "carried-tail-root", rootURL: rootURL,
            fileByteCap: 128, tailBytes: 256, maxTotalBytesRead: 512,
            carryText: true)
        XCTAssertFalse(report.indexOnly)
        XCTAssertEqual(report.entityBytesRead, 256)
        XCTAssertGreaterThan(report.bytesAddressed, 0)
        XCTAssertEqual(
            try db.carriedFileContent(rootID: "carried-tail-root", relativePath: "source.txt")?.content,
            Data("needle in tail\n".utf8))

        let hits = try db.searchSettledContent(
            query: "needle", rootID: "carried-tail-root", limit: 10)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.lineNo, 1)
    }

    func testRootSettlementRejectsTailWindowOverRemainingReadBudgetAtomically() throws {
        let databaseURL = tempURL("tail-budget")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-tail-budget-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let firstURL = rootURL.appendingPathComponent("a.txt")
        try Data(repeating: 0x78, count: 2 * 1024 * 1024).write(to: firstURL)
        defer { try? fm.removeItem(at: rootURL) }

        let db = try ESISDatabase(url: databaseURL)
        defer { db.close(); cleanup(databaseURL) }
        try db.runMigrations()
        _ = try db.settleWorkRootContents(
            rootID: "tail-budget-root", rootURL: rootURL,
            fileByteCap: 128, tailBytes: 128, maxTotalBytesRead: 128,
            carryText: false)
        let baseline = try db.listExternalFiles(rootID: "tail-budget-root")
        XCTAssertEqual(baseline.map(\.relativePath), ["a.txt"])

        try Data(repeating: 0x79, count: 2 * 1024 * 1024)
            .write(to: rootURL.appendingPathComponent("b.txt"))
        XCTAssertThrowsError(try db.settleWorkRootContents(
            rootID: "tail-budget-root", rootURL: rootURL,
            fileByteCap: 128, tailBytes: 256, maxTotalBytesRead: 128,
            carryText: false)) { error in
                XCTAssertTrue(
                    String(describing: error).contains("maxTotalBytesRead exceeded (128)"),
                    "the oversized tail window must be refused before reading: \(error)")
            }
        XCTAssertEqual(try db.listExternalFiles(rootID: "tail-budget-root"), baseline)
        XCTAssertEqual(try db.count("file_contents"), 1)
    }

    func testRootSettlementAbortsWhenNestedDirectoryCannotBeEnumerated() throws {
        let databaseURL = tempURL("enumeration-error")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-enumeration-error-\(UUID().uuidString)", isDirectory: true)
        let nestedURL = rootURL.appendingPathComponent("locked", isDirectory: true)
        let fileURL = nestedURL.appendingPathComponent("keep.txt")
        let fm = FileManager.default
        try fm.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try Data("preserve settled content".utf8).write(to: fileURL)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: nestedURL.path)
            try? fm.removeItem(at: rootURL)
        }

        let db = try ESISDatabase(url: databaseURL)
        defer { db.close(); cleanup(databaseURL) }
        try db.runMigrations()
        _ = try db.settleWorkRootContents(rootID: "enumeration-root", rootURL: rootURL)
        XCTAssertEqual(try db.count("file_contents"), 1)
        XCTAssertEqual(
            try db.listExternalFiles(rootID: "enumeration-root")
                .first(where: { $0.relativePath == "locked/keep.txt" })?.status,
            "present")

        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: nestedURL.path)
        XCTAssertThrowsError(
            try db.settleWorkRootContents(rootID: "enumeration-root", rootURL: rootURL))

        // Restore access before reading the assertions and before temporary cleanup.
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: nestedURL.path)
        XCTAssertEqual(try db.count("file_contents"), 1)
        XCTAssertEqual(
            try db.listExternalFiles(rootID: "enumeration-root")
                .first(where: { $0.relativePath == "locked/keep.txt" })?.status,
            "present")
    }

    func testInformationDemandRefusesMissingIndexOnlyFileWithoutCachingPartialResult() throws {
        let databaseURL = tempURL("missing-index-only")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-missing-index-only-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileURL = rootURL.appendingPathComponent("source.txt")
        try Data("the unique body token is present here".utf8).write(to: fileURL)
        defer { try? fm.removeItem(at: rootURL) }

        let db = try ESISDatabase(url: databaseURL)
        defer { db.close(); cleanup(databaseURL) }
        try db.runMigrations()
        _ = try db.settleWorkRootContents(
            rootID: "index-only-root", rootURL: rootURL, carryText: false)
        XCTAssertEqual(try db.count("file_contents"), 1)
        XCTAssertEqual(try db.count("retrieval_settlements"), 0)

        try fm.removeItem(at: fileURL)
        XCTAssertThrowsError(
            try db.executeInformationDemand(
                query: "unique body token", rootID: "index-only-root", limit: 10))
        XCTAssertEqual(
            try db.count("retrieval_settlements"), 0,
            "A demand with an unreadable settled source must not be persisted")
    }

    func testManualRootReconciliationMarksMissingOnceAndIsIdempotent() throws {
        let databaseURL = tempURL("manual-reconcile")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-manual-reconcile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("settled text".utf8).write(to: rootURL.appendingPathComponent("keep.txt"))
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let db = try ESISDatabase(url: databaseURL)
        defer { db.close(); cleanup(databaseURL) }
        try db.runMigrations()
        _ = try db.settleWorkRootContents(rootID: "manual-root", rootURL: rootURL)
        XCTAssertEqual(try db.count("file_contents"), 1)

        _ = try db.reconcileRoot(rootID: "manual-root", seenRelativePaths: [])
        XCTAssertEqual(try db.count("file_contents"), 0)
        XCTAssertEqual(
            try db.listExternalFiles(rootID: "manual-root")
                .first(where: { $0.relativePath == "keep.txt" })?.status,
            "missing")

        let second = try db.reconcileRoot(rootID: "manual-root", seenRelativePaths: [])
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(
            try db.listExternalFiles(rootID: "manual-root")
                .first(where: { $0.relativePath == "keep.txt" })?.status,
            "missing")
    }


    func testInformationDemandRefusesIndexOnlyInputWithoutMetadataAddress() throws {
        let databaseURL = tempURL("missing-index-address")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-missing-index-address-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let db = try ESISDatabase(url: databaseURL)
        defer { db.close(); cleanup(databaseURL) }
        try db.runMigrations()

        // Construct an incomplete index-only record without deleting from the
        // append-only carrier ledger (which correctly rejects destructive SQL).
        try rawExec(databaseURL, """
        INSERT INTO roots(root_id, category, display_name, locator_type, status, created_at, last_scanned_at)
        VALUES('index-address-root','work','\(rootURL.path)','path','present','t','t');
        INSERT INTO file_contents(
            root_id, relative_path, content_sha256, content, settled_at, object_id)
        VALUES('index-address-root','source.txt','source-digest','', 't', NULL);
        """)
        XCTAssertEqual(try db.count("file_contents"), 1)
        XCTAssertEqual(try db.count("retrieval_settlements"), 0)
        XCTAssertNil(try db.latestIndexObjectID(
            identity: "file:index-address-root/source.txt"))

        XCTAssertThrowsError(
            try db.executeInformationDemand(
                query: "unique body token", rootID: "index-address-root", limit: 10))
        XCTAssertEqual(
            try db.count("retrieval_settlements"), 0,
            "A demand without complete source-address provenance must not be persisted")
    }


    func testRemovedFilenameOnlyInputInvalidatesItsRetrievalSettlement() throws {
        let databaseURL = tempURL("filename-only-invalidation")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-filename-only-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileURL = rootURL.appendingPathComponent("needle-binary.bin")
        try Data([0xFF, 0xFE]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let db = try ESISDatabase(url: databaseURL)
        defer { db.close(); cleanup(databaseURL) }
        try db.runMigrations()
        _ = try db.settleWorkRootContents(
            rootID: "filename-root", rootURL: rootURL, carryText: false)
        XCTAssertEqual(try db.count("file_contents"), 0)

        let retrieval = try db.executeInformationDemand(
            query: "needle", rootID: "filename-root", limit: 10)
        XCTAssertEqual(retrieval.hits.map(\.relativePath), ["needle-binary.bin"])

        func retrievalStatus() throws -> String {
            var reader: OpaquePointer?
            guard sqlite3_open(databaseURL.path, &reader) == SQLITE_OK, let reader else {
                throw ESISDatabase.DatabaseError.sql("cannot open retrieval status reader")
            }
            defer { sqlite3_close(reader) }
            var stmt: OpaquePointer?
            let sql = """
            SELECT status FROM retrieval_settlements
            WHERE demand_id='\(retrieval.demandID)';
            """
            guard sqlite3_prepare_v2(reader, sql, -1, &stmt, nil) == SQLITE_OK,
                let stmt
            else {
                throw ESISDatabase.DatabaseError.sql("cannot prepare retrieval status query")
            }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW,
                let value = sqlite3_column_text(stmt, 0)
            else {
                throw ESISDatabase.DatabaseError.sql("missing retrieval status row")
            }
            return String(cString: value)
        }
        XCTAssertEqual(try retrievalStatus(), "valid")

        try FileManager.default.removeItem(at: fileURL)
        _ = try db.settleWorkRootContents(
            rootID: "filename-root", rootURL: rootURL, carryText: false)
        XCTAssertEqual(try retrievalStatus(), "invalidated")
    }


    func testInformationDemandRefusesChangedIndexOnlyFileWithoutCachingPartialResult() throws {
        let databaseURL = tempURL("changed-index-only")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-changed-index-only-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileURL = rootURL.appendingPathComponent("source.txt")
        try Data("needle original bytes".utf8).write(to: fileURL)
        defer { try? fm.removeItem(at: rootURL) }

        let db = try ESISDatabase(url: databaseURL)
        defer { db.close(); cleanup(databaseURL) }
        try db.runMigrations()
        _ = try db.settleWorkRootContents(
            rootID: "changed-index-only-root", rootURL: rootURL, carryText: false)

        // Keep the path available but change its bytes without a new root
        // settlement. An index-only reader must detect the digest mismatch,
        // rather than silently publishing a retrieval from the remaining rows.
        try Data("needle changed bytes".utf8).write(to: fileURL)
        XCTAssertThrowsError(
            try db.executeInformationDemand(
                query: "needle", rootID: "changed-index-only-root", limit: 10))
        XCTAssertEqual(
            try db.count("retrieval_settlements"), 0,
            "A demand based on stale physical bytes must not be persisted")
    }

}

extension ESISDatabaseTests {

    private func legacyState(_ id: String, checkpointIDs: [UUID] = []) -> ESISDatabase.GraphState {
        ESISDatabase.GraphState(
            id: id, parentID: nil, modelIdentity: "test-model",
            createdAt: Date(timeIntervalSince1970: 700000000), position: 1,
            continuationID: "C-\(id)", nextInput: "next", anchor: "a1",
            prefix: ["p1"], lifecycle: "active", checkpointIDs: checkpointIDs)
    }

    private func legacyCheckpoint(_ id: String, stateID: String,
                                  createdAt: TimeInterval) -> ESISDatabase.GraphCheckpoint {
        ESISDatabase.GraphCheckpoint(
            id: UUID(uuidString: id)!, stateID: stateID, modelIdentity: "test-model",
            position: 1, continuationID: "C-\(stateID)", nextInput: "next", anchor: "a1",
            prefix: ["p1"], createdAt: Date(timeIntervalSince1970: createdAt),
            checksum: "sha256-abc")
    }

    /// Put the store back into the shape a pre-v21 build leaves behind: the two
    /// v2 `ALTER TABLE ADD COLUMN` columns are NULL while the rows are live.
    private func makeLegacyNullRows(_ url: URL, _ stateID: String) throws {
        try rawExec(url, """
        UPDATE execution_states SET checkpoint_ids_json=NULL, prefix_json=NULL WHERE state_id='\(stateID)';
        DELETE FROM schema_migrations WHERE version >= 21;
        """)
    }

    func testV21RebuildsLegacyNullCheckpointListFromCheckpoints() throws {
        let url = tempURL("v21-rebuild")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()

        // The rows are deliberately handed to the writer newest-first, so the
        // rebuilt list can only come out right if it is ordered by creation time
        // rather than by whatever the table scan happens to return.
        let earlier = "11111111-1111-1111-1111-111111111111"
        let later = "22222222-2222-2222-2222-222222222222"
        try db.writeGraph(
            states: [legacyState("v21-state", checkpointIDs: [UUID(uuidString: earlier)!, UUID(uuidString: later)!])],
            checkpoints: [
                legacyCheckpoint(later, stateID: "v21-state", createdAt: 1_800_000_100),
                legacyCheckpoint(earlier, stateID: "v21-state", createdAt: 1_800_000_000),
            ])
        try makeLegacyNullRows(url, "v21-state")
        XCTAssertEqual(
            try rawText(url, "SELECT typeof(checkpoint_ids_json) FROM execution_states WHERE state_id='v21-state';"),
            "null")

        let migrated = try ESISDatabase(url: url, createIfNeeded: false)
        defer { migrated.close() }
        try migrated.runMigrations()

        XCTAssertEqual(
            try rawText(url, "SELECT checkpoint_ids_json FROM execution_states WHERE state_id='v21-state';"),
            "[\"\(earlier)\",\"\(later)\"]",
            "the backfilled list is the state's authoritative checkpoint rows in creation order")
        XCTAssertEqual(
            try rawText(url, "SELECT prefix_json FROM execution_states WHERE state_id='v21-state';"),
            "[]", "a legacy NULL prefix is the serialized empty list")
        let graph = try migrated.readGraph()
        XCTAssertEqual(
            graph.states.first(where: { $0.id == "v21-state" })?.checkpointIDs,
            [UUID(uuidString: earlier)!, UUID(uuidString: later)!])
        // The two views of the same authority must agree, row for row.
        XCTAssertEqual(
            graph.states.first(where: { $0.id == "v21-state" })?.checkpointIDs,
            graph.checkpoints.filter { $0.stateID == "v21-state" }.map(\.id))
        XCTAssertEqual(
            try rawText(url, "SELECT COUNT(*) FROM execution_states WHERE checkpoint_ids_json IS NULL;"), "0")
    }

    func testV21BackfillsLegacyNullWithoutCheckpointsToEmptyList() throws {
        let url = tempURL("v21-empty")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        try db.writeGraph(states: [legacyState("v21-orphan")], checkpoints: [])
        try makeLegacyNullRows(url, "v21-orphan")

        let migrated = try ESISDatabase(url: url, createIfNeeded: false)
        defer { migrated.close() }
        try migrated.runMigrations()

        XCTAssertEqual(
            try rawText(url, "SELECT checkpoint_ids_json FROM execution_states WHERE state_id='v21-orphan';"),
            "[]")
        XCTAssertEqual(try migrated.readGraph().states.first?.checkpointIDs, [])
        XCTAssertEqual(try migrated.readGraph().states.count, 1)
    }

    func testV21DoesNotWidenTheStrictReadForBlankOrLaterNullRows() throws {
        let url = tempURL("v21-strict")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        try db.writeGraph(
            states: [legacyState("v21-blank", checkpointIDs: [UUID()])],
            checkpoints: [])

        // v21 has already been recorded, so it rewrites nothing: these are not
        // the legacy shape but genuine corruption, and must stay fatal.
        try rawExec(url, "UPDATE execution_states SET checkpoint_ids_json='' WHERE state_id='v21-blank';")
        XCTAssertThrowsError(try db.readGraph(), "blank checkpoint_ids_json stays corruption after v21")
        try rawExec(url, "UPDATE execution_states SET checkpoint_ids_json='[\"not-a-uuid\"]' WHERE state_id='v21-blank';")
        XCTAssertThrowsError(try db.readGraph(), "a malformed UUID stays corruption after v21")
        try rawExec(url, "UPDATE execution_states SET checkpoint_ids_json=NULL WHERE state_id='v21-blank';")
        XCTAssertThrowsError(try db.readGraph(), "a NULL written after v21 must not be normalized away")
    }

    func testRecordExecutionStateSerializesCheckpointListInsteadOfNull() throws {
        let url = tempURL("v21-writer")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()

        try db.recordExecutionState(
            id: "mirror-state", parentID: nil, modelIdentity: "test-model",
            position: 0, continuationID: "C-1", anchor: "a1",
            lifecycle: "active", createdAt: Date())

        XCTAssertEqual(
            try rawText(url, "SELECT typeof(checkpoint_ids_json) FROM execution_states WHERE state_id='mirror-state';"),
            "text", "the mirroring writer must never leave the authoritative column NULL")
        XCTAssertEqual(
            try rawText(url, "SELECT checkpoint_ids_json FROM execution_states WHERE state_id='mirror-state';"),
            "[]")
        XCTAssertNoThrow(try db.readGraph())
    }

    func testV21MigrationIsIdempotentAndLeavesNoNullRows() throws {
        let url = tempURL("v21-idempotent")
        let db = try ESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        try db.writeGraph(states: [legacyState("v21-twice")], checkpoints: [])
        try makeLegacyNullRows(url, "v21-twice")

        let migrated = try ESISDatabase(url: url, createIfNeeded: false)
        defer { migrated.close() }
        try migrated.runMigrations()
        try migrated.runMigrations()

        XCTAssertEqual(
            try rawText(url, "SELECT COUNT(*) FROM schema_migrations WHERE version = 21;"), "1")
        XCTAssertEqual(
            try rawText(url, "SELECT COUNT(*) FROM execution_states WHERE checkpoint_ids_json IS NULL OR prefix_json IS NULL;"), "0")
    }
}
