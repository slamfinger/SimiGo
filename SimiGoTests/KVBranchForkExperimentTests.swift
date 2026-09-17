import XCTest
import Foundation
import MLXLMCommon
import MLXLLM
import MLXHuggingFace
import Tokenizers
@testable import SimiGo

/// KV 分叉实验（2026-09-17）：把「qwen3_5_moe（GDN 混合架构）不可 rewind 但可 fork」
/// 从代码推论变成实机证据。
///
/// 全部走现有公开 API，零生产改动：
///   generate()（SimiGo 会话复用闸门 + 官方 PromptCacheReusePolicy）
///   saveSessionCache() / loadSessionCache()（官方 saveCache / loadPromptCacheSnapshot 透传）
/// 分叉 = 测试侧把 checkpoint 文件按目标分支 storageKey 复制后分别加载。
/// 磁盘反序列化天然产生独立可变 cache 实例，等价于官方文档红线
/// 「copy the caches before constructing multiple sessions from it」。
///
/// 验收：
///  A1 快照携带 GDN 状态：safetensors 头解析出 MambaCache 类（+ attention KVCache 类）。
///  A2 checkpoint → 双分支续问零重算：恢复分支走官方 fragment-continuation
///     （raw-cache 无账本 → 官方不发 mode、cacheHit=0），物理证据 =
///     cacheTokens=checkpoint 账本长度、promptTokens≈delta、ttft 远小于冷路径。
///  A3 分支输出与同 prompt 独立冷预填逐字一致（greedy）。
///  A4 同 prompt 冷路径（retr=生产「重试分叉」的当前代价）mode=cold、cacheHit=0、
///     TTFT 高一个数量级——GDN 不可 rewind 的结构性反证：SimiGo 只能整会话重建。
/// 对照：SIMIGO_FORK_MODEL 指向标准注意力模型（如 qwen3_moe）可跑 Dense cache
/// 对照组——fork 语义与模型无关，预期仅快照组成（无 MambaCache）不同。
final class KVBranchForkExperimentTests: XCTestCase {

    private static let recallNumber = "4711"

    /// 真机生产同款模型；环境变量 SIMIGO_FORK_MODEL 可覆盖。
    private static let defaultModelPath =
        "/Users/mr.simi/.cache/huggingface/hub/models--peculiar-ragdoll--Nail-Qwen3.6-35B-A3B-MLX"
        + "/snapshots/31a0106483c94e9fbb0a6d3360ff122d47377058"

    private static let systemMsg = SimiGo.JSONValue.object([
        "role": .string("system"),
        "content": .string(
            "You are a precise assistant. Follow instructions exactly. " +
            "Answer in English without extra words.")
    ])

    private static func user(_ text: String) -> SimiGo.JSONValue {
        .object(["role": .string("user"), "content": .string(text)])
    }

    private static func assistant(_ text: String) -> SimiGo.JSONValue {
        .object(["role": .string("assistant"), "content": .string(text)])
    }

    /// ~100 行确定性档案文本，渲染后 ≈3k tokens：让冷/分叉的 prefill 差可测。
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

    // MARK: - 实验

