import XCTest
@testable import SimiGo

/// 外审三轮 P1 候选（2026-09-19）：generate() 与 suspendIfIdle() 的生命周期
/// 竞态、挂起-恢复往返、checkpoint 异常路径回归。
///
/// 门控：`SIMIGO_LIFECYCLE_RACE=1`（需本机权重；`SIMIGO_FORK_MODEL` 指定
/// 模型路径，缺省 Cyber-Tiel 生产同款）——与 BranchForkTests 同约定，
/// 缺省 XCTSkip 不污染常规跑。
///
/// 测试缝隙：`RuntimeTuning.suspendIdleTimeoutOverrideSeconds`（默认 nil =
/// 生产语义不变）。置 0 后「任务空 ⇒ 可挂起」，挂起窗口可被确定性锤击；
/// 断言的不变量是 **generate 全程成功 + 终态一致**（若竞态真实存在，
/// generate 会以 notLoaded/model_execution_error 失败，测试即红）。
final class LifecycleRaceTests: XCTestCase {
    private static let defaultModelPath =
        "/Users/mr.simi/.cache/huggingface/hub/models--peculiar-ragdoll--Cyber-Tiel-Coder-35B-A3B-MLX-oQ4e"
        + "/snapshots/b867c9dac94e521b9cabc59038fc6bf4b2f18e81"

    /// 环境门控 + 模型路径（缺失即 skip，不污染常规测试跑）。
    private static func requireModel() throws -> String {
        guard ProcessInfo.processInfo.environment["SIMIGO_LIFECYCLE_RACE"] == "1" else {
            throw XCTSkip("生命周期竞态：需 SIMIGO_LIFECYCLE_RACE=1 且本机存在权重")
        }
        let path = ProcessInfo.processInfo.environment["SIMIGO_FORK_MODEL"]
            ?? defaultModelPath
        guard FileManager.default.fileExists(atPath: path + "/config.json") else {
            throw XCTSkip("模型不存在：\(path)")
        }
        return path
    }

    private static func greedyConfig() -> ModelConfig {
        var cfg = ModelConfig()
        cfg.temperature = 0
        cfg.maxTokens = 16
        cfg.disableThinking = true
        cfg.useMTP = false
        return cfg
    }

    @discardableResult
    private func gen(
        _ runtime: NativeMLX, _ tag: String, _ content: String
    ) async throws -> GenerationResult {
        let requestId = "race-\(tag)-\(UUID().uuidString.prefix(8).lowercased())"
        await RuntimeLifecycleCoordinator.shared.register(
            requestID: requestId, sessionID: "race")
        return try await runtime.generate(
            requestId: requestId,
            sessionId: "race",
            messages: [.object([
                "role": .string("user"),
                "content": .string(content),
            ])],
            tools: nil,
            config: Self.greedyConfig()
        ) { _ in }
    }

    // MARK: - headless 回归（无需权重）

