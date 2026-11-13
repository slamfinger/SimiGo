import Foundation
import SQLite3
import XCTest

@testable import SimiGoRuntimeContract

/// #187 / #188 的契约层回归：房间归属缺口进第五项计数；增量归属撞锁的
/// 失败进持久化待重试记录，锁释放后无需人工介入即可重放成功；重试有上限；
/// 全量重建清空队列。
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

    // MARK: - #187 强制 BUSY 的全链路

    func testAssignmentFailureRetriesAfterForcedBusy() throws {
        let (url, db) = try open("busy-chain", busyTimeoutMS: 100)
        defer { db.close(); cleanup(url) }
        // 立房间 schema（dryRun 不写行），否则「没有表」会先于「锁竞争」失败。
        _ = try db.assignTurnSpaces(dryRun: true)
        try seedTurn(db, session: "s1", turn: 1)

        // 第二个连接持住写锁：被测连接的归属写入必须在 busy_timeout 内失败。
        var blocker: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &blocker,
                                       SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil),
                       SQLITE_OK)
        defer { sqlite3_close_v2(blocker) }
        var err: UnsafeMutablePointer<CChar>?
        XCTAssertEqual(sqlite3_exec(blocker, "BEGIN IMMEDIATE;", nil, nil, &err), SQLITE_OK,
                       err.map { String(cString: $0) } ?? "BEGIN 应当成功")

        var caught: Error?
        do {
            _ = try db.assignTurnSpace(sessionID: "s1", turnIndex: 1)
        } catch {
            caught = error
        }
        XCTAssertNotNil(caught, "持锁期间归属写入必须失败（SQLITE_BUSY）")
        XCTAssertEqual(try db.count("space_turns"), 0, "失败不得留半行")

        // 锁释放后：失败先落成持久记录——进程重启它也还在。
        sqlite3_exec(blocker, "ROLLBACK;", nil, nil, nil)
        try db.recordSpaceAssignmentFailure(sessionID: "s1", turnIndex: 1, error: caught!)
        XCTAssertEqual(try db.pendingSpaceAssignmentRetries(), 1)

        // 无需人工点补录：重放一次，归属写上、队列清空、缺口归零。
        let report = try db.retryPendingSpaceAssignments()
        XCTAssertEqual(report.succeeded, 1)
        XCTAssertEqual(report.stillPending, 0)
        XCTAssertEqual(try db.pendingSpaceAssignmentRetries(), 0)
        let assigned = try firstValue(url, """
        SELECT space_id FROM space_turns WHERE session_id='s1' AND turn_index=1;
        """)
        XCTAssertEqual(assigned, "space-room-simigo")
        XCTAssertEqual(try db.turnGapCounts().rooms, 0)
    }

    func testRetryAttemptsCapAndFullRebuildClearsQueue() throws {
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

        // 达到上限：明确放弃（abandoned），行保留、不无限增长。
        let report = try db.retryPendingSpaceAssignments(maxAttempts: 5)
        XCTAssertEqual(report.abandoned, 1)
        XCTAssertEqual(report.retried, 0)
        XCTAssertEqual(try db.pendingSpaceAssignmentRetries(), 1)
        XCTAssertEqual(try db.count("space_turns"), 0)

        // 全量重建覆盖每条带摘要的轮：队列一并清空。
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
}
