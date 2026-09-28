import XCTest
import MLXLMCommon
import MLX
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

    private func traceLogLineContains(
        _ markers: [String], sinceByteOffset offset: Int
    ) -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".simigo/logs/native_mlx_trace.log")
        guard let data = try? Data(contentsOf: url), data.count > offset else {
            return false
        }
        let suffix = data.suffix(data.count - offset)
        return String(decoding: suffix, as: UTF8.self)
            .split(separator: "\n")
            .contains { line in
                markers.allSatisfy { line.contains($0) }
            }
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

        // --- B-6: a genuinely NEW conversation sharing only the document
        //     (different first question) — message boundaries diverge at
        //     message 2, but the TOKEN prefix (the document) matches a
        //     grid boundary exported by turn 1. ---
        let messagesC = [message("system", "You are a precise assistant. Internal "
            + "specification document:\n" + document),
            message("user", "What is 2+2? Answer with the numeral only.")]
        let (replyC, crossSeconds) = try await chatCompletion(
            sessionId: "pool-battery-C", messages: messagesC)
        XCTAssertFalse(replyC.isEmpty)
        XCTAssertTrue(
            traceLogContains("mode=cross-session", sinceByteOffset: logStart),
            "token-level cross-session seeding must fire for a shared-document new session")
        XCTAssertTrue(
            traceLogContains("poolTokenHit", sinceByteOffset: logStart),
            "the token-level pool admitted a boundary")
        XCTAssertLessThan(
            crossSeconds, coldSeconds * 0.5,
            "cross-session turn \(crossSeconds)s should be well under cold \(coldSeconds)s")

        // --- Restart-warm: a fresh store over the same disk root admits
        //     the committed boundary without any live session. ---
        let freshStore = PrefixSnapshotStore(
            root: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".simigo/prefix-pool"),
            pool: ExecutionStatePrefixPool(tokenBudget: 200_000))
        let rescanned = try freshStore.rescan()
        XCTAssertGreaterThanOrEqual(rescanned, 1, "disk boundaries survive restart")
    }

    /// F3_DEVICE_ACCEPTANCE battery (FORK-3 step 8): the economic
    /// proposition on the real MLX path.
    ///
    ///   Parent P warms the shared prefix X @ T (cold, full prefill)
    ///   fork  → Child C (NEW session id) binds X and forwards only ΔC
    ///   Parent P continues afterwards with no attributable regression
    ///
    /// Five conditions (reviewer-ruled):
    ///   D1  Child starts from T, not 0 (bound, not cold)
    ///   D2  fork does NOT trigger a second full materialization of X
    ///       (HARD GATE — no cold-mode line for the child; shared prefix
    ///       served from the existing materialization)
    ///   D3  Child's first forward computes ΔC, not T+ΔC
    ///   D4  Parent live state / continuation has no attributable
    ///       regression after the Child forward (F-I2)
    ///   D5  Parent/Child deterministic; shared-prefix cacheEff ≈ 1
    func testF3DeviceAcceptanceBattery() async throws {
        // F3 transcript-restoration fix landed in mlx-swift-lm; this battery
        // is now a live acceptance gate for the five physical conditions.
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("daily model not present: \(modelPath)")
        }
        let runtime = NativeMLX(
            info: ModelInfo(path: modelPath, kind: .mlx), config: ModelConfig())
        try await runtime.start(ModelInfo(path: modelPath, kind: .mlx), port: port)
        defer { Task { await runtime.stop() } }
        // start() returns before the HTTP surface is accepting: poll
        // readiness so the first request never hits a closed port.
        var httpReady = false
        for _ in 0..<120 {
            if let url = URL(string: "http://127.0.0.1:\(port)/v1/models"),
                let (_, resp) = try? await URLSession.shared.data(from: url),
                (resp as? HTTPURLResponse)?.statusCode == 200 {
                httpReady = true
                break
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        XCTAssertTrue(httpReady, "runtime HTTP surface never became ready")
        let logStart = traceLogSize()

        let doc = "You are a precise assistant. Internal specification document:\n"
            + document
        func sysDoc() -> [String: Any] { message("system", doc) }

        // --- Warmup: absorb model load ---
        _ = try await chatCompletion(
            sessionId: "f3-warmup", messages: [message("user", "Say HI.")], maxTokens: 4)

        // --- Parent turn 1: cold, full prefill of X (~9.7K tokens) ---
        let msgsP1 = [sysDoc(), message("user", "Reply with the single word READY.")]
        let (replyP1, coldSeconds) = try await chatCompletion(
            sessionId: "f3-parent", messages: msgsP1)
        XCTAssertFalse(replyP1.isEmpty)

        // --- Parent turn 2: warm continuation (D4 baseline) ---
        let msgsP2 = msgsP1 + [message("assistant", replyP1), message("user", "Say WARM.")]
        let (replyP2, parentWarmSeconds) = try await chatCompletion(
            sessionId: "f3-parent", messages: msgsP2)
        XCTAssertFalse(replyP2.isEmpty)

        // --- FORK: Child C = NEW session id, Parent's full history + ΔC ---
        let childHistory = msgsP2 + [message("assistant", replyP2)]
        let msgsC = childHistory + [message("user", "Say DONE.")]
        let (replyC, childSeconds) = try await chatCompletion(
            sessionId: "f3-child", messages: msgsC)
        XCTAssertFalse(replyC.isEmpty)

        // --- D1/D2/D3: the Child bound the shared prefix and paid only ΔC ---
        XCTAssertTrue(
            traceLogContains("poolBind messages=", sinceByteOffset: logStart),
            "D1: child bound the shared boundary (started from T, not 0)")
        XCTAssertTrue(
            traceLogContains("poolHit", sinceByteOffset: logStart),
            "D1: consumption via the existing materialization")
        XCTAssertFalse(
            traceLogLineContains(
                ["session=f3-child", "mode=cold"], sinceByteOffset: logStart),
            "D2: child must not take a cold materialization path")
        XCTAssertLessThan(
            childSeconds, coldSeconds * 0.5,
            "D3: child incremental cost (\(childSeconds)s) must be far below the "
                + "full recompute (\(coldSeconds)s)")

        // --- D4: Parent continues AFTER the child forward — no
        // attributable regression (its own warm continuation level). ---
        let msgsP3 = childHistory + [message("user", "Say MORE.")]
        let (replyP3, parentAfterSeconds) = try await chatCompletion(
            sessionId: "f3-parent", messages: msgsP3)
        XCTAssertFalse(replyP3.isEmpty)
        XCTAssertLessThan(
            parentAfterSeconds, coldSeconds,
            "D4: parent continuation (\(parentAfterSeconds)s) must stay at the warm "
                + "level, not degrade toward the cold level")

        // --- D5: determinism — the same child request repeats
        // identically. ---
        let (replyC2, _) = try await chatCompletion(
            sessionId: "f3-child", messages: msgsC)
        XCTAssertEqual(replyC2, replyC, "child output deterministic")
    }
}

/// Gate C/D seed-side truncation unit battery (no model): a FULL-length
/// artifact claiming a shorter grid boundary must truncate to the
/// claimed boundary; unslicable/state-carrying candidates reject.
final class PrefixSeedTruncationTests: XCTestCase {
    private func syntheticSnapshot(rows: Int, state: Bool = false) throws
        -> PromptCacheSnapshot
    {
        let layer = KVCacheSimple()
        layer.update(
            keys: MLXArray.zeros([1, 2, rows, 4]),
            values: MLXArray.zeros([1, 2, rows, 4]))
        return PromptCacheSnapshot(cache: [layer])
    }

    func testTruncateToClaimedBoundary() throws {
        let full = try syntheticSnapshot(rows: 9708)
        let cut = NativeMLXPrefixPool.truncatedSnapshot(full, to: 8192)
        XCTAssertNotNil(cut)
        XCTAssertEqual(cut?.cache[0].state.first?.dim(2), 8192,
                       "rows sliced to the claimed boundary")
    }

    func testTruncateRejectsBeyondArtifact() throws {
        let full = try syntheticSnapshot(rows: 100)
        XCTAssertNil(NativeMLXPrefixPool.truncatedSnapshot(full, to: 8192))
    }
}
