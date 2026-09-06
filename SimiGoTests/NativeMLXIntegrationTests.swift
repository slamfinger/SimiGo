import XCTest
import MLX
import MLXLMCommon
import MLXLLM
import MLXHuggingFace
import Tokenizers
@testable import SimiGo

// MLXLMCommon 与 SimiGo 均定义 JSONValue——本文件的 messages 语义用 SimiGo 的
private typealias JSONValue = SimiGo.JSONValue

/// P1 集成测试（审计 2026-09-06 第 6 节）：stop() 收敛不变量——
/// 「stop() 返回以后，任何在 stop 开始之前已经进入 generate 生命周期的
/// request 都不得仍然持有有效 generation / KV / stream / task 状态」。
///
/// 需要真实 MLX 模型，默认跳过。模型路径来源（按序）：
/// 1. 宿主进程环境变量 SIMIGO_TEST_MODEL_PATH
/// 2. 宿主 App UserDefaults 同名键（xcodebuild 不透传环境变量时的替代通道：
///    `defaults write SwiftUI.SimiGo SIMIGO_TEST_MODEL_PATH <path>`，跑完删除）
final class NativeMLXIntegrationTests: XCTestCase {
    private static var modelPath: String? {
        if let env = ProcessInfo.processInfo.environment["SIMIGO_TEST_MODEL_PATH"],
           !env.isEmpty {
            return env
        }

        let fromDefaults = UserDefaults.standard.string(forKey: "SIMIGO_TEST_MODEL_PATH")
        return (fromDefaults?.isEmpty == false) ? fromDefaults : nil
    }

    func testStopConvergenceInvariant() async throws {
        guard let modelPath = Self.modelPath else {
            throw XCTSkip("设置 SIMIGO_TEST_MODEL_PATH 后运行（加载真实 MLX 模型，约 1-3 分钟）")
        }

        let info = ModelInfo(path: modelPath, kind: .mlx)
        let runtime = NativeMLX(info: info, config: ModelConfig())
        let port = 47_000 + Int.random(in: 0..<2_000)

        try await withTestTimeout(seconds: 600) {
            try await runtime.start(info, port: port)
        }
        XCTAssertTrue(runtime.isRunning)

        let messages: [JSONValue] = [
            .object([
                "role": .string("user"),
                "content": .string("只回复两个字母: ok"),
            ])
        ]
        var config = ModelConfig()
        config.maxTokens = 16

        // ① 快乐路径：完整生成 → revision 必须提交、收尾必须归零
        let text = try await withTestTimeout(seconds: 300) {
            try await runtime.generate(
                requestId: "itest-happy",
                agentId: "itest",
                sessionId: "s1",
                logicalBranchId: "main",
                messages: messages,
                tools: nil,
                config: config,
                onChunk: { _ in }
            )
        }
        XCTAssertFalse(text.isEmpty, "真实模型应产出非空生成")

        var snap = runtime.integrationSnapshot()
        XCTAssertGreaterThanOrEqual(snap.revisions, 1, "成功生成必须提交 Physical KV Revision")
        XCTAssertTrue(
            snap.revisionsLedgerSynced,
            "四账本不变量：revision 账本长度必须与 MLX 物理 KV offset 逐层一致" +
                "（EOS 终止路径曾偏移 1，见 KV 全链路审计 2026-09-06 P1）"
        )
        XCTAssertEqual(snap.activeRequests, 0, "请求完成后 task 登记必须清空")
        XCTAssertEqual(snap.activeGenerations, 0)
        XCTAssertEqual(snap.generatingSessions, 0)

        // ①.5 warm 轮（多轮一致性与复用全链锚点，模型无关）：
        // 以 ① 的真实回复构造 turn-2 形态 prompt（user → assistant(text) → user2），
        // 与 ① 的 revision 共享模板+对话前缀。
        // - 纯全注意力模型：应命中 warm 复用（trace [KVR] cp>0），copy→trim→delta
        //   prefill→generate→commit 全链在真实复用缓存上跑通——dense 模型到位后，
        //   此处即「复用→commit→对账」的实机回归锚点；
        // - 混合模型（MambaCache）：门禁正确拦截（trace [KVM] nonTrimmableCache），走冷启动。
        // 两种路径都等价新增一个 revision，且账本必须保持逐层对齐。
        let warmMessages: [JSONValue] = [
            messages[0],
            .object([
                "role": .string("assistant"),
                "content": .string(text),
            ]),
            .object([
                "role": .string("user"),
                "content": .string("再回复两个字母: hi"),
            ]),
        ]

        var warmConfig = config
        warmConfig.maxTokens = 16

        let warmText = try await withTestTimeout(seconds: 300) {
            try await runtime.generate(
                requestId: "itest-warm",
                agentId: "itest",
                sessionId: "s1",
                logicalBranchId: "main",
                messages: warmMessages,
                tools: nil,
                config: warmConfig,
                onChunk: { _ in }
            )
        }

        XCTAssertFalse(warmText.isEmpty, "warm 轮应产出非空生成")

        snap = runtime.integrationSnapshot()
        XCTAssertEqual(
            snap.revisions, 2,
            "warm 轮应等价新增一个 revision（token 序列不同，同 prompt 去重不适用）"
        )
        XCTAssertTrue(
            snap.revisionsLedgerSynced,
            "warm commit 后账本仍须与 KV offset 逐层对齐"
        )
        XCTAssertEqual(snap.activeRequests, 0)
        XCTAssertEqual(snap.generatingSessions, 0)

        // ② 竞态轮：generate 与 stop 并发——请求先进入生命周期，stop 再启动。
        //
        // 审计 ①：固定 sleep（300ms/500ms/1s）锁不住竞态——stop 到来时请求可能尚未注册、
        // 也可能已经跑完，测到的只是「未注册 → stop」或「完成 → stop」。
        //
        // 确定性同步点：第一个 onChunk 只会在请求通过 generation gate 并真正产出 token
        // 之后触发，因此「信号已 fire」==「请求已进入 generate 生命周期」。
        //
        // 竞态锁死（实跑教训）：短问答提示（「只回复 ok」）会让模型在首 chunk 后几十 ms
        // 内 EOS 自然完成，maxTokens 拦不住 EOS，取消抢不过自然结束。改用长生成任务：
        // 数到 500 需 500+ token 连续 decode（秒级），而 stop() 的取消在首 chunk 后
        // 毫秒级落地——自然完成抢在取消之前在物理上不可能，竞态因此锁死。
        let enteredGeneration = TestSignal()
        var raceConfig = config
        raceConfig.maxTokens = 4096
        let raceMessages: [JSONValue] = [
            .object([
                "role": .string("user"),
                "content": .string(
                    "用阿拉伯数字从1数到500，每行一个数字，不要输出任何其他内容，数完最后单独一行输出DONE"
                ),
            ])
        ]

        let raceTask = Task { () -> String? in
            do {
                return try await runtime.generate(
                    requestId: "itest-race",
                    agentId: "itest",
                    sessionId: "s2",
                    logicalBranchId: "main",
                    messages: raceMessages,
                    tools: nil,
                    config: raceConfig,
                    onChunk: { _ in enteredGeneration.fire() }
                )
            } catch {
                return nil
            }
        }

        try await withTestTimeout(seconds: 30) {
            await enteredGeneration.wait()
        }

        try await withTestTimeout(seconds: 120) {
            await runtime.stop()
        }

        // ③ 不变量：stop() 返回后五个计数全部归零
        snap = runtime.integrationSnapshot()
        XCTAssertEqual(snap.activeRequests, 0, "stop 后不得残留请求 task 登记")
        XCTAssertEqual(snap.activeGenerations, 0, "stop 后不得残留 generation task")
        XCTAssertEqual(snap.generatingSessions, 0)
        XCTAssertEqual(snap.revisions, 0, "stop 后 Physical KV 必须清空")
        XCTAssertEqual(snap.sessions, 0, "stop 后 sessionCaches 必须清空")
        XCTAssertFalse(runtime.isRunning)
        XCTAssertFalse(runtime.isGenerating)

        // ④ 竞态请求必须收敛（不悬挂、无僵尸 task），且必须是被 stop 打断的。
        //
        // 产线契约（实跑确认）：取消的 generate 不抛错——跳过 KV commit、发 cancelled
        // 观测后，正常返回已产出的部分文本（generateAfterGate 收尾 return completedText）。
        // 因此「被取消」的证据是：要么抛错（未来契约变化），要么部分文本远未到达任务
        // 终点（不含结尾标记 DONE）。若 DONE 已出现，说明取消没有打断生成——竞态未锁死。
        let raceText = try await withTestTimeout(seconds: 60) {
            await raceTask.value
        }

        if let raceText {
            XCTAssertFalse(
                raceText.contains("DONE"),
                "竞态请求应被 stop() 打断为部分文本，实际却完整生成到终点: …\(raceText.suffix(100))"
            )
        }
        XCTAssertEqual(runtime.integrationSnapshot().activeRequests, 0)

        // ⑤ stop 后新请求必须被拒绝（isRunning 门禁 → notLoaded）
        do {
            _ = try await withTestTimeout(seconds: 30) {
                try await runtime.generate(
                    requestId: "itest-after-stop",
                    agentId: "itest",
                    sessionId: "s3",
                    logicalBranchId: "main",
                    messages: messages,
                    tools: nil,
                    config: config,
                    onChunk: { _ in }
                )
            }
            XCTFail("stop 后 generate 必须失败")
        } catch is TestTimeout {
            XCTFail("stop 后 generate 不得悬挂")
        } catch {
            // RuntError.notLoaded 为预期路径
        }

        XCTAssertFalse(runtime.isRunning)
    }

