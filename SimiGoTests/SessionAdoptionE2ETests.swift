import XCTest
import SQLite3
import MLXLMCommon
import SimiGo2Experimental
import SimiGoRuntimeContract

@testable import SimiGo

/// #90 A/B/C 的运行时门（真实模型，测试层窗口）。
///
/// 判的是产品现象本身：客户端逐轮携带**新的请求级 `sessionId`**（不带
/// `session_id` ⇒ `HTTPServer` 铸造 `openai-request:<uuid>`）却回传逐条追加
/// 的同一份转录。按 `storageKey` 查表必然 miss，修前每轮都全量冷 prefill。
///
/// 本门同时判**会话所有权**（owner 2026-10-28 验收点）：A 建立分片 → B 采纳
/// 并推进 → C 从 B 的新历史继续 → 陈旧 A 重放不得改写 B/C 的分支 → 中途
/// 取消必须逐出且不留可采纳别名。断言用引擎只读投影
/// `executionStateSnapshot()`（卡片 label/historyCount/mapKey），三种实现
/// 形态互相可区分：共享别名（label 仍是旧身份）、只重绑不移动键（label
/// 缺 `#` 分片后缀）、所有权转移（label 为本轮且带 `#` 后缀）。
///
/// 两个时点分开断言（owner 2026-10-28 时序裁定）：**采纳时**原键即消失、
/// 新属主持有带 `#` 的键；**取消后**属主键与全部残留映射一并清除，其余
/// 分片的键逐字节不变。「必须冷」不靠取消结果反推，而由 `sessionAdoptMiss`
/// 的候选数与逐条拒绝理由，加上 `reuse=false` / `promptTokens` 读数直接证明。
///
/// 主证是代码级的（追踪行里的 `sessionAdopt` / `own=transfer` / `adopt=1` /
/// `mode=extend` / `promptTokens=` / `cancelCommitSkip` / `adoptedCancelEvict`），
/// 墙钟比只作宽松 sanity——套件连续加载模型时抖动大。
///
/// 2026-10-30 ADR（断连 → detach）后，D–E 两相（取消/逐出）显式退役：A–C
/// 照常跑，D 之前以 `XCTSkip` 收尾并说明需按 detach 语义重设计；旧断言保留在
/// `SESSION_ADOPTION_LEGACY_CANCEL=1` 门后，只供 ADR 前二进制重放。
///
/// 读数边界（owner 裁定）：本文件的任何读数只绑定它自己这次跑的源码与
/// 二进制，不得挪用 a18 / build-31 的旧读数背书；跑之前必须记录构建身份。
final class SessionAdoptionE2ETests: XCTestCase {
    private let port = 18_241

    private var host: LOCALBAuthorizedE2E.Host!

    /// 日常路径模型（E-line 首个验证过的架构）。缺省走 HF 缓存，
    /// `SESSION_ADOPTION_MODEL_PATH` 可覆盖。
    private var modelPath: String {
        if let override = ProcessInfo.processInfo.environment["SESSION_ADOPTION_MODEL_PATH"] {
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

    /// ~16KB 共享文档（≈4–6K token）——冷 prefill 的量级来源。每次跑用新
    /// nonce，避免持久化边界替本轮的第一轮付账，冷/热比才有意义。
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

    /// IS/ES 侧可能被日常 Chat 路径触及的表；用于逐轮写库形状对账。
    private let esisTables = [
        "information_demands", "information_advancements", "information_items",
        "chat_execution_links", "settlement_summaries", "settlement_consumptions",
        "retrieval_settlements", "chat_messages",
    ]

    // MARK: - helpers

    private func message(_ role: String, _ content: String) -> [String: Any] {
        ["role": role, "content": content]
    }

    private var traceURL: URL {
        SimiGoPaths.logs.appendingPathComponent("native_mlx_trace.log")
    }

    private func traceLogSize() -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: traceURL.path)
        return attributes?[.size] as? Int ?? 0
    }

    /// 窗口 = `since` 之后的全部新增字节。轮次串行 ⇒ 归因给本轮；完成行偶尔
    /// 晚于 HTTP 响应落盘，故轮询而不是抢。
    private func traceWindow(sinceByteOffset offset: Int) -> String {
        guard let data = try? Data(contentsOf: traceURL), data.count > offset else { return "" }
        return String(decoding: data.suffix(data.count - offset), as: UTF8.self)
    }

