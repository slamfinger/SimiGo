import XCTest
import Foundation
import MLXLMCommon
import MLXLLM
import MLXHuggingFace
import Tokenizers
import SimiGo2Experimental
@testable import SimiGo

/// Branch-Fork 能力回归（v1.4 转正）。
///
/// 证据链：GDN 不可 rewind 但可 fork——磁盘 checkpoint 双架构（GDN 混合 +
/// all-attention）、内存 `KVCache.copy()` 双向隔离、增量 prefill、与冷路径
/// greedy 逐字一致、长程记忆保持。结论与边界见
/// `docs/lessons/kv-fork-checkpoint-experiment-2026-09-17.md` 与
/// `docs/decisions/BRANCH_FORK_PROTOCOL_DRAFT.md`。
///
/// 三个用例：磁盘 fork 全链路（Runtime API + 官方遥测）、内存版 ownership、
/// 生产分支协议（forkSessionBranch/delete/list + HTTP 端点 e2e）。
/// 环境门控：`SIMIGO_FORK_EXP=1` 启用；`SIMIGO_FORK_MODEL` 覆盖模型
/// （默认真机 qwen3_5_moe，指向标准注意力模型即跑 all-attention 对照）。
final class BranchForkTests: XCTestCase {

    private static let recallNumber = "4711"
    private static let systemContent =
        "You are a precise assistant. Follow instructions exactly. " +
        "Answer in English without extra words."

    private static let systemMsg = SimiGo.JSONValue.object([
        "role": .string("system"),
        "content": .string(systemContent),
    ])

    private static func user(_ text: String) -> SimiGo.JSONValue {
        .object(["role": .string("user"), "content": .string(text)])
    }

    private static func assistant(_ text: String) -> SimiGo.JSONValue {
        .object(["role": .string("assistant"), "content": .string(text)])
    }

    /// ~100 行确定性档案文本，渲染后 ≈3k tokens：让冷/分叉的 prefill 差可测；
    /// 内嵌 recallNumber 供长程记忆探针。
    private static func baseCorpus() -> String {
        var lines: [String] = []
        for i in 0 ..< 100 {
            lines.append(
                "Record \(i): alpha bravo charlie delta echo foxtrot golf hotel india juliet " +
                "\(i * 7 % 97) kilo lima november oscar papa quebec romeo sierra tango " +
                "\(i * 13 % 89) uniform victor whiskey xray yankee zulu.")
        }
        return """
        Below is an archive of shipping records. Read them carefully.
        \(lines.joined(separator: "\n"))
        End of archive. Remember the number \(recallNumber) for later.
        Reply with exactly: OK
        """
    }

    /// 环境门控 + 模型路径（缺失即 skip，不污染常规测试跑）。
    private static func requireModel() throws -> String {
        guard ProcessInfo.processInfo.environment["SIMIGO_FORK_EXP"] == "1" else {
            throw XCTSkip("Branch-Fork 回归：需 SIMIGO_FORK_EXP=1 且本机存在权重")
        }
        guard let path = ProcessInfo.processInfo.environment["SIMIGO_FORK_MODEL"],
              !path.isEmpty else {
            throw XCTSkip("Branch-Fork 回归：需 SIMIGO_FORK_MODEL 指定本机测试权重")
        }
        guard FileManager.default.fileExists(atPath: path + "/config.json") else {
            throw XCTSkip("模型不存在：\(path)")
        }
        return path
    }

    private static func greedyConfig() -> ModelConfig {
        var cfg = ModelConfig()
        cfg.temperature = 0 // greedy：跨会话输出逐字可比
        cfg.maxTokens = 24
        cfg.disableThinking = true
        cfg.useMTP = false
        return cfg
    }

    // MARK: - 磁盘 fork 全链路（Runtime API + 官方遥测）