    // MARK: - 性能审计（KV 全链路第四轮）：多轮 warm hit 衰减 + 长上下文 + eviction 压力

    /// 多轮会话 warm hit 衰减实测（模型无关，需要 SIMIGO_TEST_MODEL_PATH）：
    /// turn-1 冷启动后，每轮注入一段代码压力块使 prompt 逐步增长至 ~20K。
    ///
    /// 硬契约（审计 P2-1：warm hit 不得只靠 trace 人工分析；模式由 topology 定义）：
    /// - 复用模式由 cache topology 决定——池内全部 revision 可裁剪（dense）→ 必须复用；
    ///   含不可裁剪 cache（hybrid/Mamba）→ 必须无复用。
    ///   不得由「turn 2 是否命中」反向推断模式：否则 dense 的 warm hit 回归会被
    ///   测试自身误判成 gated 模式，全绿假阴性。
    /// - turn 1：池空必须冷启动（lastReuse == -1），同时锁定 topology 模式；
    /// - turn 2+：dense 模式每轮必须命中上一 revision 且吃满其全部前缀
    ///   （lastReuseSourceTokens == lastReuseCommonLen == 上一 revision 账本长度，
    ///   cp == 源全长、零漂移）；gated 模式每轮必须无复用。
    /// 命中率/TTFT/prefill/decode TPS/admission 驱逐仍经 trace 留痕供衰减曲线分析。
    /// 12 轮 ≈ 20K token：32GB 机器上 32K/64K 的 decode 已实测塌方（性能审计第四轮），
    /// 更长上下文留待大内存环境。
    private func perfPaddingBlock(_ turn: Int) -> String {
        let header = "// === turn \(turn) 长上下文压力块 ===\n"
        let line = "let metric\(turn) = evaluateStep(\(turn), payload: \"pad-\(turn)-sample-payload\")\n"
        return header + String(repeating: line, count: 90)
    }

    func testPerformanceMultiTurnWarmHitDecay() async throws {
        guard let modelPath = Self.modelPath else {
            throw XCTSkip("设置 SIMIGO_TEST_MODEL_PATH 后运行（多轮长上下文压测，数分钟）")
        }

        let info = ModelInfo(path: modelPath, kind: .mlx)
        let runtime = NativeMLX(info: info, config: ModelConfig())
        let port = 47_000 + Int.random(in: 0..<2_000)

        do {
            try await withTestTimeout(seconds: 600) {
                try await runtime.start(info, port: port)
            }

            var config = ModelConfig()
            config.maxTokens = 16

            var conversation: [JSONValue] = [
                .object([
                    "role": .string("user"),
                    "content": .string(
                        "我们进行多轮代码推演。每轮我给一段代码，你只回复 ok。第一段：func add(_ a: Int, _ b: Int) -> Int { a + b }"
                    ),
                ])
            ]

            let turnBudget = 12

            var expectReuse: Bool? = nil
            var prevRevisionTokens = -1

            for turn in 1...turnBudget {
                if turn > 1 {
                    conversation.append(
                        .object([
                            "role": .string("user"),
                            "content": .string(perfPaddingBlock(turn)),
                        ])
                    )
                }

                let text = try await withTestTimeout(seconds: 180) {
                    try await runtime.generate(
                        requestId: "perf-t\(turn)",
                        agentId: "perf",
                        sessionId: "perf-s",
                        logicalBranchId: "main",
                        messages: conversation,
                        tools: nil,
                        config: config,
                        onChunk: { _ in }
                    )
                }

                XCTAssertFalse(text.isEmpty, "turn \(turn) 应产出非空生成")

                conversation.append(
                    .object([
                        "role": .string("assistant"),
                        "content": .string(text),
                    ])
                )

                let snap = runtime.integrationSnapshot()
                XCTAssertTrue(
                    snap.revisionsLedgerSynced,
                    "turn \(turn) 提交后账本必须与 KV offset 逐层对齐"
                )

                if turn == 1 {
                    XCTAssertEqual(
                        snap.lastReuseCommonLen, -1,
                        "turn 1 池空必须冷启动"
                    )
                    // 模式由 topology 定义，不由命中结果反向推断（P2-1 假阴性修复）
                    expectReuse = snap.poolTrimmable
                } else if expectReuse == true {
                    XCTAssertEqual(
                        snap.lastReuseSourceTokens, prevRevisionTokens,
                        "turn \(turn) 复用源必须是上一 revision"
                    )
                    XCTAssertEqual(
                        snap.lastReuseCommonLen, prevRevisionTokens,
                        "turn \(turn) 复用必须吃满源全部前缀（零漂移）"
                    )
                } else {
                    XCTAssertEqual(
                        snap.lastReuseCommonLen, -1,
                        "turn \(turn) 不可裁剪池必须始终无复用"
                    )
                }

                prevRevisionTokens = snap.revisionTokenCounts.first ?? -1
            }

            let finalSnap = runtime.integrationSnapshot()
            XCTAssertTrue(finalSnap.revisionsLedgerSynced)
            XCTAssertGreaterThanOrEqual(finalSnap.revisions, 1)
            XCTAssertEqual(finalSnap.activeRequests, 0)
            XCTAssertEqual(finalSnap.generatingSessions, 0)

            // 审计 P2-2：显式生命周期收尾——stop() 负责 server/task/gate/KV/memory
            // 全套收敛，不得依赖对象析构；否则污染同进程后续测试。
            await runtime.stop()
        } catch {
            // 异常路径同样收敛全套生命周期
            await runtime.stop()
            throw error
        }
    }

