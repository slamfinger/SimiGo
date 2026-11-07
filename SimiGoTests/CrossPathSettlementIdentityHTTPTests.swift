import Foundation
import SQLite3
import XCTest
import LOCALBCore
import SimiGoRuntimeContract

@testable import SimiGo

/// 裁定 2 acceptance on the real app entrance: a model turn and an MCP settle
/// that declare the SAME source identity and submit the SAME result are one
/// submission, however many times or from however many entry points they
/// arrive. Every assertion reads the authoritative store — settlements, source
/// identities, sealed objects, index entries and summaries — not only
/// `chat_messages`.
///
/// The only substituted component is generation (a counter, never a model).
/// Runs only with the three isolated roots injected (`SIMIGO_HOME`,
/// `SIMIGO_CACHE_ROOT`, `SIMIGO_STATE_GRAPH_STORE`); otherwise XCTSkip.
final class CrossPathSettlementIdentityHTTPTests: XCTestCase {

    private var modelPath: String!
    private var host: LOCALBAuthorizedE2E.Host!
    private var stub: Stub!

    private final class Stub: @unchecked Sendable {
        private let lock = NSLock()
        private var _generate = 0
        private var _text = ""

        func bump() { lock.withLock { _generate += 1 } }
        var generate: Int { lock.withLock { _generate } }

        var text: String {
            get { lock.withLock { _text } }
            set { lock.withLock { _text = newValue } }
        }
    }

    /// The declaration a client makes about where a result came from. The five
    /// fields travel identically on both wires — JSON metadata on Chat, tool
    /// arguments on MCP — so the common entrance sees one submission shape.
    private struct SourceDeclaration {
        let type: String
        let session: String
        let turn: String
        let message: String
        let revision: Int

        var chatMetadata: [String: Any] {
            [
                "simigo_source_type": type,
                "simigo_source_session_id": session,
                "simigo_source_turn_id": turn,
                "simigo_source_message_id": message,
                "simigo_source_revision": revision,
            ]
        }

