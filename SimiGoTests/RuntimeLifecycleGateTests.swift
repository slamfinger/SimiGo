import XCTest
@testable import SimiGo

/// RuntimeLifecycleGate（Tier 1：load/stop/suspend/resume 生命周期互斥）契约测试。
/// 审计 P2：补齐第二层测试强度——串行、等待者取消、授予下一个等待者、
/// 取消与授予竞争、以及数百轮压力下不悬挂不卡死。
final class RuntimeLifecycleGateTests: XCTestCase {
    // MARK: - 互斥语义

    func testSecondOperationWaitsUntilFirstReleases() async throws {
        let gate = RuntimeLifecycleGate()
        let aStarted = TestSignal()
        let releaseA = TestSignal()
        let bStarted = TestSignal()

        let taskA = Task {
            try await gate.withLock {
                await aStarted.fire()
                await releaseA.wait()
            }
        }

        await aStarted.wait()

        let taskB = Task {
            try await gate.withLock {
                await bStarted.fire()
            }
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        let bStartedEarly = await bStarted.fired
        XCTAssertFalse(bStartedEarly, "持有者未释放时第二个操作不得进入")

        await releaseA.fire()
        try await withTestTimeout(seconds: 5) {
            await bStarted.wait()
        }
        try await withTestTimeout(seconds: 5) { try await taskB.value }
        try await taskA.value
    }

    func testWithLockVoidSkipsOperationWhenCancelled() async throws {
        let gate = RuntimeLifecycleGate()
        let aStarted = TestSignal()
        let releaseA = TestSignal()

        let taskA = Task {
            await gate.withLockVoid {
                await aStarted.fire()
                await releaseA.wait()
            }
        }

        await aStarted.wait()

        let ran = TestSignal()
        let waiterTask = Task {
            await gate.withLockVoid {
                await ran.fire()
            }
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        waiterTask.cancel()
        try await withTestTimeout(seconds: 5) { await waiterTask.value }

        let ranAfterCancel = await ran.fired
        XCTAssertFalse(ranAfterCancel, "取消的 withLockVoid 不得执行操作体")

        await releaseA.fire()
        try await taskA.value

        // gate 仍然可用
        try await withTestTimeout(seconds: 5) {
            await gate.withLockVoid {}
        }
    }

    // MARK: - 等待者取消

    func testCancelledWaiterThrowsAndGateStaysUsable() async throws {
        let gate = RuntimeLifecycleGate()
        let aStarted = TestSignal()
        let releaseA = TestSignal()

        let taskA = Task {
            try await gate.withLock {
                await aStarted.fire()
                await releaseA.wait()
            }
        }

        await aStarted.wait()

        let waiterTask = Task {
            try await gate.withLock { "ran" }
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        waiterTask.cancel()

        do {
            _ = try await withTestTimeout(seconds: 5) { try await waiterTask.value }
            XCTFail("等待中的取消应抛 CancellationError")
        } catch is CancellationError {
            // 预期路径（withTestTimeout 传播原错误）
        } catch is TestTimeout {
            XCTFail("取消的等待者不得悬挂")
        } catch {
            XCTFail("意外错误: \(error)")
        }

        await releaseA.fire()
        try await taskA.value

        try await withTestTimeout(seconds: 5) {
            try await gate.withLock {}
        }
    }

    // MARK: - 竞争与压力

    /// 取消与授予竞争：waiter.cancel 与 holder.release 并发，
    /// 两种结局（取消 / 授予）都必须恰好发生其一，gate 不得卡 busy。
    func testCancelAndReleaseRaceKeepsGateUsable() async throws {
        try await withTestTimeout(seconds: 120) {
            for round in 0..<150 {
                let gate = RuntimeLifecycleGate()
                let started = TestSignal()
                let releaseHolder = TestSignal()

                let holder = Task {
                    try await gate.withLock {
                        await started.fire()
                        await releaseHolder.wait()
                    }
                }

                await started.wait()

                let waiter = Task {
                    try await gate.withLock { "ran" }
                }

                // 让 waiter 有机会入队（也可能尚未入队——两种路径都必须收敛）
                try await Task.sleep(nanoseconds: 30_000_000)
                waiter.cancel()
                await releaseHolder.fire()

                _ = try? await holder.value
                _ = try? await waiter.value

                // 探针：gate 不得卡在 busy
                try await gate.withLock {}
            }
        }
    }

    /// 数百轮随机取消：等待者全数收敛、互斥不被破坏、gate 最终可用。
    func testStressRandomCancellationRounds() async throws {
        try await withTestTimeout(seconds: 120) {
            let overlap = OverloadTracker()

            for round in 0..<150 {
                let gate = RuntimeLifecycleGate()
                let started = TestSignal()
                let releaseHolder = TestSignal()

                let holder = Task {
                    try await gate.withLock {
                        await overlap.enter()
                        await started.fire()
                        try? await Task.sleep(nanoseconds: 20_000_000)
                        await overlap.exit()
                        await releaseHolder.wait()
                    }
                }

                await started.wait()

                var waiters: [Task<String, Error>] = []
                for waiterIndex in 0..<3 {
                    let task = Task {
                        try await gate.withLock {
                            await overlap.enter()
                            try? await Task.sleep(nanoseconds: 5_000_000)
                            await overlap.exit()
                            return "w\(waiterIndex)"
                        }
                    }
                    waiters.append(task)
                }

                // 随机取消其中一个等待者（也可能全部 / 都不取消的时序发生）
                if round % 2 == 0 {
                    try await Task.sleep(nanoseconds: 10_000_000)
                    waiters[Int(round / 2) % 3].cancel()
                }

                await releaseHolder.fire()

                try await withTestTimeout(seconds: 10) {
                    try await holder.value
                    for waiter in waiters {
                        _ = try? await waiter.value
                    }
                }
            }

            let maxOverlap = await overlap.maxConcurrent
            XCTAssertEqual(maxOverlap, 1, "gate 内任何时刻至多一个操作体在执行（实测 \(maxOverlap)）")
        }
    }

    /// 互斥重叠观测器：enter/exit 跟踪并发深度。
    private actor OverloadTracker {
        private var current = 0
        private var peak = 0

        func enter() {
            current += 1
            peak = max(peak, current)
        }

        func exit() {
            current -= 1
        }

        var maxConcurrent: Int { peak }
    }
}