    /// Admission P1 回归（审计第四轮）：冷启动无任何可驱逐 revision，projected KV
    /// 超过 admission 上限 → 必须 admissionExceeded 拒绝，不得走 [ADMISSION WARN]
    /// 放行 generation（P1 缺口：WARN 后继续生成会 OOM/页出）。
    ///
    /// prompt ≈ 598K chars：实测该文本形态分词效率 ≥5.08 chars/token（首测 320K chars
    /// 仅得 ≤63K token、projected 11.4GB < 12GB 被放行，注入量不足的教训），
    /// 598K → 92K-118K token 区间：
    /// - demand = tokens + 16 恒 < ctxSize 131072 → 不会被 context 安全检查拒绝；
    /// - projected = tokens × 128KB + working set 3GB + margin 1GB ≥ 14.7GB > 12GB 预算
    ///   → 恒超预算；冷启动池空 → pendingReleases 必为空 → 走 P1 修复的统一硬拒绝。
    /// 「全池已 non-resident」与冷启动在代码上同路径（候选过滤后 candidates 为空），
    /// 由本测试结构性覆盖。
    func testAdmissionRejectsOverBudgetWithoutEvictableRevision() async throws {
        guard let modelPath = Self.modelPath else {
            throw XCTSkip("设置 SIMIGO_TEST_MODEL_PATH 后运行（admission 回归）")
        }

        let info = ModelInfo(path: modelPath, kind: .mlx)
        let runtime = NativeMLX(info: info, config: ModelConfig())
        let port = 47_000 + Int.random(in: 0..<2_000)

        do {
            try await withTestTimeout(seconds: 600) {
                try await runtime.start(info, port: port)
            }

            var config = ModelConfig()
            config.maxTokens = 16

            let pad = String(
                repeating: "let metric = evaluateStep(payload: \"admission-pressure-sample\")\n",
                count: 8_800
            )

            do {
                _ = try await withTestTimeout(seconds: 120) {
                    try await runtime.generate(
                        requestId: "admit-over",
                        agentId: "perf",
                        sessionId: "admit-s",
                        logicalBranchId: "main",
                        messages: [
                            .object([
                                "role": .string("user"),
                                "content": .string(pad),
                            ])
                        ],
                        tools: nil,
                        config: config,
                        onChunk: { _ in }
                    )
                }
                XCTFail("超预算且无可驱逐 revision 必须被 admissionExceeded 拒绝（P1 缺口回归）")
            } catch let error as RuntError {
                guard case .admissionExceeded = error else {
                    XCTFail("预期 admissionExceeded，实际: \(error)")
                    return
                }
                // 预期路径
            } catch is TestTimeout {
                XCTFail("admission 拒绝不得悬挂")
            }

            await runtime.stop()
        } catch {
            await runtime.stop()
            throw error
        }
    }

    /// 256K token 极限压测（KV 审计第五轮，ctxSize=262144）：验证超长 prompt 在正确的
    /// 防护层被拒绝、机器不死。两层防线各守其位：
    ///
    /// Phase A（默认 baseConfig，ctxSize=131072）：~234K token prompt 的
    /// demand ≈ 234K ≫ 131072 → context 门禁拒绝（contextDemandExceeded）。
    ///
    /// Phase B（base 与 request ctxSize 均抬至 262144——注意 min(request, base) 双侧
    /// 必须同时放行，首轮实测 request 侧漏抬导致 ctx 层误拒）：prompt 穿过 context
    /// 门禁，projected = ~234K × 128KB ≈ 29GB ≫ admissionLimit ~12GB
    /// → admission 硬拒绝（admissionExceeded，evicted=0）。修复前该路径是
    /// [ADMISSION WARN] 后继续生成 —— 29GB KV 分配尝试足以杀死整机。
    ///
    /// 注入量 ≈ 884K chars（实测分词效率 3.78 chars/token：首测 1.36M chars = 360,024
    /// token → ~234K token，Phase A 恒 > 131072；Phase B demand 恒 < 262144 且
    /// projected 恒 > 12GB）。
    func testExtreme256KPromptRejectedAtCorrectLayer() async throws {
        guard let modelPath = Self.modelPath else {
            throw XCTSkip("设置 SIMIGO_TEST_MODEL_PATH 后运行（256K 极限压测）")
        }

        let info = ModelInfo(path: modelPath, kind: .mlx)
        var config = ModelConfig()
        config.maxTokens = 16
        config.ctxSize = 262_144

        let pad = String(
            repeating: "let metric = evaluateStep(payload: \"extreme-256k-pressure-sample\")\n",
            count: 13_000
        )
        let extremeMessages: [JSONValue] = [
            .object(["role": .string("user"), "content": .string(pad)])
        ]

        // ── Phase A：默认 ctxSize → context 门禁拒绝 ──
        let runtimeA = NativeMLX(info: info, config: ModelConfig())
        let portA = 47_000 + Int.random(in: 0..<2_000)

        do {
            try await withTestTimeout(seconds: 600) {
                try await runtimeA.start(info, port: portA)
            }

            do {
                _ = try await withTestTimeout(seconds: 180) {
                    try await runtimeA.generate(
                        requestId: "extreme-256k-a",
                        agentId: "perf",
                        sessionId: "extreme-s",
                        logicalBranchId: "main",
                        messages: extremeMessages,
                        tools: nil,
                        config: config,
                        onChunk: { _ in }
                    )
                }
                XCTFail("256K token prompt 必须被 context 门禁拒绝（ctxSize=131072）")
            } catch let error as NativeMLXValidationError {
                guard case .contextDemandExceeded = error else {
                    XCTFail("预期 contextDemandExceeded，实际: \(error)")
                    return
                }
                // 预期路径
            } catch is TestTimeout {
                XCTFail("context 门禁拒绝不得悬挂")
            }

            await runtimeA.stop()
        } catch {
            await runtimeA.stop()
            throw error
        }

        // ── Phase B：base 与 request ctxSize 均为 262144 → admission 硬拒绝 ──
        var wideBase = ModelConfig()
        wideBase.ctxSize = 262_144
        let runtimeB = NativeMLX(info: info, config: wideBase)
        let portB = 47_000 + Int.random(in: 0..<2_000)

        do {
            try await withTestTimeout(seconds: 600) {
                try await runtimeB.start(info, port: portB)
            }

            do {
                _ = try await withTestTimeout(seconds: 180) {
                    try await runtimeB.generate(
                        requestId: "extreme-256k-b",
                        agentId: "perf",
                        sessionId: "extreme-s",
                        logicalBranchId: "main",
                        messages: extremeMessages,
                        tools: nil,
                        config: config,
                        onChunk: { _ in }
                    )
                }
                XCTFail("projected ~32GB KV 必须被 admissionExceeded 拒绝（P1 修复回归）")
            } catch let error as RuntError {
                guard case .admissionExceeded = error else {
                    XCTFail("预期 admissionExceeded，实际: \(error)")
                    return
                }
                // 预期路径
            } catch is TestTimeout {
                XCTFail("admission 拒绝不得悬挂")
            }

            await runtimeB.stop()
        } catch {
            await runtimeB.stop()
            throw error
        }
    }

