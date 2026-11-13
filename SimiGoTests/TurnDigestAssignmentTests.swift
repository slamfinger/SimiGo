import XCTest
import SimiGoRuntimeContract

@testable import SimiGo

/// #187 的 App 层回归：走的是 `write()` 用的同一段代码（`recordDigestAndAssign`），
/// 不是测试自己拼一遍。
///
/// 契约层已经用真锁证明「撞 BUSY 时摘要与待办同生共死」；这里证的是另一头：
/// 归属判定失败之后，那一轮**已经在队列里**、重启后仍在，重放一次就补上。
/// 归属失败用注入口制造——`assignRoom` 与 `completeSession` 同一条规矩，
/// 只有测试会写它。
final class TurnDigestAssignmentTests: XCTestCase {
    private final class OneShotGate: @unchecked Sendable {
        private let lock = NSLock()
        private var consumed = false

        func consume() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !consumed else { return false }
            consumed = true
            return true
        }
    }

    private var previousHome: String?
    private var homeURL: URL!
    private var previousAssignRoom: (@Sendable (ESISDatabase, String, Int) throws -> Void)!

    override func setUpWithError() throws {
        previousHome = ProcessInfo.processInfo.environment["SIMIGO_HOME"]
        homeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("simigo-digest-assign-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        setenv("SIMIGO_HOME", homeURL.path, 1)
        previousAssignRoom = TurnDigestScheduler.assignRoom
    }

    override func tearDown() {
        TurnDigestScheduler.assignRoom = previousAssignRoom
        if let previousHome {
            setenv("SIMIGO_HOME", previousHome, 1)
        } else {
            unsetenv("SIMIGO_HOME")
        }
        try? FileManager.default.removeItem(at: homeURL)
        super.tearDown()
    }

    private func openDatabase() throws -> ESISDatabase {
        let db = try ESISDatabase(url: ManagedPaths.databaseURL, createIfNeeded: true)
        try db.runMigrations()
        return db
    }

    private func seedUndigestedTurn(session: String) throws {
        let db = try openDatabase()
        defer { db.close() }
        try db.recordExternalTurn(
            sessionID: session, provider: "local", requestID: "r1",
            userText: "问：这一轮进哪个房间", model: nil, createdAt: Date())
        try db.recordExternalResponse(
            sessionID: session, provider: "local", requestID: "r1",
            assistantText: "答：SimiGo HTTPServer", model: nil, createdAt: Date())
        try db.recordTurnIndex(sessionID: session, turnIndex: 1,
                               requestID: "r1", at: Date())
    }

    /// 归属失败 → 那一条待办已经在库里（不是日志里的安慰）→ 换个连接重放 → 补上。
    func testAssignmentFailureLeavesDurablePendingRowThenReplayFixesIt() throws {
        try seedUndigestedTurn(session: "s-assign")

        TurnDigestScheduler.assignRoom = { _, _, _ in
            throw NSError(domain: "test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "模拟锁竞争",
            ])
        }
        try TurnDigestScheduler.recordDigestAndAssign(
            sessionID: "s-assign", turnIndex: 1,
            digest: "这一轮讲了归属失败之后怎么恢复",
            keywords: ["SimiGo", "HTTPServer"])

        do {
            let db = try openDatabase()
            defer { db.close() }
            XCTAssertEqual(try db.count("turn_digests"), 1, "摘要已经落了")
            XCTAssertEqual(try db.count("space_turns"), 0, "归属没写上")
            XCTAssertEqual(try db.pendingSpaceAssignmentRetries(), 1,
                           "失败要在队列里留下一条，重启也在")
            XCTAssertEqual(try db.turnGapCounts().rooms, 1,
                           "第五项缺口能看见这一轮")
            let status = try db.spaceAssignmentRetryStatus()
            XCTAssertNotNil(status.lastError, "失败原因也留了")
        }

        // 「重启」：换一个连接、走真实实现，重放一次。
        TurnDigestScheduler.assignRoom = previousAssignRoom
        let db = try openDatabase()
        defer { db.close() }
        let report = try db.retryPendingSpaceAssignments(
            now: Date().addingTimeInterval(120))
        XCTAssertEqual(report.succeeded, 1)
        XCTAssertEqual(try db.pendingSpaceAssignmentRetries(), 0)
        XCTAssertEqual(try db.turnGapCounts().rooms, 0)
    }

    /// 监视器不是「定义了但没入口」：一条已到期的欠账，在**不调用**任何重放
    /// 的情况下，由监视器自己判上。间隔压到 0.2 秒测，跑完立刻停——它是进程级的，
    /// 留着会带着出厂节奏接着打真实库。
    func testDuePendingRowIsAssignedByMonitorAlone() throws {
        let db = try openDatabase()
        defer { db.close() }
        try seedUndigestedTurn(session: "s-monitor")
        // 直接写摘要并记待办，不经过 write()：这条用例要证的是监视器，
        // 不是「摘要写完顺手重放一次」那条路。
        _ = try db.recordTurnDigest(
            sessionID: "s-monitor", turnIndex: 1,
            digest: "这一轮只欠一次归属判断",
            keywords: "SimiGo HTTPServer", requestSpaceAssignment: true)
        XCTAssertEqual(try db.count("space_turns"), 0, "归属还没写上")
        XCTAssertEqual(try db.pendingSpaceAssignmentRetries(), 1, "欠账在队列里")

        let previousInterval = TurnDigestScheduler.retryMonitorInterval
        TurnDigestScheduler.retryMonitorInterval = 0.2
        TurnDigestScheduler.startRoomAssignmentRetryMonitor()
        defer {
            TurnDigestScheduler.stopRoomAssignmentRetryMonitor()
            TurnDigestScheduler.retryMonitorInterval = previousInterval
        }

        let deadline = Date().addingTimeInterval(15)
        var assigned = 0
        while Date() < deadline {
            if let probe = try? openDatabase() {
                assigned = (try? probe.count("space_turns")) ?? 0
                probe.close()
            }
            if assigned > 0 { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertEqual(assigned, 1, "监视器应当自己把到期的一轮判上，不靠人点")

        let after = try openDatabase()
        defer { after.close() }
        XCTAssertEqual(try after.pendingSpaceAssignmentRetries(), 0, "判上之后欠账销掉")

        // 队列清空就停表：不再留一个每 30 秒空转的定时器，等下一次启动/写入再起。
        let stopDeadline = Date().addingTimeInterval(5)
        while Date() < stopDeadline,
              TurnDigestScheduler.isRoomAssignmentRetryMonitorRunning {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertFalse(TurnDigestScheduler.isRoomAssignmentRetryMonitorRunning,
                       "欠账清空之后监视器应当自己停，不无限期轮询")
    }
    /// A writer can enqueue and request a wake after the monitor's empty
    /// snapshot but before its idle stop. That wake must invalidate the stop
    /// decision, otherwise the new row can sleep forever without another write.
    func testMonitorDoesNotStopWhenNewRetryArrivesAtIdleBoundary() throws {
        try seedUndigestedTurn(session: "s-idle-race")

        let previousInterval = TurnDigestScheduler.retryMonitorInterval
        let previousHook = TurnDigestScheduler.retryMonitorIdleStopHookForTesting
        let gate = OneShotGate()
        TurnDigestScheduler.retryMonitorInterval = 0.2
        TurnDigestScheduler.retryMonitorIdleStopHookForTesting = {
            guard gate.consume() else { return }
            do {
                let db = try ESISDatabase(
                    url: ManagedPaths.databaseURL, createIfNeeded: true)
                defer { db.close() }
                _ = try db.recordTurnDigest(
                    sessionID: "s-idle-race", turnIndex: 1,
                    digest: "空队列检查与新待办到达之间的竞态",
                    keywords: "SimiGo HTTPServer", requestSpaceAssignment: true)
                // The row is committed before requesting the wake.
                TurnDigestScheduler.startRoomAssignmentRetryMonitor()
            } catch {
                NSLog("[test] idle-boundary injection failed: \(error)")
            }
        }
        TurnDigestScheduler.startRoomAssignmentRetryMonitor()
        defer {
            TurnDigestScheduler.stopRoomAssignmentRetryMonitor()
            TurnDigestScheduler.retryMonitorIdleStopHookForTesting = previousHook
            TurnDigestScheduler.retryMonitorInterval = previousInterval
        }

        let deadline = Date().addingTimeInterval(15)
        var assigned = 0
        while Date() < deadline {
            if let probe = try? openDatabase() {
                assigned = (try? probe.count("space_turns")) ?? 0
                probe.close()
            }
            if assigned > 0 { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertEqual(assigned, 1,
                       "空队列停表边界到达的新待办必须由下一跳监视器补上")

        let after = try openDatabase()
        defer { after.close() }
        XCTAssertEqual(try after.pendingSpaceAssignmentRetries(), 0)

        let stopDeadline = Date().addingTimeInterval(5)
        while Date() < stopDeadline,
              TurnDigestScheduler.isRoomAssignmentRetryMonitorRunning {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertFalse(TurnDigestScheduler.isRoomAssignmentRetryMonitorRunning)
    }


}
