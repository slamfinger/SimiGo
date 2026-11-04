import XCTest
import Foundation
import SimiGoRuntimeContract
@testable import SimiGo

/// #133 characterization window: the `content` encoding of an assistant tool
/// echo must not decide whether the echoed turn rides the primed KV prefix.
///
/// 2026-10-29 real-machine reading withdrew the original attribution. The 55 s
/// cold re-render was a REPLAY of an already-served turn, and the engine
/// named the reason itself, in the installed v2.2.1-31 trace:
///
///   14:58:04.561 [MLX] sessionAdopt key=608579/main from=4/main own=transfer
///                history=3 incoming=4 delta=1
///   14:58:04.944 [MLX] session=608579/main … mode=extend cacheHitTokens=27249
///                promptTokens=18 adopt=1            ← first replay (`content: null`)
///   14:58:05.879 [MLX] sessionAdoptMiss key=1cb8a0/main candidates=5 eligible=0
///                reasons=…,608579/main:notShorter,902b66/main:notShorter
///   14:59:00.997 [MLX] session=1cb8a0/main … mode=cold promptTokens=27267
///                cacheHitTokens=0                  ← second replay (`content: ""`)
///
/// The first replay transferred the primed shard to its own identity key and
/// grew its ledger to five messages, so the second replay was no longer an
/// extension of any live shard: `notShorter`, not a content mismatch. Prefix
/// identity is decided on `Chat.Message.content`, and `makeChatMessages` maps
/// both `null` and `""` to the empty string, so neither the same-key reuse gate
/// nor the adoption gate can observe that encoding difference at all — which is
/// exactly what this test pins: each encoding, measured as the FIRST echo after
/// a cold priming turn, must reuse.
///
/// The request budget gate is disabled for this run
/// (`SIMIGO_REQUEST_BUDGET_MS=0`, the documented local off switch): the subject
/// is prefix identity, and a live budget gate would confound the cold-prefill
/// turns this window depends on.
final class ToolEchoContinuationRealModelE2ETests: XCTestCase {
    private let port = 18_483
    private var host: LOCALBAuthorizedE2E.Host!

    /// 110 KB of filler ≈ 27k rendered tokens with the chat template — the
    /// same shape the real-machine fork was measured on.
    private let fillerKB = 110
    private let toolBudget = 128
    private let echoBudget = 32

    private var modelPath: String {
        if let override = ProcessInfo.processInfo.environment["CONTINUATION_MODEL_PATH"] {
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

    // MARK: - instruments

    private var traceURL: URL {
        SimiGoPaths.logs.appendingPathComponent("native_mlx_trace.log")
    }

    private func traceSize() -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: traceURL.path)
        return attributes?[.size] as? Int ?? 0
    }