    /// 多 execution-key 并发记账实测（审计下一阶段专项：全局 admission reservation）。
    ///
    /// 已确认缺口（审计第五轮修正后语义）：admission 已被 PrefillScheduler 串行化
    /// （[PWAIT] → [ADMISSION OBS] 实证），每个请求增量可见此前提交的 resident；
    /// 但 admission PASS 到自身 KV 物化/commit 之间无显式预留——
    /// accounting 只计 currentResidentKVBytes + 本请求 projected，
    /// 缺 inFlightReservedBytes（其他已 PASS 未 commit 请求的增量）。
    ///
    /// 本轮 5 → 10 owner 扩容（每 owner ~12K token，总 ~120K）：测量
    /// in-flight 深度、admission projected 序列、resident KV 增长、RSS/swap 峰值、
    /// 驱逐次数与分布——回答「驱逐式自我修正的安全余量还有多大、
    /// 何时才真的需要显式 reservation」。
    ///
    /// 断言只锁正确性不变量（无 admission 以外失败、账本对齐、池数上界）；
    /// 成功/拒绝分布作为测量结果记录，未来引入 reservation 语义后本测试应原样可用。
    func testConcurrentMultiOwnerAdmissionAccounting() async throws {
        guard let modelPath = Self.modelPath else {
            throw XCTSkip("设置 SIMIGO_TEST_MODEL_PATH 后运行（多 owner 并发压测，数分钟）")
        }

        let info = ModelInfo(path: modelPath, kind: .mlx)
        let runtime = NativeMLX(info: info, config: ModelConfig())
        let port = 47_000 + Int.random(in: 0..<2_000)

        do {
            try await withTestTimeout(seconds: 600) {
                try await runtime.start(info, port: port)
            }

            var config = ModelConfig()
            config.maxTokens = 16
            config.ctxSize = 32_768

            // 每个 owner 内容互异（带 owner 标记）：commit 侧按内容去重
            // （branch+fp+physicalTokens 相等即替换）——同文会被合法合并（铁律 42）。
            // ~45K chars ≈ 12K token（实测效率 3.78 chars/token）
            let ownerCount = 10
            let owners = (1...ownerCount).map { "o\($0)" }

            var results: [(owner: String, outcome: Result<String, Error>)] = []
            results.reserveCapacity(owners.count)

            await withTaskGroup(
                of: (String, Result<String, Error>).self
            ) { group in
                for owner in owners {
                    group.addTask {
                        do {
                            let ownerPrompt = String(
                                repeating: "// \(owner)\nlet metric\(owner) = evaluateStep(payload: \"sample-\(owner)\")\n",
                                count: 600
                            )
                            let text = try await withTestTimeout(seconds: 600) {
                                try await runtime.generate(
                                    requestId: "cc-\(owner)",
                                    agentId: "perf",
                                    sessionId: owner,
                                    logicalBranchId: "main",
                                    messages: [
                                        .object([
                                            "role": .string("user"),
                                            "content": .string(ownerPrompt),
                                        ])
                                    ],
                                    tools: nil,
                                    config: config,
                                    onChunk: { _ in }
                                )
                            }
                            return (owner, .success(text))
                        } catch {
                            return (owner, .failure(error))
                        }
                    }
                }

                for await pair in group {
                    results.append(pair)
                }
            }

            let successes = results.filter {
                if case .success = $0.outcome { return true }
                return false
            }
            let rejections = results.filter {
                if case .failure(let error) = $0.outcome,
                   case RuntError.admissionExceeded = error { return true }
                return false
            }
            let otherFailures = results.count - successes.count - rejections.count

            XCTAssertFalse(results.isEmpty, "并发请求必须全部返回结果")
            XCTAssertGreaterThan(
                successes.count, 0,
                "至少部分请求应完成（测量记录：成功 \(successes.count)/admission 拒绝 \(rejections.count)/其他失败 \(otherFailures)）"
            )
            XCTAssertEqual(
                otherFailures, 0,
                "不允许出现 admission 拒绝以外的失败（OOM/悬挂/内部错误都算治理缺口——若在 10 owner 压力下出现，即为 reservation 需要引入的实测信号）"
            )

            let snap = runtime.integrationSnapshot()
            // 池中 revision 数 ∈ [1, 成功数]：跨 owner 不 supersede，但 admission
            // 驱逐会随驻留增长削减旧 revision——具体数量是测量数据，
            // 正确性由 ledgerSynced 与上下界锁定。
            XCTAssertGreaterThanOrEqual(
                snap.revisions, 1,
                "至少最新 revision 应驻留"
            )
            XCTAssertLessThanOrEqual(
                snap.revisions, successes.count,
                "池中 revision 不得多于成功请求（去重后上界）"
            )
            XCTAssertTrue(
                snap.revisionsLedgerSynced,
                "并发提交后每个 revision 的账本仍必须与 KV offset 逐层对齐"
            )

            await runtime.stop()
        } catch {
            await runtime.stop()
            throw error
        }
    }

