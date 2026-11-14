import Foundation
import SQLite3
import XCTest

@testable import SimiGoRuntimeContract

final class ImportedTurnLedgerTests: XCTestCase {
    private func open(_ name: String) throws -> (URL, ESISDatabase) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("simigo-import-ledger-\(name)-\(UUID().uuidString).sqlite3")
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        return (url, db)
    }

    private func cleanup(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    /// 记账的人就是知道这一轮什么时候发生的人：时间随写入一起落，不留空等回填。
    /// 修复前实测：本会话 t52–t58 七行 source_time 全空，面板「时间」缺 7。
    func testMcpRoundStampsItsOwnSourceTime() throws {
        let (url, db) = try open("source-time")
        defer { db.close(); cleanup(url) }

        // 活库里这一列是回填工具加的（不是迁移建的），新库要用同一条路径先建出来。
        try db.backfillSourceTimes(codexSessionDirectories: [])

        let at = Date()
        try db.recordTurnIndex(
            sessionID: "codex-source-time", turnIndex: 1, requestID: "t1", at: at)

        XCTAssertEqual(
            try db.turnGapCounts().times, 0,
            "实时入账的轮自带时间，不该出现在「缺时间」这一格里")

        // 口径与回填工具一致（UTC ISO）。一列两种写法的话，下一次回填就会把
        // 实时行改写成另一种，谁按其中一种解析就有一半读不出来。
        let stamp = try firstValue(url, """
        SELECT source_time FROM chat_turn_ledger
         WHERE session_id='codex-source-time' AND turn_index=1;
        """)
        XCTAssertNotNil(stamp)
        XCTAssertNotNil(
            stamp?.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"#,
                         options: .regularExpression),
            "source_time 应是 UTC ISO，实际：\(stamp ?? "nil")")

        // 重放同一轮是幂等的：时间不倒退、账本不多行。
        try db.recordTurnIndex(
            sessionID: "codex-source-time", turnIndex: 1, requestID: "t1", at: at)
        let ledger = try db.turnLedger(sessionID: "codex-source-time")
        XCTAssertEqual(ledger.highest, 1)
        XCTAssertEqual(try db.turnGapCounts().times, 0)
    }

    /// 历史归一不挂在写入路径上：写一轮只写自己那一行。否则每写一次就要扫一遍
    /// 全表，越积越贵。旧行归 `backfillSourceTimes`（启动一次 / 人手点一次）。
    func testMcpWriteDoesNotSweepOtherSessions() throws {
        let (url, db) = try open("source-time-heal")
        defer { db.close(); cleanup(url) }

        try db.backfillSourceTimes(codexSessionDirectories: [])
        // 一个停在旧格式的实时行（CF 绝对时秒，没有 source_time）。
        try execRaw(url, """
        INSERT INTO chat_turn_ledger(session_id, turn_index, request_id, seen_at, origin)
        VALUES('probe-old', 1, 't1', '816300000.5', 'mcp');
        INSERT INTO chat_turn_ledger(session_id, turn_index, request_id, seen_at, origin)
        VALUES('deepseek:old', 1, 't1', '816300000.5', 'import');
        """)

        try db.recordTurnIndex(
            sessionID: "codex-other", turnIndex: 1, requestID: "t1")

        XCTAssertNil(
            try firstValue(url, """
            SELECT source_time FROM chat_turn_ledger WHERE session_id='probe-old';
            """),
            "写一轮不该去扫别人的行：历史归一回填路径做")

        // 归一走回填：实时行按自身 seen_at 换算，导入行不拿导入时间冒充对话时间。
        _ = try db.backfillSourceTimes(codexSessionDirectories: [])
        let healed = try firstValue(url, """
        SELECT source_time FROM chat_turn_ledger WHERE session_id='probe-old';
        """)
        XCTAssertNotNil(
            healed?.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"#,
                          options: .regularExpression),
            "回填该按同一口径补上实时行，实际：\(healed ?? "nil")")

        let imported = try firstValue(url, """
        SELECT source_time FROM chat_turn_ledger WHERE session_id='deepseek:old';
        """)
        XCTAssertNil(imported, "导入批次的 seen_at 是导入时间，不该被当成对话时间")
    }

    // MARK: - 测试里直连库（生产接口只写不读，要看结果就在这里问）

    private func firstValue(_ url: URL, _ sql: String) throws -> String? {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            sqlite3_close(handle)
            throw ESISDatabase.DatabaseError.cannotOpen(url.path)
        }
        defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            throw ESISDatabase.DatabaseError.sql("prepare 失败：\(sql)")
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    private func execRaw(_ url: URL, _ sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            sqlite3_close(handle)
            throw ESISDatabase.DatabaseError.cannotOpen(url.path)
        }
        defer { sqlite3_close(handle) }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw ESISDatabase.DatabaseError.sql("exec 失败：\(sql)")
        }
    }

    /// 导入的历史没有调用方轮号，轮号只能由到达序排出来：1..N 连续，
    /// 并且标成 import，不混进 MCP 的「缺号=漏写」。
    func testImportedSessionsGetArrivalOrderedTurns() throws {
        let (url, db) = try open("arrival")
        defer { db.close(); cleanup(url) }

        let base = Date()
        // 故意乱序写入：第二轮先到，第一轮后到。
        for (request, offset) in [("r2", 20.0), ("r1", 10.0)] {
            try db.recordExternalTurn(
                sessionID: "deepseek:abc", provider: "deepseek", requestID: request,
                userText: "问 \(request)", model: nil,
                createdAt: base.addingTimeInterval(offset))
            try db.recordExternalResponse(
                sessionID: "deepseek:abc", provider: "deepseek", requestID: request,
                assistantText: "答 \(request)", model: nil,
                createdAt: base.addingTimeInterval(offset + 1))
        }

        let report = try db.backfillImportedTurnLedger()
        XCTAssertEqual(report.sessionsFilled, 1)
        XCTAssertEqual(report.turnsInserted, 2)

        let ledger = try db.turnLedger(sessionID: "deepseek:abc")
        XCTAssertEqual(ledger.highest, 2)
        XCTAssertTrue(ledger.isContinuous, "导入轮按到达序排，不该有缺号：\(ledger)")

        // r1 的时间更早，所以拿到 1 号。
        XCTAssertEqual(
            try db.turnLedgerRequestID(sessionID: "deepseek:abc", turnIndex: 1), "r1")
        XCTAssertEqual(
            try db.turnLedgerRequestID(sessionID: "deepseek:abc", turnIndex: 2), "r2")

        // 再跑一次是空操作。
        let again = try db.backfillImportedTurnLedger()
        XCTAssertEqual(again.turnsInserted, 0)
        XCTAssertEqual(again.sessionsFilled, 0)
        XCTAssertEqual(again.importedTurnsTotal, 2)
    }

    /// 已经有 MCP 轮号的会话整会话跳过：两种编号混在一个 session 里，
    /// 「缺号」就不再表示漏写。
    func testSessionWithMCPTurnsIsLeftAlone() throws {
        let (url, db) = try open("mixed")
        defer { db.close(); cleanup(url) }

        let base = Date()
        for request in ["t1", "t3"] {
            try db.recordExternalTurn(
                sessionID: "codex-mixed", provider: "codex", requestID: request,
                userText: "问 \(request)", model: nil, createdAt: base)
            try db.recordExternalResponse(
                sessionID: "codex-mixed", provider: "codex", requestID: request,
                assistantText: "答 \(request)", model: nil, createdAt: base)
        }
        _ = try db.recordTurnIndex(sessionID: "codex-mixed", turnIndex: 1, requestID: "t1")
        _ = try db.recordTurnIndex(sessionID: "codex-mixed", turnIndex: 3, requestID: "t3")

        let report = try db.backfillImportedTurnLedger()
        XCTAssertEqual(report.sessionsKept, 1)
        XCTAssertEqual(report.turnsInserted, 0)
        XCTAssertEqual(report.sessionsFilled, 0)
        // MCP 的回填不能把 2 号补上——那个号是调用方漏掉的。
        XCTAssertEqual(try db.turnLedger(sessionID: "codex-mixed").missing, [2])
    }

    /// 没有 request_id 的消息补不了轮，只能报数；不许编一个号出来。
    func testRowsWithoutRequestIDAreReportedNotInvented() throws {
        let (url, db) = try open("unkeyed")
        defer { db.close(); cleanup(url) }

        let userID = try db.appendChatMessage(
            sessionID: "info-unkeyed", role: "user", content: "问", model: nil,
            createdAt: Date())
        _ = try db.commitChatTurn(
            sessionID: "info-unkeyed", userMessageID: userID,
            assistantText: "答", model: nil, createdAt: Date())

        let report = try db.backfillImportedTurnLedger()
        XCTAssertEqual(report.sessionsUnkeyed, 1)
        XCTAssertEqual(report.messagesUnkeyed, 2)
        XCTAssertEqual(report.turnsInserted, 0)
        XCTAssertEqual(try db.turnLedger(sessionID: "info-unkeyed").highest, 0)
    }

}