        var mcpArguments: [String: Any] {
            [
                "source_type": type,
                "source_session_id": session,
                "source_turn_id": turn,
                "source_message_id": message,
                "source_revision": revision,
            ]
        }
    }

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty,
              let graphStore = env["SIMIGO_STATE_GRAPH_STORE"], !graphStore.isEmpty,
              let cache = env["SIMIGO_CACHE_ROOT"], !cache.isEmpty,
              home.hasPrefix("/"), graphStore.hasPrefix("/"), cache.hasPrefix("/") else {
            throw XCTSkip(
                "isolated roots not injected: run through tools/make_isolated_xctestrun.py "
                + "so no real model or user state is touched")
        }
        XCTAssertTrue(
            SimiGoPaths.databaseURL.path.hasPrefix(
                (home as NSString).standardizingPath),
            "authoritative store resolves outside the isolation root")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoCrossPath-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"model_type":"cross-path-identity-model-free-stand-in"}"#.utf8)
            .write(to: dir.appendingPathComponent("tokenizer.adapter.json"))
        modelPath = dir.path

        host = try LOCALBAuthorizedE2E.makeHost()
        stub = Stub()
    }

    override func tearDown() {
        if let modelPath { try? FileManager.default.removeItem(atPath: modelPath) }
        stub = nil
        host = nil
        super.tearDown()
    }

    // MARK: - Harness

    @MainActor
    private func withServer(
        port: Int, _ run: () async throws -> Void
    ) async throws {
        let stub = self.stub!
        let identity = SimiGoProducerIdentity.identity(fromPath: modelPath)
        let server = HTTPServer(
            port: port,
            modelId: "cross-path-identity-http-test",
            generateHandler: { _, _, _, _, _, _, _, onChunk, _, _ in
                stub.bump()
                let text = stub.text
                onChunk(text)
                return GenerationResult(text: text, usage: nil, completion: .complete)
            },
            forkBranchHandler: { _, _, _, target in
                SessionCacheMetadata(
                    storageKey: "t/\(target)", modelId: "cross-path-identity-http-test",
                    savedAt: Date(), history: [])
            },
            deleteBranchHandler: { _, _, _, _ in
                BranchDeletionOutcome(
                    deletedBranch: "", hadLiveSession: false,
                    hadCheckpointFile: false, generation: 1,
                    remainingLiveBranches: [],
                    remainingCheckpointBranches: [])
            },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true },
            informationTurnProducer: {
                InformationTurnProducer(
                    modelIdentity: identity.model, identity: identity)
            }
        )
        server.configureLOCALBTransport(identity: host.identity)
        server.configureLOCALBRequestAuthorization(
            coordinator: host.coordinator,
            trustedCheckpoint: host.checkpointProvider)
        try server.start()
        try? await Task.sleep(nanoseconds: 200_000_000)
        defer { server.stop() }
        try await run()
    }

    private struct ChatOutcome {
        let status: Int
        let body: [String: Any]
        let generate: Int

        var text: String {
            let message = (body["choices"] as? [[String: Any]])?.first?["message"]
                as? [String: Any]
            return message?["content"] as? String ?? ""
        }

        var simigo: [String: Any]? { body["simigo"] as? [String: Any] }
    }

    @MainActor
    private func chat(
        port: Int, session: String, input: String, declaration: SourceDeclaration
    ) async throws -> ChatOutcome {
        let stub = self.stub!
        let body: [String: Any] = [
            "model": "cross-path-identity-http-test",
            "messages": [["role": "user", "content": input]],
            "session_id": session,
            "stream": false,
            "metadata": declaration.chatMetadata,
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        var lastError: Error?
        for _ in 0..<3 {
            do {
                let result = try await LOCALBAuthorizedE2E.send(
                    host: host, port: port, method: "POST",
                    path: "/v1/chat/completions",
                    contentType: "application/json", body: payload)
                let object = (try? JSONSerialization.jsonObject(with: result.0))
                    as? [String: Any] ?? [:]
                return ChatOutcome(
                    status: result.1.statusCode, body: object, generate: stub.generate)
            } catch let error as URLError
            where error.code == .cannotConnectToHost || error.code == .networkConnectionLost {
                lastError = error
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        XCTFail("request never reached the server: \(String(describing: lastError))")
        throw URLError(.cannotConnectToHost)
    }

    /// A cloud agent's MCP side: begin an execution under its own engine
    /// identity, then settle. `session`/`query` stay empty unless the scenario
    /// needs a conversation demand published.
    private func mcpSettle(
        state: String, output: String, declaration: SourceDeclaration
    ) throws -> [String: Any] {
        var arguments = declaration.mcpArguments
        arguments["state_id"] = state
        arguments["model"] = "cross-path-cloud-model"
        arguments["tokenizer"] = "cross-path-cloud-tokenizer"
        arguments["output"] = output
        return try HTTPServer.runMCPTool(
            name: "simigo_es_settle", arguments: arguments,
            databaseURL: SimiGoPaths.databaseURL)
    }

    private func beginMCPState() throws -> String {
        let begun = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "cross-path-cloud-model",
                "tokenizer": "cross-path-cloud-tokenizer",
            ],
            databaseURL: SimiGoPaths.databaseURL)
        return try XCTUnwrap(begun["state_id"] as? String)
    }

    private func query(_ sql: String) throws -> String {
        var handle: OpaquePointer?
        guard sqlite3_open(SimiGoPaths.databaseURL.path, &handle) == SQLITE_OK else {
            sqlite3_close(handle)
            throw NSError(domain: "CrossPath", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "cannot open \(SimiGoPaths.databaseURL.path)",
            ])
        }
        defer { sqlite3_close(handle) }
        sqlite3_busy_timeout(handle, 5_000)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "CrossPath", code: 2, userInfo: [
                NSLocalizedDescriptionKey:
                    "cannot prepare: \(sql) — \(String(cString: sqlite3_errmsg(handle)))",
            ])
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return "" }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
    }

    private func settlementID(forMessage message: String) throws -> String {
        let id = try query("""
        SELECT settlement_id FROM settlement_source_identities
        WHERE source_message_id='\(message)';
        """)
        XCTAssertFalse(id.isEmpty, "no settlement carries source message '\(message)'")
        return id
    }

    private func stateID(of settlementID: String) throws -> String {
        try query("""
        SELECT state_id FROM settlements WHERE settlement_id='\(settlementID)';
        """)
    }

    /// Knowledge actually reachable by an agent: the search runs through the
    /// real MCP retrieval entrance and returns only citable settlement items
    /// (chat rows excluded so the count is about settled knowledge, not the
    /// conversation transcript).
    private func retrievableSettlements(for token: String) throws -> [[String: Any]] {
        let search = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: ["query": token, "include_chat": false],
            databaseURL: SimiGoPaths.databaseURL)
        let items = try XCTUnwrap(search["items"] as? [[String: Any]])
        return items.filter { $0["kind"] as? String == "settlement" }
    }

    // MARK: - Scenario 1: a model retry settles once

    @MainActor
    func testChatRetryWithTheSameDeclarationSettlesOnce() async throws {
        let port = 59_383
        let session = "cross-retry-\(UUID().uuidString)"
        let declaration = SourceDeclaration(
            type: "agent_turn", session: "qoder-window-retry",
            turn: "turn-1", message: "msg-retry", revision: 1)
        stub.text = "ZEBRA-RETRY-31F"

        try await withServer(port: port) {
            let first = try await chat(
                port: port, session: session, input: "where is the vault",
                declaration: declaration)
            XCTAssertEqual(first.status, 200, "\(first.body)")
            XCTAssertEqual(first.text, stub.text)
            XCTAssertEqual(first.generate, 1)
            let settlement = try settlementID(forMessage: "msg-retry")

            // The client retries the same submission in the same conversation.
            // The Information Space already holds a settled answer for this
            // question, so the retry never reaches the model and writes no
            // second settlement.
            let retry = try await chat(
                port: port, session: session, input: "where is the vault",
                declaration: declaration)
            XCTAssertEqual(retry.status, 200)
            XCTAssertEqual(retry.generate, 1, "a retry calls no model")
            let reuse = try XCTUnwrap(retry.simigo, "\(retry.body)")
            XCTAssertEqual(reuse["answer_reuse"] as? Bool, true)
            XCTAssertEqual(reuse["model_calls"] as? Int, 0)
            XCTAssertEqual(reuse["settlement_id"] as? String, settlement,
                           "the retry is served from the one settled result")

            XCTAssertEqual(try query("""
            SELECT COUNT(*) FROM settlement_source_identities
            WHERE source_message_id='msg-retry';
            """), "1")
            XCTAssertEqual(try query("""
            SELECT COUNT(*) FROM settlements s
            JOIN settlement_source_identities i ON i.settlement_id=s.settlement_id
            WHERE i.source_message_id='msg-retry';
            """), "1")
            XCTAssertEqual(try query("""
            SELECT COUNT(*) FROM settlement_summaries
            WHERE settlement_id='\(settlement)';
            """), "1")
            XCTAssertEqual(try query("""
            SELECT COUNT(*) FROM is_index_entries
            WHERE srs_identity='settlement:\(settlement)';
            """), "1")

            // Retrieval sees one answer, not one per submission.
            let retrievable = try retrievableSettlements(
                for: "ZEBRA-RETRY-31F")
            XCTAssertEqual(
                retrievable.compactMap { $0["item_id"] as? String },
                ["settlement:\(settlement)"],
                "a retried submission stays a single citable answer")
        }
    }

    // MARK: - Scenario 3: model first, MCP replay

    @MainActor
    func testModelThenMCPReplaySettlesOnce() async throws {
        let port = 59_384
        let session = "cross-model-mcp-\(UUID().uuidString)"
        let declaration = SourceDeclaration(
            type: "agent_turn", session: "qoder-window-cross",
            turn: "turn-2", message: "msg-model-then-mcp", revision: 1)
        stub.text = "QUARTZ-MODEL-MCP-72B"

        try await withServer(port: port) {
            let generated = try await chat(
                port: port, session: session, input: "where is the anvil",
                declaration: declaration)
            XCTAssertEqual(generated.status, 200)
            let settlement = try settlementID(forMessage: "msg-model-then-mcp")
            let chatState = try stateID(of: settlement)
            let object = try query("""
            SELECT payload_digest FROM settlement_source_identities
            WHERE source_message_id='msg-model-then-mcp';
            """)

            // The cloud agent reports the same source and the same result over
            // MCP. That is the model turn's submission arriving again, not a
            // second piece of knowledge.
            let replay = try mcpSettle(
                state: try beginMCPState(), output: stub.text, declaration: declaration)
            print("[CROSS-MODEL-MCP] settlement=\(settlement) chat_state=\(chatState) "
                + "object=\(object) reply=\(replay)")
            XCTAssertEqual(replay["reused"] as? Bool, true)
            XCTAssertEqual(replay["settlement_id"] as? String, settlement)
            XCTAssertEqual(replay["state_id"] as? String, chatState,
                           "the replay returns the state that produced the result")

            XCTAssertEqual(try query("""
            SELECT COUNT(*) FROM settlement_source_identities
            WHERE source_message_id='msg-model-then-mcp';
            """), "1")
            XCTAssertEqual(try query("""
            SELECT COUNT(*) FROM settlements s
            JOIN settlement_source_identities i ON i.settlement_id=s.settlement_id
            WHERE i.source_message_id='msg-model-then-mcp';
            """), "1")
            XCTAssertEqual(try query("""
            SELECT COUNT(*) FROM is_objects WHERE object_id='\(object)';
            """), "1")
            XCTAssertEqual(try query("""
            SELECT COUNT(*) FROM settlement_summaries
            WHERE settlement_id='\(settlement)';
            """), "1")
            XCTAssertEqual(try query("""
            SELECT COUNT(*) FROM is_index_entries
            WHERE srs_identity='settlement:\(settlement)';
            """), "1")
        }
    }

    // MARK: - Scenario 4: MCP first, model replay

    @MainActor
    func testMCPThenModelReplaySettlesOnce() async throws {
        let port = 59_385
        let session = "cross-mcp-model-\(UUID().uuidString)"
        let declaration = SourceDeclaration(
            type: "agent_turn", session: "qoder-window-cross",
            turn: "turn-3", message: "msg-mcp-then-model", revision: 1)
        stub.text = "VIPER-MCP-MODEL-08C"

        try await withServer(port: port) {
            let settled = try mcpSettle(
                state: try beginMCPState(), output: stub.text, declaration: declaration)
            XCTAssertEqual(settled["reused"] as? Bool, false)
            let settlement = try XCTUnwrap(settled["settlement_id"] as? String)
            let cloudState = try XCTUnwrap(settled["state_id"] as? String)

            // The same source and result now arrive through the model wire.
            // Generation still happens (this conversation never asked the
            // question), but the result is the one already settled.
            let generated = try await chat(
                port: port, session: session, input: "where is the anvil",
                declaration: declaration)
            XCTAssertEqual(generated.status, 200)
            XCTAssertEqual(generated.text, stub.text)
            XCTAssertEqual(generated.generate, 1)

            let store = ExecutionStateGraphStore()
            let db = try XCTUnwrap(store.esis)
            XCTAssertEqual(
                try db.currentChatStateID(sessionID: session), cloudState,
                "the model turn reused the settled result instead of creating a "
                + "second settlement")

            XCTAssertEqual(try query("""
            SELECT COUNT(*) FROM settlement_source_identities
            WHERE source_message_id='msg-mcp-then-model';
            """), "1")
            XCTAssertEqual(try query("""
            SELECT COUNT(*) FROM settlements s
            JOIN settlement_source_identities i ON i.settlement_id=s.settlement_id
            WHERE i.source_message_id='msg-mcp-then-model';
            """), "1")
            XCTAssertEqual(try query("""
            SELECT COUNT(*) FROM is_index_entries
            WHERE srs_identity='settlement:\(settlement)';
            """), "1")
        }
    }

    // MARK: - Scenario 5: different sources, identical text, both kept

    @MainActor
    func testDifferentSourcesWithIdenticalTextKeepBothSettlements() async throws {
        let port = 59_386
        let session = "cross-distinct-\(UUID().uuidString)"
        let first = SourceDeclaration(
            type: "agent_turn", session: "qoder-window-a",
            turn: "turn-4", message: "msg-distinct-a", revision: 1)
        let second = SourceDeclaration(
            type: "agent_turn", session: "qoder-window-b",
            turn: "turn-4", message: "msg-distinct-b", revision: 1)
        stub.text = "JADE-SHARED-9A4"

        try await withServer(port: port) {
            let generated = try await chat(
                port: port, session: session, input: "what is the shared text",
                declaration: first)
            XCTAssertEqual(generated.status, 200)
            let firstSettlement = try settlementID(forMessage: "msg-distinct-a")

            let other = try mcpSettle(
                state: try beginMCPState(), output: stub.text, declaration: second)
            XCTAssertEqual(other["reused"] as? Bool, false,
                           "another source with the same text is another submission")
            let secondSettlement = try XCTUnwrap(other["settlement_id"] as? String)
            XCTAssertNotEqual(secondSettlement, firstSettlement)

            XCTAssertEqual(try query("""
            SELECT COUNT(*) FROM settlement_source_identities
            WHERE source_message_id IN ('msg-distinct-a','msg-distinct-b');
            """), "2")
            XCTAssertEqual(try query("""
            SELECT COUNT(DISTINCT s.settlement_id) FROM settlements s
            JOIN settlement_source_identities i ON i.settlement_id=s.settlement_id
            WHERE i.source_message_id IN ('msg-distinct-a','msg-distinct-b');
            """), "2")
            XCTAssertEqual(try query("""
            SELECT COUNT(DISTINCT payload_digest) FROM settlement_source_identities
            WHERE source_message_id IN ('msg-distinct-a','msg-distinct-b');
            """), "1", "the payloads are identical; only the sources differ")

            // Retrieval keeps both submissions: identical text is not a reason
            // to erase either source's knowledge.
            let shared = try retrievableSettlements(
                for: "JADE-SHARED-9A4")
            XCTAssertEqual(
                Set(shared.compactMap { $0["item_id"] as? String }),
                Set(["settlement:\(firstSettlement)",
                     "settlement:\(secondSettlement)"]),
                "both sources stay citable even though their text is identical")
        }
    }

    // MARK: - Scenario 6: concurrent dual entry settles exactly once

    @MainActor
    func testConcurrentChatAndMCPEntrySettleExactlyOnce() async throws {
        let port = 59_387
        let session = "cross-concurrent-\(UUID().uuidString)"
        let declaration = SourceDeclaration(
            type: "agent_turn", session: "qoder-window-c",
            turn: "turn-5", message: "msg-concurrent", revision: 1)
        stub.text = "ONYX-CONCURRENT-5E2"

        try await withServer(port: port) {
            let mcpState = try beginMCPState()
            let text = stub.text
            async let chatOutcome = chat(
                port: port, session: session, input: "which answer wins",
                declaration: declaration)
            async let mcpOutcome = mcpSettle(
                state: mcpState, output: text, declaration: declaration)

            let generated = try await chatOutcome
            let settled = try await mcpOutcome
            print("[CROSS-CONCURRENT] chat=\(generated.body) mcp=\(settled)")

            XCTAssertEqual(generated.status, 200)
            XCTAssertEqual(generated.text, text)

            let settlement = try settlementID(forMessage: "msg-concurrent")
            let object = try query("""
            SELECT payload_digest FROM settlement_source_identities
            WHERE source_message_id='msg-concurrent';
            """)
            XCTAssertEqual(try query("""
            SELECT COUNT(*) FROM settlement_source_identities
            WHERE source_message_id='msg-concurrent';
            """), "1", "two concurrent entries produced one source identity")
            XCTAssertEqual(try query("""
            SELECT COUNT(*) FROM settlements s
            JOIN settlement_source_identities i ON i.settlement_id=s.settlement_id
            WHERE i.source_message_id='msg-concurrent';
            """), "1", "two concurrent entries produced one settlement")
            XCTAssertEqual(try query("""
            SELECT COUNT(*) FROM is_objects WHERE object_id='\(object)';
            """), "1")
            XCTAssertEqual(try query("""
            SELECT COUNT(*) FROM settlement_summaries
            WHERE settlement_id='\(settlement)';
            """), "1")
            XCTAssertEqual(try query("""
            SELECT COUNT(*) FROM is_index_entries
            WHERE srs_identity='settlement:\(settlement)';
            """), "1")

            // Whichever entry lost the race must have landed on the winner's
            // settlement rather than writing a second one.
            let store = ExecutionStateGraphStore()
            let db = try XCTUnwrap(store.esis)
            let chatState = try db.currentChatStateID(sessionID: session)
            let mcpReused = (settled["reused"] as? Bool) == true
            XCTAssertEqual(
                mcpReused, chatState != mcpState,
                "exactly one of the two entries won: reused=\(mcpReused) "
                    + "chat_state=\(chatState ?? "nil") mcp_state=\(mcpState)")
        }
    }
}