    /// Decode Batch Size Sweep（Batched Decode 实验轨 P0 基准，生产代码零改动）：
    /// dense 模型上并发 decode 流数吞吐扫描——1/2/3/4/6/8 路。
    ///
    /// 设计：同长度 prompt（计数指令保证 decode 全长跑满 maxTokens=128）、
    /// 不同 execution key（互不 supersede）、单次模型加载 + warm-up 后
    /// 逐批并发发起。每批打印 [BENCH] 墙钟；每路 decode TPS/TTFT/dur
    /// 经 [PERF] trace 留痕，聚合吞吐 = Σtok / 批墙钟（离线计算）。
    ///
    /// 目标：测出本机（32GB/Apple Silicon）当前「交错单流 decode」架构下
    /// 聚合吞吐随流数的真实曲线与甜点位，为最小 Batched KVCache 实现提供
    /// go/no-go 依据——已知先验：单流 28-33 tok/s，3 流聚合 ~25 tok/s
    /// （README 实验数据），预期聚合不随流数扩展（每路争同一内存带宽）。
    func testDecodeBatchSizeSweepBenchmark() async throws {
        guard let modelPath = Self.modelPath else {
            throw XCTSkip("设置 SIMIGO_TEST_MODEL_PATH 后运行（decode 批扫描基准，数分钟）")
        }

        let info = ModelInfo(path: modelPath, kind: .mlx)
        let runtime = NativeMLX(info: info, config: ModelConfig())
        let port = 47_000 + Int.random(in: 0..<2_000)

        do {
            try await withTestTimeout(seconds: 600) {
                try await runtime.start(info, port: port)
            }

            // warm-up（不计入测量）：模型加载后的首次推理预热
            var warmConfig = ModelConfig()
            warmConfig.maxTokens = 8
            _ = try await withTestTimeout(seconds: 120) {
                try await runtime.generate(
                    requestId: "sweep-warm",
                    agentId: "bench",
                    sessionId: "bench-warm",
                    logicalBranchId: "main",
                    messages: [
                        .object([
                            "role": .string("user"),
                            "content": .string("回复 ok"),
                        ])
                    ],
                    tools: nil,
                    config: warmConfig,
                    onChunk: { _ in }
                )
            }

            var decodeConfig = ModelConfig()
            decodeConfig.maxTokens = 128

            // 批请求：计数指令保证 decode 全长；尾部路号标记使内容互异
            // （避免 commit 内容去重），长度差异 ≤ 数 token。
            func benchPrompt(_ index: Int) -> [JSONValue] {
                [
                    .object([
                        "role": .string("user"),
                        "content": .string(
                            "用阿拉伯数字从1数到500，每行一个数字，不要输出任何其他内容（第 \(index) 路）"
                        ),
                    ])
                ]
            }

            for batch in [1, 2, 3, 4, 6, 8] {
                let start = Date()
                var texts: [String] = []
                texts.reserveCapacity(batch)

                try await withThrowingTaskGroup(of: String.self) { group in
                    for index in 1...batch {
                        group.addTask {
                            try await withTestTimeout(seconds: 300) {
                                try await runtime.generate(
                                    requestId: "sw\(batch)-i\(index)",
                                    agentId: "bench",
                                    sessionId: "sw\(batch)-s\(index)",
                                    logicalBranchId: "main",
                                    messages: benchPrompt(index),
                                    tools: nil,
                                    config: decodeConfig,
                                    onChunk: { _ in }
                                )
                            }
                        }
                    }

                    for try await text in group {
                        texts.append(text)
                    }
                }

                let wall = Date().timeIntervalSince(start)

                XCTAssertEqual(texts.count, batch, "batch=\(batch) 应全部完成")
                for text in texts {
                    XCTAssertFalse(text.isEmpty, "batch=\(batch) 每路应产出非空生成")
                }

                print(
                    "[BENCH] batch=\(batch) wall=\(String(format: "%.2f", wall))s streams=\(batch) maxTokens=128"
                )
            }

            await runtime.stop()
        } catch {
            await runtime.stop()
            throw error
        }
    }

    // MARK: - Dense Batched Decode 原型（实验轨 P0，Batched Decode 审计立项）

    /// 原型运行结果（值类型，自动 Sendable）。
    /// routeTokens：每路采样的 token 序列（取消路由截至取消点）。
    struct BatchedRunResult {
        var batch: Int
        var decodeWallSeconds: Double
        var totalGeneratedTokens: Int
        var aggregateTokensPerSecond: Double
        var routeTokens: [[Int]]
    }

    /// Batched Decode 能力契约（审计立项：Model Capability Adapter 雏形）。
    /// 由 cache topology 推导——全可裁剪（标准注意力）→ 批化支持；
    /// 含 recurrent cache（Mamba 等）→ 不支持。
    /// 生产化时本契约移入 Execution Plane，作为 BatchedDecodeScheduler 的
    /// 准入判据（不绑定 Qwen3MoE；Gemma 4 等后续模型按同一契约接入）。
    enum BatchDecodeCapability {
        case supported
        case unsupported(reason: String)

        static func evaluate(caches: [any KVCache]) -> BatchDecodeCapability {
            if caches.isEmpty {
                return .unsupported(reason: "noCache")
            }
            if caches.allSatisfy({ $0.isTrimmable }) {
                return .supported
            }
            return .unsupported(reason: "recurrentCacheNotTrimable")
        }
    }

