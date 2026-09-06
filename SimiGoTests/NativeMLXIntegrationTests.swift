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
}
