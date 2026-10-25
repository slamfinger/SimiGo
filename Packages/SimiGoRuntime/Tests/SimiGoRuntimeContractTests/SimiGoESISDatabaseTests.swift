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
        XCTAssertEqual(try db.schemaVersion(), 7)   // v7 repair pass is the head
        XCTAssertTrue(try db.integrityCheck())
        XCTAssertEqual(try db.count("chat_messages"), 0)
        XCTAssertEqual(try db.count("file_contents"), 0)
        XCTAssertEqual(try db.count("retrieval_settlements"), 0)
        // Idempotent: re-running does not error or double-apply.
        try db.runMigrations()
        XCTAssertEqual(try db.schemaVersion(), 7)
    }

    /// A database stamped v6 by the old out-of-order gates reports the head
    /// version while `chat_messages` and `file_contents` are absent. The v7
    /// repair pass must recreate them without touching existing rows.
    func testRepairsTablesSkippedByOutOfOrderGates() throws {
        let url = tempURL("repair")
        defer { cleanup(url) }
        let db = try SimiGoESISDatabase(url: url)
        try db.runMigrations()
        XCTAssertEqual(try db.schemaVersion(), 7)
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
        XCTAssertEqual(try repaired.schemaVersion(), 7)
        XCTAssertEqual(try repaired.count("chat_messages"), 0)
        XCTAssertEqual(try repaired.count("file_contents"), 0)
        XCTAssertEqual(try repaired.count("retrieval_settlements"), 0)
        try repaired.runMigrations()
        XCTAssertEqual(try repaired.schemaVersion(), 7)
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
