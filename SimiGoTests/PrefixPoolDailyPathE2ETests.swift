import XCTest
import MLXLMCommon
import MLX
import SimiGo2Experimental
import SimiGoRuntimeContract

@testable import SimiGo

/// B-5 real-device battery (SIMIGO17_PREFIX_POOL): the daily ChatSession
/// path serves a NEW session (new session_id = new storage key) from the
/// shared prefix pool when its conversation history was committed by an
/// earlier session — the agent-restart/reconnect scenario from the
/// 2026-09-27 log evidence (cold 47.6s @6.2K).
///
/// Registered metrics: pool-hit turn ≈ snapshot load + delta prefill
/// (seconds) vs cold full prefill (tens of seconds at the same context
/// size); structured pool events (`NativeMLXPrefixPool.events(after:)`:
/// bind / tokenExport / tokenHit) rather than trace text; disk rescan
/// admits after "restart" (fresh store instance over the same root).
final class PrefixPoolDailyPathE2ETests: XCTestCase {
    private let port = 18_231

    /// LOCALB-authorized E2E host (owner ruling, option (a)): assigned per
    /// test before runtime.start so every protected request passes the real
    /// B1 transport gate and B3 proof gate.
    private var host: LOCALBAuthorizedE2E.Host!

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

    /// ~16KB shared document (≈4-6K tokens) — the cold-prefill class from
    /// the registered evidence. A per-run nonce keeps the pool's persistent
    /// boundaries from serving THIS run's turn 1, so the cold baseline is a
    /// genuine full prefill and the warm/cold ratio stays meaningful.
    private let document: String = {
        var lines: [String] = []
        lines.append("Run scope: \(UUID().uuidString)")
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

    // MARK: - Structured evidence (2026-11-06)
    //
    // 池事件与逐轮遥测都从产品状态读：`NativeMLXPrefixPool.events(after:)`
    // 是池自己的类型化留档，`runtime.observation.snapshot()` 是引擎侧认可
    // 的逐轮真值。`native_mlx_trace.log` 只作事后审计证据，不参与判定——
    // 日志格式可以改、可以被降噪，验收结论不能因此失效。

    private func poolEventCursor() -> Int {
        NativeMLXPrefixPool.shared.eventCursor()
    }

    /// 轮询等一条指定类型的池事件（池事件在响应收口前同步登记，正常一轮
    /// 就有；这里留出短暂容忍，避免内存压力下抢在登记之前断言）。
    private func poolEvent(
        _ kind: NativeMLXPrefixPool.PoolEventKind, since cursor: Int,
        timeout: TimeInterval = 2
    ) -> NativeMLXPrefixPool.PoolEvent? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let hit = NativeMLXPrefixPool.shared.events(after: cursor)
                .first(where: { $0.kind == kind }) {
                return hit
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return NativeMLXPrefixPool.shared.events(after: cursor)
            .first { $0.kind == kind }
    }

    private func observation(_ runtime: NativeMLX, _ key: String) -> Any? {
        let snapshot = runtime.observation.snapshot()
        guard let value = snapshot[key], !(value is NSNull) else { return nil }
        return value
    }

    /// 池的 token 边界按 2048 网格导出（`exportTokenBoundaries`：全量边界 +
    /// 2048/4096/… 网格）。**被消费的前缀必须落在这张网格上**——这是「跨会话
    /// 复用真的经过了池」的结构判据，也是 `cacheEff` 达不到 1.00 的原因：
    /// 网格之上没有边界可用，尾巴只能重算。
    private static let prefixGridStep = 2048

    private func engineCacheHit(_ runtime: NativeMLX) -> Int {
        (observation(runtime, "cache_hit_tokens_engine_reported") as? Int) ?? 0
    }

    private func engineDelta(_ runtime: NativeMLX) -> Int {
        (observation(runtime, "prompt_tokens_engine_reported") as? Int) ?? 0
    }

    private func reuseMode(_ runtime: NativeMLX) -> String? {
        observation(runtime, "reported_reuse_mode") as? String
    }

    private func cacheEfficiency(_ runtime: NativeMLX) -> Double {
        (observation(runtime, "cache_efficiency") as? Double) ?? 0
    }

    /// 引擎报的首 token 时延。时钟（墙钟）在连续加载 30B 的套件里抖动大，
    /// 判据用引擎自己的分段计时，不用套件墙钟。
    private func ttft(_ runtime: NativeMLX) -> Double {
        (observation(runtime, "ttft_seconds") as? Double) ?? 0
    }

    /// 某一类池事件的全部 token 主张（导出集 = 全量边界 + 网格点）。
    private func poolEventTokens(
        _ kind: NativeMLXPrefixPool.PoolEventKind, since cursor: Int
    ) -> [Int] {
        NativeMLXPrefixPool.shared.events(after: cursor)
            .filter { $0.kind == kind }
            .map(\.tokens)
    }

    private func chatCompletion(
        sessionId: String, messages: [[String: Any]], maxTokens: Int = 8
    ) async throws -> (text: String, seconds: Double) {
        let body = try JSONSerialization.data(withJSONObject: [
            "model": "daily",
            "messages": messages,
            "max_tokens": maxTokens,
            "stream": false,
            "session_id": sessionId,
        ])
        let start = Date()
        let (data, response) = try await LOCALBAuthorizedE2E.send(
            host: host,
            port: port,
            method: "POST",
            path: "/v1/chat/completions",
            contentType: "application/json",
            body: body
        )
        let seconds = Date().timeIntervalSince(start)
        XCTAssertEqual(
            response.statusCode, 200,
            String(decoding: data, as: UTF8.self))
        let bodyJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = bodyJSON?["choices"] as? [[String: Any]]
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
        defer { Task { await runtime.stop() } }
        let logStart = poolEventCursor()

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
        XCTAssertNotNil(
            poolEvent(.export, since: logStart),
            "turn 1 exports its boundary: "
                + "\(NativeMLXPrefixPool.shared.events(after: logStart))")
        // 导出集 = 全量边界 + 2048 网格点（实测 9927 / 2048 / 4096 / 6144 /
        // 8192）。网格点是跨会话复用的**唯一**来源，所以判据是「导出集里
        // 至少有一个网格点」，不是「导出集每一项都在网格上」。
        let exports = poolEventTokens(.tokenExport, since: logStart)
        XCTAssertTrue(
            exports.contains { $0 % Self.prefixGridStep == 0 },
            "turn 1 must export 2048-grid boundaries, got \(exports)")
        // 冷轮的实际预填量 = 后续 delta 的比较基准（引擎报的值，非请求值）。
        let coldPromptTokens = engineDelta(runtime)
        XCTAssertGreaterThan(coldPromptTokens, Self.prefixGridStep,
                             "the cold turn must have prefilled the document")

        // --- Turn 2 (session B = NEW session id, A's history + one user
        //     message): the agent-reconnect scenario. Same-session reuse
        //     CANNOT fire (different storage key); the pool must. ---
        let messagesB = messagesA + [message("assistant", replyA), message("user", "Say DONE.")]
        let (_, warmSeconds) = try await chatCompletion(
            sessionId: "pool-battery-B", messages: messagesB)

        // Registered metric shape（2026-11-06 对齐网格现实）。
        //
        // 旧断言要求 `poolBind messages=3` + `mode=restore` + `cacheEff=1.00`，
        // 那是 message 级 bind 的形状。日常路径实际走的是 token 网格钩子
        // （`ChatSession.crossSessionPrefixLookup`）：2048/4096/6144/8192 网格点
        // 命中多少就少预填多少，网格之上没有点，所以 cacheEff 天然到不了 1.00。
        // 判据改成网格不变式——仍然可证伪，而且更贴近产品行为。
        let hit = engineCacheHit(runtime)
        let delta = engineDelta(runtime)
        XCTAssertNotNil(
            poolEvent(.tokenHit, since: logStart),
            "the token-level pool must admit a boundary for the new session")
        XCTAssertEqual(
            reuseMode(runtime), "cross-session",
            "the new session must consume the shared prefix from the pool")
        XCTAssertGreaterThan(hit, 0, "the pool must serve a real token prefix")
        XCTAssertEqual(
            hit % Self.prefixGridStep, 0,
            "consumed prefix \(hit) must be an exported grid boundary")
        XCTAssertTrue(
            exports.contains(hit),
            "consumed prefix \(hit) must be a boundary exported BEFORE this turn, "
                + "got \(exports)")
        XCTAssertGreaterThanOrEqual(
            hit, 2 * Self.prefixGridStep,
            "at least one full grid step beyond the first must be reused")
        XCTAssertLessThan(
            delta, coldPromptTokens / 2,
            "only the tail may be re-prefilled: delta=\(delta) "
                + "cold=\(coldPromptTokens)")
        XCTAssertGreaterThanOrEqual(
            cacheEfficiency(runtime), 0.75,
            "grid-limited hit quality must still dominate the turn")
        XCTAssertLessThan(
            warmSeconds, coldSeconds * 0.75,
            "pool turn \(warmSeconds)s should be well under cold \(coldSeconds)s")

        // --- B-6: a genuinely NEW conversation sharing only the document
        //     (different first question) — message boundaries diverge at
        //     message 2, but the TOKEN prefix (the document) matches a
        //     grid boundary exported by turn 1. ---
        let messagesC = [message("system", "You are a precise assistant. Internal "
            + "specification document:\n" + document),
            message("user", "What is 2+2? Answer with the numeral only.")]
        let cursorC = poolEventCursor()
        let (replyC, crossSeconds) = try await chatCompletion(
            sessionId: "pool-battery-C", messages: messagesC)
        XCTAssertFalse(replyC.isEmpty)
        XCTAssertEqual(
            reuseMode(runtime), "cross-session",
            "token-level cross-session seeding must fire for a shared-document "
                + "new session")
        XCTAssertNotNil(
            poolEvent(.tokenHit, since: cursorC),
            "the token-level pool admitted a boundary for the cross-session turn")
        XCTAssertEqual(
            engineCacheHit(runtime) % Self.prefixGridStep, 0,
            "the cross-session hit must also land on a grid boundary")
        XCTAssertLessThan(
            crossSeconds, coldSeconds,
            "cross-session turn \(crossSeconds)s should stay well under the cold "
                + "level (code-level markers asserted above)")

        // --- Restart-warm: a fresh store over the same disk root admits
        //     the committed boundary without any live session. ---
        let freshStore = PrefixSnapshotStore(
            root: RuntimeCachePaths.prefixPoolRoot,
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
    ///   D5  Parent/Child deterministic
    ///
    /// 2026-11-06 断言对齐网格现实：池只在 **2048 网格**上导出可消费边界
    /// （`exportTokenBoundaries`），网格之上没有点，尾巴必然重算，所以
    /// `cacheEff == 1.00` 物理上不可达（eff = hit/(hit+delta)，delta > 0）。
    /// 断言改为可证伪的网格不变式 + 相对 delta/时序比率。
    ///
    /// **两条路由（实测，同一份代码连跑三次）**：子代要么走 message 级
    /// bind→restore（`poolBind messages=3`，恢复整段前缀，mode=restore），
    /// 要么走 token 网格跨会话（`poolTokenHit tokens=8192`，
    /// mode=cross-session）。哪条先命中取决于池的状态，因此 D1–D3 只断言
    /// **两条路由都成立的不变式**；路由本身作为测量结果记录在消息里。
    ///
    /// FORK-3 step-9 的绑定登记只在 bind 路由上发生（`bindings.bind(
    /// executionID: 子代)`），所以它的断言也只在 bind 路由上生效。判据是
    /// 「子代在执行绑定账本里有自己的 ACTIVE 行」，不是「账本行数变多」
    /// ——导出路径每轮也 bind，数行数什么也证明不了（旧断言就是这条假证据）。
    func testF3DeviceAcceptanceBattery() async throws {
        // F3 transcript-restoration fix landed in mlx-swift-lm; this battery
        // is now a live acceptance gate for the five physical conditions.
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("daily model not present: \(modelPath)")
        }
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
        defer { Task { await runtime.stop() } }
        // start() returns before the HTTP surface is accepting: poll
        // readiness so the first request never hits a closed port. The
        // poll itself is an authorized protected request — an unauthorized
        // GET /v1/models is refused by the B3 gate.
        var httpReady = false
        for _ in 0..<120 {
            if let result = try? await LOCALBAuthorizedE2E.send(
                host: host, port: port, method: "GET", path: "/v1/models"),
                result.1.statusCode == 200 {
                httpReady = true
                break
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        XCTAssertTrue(httpReady, "runtime HTTP surface never became ready")
        let logStart = poolEventCursor()

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
        // 冷轮的实际预填量 = 后续 delta 的比较基准（引擎报的值，非请求值）。
        let coldPromptTokens = engineDelta(runtime)
        let coldTTFT = ttft(runtime)
        XCTAssertGreaterThan(
            coldPromptTokens, Self.prefixGridStep,
            "the cold parent turn must have prefilled the shared document")
        XCTAssertGreaterThan(coldTTFT, 1, "the cold turn must report its TTFT")

        // --- Parent turn 2: warm continuation (D4 baseline; its wall clock
        //     is only a sanity reference, D4 evidence is code-level) ---
        let msgsP2 = msgsP1 + [message("assistant", replyP1), message("user", "Say WARM.")]
        let (replyP2, _) = try await chatCompletion(
            sessionId: "f3-parent", messages: msgsP2)
        XCTAssertFalse(replyP2.isEmpty)

        // --- FORK: Child C = NEW session id, Parent's full history + ΔC ---
        let childHistory = msgsP2 + [message("assistant", replyP2)]
        let msgsC = childHistory + [message("user", "Say DONE.")]
        let (replyC, childSeconds) = try await chatCompletion(
            sessionId: "f3-child", messages: msgsC)
        XCTAssertFalse(replyC.isEmpty)

        // --- D1/D2/D3: the Child bound the shared prefix and paid only ΔC ---
        //
        // 实测（2026-11-06，Qwen3-Coder-30B-A3B-4bit，连跑三次）：
        //   bind 路由   poolBind messages=3 → restore 9748 token，delta=98，
        //               cacheEff=0.99，ttft=3.30s（冷 11.27s）
        //   grid 路由   poolTokenHit tokens=8192 → cross-session，delta=1826，
        //               cacheEff=0.82，ttft=6.64s（冷 11.83s）
        // 两条都会发生，所以判据是交集：可证明的前缀复用 + 只付尾巴。
        let childHit = engineCacheHit(runtime)
        let boundRoute = poolEvent(.bind, since: logStart) != nil
        let gridRoute = poolEvent(.tokenHit, since: logStart) != nil
        XCTAssertTrue(
            boundRoute || gridRoute,
            "D1: child consumed a pooled prefix — neither the bound restore nor "
                + "the token-grid cross-session route fired (started from 0)")
        XCTAssertGreaterThanOrEqual(
            childHit, 4 * Self.prefixGridStep,
            "D1: reused prefix \(childHit) tokens must be at least the largest "
                + "grid boundary in play (cold \(coldPromptTokens); route "
                + (boundRoute ? "bind" : "grid") + ")")
        let childMode = reuseMode(runtime)
        XCTAssertNotEqual(
            childMode, "cold",
            "D2: child must not take a cold materialization path")
        XCTAssertTrue(
            childMode == "restore" || childMode == "cross-session",
            "D2: measured reuse routes are restore (message-bound) and "
                + "cross-session (token grid), got \(childMode ?? "nil")")
        // FORK-3 step-9 只在 bind 路由上登记（executionID 是会话键，按前缀
        // 匹配以避免依赖 traceKey 的压缩形式）。
        if boundRoute {
            let childBinding = NativeMLXPrefixPool.shared.bindings.allRows()
                .last { $0.executionID.contains("f3-child") && $0.state == .active }
            XCTAssertNotNil(
                childBinding, "step-9: the child execution must be bound")
            XCTAssertGreaterThan(
                childBinding?.boundPositionAtBind ?? 0, 0,
                "step-9: the child starts at a non-zero boundary")
        }
        // Code-level D3 witness: 引擎报的 promptTokens 是本轮真正预填的
        // delta，不是墙钟代理值。
        let childDeltaTokens = try XCTUnwrap(
            observation(runtime, "prompt_tokens_engine_reported") as? Int,
            "D3: the child turn reported no engine prompt token count")
        XCTAssertLessThan(
            childDeltaTokens, coldPromptTokens / 3,
            "D3: child paid \(childDeltaTokens) delta tokens vs cold "
                + "\(coldPromptTokens) — a re-prefill would be the full size")
        XCTAssertGreaterThanOrEqual(
            cacheEfficiency(runtime), 0.80,
            "D3: the reused prefix must dominate the child turn (measured "
                + "0.99 on the bind route, 0.82 on the grid route)")
        XCTAssertLessThan(
            ttft(runtime), coldTTFT * 0.75,
            "D3: child TTFT (\(ttft(runtime))s) must be well below the cold "
                + "prefill (\(coldTTFT)s); wall clock was \(childSeconds)s vs "
                + "\(coldSeconds)s")

        // --- D4: Parent continues AFTER the child forward — no
        // attributable regression (its own warm continuation level). ---
        let msgsP3 = childHistory + [message("user", "Say MORE.")]
        let (replyP3, _) = try await chatCompletion(
            sessionId: "f3-parent", messages: msgsP3)
        XCTAssertFalse(replyP3.isEmpty)
        // D4 主证据 = 代码级：P3（messages=6 的 parent 轮）必须仍是 parent
        // 缓存上的 extend，且只补算新增的尾部——child 前向未扰动 parent
        // 缓存。cacheEff 只到 ~0.99：尾部没有网格边界。
        //
        // 时间**不进**判据：同形态的 extend 轮在两次连跑里差一个数量级 ——
        // 第 1 次 P2 ttft=8.05s / P3 ttft=13.09s（冷 12.25s），第 2 次
        // P2=1.50s / P3=0.55s（冷 11.27s），delta 都是 ~96 token。抖动来自
        // 机器（内存压力/热降频），大于 D4 想识别的差异；拿它当门只会产出
        // 假失败。D4 的证据是缓存形态：extend + 尾部 delta + cacheEff。
        XCTAssertEqual(
            reuseMode(runtime), "extend",
            "D4: parent after-child turn must remain a warm extend")
        XCTAssertLessThan(
            engineDelta(runtime), 512,
            "D4: the parent continuation may only pay the new tail")
        XCTAssertGreaterThanOrEqual(
            cacheEfficiency(runtime), 0.95,
            "D4: the parent continuation must remain a near-full hit")

        // --- D5: determinism — the same child request repeats
        // identically. ---
        let (replyC2, _) = try await chatCompletion(
            sessionId: "f3-child", messages: msgsC)
        XCTAssertEqual(
            replyC2.trimmingCharacters(in: .whitespacesAndNewlines),
            replyC.trimmingCharacters(in: .whitespacesAndNewlines),
            "child output deterministic")
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