    /// 未加载模型时 loadSessionCache 必须在触碰状态池之前拒绝，
    /// suspendIfIdle 对未运行实例返回 false——异常路径不留下半初始化状态。
    func testLoadSessionCacheWithoutModelDoesNotPoisonState() async throws {
        let runtime = NativeMLX(
            info: ModelInfo(path: "/nonexistent-model", kind: .mlx),
            config: ModelConfig())
        do {
            _ = try await runtime.loadSessionCache(
                sessionId: "nope",
                from: URL(fileURLWithPath: "/nonexistent-checkpoint-dir"))
            XCTFail("未加载模型时 loadSessionCache 应抛错")
        } catch RuntError.notLoaded {
            // 预期精确错误：notLoaded 守卫先行，状态池零触碰
            // （错误类型断言收紧，外审四轮 P2）
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
        XCTAssertFalse(runtime.isGenerating)
        let suspended = await runtime.suspendIfIdle()
        XCTAssertFalse(suspended, "未运行实例不可被挂起")
    }

    // MARK: - 生成 vs 挂起竞态（门控，需权重）

    func testGenerateSurvivesSuspendIfIdleHammeringAndResumeRoundtrip() async throws {
        let modelPath = try Self.requireModel()
        let runtime = NativeMLX(
            info: ModelInfo(path: modelPath, kind: .mlx),
            config: Self.greedyConfig())

        // 装载：公开面唯一入口 start()（含 HTTP server 绑定）。测试用
        // port 0（系统分配临时端口，不依赖固定端口），并在测试退出前
        // 可等待地恢复 InferenceNodeConfiguration 快照——异步 defer 的
        // 悬挂窗口问题（外审四轮 P2 采纳）。
        let configSnapshot = await MainActor.run {
            InferenceNodeConfiguration.shared.snapshot()
        }
        var configRestored = false
        func restoreConfig() async {
            guard !configRestored else { return }
            configRestored = true
            await MainActor.run {
                InferenceNodeConfiguration.configure(
                    bindHost: configSnapshot.bindHost,
                    advertisedHost: configSnapshot.advertisedHost,
                    port: configSnapshot.port,
                    bonjourEnabled: configSnapshot.bonjourEnabled)
            }
        }
        // 资源清理（外审五轮 P1 采纳）：start() 持有 ModelContainer/
        // HTTPServer/会话 KV——测试结束必须 stop() 释放，否则模型驻留
        // 污染后续测试。幂等；stop 非 throwing，不会掩盖原始测试错误。
        var runtimeStopped = false
        func stopRuntime() async {
            guard !runtimeStopped else { return }
            runtimeStopped = true
            await runtime.stop()
        }
        // 测试开关显式恢复（外审六轮 P2 采纳）：防止 DEBUG 静态配置在
        // 同进程后续测试中残留 0 值——与 stop/restore 同入统一清理路径。
        #if DEBUG
        var seamReset = false
        func resetTestSeam() {
            guard !seamReset else { return }
            seamReset = true
            RuntimeTuning.suspendIdleTimeoutOverrideSeconds = nil
        }
        #else
        func resetTestSeam() {}
        #endif

        // 竞态锤击：3 轮生成，每轮期间并行快打 suspendIfIdle。
        // 不变量：无论挂起在窗口内命中多少次，generate 必须成功完成。
        do {
            try await runtime.start(ModelInfo(path: modelPath, kind: .mlx), port: 0)

            // 预热：建立会话
            _ = try await gen(runtime, "warm", "只回复:OK")

            // 打开测试缝隙：任务空即可挂起（生产默认 nil 不受影响）
            RuntimeTuning.suspendIdleTimeoutOverrideSeconds = 0

            var suspendWins = 0
            for round in 1...3 {
                let hammer = Task {
                    var wins = 0
                    for _ in 0..<200 {
                        if await runtime.suspendIfIdle() { wins += 1 }
                        try? await Task.sleep(nanoseconds: 2_000_000)
                    }
                    return wins
                }
                let result = try await gen(
                    runtime, "r\(round)", "第\(round)轮:只回复收到")
                XCTAssertFalse(
                    result.text.isEmpty, "round\(round) 生成不应为空")
                suspendWins += try await hammer.value
            }

            // 终态一致性：运行中、容器在、可继续生成
            let after = try await gen(runtime, "final", "只回复:END")
            XCTAssertFalse(after.text.isEmpty)

            // 重复挂起/恢复往返（外审清单第 5 类）：挂起 → 自动恢复成功 →
            // 再挂起成功 → 已挂起再挂起必须 false（不重复释放）
            let s1 = await runtime.suspendIfIdle()
            XCTAssertTrue(s1, "任务空时应当可挂起")
            let resumed = try await gen(runtime, "resume", "只回复:BACK")
            XCTAssertFalse(resumed.text.isEmpty, "挂起后新请求应自动恢复并成功")
            let s2 = await runtime.suspendIfIdle()
            XCTAssertTrue(s2, "恢复后应可再次挂起")
            let s3 = await runtime.suspendIfIdle()
            XCTAssertFalse(s3, "已挂起实例重复挂起应返回 false，不重复释放")

            // 结果语义分层（外审四轮 P1 采纳）：
            // RACE_WINDOW_HIT        = 竞态窗口被真实覆盖且 generate 存活——完整验证
            // PROTECTION_PASS_NO_HIT = 保护不变量成立，但窗口未被覆盖——
            //   不得宣称已完成竞态验证，仅登记保护侧成立
            let outcome = suspendWins > 0 ? "RACE_WINDOW_HIT" : "PROTECTION_PASS_NO_HIT"
            print("[race] outcome=\(outcome) suspendWins=\(suspendWins) generate 全部存活")
        } catch {
            resetTestSeam()
            await stopRuntime()
            await restoreConfig()
            throw error
        }
        resetTestSeam()
        await stopRuntime()
        await restoreConfig()
    }
}
