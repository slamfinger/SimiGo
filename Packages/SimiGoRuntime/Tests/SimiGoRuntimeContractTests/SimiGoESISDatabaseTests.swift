import Foundation
import SQLite3
import XCTest
@testable import SimiGoRuntimeContract

final class SimiGoESISDatabaseTests: XCTestCase {

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

    func testFreshDatabaseMigratesAndPassesIntegrity() throws {
        let url = tempURL("fresh")
        let db = try SimiGoESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        XCTAssertEqual(try db.schemaVersion(), 0)
        try db.runMigrations()
        XCTAssertEqual(try db.schemaVersion(), 19)   // v18 binds MCP tokenizer identity to ES
        XCTAssertTrue(try db.integrityCheck())
        XCTAssertEqual(try db.count("chat_messages"), 0)
        XCTAssertEqual(try db.count("file_contents"), 0)
        XCTAssertEqual(try db.count("retrieval_settlements"), 0)
        // Idempotent: re-running does not error or double-apply.
        try db.runMigrations()
        XCTAssertEqual(try db.schemaVersion(), 19)
    }

    /// A database stamped v6 by the old out-of-order gates reports the head
    /// version while `chat_messages` and `file_contents` are absent. The v7
    /// repair pass must recreate them without touching existing rows.
    func testRepairsTablesSkippedByOutOfOrderGates() throws {
        let url = tempURL("repair")
        defer { cleanup(url) }
        let db = try SimiGoESISDatabase(url: url)
        try db.runMigrations()
        XCTAssertEqual(try db.schemaVersion(), 19)
        db.close()

        try rawExec(url, """
        DROP TABLE file_contents;
        DROP TABLE chat_messages;
        DROP TABLE retrieval_settlements;
        DELETE FROM schema_migrations WHERE version >= 4;
        INSERT INTO schema_migrations(version, applied_at, checksum)
            VALUES(6, '2026-10-26T00:00:00Z', 'simigo-demand-retrieval-settlement-v6');
        """)

        let repaired = try SimiGoESISDatabase(url: url)
        defer { repaired.close() }
        XCTAssertEqual(try repaired.schemaVersion(), 6)
        try repaired.runMigrations()
        XCTAssertEqual(try repaired.schemaVersion(), 19)
        XCTAssertEqual(try repaired.count("chat_messages"), 0)
        XCTAssertEqual(try repaired.count("file_contents"), 0)
        XCTAssertEqual(try repaired.count("retrieval_settlements"), 0)
        try repaired.runMigrations()
        XCTAssertEqual(try repaired.schemaVersion(), 19)
    }

