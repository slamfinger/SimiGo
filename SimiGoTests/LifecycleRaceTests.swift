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
        } catch {
            // 预期：notLoaded 守卫先行
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

        // 装载：公开面唯一入口 start()（含 HTTP server 绑定）。测试用独立
        // 端口 8765 并在 defer 里恢复 InferenceNodeConfiguration 快照，
        // 避免污染生产端口配置。
        let configSnapshot = await MainActor.run {
            InferenceNodeConfiguration.shared.snapshot()
        }
        defer {
            Task { @MainActor in
                InferenceNodeConfiguration.configure(
                    bindHost: configSnapshot.bindHost,
                    advertisedHost: configSnapshot.advertisedHost,
                    port: configSnapshot.port,
                    bonjourEnabled: configSnapshot.bonjourEnabled)
            }
        }
        try await runtime.start(ModelInfo(path: modelPath, kind: .mlx), port: 8765)

        // 预热：建立会话
        _ = try await gen(runtime, "warm", "只回复:OK")

        // 打开测试缝隙：任务空即可挂起（生产默认 nil 不受影响）
        RuntimeTuning.suspendIdleTimeoutOverrideSeconds = 0
        defer { RuntimeTuning.suspendIdleTimeoutOverrideSeconds = nil }

        // 竞态锤击：3 轮生成，每轮期间并行快打 suspendIfIdle。
        // 不变量：无论挂起在窗口内命中多少次，generate 必须成功完成。
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
        RuntimeTuning.suspendIdleTimeoutOverrideSeconds = 0
        let s1 = await runtime.suspendIfIdle()
        XCTAssertTrue(s1, "任务空时应当可挂起")
        let resumed = try await gen(runtime, "resume", "只回复:BACK")
        XCTAssertFalse(resumed.text.isEmpty, "挂起后新请求应自动恢复并成功")
        let s2 = await runtime.suspendIfIdle()
        XCTAssertTrue(s2, "恢复后应可再次挂起")
        let s3 = await runtime.suspendIfIdle()
        XCTAssertFalse(s3, "已挂起实例重复挂起应返回 false，不重复释放")

        if suspendWins == 0 {
            // 未击中窗口本身不算失败：窗口保护可能使挂起在生成期间
            // 永远不可 eligible——这正是被验证的不变量之一。
            print("[race] 3 轮未击中挂起窗口（合格：保护生效或样本未命中）")
        } else {
            print("[race] 击中挂起窗口 \(suspendWins) 次，generate 全部存活")
        }
    }
}
