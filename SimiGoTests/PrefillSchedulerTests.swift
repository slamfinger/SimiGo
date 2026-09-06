import XCTest
@testable import SimiGo

/// PrefillScheduler 契约测试（审计 P2）：全局单 prefill 槽位的
/// FIFO 排队、等待者取消跳过、cancelAll 全清、非持有者 release 无效、
/// 以及 release/cancel 竞争压力下不悬挂不双授予。
final class PrefillSchedulerTests: XCTestCase {
    // MARK: - 槽位与 FIFO

    func testHolderExcludesOthersAndReleasePromotesWaiter() async throws {
        let scheduler = PrefillScheduler()

        let first = await scheduler.acquire(requestId: "A")
        XCTAssertTrue(first.granted)

        let second = Task { await scheduler.acquire(requestId: "B") }
        try await Task.sleep(nanoseconds: 200_000_000) // 确保 B 已入队

        let snapWhileHeld = await scheduler.snapshot()
        XCTAssertEqual(snapWhileHeld.activeRequestId, "A")
        XCTAssertEqual(snapWhileHeld.queued, 1)

        await scheduler.release(requestId: "A")

        let bResult = try await withTestTimeout(seconds: 5) { await second.value }
        XCTAssertTrue(bResult.granted, "持有者释放后唯一等待者必须被授予")

        await scheduler.release(requestId: "B")
        let third = await scheduler.acquire(requestId: "C")
        XCTAssertTrue(third.granted)
        await scheduler.release(requestId: "C")

        let final = await scheduler.snapshot()
        XCTAssertNil(final.activeRequestId)
    }

    /// 审计指定场景：A 持有 → B 等待 → B 取消 → A 释放 → C 立即获得。
    /// B 必须永不获得；队列必须清空。
    func testCancelledWaiterIsSkippedAndNextAcquireIsFresh() async throws {
        let scheduler = PrefillScheduler()

        let first = await scheduler.acquire(requestId: "A")
        XCTAssertTrue(first.granted)

        let bTask = Task { await scheduler.acquire(requestId: "B") }
        try await Task.sleep(nanoseconds: 200_000_000)

        bTask.cancel()
        let bResult = try await withTestTimeout(seconds: 5) { await bTask.value }
        XCTAssertFalse(bResult.granted, "已取消的等待者必须返回 false")

        await scheduler.release(requestId: "A")

        let snapAfterRelease = await scheduler.snapshot()
        XCTAssertNil(snapAfterRelease.activeRequestId, "B 被取消后 A 释放不得把槽位交给已消失的等待者")
        XCTAssertEqual(snapAfterRelease.queued, 0)

        let c = await scheduler.acquire(requestId: "C")
        XCTAssertTrue(c.granted, "C 必须立即获得槽位")
        await scheduler.release(requestId: "C")
    }

    // MARK: - 边界

    func testReleaseByNonHolderIsNoOp() async throws {
        let scheduler = PrefillScheduler()

        let first = await scheduler.acquire(requestId: "A")
        XCTAssertTrue(first.granted)

        await scheduler.release(requestId: "bogus")

        let snap = await scheduler.snapshot()
        XCTAssertEqual(snap.activeRequestId, "A", "非持有者 release 不得清空槽位")
        XCTAssertEqual(snap.queued, 0)

        await scheduler.release(requestId: "A")
        let again = await scheduler.acquire(requestId: "B")
        XCTAssertTrue(again.granted)
        await scheduler.release(requestId: "B")
    }

    /// 审计指定场景：cancelAll 之后 active == nil、queued == 0、
    /// 所有等待者返回 false，且调度器可立即重新使用。
    func testCancelAllClearsEverythingAndSchedulerIsReusable() async throws {
        let scheduler = PrefillScheduler()

        let first = await scheduler.acquire(requestId: "A")
        XCTAssertTrue(first.granted)

        var waiters: [Task<(granted: Bool, waited: TimeInterval), Never>] = []
        for index in 0..<3 {
            waiters.append(Task { await scheduler.acquire(requestId: "W\(index)") })
        }
        try await Task.sleep(nanoseconds: 200_000_000)

        await scheduler.cancelAll()

        for (index, waiter) in waiters.enumerated() {
            let result = try await withTestTimeout(seconds: 5) { await waiter.value }
            XCTAssertFalse(result.granted, "W\(index) 必须被 cancelAll 拒绝")
        }

        let snap = await scheduler.snapshot()
        XCTAssertNil(snap.activeRequestId)
        XCTAssertEqual(snap.queued, 0)

        let fresh = await scheduler.acquire(requestId: "D")
        XCTAssertTrue(fresh.granted, "cancelAll 后调度器必须立即可用")
        await scheduler.release(requestId: "D")
    }

    // MARK: - 竞争压力

    /// release 与 cancel 竞争：任何等待者至多被授予一次（双授予会使两个
    /// 操作体并发执行），全部任务必须收敛，调度器最终归零可用。
    func testReleaseCancelRaceStress() async throws {
        try await withTestTimeout(seconds: 120) {
            let overlap = OverlapTracker()

            for round in 0..<150 {
                let scheduler = PrefillScheduler()

                let first = await scheduler.acquire(requestId: "holder")
                XCTAssertTrue(first.granted)

                var waiters: [Task<(granted: Bool, waited: TimeInterval), Never>] = []
                for index in 0..<3 {
                    let id = "w\(round)-\(index)"
                    let task = Task {
                        let result = await scheduler.acquire(requestId: id)
                        if result.granted {
                            await overlap.enter()
                            try? await Task.sleep(nanoseconds: 5_000_000)
                            await overlap.exit()
                            await scheduler.release(requestId: id)
                        }
                        return result
                    }
                    waiters.append(task)
                }

                try await Task.sleep(nanoseconds: 20_000_000)
                if round % 2 == 0 {
                    waiters[round % 3].cancel()
                }
                await scheduler.release(requestId: "holder")

                var grantedCount = 0
                for waiter in waiters {
                    let result = await waiter.value
                    if result.granted { grantedCount += 1 }
                }

                // grantedCount 无上限是合法结局：自归还的等待者会把槽位串行地
                // 传给下一个（FIFO 链式授予），真正的负载不变量是互斥重叠深度，
                // 由下方 overlap 断言承担。

                // 全部等待者收敛后，槽位与队列必须归零
                let snap = await scheduler.snapshot()
                XCTAssertNil(snap.activeRequestId, "round \(round): 压力轮结束后槽位必须归零")
                XCTAssertEqual(snap.queued, 0, "round \(round): 队列必须清空")
            }

            let maxOverlap = await overlap.maxConcurrent
            XCTAssertEqual(maxOverlap, 1, "prefill 操作体任何时刻至多一个（实测 \(maxOverlap)）")
        }
    }

    private actor OverlapTracker {
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