    /// BETA-AUDIT-1 R4-A（P1-C1 动态注入实证）：现有 Beta 能不能安全失败？
    ///
    /// W2（新 cache + 旧/异 transcript meta，两文件各自合法）：
    ///   → restore 静默成功（fail-open）——错位对被当正常 checkpoint。
    /// W1（.safetensors 截断损坏）：
    ///   → restore 抛出（fail-closed）。
    /// meta 缺失：
    ///   → restore 抛出（fail-closed）。
    /// C1 契约测试（BETA-AUDIT-1 R5）：checkpoint 配对一致性——
    /// 混代对/截断/缺失一律 fail-closed；语义残留（W2b）已登记为
    /// 非阻塞见证。
    func testCheckpointPairMismatchFailsClosed() async throws {
        let modelPath = try Self.requireModel()
        let cfg = Self.greedyConfig()
        let info = ModelInfo(path: modelPath, kind: .mlx)
        let runtime = NativeMLX(info: info, config: cfg)
        let port = 18777
        try await runtime.start(info, port: port)
        defer { Task { await runtime.stop() } }

        func gen(_ branch: String, _ messages: [SimiGo.JSONValue]) async throws -> GenerationResult {
            let requestId = "mismatch-\(branch)-\(UUID().uuidString.prefix(8).lowercased())"
            await RuntimeLifecycleCoordinator.shared.register(requestID: requestId, sessionID: "s")
            return try await runtime.generate(
                requestId: requestId,
                agentId: nil,
                sessionId: "s",
                logicalBranchId: branch,
                messages: messages,
                tools: nil,
                config: cfg
            ) { _ in }
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mismatch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 真实会话 + 真实 checkpoint
        let baseMessages: [SimiGo.JSONValue] = [Self.systemMsg, Self.user(Self.baseCorpus())]
        _ = try await gen("main", baseMessages)
        let real = try await gen(
            "main", baseMessages + [Self.user("What number did I ask you to remember?")])
        XCTAssertFalse(real.text.isEmpty)
        _ = try await runtime.saveSessionCache(
            sessionId: "s", logicalBranchId: "main", to: dir)

        let mainKey = "default/s/main"
        let metaURL = dir.appendingPathComponent(
            NativeMLX.cacheFileName(for: mainKey) + ".meta.json")
        let cacheURL = dir.appendingPathComponent(
            NativeMLX.cacheFileName(for: mainKey) + ".safetensors")

        // ---- W2 注入：伪造一个从未发生过的异 transcript（各自合法）----
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let realMeta = try decoder.decode(
            SessionCacheMetadata.self, from: Data(contentsOf: metaURL))
        XCTAssertGreaterThanOrEqual(
            realMeta.history.count, 3, "真实 checkpoint 应含多轮 history")
        let fabricatedHistory: [SimiGo.JSONValue] = [
            Self.systemMsg,
            Self.user("fabricated question"),
            Self.assistant("fabricated reply"),
        ]
        var forgedMeta = realMeta
        forgedMeta.history = fabricatedHistory
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(forgedMeta).write(to: metaURL, options: .atomic)

        // ---- W2a 意外窗口（C1 修复验证）：陈旧 cacheSHA256 的 meta 配新
        // 形态（= crash-between-files 的磁盘残留）。SHA 守卫必须拒绝混代对。
        var stalePairMeta = realMeta
        stalePairMeta.cacheSHA256 = String(repeating: "0", count: 64)
        stalePairMeta.checkpointGeneration = "stale-generation"
        try encoder.encode(stalePairMeta).write(to: metaURL, options: .atomic)
        do {
            _ = try await runtime.loadSessionCache(
                sessionId: "s", logicalBranchId: "main", from: dir)
            XCTFail("W2a：陈旧 SHA/代际的配对不应 restore（fail-closed 修复必须保持）")
        } catch {
            // 期望：fail-closed（C1 修复生效）
        }

        // ---- W2b 语义残留（已登记，非阻塞）：伪造 transcript + 保留真实
        // cacheSHA256/checkpointGeneration 的配对仍会 restore——SHA/代际
        // 只证同 commit 配对，不证 transcript↔KV 语义一致。收口 = C1 的
        // tokenCount 交叉核对（E4 Position 验证面）。见证性记录，不作断言。
        try encoder.encode(forgedMeta).write(to: metaURL, options: .atomic)
        if let residual = try? await runtime.loadSessionCache(
            sessionId: "s", logicalBranchId: "main", from: dir) {
            XCTAssertEqual(
                residual.history.count, fabricatedHistory.count,
                "W2b 残留见证：伪造 transcript 被静默 restore（已登记非阻塞）")
        }

        // ---- W1 注入：截断 .safetensors（数据段损坏）----
        // 动态发现：头部可解析 + 数组惰性映射 → 截断文件 restore 也不抛出，
        // 损坏推迟到生成时的前向读取。与 W2 同属 fail-open 见证。
        let originalCache = try Data(contentsOf: cacheURL)
        try Data(originalCache.prefix(originalCache.count / 2))
            .write(to: cacheURL)
        // ---- C1 修复验证：截断 safetensors fail-closed（SHA/代际守卫）----
        do {
            _ = try await runtime.loadSessionCache(
                sessionId: "s", logicalBranchId: "main", from: dir)
            XCTFail("W1：截断 safetensors 不应静默 restore")
        } catch {
            // 期望：fail-closed（C1 修复生效）
        }

        // ---- meta 缺失注入 ----
        try FileManager.default.removeItem(at: metaURL)
        do {
            _ = try await runtime.loadSessionCache(
                sessionId: "s", logicalBranchId: "main", from: dir)
            XCTFail("meta 缺失应 fail-closed（restore 抛出）")
        } catch {
            // 期望：fail-closed
        }
    }

    func testCheckpointForkRoundTrip() async throws {
        let modelPath = try Self.requireModel()
        let traceOffset = Self.traceLogByteLength()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kvfork-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let info = ModelInfo(path: modelPath, kind: .mlx)
        let runtime = NativeMLX(info: info, config: Self.greedyConfig())

        func gen(_ branch: String, _ messages: [SimiGo.JSONValue]) async throws -> GenerationResult {
            let requestId = "fork-\(branch)-\(UUID().uuidString.prefix(8).lowercased())"
            await RuntimeLifecycleCoordinator.shared.register(requestID: requestId, sessionID: "s")
            return try await runtime.generate(
                requestId: requestId,
                agentId: nil,
                sessionId: "s",
                logicalBranchId: branch,
                messages: messages,
                tools: nil,
                config: Self.greedyConfig()
            ) { _ in }
        }

        // base 冷生成 → 会话 default/s/base（ledger = 渲染 prompt + a0）
        try await runtime.start(info, port: 18773)
        let baseMessages: [SimiGo.JSONValue] = [Self.systemMsg, Self.user(Self.baseCorpus())]
        let base = try await gen("base", baseMessages)
        let a0 = base.text
        XCTAssertFalse(a0.isEmpty, "base 生成不应为空")
        XCTAssertGreaterThan(
            base.usage?.promptTokens ?? 0, 2000,
            "base 语料应 ≥2k tokens，实际 \(base.usage?.promptTokens ?? 0)")

        // checkpoint：base 轮结束的消息边界
        let snapshotURL = try await runtime.saveSessionCache(
            sessionId: "s", logicalBranchId: "base", to: dir)
        let snapSize = ((try? FileManager.default.attributesOfItem(
            atPath: snapshotURL.path))?[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(snapSize, 1_000_000, "checkpoint 应为 MB 级，实际 \(snapSize)B")

        // 快照 cache 组成与架构一致：混合 GDN 带 MambaCache；all-attention 全 KVCache
        let configData = try? Data(contentsOf: URL(fileURLWithPath: modelPath + "/config.json"))
        let configObject = (try? JSONSerialization.jsonObject(with: configData ?? Data()))
            as? [String: Any]
        let modelType = configObject?["model_type"] as? String ?? "unknown"
        let isHybridGDN = modelType == "qwen3_5_moe" || modelType == "qwen3_next"
        let classes = try Self.snapshotCacheClasses(at: snapshotURL)
        let mambaCount = classes.filter { $0 == "MambaCache" }.count
        let attnCount = classes.filter { $0 == "KVCache" || $0 == "RotatingKVCache" }.count
        print("[fork-cap] model_type=\(modelType) MambaCache=\(mambaCount) attn=\(attnCount) total=\(classes.count)")
        if isHybridGDN {
            XCTAssertGreaterThanOrEqual(mambaCount, 8, "快照应携带 GDN(MambaCache) 状态，实际 \(mambaCount)")
            XCTAssertGreaterThanOrEqual(attnCount, 2, "快照应携带 attention KV，实际 \(attnCount)")
        } else {
            XCTAssertEqual(mambaCount, 0, "标准注意力模型不应有 MambaCache，实际 \(mambaCount)")
            XCTAssertGreaterThanOrEqual(attnCount, 8, "快照应携带全部 attention KV，实际 \(attnCount)")
        }

        // 分支：checkpoint 复制到两个分支 storageKey 名下（磁盘反序列化 = 独立可变实例）
        let baseKey = "default/s/base"
        for branch in ["forkA", "forkB"] {
            let branchKey = "default/s/\(branch)"
            for suffix in [".safetensors", ".meta.json"] {
                try FileManager.default.copyItem(
                    at: dir.appendingPathComponent(NativeMLX.cacheFileName(for: baseKey) + suffix),
                    to: dir.appendingPathComponent(NativeMLX.cacheFileName(for: branchKey) + suffix))
            }
        }

        // forkA：恢复 + 两轮续问
        let metaA = try await runtime.loadSessionCache(
            sessionId: "s", logicalBranchId: "forkA", from: dir)
        XCTAssertEqual(metaA.history.count, 3, "恢复的 history 应为 [system, corpus, a0]")

        let withReply = baseMessages + [Self.assistant(a0)]
        let questionA =
            "Rewrite exactly this sentence and nothing else: The fork carries the prefix state."
        let forkA1 = try await gen("forkA", withReply + [Self.user(questionA)])
        XCTAssertFalse(forkA1.text.isEmpty, "forkA 首轮生成不应为空")
        let forkA2 = try await gen(
            "forkA", withReply + [Self.user(questionA), Self.assistant(forkA1.text),
                Self.user("Append the word DONE to your previous answer.")]
        )
        XCTAssertFalse(forkA2.text.isEmpty, "forkA 二轮生成不应为空")

        // forkB：同一 checkpoint + 长程记忆探针
        _ = try await runtime.loadSessionCache(sessionId: "s", logicalBranchId: "forkB", from: dir)
        let questionB = "What number did I ask you to remember? Reply with only that number."
        let forkB = try await gen("forkB", withReply + [Self.user(questionB)])
        XCTAssertTrue(
            forkB.text.contains(Self.recallNumber),
            "forkB 应召回 \(Self.recallNumber)，实际：\(forkB.text)")

        // 冷参照与冷重试（同 prompt 双路径）
        let coldA = try await gen("coldA", withReply + [Self.user(questionA)])
        let retr = try await gen("retr", withReply + [Self.user(questionB)])

        await runtime.stop()

        // —— 验收（trace 窗口内按分支读取官方遥测）——
        let lines = try Self.traceLines(after: traceOffset)

        func modes(_ branch: String) -> [String] {
            lines.compactMap { line -> String? in
                guard line.contains("session=s/\(branch) "),
                    let range = line.range(of: " mode=")
                else { return nil }
                let value = line[range.upperBound...].prefix { $0.isLetter || $0 == "-" }
                return value.isEmpty ? nil : String(value)
            }
        }

        XCTAssertEqual(modes("base"), ["cold"], "base 首生成应为 cold")
        // 池语义后：同内容的分支复制会被内容寻址 admission 命中（同一
        // RepresentationRef 的 poolBind）→ restore，而非 cold。这正是 F3
        // 经济学在复制分支上的体现。
        XCTAssertEqual(modes("coldA"), ["restore"], "coldA 同内容 → 池 restore")
        XCTAssertEqual(modes("retr"), ["restore"], "retr 同内容 → 池 restore")
        // 账本修复链（ce9e056..6d01a13）后：恢复分支 bootstrap 出对齐账本，
        // 走真正的暖 extend，不再 fragment-continuation。
        XCTAssertEqual(modes("forkA"), ["extend", "extend"], "恢复分支应暖 extend")
        XCTAssertEqual(modes("forkB"), ["extend"])

        // checkpoint 账本 = base prompt + 生成尾部；官方 generationTokens 口径
        // 可能不含结束 token（±2 容差，真正的截断是千级差距）。
        let baseLedger = (base.usage?.promptTokens ?? -1) + (base.usage?.generationTokens ?? -1)
        let forkALedger = Int(
            Self.field(in: lines, sessionKey: "s/forkA", "cacheTokens").first ?? "") ?? -1
        let forkBLedger = Int(
            Self.field(in: lines, sessionKey: "s/forkB", "cacheTokens").first ?? "") ?? -1
        XCTAssertTrue(
            abs(forkALedger - baseLedger) <= 2,
            "checkpoint 账本应≈base prompt+生成（±2 口径差），实际 \(forkALedger) vs \(baseLedger)")
        XCTAssertEqual(forkBLedger, forkALedger, "forkB 载入的是同一 checkpoint")
        for (branch, turns) in [("forkA", 2), ("forkB", 1)] {
            let prompts = Self.field(in: lines, sessionKey: "s/\(branch)", "promptTokens")
                .compactMap(Int.init)
            XCTAssertEqual(prompts.count, turns, "\(branch) 应有 \(turns) 轮生成")
            XCTAssertLessThan(
                prompts.max() ?? .max, 400,
                "\(branch) 每轮只应预填新增问句（<400 tok），实际 \(prompts)")
        }

        XCTAssertFalse(
            lines.contains { $0.contains("reuseMiss") },
            "不应出现 SimiGo 复用闸门 miss")
        XCTAssertFalse(
            lines.contains { $0.contains("fork@common") },
            "不应出现活会话渲染分叉（fork-no-rewind）")

        // 输出：greedy 下分支与冷路径逐字一致；同 prompt 冷重试代价高 3 倍以上
        XCTAssertEqual(
            forkA1.text, coldA.text,
            "forkA 与 coldA 输出应逐字一致\nforkA: \(forkA1.text)\ncoldA: \(coldA.text)")
        XCTAssertEqual(
            forkB.text, retr.text,
            "forkB 与 retr 输出应逐字一致\nforkB: \(forkB.text)\nretr: \(retr.text)")
        // usage.cachedPromptTokens 在 restore 路径透传官方 0 值——池经济性
        // 证据用 trace 的 cacheEff（完整命中 = 1.00）。
        let retrCacheEff = Double(
            Self.field(in: lines, sessionKey: "s/retr", "cacheEff").first ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(
            retrCacheEff, 0.9,
            "池 restore 应近满命中（delta 仅为最后一条消息），实际 cacheEff=\(retrCacheEff)")
        // 原「fork TTFT < cold/3」断言退役：retr 已被池 restore（不再冷）。
        // fork 经济学的代码级证据在 F3 电池 D3（实际 delta prefill < 200）。
        // 这里保留 forkB 快于 base 真冷的单一 sanity。
        XCTAssertLessThan(
            forkB.usage?.ttftSeconds ?? .greatestFiniteMagnitude,
            base.usage?.ttftSeconds ?? .greatestFiniteMagnitude,
            "forkB 应快于 base 真冷")
    }

    // MARK: - 内存版 ownership（KVCache.copy() 双向隔离）

    /// 直接打官方层（自建 ModelContainer；32GB 机器单容器）：同一内存快照 →
    /// 每 cache copy()（官方红线；state 为 struct 值语义直接共享）→ 两个 ChatSession。
    /// 交错 A1 → A2 → B → A3 双向污染探测；官方 promptTokenCount 直证增量。
    func testInMemoryForkCopyOwnership() async throws {
        let modelPath = try Self.requireModel()
        let container = try await LLMModelFactory.shared.loadContainer(
            from: URL(fileURLWithPath: modelPath),
            using: #huggingFaceTokenizerLoader())

        let params = GenerateParameters(maxTokens: 24, temperature: 0)
        let extra: [String: any Sendable] = ["enable_thinking": false]

        func drain(
            _ session: ChatSession, _ messages: [Chat.Message]
        ) async throws -> (text: String, promptTokens: Int) {
            var text = ""
            var promptTokens = -1
            for try await g in session.streamDetails(to: messages) {
                switch g {
                case .chunk(let t): text += t
                case .info(let i): promptTokens = i.promptTokenCount
                default: break
                }
            }
            return (text, promptTokens)
        }

        let base = ChatSession(
            container, history: [], generateParameters: params, additionalContext: extra)
        let (a0, basePrompt) = try await drain(base, [
            .system(Self.systemContent),
            .user(Self.baseCorpus()),
        ])
        XCTAssertFalse(a0.isEmpty, "base 生成不应为空")
        XCTAssertGreaterThan(basePrompt, 2000, "base 语料应 ≥2k tokens，实际 \(basePrompt)")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kvfork-mem-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let snapshotURL = dir.appendingPathComponent("base.safetensors")
        try await base.saveCache(to: snapshotURL)
        let shared = try loadPromptCacheSnapshot(url: snapshotURL)

        // 同一快照：cache 各自 copy()，state 按值共享
        let forkA = ChatSession(
            container, instructions: nil,
            promptCache: PromptCacheSnapshot(
                cache: shared.cache.map { $0.copy() }, state: shared.state),
            generateParameters: params, additionalContext: extra)
        let forkB = ChatSession(
            container, instructions: nil,
            promptCache: PromptCacheSnapshot(
                cache: shared.cache.map { $0.copy() }, state: shared.state),
            generateParameters: params, additionalContext: extra)

        let questionA =
            "Rewrite exactly this sentence and nothing else: The fork carries the prefix state."
        let questionB = "What number did I ask you to remember? Reply with only that number."

        // 交错：A1 → A2（A 变异自身副本）→ B → A3（B 运行后 A 再续，反向探针）
        let (a1, pA1) = try await drain(forkA, [.user(questionA)])
        let (a2, pA2) = try await drain(forkA, [.user("Append the word DONE to your previous answer.")])
        let (b1, pB1) = try await drain(forkB, [.user(questionB)])
        let (a3, pA3) = try await drain(forkA, [.user(questionB)])

        // 冷参照：history 初始化器全量渲染
        let logicalHistory: [Chat.Message] = [
            .system(Self.systemContent),
            .user(Self.baseCorpus()),
            .assistant(a0),
        ]
        let coldA = ChatSession(
            container, history: logicalHistory, generateParameters: params,
            additionalContext: extra)
        let (ca, pCA) = try await drain(coldA, [.user(questionA)])
        let coldB = ChatSession(
            container, history: logicalHistory, generateParameters: params,
            additionalContext: extra)
        let (cb, pCB) = try await drain(coldB, [.user(questionB)])

        // 验收：逐字一致、双向隔离、增量、长程记忆
        XCTAssertEqual(a1, ca, "内存 forkA 与冷参照应逐字一致\nforkA: \(a1)\ncoldA: \(ca)")
        XCTAssertEqual(b1, cb, "内存 forkB 与冷参照应逐字一致\nforkB: \(b1)\ncoldB: \(cb)")
        XCTAssertTrue(a2.contains("DONE"), "A2 应延续 A 的回答，实际：\(a2)")
        XCTAssertTrue(a3.contains(Self.recallNumber), "A3（B 运行后）应仍召回，实际：\(a3)")
        for (label, tokens) in [("forkA1", pA1), ("forkA2", pA2), ("forkB1", pB1), ("forkA3", pA3)] {
            XCTAssertLessThan(tokens, 400, "\(label) 只应预填增量（<400 tok），实际 \(tokens)")
        }
        XCTAssertGreaterThan(pCA, 2000, "冷参照应为全量预填，实际 \(pCA)")
        XCTAssertGreaterThan(pCB, 2000, "冷参照应为全量预填，实际 \(pCB)")
        print("[fork-cap][mem] promptTokens: forkA1=\(pA1) forkA2=\(pA2) forkB1=\(pB1) forkA3=\(pA3) coldA=\(pCA) coldB=\(pCB)")
    }

    // MARK: - 生产分支协议（Runtime API + HTTP 端点 e2e）

    /// forkSessionBranch / deleteSessionBranch / listSessionBranches +
    /// /v1/branches/fork、/v1/branches/list、/v1/branches/delete 与 chat
    /// `fork_from_branch` 内联触发的端到端。
    func testForkSessionBranchProductionAPI() async throws {
        let modelPath = try Self.requireModel()
        let cfg = Self.greedyConfig()
        let info = ModelInfo(path: modelPath, kind: .mlx)
        let runtime = NativeMLX(info: info, config: cfg)
        let port = 18775
        try await runtime.start(info, port: port)
        defer { Task { await runtime.stop() } }

        func gen(_ branch: String, _ messages: [SimiGo.JSONValue]) async throws -> GenerationResult {
            let requestId = "prod-\(branch)-\(UUID().uuidString.prefix(8).lowercased())"
            await RuntimeLifecycleCoordinator.shared.register(requestID: requestId, sessionID: "s")
            return try await runtime.generate(
                requestId: requestId,
                agentId: nil,
                sessionId: "s",
                logicalBranchId: branch,
                messages: messages,
                tools: nil,
                config: cfg
            ) { _ in }
        }

        // 源分支 main 正常生成（logical history = [system, corpus, a0]）
        let baseMessages: [SimiGo.JSONValue] = [Self.systemMsg, Self.user(Self.baseCorpus())]
        let base = try await gen("main", baseMessages)
        XCTAssertFalse(base.text.isEmpty, "base 生成不应为空")
        let withReply = baseMessages + [Self.assistant(base.text)]

        // Runtime API：main → alt fork
        let store = NativeMLX.defaultBranchCheckpointStore()
        let forkMeta = try await runtime.forkSessionBranch(
            sessionId: "s", sourceBranch: "main", targetBranch: "alt")
        XCTAssertEqual(forkMeta.history.count, 3, "fork 元数据应携带源分支 history")

        // STEP-10 R2: fork 点持久化进 target 分支 metadata。
        let altKey = try AgentExecutionKey(
            agentId: nil, sessionId: "s", logicalBranchId: "alt")
        let altMetaURL = store.appendingPathComponent(
            NativeMLX.cacheFileName(for: altKey.storageKey) + ".meta.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let stamped = try decoder.decode(
            SessionCacheMetadata.self, from: Data(contentsOf: altMetaURL))
        let forkPoint = try XCTUnwrap(
            stamped.forkPoint, "forkSessionBranch 必须持久化 fork 点")
        XCTAssertEqual(forkPoint.sourceStorageKey, "default/s/main")
        XCTAssertEqual(forkPoint.atMessage, 3)
        XCTAssertGreaterThan(forkPoint.atToken, 0)

        // STEP-10 R3: child 在 ExecutionBindingRegistry 绑定 checkpoint 的
        // .residentKV RepresentationRef；parent 的池绑定不被 supersede。
        let childBinding = try XCTUnwrap(
            NativeMLXPrefixPool.shared.bindings.currentBinding(
                executionID: altKey.storageKey),
            "child fork binding 必须已登记")
        XCTAssertEqual(childBinding.ref.kind, .residentKV)
        XCTAssertEqual(childBinding.ref.boundLength, forkPoint.atToken)
        XCTAssertNotEqual(childBinding.executionID, forkPoint.sourceStorageKey)

        // alt 分支续问：只算增量 + 记忆召回
        let questionB = "What number did I ask you to remember? Reply with only that number."
        let alt = try await gen("alt", withReply + [Self.user(questionB)])
        XCTAssertTrue(
            alt.text.contains(Self.recallNumber),
            "alt 分支应召回 \(Self.recallNumber)，实际：\(alt.text)")
        XCTAssertLessThan(
            alt.usage?.promptTokens ?? .max, 400,
            "alt 只应预填增量，实际 \(alt.usage?.promptTokens ?? -1)")

        // list：live 同时含 main 与 alt
        let listing = runtime.listSessionBranches(sessionId: "s")
        XCTAssertTrue(listing.liveBranches.contains("main"), "live 应含 main：\(listing.liveBranches)")
        XCTAssertTrue(listing.liveBranches.contains("alt"), "live 应含 alt：\(listing.liveBranches)")

        // delete：回收 alt（KV 释放 + checkpoint 清理）
        try await runtime.deleteSessionBranch(sessionId: "s", logicalBranchId: "alt")
        let altPrefix = NativeMLX.cacheFileName(for: "default/s/alt")
        let residue = ((try? FileManager.default.contentsOfDirectory(atPath: store.path)) ?? [])
            .filter { $0.hasPrefix(altPrefix) }
        XCTAssertTrue(residue.isEmpty, "delete 后不应有 checkpoint 残留：\(residue)")
        // STEP-10 lifecycle: delete detaches the child binding (Gate C:
        // detach is an operation; the row history remains, active clears).
        XCTAssertNil(
            NativeMLXPrefixPool.shared.bindings.currentBinding(
                executionID: altKey.storageKey),
            "delete 后 child binding 必须已 detach")
        XCTAssertFalse(
            runtime.listSessionBranches(sessionId: "s").liveBranches.contains("alt"),
            "delete 后 live 不应含 alt")

        // HTTP e2e：fork 端点 → chat on 新分支 → list → delete 端点
        let baseURL = "http://127.0.0.1:\(port)"
        func post(_ path: String, _ body: [String: Any]) async throws -> (Int, Data) {
            var request = URLRequest(url: URL(string: baseURL + path)!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? -1, data)
        }

        let (forkStatus, _) = try await post("/v1/branches/fork", [
            "session_id": "s", "fork_from_branch": "main", "branch_id": "e2e",
        ])
        XCTAssertEqual(forkStatus, 200, "HTTP fork 应成功")

        let (chatStatus, chatBody) = try await post("/v1/chat/completions", [
            "session_id": "s",
            "branch_id": "e2e",
            "messages": [
                ["role": "system", "content": Self.systemContent],
                ["role": "user", "content": Self.baseCorpus()],
                ["role": "assistant", "content": base.text],
                ["role": "user", "content": questionB],
            ],
        ])
        XCTAssertEqual(chatStatus, 200, "chat on fork 分支应成功")
        XCTAssertTrue(
            String(decoding: chatBody, as: UTF8.self).contains(Self.recallNumber),
            "e2e chat 应召回 \(Self.recallNumber)")

        let (listStatus, listBody) = try await post("/v1/branches/list", ["session_id": "s"])
        XCTAssertEqual(listStatus, 200)
        XCTAssertTrue(
            String(decoding: listBody, as: UTF8.self).contains("e2e"),
            "list 应含 e2e 分支")

        let (deleteStatus, _) = try await post("/v1/branches/delete", [
            "session_id": "s", "branch_id": "e2e",
        ])
        XCTAssertEqual(deleteStatus, 200, "HTTP delete 应成功")

        // e2e checkpoint 在默认 store，删除端点应已清理
        let e2ePrefix = NativeMLX.cacheFileName(for: "default/s/e2e")
        let e2eResidue = ((try? FileManager.default.contentsOfDirectory(atPath: store.path)) ?? [])
            .filter { $0.hasPrefix(e2ePrefix) }
        XCTAssertTrue(e2eResidue.isEmpty, "e2e 分支删除后不应有残留：\(e2eResidue)")

        await runtime.stop()
    }

    // MARK: - 辅助

    private static let traceLogURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".simigo/logs/native_mlx_trace.log")

    private static func field(
        in lines: [String], sessionKey: String, _ name: String
    ) -> [String] {
        lines.compactMap { line -> String? in
            guard line.contains("session=\(sessionKey) "),
                let range = line.range(of: " \(name)=")
            else { return nil }
            let value = line[range.upperBound...].prefix { !$0.isWhitespace }
            return value.isEmpty ? nil : String(value)
        }
    }

    private static func traceLogByteLength() -> Int {
        RuntimeTraceLogger.shared.flush()
        return ((try? FileManager.default.attributesOfItem(atPath: traceLogURL.path))?[.size]
            as? NSNumber)?.intValue ?? 0
    }

    private static func traceLines(after byteOffset: Int) throws -> [String] {
        RuntimeTraceLogger.shared.flush()
        let data = try Data(contentsOf: traceLogURL)
        guard data.count > byteOffset else { return [] }
        return String(decoding: data.suffix(from: byteOffset), as: UTF8.self)
            .split(separator: "\n")
            .map(String.init)
    }

    /// 解析官方 savePromptCache 写出的 safetensors 头（8B 小端长度 + JSON），
    /// 返回按序的 cache 类名列表（meta "2.i" 键）。
    private static func snapshotCacheClasses(at url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        guard data.count > 24 else {
            throw SnapshotFormatError("快照过小：\(data.count)B")
        }
        let headerLength = Int(
            data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt64.self) }
                .littleEndian)
        let headerEnd = 8 + headerLength
        guard headerEnd > 8, headerEnd <= data.count else {
            throw SnapshotFormatError("快照头长度非法：\(headerLength)")
        }
        guard
            let header = try JSONSerialization.jsonObject(
                with: data.subdata(in: 8 ..< headerEnd)) as? [String: Any],
            let metadata = header["__metadata__"] as? [String: String]
        else {
            throw SnapshotFormatError("快照头缺少 __metadata__（官方 savePromptCache 约定）")
        }
        return metadata
            .filter { $0.key.hasPrefix("2.") }
            .sorted { $0.key.compare($1.key, options: .numeric) == .orderedAscending }
            .map { $0.value }
    }
    /// BETA-AUDIT-1 R5-C1（W2 注入实测）：crash-residue 形态——新一代
    /// .safetensors 覆盖旧代配对（旧 meta 保留）→ restore 必须 fail-closed
    /// （SHA 守卫拒绝混代对）。
    func testCheckpointGenerationMismatchFailsClosed() async throws {
        let modelPath = try Self.requireModel()
        let cfg = Self.greedyConfig()
        let info = ModelInfo(path: modelPath, kind: .mlx)
        let runtime = NativeMLX(info: info, config: cfg)
        let port = 18779
        try await runtime.start(info, port: port)
        defer { Task { await runtime.stop() } }

        func gen(_ messages: [SimiGo.JSONValue]) async throws -> GenerationResult {
            let requestId = "g1m-\(UUID().uuidString.prefix(8).lowercased())"
            await RuntimeLifecycleCoordinator.shared.register(requestID: requestId, sessionID: "s")
            return try await runtime.generate(
                requestId: requestId, agentId: nil, sessionId: "s",
                logicalBranchId: "main", messages: messages, tools: nil,
                config: cfg) { _ in }
        }

        let dirA = FileManager.default.temporaryDirectory
            .appendingPathComponent("g1m-a-\(UUID().uuidString)", isDirectory: true)
        let dirB = FileManager.default.temporaryDirectory
            .appendingPathComponent("g1m-b-\(UUID().uuidString)", isDirectory: true)
        for d in [dirA, dirB] {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        defer {
            for d in [dirA, dirB] {
                try? FileManager.default.removeItem(at: d)
            }
        }

        let baseMessages: [SimiGo.JSONValue] = [Self.systemMsg, Self.user(Self.baseCorpus())]
        _ = try await gen(baseMessages)
        // G1 配对：A 目录（G1 cache + G1 meta/SHA_A）
        _ = try await runtime.saveSessionCache(sessionId: "s", logicalBranchId: "main", to: dirA)
        // 推进 session（G2 状态）
        _ = try await gen(baseMessages + [
            Self.assistant("OK"),
            Self.user("Add one more sentence."),
        ])
        // G2 配对：B 目录（G2 cache + G2 meta/SHA_B）
        _ = try await runtime.saveSessionCache(sessionId: "s", logicalBranchId: "main", to: dirB)

        // W2 注入：新 cache（G2）覆盖 A 目录，旧 meta（G1/SHA_A）保留——
        // 即 crash-between-files 的磁盘残留形态。
        let aCache = dirA.appendingPathComponent(
            NativeMLX.cacheFileName(for: "default/s/main") + ".safetensors")
        let bCache = dirB.appendingPathComponent(
            NativeMLX.cacheFileName(for: "default/s/main") + ".safetensors")
        try FileManager.default.removeItem(at: aCache)
        try FileManager.default.copyItem(at: bCache, to: aCache)

        // restore：SHA 守卫必须拒绝混代对（fail-closed）
        do {
            _ = try await runtime.loadSessionCache(
                sessionId: "s", logicalBranchId: "main", from: dirA)
            XCTFail("混代对（G2 cache + G1 meta）不应静默 restore")
        } catch {
            // 期望：fail-closed（SHA/generation 守卫）
        }
    }

    /// BETA-AUDIT-1 R5-C3（fork/source generation race seam）：fork 事务必须
    /// 持 source generation gate 直到完成——长生成期间 fork 不得完成。
    func testForkBlocksDuringSourceGeneration() async throws {
        let modelPath = try Self.requireModel()
        var longCfg = Self.greedyConfig()
        longCfg.maxTokens = 128
        let info = ModelInfo(path: modelPath, kind: .mlx)
        let runtime = NativeMLX(info: info, config: longCfg)
        let port = 18781
        try await runtime.start(info, port: port)
        defer { Task { await runtime.stop() } }

        func gen(_ branch: String, _ messages: [SimiGo.JSONValue]) async throws -> GenerationResult {
            let requestId = "race-\(branch)-\(UUID().uuidString.prefix(8).lowercased())"
            await RuntimeLifecycleCoordinator.shared.register(requestID: requestId, sessionID: "s")
            return try await runtime.generate(
                requestId: requestId, agentId: nil, sessionId: "s",
                logicalBranchId: branch, messages: messages, tools: nil,
                config: longCfg) { _ in }
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("race-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let baseMessages: [SimiGo.JSONValue] = [Self.systemMsg, Self.user(Self.baseCorpus())]
        _ = try await gen("main", baseMessages)

        // 长生成占住 source generation gate（128 token 上限）
        let longMessages = baseMessages + [
            Self.user("Count from 1 to 30, one number per line."),
        ]
        let genTask = Task { try await gen("main", longMessages) }
        try await Task.sleep(nanoseconds: 1_500_000_000)

        // 并发 fork：事务必须阻塞在 source generation gate 上
        let forkFinished = TestFlag()
        let forkTask = Task {
            defer { Task { await forkFinished.set(true) } }
            return try await runtime.forkSessionBranch(
                sessionId: "s", sourceBranch: "main", targetBranch: "alt", in: dir)
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let forkStillBlocked = await forkFinished.get()
        XCTAssertFalse(
            forkStillBlocked,
            "fork 不能在 source generation 持 gate 期间完成（skew window 复发）")

        // generation 释放后 fork 才执行；forkPoint 必须记录 source 状态
        let genResult = try await genTask.value
        XCTAssertFalse(genResult.text.isEmpty)
        let forkMeta = try await forkTask.value
        XCTAssertEqual(
            forkMeta.forkPoint?.sourceStorageKey, "default/s/main",
            "child fork point 必须记录 source execution")
        XCTAssertGreaterThan(
            forkMeta.forkPoint?.atToken ?? 0, 0, "fork 点必须持久化")
    }

}

/// 快照格式异常（官方 savePromptCache 约定被破坏时中断并给出上下文）。
private struct SnapshotFormatError: LocalizedError, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
    var description: String { message }
}