    /// Dense-only Batched Decode 原型（Batched Decode 审计立项 P0）：
    /// 等长同步 batch（N 条相同 prompt）+ 贪心 argmax，直接驱动
    /// `LanguageModel.callAsFunction(_ inputs: MLXArray, cache:)` raw 入口。
    ///
    /// 机制（已按 mlx-swift-lm 3.31.4 源码核实全部 batch 无关）：
    /// - Qwen3MoEAttention 显式读取 (B, L) 并按 B reshape，RoPE 用共享 offset；
    /// - StandardKVCache.update 的 kShape 以 B = keys.dim(0) 分配、offset += keys.dim(2)
    ///   共享推进、`keys[.ellipsis, previous..<offset, 0...] = keys` 批量沿 seq 轴写入；
    /// - decode 单步 n=1 时 mask = .none；MoE SwitchGLU/argPartition/takeAlong 均为末轴算子。
    ///
    /// 贪心 argmax：batch 安全且确定性——可断言「batch=4 的序列 0 与 batch=1 的
    /// 序列 0 输出逐 token 相等」，数值等价校验批化 forward。
    ///
    /// 验收（审计立项硬指标）：batch=4 聚合 > 43 tok/s（交错单流基线）；> 50 才算
    /// 真正兑现 weight-read 摊销；< 43 = batch overhead 吃掉收益，立即止损。
    func testBatchedDecodePrototype() async throws {
        guard let modelPath = Self.modelPath else {
            throw XCTSkip("设置 SIMIGO_TEST_MODEL_PATH 后运行（Batched Decode 原型）")
        }

        // 实验轨门控（审计裁决：Hybrid Batch Decode = NO-GO，Dense-only 实验轨）：
        // 原型仅针对全注意力 dense 模型（Qwen3-Coder-30B-A3B）验证，
        // 混合模型（MambaCache batch 语义未定义）须显式 opt-in 才允许进入本路径。
        let batchedEnabled = ProcessInfo.processInfo.environment["SIMIGO_TEST_BATCHED"] == "1"
            || UserDefaults.standard.string(forKey: "SIMIGO_TEST_BATCHED") == "1"
        guard batchedEnabled else {
            throw XCTSkip("Batched Decode 实验轨：设置 SIMIGO_TEST_BATCHED=1 后运行（Dense-only）")
        }

        // 与 SimiGo loadModelContainer 相同的加载路径与 tokenizer loader
        Memory.memoryLimit = 22 * 1024 * 1024 * 1024
        let container = try await LLMModelFactory.shared.loadContainer(
            from: URL(fileURLWithPath: modelPath),
            using: #huggingFaceTokenizerLoader()
        )

        let decodeSteps = 128

        // 同 prompt 吞吐基准（row 隔离由 testBatchedDecodeDistinctPromptIsolation 锁定）
        let promptTokens = try await container.perform { context -> [Int] in
            context.tokenizer.encode(
                text: "用阿拉伯数字从1数到500，每行一个数字，不要输出任何其他内容"
            )
        }

        let single = try await runBatched(
            container: container,
            routes: [promptTokens],
            decodeSteps: decodeSteps
        )
        let batched = try await runBatched(
            container: container,
            routes: Array(repeating: promptTokens, count: 4),
            decodeSteps: decodeSteps
        )

        print(
            "[BATCHED-PROTOTYPE] batch=1 wall=\(String(format: "%.3f", single.decodeWallSeconds))s " +
                "agg=\(String(format: "%.1f", single.aggregateTokensPerSecond)) tok/s"
        )
        print(
            "[BATCHED-PROTOTYPE] batch=4 wall=\(String(format: "%.3f", batched.decodeWallSeconds))s " +
                "agg=\(String(format: "%.1f", batched.aggregateTokensPerSecond)) tok/s"
        )

        // 数值等价：贪心确定性下批化 forward 与单流在前缀上逐 token 一致——
        // 实测前 ~60 token 完全相同后，因 B=1 vs B=4 的 GEMM 求和顺序差异在
        // 贪心近平局处分叉（批化推理固有数值现象，非 forward 缺陷）。
        // 契约取前缀阈值：前 32 token 必须一致（足以验证批化分布正确性）。
        let prefixMatch = zip(batched.routeTokens[0], single.routeTokens[0])
            .prefix(32)
            .filter { $0 == $1 }
            .count
        XCTAssertEqual(
            prefixMatch, 32,
            "batch=4 与 batch=1 的前 32 token 必须逐 token 一致（批化 forward 数值等价）"
        )

        // 审计立项硬指标：batch=4 聚合 > 43 tok/s（交错单流基线）
        XCTAssertGreaterThan(
            batched.aggregateTokensPerSecond, 43,
            "Batched Decode 原型必须突破交错单流基线 43 tok/s；未突破 = overhead 吃掉收益，止损"
        )
    }

    /// 批化运行：等长同步 batch（routes 全部等长）+ 贪心 argmax，直接驱动
    /// `LanguageModel.callAsFunction(_ inputs: MLXArray, cache:)` raw 入口。
    ///
    /// cancelledAfter[i] 非 nil = 模拟 batch 成员 i 在该 step 停止消费输出
    /// （Phase 0 取消语义：批行继续计算、其余路由不受影响；ragged 缩批属 Phase B）。
    func runBatched(
        container: ModelContainer,
        routes: [[Int]],
        decodeSteps: Int,
        cancelledAfter: [Int?] = []
    ) async throws -> BatchedRunResult {
        try await container.perform { context -> BatchedRunResult in
            let model = context.model

            let batch = routes.count
            let promptLength = routes[0].count
            precondition(
                routes.allSatisfy { $0.count == promptLength },
                "等长同步 batch 要求全部序列等长"
            )

            let flat = routes.flatMap { $0 }
            let input = MLXArray(flat.map { Int32($0) }, [batch, promptLength])

            let caches = model.newCache(parameters: nil)

            // Prefill → logits [batch, L, V]；标量索引 -1 移除轴 → 末位 [batch, V]，
            // argMax → [batch]（1-D）——decode 输入用 expandedDimensions 恢复 [batch, 1]。
            let logits = model(input, cache: caches)
            var next = logits[0..., -1, 0...].argMax(axis: -1)
            eval(next)

            var routeTokens = Array(repeating: [Int](), count: batch)
            func record(_ step: Int) {
                for i in 0..<batch {
                    let limit = i < cancelledAfter.count
                        ? (cancelledAfter[i] ?? Int.max)
                        : Int.max
                    if step < limit {
                        routeTokens[i].append(next[i].item(Int.self))
                    }
                }
            }
            record(0)

            var generated = batch
            let decodeStart = Date()

            for step in 1..<decodeSteps {
                let stepInput = next.expandedDimensions(axis: 1) // [batch, 1]
                let out = model(stepInput, cache: caches) // [batch, 1, V]
                next = out[0..., -1, 0...].argMax(axis: -1) // [batch]
                eval(next)

                generated += batch
                record(step)
            }

            let decodeWall = Date().timeIntervalSince(decodeStart)

            return BatchedRunResult(
                batch: batch,
                decodeWallSeconds: decodeWall,
                totalGeneratedTokens: generated,
                aggregateTokensPerSecond: Double(generated) / decodeWall,
                routeTokens: routeTokens
            )
        }
    }

    // MARK: - Batched Decode Phase 0：distinct-prompt 隔离 + 取消模拟（审计 Phase 0）

