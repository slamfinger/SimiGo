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
        XCTAssertEqual(snap.activeRequests, 0, "请求完成后 task 登记必须清空")
        XCTAssertEqual(snap.activeGenerations, 0)
        XCTAssertEqual(snap.generatingSessions, 0)

        // ② 竞态轮：generate 与 stop 并发——请求先进入生命周期，stop 再启动
        let raceTask = Task {
            try? await runtime.generate(
                requestId: "itest-race",
                agentId: "itest",
                sessionId: "s2",
                logicalBranchId: "main",
                messages: messages,
                tools: nil,
                config: config,
                onChunk: { _ in }
            )
        }

        try await Task.sleep(nanoseconds: 300_000_000) // 让请求完成注册并进入 gate

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

        // ④ 竞态请求必须在有限时间内收敛（不悬挂、无僵尸 task）
        _ = try await withTestTimeout(seconds: 60) {
            await raceTask.value
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
}
