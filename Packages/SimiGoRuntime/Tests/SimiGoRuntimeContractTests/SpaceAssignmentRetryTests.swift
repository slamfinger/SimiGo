import Foundation
import SQLite3
import XCTest

@testable import SimiGoRuntimeContract

/// #187 / #188 的契约层回归。
///
/// 三件事各自独立、都要证：
/// 1 第五项计数认「有摘要、无归属」，也认「房间表还没建」这一段；
/// 2 归属失败不会没留下东西——待办与摘要同一个事务落库；
/// 3 重试有次数上限**和**时间退避，放弃的轮能被人按「重放」重新武装。
///
/// 强制 SQLITE_BUSY 的手法：第二个裸 sqlite3 连接持住 `BEGIN IMMEDIATE`，
/// 被测连接用 100ms 的 `busy_timeout`（产品默认 5000 只为测试参数让位）。
final class SpaceAssignmentRetryTests: XCTestCase {
    private func tempURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("simigo-space-retry-\(name)-\(UUID().uuidString).sqlite3")
    }

    private func cleanup(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func open(_ name: String, busyTimeoutMS: Int32 = 5000) throws
        -> (URL, ESISDatabase) {
        let url = tempURL(name)
        let db = try ESISDatabase(url: url, busyTimeoutMS: busyTimeoutMS)
        try db.runMigrations()
        return (url, db)
    }

    /// 造一条「有账、有摘要、有词、无归属」的轮。
    private func seedTurn(_ db: ESISDatabase, session: String, turn: Int) throws {
        try db.recordExternalTurn(
            sessionID: session, provider: "local", requestID: "r\(turn)",
            userText: "问：\(session) 第 \(turn) 轮", model: nil, createdAt: Date())
        try db.recordExternalResponse(
            sessionID: session, provider: "local", requestID: "r\(turn)",
            assistantText: "答：SimiGo HTTPServer", model: nil, createdAt: Date())
        try db.recordTurnIndex(sessionID: session, turnIndex: turn,
                               requestID: "r\(turn)", at: Date())
        try db.recordTurnDigest(
            sessionID: session, turnIndex: turn, digest: "d\(turn)",
            keywords: "simigo HTTPServer")
    }

    /// 拿住写锁。返回的句柄要显式 `release`（或 defer close 前先 ROLLBACK）。
    private func holdWriteLock(_ url: URL) throws -> OpaquePointer {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &handle,
                                       SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil),
                       SQLITE_OK)
        var err: UnsafeMutablePointer<CChar>?
        XCTAssertEqual(sqlite3_exec(handle, "BEGIN IMMEDIATE;", nil, nil, &err), SQLITE_OK,
                       err.map { String(cString: $0) } ?? "BEGIN 应当成功")
        return handle!
    }

    private func releaseLock(_ handle: OpaquePointer) {
        sqlite3_exec(handle, "ROLLBACK;", nil, nil, nil)
        sqlite3_close_v2(handle)
    }

    // MARK: - #188 第五项

    func testTurnGapCountsRoomsWithoutAssignment() throws {
        let (url, db) = try open("gap-rooms")
        defer { db.close(); cleanup(url) }
        // 房间表是惰性建的（首次触碰房间函数才建）；dryRun 只立 schema，
        // 不写行、不清重试队列。
        _ = try db.assignTurnSpaces(dryRun: true)

        try seedTurn(db, session: "s1", turn: 1)
        // 既无摘要也无归属的轮：不进 rooms（那归 digests 说话）。
        try db.recordExternalTurn(
            sessionID: "s1", provider: "local", requestID: "r2",
            userText: "问：还没摘要", model: nil, createdAt: Date())
        try db.recordExternalResponse(
            sessionID: "s1", provider: "local", requestID: "r2",
            assistantText: "答：也没有", model: nil, createdAt: Date())
        try db.recordTurnIndex(sessionID: "s1", turnIndex: 2,
                               requestID: "r2", at: Date())

        var gaps = try db.turnGapCounts()
        XCTAssertEqual(gaps.rooms, 1, "有摘要、无归属的轮正好一条")
        XCTAssertEqual(gaps.digests, 1, "没摘要的轮仍在原有账上")
        XCTAssertTrue(gaps.total > 0)

        _ = try db.assignTurnSpaces()
        gaps = try db.turnGapCounts()
        XCTAssertEqual(gaps.rooms, 0, "全量归属之后房间缺口归零")
    }

    /// 房间表还没建出来，不等于「归属都齐了」：每条带摘要的轮都还没有归属。
    /// 老库第一次数缺口就走这条路，数成 0 会让人以为没事（#188 审核 2026-11-13）。
    func testRoomGapCountsAllDigestsWhenRoomTableMissing() throws {
        let (url, db) = try open("gap-no-room-table")
        defer { db.close(); cleanup(url) }
        try seedTurn(db, session: "s1", turn: 1)
        try seedTurn(db, session: "s1", turn: 2)
        XCTAssertFalse(tableExists(url, "space_turns"), "这条用例的前提就是房间表还没建")

        let gaps = try db.turnGapCounts()
        XCTAssertEqual(gaps.rooms, 2, "没有房间表时，两条带摘要的轮都算缺口")
    }

    // MARK: - #187 摘要与待办同生共死

    /// 撞锁时摘要写不进去，那么待办也不能单独留下——不能出现「有欠账、没摘要」
    /// 这种一半的状态。放开锁之后同一次调用把两样都写上。
    func testDigestAndIntentLiveOrDieTogether() throws {
        let (url, db) = try open("intent-atomic", busyTimeoutMS: 100)
        defer { db.close(); cleanup(url) }
        _ = try db.assignTurnSpaces(dryRun: true)
        try seedTurn(db, session: "s1", turn: 1)

        let lock = try holdWriteLock(url)
        var caught: Error?
        do {
            _ = try db.recordTurnDigest(
                sessionID: "s1", turnIndex: 2, digest: "抢不到锁的一轮",
                keywords: "simigo HTTPServer", requestSpaceAssignment: true)
        } catch {
            caught = error
        }
        XCTAssertNotNil(caught, "持锁期间摘要写入必须失败")
        XCTAssertEqual(try db.count("turn_digests"), 1, "第二条摘要没有落库")
        XCTAssertEqual(try db.pendingSpaceAssignmentRetries(), 0, "也没有留下孤零零的待办")

        releaseLock(lock)

        _ = try db.recordTurnDigest(
            sessionID: "s1", turnIndex: 2, digest: "放开锁之后的一轮",
            keywords: "simigo HTTPServer", requestSpaceAssignment: true)
        XCTAssertEqual(try db.count("turn_digests"), 2)
        XCTAssertEqual(try db.pendingSpaceAssignmentRetries(), 1, "摘要落了，待办同时落了")
    }

    // MARK: - #187 退避与恢复

    /// 锁还被别人拿着的时候，重放可以试、但**不许把额度烧掉**：失败记不下来就
    /// 不算一次尝试（#187 审核：5 次上限被连续写入快速耗尽是实实在在的风险）。
    func testLockHeldDoesNotBurnAttempts() throws {
        let (url, db) = try open("lock-no-burn", busyTimeoutMS: 100)
        defer { db.close(); cleanup(url) }
        _ = try db.assignTurnSpaces(dryRun: true)
        try seedTurn(db, session: "s1", turn: 1)
        _ = try db.recordTurnDigest(
            sessionID: "s1", turnIndex: 1, digest: "d1", keywords: "simigo HTTPServer",
            requestSpaceAssignment: true)

        let lock = try holdWriteLock(url)
        let blocked = try db.retryPendingSpaceAssignments()
        XCTAssertEqual(blocked.retried, 1, "试过")
        XCTAssertEqual(blocked.stillPending, 1)
        XCTAssertEqual(blocked.succeeded, 0)
        XCTAssertEqual(blocked.abandoned, 0)
        XCTAssertEqual(try db.pendingSpaceAssignmentRetries(), 1, "行还在")
        // 记不下来的失败不算数：attempts 仍是 0，额度没动。
        let status = try db.spaceAssignmentRetryStatus()
        XCTAssertEqual(status.abandoned, 0)
        let attempts = try firstValue(url,
            "SELECT attempts FROM space_assignment_retry WHERE session_id='s1' AND turn_index=1;")
        XCTAssertEqual(attempts, "0", "锁在手上时记不下失败，这次尝试不该计入次数")

        releaseLock(lock)

        let ok = try db.retryPendingSpaceAssignments()
        XCTAssertEqual(ok.succeeded, 1, "锁放开后一次就补上")
        XCTAssertEqual(try db.pendingSpaceAssignmentRetries(), 0)
        XCTAssertEqual(try db.turnGapCounts().rooms, 0)
    }

    /// 记下来的失败才进退避：30 秒内不再试，时间到了再试就成。
    func testRecordedFailureBacksOffThenSucceeds() throws {
        let (url, db) = try open("backoff")
        defer { db.close(); cleanup(url) }
        _ = try db.assignTurnSpaces(dryRun: true)
        try seedTurn(db, session: "s1", turn: 1)
        _ = try db.recordTurnDigest(
            sessionID: "s1", turnIndex: 1, digest: "d1", keywords: "simigo HTTPServer",
            requestSpaceAssignment: true)

        let start = Date()
        try db.recordSpaceAssignmentFailure(
            sessionID: "s1", turnIndex: 1,
            error: ESISDatabase.DatabaseError.sql("模拟 BUSY"), now: start)

        let tooSoon = try db.retryPendingSpaceAssignments(now: start.addingTimeInterval(1))
        XCTAssertEqual(tooSoon.retried, 0)
        XCTAssertEqual(tooSoon.deferred, 1, "第一次失败后 30 秒内不再试")
        XCTAssertEqual(tooSoon.abandoned, 0, "退避不等于放弃")

        let later = start.addingTimeInterval(
            ESISDatabase.assignmentRetryDelay(attempts: 1) + 1)
        let ok = try db.retryPendingSpaceAssignments(now: later)
        XCTAssertEqual(ok.retried, 1)
        XCTAssertEqual(ok.succeeded, 1)
        XCTAssertEqual(try db.pendingSpaceAssignmentRetries(), 0)
        XCTAssertEqual(try db.turnGapCounts().rooms, 0)
    }

    /// 退避是递增的，且有 30 分钟天花板——不是「等 30 秒再来」一直循环。
    func testBackoffGrowsAndIsCapped() {
        let delays = (1...8).map { ESISDatabase.assignmentRetryDelay(attempts: $0) }
        XCTAssertEqual(delays.first, 30)
        XCTAssertEqual(delays[1], 60)
        XCTAssertEqual(delays[2], 120)
        XCTAssertEqual(delays.last, 1800, "封顶 30 分钟")
        for (lhs, rhs) in zip(delays, delays.dropFirst()) where rhs < 1800 {
            XCTAssertGreaterThan(rhs, lhs)
        }
    }

    /// 到上限就停手，行不消失；人按「重放」重新武装后还能补上。
    func testAttemptsCapThenManualRearm() throws {
        let (url, db) = try open("retry-cap")
        defer { db.close(); cleanup(url) }
        try seedTurn(db, session: "s1", turn: 1)

        // 同一轮反复失败只累计 attempts，不积行。
        for i in 0..<5 {
            try db.recordSpaceAssignmentFailure(
                sessionID: "s1", turnIndex: 1,
                error: ESISDatabase.DatabaseError.sql("模拟 BUSY #\(i)"))
        }
        XCTAssertEqual(try db.pendingSpaceAssignmentRetries(), 1)

        let report = try db.retryPendingSpaceAssignments(maxAttempts: 5)
        XCTAssertEqual(report.abandoned, 1)
        XCTAssertEqual(report.retried, 0)
        XCTAssertEqual(try db.count("space_turns"), 0, "放弃之后不会自己再判")

        let status = try db.spaceAssignmentRetryStatus(maxAttempts: 5)
        XCTAssertEqual(status.pending, 1)
        XCTAssertEqual(status.abandoned, 1, "放弃的轮要能在界面上数出来")
        XCTAssertTrue(status.lastError?.contains("模拟 BUSY") == true)

        // 人按「重放」：次数归零、退避清掉，于是真的补上了。
        XCTAssertEqual(try db.resetSpaceAssignmentRetries(), 1)
        let retried = try db.retryPendingSpaceAssignments()
        XCTAssertEqual(retried.succeeded, 1)
        XCTAssertEqual(try db.pendingSpaceAssignmentRetries(), 0)
        XCTAssertEqual(try db.turnGapCounts().rooms, 0)
    }

    /// 全量重建覆盖每条带摘要的轮，队列一并清空。
    ///
    /// 另一半：**队列之外的孤儿**（有摘要、没归属、不在队列里）只重放队列是
    /// 补不到的，得先补进队列——工具补的摘要、断电丢掉的那一行都是这一类。
    func testOrphanDigestIsEnqueuedThenAssigned() throws {
        let (url, db) = try open("orphan")
        defer { db.close(); cleanup(url) }
        // seedTurn 只写摘要，不写待办：这正是「孤儿」的形状。
        try seedTurn(db, session: "s1", turn: 1)
        XCTAssertEqual(try db.pendingSpaceAssignmentRetries(), 0, "队列里本来没有它")
        XCTAssertEqual(try db.turnGapCounts().rooms, 1, "但第五项看得见它")

        XCTAssertEqual(try db.enqueueDigestsWithoutRoom(), 1)
        XCTAssertEqual(try db.pendingSpaceAssignmentRetries(), 1)
        // 幂等：再补一次不会多出第二行。
        XCTAssertEqual(try db.enqueueDigestsWithoutRoom(), 0)

        let report = try db.retryPendingSpaceAssignments()
        XCTAssertEqual(report.succeeded, 1)
        XCTAssertEqual(try db.turnGapCounts().rooms, 0)
        XCTAssertEqual(try db.pendingSpaceAssignmentRetries(), 0)
    }

    func testFullRebuildClearsQueue() throws {
        let (url, db) = try open("rebuild-clears")
        defer { db.close(); cleanup(url) }
        try seedTurn(db, session: "s1", turn: 1)
        try db.recordSpaceAssignmentFailure(
            sessionID: "s1", turnIndex: 1,
            error: ESISDatabase.DatabaseError.sql("模拟 BUSY"))

        let rebuild = try db.assignTurnSpaces()
        XCTAssertEqual(rebuild.rowsWritten, 1)
        XCTAssertEqual(try db.pendingSpaceAssignmentRetries(), 0)
        XCTAssertEqual(try db.turnGapCounts().rooms, 0)
    }

    // MARK: - #189 失败原因分类（分类器在契约包，包测试直接断言）

    func testFailureReasonVocabulary() {
        XCTAssertEqual(
            DigestRepairReceipt.FailureReason.describe(
                DigestRepairReceipt.DigestionError.badFormat),
            "格式不合")
        XCTAssertEqual(
            DigestRepairReceipt.FailureReason.describe(
                NSError(domain: "TurnDigest", code: 1)),
            "HTTP：模型返回非 200")
        XCTAssertEqual(
            DigestRepairReceipt.FailureReason.describe(
                NSError(domain: "TurnDigest", code: 2)),
            "HTTP：模型返回里没有 content")
        XCTAssertTrue(
            DigestRepairReceipt.FailureReason.describe(
                URLError(.cannotConnectToHost)).hasPrefix("HTTP："),
            "其余错误保底归 HTTP，不吞原因；stopped/yielded 不走这里，"
                + "由回执的 stoppedAt/yielded 单独表达")
    }

    // MARK: - helpers

    /// 裸连接读一个字符串值，用来断言测试不该通过产品接口知道的列。
    private func firstValue(_ url: URL, _ sql: String) throws -> String? {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close_v2(handle) }
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(handle, sql, -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    /// `sqlite_master` 里有没有这张表。用裸连接问，不走被测对象。
    private func tableExists(_ url: URL, _ name: String) -> Bool {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
        else { return false }
        defer { sqlite3_close_v2(handle) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(
            handle,
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?;",
            -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return false }
        return sqlite3_column_int64(stmt, 0) > 0
    }
}
