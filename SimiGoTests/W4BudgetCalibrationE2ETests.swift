import XCTest
import Foundation
import SimiGoRuntimeContract

@testable import SimiGo

/// W4 §6 隔离校准（owner 2026-10-29 授权：允许构建与隔离根内校准，不安装、
/// 不写真实用户状态）。
///
/// ADR 2026-10-30：W4 的时间门控路线已被 owner 裁定撤销，准入拒绝不再执行。
/// Phase A（8K / 24K / 40K 真实冷预填的 token/秒读数）仍然有效，因为它测的
/// 是硬件事实，也是 `estMs` 观测的输入。Phase B/C 测的是「拒绝、拒绝缓存、
/// 取消后重试被拒」——这些行为已不存在，因此默认不跑；只有对仍会拒绝的旧
/// 二进制做历史复核时，才显式设置 `W4_MEASURE_ENFORCEMENT=1` 运行。
/// 这些读数不随本文件的变化被重新解释，也不用于关闭 #138（样本污染）。
///
/// 1. 8K / 24K / 40K 三档真实冷预填各 3 次（`promptTokens` / `promptTime`）；
/// 2. 校准样本就位后，默认 60 s 预算下门是**实际拦截**还是**样本不足放行**；
/// 3. 同一超预算 payload 连续重放是否命中 TTL 缓存、每次拒绝的墙钟；
/// 4. 首轮「样本不足放行 → 客户端取消 → 同 payload 重试」是否落到
///    `reject_prior_attempt`（#121 的服务端保护），而不是再付一次冷预填。
///
/// 门控：`W4_BUDGET_CALIBRATION=1` 且本机存在权重；常规测试跑不会触发。
/// 请求走回环明文（`LOCALBTransportPolicy`：回环默认 plaintext），因为
/// LOCALB 授权路由会丢弃未签名的 `X-Simigo-Deadline-Ms`（见
/// `HTTPServer.requestBudgetDeadlineMS` 注释），而本校准必须用请求头把三档
/// 测量轮的预算放大，否则门会在 24K 就开始拦，测不到真实预填。
final class W4BudgetCalibrationE2ETests: XCTestCase {

    private let port = 18_245
    private var runtime: NativeMLX?
    private var records: [[String: Any]] = []

