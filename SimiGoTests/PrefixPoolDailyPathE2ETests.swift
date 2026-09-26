import XCTest
import SimiGo2Experimental

@testable import SimiGo

/// B-5 real-device battery (SIMIGO17_PREFIX_POOL): the daily ChatSession
/// path serves a NEW session (new session_id = new storage key) from the
/// shared prefix pool when its conversation history was committed by an
/// earlier session — the agent-restart/reconnect scenario from the
/// 2026-09-27 log evidence (cold 47.6s @6.2K).
///
/// Registered metrics: pool-hit turn ≈ snapshot load + delta prefill
/// (seconds) vs cold full prefill (tens of seconds at the same context
/// size); trace markers poolBind / poolExport; disk rescan admits after
/// "restart" (fresh store instance over the same root).
final class PrefixPoolDailyPathE2ETests: XCTestCase {
    private let port = 18_231

    /// Daily-path fitting model (E-line's first validated architecture).
    private var modelPath: String {
        if let override = ProcessInfo.processInfo.environment["PREFIX_POOL_MODEL_PATH"] {
            return override
        }
        let hub = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                ".cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit/snapshots")
        let snapshots = (try? FileManager.default.contentsOfDirectory(
            at: hub, includingPropertiesForKeys: [.isDirectoryKey]))?
            .filter { $0.hasDirectoryPath } ?? []
        return snapshots.first?.path ?? hub.appendingPathComponent("NOT-PRESENT").path
    }

    /// ~16KB deterministic shared document (≈4-6K tokens) — the cold-
    /// prefill class from the registered evidence.
    private let document: String = {
        var lines: [String] = []
        for i in 0..<220 {
            lines.append(
                "Section \(i): The runtime maintains execution state as a first-class "
                    + "object; representations bind to logical states by content, and "
                    + "continuity is preserved across sessions and restarts. (\(i) of 220)")
        }
        return lines.joined(separator: "\n")
    }()

    private func message(_ role: String, _ content: String) -> [String: Any] {
        ["role": role, "content": content]
    }

    private func traceLogContains(_ marker: String, sinceByteOffset offset: Int) -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".simigo/logs/native_mlx_trace.log")
        guard let data = try? Data(contentsOf: url), data.count > offset else {
            return false
        }
        return data.suffix(data.count - offset).range(of: Data(marker.utf8)) != nil
    }

    private func traceLogSize() -> Int {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".simigo/logs/native_mlx_trace.log")
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.size] as? Int ?? 0
    }

    private func chatCompletion(
        sessionId: String, messages: [[String: Any]], maxTokens: Int = 8
    ) async throws -> (text: String, seconds: Double) {
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!,
            timeoutInterval: 900)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "daily",
            "messages": messages,
            "max_tokens": maxTokens,
            "stream": false,
            "session_id": sessionId,
        ])
        let start = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let seconds = Date().timeIntervalSince(start)
        XCTAssertEqual(
            (response as? HTTPURLResponse)?.statusCode, 200,
            String(decoding: data, as: UTF8.self))
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = body?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let text = message?["content"] as? String ?? ""
        return (text, seconds)
    }

    func testNewSessionWithCommittedHistoryServesFromPool() async throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("daily model not present: \(modelPath)")
        }
        let runtime = NativeMLX(
            info: ModelInfo(path: modelPath, kind: .mlx), config: ModelConfig())
        try await runtime.start(ModelInfo(path: modelPath, kind: .mlx), port: port)
        defer { Task { await runtime.stop() } }
        let logStart = traceLogSize()

        // --- Warmup: absorb model load so the cold measurement below is
        //     pure prefill cost. ---
        _ = try await chatCompletion(
            sessionId: "pool-battery-warmup",
            messages: [message("user", "Say HI.")], maxTokens: 4)

        // --- Turn 1 (session A): cold — full document prefill ---
        let messagesA = [message("system", "You are a precise assistant. Internal "
            + "specification document:\n" + document), message("user", "Say READY.")]
        let (replyA, coldSeconds) = try await chatCompletion(
            sessionId: "pool-battery-A", messages: messagesA)
        XCTAssertFalse(replyA.isEmpty)
        XCTAssertTrue(
            traceLogContains("poolExport", sinceByteOffset: logStart),
            "turn 1 exports its boundary")

        // --- Turn 2 (session B = NEW session id, A's history + one user
        //     message): the agent-reconnect scenario. Same-session reuse
        //     CANNOT fire (different storage key); the pool must. ---
        let messagesB = messagesA + [message("assistant", replyA), message("user", "Say DONE.")]
        let (_, warmSeconds) = try await chatCompletion(
            sessionId: "pool-battery-B", messages: messagesB)
        XCTAssertTrue(
            traceLogContains("poolBind messages=3", sinceByteOffset: logStart),
            "3-message boundary admitted")

        // Registered metric shape: the pool-hit turn must not re-prefill
        // the document. Cold turn ≈ full prefill; pool turn ≈ snapshot
        // load + one-message delta. Assert the dominant cost vanished.
        XCTAssertLessThan(
            warmSeconds, coldSeconds * 0.5,
            "pool turn \(warmSeconds)s should be well under cold \(coldSeconds)s")

        // --- Restart-warm: a fresh store over the same disk root admits
        //     the committed boundary without any live session. ---
        let freshStore = PrefixSnapshotStore(
            root: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".simigo/prefix-pool"),
            pool: ExecutionStatePrefixPool(tokenBudget: 200_000))
        let rescanned = try freshStore.rescan()
        XCTAssertGreaterThanOrEqual(rescanned, 1, "disk boundaries survive restart")
    }
}
