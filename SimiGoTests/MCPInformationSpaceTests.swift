import Foundation
import SQLite3
import XCTest
import SimiGoRuntimeContract
@testable import SimiGo

/// App-level proof for the MCP facade: every tool runs the SAME native ES/IS
/// operations (settled index, locator reads, demand reuse) over an isolated
/// temporary store, and registering a root indexes it WITHOUT copying bytes.
final class MCPInformationSpaceTests: XCTestCase {

    private var dir: URL!
    private var dbURL: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-is-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("simigo.sqlite3")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeServer() -> HTTPServer {
        HTTPServer(
            port: 0,
            modelId: "test-model",
            generateHandler: { _, _, _, _, _, _, _, _, _, _ in
                GenerationResult(text: "", usage: nil, completion: .complete)
            },
            forkBranchHandler: { _, _, _, _ in
                SessionCacheMetadata(
                    storageKey: "test/main",
                    modelId: "test-model",
                    savedAt: Date(),
                    history: [])
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true }
        )
    }

    private func rawText(_ sql: String) throws -> String {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &handle), SQLITE_OK)
        guard let handle else { return "" }
        defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(handle, sql, -1, &stmt, nil), SQLITE_OK)
        guard let stmt else { return "" }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return "" }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
    }

    // MARK: - Protocol shape

    func testInitializeToolsListAndNotificationShape() {
        let server = makeServer()
        let initResponse = server.mcpResponse(for: [
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
        ])
        let initResult = initResponse?["result"] as? [String: Any]
        XCTAssertEqual(initResult?["protocolVersion"] as? String, "2025-06-18")
        XCTAssertNotNil(initResult?["capabilities"])

        let listResponse = server.mcpResponse(for: [
            "jsonrpc": "2.0", "id": 2, "method": "tools/list",
        ])
        let tools = (listResponse?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        let names = Set(tools?.compactMap { $0["name"] as? String } ?? [])
        XCTAssertEqual(names, [
            "simigo_is_search", "simigo_is_status", "simigo_roots_list",
            "simigo_root_register", "simigo_is_reconcile", "simigo_is_settlement",
            "simigo_es_begin", "simigo_es_settle", "simigo_es_fail",
        ])

        XCTAssertNil(server.mcpResponse(for: [
            "jsonrpc": "2.0", "method": "notifications/initialized",
        ]), "a notification carries no response")

        let unknown = server.mcpResponse(for: [
            "jsonrpc": "2.0", "id": 3, "method": "does/not/exist",
        ])
        let error = unknown?["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? Int, -32601)
    }

    // MARK: - Same native operations

    func testRootRegisterIsIndexOnlyAndSearchResolvesIt() throws {
        let root = dir.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("alpha\nneedle body\n".utf8)
            .write(to: root.appendingPathComponent("doc.md"))

        let registered = try HTTPServer.runMCPTool(
            name: "simigo_root_register",
            arguments: ["path": root.path], databaseURL: dbURL)
        XCTAssertEqual(registered["registered"] as? Bool, true)
        let settle = registered["content_settle"] as? [String: Any]
        XCTAssertEqual(settle?["index_only"] as? Bool, true)
        XCTAssertEqual(settle?["settled"] as? Int, 1)

        XCTAssertEqual(try rawText(
            "SELECT COUNT(*) FROM file_contents WHERE object_id IS NOT NULL;"), "0",
            "the index stores a locator + digest, never the entity bytes")
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM file_contents;"), "1")

        let search = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: [
                "query": "needle", "include_chat": false,
                "request_id": "mcp-needle-1",
            ],
            databaseURL: dbURL)
        let items = search["items"] as? [[String: Any]]
        XCTAssertEqual(items?.count, 1)
        XCTAssertEqual(items?.first?["text"] as? String, "needle body")
        XCTAssertEqual(items?.first?["kind"] as? String, "file")
        XCTAssertEqual(search["reused"] as? Bool, false)

        // The same declared request reuses its settled result, reading no new
        // bytes.
        let again = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: [
                "query": "needle", "include_chat": false,
                "request_id": "mcp-needle-1",
            ],
            databaseURL: dbURL)
        XCTAssertEqual(again["reused"] as? Bool, true)
        XCTAssertEqual(again["demand_id"] as? String, search["demand_id"] as? String)

        // Without a request identity two calls are independent requests: the
        // shared retrieval is reused as knowledge, never fused into one demand
        // lifecycle.
        let unrelated = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: ["query": "needle", "include_chat": false],
            databaseURL: dbURL)
        XCTAssertEqual(unrelated["reused"] as? Bool, false)
        XCTAssertNotEqual(
            unrelated["demand_id"] as? String, search["demand_id"] as? String)

        // A changed file fails digest verification and stops being cited.
        try Data("different\n".utf8)
            .write(to: root.appendingPathComponent("doc.md"))
        let afterChange = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: [
                "query": "needle", "include_chat": false,
                "request_id": "mcp-needle-1",
            ],
            databaseURL: dbURL)
        XCTAssertEqual((afterChange["items"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(
            (afterChange["stale_items"] as? [String])?.count, 1)
    }

    func testUnknownToolAndMissingSettlementFailClosed() throws {
        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_no_such_tool",
            arguments: [:], databaseURL: dbURL))

        do {
            _ = try HTTPServer.runMCPTool(
                name: "simigo_is_settlement",
                arguments: ["settlement_id": "missing"], databaseURL: dbURL)
            XCTFail("an unknown settlement must not resolve")
        } catch {
            XCTAssertTrue(String(describing: error).contains("no such settlement"))
        }
    }

    // MARK: - Post-settlement distillation

    func testSettlementSummaryIsReadableAndCitableOverMCP() throws {
        let db = try SimiGoESISDatabase(url: dbURL, createIfNeeded: true)
        try db.runMigrations()
        let loop = SimiGoInformationLoop(database: db)
        let turn = try loop.settleTurn(
            generatedText: "施工组织设计以实施性方案为纲，覆盖关键线路与节点工期。",
            resolution: nil, stateID: "S-MCP-1", parentStateID: nil, position: 0,
            modelIdentity: "test-model",
            identity: .init(model: "m", tokenizer: "t"),
            sessionID: "mcp-alpha", summaryQuery: "施工组织设计要点",
            actions: ["chat.completion"])
        db.close()

        let receipt = try HTTPServer.runMCPTool(
            name: "simigo_is_settlement",
            arguments: ["settlement_id": turn.settlementID], databaseURL: dbURL)
        let summary = try XCTUnwrap(receipt["summary"] as? [String: Any])
        XCTAssertEqual(summary["query"] as? String, "施工组织设计要点")
        XCTAssertTrue((summary["text"] as? String ?? "").contains("关键线路"))
        XCTAssertEqual(
            summary["source_payload_digest"] as? String,
            receipt["payload_sha256"] as? String,
            "a summary names the payload digest it distilled")

        let status = try HTTPServer.runMCPTool(
            name: "simigo_is_status", arguments: [:], databaseURL: dbURL)
        XCTAssertEqual(status["settlement_summaries"] as? Int, 1)

        let search = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: [
                "query": "关键线路 节点工期",
                "include_chat": false,
                "session_ids": ["mcp-beta"],
            ],
            databaseURL: dbURL)
        let items = try XCTUnwrap(search["items"] as? [[String: Any]])
        let cited = try XCTUnwrap(items.first { $0["kind"] as? String == "settlement" })
        XCTAssertEqual(cited["item_id"] as? String, "settlement:\(turn.settlementID)")
        XCTAssertEqual(cited["source_sha256"] as? String, summary["sha256"] as? String)
    }

    // MARK: - Execution lifecycle wiring
    //
    // The point of these tests is NOT that JSON-RPC answers. A cloud agent's
    // model call happens outside SimiGo, so "MCP connected" says nothing about
    // whether anything was recorded: these assert what the tool call actually
    // wrote into the authoritative store.

    func testBeginSettleRecordsAuthoritativeSettlement() throws {
        let begun = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: ["model": "cloud-model", "tokenizer": "cloud-tokenizer"],
            databaseURL: dbURL)
        let stateID = try XCTUnwrap(begun["state_id"] as? String)
        XCTAssertEqual(begun["settled"] as? Bool, false)
        XCTAssertTrue(begun["reusable_answer"] is NSNull)
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "0",
                       "beginning an execution records no result")

        let settled = try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": stateID,
                "model": "cloud-model",
                "tokenizer": "cloud-tokenizer",
                "output": "the exit is north",
                "session_id": "cloud-a",
                "query": "where is the exit",
            ],
            databaseURL: dbURL)
        // Printed before any assertion: a failure here symbolicates through a
        // dSYM and can stall the report, so the raw reply must reach the log.
        print("[MCP-SETTLE] \(settled)")
        let settlementID = try XCTUnwrap(settled["settlement_id"] as? String)
        let payloadSHA = try XCTUnwrap(settled["payload_sha256"] as? String)
        XCTAssertEqual(settled["state_id"] as? String, stateID)
        XCTAssertEqual(settled["validity"] as? String, "valid")
        XCTAssertEqual(settled["summary_recorded"] as? Bool, true)
        XCTAssertEqual((settled["dependencies"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "1")

        // A declared source must already be sealed in the carrier: the follow-up
        // turn cites the first result's payload object, and that dependency row
        // commits with the settlement instead of after it.
        let begunFollowUp = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "cloud-model", "tokenizer": "cloud-tokenizer",
                "session_id": "cloud-b", "query": "what did you just say",
            ],
            databaseURL: dbURL)
        let followUpState = try XCTUnwrap(begunFollowUp["state_id"] as? String)
        let followUp = try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": followUpState, "model": "cloud-model",
                "tokenizer": "cloud-tokenizer",
                "output": "I said the exit is north",
                "session_id": "cloud-b", "query": "what did you just say",
                "dependencies": [[
                    "dependency_id": "prior-result",
                    "content_address": payloadSHA,
                    "reason": "restates the prior answer",
                ]],
            ],
            databaseURL: dbURL)
        print("[MCP-SETTLE-DEP] \(followUp)")
        let followUpID = try XCTUnwrap(followUp["settlement_id"] as? String)
        let declared = followUp["dependencies"] as? [[String: Any]]
        XCTAssertEqual(declared?.count, 1, "settle=\(followUp)")
        XCTAssertEqual(declared?.first?["content_address"] as? String, payloadSHA)
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM is_dependency_entries;"), "1",
                       "the declared source is a row in the authoritative store")

        // The producer identity is in the table, not only in the reply — this is
        // what stops another engine from inheriting the answer.
        let receipt = try HTTPServer.runMCPTool(
            name: "simigo_is_settlement",
            arguments: ["settlement_id": followUpID], databaseURL: dbURL)
        print("[MCP-SETTLE-RECEIPT] \(receipt)")
        let bindings = try XCTUnwrap(receipt["bindings"] as? [String: String])
        XCTAssertNotNil(bindings[SimiGoSettlementIdentityBinding.modelKey])
        XCTAssertNotNil(bindings[SimiGoSettlementIdentityBinding.tokenizerKey])
        XCTAssertEqual(
            (receipt["dependencies"] as? [[String: Any]])?.count, 1,
            "the declared dependency is readable back from the settlement: \(receipt)")

        // A declared source that is not a sealed object refuses the whole
        // settle: nothing is recorded, and the state is still settleable after.
        let unsealedState = try XCTUnwrap(
            try HTTPServer.runMCPTool(
                name: "simigo_es_begin",
                arguments: ["model": "cloud-model", "tokenizer": "cloud-tokenizer"],
                databaseURL: dbURL)["state_id"] as? String)
        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": unsealedState, "model": "cloud-model",
                "tokenizer": "cloud-tokenizer", "output": "unsourced",
                "dependencies": [["dependency_id": "doc-1", "content_address": "abc"]],
            ],
            databaseURL: dbURL))
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "2",
                       "an unsealed dependency leaves no settlement behind")
        let rescued = try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": unsealedState, "model": "cloud-model",
                "tokenizer": "cloud-tokenizer", "output": "unsourced",
            ],
            databaseURL: dbURL)
        XCTAssertEqual(rescued["validity"] as? String, "valid",
                       "the refused settle did not consume the state: \(rescued)")

        // One state settles once, and only under the engine it was begun with.
        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": stateID, "model": "cloud-model",
                "tokenizer": "cloud-tokenizer", "output": "again",
            ],
            databaseURL: dbURL))
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "3")
    }

    func testSettleWithoutBeginAndWrongModelFailClosed() throws {
        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": "never-begun", "model": "m",
                "tokenizer": "t", "output": "text",
            ],
            databaseURL: dbURL), "a settlement cannot precede its execution")

        let begun = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: ["model": "model-a", "tokenizer": "tok"],
            databaseURL: dbURL)
        let stateID = try XCTUnwrap(begun["state_id"] as? String)

        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": stateID, "model": "model-b",
                "tokenizer": "tok", "output": "text",
            ],
            databaseURL: dbURL), "two engines are not interchangeable on one state")
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "0")
    }

    func testBeginDoesNotServeSettledAnswerWithoutCurrentDemand() throws {
        let first = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "cloud-model", "tokenizer": "cloud-tokenizer",
                "session_id": "cloud-a", "query": "where is the exit",
            ],
            databaseURL: dbURL)
        let firstState = try XCTUnwrap(first["state_id"] as? String)
        let settled = try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": firstState, "model": "cloud-model",
                "tokenizer": "cloud-tokenizer", "output": "the exit is north",
                "session_id": "cloud-a", "query": "where is the exit",
            ],
            databaseURL: dbURL)

        let again = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "cloud-model", "tokenizer": "cloud-tokenizer",
                "session_id": "cloud-a", "query": "where is the exit",
            ],
            databaseURL: dbURL)
        // Printed before the unwrap: an XCTest failure here symbolicates from a
        // build under ~/Documents and can stall the whole window, so the raw
        // value must reach the log first.
        print("[MCP-REUSE] demand_published=\(settled["demand_id"] as? String ?? "") "
            + "demand_error=\(settled["demand_error"] as? String ?? "") "
            + "advancement=\(settled["advancement_id"] as? String ?? "") "
            + "reusable=\(again["reusable_answer"] as? [String: Any] ?? [:])")
        XCTAssertNotEqual(again["state_id"] as? String, firstState)
        // begin resolves no current demand, so it has no identity to gate a
        // historical answer on and must not serve one.
        XCTAssertTrue(again["reusable_answer"] is NSNull)

        // The answer is still recorded; only the unverified begin path refuses.
        let db = try SimiGoESISDatabase(url: dbURL, createIfNeeded: false)
        let answered = try XCTUnwrap(
            try db.answeredDemand(sessionID: "cloud-a", query: "where is the exit"))
        XCTAssertFalse(answered.answerSettlementID.isEmpty)
        db.close()

        // Another engine may not inherit it, and another scope is another question.
        let otherModel = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "other-model", "tokenizer": "cloud-tokenizer",
                "session_id": "cloud-a", "query": "where is the exit",
            ],
            databaseURL: dbURL)
        XCTAssertTrue(otherModel["reusable_answer"] is NSNull)
        let otherScope = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "cloud-model", "tokenizer": "cloud-tokenizer",
                "session_id": "cloud-b", "query": "where is the exit",
            ],
            databaseURL: dbURL)
        XCTAssertTrue(otherScope["reusable_answer"] is NSNull)

        // Asking is a read: no settlement and no reuse row was written for it.
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "1")
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM information_reuse_events;"), "0")
    }

    func testFailureIsAuditedAndNeverBecomesASettlement() throws {
        let begun = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: ["model": "cloud-model", "tokenizer": "cloud-tokenizer"],
            databaseURL: dbURL)
        let stateID = try XCTUnwrap(begun["state_id"] as? String)

        let failed = try HTTPServer.runMCPTool(
            name: "simigo_es_fail",
            arguments: [
                "state_id": stateID, "detail": "cloud API returned 529",
                "evidence": ["status": "529"],
            ],
            databaseURL: dbURL)
        XCTAssertEqual(failed["audit_persisted"] as? Bool, true)
        XCTAssertEqual(failed["settlement_id"] as? String, "",
                       "a failure never fabricates a settlement")
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "0")

        // The audit is append-only: a second attempt under the same execution id
        // is reported as a duplicate instead of overwriting the first record.
        let retry = try HTTPServer.runMCPTool(
            name: "simigo_es_fail",
            arguments: ["state_id": stateID, "detail": "again"],
            databaseURL: dbURL)
        XCTAssertEqual(retry["audit_persisted"] as? Bool, false)
        XCTAssertEqual(retry["failure_class"] as? String, "duplicate_execution_id")
    }

    // MARK: - Sourced settlement (D-2)
    //
    // The documented cloud-agent loop is search → settle citing that retrieval →
    // begin. Before D-2 the retrieval demand carried no session, so the settled
    // answer was authoritative but unfindable by `reusable_answer`.

    /// Registers a root, searches it under `session`, then settles the answer
    /// WITH the retrieval settlement as its source — the exact loop that used to
    /// skip the session-demand publish.
    @discardableResult
    private func settleSourcedAnswer(
        session: String, query: String, answer: String
    ) throws -> [String: Any] {
        let root = dir.appendingPathComponent("sourced-\(session)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("alpha\nneedle body\n".utf8)
            .write(to: root.appendingPathComponent("doc.md"))
        _ = try HTTPServer.runMCPTool(
            name: "simigo_root_register",
            arguments: ["path": root.path], databaseURL: dbURL)

        let search = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: ["query": query, "include_chat": false, "session_id": session],
            databaseURL: dbURL)
        let demandID = try XCTUnwrap(search["demand_id"] as? String)
        let retrievalID = try XCTUnwrap(search["retrieval_settlement_id"] as? String)
        XCTAssertFalse(retrievalID.isEmpty, "search=\(search)")
        // The demand row names its session in the existing schema: no migration.
        XCTAssertEqual(try rawText(
            "SELECT session_id FROM information_demands WHERE demand_id='\(demandID)';"),
            session)

        let begun = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: ["model": "cloud-model", "tokenizer": "cloud-tokenizer"],
            databaseURL: dbURL)
        let stateID = try XCTUnwrap(begun["state_id"] as? String)
        let settled = try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": stateID, "model": "cloud-model",
                "tokenizer": "cloud-tokenizer", "output": answer,
                "session_id": session, "query": query,
                "demand_id": demandID, "retrieval_settlement_id": retrievalID,
            ],
            databaseURL: dbURL)
        print("[MCP-SOURCED-SETTLE] demand=\(demandID) retrieval=\(retrievalID) "
            + "advancement=\(settled["advancement_id"] as? String ?? "") "
            + "reply=\(settled)")
        XCTAssertFalse(
            (settled["advancement_id"] as? String ?? "").isEmpty,
            "a sourced settle advances the retrieval demand: \(settled)")
        XCTAssertEqual(
            settled["demand_id"] as? String, "",
            "no session demand is published when the retrieval demand advanced")
        return [
            "demand_id": demandID,
            "retrieval_settlement_id": retrievalID,
            "settlement_id": settled["settlement_id"] as? String ?? "",
        ]
    }

    func testSourcedSettleIsRecordedButNotServedByBegin() throws {
        let query = "needle"
        let session = "cloud-sourced-a"
        let settled = try settleSourcedAnswer(
            session: session, query: query, answer: "the vault is behind the stairs")

        let again = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "cloud-model", "tokenizer": "cloud-tokenizer",
                "session_id": session, "query": query,
            ],
            databaseURL: dbURL)
        print("[MCP-SOURCED-REUSE] \(again["reusable_answer"] ?? "null")")
        XCTAssertTrue(
            again["reusable_answer"] is NSNull,
            "begin resolves no current demand and must not serve the answer: \(again)")

        // Same store, same schema: reopening it still finds the recorded answer.
        let reopened = try SimiGoESISDatabase(url: dbURL, createIfNeeded: false)
        let answered = try XCTUnwrap(
            try reopened.answeredDemand(sessionID: session, query: query))
        XCTAssertEqual(
            answered.answerSettlementID, settled["settlement_id"] as? String)
        reopened.close()
    }

    func testSourcedSettleIsNotReusableFromAnotherSession() throws {
        let query = "needle"
        try settleSourcedAnswer(
            session: "cloud-sourced-b", query: query, answer: "behind the stairs")

        let other = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "cloud-model", "tokenizer": "cloud-tokenizer",
                "session_id": "cloud-sourced-c", "query": query,
            ],
            databaseURL: dbURL)
        XCTAssertTrue(
            other["reusable_answer"] is NSNull,
            "another session is another question: \(other)")
    }

    // MARK: - Cross-path source identity (裁定 2)
    //
    // A retry, a second entry point, and a genuine update all reach the same
    // entrance. The declared source identity decides which one this call is:
    // the same source at the same revision is not a new settlement, and only an
    // explicit new revision may create a version.

    private func declaredSource(
        _ message: String, revision: Int = 1, turn: String = "turn-7",
        session: String = "qoder-window-1"
    ) -> [String: Any] {
        [
            "source_type": "agent_turn",
            "source_session_id": session,
            "source_turn_id": turn,
            "source_message_id": message,
            "source_revision": revision,
        ]
    }

    private func beginMCPState() throws -> String {
        let begun = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: ["model": "cloud-model", "tokenizer": "cloud-tokenizer"],
            databaseURL: dbURL)
        return try XCTUnwrap(begun["state_id"] as? String)
    }

    @discardableResult
    private func settleMCP(
        state: String, output: String, source: [String: Any] = [:],
        session: String = "cloud-identity", query: String = "where is the vault"
    ) throws -> [String: Any] {
        var arguments = source
        arguments["state_id"] = state
        arguments["model"] = "cloud-model"
        arguments["tokenizer"] = "cloud-tokenizer"
        arguments["output"] = output
        arguments["session_id"] = session
        arguments["query"] = query
        return try HTTPServer.runMCPTool(
            name: "simigo_es_settle", arguments: arguments, databaseURL: dbURL)
    }

    /// Every table an identical resubmission must leave untouched. Objects,
    /// summaries and indexes are included on purpose: an idempotent hit that
    /// only skipped `settlements` would still be a duplicate write elsewhere.
    private func writeCounters() throws -> [String: String] {
        var counts: [String: String] = [:]
        for table in [
            "settlements", "execution_states", "is_objects", "is_index_entries",
            "is_dependency_entries", "settlement_summaries",
            "settlement_source_identities", "settlement_operation_keys",
            "information_demands", "information_advancements",
        ] {
            counts[table] = try rawText("SELECT COUNT(*) FROM \(table);")
        }
        return counts
    }

    func testDeclaredSourceReplayReturnsTheExistingSettlement() throws {
        let source = declaredSource("msg-1")
        let first = try settleMCP(
            state: try beginMCPState(), output: "the vault is behind the stairs",
            source: source)
        print("[MCP-IDENTITY-FIRST] \(first)")
        let firstID = try XCTUnwrap(first["settlement_id"] as? String)
        let firstState = try XCTUnwrap(first["state_id"] as? String)
        XCTAssertEqual(first["reused"] as? Bool, false)

        // The retry's own execution state is begun BEFORE the baseline: an
        // execution state is per-request ES bookkeeping, not a settlement
        // write, so only the IS tables are expected to stay frozen.
        let replayState = try beginMCPState()
        let before = try writeCounters()

        // A retry through a fresh execution carries the same declared source:
        // it returns the existing settlement and writes nothing new.
        let replay = try settleMCP(
            state: replayState, output: "the vault is behind the stairs",
            source: source)
        print("[MCP-IDENTITY-REPLAY] \(replay)")
        XCTAssertEqual(replay["reused"] as? Bool, true)
        XCTAssertEqual(replay["settlement_id"] as? String, firstID)
        XCTAssertEqual(replay["state_id"] as? String, firstState,
                       "a replay returns the state that produced the result")
        XCTAssertEqual(try writeCounters(), before,
                       "an idempotent hit writes no settlement, object, index, summary or demand row")

        XCTAssertEqual(
            try rawText("SELECT COUNT(*) FROM settlement_source_identities WHERE source_message_id='msg-1';"),
            "1")
    }

    func testSameRevisionWithDifferentOutputIsRefusedAtomically() throws {
        let source = declaredSource("msg-2")
        _ = try settleMCP(
            state: try beginMCPState(), output: "first answer", source: source)

        // Begin the refused attempt first, for the same reason as the replay
        // test: its execution state is allowed, its IS writes are not.
        let refusedState = try beginMCPState()
        let before = try writeCounters()
        XCTAssertThrowsError(try settleMCP(
            state: refusedState, output: "a different answer", source: source)
        ) { error in
            XCTAssertTrue(
                String(describing: error).contains("different payload digest"),
                "got: \(error)")
        }
        XCTAssertEqual(try writeCounters(), before,
                       "a refused identity conflict leaves no partial write")

        // The refusal did not consume the execution: it can still settle, and
        // the retry was never mistaken for an update.
        let rescued = try settleMCP(
            state: refusedState, output: "a different answer")
        XCTAssertEqual(rescued["reused"] as? Bool, false)
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "2")
    }

    func testExplicitRevisionTwoCreatesALinkedVersion() throws {
        let first = try settleMCP(
            state: try beginMCPState(), output: "revision one answer",
            source: declaredSource("msg-3"))
        let firstID = try XCTUnwrap(first["settlement_id"] as? String)

        // Same source, explicitly declared new revision, new content: a new
        // version linked to the one it supersedes.
        let second = try settleMCP(
            state: try beginMCPState(), output: "revision two answer",
            source: declaredSource("msg-3", revision: 2))
        print("[MCP-IDENTITY-REV2] \(second)")
        XCTAssertEqual(second["reused"] as? Bool, false)
        let secondID = try XCTUnwrap(second["settlement_id"] as? String)
        XCTAssertNotEqual(secondID, firstID)
        XCTAssertEqual(try rawText("""
        SELECT previous_settlement_id FROM settlement_source_identities
        WHERE source_message_id='msg-3' AND source_revision=2;
        """), firstID)
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "2")

        // Version numbers are never inferred or skipped...
        XCTAssertThrowsError(try settleMCP(
            state: try beginMCPState(), output: "revision four answer",
            source: declaredSource("msg-3", revision: 4))
        ) { error in
            XCTAssertTrue(
                String(describing: error).contains("next declared revision is 3"),
                "got: \(error)")
        }
        // ...and a declared update must actually change the result.
        XCTAssertThrowsError(try settleMCP(
            state: try beginMCPState(), output: "revision two answer",
            source: declaredSource("msg-3", revision: 3))
        ) { error in
            XCTAssertTrue(
                String(describing: error).contains("must change the result"),
                "got: \(error)")
        }
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "2")
    }

    func testDifferentSourceMessagesWithIdenticalTextAreBothKept() throws {
        let text = "the same words from two different turns"
        let first = try settleMCP(
            state: try beginMCPState(), output: text,
            source: declaredSource("msg-a"))
        let second = try settleMCP(
            state: try beginMCPState(), output: text,
            source: declaredSource("msg-b"))
        XCTAssertEqual(first["reused"] as? Bool, false)
        XCTAssertEqual(second["reused"] as? Bool, false,
                       "different sources are never merged by text equality")
        XCTAssertNotEqual(
            first["settlement_id"] as? String, second["settlement_id"] as? String)
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "2")
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlement_source_identities;"), "2")
        XCTAssertEqual(try rawText("""
        SELECT COUNT(DISTINCT payload_digest) FROM settlement_source_identities;
        """), "1", "the payloads are identical; only the declared sources differ")
    }

    // MARK: - Chat grouping

    func testInformationScopeGroupsByConversationOpening() {
        func scope(_ opening: String, _ lastUser: String) -> String {
            HTTPServer.informationScope(agentId: "agent", messages: [
                .object(["role": .string("system"), "content": .string("sys")]),
                .object(["role": .string("user"), "content": .string(opening)]),
                .object(["role": .string("assistant"), "content": .string("a")]),
                .object(["role": .string("user"), "content": .string(lastUser)]),
            ])
        }
        XCTAssertEqual(scope("first", "one"), scope("first", "two"),
                       "later turns stay in the same information scope")
        XCTAssertNotEqual(scope("first", "one"), scope("second", "one"),
                          "a different conversation is a different scope")
        XCTAssertTrue(scope("first", "one").hasPrefix("info-"))
    }

    func testBeginTokenizerIdentityIsFixedAcrossResumeAndSettle() throws {
        let db = try SimiGoESISDatabase(url: dbURL)
        try db.runMigrations()
        defer { db.close() }
        let stateID = "tokenizer-bound-state"
        let begun = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "state_id": stateID,
                "model": "cloud-model",
                "tokenizer": "tokenizer-a",
            ],
            databaseURL: dbURL)
        XCTAssertEqual(begun["state_id"] as? String, stateID)
        XCTAssertEqual(
            try db.executionStateTokenizerIdentity(stateID), "tokenizer-a")

        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "state_id": stateID,
                "model": "cloud-model",
                "tokenizer": "tokenizer-b",
            ],
            databaseURL: dbURL),
            "resuming with a different tokenizer must fail closed")

        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": stateID,
                "model": "cloud-model",
                "tokenizer": "tokenizer-b",
                "output": "wrong tokenizer",
            ],
            databaseURL: dbURL),
            "settlement identity must match the tokenizer fixed at begin")
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "0")

        let settled = try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": stateID,
                "model": "cloud-model",
                "tokenizer": "tokenizer-a",
                "output": "correct tokenizer",
            ],
            databaseURL: dbURL)
        XCTAssertEqual(settled["validity"] as? String, "valid")
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "1")
    }

    func testMCPStateSurvivesNativeGraphReconciliationAndKeepsTokenizerBinding() throws {
        let db = try SimiGoESISDatabase(url: dbURL)
        try db.runMigrations()
        let stateID = "mcp-graph-isolation-\(UUID().uuidString)"
        let begun = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "state_id": stateID,
                "model": "cloud-model",
                "tokenizer": "tokenizer-a",
            ],
            databaseURL: dbURL)
        XCTAssertEqual(begun["state_id"] as? String, stateID)
        XCTAssertEqual(
            try rawText("SELECT graph_managed FROM execution_states WHERE state_id='\(stateID)';"),
            "0", "MCP-created ES is external to the native graph")

        // An empty native graph may remove native-owned states, but must not
        // erase an unsettled MCP execution it does not own.
        try db.writeGraph(states: [], checkpoints: [])
        XCTAssertEqual(
            try rawText("SELECT COUNT(*) FROM execution_states WHERE state_id='\(stateID)';"),
            "1", "graph reconciliation must leave external MCP ES intact")
        db.close()

        // Reopen from SQLite alone, then prove the begin-time tokenizer remains
        // authoritative: a different tokenizer cannot claim the surviving ES.
        let reopened = try SimiGoESISDatabase(url: dbURL, createIfNeeded: false)
        XCTAssertEqual(try reopened.executionStateTokenizerIdentity(stateID), "tokenizer-a")
        reopened.close()

        let resumed = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "state_id": stateID,
                "model": "cloud-model",
                "tokenizer": "tokenizer-a",
            ],
            databaseURL: dbURL)
        XCTAssertEqual(resumed["resumed"] as? Bool, true)
        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "state_id": stateID,
                "model": "cloud-model",
                "tokenizer": "tokenizer-b",
            ],
            databaseURL: dbURL),
            "native graph sync must not make the MCP state look newly created")
        XCTAssertEqual(
            try rawText("SELECT tokenizer_identity FROM execution_states WHERE state_id='\(stateID)';"),
            "tokenizer-a")
    }

    func testLegacyMCPStateWithoutTokenizerCannotSettle() throws {
        let db = try SimiGoESISDatabase(url: dbURL)
        try db.runMigrations()
        defer { db.close() }
        try db.recordExecutionState(
            id: "legacy-no-tokenizer", parentID: nil,
            modelIdentity: "cloud-model", position: 0,
            continuationID: "legacy", anchor: "",
            lifecycle: "active", createdAt: Date())

        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": "legacy-no-tokenizer",
                "model": "cloud-model",
                "tokenizer": "caller-asserted",
                "output": "must refuse",
            ],
            databaseURL: dbURL),
            "an absent begin-time tokenizer is not a wildcard")
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "0")
    }
}
