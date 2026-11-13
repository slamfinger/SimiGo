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
}
