import XCTest
@testable import SimiGo

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
    /// 已知缺口（审计第五轮观察项）：admission 检查位于 prefillScheduler.acquire 之前，
    /// 跨 execution key 完全并行——N 个并发请求各自读到同一份 resident 快照、各自
    /// 通过 admission，「预算」实际是单请求瞬时估算而非全局并发预算。
    ///
    /// 本测试把缺口变成可量化数据：5 个不同 session（互不 supersede）各 ~16K token
    /// 并发生成。单请求 projected ≈ 16K×128KB + 4GB ≈ 6GB < 12GB（各自应通过）；
    /// 并发总和 ≈ 5×16K×128KB + 4GB ≈ 14GB > 12GB（若 admission 具备全局预算语义
    /// 则应有请求被拒/驱逐）。同时 [PWAIT] 会实测 prefill 串行化排队时长。
    ///
    /// 断言只锁定正确性不变量（账本对齐、池与成功数一致、机器存活）；
    /// 「全部通过 admission」本身作为测量结果记录，不作为断言——
    /// 未来引入 reservation 语义后本测试应原样可用。
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
            // （branch+fp+physicalTokens 相等即替换）——若五者同文，池会合法地
            // 合并为 1 个 revision（铁律 42 全局计算共享池的设计行为，首轮实测验证）。
            // ~66K chars ≈ 17.6K token（实测效率 3.78 chars/token）
            let owners = ["sess-a", "sess-b", "sess-c", "sess-d", "sess-e"]

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
                                count: 890
                            )
                            let text = try await withTestTimeout(seconds: 600) {
                                try await runtime.generate(
                                    requestId: "cc-\(owner.suffix(1))",
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
                "不允许出现 admission 拒绝以外的失败（OOM/悬挂/内部错误都算治理缺口）"
            )

            let snap = runtime.integrationSnapshot()
            // 池中 revision 数 ∈ [1, 成功数]：跨 owner 不 supersede，但 admission
            // 驱逐会随驻留增长削减旧 revision（第 4-5 个请求预计触发）——
            // 具体数量是测量数据，正确性由 ledgerSynced 与下界锁定。
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
}