    private func rawExec(_ url: URL, _ sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            sqlite3_close(handle)
            throw SimiGoESISDatabase.DatabaseError.cannotOpen(url.path)
        }
        defer { sqlite3_close(handle) }
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &message) == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(message)
            throw SimiGoESISDatabase.DatabaseError.sql(detail)
        }
    }

    private func rawText(_ url: URL, _ sql: String) throws -> String {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            sqlite3_close(handle)
            throw SimiGoESISDatabase.DatabaseError.cannotOpen(url.path)
        }
        defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SimiGoESISDatabase.DatabaseError.sql(sql)
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return "" }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
    }

    /// An existing v17 store must upgrade in place through v19: tokenizer
    /// identity remains NULL for historical states, graph ownership defaults
    /// to native-managed, and both migration rows land exactly once.
    func testV17UpgradeAddsTokenizerIdentityAndGraphOwnership() throws {
        let url = tempURL("v17-upgrade")
        defer { cleanup(url) }
        let db = try SimiGoESISDatabase(url: url)
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
        DELETE FROM schema_migrations WHERE version IN (18, 19);
        """)

        let upgraded = try SimiGoESISDatabase(url: url, createIfNeeded: false)
        defer { upgraded.close() }
        XCTAssertEqual(try upgraded.schemaVersion(), 17)
        try upgraded.runMigrations()
        XCTAssertEqual(try upgraded.schemaVersion(), 19)
        XCTAssertNil(
            try upgraded.executionStateTokenizerIdentity("legacy-state"),
            "a pre-v18 state carries no claim and must keep failing closed")
        XCTAssertEqual(
            try rawText(url, "SELECT graph_managed FROM execution_states WHERE state_id='legacy-state';"),
            "1", "legacy rows default to native graph ownership")
        XCTAssertEqual(
            try rawText(url, "SELECT COUNT(*) FROM schema_migrations WHERE version IN (18, 19);"), "2")
    }

    /// Re-running the v19 migration — including after reopening the store —
    /// must not duplicate version rows or re-add either column.
    func testV19MigrationIsIdempotentAcrossReopens() throws {
        let url = tempURL("v18-idempotent")
        defer { cleanup(url) }
        let db = try SimiGoESISDatabase(url: url)
        try db.runMigrations()
        try db.runMigrations()
        db.close()

        let reopened = try SimiGoESISDatabase(url: url, createIfNeeded: false)
        try reopened.runMigrations()
        XCTAssertEqual(try reopened.schemaVersion(), 19)
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
        let db = try SimiGoESISDatabase(url: url)
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
        let db = try SimiGoESISDatabase(url: url)
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
        let db = try SimiGoESISDatabase(url: url)
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
        let db = try SimiGoESISDatabase(url: url)
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
        let db = try SimiGoESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        XCTAssertThrowsError(try db.importLegacyGraph(jsonData: legacyGraphJSON(contractVersion: "v9.9"), sourceLabel: "bad.json")) { e in
            XCTAssertEqual(e as? SimiGoESISDatabase.DatabaseError,
                           .contractVersionMismatch("v9.9"))
        }
        // No half-written authority survives the rollback.
        XCTAssertEqual(try db.count("execution_states"), 0)
        XCTAssertEqual(try db.count("settlements"), 0)
    }

    func testForeignKeyViolationRollsBackEntirely() throws {
        let url = tempURL("fk")
        let db = try SimiGoESISDatabase(url: url)
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
        XCTAssertThrowsError(try SimiGoESISDatabase(url: url)) { e in
            guard case SimiGoESISDatabase.DatabaseError.notADatabase = e as! SimiGoESISDatabase.DatabaseError else {
                return XCTFail("expected notADatabase, got \(e)")
            }
        }
    }
}

extension SimiGoESISDatabaseTests {
    func testRecordNativeSettlementAsWriteAuthority() throws {
        let url = tempURL("native-settle")
        let db = try SimiGoESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        try db.recordExecutionState(id: "S-0001", parentID: nil, modelIdentity: "m", position: 1, continuationID: "C-1", anchor: "a1", lifecycle: "saved", createdAt: Date())
        let route = #"{"schema_version":"simigo.result-contract/v1","fields":{"secret":{"pattern":"^SECRET=(.+)$","type":"string"}},"constraints":[{"kind":"digest_equals_binding","field":"secret","binding":"secret_commitment"}]}"#
        let settled = try SimiGoSettlementAuthority.authorize(
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
        let db = try SimiGoESISDatabase(url: url)
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
        XCTAssertThrowsError(try SimiGoSettlementAuthority.authorize(
            generatedText: "RESULT=tampered", contractJSON: Data(contract.utf8), verifiedBindings: bindings
        )) { e in
            XCTAssertEqual((e as? NativeResultContractError)?.code, "PRODUCER_RESULT_BINDING_MISMATCH")
        }
        XCTAssertEqual(try db.count("settlements"), 0, "refusal must not write any settlement")

        // Authorized path: commit to the authoritative store, then read it back.
        let settled = try SimiGoSettlementAuthority.authorize(
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
        let db = try SimiGoESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        let cpID = UUID()
        let state = SimiGoESISDatabase.GraphState(
            id: "S-0001", parentID: nil, modelIdentity: "reference-model",
            createdAt: Date(timeIntervalSince1970: 700000000), position: 2,
            continuationID: "C-1", nextInput: "east", anchor: "a1",
            prefix: ["hello", "east"], lifecycle: "active", checkpointIDs: [cpID])
        let cp = SimiGoESISDatabase.GraphCheckpoint(
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
        let db = try SimiGoESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        func st(_ id: String) -> SimiGoESISDatabase.GraphState {
            SimiGoESISDatabase.GraphState(id: id, parentID: nil, modelIdentity: "m",
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
        let db = try SimiGoESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        func st(_ id: String) -> SimiGoESISDatabase.GraphState {
            SimiGoESISDatabase.GraphState(id: id, parentID: nil, modelIdentity: "m",
                createdAt: Date(timeIntervalSince1970: 700000000), position: 0,
                continuationID: "C", nextInput: "", anchor: "a", prefix: [], lifecycle: "active", checkpointIDs: [])
        }
        try db.writeGraph(states: [st("A"), st("B")], checkpoints: [])
        // B has an authoritative settlement; removing it from the live graph must NOT
        // cascade-delete it, so the IS record stays resolvable.
        try db.recordExecutionState(id: "B", parentID: nil, modelIdentity: "m", position: 0,
                                    continuationID: "C", anchor: "a", lifecycle: "saved", createdAt: Date())
        let route = #"{"schema_version":"simigo.result-contract/v1","fields":{"secret":{"pattern":"^SECRET=(.+)$","type":"string"}},"constraints":[{"kind":"digest_equals_binding","field":"secret","binding":"secret_commitment"}]}"#
        let settled = try SimiGoSettlementAuthority.authorize(
            generatedText: "SECRET=NORTH>EAST", contractJSON: Data(route.utf8),
            verifiedBindings: ["secret_commitment": .string("2b1a5d9f0a1183c966ce8325a252424579a625c1b2314654dd6aaebaf9c334a8")])
        _ = try db.recordNativeSettlement(settled, stateID: "B")
        try db.writeGraph(states: [st("A")], checkpoints: [])   // drop B from live graph
        XCTAssertEqual(try db.count("settlements"), 1)          // settlement survives
        XCTAssertTrue(try db.readGraph().states.contains { $0.id == "B" })  // B kept (referenced)
    }
}

extension SimiGoESISDatabaseTests {

    private func settleSource(_ db: SimiGoESISDatabase, stateID: String) throws -> String {
        try db.recordExecutionState(
            id: stateID, parentID: nil, modelIdentity: "reference-model",
            position: 1, continuationID: "C-1", anchor: "a1",
            lifecycle: "saved", createdAt: Date())
        let route = #"{"schema_version":"simigo.result-contract/v1","fields":{"secret":{"pattern":"^SECRET=(.+)$","type":"string"}},"constraints":[{"kind":"digest_equals_binding","field":"secret","binding":"secret_commitment"}]}"#
        let settled = try SimiGoSettlementAuthority.authorize(
            generatedText: "SECRET=NORTH>EAST", contractJSON: Data(route.utf8),
            verifiedBindings: ["secret_commitment": .string("2b1a5d9f0a1183c966ce8325a252424579a625c1b2314654dd6aaebaf9c334a8")])
        return try db.recordNativeSettlement(settled, stateID: stateID)
    }

    /// Serving an already-settled answer must be verifiable from the database
    /// alone, not from trace text: the reuse row carries `model_calls=0`, the
    /// source settlement it consumed, and the digest of the exact lookup key.
    func testAnswerReuseIsRecordedAsZeroModelCallRow() throws {
        let url = tempURL("reuse-row")
        let db = try SimiGoESISDatabase(url: url)
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
        let db = try SimiGoESISDatabase(url: url)
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
        let db = try SimiGoESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        let source = try settleSource(db, stateID: "S-SRC")
        _ = try db.invalidateSettlement(source)

        XCTAssertThrowsError(try db.recordInformationReuse(
            sourceSettlementID: source, sourceStateID: "S-SRC",
            demandID: "D-1", sessionID: "info-a", query: "q"
        )) { e in
            XCTAssertEqual(
                e as? SimiGoESISDatabase.InformationReuseError, .sourceNotValid(source))
        }
        XCTAssertEqual(try db.count("information_reuse_events"), 0)

        XCTAssertThrowsError(try db.recordInformationReuse(
            sourceSettlementID: source, sourceStateID: "S-SRC",
            demandID: "", sessionID: "info-a", query: "q"
        )) { e in
            XCTAssertEqual(
                e as? SimiGoESISDatabase.InformationReuseError, .emptyField("demand_id"))
        }
    }
}

// MARK: - #223-A regression: init-time lock contention is an execution
// condition, never a corruption diagnostic

extension SimiGoESISDatabaseTests {

    /// Races two real `SimiGoESISDatabase` opens on a closed WAL carrier.
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
            let seed = try SimiGoESISDatabase(url: url)
            try seed.runMigrations()
            seed.close()
        }

        let outcomeLock = NSLock()
        var outcomes: [Result<SimiGoESISDatabase, Error>] = []
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
                        let db = try SimiGoESISDatabase(url: url, createIfNeeded: false)
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
                    guard let dbError = error as? SimiGoESISDatabase.DatabaseError else {
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
        let final = try SimiGoESISDatabase(url: url, createIfNeeded: false)
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
                throw SimiGoESISDatabase.DatabaseError.sql(detail)
            }
        }
        try blockerExec("PRAGMA journal_mode = DELETE;")
        try blockerExec("CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT);")
        try blockerExec("BEGIN EXCLUSIVE;")
        try blockerExec("INSERT INTO t(v) VALUES('held');")

        let start = Date()
        do {
            _ = try SimiGoESISDatabase(url: url, createIfNeeded: false)
            XCTFail("init should have failed while an exclusive writer held the database")
        } catch let error as SimiGoESISDatabase.DatabaseError {
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
        let db = try SimiGoESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()

        let state = SimiGoESISDatabase.GraphState(
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

}
