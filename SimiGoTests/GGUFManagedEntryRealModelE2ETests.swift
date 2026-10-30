import Foundation
import XCTest
import SimiGoRuntimeContract

@testable import SimiGo

/// Real llama.cpp engine, real GGUF weights, product entry.
///
/// Unlike `GGUFManagedEntryHTTPTests` (stub engine), this class spawns the
/// actual `llama-server` through `ManagedGGUFRuntime` and drives a real
/// generation. It is the only layer that can prove the launch arguments,
/// engine readiness, real SSE shape and real usage survive the new wiring.
///
/// Gated, because it costs a model load and real GPU work:
///   * `SIMIGO_GGUF_E2E_MODEL` — absolute path to a `.gguf` checkpoint,
///   * `SIMIGO_GGUF_E2E_BIN` — absolute path to a `llama-server` executable,
///   * the three isolated roots (`SIMIGO_HOME`, `SIMIGO_CACHE_ROOT`,
///     `SIMIGO_STATE_GRAPH_STORE`) injected by
///     `tools/make_isolated_xctestrun.py`, so no real user state is touched.
final class GGUFManagedEntryRealModelE2ETests: XCTestCase {

    private var isolationRoot: URL!

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty, home.hasPrefix("/"),
            env["SIMIGO_STATE_GRAPH_STORE"]?.isEmpty == false,
            env["SIMIGO_CACHE_ROOT"]?.isEmpty == false
        else {
            throw XCTSkip(
                "isolated roots not injected: run through tools/make_isolated_xctestrun.py "
                + "so no real user state is touched")
        }
        isolationRoot = URL(
            fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
        XCTAssertTrue(
            SimiGoPaths.databaseURL.path.hasPrefix(isolationRoot.path),
            "authoritative store resolves outside the isolation root")
    }

    @MainActor
    func testRealGGUFTurnSettlesAndReusesThroughManagedEntry() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let model = env["SIMIGO_GGUF_E2E_MODEL"],
            FileManager.default.fileExists(atPath: model)
        else {
            throw XCTSkip("SIMIGO_GGUF_E2E_MODEL not injected")
        }
        guard let binary = env["SIMIGO_GGUF_E2E_BIN"],
            FileManager.default.isExecutableFile(atPath: binary)
        else {
            throw XCTSkip("SIMIGO_GGUF_E2E_BIN not injected")
        }

        var config = ModelConfig()
        config.ctxSize = 4096
        // LFM2.5 spends ~120 tokens on `reasoning_content` before any
        // `content` delta. A small budget caps the turn mid-thinking and the
        // wire correctly reports `length` — that is not what this test checks.
        config.maxTokens = 512
        let backend = BackendConfig(
            name: "llama.cpp",
            customExecutable: binary,
            args: BackendConfig.llama.args,
            healthEndpoint: "/health",
            startupTimeout: 600,
            kind: .gguf)

        let runtime = ManagedGGUFRuntime(config: config, backendConfig: backend)
        let port = Int(try GGUFRestFixture.freePort())
        try await runtime.start(ModelInfo(path: model, kind: .gguf), port: port)
        addTeardownBlock { await runtime.stop() }
        try GGUFRestFixture.waitUntilListening(port: port)

        let session = "gguf-real-\(UUID().uuidString)"
        let query = "只回答两个字：收到"
        let first = try await sendChat(to: port, session: session, query: query)

        XCTAssertEqual(first.status, 200)
        let choices = first.body["choices"] as? [[String: Any]]
        XCTAssertEqual(
            choices?.first?["finish_reason"] as? String, "stop",
            "a real turn that ends normally must reach the wire as stop")
        let text = (assistantContent(first.body) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(text.isEmpty, "the real engine produced no text")

        let db = try SimiGoESISDatabase(url: SimiGoPaths.databaseURL)
        let messages = try db.listChatMessages(sessionID: session)
        XCTAssertEqual(messages.map(\.role), ["user", "assistant"])
        // The settlement writes the canonical (trimmed) answer; llama.cpp's
        // content for this model starts with a newline before the template's
        // answer section, so the wire and the record differ only by that.
        XCTAssertEqual(messages.last?.content, text)

        let answered = try XCTUnwrap(
            db.answeredDemand(sessionID: session, query: query),
            "a complete real turn settles its demand")
        XCTAssertEqual(
            try db.settlementReceipt(answered.answerSettlementID)?.validity, "valid")
        XCTAssertNotNil(try db.currentChatStateID(sessionID: session))

        let loop = SimiGoInformationLoop(database: db)
        let resolution = try loop.resolve(
            .init(
                sessionID: session, query: query, includeChat: true,
                chatSessionIDs: [session]))
        XCTAssertTrue(
            resolution.hits.contains { $0.itemID.hasPrefix("chat:\(session)/") },
            "the settled real answer becomes retrievable history")

        // Identical second ask: served by the settlement, no engine work.
        let second = try await sendChat(to: port, session: session, query: query)
        XCTAssertEqual(second.status, 200)
        let simigo = second.body["simigo"] as? [String: Any]
        XCTAssertEqual(simigo?["answer_reuse"] as? Bool, true)
        XCTAssertEqual(simigo?["model_calls"] as? Int, 0)
        XCTAssertEqual(assistantContent(second.body), text)
    }

    // MARK: - Wire

    private func sendChat(
        to port: Int, session: String, query: String
    ) async throws -> (status: Int, body: [String: Any]) {
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Cold prefill on a real 24B checkpoint is minutes, not seconds.
        request.timeoutInterval = 900
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelName(from: ProcessInfo.processInfo.environment["SIMIGO_GGUF_E2E_MODEL"] ?? ""),
            "session_id": session,
            "messages": [["role": "user", "content": query]],
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, json)
    }

    private func assistantContent(_ body: [String: Any]) -> String? {
        let choices = body["choices"] as? [[String: Any]]
        return (choices?.first?["message"] as? [String: Any])?["content"] as? String
    }
}