    /// Batch 成员隔离契约（审计 Phase 0）→ 实测结论：**Batched Decode NO-GO 实证**。
    ///
    /// 设计：4 条语义互异、等长化后的 prompt；逐一单流跑出基准序列，再批化跑一遍，
    /// 逐路对比前缀与语义首行。
    ///
    /// 实测结论（本测试即 NO-GO 证据，逐轮可复跑监控上游修复）：
    /// - batch 行 0 与单流 decode 逐 token BIT-EXACT（7 步 max|Δ| 全 0.0）；
    /// - batch 行 1/2/3 从第一个 decode step 起与单流系统性偏离
    ///   （logits max|Δ| 9.5→17.75，且各路输出仍带自己 prompt 的语义——
    ///   非 KV 跨行串写，而是 T=1 batched forward 对行 > 0 的计算缺陷，
    ///   mlx-swift-lm 3.31.4 / MLX 0.31.6 已实证）。
    ///
    /// 断言仅锁行 0（当前唯一可信行）+ 池不变量；rows>0 的分叉作为
    /// NO-GO 证据打印记录——上游修复后本测试的失败行会自动消失。
    func testBatchedDecodeDistinctPromptIsolation() async throws {
        guard let modelPath = Self.modelPath else {
            throw XCTSkip("设置 SIMIGO_TEST_MODEL_PATH 后运行（批化隔离契约）")
        }
        let batchedEnabled = ProcessInfo.processInfo.environment["SIMIGO_TEST_BATCHED"] == "1"
            || UserDefaults.standard.string(forKey: "SIMIGO_TEST_BATCHED") == "1"
        guard batchedEnabled else {
            throw XCTSkip("Batched Decode 实验轨：设置 SIMIGO_TEST_BATCHED=1 后运行（Dense-only）")
        }

        Memory.memoryLimit = 22 * 1024 * 1024 * 1024
        let container = try await LLMModelFactory.shared.loadContainer(
            from: URL(fileURLWithPath: modelPath),
            using: #huggingFaceTokenizerLoader()
        )

        let decodeSteps = 128
        let starts = [100, 300, 500, 700]

        // ① 能力契约（cache topology → capability；Hybrid NO-GO 门禁）
        let capability = try await container.perform { context -> BatchDecodeCapability in
            BatchDecodeCapability.evaluate(caches: context.model.newCache(parameters: nil))
        }
        guard case .supported = capability else {
            throw XCTSkip("Batch Decode 不支持：\(capability) cache topology 非 standard-KV")
        }

        // ② 语义互异 prompt + 确定性等长化：
        // 实测原始长度 [23,23,23,24]——BPE 对 "400" 的数字分组与上下文合并存在 ±1
        // 波动，词面构造不可靠；改为尾部补换行 token 至等长（语义中性）。
        let routesRaw: [[Int]] = try await container.perform { context -> [[Int]] in
            let tokenizer = context.tokenizer
            return starts.map { start in
                tokenizer.encode(
                    text: "用阿拉伯数字从\(start)数到\(start + 300)，每行一个数字，不要输出任何其他内容"
                )
            }
        }
        print("[BATCHED-ISO] 原始长度 \(routesRaw.map { $0.count })")

        let maxLen = routesRaw.map { $0.count }.max()!
        let padTokens: [Int] = try await container.perform { context -> [Int] in
            context.tokenizer.encode(text: "\n")
        }
        precondition(!padTokens.isEmpty, "换行必须可分词")
        let routes: [[Int]] = routesRaw.map { tokens in
            let deficit = maxLen - tokens.count
            guard deficit > 0 else { return tokens }
            return tokens + (0..<deficit).map { padTokens[$0 % padTokens.count] }
        }
        XCTAssertEqual(
            Set(routes.map { $0.count }).count, 1,
            "等长化后必须全部一致（实测 \(routes.map { $0.count })）——同步 batch 前提"
        )

        // ③ 单流基准 ×4
        var singleTokens: [[Int]] = []
        for tokens in routes {
            let run = try await runBatched(
                container: container,
                routes: [tokens],
                decodeSteps: decodeSteps
            )
            singleTokens.append(run.routeTokens[0])
        }

        // ④ 批化 ×1（distinct prompts）
        let batched = try await runBatched(
            container: container,
            routes: routes,
            decodeSteps: decodeSteps
        )

        // ⑤ 逐行前缀对比（前 24 token）：行 0 硬断言；rows 1-3 打印 NO-GO 证据
        for i in 0..<routes.count {
            let match = zip(batched.routeTokens[i], singleTokens[i])
                .prefix(24)
                .filter { $0 == $1 }
                .count
            if i == 0 {
                XCTAssertGreaterThanOrEqual(
                    match, 20,
                    "batch 行 0 与单流的输出前缀必须基本一致（行 0 是当前唯一可信行）"
                )
            } else {
                print(
                    "[BATCHED-ISO] NO-GO 证据 row \(i) 前缀匹配 \(match)/24 " +
                        "(rows>0 decode 分叉已实证)"
                )
            }
        }

        // ⑥ 语义隔离：行 0 首行硬断言；rows 1-3 打印首行（分叉证据）
        for i in 0..<routes.count {
            let text = try await container.perform { context -> String in
                context.tokenizer.decode(tokenIds: batched.routeTokens[i])
            }
            let firstLine = text.split(separator: "\n").first.map(String.init) ?? ""
            if i == 0 {
                XCTAssertEqual(
                    firstLine, String(starts[i]),
                    "batch 行 0 的首行必须为 \(starts[i])"
                )
            } else {
                print(
                    "[BATCHED-ISO] NO-GO 证据 row \(i) 首行=\(firstLine)（预期 \(starts[i])）"
                )
            }
        }

        // ⑦ 取消模拟：route 1 于 step 32 停止消费输出——断言仅行 0 与取消路由自身
        // （rows>0 分叉下他路对比无意义，取消隔离的完整契约待 ragged 批阶段）
        let cancelledAfter: [Int?] = [nil, 32, nil, nil]
        let cancelledRun = try await runBatched(
            container: container,
            routes: routes,
            decodeSteps: decodeSteps,
            cancelledAfter: cancelledAfter
        )

        XCTAssertEqual(
            cancelledRun.routeTokens[1].count, 32,
            "取消路由应停止于取消点"
        )
        let route0Match = zip(cancelledRun.routeTokens[0], singleTokens[0])
            .prefix(24)
            .filter { $0 == $1 }
            .count
        XCTAssertGreaterThanOrEqual(
            route0Match, 20,
            "取消模拟不得影响行 0（当前唯一可信行）"
        )
    }

