import LOCALBCore
import SimiGoRuntimeContract
import XCTest

@testable import SimiGo

/// #90 B 受控子场景：字节上限在**运行时**的逐出路径（真实模型）。
///
/// 与主闭环（SessionAdoptionE2ETests）分开跑：本测只在显式设置
/// `SIMIGO_LIVE_SESSION_MAX_BYTES` 时执行，并把该覆盖值写进断言与
/// `[EVICT]` 读数行；产品默认预算（`sessionLimit`×固定状态 +
/// `warmTokenBudget`×每 token 字节）不因此改变。缺省 XCTSkip。
///
/// 判据（与 owner 裁定对齐）：
///  ① 上限按覆盖值生效：ledger 的 `ceilingBytes` 逐字等于覆盖值；
///  ② 第二轮准入时 LRU 逐出真的发生：`plannedEvictions=1`、
///     `residencyCeiling evicted=1`、`[MEM] session LRU evicted=1`；
///  ③ 被逐出的分片对象已移除：再次请求第一会话时为 `mode=cold`
///     （不出现跨会话 extend，也不出现自复用）；
///  ④ 账本与物理足迹分开报告：`ledgerBytes` 是几何估算，footprint 是
///     进程 phys_footprint；后者只打印不断言（两者不是同一个指标）。
final class LiveSessionCeilingEvictionRealModelTests: XCTestCase {

