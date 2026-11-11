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