    private func traceWindow(
        since offset: Int, waitingFor markers: [String], timeout: TimeInterval = 300
    ) -> [String] {
        func read() -> [String] {
            guard let data = try? Data(contentsOf: traceURL), data.count > offset else {
                return []
            }
            return String(decoding: data.suffix(data.count - offset), as: UTF8.self)
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init)
        }
        let deadline = Date().addingTimeInterval(timeout)
        var window = read()
        while Date() < deadline {
            if window.contains(where: { line in markers.contains(where: line.contains) }) {
                Thread.sleep(forTimeInterval: 0.6)
                return read()
            }
            Thread.sleep(forTimeInterval: 0.2)
            window = read()
        }
        return window
    }

    private func value(_ marker: String, in line: String) -> String? {
        guard let range = line.range(of: marker) else { return nil }
        var token = String(line[range.upperBound...].prefix { !$0.isWhitespace })
        if token.hasPrefix("Optional("), token.hasSuffix(")") {
            token = String(token.dropFirst("Optional(".count).dropLast())
        }
        return token
    }

    private struct Outcome {
        let status: Int
        let json: [String: Any]
        let raw: String
        let window: [String]
        var choice: [String: Any] {
            (json["choices"] as? [[String: Any]])?.first ?? [:]
        }
        var message: [String: Any] { choice["message"] as? [String: Any] ?? [:] }
        var toolCalls: [[String: Any]] { message["tool_calls"] as? [[String: Any]] ?? [] }
        var finishReason: String? { choice["finish_reason"] as? String }
        var engineLine: String? {
            window.last { $0.contains("[MLX] session=") }
        }
        var adopts: [String] { window.filter { $0.contains("[MLX] sessionAdopt") } }
        var normalized: [String] { window.filter { $0.contains("[MLX] toolEchoNormalize") } }
        var misses: [String] {
            window.filter {
                $0.contains("reuseMiss") || $0.contains("prefixMismatch")
                    || $0.contains("prefixDiff")
            }
        }
    }

    private func startRuntime(port: Int) async throws -> NativeMLX {
        let runtime = NativeMLX(
            info: ModelInfo(path: modelPath, kind: .mlx), config: ModelConfig())
        host = try LOCALBAuthorizedE2E.makeHost()
        try await runtime.startWithLOCALB(
            ModelInfo(path: modelPath, kind: .mlx),
            port: port,
            localbTransportIdentity: host.identity,
            localbRequestAuthorization: (
                coordinator: host.coordinator,
                trustedCheckpoint: host.checkpointProvider
            )
        )
        return runtime
    }

    private func chat(
        messages: [[String: Any]], tools: [[String: Any]], maxTokens: Int
    ) async throws -> Outcome {
        let offset = traceSize()
        // Deliberately NO session_id: real clients of this wire do not send
        // one, and the fork was measured on that path.
        let body: [String: Any] = [
            "model": "tool-echo-e2e",
            "messages": messages,
            "tools": tools,
            "max_tokens": maxTokens,
            "stream": false,
            "temperature": 0,
            "disable_thinking": true,
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let (responseData, response) = try await LOCALBAuthorizedE2E.send(
            host: host, port: port, method: "POST",
            path: "/v1/chat/completions", contentType: "application/json", body: data)
        let raw = String(decoding: responseData, as: UTF8.self)
        let json = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any] ?? [:]
        return Outcome(
            status: response.statusCode, json: json, raw: raw,
            window: traceWindow(since: offset, waitingFor: ["[MLX] session="]))
    }

    private func filler(_ kb: Int) -> String {
        let unit = String(repeating: "The quick brown fox jumps over the lazy dog. "
            + "Reference ledger note: settle, bind, advance, reuse. ", count: 20)
        return String(String(repeating: unit, count: max(1, kb * 1024 / unit.count))
            .prefix(kb * 1024))
    }

    private var tools: [[String: Any]] {
        [[
            "type": "function",
            "function": [
                "name": "echo",
                "description": "Echo the given text back to the caller.",
                "parameters": [
                    "type": "object",
                    "properties": ["text": ["type": "string", "description": "text to echo"]],
                    "required": ["text"],
                ],
            ],
        ]]
    }

    private func baseMessages(salt: String) -> [[String: Any]] {
        [
            [
                "role": "system",
                "content": "你必须调用 echo 工具，参数 text 固定为 ping。不要说其他话。",
            ],
            [
                "role": "user",
                // `salt` keeps each window's demand distinct: an identical
                // demand text in the second window would be answered from the
                // first window's settlement with zero model calls, which is
                // not a prefix reading at all.
                "content": "背景资料（占位，与任务无关）：\n" + filler(fillerKB)
                    + "\n\n任务：调用 echo 工具，text=\"ping\"。（窗口 \(salt)）",
            ],
        ]
    }

    private func record(_ name: String, _ payload: [String: Any]) {
        let url = SimiGoPaths.logs.appendingPathComponent("tool-echo-realmodel-\(name).json")
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url)
    }

    // MARK: - gate

    /// One window = one cold priming turn + one echo turn, then a fresh runtime.
    /// Two windows keep the two encodings independent: a shared window would
    /// make the second echo a replay of an already-served turn, which is the
    /// confound that produced the 55 s reading.
    private func measureEchoWindow(
        labeled label: String,
        echoContent: Any
    ) async throws -> [String: Any] {
        let runtime = try await startRuntime(port: port)
        var stopped = false
        defer {
            if !stopped {
                let stopping = runtime
                Task { await stopping.stop() }
            }
        }

        let messages = baseMessages(salt: label)
        let tools = self.tools

        // ① tool-call turn — always a cold prefill: it primes the shard.
        let first = try await chat(messages: messages, tools: tools, maxTokens: toolBudget)
        XCTAssertEqual(first.status, 200, first.raw)
        XCTAssertEqual(first.finishReason, "tool_calls", first.raw)
        let calls = first.toolCalls
        XCTAssertEqual(calls.count, 1, "the model must produce exactly one echo call: \(first.raw)")
        let call = try XCTUnwrap(calls.first)
        let callID = try XCTUnwrap(call["id"] as? String, first.raw)
        let firstLine = try XCTUnwrap(first.engineLine, "no engine line: \(first.raw)")
        XCTAssertEqual(value("mode=", in: firstLine), "cold", firstLine)
        XCTAssertEqual(value("toolCalls=", in: firstLine), "1", firstLine)
        let firstPromptTokens = Int(try XCTUnwrap(
            value("promptTokens=", in: firstLine), firstLine)) ?? 0
        XCTAssertGreaterThan(
            firstPromptTokens, 20_000,
            "the priming turn must render the ~27k filler, else the reuse below is trivial: "
                + firstLine)

        // ② the client's echo, byte-for-byte as returned, in `echoContent` form.
        let echo: [[String: Any]] = messages + [
            ["role": "assistant", "content": echoContent, "tool_calls": calls],
            ["role": "tool", "tool_call_id": callID, "content": "ping"],
        ]
        let echoed = try await chat(messages: echo, tools: tools, maxTokens: echoBudget)
        XCTAssertEqual(echoed.status, 200, echoed.raw)
        let line = try XCTUnwrap(echoed.engineLine, "no engine line: \(echoed.raw)")
        let mode = value("mode=", in: line)
        let hit = Int(value("cacheHitTokens=", in: line) ?? "") ?? 0
        let prompt = Int(value("promptTokens=", in: line) ?? "") ?? 0
        let answer = (echoed.message["content"] as? String) ?? ""

        XCTAssertEqual(
            mode, "extend",
            "a \(label) echo sent as the first echo after priming must ride the prefix — "
                + "a `cold` here means the encoding reached the prefix decision: \(line)")
        XCTAssertGreaterThan(
            hit, 20_000,
            "the echoed prefix must be recognised as cached: \(line)")
        XCTAssertLessThan(
            prompt, 2_000,
            "only the delta should be prefilled on the echoed turn: \(line)")
        XCTAssertFalse(
            answer.isEmpty,
            "the echo turn must still answer, not reuse into a truncated transcript: "
                + "\(echoed.raw)")

        // Stop before the next window so the two model loads never overlap.
        await runtime.stop()

        return [
            "label": label,
            "modelPath": modelPath,
            "fillerKB": fillerKB,
            "firstEngineLine": firstLine,
            "echoEngineLine": line,
            "echoMode": mode ?? "",
            "echoCacheHitTokens": hit,
            "echoPromptTokens": prompt,
            "echoAnswer": answer,
            "echoWindow": echoed.window,
            "echoAdoptLines": echoed.adopts,
            "echoNormalizeLines": echoed.normalized,
            "echoMissLines": echoed.misses,
            "firstMissLines": first.misses,
        ]
    }

    func testToolEchoContentEncodingDoesNotDecidePrefixReuse() async throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("local MLX model not present: \(modelPath)")
        }
        XCTAssertEqual(
            RuntimeTuning.requestBudgetMs, 0,
            "this run must state SIMIGO_REQUEST_BUDGET_MS=0: the subject is prefix "
                + "identity, and a live budget gate would confound a cold-prefill control")

        var windows: [[String: Any]] = []
        windows.append(try await measureEchoWindow(labeled: "content:null", echoContent: NSNull()))
        windows.append(try await measureEchoWindow(labeled: "content:\"\"", echoContent: ""))
        record("echo", ["windows": windows])

        let modes = windows.compactMap { $0["echoMode"] as? String }
        XCTAssertEqual(
            Set(modes), ["extend"],
            "both encodings must reuse identically; a split means the echo's content "
                + "encoding reached the prefix decision after all: \(modes)")
    }
}
