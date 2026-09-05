import XCTest
@testable import SimiGo

/// SessionGenerationGate 并发正确性：同 Key 串行 / 跨 Key 并行 / shutdown drain 永不悬挂。
/// 审计结论（P0）：invariant 目前靠构造成立，必须由测试钉死，不得再叠加逻辑。
final class SessionGenerationGateTests: XCTestCase {
    struct GateTimeout: Error {}

    /// 有界等待包装：block 未在时限内完成即失败，防止测试自身悬挂拖死 CI。
    private func withTimeout<T: Sendable>(
        seconds: Double,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw GateTimeout()
            }

            guard let result = try await group.next() else {
                throw GateTimeout()
            }

            group.cancelAll()
            return result
        }
    }

    /// 跨并发上下文的握手信号：signal 记录状态（无等待者也不丢），wait 立即或挂起。
    private actor Signal {
        private var signaled = false
        private var continuation: CheckedContinuation<Void, Never>?

        func fire() {
            signaled = true
            continuation?.resume()
            continuation = nil
        }

        func wait() async {
            if signaled { return }
            await withCheckedContinuation { self.continuation = $0 }
        }

        var fired: Bool { signaled }
    }

    private func makeKey(branch: String) throws -> AgentExecutionKey {
        try AgentExecutionKey(agentId: "agent", sessionId: "session", logicalBranchId: branch)
    }

    // MARK: - Serialization Semantics

    func testSameKeySerializesWhileDifferentKeysRunInParallel() async throws {
        let gate = SessionGenerationGate()
        let branchA = try makeKey(branch: "b-a")
        let branchB = try makeKey(branch: "b-b")

        let aStarted = Signal()
        let releaseA = Signal()
        let bStarted = Signal()
        let releaseB = Signal()

        let taskA = Task {
            try await gate.withExclusive(branchA) {
                await aStarted.fire()
                await releaseA.wait()
            }
        }

        await aStarted.wait()

        // 同 Key 的 B 必须等 A 释放
        let taskB = Task {
            try await gate.withExclusive(branchA) {
                await bStarted.fire()
                await releaseB.wait()
            }
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        let bFiredEarly = await bStarted.fired
        XCTAssertFalse(bFiredEarly, "同 Key 第二个任务在持有者未释放时不应获得执行权")

        // 不同 Key 的 C 在 A 持锁期间照常并行
        try await gate.withExclusive(branchB) {}

        await releaseA.fire()
        try await taskA.value

        // A 释放后 B 获得执行权：等 B 真正开始运行（此时 B 仍在等 releaseB）
        try await withTimeout(seconds: 5) {
            await bStarted.wait()
        }
        let bFiredAfterRelease = await bStarted.fired
        XCTAssertTrue(bFiredAfterRelease, "前序任务释放后同 Key 等待者应被授予")

        await releaseB.fire()
        try await withTimeout(seconds: 5) { try await taskB.value }
    }

    // MARK: - Shutdown Semantics

    func testBeginShutdownRejectsNewAcquiresImmediately() async throws {
        let gate = SessionGenerationGate()
        await gate.beginShutdown()

        let key = try makeKey(branch: "b")

        do {
            try await gate.withExclusive(key) {}
            XCTFail("shutdown 后 acquire 必须被拒绝")
        } catch is CancellationError {
            // 预期路径
        } catch {
            XCTFail("应抛 CancellationError，实际: \(error)")
        }

        await gate.awaitDrain()
    }

    func testBeginShutdownCancelsWaitersButLetsInFlightFinish() async throws {
        let gate = SessionGenerationGate()
        let key = try makeKey(branch: "b")

        let aStarted = Signal()
        let releaseA = Signal()

        let taskA = Task {
            try await gate.withExclusive(key) {
                await aStarted.fire()
                await releaseA.wait()
            }
        }

        await aStarted.wait()

        // B 排队成为 waiter，shutdown 时必须被取消
        let taskB = Task {
            try await gate.withExclusive(key) {
                XCTFail("shutdown 已开始，waiter 不应再获得执行权")
            }
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        await gate.beginShutdown()

        do {
            try await taskB.value
            XCTFail("shutdown 期间 waiter 应抛 CancellationError")
        } catch is CancellationError {
            // 预期路径
        } catch {
            XCTFail("应抛 CancellationError，实际: \(error)")
        }

        // 在飞任务不被 shutdown 打断，完成后 drain 才收敛
        await releaseA.fire()
        try await taskA.value

        try await withTimeout(seconds: 5) {
            await gate.awaitDrain()
        }
    }

    // MARK: - Stress: generate / shutdown 交替 1000 轮

    /// 审计 P0 要求的压测：反复制造「任务已捕获 gate 但尚未进入 acquire」与
    /// 「in-flight + waiter 混合」两类窗口，验证 drain 永不悬挂、shutdown 后 acquire 全被拒。
    /// 超时 60s：正常应在数秒内完成，悬挂即失败。
    func testStressThousandRoundsOfAcquireAndShutdownNeverHangs() async throws {
        try await withTimeout(seconds: 60) {
            for iteration in 0..<1000 {
                let gate = SessionGenerationGate()
                let keys = try (0..<3).map { branch in
                    try AgentExecutionKey(
                        agentId: nil,
                        sessionId: "session-\(iteration)",
                        logicalBranchId: "branch-\(branch)"
                    )
                }

                let holders = keys.map { key in
                    Task {
                        try? await gate.withExclusive(key) {
                            // 偶数轮稍作停留：让部分任务真正进入 acquire / waiter 状态
                            if iteration % 2 == 0 {
                                try? await Task.sleep(nanoseconds: 1_000_000)
                            }
                        }
                    }
                }

                if iteration % 2 == 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000)
                }

                // 立即 shutdown：故意不等 holders 全部进入 gate，制造调度窗口
                await gate.beginShutdown()

                for holder in holders {
                    await holder.value
                }

                // drain 必须收敛（悬挂即超时失败）
                await gate.awaitDrain()

                // shutdown 后任何 acquire 都必须被拒绝
                for key in keys {
                    do {
                        try await gate.withExclusive(key) {}
                        XCTFail("iteration \(iteration): shutdown 后 acquire 未被拒绝")
                    } catch is CancellationError {
                        // 预期路径
                    } catch {
                        XCTFail("iteration \(iteration): 应抛 CancellationError，实际: \(error)")
                    }
                }
            }
        }
    }
}
