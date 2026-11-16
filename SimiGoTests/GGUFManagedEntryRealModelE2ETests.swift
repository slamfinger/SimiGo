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
            ManagedPaths.databaseURL.path.hasPrefix(isolationRoot.path),
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

        let db = try ESISDatabase(url: ManagedPaths.databaseURL)
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

        let loop = InformationLoop(database: db)
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

    /// Zero-call settlement consumption against the REAL engine: a settlement
    /// that a real llama.cpp turn produced is served back with no engine work,
    /// and the engine's own prompt cells are untouched by the consumption.
    ///
    /// The reuse contract is declared BY THIS TEST. `declareSettlementReuseContract`
    /// has no non-test caller in the product, so a real chat turn's settlement is
    /// not consumable on its own today — this arm proves the real carrier serves a
    /// DECLARED contract with zero engine calls, and does not claim turns
    /// auto-declare. Whether they should is a product decision, not a test's.
    @MainActor
    func testRealGGUFSettlementIsConsumedWithZeroEngineCalls() async throws {
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

        // 1) 真轮产生一个真结算。
        let session = "gguf-real-consume-\(UUID().uuidString)"
        let query = "只回答两个字：收到"
        let first = try await sendChat(to: port, session: session, query: query)
        XCTAssertEqual(first.status, 200)
        let text = (assistantContent(first.body) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(text.isEmpty, "the real engine produced no text")

        let db = try ESISDatabase(url: ManagedPaths.databaseURL)
        let answered = try XCTUnwrap(
            db.answeredDemand(sessionID: session, query: query),
            "a complete real turn settles its demand")
        let source = answered.answerSettlementID
        XCTAssertEqual(try db.settlementReceipt(source)?.validity, "valid")

        // 2) 声明复用契约（测试侧）。规范输入基底用一个与当轮无关的独立工作根，
        //    免得把 chat 侧写入混进 canonical digest。
        let workRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "GGUFRealConsumptionRoot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workRoot, withIntermediateDirectories: true)
        try Data("alpha beta gamma".utf8)
            .write(to: workRoot.appendingPathComponent("notes.md"))
        defer { try? FileManager.default.removeItem(at: workRoot) }
        let rootID = "gguf-real-work-" + UUID().uuidString.lowercased()
        _ = try db.settleWorkRootContents(rootID: rootID, rootURL: workRoot)
        _ = try db.declareSettlementReuseContract(
            settlementID: source,
            contractID: SettlementConsumption.Contract.contractID,
            demandClass: SettlementConsumption.Contract.demandClass,
            contractVersion: SettlementConsumption.Contract.version,
            query: query,
            rootIDs: [rootID])

        // 3) 正控：读零之前先从同一个引擎读到非零，否则「消费没有动引擎」是空断言。
        let before = try await slotPromptTokens(runtime)
        XCTAssertTrue(
            before.contains { $0 > 0 },
            "the real turn must have loaded a prompt into some slot")

        // 4) 显式消费。
        let o = try await postResponses(
            to: port,
            body: [
                "model": modelName(from: model),
                "input": "consume",
                "settlement_consumption": [
                    "source_settlement_id": source,
                    "contract": [
                        "id": SettlementConsumption.Contract.contractID,
                        "demand_class": SettlementConsumption.Contract.demandClass,
                        "version": SettlementConsumption.Contract.version,
                        "extract": SettlementConsumption.Contract.defaultExtractField,
                    ],
                    "query": query,
                    "root_ids": [rootID],
                ],
            ])
        XCTAssertEqual(o.status, 200, String(decoding: o.raw, as: UTF8.self))
        let payload = try XCTUnwrap(o.body["settlement_consumption"] as? [String: Any])
        XCTAssertEqual(payload["outcome"] as? String, "consumed")
        XCTAssertEqual(payload["model_calls"] as? Int, 0)
        XCTAssertEqual(payload["source_settlement_id"] as? String, source)
        XCTAssertEqual(payload["derived_settlement"] as? Bool, true)
        XCTAssertEqual(o.body["store"] as? Bool, false)
        XCTAssertEqual(
            responsesOutputText(o.body), text,
            "the served text is the settled value of the real turn")

        // 5) 引擎侧独立证据：prompt cells 一格未动。llama.cpp 不导出前缀表示，
        //    消费也从不碰它的 KV —— 这两句在这里是同一件事的两种读法。
        let after = try await slotPromptTokens(runtime)
        XCTAssertEqual(after, before, "consumption must not touch the engine's prompt cells")
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

    private func postResponses(
        to port: Int, body: [String: Any]
    ) async throws -> (status: Int, body: [String: Any], raw: Data) {
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(port)/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, json, data)
    }

    private func responsesOutputText(_ body: [String: Any]) -> String? {
        guard let output = body["output"] as? [[String: Any]],
            let content = output.first?["content"] as? [[String: Any]]
        else { return nil }
        return content.first?["text"] as? String
    }

    /// Tokens loaded in each engine slot's prompt. An engine that never saw a
    /// prompt answers `/slots` without the key at all, so absence reads as 0 —
    /// which is why every zero-read here is preceded by a non-zero read.
    private func slotPromptTokens(_ runtime: ManagedGGUFRuntime) async throws -> [Int] {
        let enginePort = try XCTUnwrap(runtime.enginePort)
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(enginePort)/slots")!)
        request.timeoutInterval = 60
        let (data, _) = try await URLSession.shared.data(for: request)
        let slots = try XCTUnwrap(
            try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            "engine /slots probe unreadable")
        XCTAssertFalse(slots.isEmpty, "an empty slot table would make every zero vacuous")
        return slots.map { ($0["n_prompt_tokens"] as? NSNumber)?.intValue ?? 0 }
    }
}