    private static func modelPath() throws -> String {
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

    private static func greedyConfig() -> ModelConfig {
        var cfg = ModelConfig()
        cfg.temperature = 0
        cfg.maxTokens = 8
        cfg.disableThinking = true
        cfg.useMTP = false
        return cfg
    }

    private static func mb(_ bytes: UInt64) -> Double {
        Double(bytes) / Double(1024 * 1024)
    }

    /// 每轮用新 nonce，避免任何持久化边界替本轮付账。
    private func document(_ nonce: String, lines: Int = 220) -> String {
        var out = ["Run scope: \(nonce)"]
        for i in 0..<lines {
            out.append(
                "Section \(i): The runtime maintains execution state as a first-class "
                    + "artifact; settlements, dependencies and continuity anchors are "
                    + "recorded per logical branch so that a later request can resume "
                    + "without relying on persisted KV cache blobs. Line \(i) of \(lines).")
        }
        return out.joined(separator: "\n")
    }

    private var traceURL: URL {
        SimiGoPaths.logs.appendingPathComponent("native_mlx_trace.log")
    }

    private func traceSize() -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: traceURL.path)
        return (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func traceWindow(since offset: UInt64) -> [String] {
        guard let data = try? Data(contentsOf: traceURL), data.count > Int(offset) else {
            return []
        }
        let tail = data.suffix(from: data.startIndex + Int(offset))
        return String(decoding: tail, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private static func groups(_ pattern: String, in line: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }
        var out: [String] = []
        for i in 1..<match.numberOfRanges {
            guard let r = Range(match.range(at: i), in: line) else { return nil }
            out.append(String(line[r]))
        }
        return out
    }

    private struct Ledger {
        let sessions: Int
        let warmTokens: Int
        let ledgerBytes: Int
        let ceilingBytes: Int
        let plannedEvictions: Int
    }

    private func ledger(in lines: [String]) -> Ledger? {
        let pattern = #"residencyLedger sessions=(\d+) warmTokens=(\d+) ledgerBytes=(-?\d+) ceilingBytes=(-?\d+) plannedEvictions=(\d+)"#
        guard let line = lines.last(where: { $0.contains("residencyLedger") }),
              let g = Self.groups(pattern, in: line), g.count == 5,
              let sessions = Int(g[0]), let warmTokens = Int(g[1]),
              let ledgerBytes = Int(g[2]), let ceilingBytes = Int(g[3]),
              let planned = Int(g[4]) else { return nil }
        return Ledger(
            sessions: sessions, warmTokens: warmTokens, ledgerBytes: ledgerBytes,
            ceilingBytes: ceilingBytes, plannedEvictions: planned)
    }

    private struct CeilingEvent {
        let evicted: Int
        let freedBytes: Int
        let warmBytesNow: Int
        let ceilingBytes: Int
        let overCeiling: Int
    }

    private func ceilingEvents(in lines: [String]) -> [CeilingEvent] {
        let pattern = #"residencyCeiling evicted=(\d+) freedBytes=(\d+) warmBytesNow=(\d+) ceilingBytes=(\d+) overCeiling=(\d+)"#
        return lines.compactMap { line in
            guard line.contains("residencyCeiling"),
                  let g = Self.groups(pattern, in: line), g.count == 5,
                  let evicted = Int(g[0]), let freed = Int(g[1]),
                  let now = Int(g[2]), let ceiling = Int(g[3]),
                  let over = Int(g[4]) else { return nil }
            return CeilingEvent(
                evicted: evicted, freedBytes: freed, warmBytesNow: now,
                ceilingBytes: ceiling, overCeiling: over)
        }
    }

    /// 该窗口内最后一条会话遥测行的 `mode` 与键。
    private func lastSessionMode(in lines: [String]) -> (key: String, mode: String)? {
        let pattern = #"session=([0-9a-zA-Z]+)/main .* mode=([a-z]+)"#
        for line in lines.reversed() where line.contains(" mode=") {
            if let g = Self.groups(pattern, in: line), g.count == 2 {
                return (g[0], g[1])
            }
        }
        return nil
    }

    @discardableResult
    private func generate(
        _ runtime: NativeMLX, session: String, tag: String, messages: [JSONValue]
    ) async throws -> GenerationResult {
        let requestId = "evict-\(tag)-\(UUID().uuidString.prefix(8).lowercased())"
        await RuntimeLifecycleCoordinator.shared.register(
            requestID: requestId, sessionID: session)
        return try await runtime.generate(
            requestId: requestId,
            sessionId: session,
            messages: messages,
            tools: nil,
            config: Self.greedyConfig()
        ) { _ in }
    }

    func testByteCeilingEvictsLRUShardAtRuntime() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let ceilingText = env["SIMIGO_LIVE_SESSION_MAX_BYTES"],
              let ceiling = Int(ceilingText), ceiling > 0 else {
            throw XCTSkip("受控子场景：需显式 SIMIGO_LIVE_SESSION_MAX_BYTES 覆盖值")
        }
        try XCTSkipIf(
            RuntimeTuning.prefixPoolEnabled,
            "前缀池开启时活会话复用路径不同；逐出判据须在默认关闭窗跑")
        let modelPath = try Self.modelPath()
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("daily model not present: \(modelPath)")
        }
        guard let home = env["SIMIGO_HOME"], !home.isEmpty else {
            throw XCTSkip("SIMIGO_HOME not injected; 逐出读数需在隔离根内跑")
        }
        XCTAssertTrue(
            SimiGoPaths.databaseURL.path.hasPrefix((home as NSString).standardizingPath),
            "authoritative store resolves outside the isolation root: "
                + SimiGoPaths.databaseURL.path)
        XCTAssertEqual(
            RuntimeTuning.liveSessionByteBudgetOverrideBytes, ceiling,
            "覆盖值必须在进程启动时被读到（static let 每进程只求值一次）")

        print("[EVICT] controlled ceiling override=\(ceiling) B")
        let baseline = RuntimeTuning.footprintBytes()
        print("[EVICT] footprint baseline=\(Int(Self.mb(baseline)))MiB")

        let runtime = NativeMLX(
            info: ModelInfo(path: modelPath, kind: .mlx), config: Self.greedyConfig())
        let identityStore = LOCALBTransportIdentityStore(
            service: "com.simigo.tests.evict.\(UUID().uuidString)", account: "tls")
        addTeardownBlock { identityStore.deleteAll() }
        let identity = try identityStore.loadOrCreate()
        try await runtime.startWithLOCALB(
            ModelInfo(path: modelPath, kind: .mlx),
            port: 0,
            localbTransportIdentity: identity,
            localbRequestAuthorization: nil
        )
        defer { Task { await runtime.stop() } }

        let run = UUID().uuidString.prefix(8).lowercased()
        let s1 = "evict-s1-\(run)"
        let s2 = "evict-s2-\(run)"
        let docA = "Internal specification document:\n" + document("A-\(run)")
        let docB = "Internal specification document:\n" + document("B-\(run)")

        // --- ① 第一会话：唯一驻留分片，占据约一半预算。 ---
        let mark1 = traceSize()
        let t1 = [message("user", docA), message("user", "Reply READY.")]
        _ = try await generate(runtime, session: s1, tag: "s1", messages: t1)
        let window1 = traceWindow(since: mark1)
        let ledger1 = ledger(in: window1)
        let footprint1 = RuntimeTuning.footprintBytes()
        print(
            "[EVICT] after-s1 ledger=\(ledger1.map { "sessions=\($0.sessions) warmTokens=\($0.warmTokens) ledgerBytes=\($0.ledgerBytes) planned=\($0.plannedEvictions)" } ?? "MISSING")"
                + " footprint=\(Int(Self.mb(footprint1)))MiB")
        let first = try XCTUnwrap(ledger1, "第一轮必须留下 residencyLedger 行")
        XCTAssertEqual(first.sessions, 1, "第一轮后应只有一个活会话分片")
        XCTAssertEqual(first.ceilingBytes, ceiling, "上限必须逐字等于覆盖值")
        XCTAssertEqual(first.plannedEvictions, 0, "单分片低于上限时不得逐出")
        XCTAssertLessThanOrEqual(first.ledgerBytes, ceiling, "单分片账本必须仍在上限内")
        XCTAssertEqual(lastSessionMode(in: window1)?.mode, "cold", "第一轮是冷 prefill")

        // --- ② 第二会话：保护新请求 + 驻留 s1 超过上限 ⇒ 必须逐出 s1。 ---
        let mark2 = traceSize()
        let t2 = [message("user", docB), message("user", "Reply READY.")]
        _ = try await generate(runtime, session: s2, tag: "s2", messages: t2)
        let window2 = traceWindow(since: mark2)
        let ledger2 = ledger(in: window2)
        let events2 = ceilingEvents(in: window2)
        let footprint2 = RuntimeTuning.footprintBytes()
        let lru2 = window2.last(where: { $0.contains("session LRU evicted=") })
        print(
            "[EVICT] after-s2 ledger=\(ledger2.map { "sessions=\($0.sessions) warmTokens=\($0.warmTokens) ledgerBytes=\($0.ledgerBytes) planned=\($0.plannedEvictions)" } ?? "MISSING")"
                + " footprint=\(Int(Self.mb(footprint2)))MiB")
        print("[EVICT] after-s2 ceilingEvents=\(events2.map { "evicted=\($0.evicted) freedBytes=\($0.freedBytes) warmBytesNow=\($0.warmBytesNow) ceiling=\($0.ceilingBytes) over=\($0.overCeiling)" })")
        print("[EVICT] after-s2 lru=\(lru2.map { String($0.suffix(160)) } ?? "MISSING")")

        let second = try XCTUnwrap(ledger2, "第二轮必须留下 residencyLedger 行")
        XCTAssertEqual(second.ceilingBytes, ceiling, "上限必须逐字等于覆盖值")
        XCTAssertEqual(second.plannedEvictions, 1, "两个半满分片相加超上限 ⇒ 计划逐出一个")
        let fired = try XCTUnwrap(events2.first, "超上限必须产生 residencyCeiling 行")
        XCTAssertEqual(fired.evicted, 1, "逐出对象数量")
        XCTAssertEqual(fired.ceilingBytes, ceiling, "逐出行记录的仍应是覆盖值")
        XCTAssertGreaterThan(fired.freedBytes, 0, "逐出必须释放账本字节")
        XCTAssertEqual(fired.overCeiling, 0, "逐出后账本应回到上限内")
        XCTAssertLessThanOrEqual(fired.warmBytesNow, ceiling, "逐出后驻留账本 ≤ 上限")
        XCTAssertTrue(
            (lru2 ?? "").contains("evicted=1"),
            "既有 LRU 日志必须记录同一批逐出（keys/释放量可复核）")
        let mode2 = try XCTUnwrap(lastSessionMode(in: window2), "第二轮必须有会话遥测行")
        XCTAssertEqual(mode2.mode, "cold", "第二会话不应复用第一会话的分片")

        // --- ③ 再请求第一会话：其分片已被移除 ⇒ 只能冷 prefill。 ---
        let mark3 = traceSize()
        let t3 = t1 + [message("assistant", "READY."), message("user", "Reply AGAIN.")]
        _ = try await generate(runtime, session: s1, tag: "s1b", messages: t3)
        let window3 = traceWindow(since: mark3)
        let ledger3 = ledger(in: window3)
        let events3 = ceilingEvents(in: window3)
        let footprint3 = RuntimeTuning.footprintBytes()
        let mode3 = lastSessionMode(in: window3)
        let miss3 = window3.last(where: { $0.contains("sessionAdoptMiss") })
        print(
            "[EVICT] after-s1-rerun ledger=\(ledger3.map { "sessions=\($0.sessions) warmTokens=\($0.warmTokens) ledgerBytes=\($0.ledgerBytes) planned=\($0.plannedEvictions)" } ?? "MISSING")"
                + " footprint=\(Int(Self.mb(footprint3)))MiB"
                + " mode=\(mode3?.mode ?? "MISSING")")
        print("[EVICT] after-s1-rerun ceilingEvents=\(events3.map { "evicted=\($0.evicted) freedBytes=\($0.freedBytes) warmBytesNow=\($0.warmBytesNow) over=\($0.overCeiling)" })")
        print("[EVICT] after-s1-rerun adoptMiss=\(miss3.map { String($0.suffix(160)) } ?? "none")")

        XCTAssertEqual(
            mode3?.mode, "cold",
            "被逐出的分片对象已移除：再次请求第一会话必须冷 prefill，而不是 extend")
        XCTAssertTrue(
            events3.count == 1 && events3[0].evicted == 1,
            "第三轮准入再次超上限时，驻留的第二会话分片应被同一判据逐出")
        XCTAssertEqual(events3.last?.overCeiling, 0, "逐出后账本须回到上限内")
        XCTAssertLessThanOrEqual(events3.last?.warmBytesNow ?? .max, ceiling, "驻留账本 ≤ 上限")
        let third = try XCTUnwrap(ledger3, "第三轮必须留下 residencyLedger 行")
        XCTAssertEqual(third.ceilingBytes, ceiling, "上限仍是覆盖值")

        print(
            "[EVICT] residency curve MiB: baseline=\(Int(Self.mb(baseline)))"
                + " after-s1=\(Int(Self.mb(footprint1)))"
                + " after-s2(evict1)=\(Int(Self.mb(footprint2)))"
                + " after-s1-rerun(evict2)=\(Int(Self.mb(footprint3)))")
        print(
            "[EVICT] ledger vs footprint: ledgerBytes are geometric estimates; "
                + "footprint is process phys_footprint; they are not the same metric")
    }

    private func message(_ role: String, _ content: String) -> JSONValue {
        .object(["role": .string(role), "content": .string(content)])
    }
}