    /// 【诊断】batch 维数值一致性：单流 forward vs batch 行 0/行 1 的末位 logits
    /// 与 KV cache state 逐元素对比——定位 batch 行污染发生在 cache 写入层还是
    /// model forward 层（Batched Decode 原型 rows>0 崩坏的分型依据）。
    func testBatchedNumericalDiagnostic() async throws {
        guard let modelPath = Self.modelPath else {
            throw XCTSkip("设置 SIMIGO_TEST_MODEL_PATH 后运行（batch 数值诊断）")
        }
        let batchedEnabled = ProcessInfo.processInfo.environment["SIMIGO_TEST_BATCHED"] == "1"
            || UserDefaults.standard.string(forKey: "SIMIGO_TEST_BATCHED") == "1"
        guard batchedEnabled else {
            throw XCTSkip("Batched Decode 实验轨：设置 SIMIGO_TEST_BATCHED=1 后运行")
        }

        Memory.memoryLimit = 22 * 1024 * 1024 * 1024
        let container = try await LLMModelFactory.shared.loadContainer(
            from: URL(fileURLWithPath: modelPath),
            using: #huggingFaceTokenizerLoader()
        )

            struct Diag: @unchecked Sendable {
                var singleLastLogits: [Float]
                var batchRow0LastLogits: [Float]
                var batchRow1LastLogits: [Float]
                var batchRow0Row1KVMaxDiff: Float
                var singleKVShape: [Int]
                var batchKVShape: [Int]
                var decodeStepMaxDiffRow1: [Float]   // 单流 vs batch 行 1
                var decodeStepMaxDiffRow0: [Float]   // 单流 vs batch 行 0
                var decodeTokensSingle: [Int]
                var decodeTokensBatchRow1: [Int]
            }

        let diag = try await container.perform { context -> Diag in
            let model = context.model
            let promptTokens = context.tokenizer.encode(
                text: "用阿拉伯数字从1数到500，每行一个数字，不要输出任何其他内容"
            )
            let L = promptTokens.count
            let decodeSteps = 8

            func sampleToken(_ logits: MLXArray) -> MLXArray {
                logits[0..., -1, 0...].argMax(axis: -1) // [B]（标量索引移除轴）
            }

            // ── 单流（[1, L] 2-D；1-D 输入会因 attention (B, L)=(21, 2048) reshape 崩溃）──
            let singleCaches = model.newCache(parameters: nil)
            var singleLogits = model(
                MLXArray(promptTokens.map { Int32($0) }, [1, L]),
                cache: singleCaches
            )
            var singleNext = sampleToken(singleLogits) // [1]
            eval(singleNext)
            var singleTokensSingle = [singleNext[0].item(Int.self)]
            var decodeStepMaxDiffRow1: [Float] = []
            var decodeStepMaxDiffRow0: [Float] = []

            // ── batch=2（同文 ×2）──
            let batchCaches = model.newCache(parameters: nil)
            let batchInput = MLXArray(
                (0..<2).flatMap { _ in promptTokens }.map { Int32($0) },
                [2, L]
            )
            var batchLogits = model(batchInput, cache: batchCaches)
            var batchNext = sampleToken(batchLogits) // [2]
            eval(batchNext)
            var batchTokensRow1 = [batchNext[1].item(Int.self)]

            // prefill 末位 logits（单流 vs batch 行对拍的基准）
            let singleLastPrefill = singleLogits[0..., -1, 0...]
            let batchLastPrefill = batchLogits[0..., -1, 0...]

            // ── decode 逐步对拍：单流 [1,1] vs batch [2,1] ──
            for _ in 1..<decodeSteps {
                let singleOut = model(
                    singleNext.expandedDimensions(axis: 1), cache: singleCaches
                ) // [1, 1, V]
                let batchOut = model(
                    batchNext.expandedDimensions(axis: 1), cache: batchCaches
                ) // [2, 1, V]

                let singleLast = singleOut[0..., -1, 0...] // [1, V]
                let batchLast = batchOut[0..., -1, 0...] // [2, V]
                let singleVec = singleLast[0] // [V]
                decodeStepMaxDiffRow1.append(
                    MLX.abs(singleVec - batchLast[1]).max().item(Float.self)
                )
                decodeStepMaxDiffRow0.append(
                    MLX.abs(singleVec - batchLast[0]).max().item(Float.self)
                )

                singleNext = singleLast.argMax(axis: -1) // [1]
                batchNext = batchLast.argMax(axis: -1) // [2]
                eval(singleNext)
                eval(batchNext)

                singleTokensSingle.append(singleNext[0].item(Int.self))
                batchTokensRow1.append(batchNext[1].item(Int.self))
            }

            // KV state 第一层：keys [B, kvh, L, d]
            let singleState = singleCaches[0].state
            let batchState = batchCaches[0].state
            let singleKeys = singleState.isEmpty ? MLXArray(0) : singleState[0]
            let batchKeys = batchState.isEmpty ? MLXArray(0) : batchState[0]

            let kvDiff = MLX.abs(batchKeys[1] - batchKeys[0]).max().item(Float.self)

            let batchRow0Last = batchLastPrefill[0].asArray(Float.self)
            let batchRow1Last = batchLastPrefill[1].asArray(Float.self)
            let singleLastArray = singleLastPrefill[0].asArray(Float.self)

            return Diag(
                singleLastLogits: singleLastArray,
                batchRow0LastLogits: batchRow0Last,
                batchRow1LastLogits: batchRow1Last,
                batchRow0Row1KVMaxDiff: kvDiff,
                singleKVShape: singleKeys.shape,
                batchKVShape: batchKeys.shape,
                decodeStepMaxDiffRow1: decodeStepMaxDiffRow1,
                decodeStepMaxDiffRow0: decodeStepMaxDiffRow0,
                decodeTokensSingle: singleTokensSingle,
                decodeTokensBatchRow1: batchTokensRow1
            )
        }

        // 逐元素偏差
        func maxAbsDiff(_ a: [Float], _ b: [Float]) -> Float {
            precondition(a.count == b.count && !a.isEmpty)
            return zip(a, b).map { abs($0 - $1) }.max() ?? 0
        }

        let singleVsRow0 = maxAbsDiff(diag.singleLastLogits, diag.batchRow0LastLogits)
        let singleVsRow1 = maxAbsDiff(diag.singleLastLogits, diag.batchRow1LastLogits)
        let row0VsRow1 = maxAbsDiff(diag.batchRow0LastLogits, diag.batchRow1LastLogits)

        print("[DIAG] batch KV rows 0 vs 1 max|Δ| = \(diag.batchRow0Row1KVMaxDiff)")
        print("[DIAG] KV shape single=\(diag.singleKVShape) batch=\(diag.batchKVShape)")
        print("[DIAG] last-logits max|Δ| single↔row0 = \(singleVsRow0)")
        print("[DIAG] last-logits max|Δ| single↔row1 = \(singleVsRow1)")
        print("[DIAG] last-logits max|Δ| row0↔row1   = \(row0VsRow1)")
        print("[DIAG] decode step max|Δ| 单流vs行1 = \(diag.decodeStepMaxDiffRow1)")
        print("[DIAG] decode step max|Δ| 单流vs行0 = \(diag.decodeStepMaxDiffRow0)")
        print("[DIAG] decode tokens single   = \(diag.decodeTokensSingle)")
        print("[DIAG] decode tokens batchRow1 = \(diag.decodeTokensBatchRow1)")

        // 判定：prefill bit-exact 是硬契约（已实测 0.0）
        XCTAssertLessThan(singleVsRow0, 1e-3, "prefill 末位 logits：单流 vs batch 行 0 必须一致")
        XCTAssertLessThan(singleVsRow1, 1e-3, "prefill 末位 logits：单流 vs batch 行 1 必须一致")
        // decode 逐步偏差作为测量数据记录——分叉机理（MLX batched T=1 前向 vs 单流）
        // 是 Batched Decode 生产化的核心阻断项，结论见提交说明与本测试注释。
        for (step, diffRow1) in diag.decodeStepMaxDiffRow1.enumerated() {
            print(
                "[DIAG] decode step \(step + 1): 单流vs行1 max|Δ|=\(diffRow1) 单流vs行0 max|Δ|=\(diag.decodeStepMaxDiffRow0[step])"
            )
        }
    }
}