    private func traceWindow(
        sinceByteOffset offset: Int, containing markers: [String], timeout: TimeInterval = 5
    ) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let line = traceWindow(sinceByteOffset: offset)
                .split(separator: "\n")
                .first { line in markers.allSatisfy(line.contains) }
            if let line { return String(line) }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return nil
    }

    private func windowHas(_ marker: String, sinceByteOffset offset: Int) -> Bool {
        traceWindow(sinceByteOffset: offset).contains(marker)
    }

    private func number(from line: String, marker: String) -> Double? {
        guard let range = line.range(of: marker) else { return nil }
        let digits = line[range.upperBound...].prefix { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(digits)
    }

    /// 本轮的完成行（含 `rawEv=` 尾块即为完成行），并断言它存在——所有
    /// 「本轮没有 X」的否定判据都靠它保证不空转。超时按冷 prefill 量级给：
    /// 本机 30B 冷 prefill 实测 15–21s，5s 会把慢轮误判成「没有完成行」。
    private func completionLine(
        sinceByteOffset offset: Int, timeout: TimeInterval = 120
    ) throws -> String {
        try XCTUnwrap(
            traceWindow(sinceByteOffset: offset, containing: ["rawEv="], timeout: timeout),
            "本轮完成行缺失，后续判据将无从成立（若窗口里出现 [IS_REUSE]，"
                + "说明本轮被已结算答案复用应答、根本没进模型）")
    }

    private func sessionLabel(of line: String) -> String? {
        guard let range = line.range(of: "session=") else { return nil }
        return String(line[range.upperBound...].prefix { $0 != " " })
    }

    /// `sessionAdopt key=<traceKey>` —— 采纳成功行里的本轮属主身份。
    private func adoptKey(of line: String) -> String? {
        guard let range = line.range(of: "key=") else { return nil }
        return String(line[range.upperBound...].prefix { $0 != " " })
    }

    /// `session_id` 传 nil = 不带该字段，让 HTTPServer 走请求级铸造路径——
    /// 这正是 #90 现象的发生条件。
    @discardableResult
    private func chatCompletion(
        sessionId: String?,
        messages: [[String: Any]],
        extra: [String: Any] = [:],
        maxTokens: Int = 8
    ) async throws -> (text: String, seconds: Double) {
        var body: [String: Any] = [
            "model": "daily",
            "messages": messages,
            "max_tokens": maxTokens,
            "stream": false,
        ]
        if let sessionId { body["session_id"] = sessionId }
        for (key, value) in extra { body[key] = value }

        let start = Date()
        let (data, response) = try await LOCALBAuthorizedE2E.send(
            host: host,
            port: port,
            method: "POST",
            path: "/v1/chat/completions",
            contentType: "application/json",
            body: try JSONSerialization.data(withJSONObject: body)
        )
        let seconds = Date().timeIntervalSince(start)
        XCTAssertEqual(response.statusCode, 200, String(decoding: data, as: UTF8.self))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let text = (choices?.first?["message"] as? [String: Any])?["content"] as? String ?? ""
        return (text, seconds)
    }

    /// 流式请求任务：调用方在生成中途 `cancel()`。取消会关闭连接，
    /// HTTPServer 的对端关闭监听（markGenerationStarted 时挂起）据此走
    /// terminate(cancelGeneration: true) → cancelGeneration(requestId)，
    /// 与真机断连同一路径。同时返回已收字节计数：取消必须落在**流已经
    /// 活着**之后，否则监听尚未挂起，取消窗口本身不成立。
    private final class ByteCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func add(_ n: Int) { lock.lock(); value += n; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    private func streamingChatTask(
        messages: [[String: Any]], maxTokens: Int
    ) async throws -> (task: Task<Int, Never>, streamed: ByteCounter) {
        let body: [String: Any] = [
            "model": "daily",
            "messages": messages,
            "max_tokens": maxTokens,
            "stream": true,
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        let path = "/v1/chat/completions"
        let headers = try await LOCALBAuthorizedE2E.proofHeaders(
            host: host, port: port, method: "POST", target: path,
            contentType: "application/json", body: payload)
        var request = URLRequest(
            url: URL(string: "https://127.0.0.1:\(port)\(path)")!,
            timeoutInterval: 900)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = payload
        let session = host.session
        let streamed = ByteCounter()
        let task = Task {
            var received = 0
            do {
                let (bytes, _) = try await session.bytes(for: request)
                for try await line in bytes.lines {
                    received += line.utf8.count
                    streamed.add(line.utf8.count)
                }
            } catch {
                // 取消即关闭连接（预期路径）。
            }
            return received
        }
        return (task, streamed)
    }

    private func esisCounts() -> [String: Int] {
        var handle: OpaquePointer?
        // 只读打开：本测试不得改动权威库。库文件尚未建立 = 各表零行。
        guard sqlite3_open_v2(
            SimiGoPaths.databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil
        ) == SQLITE_OK else {
            sqlite3_close(handle)
            return Dictionary(uniqueKeysWithValues: esisTables.map { ($0, 0) })
        }
        defer { sqlite3_close(handle) }
        var counts: [String: Int] = [:]
        for table in esisTables {
            // 表名来自上面的固定数组，不是外部输入。
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(handle, "SELECT COUNT(*) FROM \(table);", -1, &stmt, nil)
                == SQLITE_OK, sqlite3_step(stmt) == SQLITE_ROW {
                counts[table] = Int(sqlite3_column_int64(stmt, 0))
            } else {
                counts[table] = 0  // 迁移尚未建表
            }
            sqlite3_finalize(stmt)
        }
        return counts
    }

    /// 异步结算/摘要写入可能滞后于响应；读到连续两次不变才认账，避免把
    /// 时序噪声读成写库差异。
    private func stableESICounts() -> [String: Int] {
        var previous = esisCounts()
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.2)
            let current = esisCounts()
            if current == previous { return current }
            previous = current
        }
        return previous
    }

    private func delta(_ before: [String: Int], _ after: [String: Int]) -> [String: Int] {
        esisTables.reduce(into: [:]) { counts, table in
            counts[table] = (after[table] ?? 0) - (before[table] ?? 0)
        }
    }

    /// `chat_execution_links` 的行键（session_id）。该表按稳定身份登记：
    /// 请求级身份（`*-request:`）根本不应出现在这里——采纳是引擎内部续接，
    /// 不是身份合并。`nil` = 打开/准备/读取失败，与「零行」区分开：结算与
    /// 摘要写入是异步的，WAL 检查点会短暂持锁，一次 BUSY 不得把否定判据
    /// 变成空转。故设 busy_timeout 并把任何读失败如实上报。
    private func chatExecutionLinkIds() -> [String]? {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            SimiGoPaths.databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil
        ) == SQLITE_OK else {
            sqlite3_close(handle)
            return nil
        }
        defer { sqlite3_close(handle) }
        sqlite3_busy_timeout(handle, 3_000)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(
            handle, "SELECT session_id FROM chat_execution_links;", -1, &stmt, nil
        ) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        var ids: [String] = []
        var rc = sqlite3_step(stmt)
        while rc == SQLITE_ROW {
            if let text = sqlite3_column_text(stmt, 0) {
                ids.append(String(cString: text))
            }
            rc = sqlite3_step(stmt)
        }
        guard rc == SQLITE_DONE else { return nil }
        return ids
    }

    // MARK: - 驻留曲线（#90 B）

    /// 引擎账本行（几何估算字节）与本进程物理足迹**分开打印**：预算估算
    /// 可以精确，却不意味着 RSS/MLX 实际内存被同样的字节数硬性限制。
    /// 账本只有引擎自己算得出（逐会话命中 token 数 × 几何 + 每会话固定态），
    /// 所以这里引用追踪行原文，不做二次估算。
    private func residencySample(
        _ phase: String, sinceByteOffset offset: Int
    ) {
        let ledger = traceWindow(sinceByteOffset: offset)
            .split(separator: "\n")
            .last(where: { $0.contains("residencyLedger") })
            .map { String($0) } ?? "absent"
        let footprint = RuntimeTuning.footprintBytes()
        print("[#90 residency] \(phase) footprint=\(footprint)B \(ledger)")
    }

    // MARK: - 会话所有权现场

    private func requestScopedCards(
        _ runtime: NativeMLX
    ) -> [EngineExecutionStateSnapshot.SessionCard] {
        runtime.executionStateSnapshot().sessions.filter { $0.requestScoped }
    }

    /// 所有权现场打印（报告要能直接读到属主身份与账本条数）。
    private func ownershipSnapshot(
        _ runtime: NativeMLX, _ phase: String
    ) -> [EngineExecutionStateSnapshot.SessionCard] {
        let cards = requestScopedCards(runtime)
        print(
            "[#90 ownership] \(phase): "
                + cards.map {
                    "\($0.label) hist=\($0.historyCount) key=…\($0.mapKey.suffix(10))"
                }.joined(separator: " | "))
        return cards
    }

    /// 互斥形态判据：
    /// - 共享别名（修前）：卡片仍是旧请求身份 ⇒ label 不以本轮 traceKey 开头。
    /// - 只重绑身份不移动键：label 变为本轮，但 mapKey 仍是旧键 ⇒ 缺 `#` 分片后缀。
    /// - 所有权转移（本实现）：label 以本轮 traceKey 开头且保留 `#` 后缀。
    private func assertSoleOwner(
        _ cards: [EngineExecutionStateSnapshot.SessionCard],
        label: String,
        historyCount: Int,
        phase: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            cards.count, 1,
            "\(phase): 请求级分片应恰好一张，实际 \(cards.map(\.label))",
            file: file, line: line)
        guard let card = cards.first else { return }
        XCTAssertTrue(
            card.label.hasPrefix(label),
            "\(phase): 属主身份应为 \(label)，实际 \(card.label)",
            file: file, line: line)
        XCTAssertTrue(
            card.label.contains("#"),
            "\(phase): 键必须随身份一起转移（mapKey 仍是旧键 ⇒ 只重绑未转移）",
            file: file, line: line)
        XCTAssertEqual(
            card.historyCount, historyCount, "\(phase): 账本条数",
            file: file, line: line)
    }

    // MARK: - 主门

    func testAppendOnlyTranscriptAcrossRequestLevelSessionsTransfersOwnership() async throws {
        try XCTSkipIf(
            RuntimeTuning.prefixPoolEnabled,
            "本门判的是引擎内采纳路径；前缀池开启时边界优先级不同，须用默认关闭窗跑")
        try XCTSkipIf(
            !FileManager.default.fileExists(atPath: modelPath),
            "daily model not present: \(modelPath)")
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty else {
            throw XCTSkip("SIMIGO_HOME not injected; ES/IS 对账需在隔离根内跑")
        }
        XCTAssertTrue(
            SimiGoPaths.databaseURL.path.hasPrefix((home as NSString).standardizingPath),
            "authoritative store resolves outside the isolation root: "
                + SimiGoPaths.databaseURL.path)

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

        // 预热轮用**稳定** sessionId：它不进请求级候选集（作用域判据本身
        // 也是被测对象之一），且吸收模型加载成本。
        _ = try await chatCompletion(
            sessionId: "sa-warmup", messages: [message("user", "Say HI.")], maxTokens: 4)

        let doc = "You are a precise assistant. Internal specification document:\n" + document
        let turn1 = [message("system", doc), message("user", "Reply READY.")]

        // --- A：请求级身份 A，冷 prefill，建立活分片。 ---
        let t1Start = traceLogSize()
        let before1 = stableESICounts()
        let (reply1, coldSeconds) = try await chatCompletion(sessionId: nil, messages: turn1)
        let line1 = try completionLine(sinceByteOffset: t1Start)
        let delta1 = delta(before1, stableESICounts())
        XCTAssertFalse(reply1.isEmpty)
        XCTAssertFalse(windowHas("adopt=1", sinceByteOffset: t1Start), "冷轮无采纳")
        XCTAssertFalse(windowHas("own=transfer", sinceByteOffset: t1Start))
        let coldPromptTokens = try XCTUnwrap(
            number(from: line1, marker: "promptTokens="), "冷轮完成行缺 promptTokens")
        XCTAssertGreaterThan(coldPromptTokens, 1_000, "冷轮必须真的付了整份文档的 prefill")
        let labelA = try XCTUnwrap(sessionLabel(of: line1))
        residencySample("A(cold)", sinceByteOffset: t1Start)
        XCTAssertEqual(
            requestScopedCards(runtime).count, 1,
            "A 之后应恰好一张请求级分片（请求级身份各占其键）")

        // --- B：新的请求级 sessionId，A 的转录 + 一条新用户消息 ⇒ #90 正例。 ---
        let turn2 = turn1 + [message("assistant", reply1), message("user", "Say DONE.")]
        let t2Start = traceLogSize()
        let before2 = stableESICounts()
        let (reply2, warmSeconds) = try await chatCompletion(sessionId: nil, messages: turn2)
        let line2 = try completionLine(sinceByteOffset: t2Start)
        let delta2 = delta(before2, stableESICounts())

        let adoptLineB = try XCTUnwrap(
            traceWindow(sinceByteOffset: t2Start, containing: ["sessionAdopt key="]),
            "A: 采纳必须发生（严格前缀 + 同作用域 + 同配置 + 不在途 + 仅请求级）")
        XCTAssertTrue(
            adoptLineB.contains("own=transfer"),
            "采纳必须走所有权转移（own=transfer），不是共享别名：\(adoptLineB)")
        XCTAssertTrue(line2.contains("adopt=1"), "C: 采纳轮完成行要显式声明 \(line2)")
        XCTAssertTrue(line2.contains("mode=extend"), "owner 判据：第二轮必须 extend \(line2)")
        XCTAssertTrue(line2.contains("reuse=true"), "B: 复用同一活执行，不是新建分片 \(line2)")
        let adoptPromptTokens = try XCTUnwrap(
            number(from: line2, marker: "promptTokens="), "采纳轮完成行缺 promptTokens")
        XCTAssertLessThan(
            adoptPromptTokens, coldPromptTokens,
            "本轮只付 delta：promptTokens 必须明显小于冷轮整份文档")
        let cacheHit = try XCTUnwrap(
            number(from: line2, marker: "cacheHitTokens="),
            "采纳轮必须报出命中的前缀 token 数")
        XCTAssertGreaterThan(cacheHit, 0)

        // 宽松 sanity（非主证）：extend 轮的墙钟应低于冷轮。
        XCTAssertLessThan(
            warmSeconds, coldSeconds,
            "adopt 轮 \(warmSeconds)s 不应高于冷轮 \(coldSeconds)s")
        XCTAssertFalse(reply2.isEmpty)

        // --- C: 身份不合并。追踪里的 session= 仍是本轮自己的请求级身份。 ---
        let labelB = try XCTUnwrap(sessionLabel(of: line2))
        XCTAssertNotEqual(
            labelA, labelB, "两轮各自按原始请求级身份登记：\(labelA) vs \(labelB)")

        // --- 所有权判据（owner：必须能区分共享别名 / 只重绑 / 转移）。B 之后
        //     这份可变会话的唯一属主是 B；A 的身份不得映射到 B 推进后的分支。 ---
        let cardsAfterB = ownershipSnapshot(runtime, "after-B")
        assertSoleOwner(cardsAfterB, label: labelB, historyCount: 5, phase: "B 采纳后")
        residencySample("B(adopt)", sinceByteOffset: t2Start)
        XCTAssertFalse(
            cardsAfterB.contains { $0.label.hasPrefix(labelA) },
            "A 的身份不得映射到 B 推进后的分支（\(labelA) 仍在表里 ⇒ 共享别名或键未转移）")

        // --- 落库面（D）：采纳轮的逐轮写库形状必须与冷轮同形。 ---
        // `chat_execution_links` 单独判：该表按**稳定身份**做 INSERT OR
        // REPLACE、写入异步滞后于响应，窗口计数会被上一轮尾写污染（实测
        // warmup 的行落进冷轮窗口）。它的身份语义用行键本身判——见最终断言
        // 「链接表不得出现请求级身份」。
        func writeShape(_ counts: [String: Int]) -> [String: Int] {
            counts.filter { $0.key != "chat_execution_links" }
        }
        XCTAssertEqual(
            writeShape(delta2), writeShape(delta1),
            "跨请求采纳不得改变 ES/IS 逐轮写入（多写一行=把引擎内部复用登记成身份）")

        // --- C：B 的转录 + B 的真实回复 + 新用户消息 ⇒ 从 B 手里继续。 ---
        let turn3 = turn2 + [message("assistant", reply2), message("user", "Say NEXT.")]
        let t3Start = traceLogSize()
        let (reply3, _) = try await chatCompletion(sessionId: nil, messages: turn3)
        let line3 = try completionLine(sinceByteOffset: t3Start)
        XCTAssertTrue(
            windowHas("own=transfer", sinceByteOffset: t3Start), "C 轮必须采纳 B 的分片")
        XCTAssertTrue(line3.contains("adopt=1"))
        XCTAssertTrue(line3.contains("mode=extend"), "owner 判据：C 轮仍须 extend \(line3)")
        XCTAssertLessThan(
            try XCTUnwrap(number(from: line3, marker: "promptTokens=")),
            coldPromptTokens, "C 轮仍只付 delta")
        XCTAssertFalse(reply3.isEmpty)
        let labelC = try XCTUnwrap(sessionLabel(of: line3))
        XCTAssertNotEqual(labelC, labelB)

        let cardsAfterC = ownershipSnapshot(runtime, "after-C")
        assertSoleOwner(cardsAfterC, label: labelC, historyCount: 7, phase: "C 采纳后")
        residencySample("C(adopt)", sinceByteOffset: t3Start)
        let cMapKey = try XCTUnwrap(cardsAfterC.first?.mapKey)
        XCTAssertFalse(cardsAfterC.contains { $0.label.hasPrefix(labelA) })
        XCTAssertFalse(
            cardsAfterC.contains { $0.label.hasPrefix(labelB) },
            "B 的映射应随所有权转移到 C，而不是继续指向推进后的分支")

        // --- 陈旧 A：重放 A 的第二轮，但换一条用户消息（与 B 分支决定性
        //     分叉，不依赖采样是否重复）⇒ 长度判据不过，只能冷路径。 ---
        let staleA = turn1 + [message("assistant", reply1), message("user", "Say STALE.")]
        let t4Start = traceLogSize()
        try await chatCompletion(sessionId: nil, messages: staleA)
        let line4 = try completionLine(sinceByteOffset: t4Start)
        XCTAssertFalse(
            windowHas("own=transfer", sinceByteOffset: t4Start),
            "陈旧 A 的转录比手中分支短 ⇒ 不得采纳任何分片")
        XCTAssertFalse(line4.contains("adopt=1"))
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(number(from: line4, marker: "promptTokens=")),
            coldPromptTokens * 0.9, "陈旧 A 只能整份冷 prefill")
        let labelStale = try XCTUnwrap(sessionLabel(of: line4))
        residencySample("stale-A(cold)", sinceByteOffset: t4Start)

        let cardsAfterStale = ownershipSnapshot(runtime, "after-stale-A")
        XCTAssertEqual(cardsAfterStale.count, 2, "陈旧 A 新建自己的分片，不得接管 C 的")
        let cStill = try XCTUnwrap(
            cardsAfterStale.first { $0.mapKey == cMapKey },
            "C 的映射必须在陈旧 A 之后原样存在")
        XCTAssertEqual(cStill.historyCount, 7, "C 的账本不得被陈旧 A 推进")
        XCTAssertTrue(cStill.label.hasPrefix(labelC))
        let staleCard = try XCTUnwrap(cardsAfterStale.first { $0.mapKey != cMapKey })
        XCTAssertEqual(staleCard.historyCount, 5)
        XCTAssertFalse(
            staleCard.label.hasPrefix(labelC), "陈旧 A 必须以自己的请求级身份登记")

        // --- 负例 1：长度合格但中段改写 ⇒ 严格前缀不成立，必须拒。 ---
        let rewritten = [
            message("system", doc), message("user", "Reply RETHINK."),
            message("assistant", reply1), message("user", "Say DONE."),
            message("assistant", reply2), message("user", "Say NEXT."),
            message("assistant", reply3), message("user", "Say FINAL."),
        ]
        let t5Start = traceLogSize()
        try await chatCompletion(sessionId: nil, messages: rewritten)
        let line5 = try completionLine(sinceByteOffset: t5Start)
        XCTAssertFalse(
            windowHas("own=transfer", sinceByteOffset: t5Start),
            "历史不匹配时不得采纳——转录更长也不算数")
        XCTAssertFalse(line5.contains("adopt=1"))
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(number(from: line5, marker: "promptTokens=")),
            coldPromptTokens * 0.9, "落冷路径就要付整份文档")
        let labelNeg1 = try XCTUnwrap(sessionLabel(of: line5))
        residencySample("neg1(cold)", sinceByteOffset: t5Start)

        // --- 负例 2：前缀合法（C 分支 + 两条），但请求级 kvCache 与分片记账
        //     不同 ⇒ 前缀对账过了也必须拒。 ---
        // 尾部话语必须与同 scope 内已结算的问句不同：答案复用（默认开启，
        // `isAnswerReuseEnabled`）按 (scope, 用户话语) 命中，而 B 轮已结算
        // 过 "Say DONE."——复用它会让本轮根本不进模型（`[IS_REUSE]` 200，
        // 无完成行）。这不是 #90 的路径，本门每轮都得真的执行引擎。
        let configMismatch = turn3
            + [message("assistant", reply3), message("user", "Say CONFIG.")]
        let t6Start = traceLogSize()
        try await chatCompletion(
            sessionId: nil,
            messages: configMismatch,
            extra: ["kvCache": ["strategy": "fullPrecision", "maxTokens": 32_000]])
        let line6 = try completionLine(sinceByteOffset: t6Start)
        XCTAssertFalse(
            windowHas("own=transfer", sinceByteOffset: t6Start),
            "执行配置不兼容（kvFingerprint 变更）时不得采纳——前缀对账通过不算数")
        XCTAssertFalse(line6.contains("adopt=1"))
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(number(from: line6, marker: "promptTokens=")),
            coldPromptTokens * 0.9,
            "配置变了就必须重建，KV 语义连续性不得靠旧表示撑着")
        let labelNeg2 = try XCTUnwrap(sessionLabel(of: line6))
        residencySample("neg2(cold)", sinceByteOffset: t6Start)

        // 2026-10-30 ADR 后退役：D–E 两相判的是「断连 → 取消生成 → 逐出分片」。
        // ADR_LOCAL_OFFLINE_PREFILL_AND_CANCEL_20261030 把断连改为 detach：
        // 生成继续跑完、账本停在继承条数、不逐出、不结算。A–C（采纳/所有权
        // 转移）与取消无关，仍在上方照常断言；D–E 必须按 detach 语义重新设计
        // （新判据是 [DETACH] 出现、账本不推进、分片不被逐出），在此之前显式
        // 退役，绝不以「没看到 cancelCommitSkip」冒充 PASS。旧断言原样保留在
        // 门后，仅对 ADR 前二进制重放。
        guard ProcessInfo.processInfo.environment["SESSION_ADOPTION_LEGACY_CANCEL"] == "1" else {
            print(
                "[#90 retired] phase D–E: client disconnect now detaches "
                    + "(ADR 2026-10-30); re-design required, not a PASS")
            throw XCTSkip(
                "阶段 D–E 退役：ADR 2026-10-30 把断连从取消改为 detach，"
                    + "cancelCommitSkip/adoptedCancelEvict 判据只对 ADR 前二进制成立；"
                    + "设 SESSION_ADOPTION_LEGACY_CANCEL=1 仅用于重放旧仪器")
        }

        // --- D：中途取消。转录 = C 分支 + 一条**要求长输出**的新用户消息 ⇒
        //     先采纳 C 的分片，再在生成仍在途时断连。断连经 HTTPServer
        //     peerClosed → terminate → cancelGeneration(requestId) 落到引擎，
        //     走 Task.isCancelled 分支。
        //     取消点由「首字节到达」触发，不用固定睡眠：extend 轮自然完成只要
        //     ~0.9s，睡 1s 生成已提交、取消会落空（2026-10-28 04:11 实测：
        //     cancelCommitSkip 缺失、账本已推进到 9）。长输出保证首字节之后
        //     仍有大量 token 未生成，取消必落在在途窗口内。
        //     两个时点分开断言：采纳时键就已转移；取消只清除属主对象。 ---
        let preDCards = ownershipSnapshot(runtime, "pre-D")
        XCTAssertEqual(preDCards.count, 4, "C 与陈旧 A/两负例各一张")
        let survivorKeys = Set(preDCards.filter { $0.mapKey != cMapKey }.map(\.mapKey))
        XCTAssertEqual(survivorKeys.count, 3)

        let turn4 = turn3 + [
            message("assistant", reply3),
            message(
                "user",
                "List the integers 1 to 400, one per line, no prose. Do not stop early."),
        ]
        let t7Start = traceLogSize()
        let (stream, streamed) = try await streamingChatTask(messages: turn4, maxTokens: 4_096)
        let adoptLineD = try XCTUnwrap(
            traceWindow(
                sinceByteOffset: t7Start,
                containing: ["sessionAdopt key=", "own=transfer"], timeout: 120),
            "取消轮必须先命中采纳")
        // 首字节 = 服务器已在应答（peer-close 监听已挂起）且引擎在生成；
        // 此刻取消才是「生成在途时断连」，而不是与自然完成赛跑。
        let firstByteDeadline = Date().addingTimeInterval(30)
        while streamed.count == 0, Date() < firstByteDeadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertGreaterThan(streamed.count, 0, "流式响应 30s 内没有任何字节，取消窗口不成立")

        // 所有权断言（时点 1：取消之前）。C 的键必须在**采纳时**就消失——
        // 这是所有权转移而不是共享别名；D 是这份可变会话此刻唯一的属主。
        let atDAdoption = ownershipSnapshot(runtime, "at-D-adoption(before-cancel)")
        XCTAssertEqual(atDAdoption.count, 4, "转移不新增分片：C 的键换成 D 的键")
        let labelD = try XCTUnwrap(adoptKey(of: adoptLineD), adoptLineD)
        let dCard = try XCTUnwrap(
            atDAdoption.first { $0.label.hasPrefix(labelD) },
            "采纳后必须存在 D 的属主卡片：\(atDAdoption.map(\.label))")
        XCTAssertTrue(dCard.label.contains("#"), "D 的键必须随身份转移：\(dCard.label)")
        XCTAssertEqual(
            dCard.historyCount, 7,
            "在途快照的账本仍是继承的 7 条：提交（incoming+assistant）只在生成成功后追加")
        XCTAssertFalse(
            atDAdoption.contains { $0.mapKey == cMapKey },
            "C 的键必须在采纳时就消失，而不是等到取消（转移 ≠ 共享别名）")
        XCTAssertEqual(
            Set(atDAdoption.filter { !$0.label.hasPrefix(labelD) }.map(\.mapKey)),
            survivorKeys, "采纳不得扰动其余分片的键")
        let dMapKey = dCard.mapKey

        stream.cancel()
        _ = await stream.result

        let cancelLine = try XCTUnwrap(
            traceWindow(sinceByteOffset: t7Start, containing: ["cancelCommitSkip"], timeout: 180),
            "断连未取消生成：cancelCommitSkip 缺失（取消判据无从成立）")
        XCTAssertTrue(
            cancelLine.contains("session=\(labelD)"),
            "取消落到的必须是 D 的属主身份：\(cancelLine)")
        let evictLine = try XCTUnwrap(
            traceWindow(sinceByteOffset: t7Start, containing: ["adoptedCancelEvict"], timeout: 60),
            "#90 C: 采纳分片被取消后必须逐出")
        XCTAssertTrue(evictLine.contains("session=\(labelD)"), evictLine)
        XCTAssertTrue(
            evictLine.contains("history=7"),
            "取消不得提交：账本应停在继承的 7 条（若为 9 说明生成先自然完成并提交）：\(evictLine)")
        XCTAssertTrue(
            evictLine.contains("aliases=1"),
            "所有权转移后该对象只应有一个键（无别名）：\(evictLine)")
        XCTAssertTrue(
            evictLine.contains("keys=\(String(dMapKey.suffix(6)))"),
            "被逐出的必须是 D 的键：\(evictLine)")

        // 所有权断言（时点 2：取消之后）。D 的对象不得留下任何可采纳映射；
        // 其余分片的键与转移前逐字节一致 ⇒ 取消只打掉属主对象本身。
        let cardsAfterCancel = ownershipSnapshot(runtime, "after-cancel")
        XCTAssertEqual(
            cardsAfterCancel.count, 3, "取消后只剩陈旧 A 与两个负例分片")
        XCTAssertFalse(
            cardsAfterCancel.contains { $0.label.hasPrefix(labelD) },
            "被逐出的分片不得留下可采纳别名")
        XCTAssertFalse(
            cardsAfterCancel.contains { $0.mapKey == dMapKey },
            "D 的键必须被清除")
        XCTAssertEqual(
            Set(cardsAfterCancel.map(\.mapKey)), survivorKeys,
            "取消不得扰动其余分片（键逐字节对照）")

        // --- E：重放同一前缀（新请求级身份）。逐出前它应由 C/D 的分片直接
        //     extend；逐出后必须整份冷 prefill。「必须冷」由候选检索本身证明，
        //     不靠 D 已取消反推。 ---
        let t8Start = traceLogSize()
        let (replyE, _) = try await chatCompletion(sessionId: nil, messages: turn4)
        let lineE = try completionLine(sinceByteOffset: t8Start)
        XCTAssertFalse(replyE.isEmpty)
        XCTAssertFalse(
            windowHas("own=transfer", sinceByteOffset: t8Start),
            "逐出的分片及其别名都不得再被采纳")
        XCTAssertFalse(lineE.contains("adopt=1"))
        residencySample("E(cold-after-evict)", sinceByteOffset: t8Start)

        // 行为断言：候选集真的被检过，且逐条给出了拒绝理由。没检（候选集
        // 为空）时不会有这行；因此这行存在本身就区分「没看」与「看了但没有
        // 合格候选」，不需要为了通过而禁用正常的前缀复用。
        let missLineE = try XCTUnwrap(
            traceWindow(sinceByteOffset: t8Start, containing: ["sessionAdoptMiss"], timeout: 60),
            "E 必须留下候选检索记录：sessionAdoptMiss 缺失 ⇒ 无法断言『检过且无合格候选』")
        XCTAssertTrue(missLineE.contains("candidates=3"), missLineE)
        XCTAssertTrue(missLineE.contains("eligible=0"), missLineE)
        let expectedReasons: [(String, String)] = [
            // 陈旧 A：账本 5 条短于入站 8 条，但第 4 条起与 E 的转录分叉。
            (labelStale, "notPrefix"),
            // 负例 1：账本 9 条不短于入站 8 条。
            (labelNeg1, "notShorter"),
            // 负例 2：kv 配置指纹不同（理由先于长度判）。
            (labelNeg2, "fpMismatch"),
        ]
        for (label, reason) in expectedReasons {
            XCTAssertTrue(
                missLineE.contains("\(label):\(reason)"),
                "候选 \(label) 的拒绝理由应为 \(reason)：\(missLineE)")
        }
        XCTAssertTrue(lineE.contains("reuse=false"), "冷轮必须显式 reuse=false：\(lineE)")
        XCTAssertTrue(lineE.contains("mode=cold"), lineE)
        XCTAssertEqual(
            number(from: lineE, marker: "cacheHitTokens=") ?? 0, 0,
            "冷轮不得报告任何缓存命中：\(lineE)")
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(number(from: lineE, marker: "promptTokens=")),
            coldPromptTokens * 0.9, "逐出后只能付整份冷 prefill（读数不得比冷轮小）")

        let finalCards = ownershipSnapshot(runtime, "final")
        XCTAssertEqual(finalCards.count, 4, "陈旧 A / 两负例 / E 各自一张")
        for retired in [labelA, labelB, labelC, labelD] {
            XCTAssertFalse(
                finalCards.contains { $0.label.hasPrefix(retired) },
                "已转移或已逐出的身份 \(retired) 不得仍指向活分支")
        }

        // #90 B：本轮真实模型上的账本读数必须成立——几何可解析（>0）、
        // 上限有限，且驻留账本没有越界。取**最后一行**（E 之后的驻留状态），
        // 不是窗口里的第一行（那是 A 之前、尚未建立分片的空账本）。物理足迹
        // 只打印（见 residencySample），不拿来证明「RSS 被同等字节数限制」。
        let ledgerLine = try XCTUnwrap(
            traceWindow(sinceByteOffset: t1Start)
                .split(separator: "\n")
                .last(where: { $0.contains("residencyLedger") })
                .map { String($0) },
            "真实模型上必须采到驻留账本行（#90 B 的计量维度）")
        let ledgerBytes = try XCTUnwrap(number(from: ledgerLine, marker: "ledgerBytes="))
        let ceilingBytes = try XCTUnwrap(number(from: ledgerLine, marker: "ceilingBytes="))
        XCTAssertGreaterThan(ledgerBytes, 0, ledgerLine)
        XCTAssertGreaterThan(ceilingBytes, ledgerBytes, ledgerLine)
        print("[#90 B final] \(ledgerLine)")

        // 身份链接表的结构判据：只按稳定身份登记，任何请求级身份都不得出现。
        let linkIds = try XCTUnwrap(
            chatExecutionLinkIds(),
            "链接表探测失败（打开/准备/读取）：读不到就不能据此下否定判据")
        XCTAssertFalse(linkIds.isEmpty, "链接表应有稳定身份行（否则否定判据空转）")
        XCTAssertFalse(
            linkIds.contains { $0.contains("-request:") },
            "链接表不得出现请求级身份：\(linkIds)")
    }

    // MARK: - 字节上限（运行时侧）

    /// 上限触发的主证已在 `SessionAdoptionTests` 的 `ResidencyGovernor`
    /// 纯函数层跑过。这里只钉运行时事实：日常模型（4bit、无状态层）的每
    /// token 宽度与固定态必须解析出来，且字节上限是有限值——跨请求复用
    /// 不许变成无限累积。
    func testByteCeilingIsResolvedAndBoundedOnDailyModel() throws {
        try XCTSkipIf(
            !FileManager.default.fileExists(atPath: modelPath),
            "daily model not present: \(modelPath)")
        let residency = try XCTUnwrap(
            LiveSessionResidency.resolve(modelPath: modelPath),
            "解析不出几何 ⇒ 字节维度不启用，#90 B 的上限形同虚设")
        let ceiling = LiveSessionResidency.byteBudget(
            residency: residency, override: RuntimeTuning.liveSessionByteBudgetOverrideBytes)
        XCTAssertGreaterThan(residency.bytesPerToken, 0)
        XCTAssertGreaterThan(ceiling, 0)
        XCTAssertLessThan(ceiling, RuntimeTuning.mlxMemoryLimitBytes)
        print(
            "[#90 B] daily-model residency: bytesPerToken=\(residency.bytesPerToken) "
            + "fixedPerSession=\(residency.fixedBytesPerSession) ceiling=\(ceiling) B ("
            + String(format: "%.2f", Double(ceiling) / Double(RuntimeTuning.gibibyte))
            + " GiB)")
    }
}