    func testCheckpointForkOnQwen35MoE() async throws {
        guard ProcessInfo.processInfo.environment["SIMIGO_FORK_EXP"] == "1" else {
            throw XCTSkip("实机 KV 分叉实验：需 SIMIGO_FORK_EXP=1 且本机存在 qwen3_5_moe 权重")
        }
        let modelPath = ProcessInfo.processInfo.environment["SIMIGO_FORK_MODEL"]
            ?? Self.defaultModelPath
        guard FileManager.default.fileExists(atPath: modelPath + "/config.json") else {
            throw XCTSkip("模型不存在：\(modelPath)")
        }

        let traceOffset = Self.traceLogByteLength()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kvfork-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var cfg = ModelConfig()
        cfg.temperature = 0 // greedy：跨会话输出逐字可比
        cfg.maxTokens = 24
        cfg.disableThinking = true
        cfg.useMTP = false

        let info = ModelInfo(path: modelPath, kind: .mlx)
        let runtime = NativeMLX(info: info, config: cfg)

        func gen(_ branch: String, _ messages: [SimiGo.JSONValue]) async throws -> GenerationResult {
            // UUID 与生产默认同款；时间戳形态在长期回归里存在同毫秒碰撞理论窗口
            let requestId = "exp-\(branch)-\(UUID().uuidString.prefix(8).lowercased())"
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

        // phase 1：base 冷生成 → 会话 default/s/base（ledger = 渲染 prompt + a0）
        try await runtime.start(info, port: 18773)
        let baseMessages: [SimiGo.JSONValue] = [Self.systemMsg, Self.user(Self.baseCorpus())]
        let base = try await gen("base", baseMessages)
        let a0 = base.text
        XCTAssertFalse(a0.isEmpty, "base 生成不应为空")
        XCTAssertGreaterThan(
            base.usage?.promptTokens ?? 0, 2000,
            "base 语料应 ≥2k tokens，实际 \(base.usage?.promptTokens ?? 0)")

        // phase 2：checkpoint @ D = base 轮结束的消息边界
        let snapshotURL = try await runtime.saveSessionCache(
            sessionId: "s", logicalBranchId: "base", to: dir)
        let snapAttributes = (try? FileManager.default.attributesOfItem(atPath: snapshotURL.path)) ?? [:]
        let snapSize = (snapAttributes[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(snapSize, 1_000_000, "checkpoint 应为 MB 级，实际 \(snapSize)B")

        // A1：快照 cache 组成必须与架构一致——混合 GDN 模型携带 MambaCache，
        // 标准注意力模型（Dense cache 对照，SIMIGO_FORK_MODEL 覆盖）全为 KVCache。
        let configData = try? Data(contentsOf: URL(fileURLWithPath: modelPath + "/config.json"))
        let configObject = (try? JSONSerialization.jsonObject(with: configData ?? Data()))
            as? [String: Any]
        let modelType = configObject?["model_type"] as? String ?? "unknown"
        let isHybridGDN = modelType == "qwen3_5_moe" || modelType == "qwen3_next"
        let classes = try Self.snapshotCacheClasses(at: snapshotURL)
        let mambaCount = classes.filter { $0 == "MambaCache" }.count
        let attnCount = classes.filter { $0 == "KVCache" || $0 == "RotatingKVCache" }.count
        print("[fork-exp] model_type=\(modelType) hybridGDN=\(isHybridGDN)")
        print("[fork-exp] snapshot caches: MambaCache=\(mambaCount) attn=\(attnCount) total=\(classes.count)")
        if isHybridGDN {
            XCTAssertGreaterThanOrEqual(mambaCount, 8, "快照应携带 GDN(MambaCache) 状态，实际 \(mambaCount)")
            XCTAssertGreaterThanOrEqual(attnCount, 2, "快照应携带 attention KV，实际 \(attnCount)")
        } else {
            XCTAssertEqual(mambaCount, 0, "标准注意力模型不应有 MambaCache，实际 \(mambaCount)")
            XCTAssertGreaterThanOrEqual(attnCount, 8, "快照应携带全部 attention KV，实际 \(attnCount)")
        }

        // phase 3：checkpoint 复制到两个分支 storageKey 名下（各自独立可变实例）
        let baseKey = "default/s/base"
        for branch in ["forkA", "forkB"] {
            let branchKey = "default/s/\(branch)"
            for suffix in [".safetensors", ".meta.json"] {
                try FileManager.default.copyItem(
                    at: dir.appendingPathComponent(NativeMLX.cacheFileName(for: baseKey) + suffix),
                    to: dir.appendingPathComponent(NativeMLX.cacheFileName(for: branchKey) + suffix))
            }
        }

        // phase 4：forkA 从 checkpoint 恢复（官方 fragment-continuation 语义）
        let metaA = try await runtime.loadSessionCache(
            sessionId: "s", logicalBranchId: "forkA", from: dir)
        XCTAssertEqual(metaA.history.count, 3, "恢复的 history 应为 [system, corpus, a0]")

        // phase 5：forkA 续问——应 extend，只预填新增问句
        let withReply = baseMessages + [Self.assistant(a0)]
        let questionA =
            "Rewrite exactly this sentence and nothing else: The fork carries the prefix state."
        let forkA1 = try await gen("forkA", withReply + [Self.user(questionA)])
        XCTAssertFalse(forkA1.text.isEmpty, "forkA 首轮生成不应为空")

        // phase 6：forkA 再续一轮——恢复后的会话必须还能继续 extend
        let forkA2 = try await gen(
            "forkA", withReply + [Self.user(questionA), Self.assistant(forkA1.text),
                Self.user("Append the word DONE to your previous answer.")]
        )
        XCTAssertFalse(forkA2.text.isEmpty, "forkA 二轮生成不应为空")

        // phase 7：forkB 从同一 checkpoint 恢复并问召回问题（GDN 长程记忆探针）
        _ = try await runtime.loadSessionCache(sessionId: "s", logicalBranchId: "forkB", from: dir)
        let questionB = "What number did I ask you to remember? Reply with only that number."
        let forkB = try await gen("forkB", withReply + [Self.user(questionB)])
        XCTAssertTrue(
            forkB.text.contains(Self.recallNumber),
            "forkB 应召回 \(Self.recallNumber)，实际：\(forkB.text)")

        // phase 8：coldA = 同 prompt 独立冷预填（forkA 的正确性参照）
        let coldA = try await gen("coldA", withReply + [Self.user(questionA)])

        // phase 9/A4：retr = 完全相同的 forkB prompt 走冷路径
        //（生产「分叉后重试」的当前代价；GDN 不可 rewind → 只能整会话重建）
        let retr = try await gen("retr", withReply + [Self.user(questionB)])

        await runtime.stop()

        // —— 验收断言（trace 窗口内按分支读取官方 mode）——
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
        XCTAssertEqual(modes("coldA"), ["cold"], "coldA 应 cold")
        XCTAssertEqual(modes("retr"), ["cold"], "retr 应 cold（A4）")

        // 官方语义（2026-09-17 实机校准）：checkpoint 恢复的会话是 raw-cache
        //（无 token 账本），复用判定没有可对照的 ledger → 官方不发 mode 字符串，
        // cacheHit/cacheEff 报 0（SimiGo 透传官方值，不估算）。
        // 分叉零重算的物理证据由三项承担：cacheTokens=5413（checkpoint 账本
        // 逐位在列）、promptTokens≈delta（只预填新增问句）、ttft 远小于冷路径。
        XCTAssertEqual(modes("forkA"), [], "恢复分支走 fragment-continuation，官方不发 mode")
        XCTAssertEqual(modes("forkB"), [])
        // checkpoint 账本 = base prompt + 生成尾部。官方 generationTokens 口径
        // 可能不含结束 token（dense 实测报告 +1、账本 +2），故取 ±2 容差；
        // 真正的截断/丢失会是千级差距，±2 足以证明逐位在列。
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
            "不应出现 SimiGo 复用闸门 miss：\n" +
                lines.filter { $0.contains("reuseMiss") }.joined(separator: "\n"))
        XCTAssertFalse(
            lines.contains { $0.contains("fork@common") },
            "不应出现活会话渲染分叉（fork-no-rewind）")

        // A3：greedy 下分支与冷预填逐字一致
        XCTAssertEqual(
            forkA1.text, coldA.text,
            "forkA 与 coldA 输出应逐字一致\nforkA: \(forkA1.text)\ncoldA: \(coldA.text)")
        XCTAssertEqual(
            forkB.text, retr.text,
            "forkB 与 retr 输出应逐字一致\nforkB: \(forkB.text)\nretr: \(retr.text)")

        // A4：同 prompt 双路径的代价对比
        let ttftFork = forkB.usage?.ttftSeconds ?? -1
        let ttftCold = retr.usage?.ttftSeconds ?? .greatestFiniteMagnitude
        let cachedCold = retr.usage?.cachedPromptTokens ?? 0
        XCTAssertEqual(cachedCold, 0, "冷路径 cacheHit 应为 0，实际 \(cachedCold)")
        XCTAssertGreaterThan(
            ttftCold, ttftFork * 3,
            String(format: "fork TTFT 应比 cold 低 3 倍以上：fork=%.3fs cold=%.3fs", ttftFork, ttftCold))

        // —— 汇总报告 ——
        func row(_ label: String, _ mode: String, _ r: GenerationResult) -> String {
            let u = r.usage
            let ttft = u?.ttftSeconds.map { String(format: "%.3fs", $0) } ?? "-"
            return "\(label.padding(toLength: 6, withPad: " ", startingAt: 0)) mode=\(mode.padding(toLength: 8, withPad: " ", startingAt: 0)) " +
                "prompt=\(u?.promptTokens ?? -1) cached=\(u?.cachedPromptTokens ?? -1) " +
                "cacheEff=\(u?.cacheEfficiency.map { String(format: "%.3f", $0) } ?? "-") ttft=\(ttft)"
        }
        print("[fork-exp] ===== 结果汇总 =====")
        print("[fork-exp] " + row("base", modes("base").last ?? "-", base))
        print("[fork-exp] " + row("forkA1", "fragment", forkA1))
        print("[fork-exp] " + row("forkA2", "fragment", forkA2))
        print("[fork-exp] " + row("forkB", modes("forkB").last ?? "-", forkB))
        print("[fork-exp] " + row("coldA", modes("coldA").last ?? "-", coldA))
        print("[fork-exp] " + row("retr", modes("retr").last ?? "-", retr))
        print("[fork-exp] snapshot: \(snapSize)B, MambaCache=\(mambaCount), attn=\(attnCount)")
        print("[fork-exp] forkA1 text: \(forkA1.text)")
        print("[fork-exp] forkA2 text: \(forkA2.text)")
        print("[fork-exp] forkB  text: \(forkB.text)")
        print("[fork-exp] coldA  text: \(coldA.text)")
        print("[fork-exp] retr   text: \(retr.text)")
    }

    /// 内存版 fork 专测：闭合「同一内存快照 → KVCache.copy() → 多个 ChatSession
    /// 是否安全」这一未验证边界。直接打官方层（自建 ModelContainer，不经 NativeMLX），
    /// 32GB 机器只允许单容器加载。
    ///
    /// 与磁盘 fork 的差异：省去序列化往返，各分支 cache 是同一组内存对象的 copy()。
    /// 官方红线：cache 是可变引用类型，多 session 前必须 copy——本测试验证的正是
    /// 「copy() 是否足以隔离」。state（LMOutput.State）是 struct 值语义，按生产 fork
    /// 形态直接共享传入，由行为断言背书。
    ///
    /// 交错顺序覆盖双向污染探测：A1 → A2 → B（B 在 A 变异后载入运行）→ A3
    /// （A 在 B 运行后再续一轮）。每轮记录官方 promptTokenCount 证明只算增量。
    func testInMemoryForkCopyOwnership() async throws {
        guard ProcessInfo.processInfo.environment["SIMIGO_FORK_EXP"] == "1" else {
            throw XCTSkip("实机 KV 分叉实验：需 SIMIGO_FORK_EXP=1 且本机存在 qwen3_5_moe 权重")
        }
        let modelPath = ProcessInfo.processInfo.environment["SIMIGO_FORK_MODEL"]
            ?? Self.defaultModelPath
        guard FileManager.default.fileExists(atPath: modelPath + "/config.json") else {
            throw XCTSkip("模型不存在：\(modelPath)")
        }

        let container = try await LLMModelFactory.shared.loadContainer(
            from: URL(fileURLWithPath: modelPath),
            using: #huggingFaceTokenizerLoader())

        let params = GenerateParameters(maxTokens: 24, temperature: 0) // greedy
        let extra: [String: any Sendable] = ["enable_thinking": false]

        func drain(
            _ session: ChatSession, _ messages: [Chat.Message]
        ) async throws -> (text: String, promptTokens: Int, promptTime: Double?) {
            var text = ""
            var promptTokens = -1
            var promptTime: Double?
            for try await g in session.streamDetails(to: messages) {
                switch g {
                case .chunk(let t): text += t
                case .info(let i):
                    promptTokens = i.promptTokenCount
                    promptTime = i.promptTime
                default: break
                }
            }
            return (text, promptTokens, promptTime)
        }

        // base：官方会话直接生成（等价磁盘实验 phase 1，但走 ChatSession 原生 API）
        let base = ChatSession(
            container, history: [], generateParameters: params, additionalContext: extra)
        let (a0, basePrompt, _) = try await drain(base, [
            .system("You are a precise assistant. Follow instructions exactly. " +
                "Answer in English without extra words."),
            .user(Self.baseCorpus()),
        ])
        XCTAssertFalse(a0.isEmpty, "base 生成不应为空")
        XCTAssertGreaterThan(basePrompt, 2000, "base 语料应 ≥2k tokens，实际 \(basePrompt)")

        // checkpoint → 内存快照
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kvfork-mem-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let snapshotURL = dir.appendingPathComponent("base.safetensors")
        try await base.saveCache(to: snapshotURL)
        let shared = try loadPromptCacheSnapshot(url: snapshotURL)

        // 分支：同一快照，各 cache copy()（官方红线）；state 按值共享
        let cachesA = shared.cache.map { $0.copy() }
        let cachesB = shared.cache.map { $0.copy() }
        let forkA = ChatSession(
            container, instructions: nil,
            promptCache: PromptCacheSnapshot(cache: cachesA, state: shared.state),
            generateParameters: params, additionalContext: extra)
        let forkB = ChatSession(
            container, instructions: nil,
            promptCache: PromptCacheSnapshot(cache: cachesB, state: shared.state),
            generateParameters: params, additionalContext: extra)

        let questionA =
            "Rewrite exactly this sentence and nothing else: The fork carries the prefix state."
        let followupA = "Append the word DONE to your previous answer."
        let questionB = "What number did I ask you to remember? Reply with only that number."

        // 交错：A1 → A2（A 已变异自身副本）→ B（此时才首次运行）→ A3（B 运行后 A 再续）
        let (a1, pA1, _) = try await drain(forkA, [.user(questionA)])
        let (a2, pA2, _) = try await drain(forkA, [.user(followupA)])
        let (b1, pB1, _) = try await drain(forkB, [.user(questionB)])
        let (a3, pA3, _) = try await drain(forkA, [.user(questionB)])

        // 冷参照：history 初始化器全量渲染（logical history = base + a0 + 新问句）
        let logicalHistory: [Chat.Message] = [
            .system("You are a precise assistant. Follow instructions exactly. " +
                "Answer in English without extra words."),
            .user(Self.baseCorpus()),
            .assistant(a0),
        ]
        let coldA = ChatSession(
            container, history: logicalHistory, generateParameters: params,
            additionalContext: extra)
        let (ca, pCA, _) = try await drain(coldA, [.user(questionA)])
        let coldB = ChatSession(
            container, history: logicalHistory, generateParameters: params,
            additionalContext: extra)
        let (cb, pCB, _) = try await drain(coldB, [.user(questionB)])

        // —— 验收 ——
        // 输出：逐字一致（greedy）
        XCTAssertEqual(
            a1, ca, "内存 forkA 与冷参照应逐字一致\nforkA: \(a1)\ncoldA: \(ca)")
        XCTAssertEqual(
            b1, cb, "内存 forkB 与冷参照应逐字一致\nforkB: \(b1)\ncoldB: \(cb)")
        XCTAssertTrue(a2.contains("DONE"), "A2 应延续 A 的回答，实际：\(a2)")
        XCTAssertTrue(a3.contains(Self.recallNumber), "A3（B 运行后）应仍召回，实际：\(a3)")

        // 只算增量：分支每轮官方报告的 promptTokenCount 必须是 fragment 量级
        for (label, tokens) in [("forkA1", pA1), ("forkA2", pA2), ("forkB1", pB1), ("forkA3", pA3)] {
            XCTAssertLessThan(
                tokens, 400, "\(label) 只应预填增量（<400 tok），实际 \(tokens)")
        }
        XCTAssertGreaterThan(pCA, 2000, "冷参照应为全量预填，实际 \(pCA)")
        XCTAssertGreaterThan(pCB, 2000, "冷参照应为全量预填，实际 \(pCB)")

        print("[fork-exp][mem] promptTokens: forkA1=\(pA1) forkA2=\(pA2) forkB1=\(pB1) forkA3=\(pA3) coldA=\(pCA) coldB=\(pCB)")
        print("[fork-exp][mem] a1: \(a1)")
        print("[fork-exp][mem] a2: \(a2)")
        print("[fork-exp][mem] b1: \(b1)")
        print("[fork-exp][mem] a3: \(a3)")
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
}

/// 快照格式异常（官方 savePromptCache 约定被破坏时中断实验并给出上下文）。
private struct SnapshotFormatError: LocalizedError, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
    var description: String { message }
}
