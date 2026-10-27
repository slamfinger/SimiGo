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
            generateHandler: { _, _, _, _, _, _, _, _, _ in
                GenerationResult(text: "", usage: nil)
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
            arguments: ["query": "needle", "include_chat": false],
            databaseURL: dbURL)
        let items = search["items"] as? [[String: Any]]
        XCTAssertEqual(items?.count, 1)
        XCTAssertEqual(items?.first?["text"] as? String, "needle body")
        XCTAssertEqual(items?.first?["kind"] as? String, "file")
        XCTAssertEqual(search["reused"] as? Bool, false)

        // The same demand reuses its settled result, reading no new bytes.
        let again = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: ["query": "needle", "include_chat": false],
            databaseURL: dbURL)
        XCTAssertEqual(again["reused"] as? Bool, true)
        XCTAssertEqual(again["demand_id"] as? String, search["demand_id"] as? String)

        // A changed file fails digest verification and stops being cited.
        try Data("different\n".utf8)
            .write(to: root.appendingPathComponent("doc.md"))
        let afterChange = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: ["query": "needle", "include_chat": false],
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
}