    private var modelPath: String {
        if let override = ProcessInfo.processInfo.environment["W4_CALIBRATION_MODEL"],
            !override.isEmpty
        {
            return override
        }
        let hub = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                ".cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit/snapshots")
        let snapshots =
            (try? FileManager.default.contentsOfDirectory(
                at: hub, includingPropertiesForKeys: [.isDirectoryKey]))?
            .filter { $0.hasDirectoryPath } ?? []
        return snapshots.first?.path ?? hub.appendingPathComponent("NOT-PRESENT").path
    }

    private struct GateReading {
        var kind: String?
        var gate: String?
        var bucket: String?
        var promptTokens: Int?
        var renderedTokens: Int?
        var deltaTokens: Int?
        var estMs: Int?
        var samples: Int?
        var rate: Double?
        var cached = false
        var priorProcessed: Int?
        var priorTotal: Int?
        var priorElapsedMs: Int?
    }

    // MARK: - Prompt construction

    private func prompt(tokens: Int, tag: String) -> String {
        var sections: [String] = []
        var chars = 0
        let target = tokens * 4
        var index = 0
        while chars < target {
            let line =
                "\(tag) entry \(index): the maintenance log records routine inspections, "
                + "replaced parts, measured tolerances and the technician notes for "
                + "assembly line seven. No anomaly was reported in this entry."
            sections.append(line)
            chars += line.count + 1
            index += 1
        }
        sections.append("Ignore every entry above. Reply with exactly the single word: DONE")
        return sections.joined(separator: "\n")
    }

    // MARK: - Isolation

    private func requireIsolatedRoots() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty,
            let graphStore = env["SIMIGO_STATE_GRAPH_STORE"], !graphStore.isEmpty,
            let cache = env["SIMIGO_CACHE_ROOT"], !cache.isEmpty,
            home.hasPrefix("/"), graphStore.hasPrefix("/"), cache.hasPrefix("/")
        else {
            throw XCTSkip(
                "isolated roots not injected: run through tools/make_isolated_xctestrun.py")
        }
        let root = URL(
            fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
        XCTAssertTrue(
            SimiGoPaths.databaseURL.path.hasPrefix(root.path),
            "authoritative store resolves outside the isolation root")
        return root
    }

    // MARK: - HTTP

    private func request(
        body: [String: Any],
        headers: [String: String],
        timeout: TimeInterval = 900
    ) -> URLRequest {
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(port)/v1/responses")!,
            timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody =
            (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return request
    }

    private func send(
        body: [String: Any], headers: [String: String], timeout: TimeInterval = 900
    ) async throws -> (status: Int, data: Data, headers: [AnyHashable: Any], elapsedMs: Int) {
        let started = Date()
        let (data, response) = try await URLSession.shared.data(
            for: request(body: body, headers: headers, timeout: timeout))
        let http = response as? HTTPURLResponse
        return (
            http?.statusCode ?? -1, data, http?.allHeaderFields ?? [:],
            Int(Date().timeIntervalSince(started) * 1000)
        )
    }

    /// Plain-HTTP streaming reader used only for the cancel case: it must close
    /// the connection mid-prefill exactly like a client whose own timeout fired.
    private final class StreamHandle: @unchecked Sendable {
        private let lock = NSLock()
        private var task: Task<Void, Never>?
        private var _status: Int?
        private var _lines: [String] = []
        private var _finished = false

        func start(_ request: URLRequest) {
            task = Task { [self] in
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    lock.withLock {
                        _status = (response as? HTTPURLResponse)?.statusCode
                    }
                    for try await line in bytes.lines {
                        lock.withLock { _lines.append(line) }
                    }
                } catch {
                    // The disconnect is the point of this handle.
                }
                lock.withLock { _finished = true }
            }
        }

        var status: Int? { lock.withLock { _status } }
        var sse: String { lock.withLock { _lines.joined(separator: "\n") } }
        var finished: Bool { lock.withLock { _finished } }
        func cancel() { task?.cancel() }
    }

    // MARK: - Trace parsing

    private func gateLine(since mark: Int, containing marker: String = "[BUDGET]") -> String? {
        CancelTrace.lines(since: mark).first {
            $0.contains(marker) && $0.contains("verdict=")
        }
    }

    private func completionLine(since mark: Int) -> String? {
        CancelTrace.lines(since: mark).last {
            $0.contains("[MLX] session=") && $0.contains("promptTime=")
        }
    }

    private func parseGate(_ line: String?) -> GateReading {
        var reading = GateReading()
        guard let line else { return reading }
        var prior: String?
        for token in line.split(separator: " ") {
            let pair = token.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            switch pair[0] {
            case "verdict": reading.kind = pair[1]
            case "gate": reading.gate = pair[1]
            case "bucket": reading.bucket = pair[1]
            case "promptTokens": reading.promptTokens = Int(pair[1])
            case "renderedTokens": reading.renderedTokens = Int(pair[1])
            case "deltaTokens": reading.deltaTokens = Int(pair[1])
            case "estMs": reading.estMs = Int(pair[1])
            case "samples": reading.samples = Int(pair[1])
            case "rate": reading.rate = Double(pair[1])
            case "cached": reading.cached = pair[1] == "1"
            case "priorAttempt": prior = pair[1]
            default: break
            }
        }
        if let prior {
            // processed/total@elapsedms
            let parts = prior.split(separator: "@").map(String.init)
            let fraction = parts.first?.split(separator: "/").map(String.init) ?? []
            reading.priorProcessed = fraction.count == 2 ? Int(fraction[0]) : nil
            reading.priorTotal = fraction.count == 2 ? Int(fraction[1]) : nil
            reading.priorElapsedMs = parts.count == 2 ? Int(parts[1]) : nil
        }
        return reading
    }

    private func engineReading(_ line: String?) -> (tokens: Int?, seconds: Double?) {
        guard let line else { return (nil, nil) }
        var tokens: Int?
        var seconds: Double?
        for token in line.split(separator: " ") {
            let pair = token.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            if pair[0] == "promptTokens" { tokens = Int(pair[1]) }
            if pair[0] == "promptTime" {
                seconds = Double(pair[1].replacingOccurrences(of: "s", with: ""))
            }
        }
        return (tokens, seconds)
    }

    // MARK: - Records

    private func record(_ entry: [String: Any]) {
        records.append(entry)
        flush()
    }

    private func flush() {
        let url = SimiGoPaths.logs.appendingPathComponent("w4-budget-calibration.json")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload: [String: Any] = [
            "model": modelPath,
            "port": port,
            "recorded_at": ISO8601DateFormatter().string(from: Date()),
            "runs": records,
        ]
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? data.write(to: url, options: .atomic)
        print("[W4-CAL] recorded \(url.path) runs=\(records.count)")
    }

    // MARK: - The calibration

    func testColdPrefillTiersAndGateDecisions() async throws {
        guard ProcessInfo.processInfo.environment["W4_BUDGET_CALIBRATION"] == "1" else {
            throw XCTSkip("§6 calibration: set W4_BUDGET_CALIBRATION=1 in the isolated run")
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("local Qwen3-Coder not present: \(modelPath)")
        }
        let root = try requireIsolatedRoots()
        XCTAssertEqual(
            RuntimeTuning.requestBudgetMs, 60_000,
            "owner Q1: the default product budget is 60 s and on by default")
        XCTAssertFalse(
            RuntimeTuning.prefixPoolEnabled,
            "default product state: prefix pool off, so the gate is not declared inactive")
        XCTAssertFalse(
            RuntimeTuning.branchCheckpointsEnabled,
            "default product state: branch checkpoints off")

        RequestBudgetController.shared.resetForTesting()
        try? FileManager.default.removeItem(at: RequestBudgetController.calibrationURL)
        print("[W4-CAL] isolation=\(root.path)")
        print("[W4-CAL] budget_ms=\(RuntimeTuning.requestBudgetMs) calibration=\(RequestBudgetController.calibrationURL.path)")

        let runtime = NativeMLX(
            info: ModelInfo(path: modelPath, kind: .mlx), config: ModelConfig())
        self.runtime = runtime
        try await runtime.start(ModelInfo(path: modelPath, kind: .mlx), port: port)
        defer { Task { await runtime.stop() } }
        print("[W4-CAL] runtime started port=\(port)")

        // MARK: Phase A — real cold prefills at 8K / 24K / 40K, 3 each.
        // A 600 s header budget keeps the gate from refusing the measurement
        // rounds; it is a per-request override, not a disabled gate.
        let tiers: [(name: String, tokens: Int)] = [
            ("8k", 8_000), ("24k", 24_000), ("40k", 40_000),
        ]
        for tier in tiers {
            for index in 0..<3 {
                let session = "w4-cal-\(tier.name)-\(index)-\(UUID().uuidString)"
                let text = prompt(tokens: tier.tokens, tag: "W4-\(tier.name.uppercased())")
                let body: [String: Any] = [
                    "model": "w4-budget-calibration",
                    "input": text,
                    "session_id": session,
                    "stream": false,
                    "temperature": 0,
                    "disable_thinking": true,
                    "max_completion_tokens": 8,
                ]
                let mark = CancelTrace.size()
                let outcome = try await send(
                    body: body, headers: ["X-Simigo-Deadline-Ms": "600000"])
                let gate = parseGate(gateLine(since: mark))
                let engine = engineReading(completionLine(since: mark))
                var entry: [String: Any] = [
                    "phase": "measure",
                    "tier": tier.name,
                    "index": index,
                    "requested_tokens": tier.tokens,
                    "session": session,
                    "status": outcome.status,
                    "elapsed_ms": outcome.elapsedMs,
                    "verdict": gate.kind ?? "missing",
                    "bucket": gate.bucket ?? "missing",
                    "rendered_tokens": gate.renderedTokens ?? -1,
                    "prompt_tokens": gate.promptTokens ?? -1,
                    "samples": gate.samples ?? -1,
                    "engine_prompt_tokens": engine.tokens ?? -1,
                    "engine_prompt_seconds": engine.seconds ?? -1,
                ]
                if let engineTokens = engine.tokens, let engineSeconds = engine.seconds,
                    engineTokens > 0, engineSeconds > 0
                {
                    entry["tok_per_second"] = Double(engineTokens) / engineSeconds
                }
                record(entry)
                XCTAssertEqual(
                    outcome.status, 200,
                    "measurement round must be admitted: \(tier.name)#\(index) "
                        + String(String(decoding: outcome.data, as: UTF8.self).prefix(400)))
                XCTAssertEqual(gate.bucket, "cold", "every measurement session is new")
            }
        }

        // MARK: Phase B/C — retired with the W4 route (ADR 2026-10-30).
        // The invariant below measured refusals: 40K must be a 503, repeats
        // must be cached refusals, the post-cancel retry must be refused.
        // None of that describes the product any more — enforcement is off and
        // a client disconnect now detaches instead of cancelling. The code is
        // kept verbatim as the historical instrument and runs only against a
        // binary that still enforces, under an explicit opt-in.
        guard ProcessInfo.processInfo.environment["W4_MEASURE_ENFORCEMENT"] == "1" else {
            record([
                "phase": "gate-retired",
                "note": "W4 enforcement withdrawn by ADR 2026-10-30; phases B/C not run",
                "admission_enforcement":
                    RequestBudgetController.admissionEnforcementEnabled,
            ])
            flush()
            print("[W4-CAL] phases B/C retired (W4_MEASURE_ENFORCEMENT != 1)")
            return
        }

        // MARK: Phase B — the same model, default 60 s budget, no header.
        // 40K must be refused from the measured samples; the refusal is what
        // stops the #121 loop from paying the prefill again.
        let rejectedPayload = [
            "model": "w4-budget-calibration",
            "input": prompt(tokens: 40_000, tag: "W4-B-40K-UNIQUE"),
            "session_id": "w4-gate-40k-\(UUID().uuidString)",
            "stream": false,
            "temperature": 0,
            "disable_thinking": true,
            "max_completion_tokens": 8,
        ] as [String: Any]
        var rejectionMark = CancelTrace.size()
        let firstReject = try await send(body: rejectedPayload, headers: [:])
        let firstGate = parseGate(gateLine(since: rejectionMark))
        record([
            "phase": "gate",
            "tier": "40k",
            "index": 0,
            "status": firstReject.status,
            "elapsed_ms": firstReject.elapsedMs,
            "verdict": firstGate.kind ?? "missing",
            "est_ms": firstGate.estMs ?? -1,
            "samples": firstGate.samples ?? -1,
            "cached": firstGate.cached,
            "retry_after": firstReject.headers["Retry-After"] as? String ?? "absent",
            "retry_policy": firstReject.headers["X-Simigo-Retry-Policy"] as? String ?? "absent",
        ])
        XCTAssertEqual(firstReject.status, 503, "a 40K cold prefill cannot fit 45 s")
        XCTAssertEqual(firstGate.kind, "reject_estimated")
        XCTAssertNil(
            firstReject.headers["Retry-After"],
            "owner Q3: the refusal never invites a timed retry")

        // A retrying client repeats the identical payload. Record what the
        // server does and how long each attempt takes — never assume the
        // client stopped because the status was 503.
        for index in 1...3 {
            rejectionMark = CancelTrace.size()
            let repeatOutcome = try await send(body: rejectedPayload, headers: [:])
            let repeatGate = parseGate(gateLine(since: rejectionMark))
            record([
                "phase": "gate-replay",
                "tier": "40k",
                "index": index,
                "status": repeatOutcome.status,
                "elapsed_ms": repeatOutcome.elapsedMs,
                "verdict": repeatGate.kind ?? "missing",
                "cached": repeatGate.cached,
                "samples": repeatGate.samples ?? -1,
            ])
            XCTAssertEqual(repeatOutcome.status, 503)
            XCTAssertEqual(repeatGate.kind, "reject_estimated")
            XCTAssertTrue(
                repeatGate.cached,
                "the repeated refusal is served from the 10 min TTL cache")
            XCTAssertLessThan(
                repeatOutcome.elapsedMs, 60_000,
                "a repeated refusal must not spend the budget again")
        }

        // 8K is the positive control inside the same budget: the gate must
        // admit it and the turn must complete normally.
        let mark = CancelTrace.size()
        let smallTier = try await send(
            body: [
                "model": "w4-budget-calibration",
                "input": prompt(tokens: 8_000, tag: "W4-B-8K-UNIQUE"),
                "session_id": "w4-gate-8k-\(UUID().uuidString)",
                "stream": false,
                "temperature": 0,
                "disable_thinking": true,
                "max_completion_tokens": 8,
            ],
            headers: [:])
        let smallGate = parseGate(gateLine(since: mark))
        let smallEngine = engineReading(completionLine(since: mark))
        record([
            "phase": "gate-admit",
            "tier": "8k",
            "status": smallTier.status,
            "elapsed_ms": smallTier.elapsedMs,
            "verdict": smallGate.kind ?? "missing",
            "est_ms": smallGate.estMs ?? -1,
            "samples": smallGate.samples ?? -1,
            "engine_prompt_tokens": smallEngine.tokens ?? -1,
            "engine_prompt_seconds": smallEngine.seconds ?? -1,
        ])
        XCTAssertEqual(
            smallTier.status, 200,
            "8K inside the 45 s prefill budget must still run: "
                + String(String(decoding: smallTier.data, as: UTF8.self).prefix(400)))
        XCTAssertEqual(smallGate.kind, "admit_within_budget")

        // MARK: Phase C — the R4 gap and the #121 shape.
        // Dropping the samples models a first-run install: no matched rate,
        // no calibration record, no observation. The gate must say so and
        // admit — never counterfeit a refusal — and that admitted turn is
        // where the client timeout turns into a cancellation.
        RequestBudgetController.shared.resetForTesting()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: RequestBudgetController.calibrationURL.path),
            "the calibration record is removed for the cold-start phase")
        let cancelPayload = [
            "model": "w4-budget-calibration",
            "input": prompt(tokens: 40_000, tag: "W4-C-CANCEL-UNIQUE"),
            "session_id": "w4-cancel-\(UUID().uuidString)",
            "stream": true,
            "temperature": 0,
            "max_completion_tokens": 8,
        ] as [String: Any]
        let cancelMark = CancelTrace.size()
        let stream = StreamHandle()
        stream.start(request(body: cancelPayload, headers: [:]))
        let started = await CancelPathWait.until(timeout: 300) { stream.status != nil }
        XCTAssertTrue(started, "the streaming attempt never produced a status")
        XCTAssertEqual(stream.status, 200, "no samples yet: the first attempt is admitted")
        let prefill = await CancelTrace.waitForLine(
            containing: ["[MLX] prefill "], since: cancelMark, timeout: 300)
        XCTAssertNotNil(
            prefill,
            "no real prefill started; window:\n"
                + String(CancelTrace.window(since: cancelMark).prefix(2000)))
        let admittedGate = parseGate(gateLine(since: cancelMark))
        XCTAssertEqual(
            admittedGate.kind, "insufficient_samples",
            "with no samples the first 40K attempt is an honest gate-inactive pass")
        stream.cancel()
        let cancelLine = await CancelTrace.waitForLine(
            containing: ["[MLX] cancelCommitSkip"], since: cancelMark, timeout: 300)
        XCTAssertNotNil(
            cancelLine,
            "the engine never observed the cancellation; window:\n"
                + String(CancelTrace.window(since: cancelMark).prefix(2000)))

        // The client retries the identical payload immediately (observed
        // #121 shape: ~0.2 s after the cancel).
        let retryMark = CancelTrace.size()
        let retry = try await send(body: cancelPayload, headers: [:], timeout: 120)
        let retryGate = parseGate(gateLine(since: retryMark))
        record([
            "phase": "prior-attempt-retry",
            "status": retry.status,
            "elapsed_ms": retry.elapsedMs,
            "verdict": retryGate.kind ?? "missing",
            "est_ms": retryGate.estMs ?? -1,
            "prior_processed": retryGate.priorProcessed ?? -1,
            "prior_total": retryGate.priorTotal ?? -1,
            "prior_elapsed_ms": retryGate.priorElapsedMs ?? -1,
            "cancel_line": cancelLine ?? "missing",
        ])
        XCTAssertEqual(
            retry.status, 503,
            "the retry of a payload whose prefill already exceeded the budget must be refused")
        XCTAssertEqual(
            retryGate.kind, "reject_prior_attempt",
            "the refusal is grounded in the measured progress of the cancelled attempt")
        XCTAssertNotNil(
            retryGate.priorProcessed,
            "the refusal carries processed/total/elapsed of the prior attempt")
        XCTAssertLessThan(
            retry.elapsedMs, 30_000,
            "the retry must not start another cold prefill")

        // A4 inside the same no-sample state: a short prompt still completes.
        // The gate records that it was inactive instead of pretending to have
        // screened this turn.
        let markAfter = CancelTrace.size()
        let small = try await send(
            body: [
                "model": "w4-budget-calibration",
                "input": "Reply with the single word: OK",
                "session_id": "w4-small-\(UUID().uuidString)",
                "stream": false,
                "temperature": 0,
                "max_completion_tokens": 8,
            ],
            headers: [:])
        let smallGateAfter = parseGate(gateLine(since: markAfter))
        record([
            "phase": "gate-insufficient",
            "status": small.status,
            "elapsed_ms": small.elapsedMs,
            "verdict": smallGateAfter.kind ?? "missing",
            "samples": smallGateAfter.samples ?? -1,
        ])
        XCTAssertEqual(small.status, 200)
        XCTAssertEqual(
            smallGateAfter.kind, "insufficient_samples",
            "with no samples the gate reports gate-inactive; it never invents a refusal")

        flush()
        print("[W4-CAL] done records=\(records.count)")
    }
}
