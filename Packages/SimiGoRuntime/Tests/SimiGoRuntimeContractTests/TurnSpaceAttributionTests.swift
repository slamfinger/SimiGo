import Foundation
import SQLite3
import XCTest

@testable import SimiGoRuntimeContract

/// 归属修复（L4 行1 A 段）的隔离自测。
///
/// 两件事各证一次：
/// 1 判据读内容：关键词没命中、摘要正文说清楚了，轮次也该进房间；
/// 2 归属是会话证据的函数，不是轮次到达顺序的函数：多数晚到时，早先
///   落成「其他」（或还没判）的轮次按当前证据补判，结果与全量重建同形，
///   且判据没变的行不重写。
final class TurnSpaceAttributionTests: XCTestCase {
    private func tempURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("simigo-space-attr-\(name)-\(UUID().uuidString).sqlite3")
    }

    private func cleanup(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func open(_ name: String) throws -> (URL, ESISDatabase) {
        let url = tempURL(name)
        let db = try ESISDatabase(url: url, busyTimeoutMS: 5000)
        try db.runMigrations()
        return (url, db)
    }

    private func seedTurn(
        _ db: ESISDatabase, session: String, turn: Int,
        digest: String, keywords: String
    ) throws {
        let question = "问：\(session) 第 \(turn) 轮"
        let answer = "答：\(digest)"
        try db.recordExternalTurn(
            sessionID: session, provider: "local", requestID: "r\(turn)",
            userText: question, model: nil, createdAt: Date())
        try db.recordExternalResponse(
            sessionID: session, provider: "local", requestID: "r\(turn)",
            assistantText: answer, model: nil, createdAt: Date())
        try db.recordTurnIndex(sessionID: session, turnIndex: turn,
                               requestID: "r\(turn)", at: Date())
        try db.recordTurnDigest(
            sessionID: session, turnIndex: turn, digest: digest, keywords: keywords,
            expectedQuestionSHA256: TurnDigestText.sourceSHA256(question),
            expectedAnswerSHA256: TurnDigestText.sourceSHA256(answer))
    }

    /// turn → [(space_id, assigned_by)]，按 space_id 排序。
    private func assignments(
        _ db: ESISDatabase, session: String
    ) throws -> [Int: [(space: String, by: String)]] {
        let stmt = try db.prepare("""
        SELECT turn_index, space_id, assigned_by FROM space_turns
         WHERE session_id=? ORDER BY turn_index, space_id;
        """)
        defer { sqlite3_finalize(stmt) }
        try db.bind(stmt, 1, session)
        var out: [Int: [(space: String, by: String)]] = [:]
        while try db.stepRowOrDone(stmt) {
            let turn = Int(sqlite3_column_int64(stmt, 0))
            let space = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let by = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            out[turn, default: []].append((space: space, by: by))
        }
        return out
    }

    private func stampOf(_ db: ESISDatabase, session: String, turn: Int) throws -> String? {
        let stmt = try db.prepare("""
        SELECT assigned_at FROM space_turns
         WHERE session_id=? AND turn_index=? ORDER BY space_id LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try db.bind(stmt, 1, session)
        try db.bind(stmt, 2, Int64(turn))
        guard try db.stepRowOrDone(stmt), let c = sqlite3_column_text(stmt, 0) else {
            return nil
        }
        return String(cString: c)
    }

    private func shape(
        _ rows: [Int: [(space: String, by: String)]]
    ) -> [String] {
        rows.keys.sorted().flatMap { turn in
            rows[turn]!.map { "\(turn)|\($0.space)|\($0.by)" }.sorted()
        }
    }

    /// 三条中性轮 + 三条 SimiGo 轮。第三轮故意不单独判：补判要能把它接上。
    private func buildHealedSession(_ db: ESISDatabase, session: String) throws {
        for turn in 1...3 {
            try seedTurn(db, session: session, turn: turn,
                         digest: "整理一份待办清单", keywords: "todo list")
            if turn != 3 {
                _ = try db.assignTurnSpace(sessionID: session, turnIndex: turn)
            }
        }
        for turn in 4...6 {
            try seedTurn(db, session: session, turn: turn,
                         digest: "SimiGo 的发布流程记录", keywords: "simigo")
        }
        _ = try db.assignTurnSpace(sessionID: session, turnIndex: 4)
        _ = try db.assignTurnSpace(sessionID: session, turnIndex: 5)
        _ = try db.assignTurnSpace(sessionID: session, turnIndex: 6)
    }

    // MARK: - 判据读内容

    func testDigestTextCarriesEvidenceWhenKeywordsMiss() throws {
        let (url, db) = try open("gist-evidence")
        defer { db.close(); cleanup(url) }
        try seedTurn(db, session: "s", turn: 1,
                     digest: "围绕 SimiGo 的发布流程整理成清单",
                     keywords: "release checklist")
        _ = try db.assignTurnSpace(sessionID: "s", turnIndex: 1)
        let rows = try assignments(db, session: "s")
        XCTAssertEqual(rows[1]?.map(\.space), ["space-room-simigo"],
                       "关键词没命中、摘要正文命中，也应判进内容房间")
        XCTAssertEqual(rows[1]?.map(\.by), ["content"])
    }

    func testFullRebuildReadsDigestText() throws {
        let (url, db) = try open("gist-rebuild")
        defer { db.close(); cleanup(url) }
        try seedTurn(db, session: "s", turn: 1,
                     digest: "围绕 SimiGo 的发布流程整理成清单",
                     keywords: "release checklist")
        _ = try db.assignTurnSpaces()
        let rows = try assignments(db, session: "s")
        XCTAssertEqual(rows[1]?.map(\.space), ["space-room-simigo"],
                       "全量重算与增量用同一个取词面")
        XCTAssertEqual(rows[1]?.map(\.by), ["content"])
    }

    // MARK: - 顺序无关

    func testLateMajorityHealsEarlierOtherTurns() throws {
        let (url, db) = try open("late-majority")
        defer { db.close(); cleanup(url) }

        for turn in 1...3 {
            try seedTurn(db, session: "s", turn: turn,
                         digest: "整理一份待办清单", keywords: "todo list")
            if turn != 3 {
                _ = try db.assignTurnSpace(sessionID: "s", turnIndex: turn)
            }
        }
        let early = try assignments(db, session: "s")
        XCTAssertEqual(early[1]?.map(\.space), ["space-room-other"],
                       "多数未到，先落「其他」")
        XCTAssertNil(early[3], "第三轮还没有归属")

        for turn in 4...6 {
            try seedTurn(db, session: "s", turn: turn,
                         digest: "SimiGo 的发布流程记录", keywords: "simigo")
        }
        _ = try db.assignTurnSpace(sessionID: "s", turnIndex: 4)
        let stampTurn4 = try stampOf(db, session: "s", turn: 4)
        XCTAssertNotNil(stampTurn4)
        _ = try db.assignTurnSpace(sessionID: "s", turnIndex: 5)
        _ = try db.assignTurnSpace(sessionID: "s", turnIndex: 6)

        let healed = try assignments(db, session: "s")
        for turn in 1...3 {
            XCTAssertEqual(healed[turn]?.map(\.space), ["space-room-simigo"],
                           "多数到齐后第 \(turn) 轮按当前证据补判")
            XCTAssertEqual(healed[turn]?.map(\.by), ["inherit"])
        }
        for turn in 4...6 {
            XCTAssertEqual(healed[turn]?.map(\.space), ["space-room-simigo"])
            XCTAssertEqual(healed[turn]?.map(\.by), ["content"])
        }
        XCTAssertEqual(try stampOf(db, session: "s", turn: 4), stampTurn4,
                       "判据没变的行不重写，assigned_at 保留第一次判定的时刻")
    }

    func testIncrementalConvergesToFullRebuildShape() throws {
        let (url, db) = try open("converge")
        defer { db.close(); cleanup(url) }
        try buildHealedSession(db, session: "s")
        let incremental = try assignments(db, session: "s")

        _ = try db.assignTurnSpaces()
        let rebuilt = try assignments(db, session: "s")
        XCTAssertEqual(shape(incremental), shape(rebuilt),
                       "增量路径（含补判）应与全量重算同形")
    }

    func testHealStaysInsideSession() throws {
        let (url, db) = try open("isolation")
        defer { db.close(); cleanup(url) }
        try buildHealedSession(db, session: "s1")
        for turn in 1...2 {
            try seedTurn(db, session: "s2", turn: turn,
                         digest: "整理一份待办清单", keywords: "todo list")
            _ = try db.assignTurnSpace(sessionID: "s2", turnIndex: turn)
        }
        let rows = try assignments(db, session: "s2")
        for turn in 1...2 {
            XCTAssertEqual(rows[turn]?.map(\.space), ["space-room-other"],
                           "别的会话的多数不能跨会话继承")
            XCTAssertEqual(rows[turn]?.map(\.by), ["other"])
        }
    }

    func testNoHealBelowMajorityThreshold() throws {
        let (url, db) = try open("below-threshold")
        defer { db.close(); cleanup(url) }
        for turn in [1, 2] {
            try seedTurn(db, session: "s", turn: turn,
                         digest: "整理一份待办清单", keywords: "todo list")
            _ = try db.assignTurnSpace(sessionID: "s", turnIndex: turn)
        }
        for turn in [3, 4] {
            try seedTurn(db, session: "s", turn: turn,
                         digest: "SimiGo 的发布流程记录", keywords: "simigo")
            _ = try db.assignTurnSpace(sessionID: "s", turnIndex: turn)
        }
        let rows = try assignments(db, session: "s")
        for turn in [1, 2] {
            XCTAssertEqual(rows[turn]?.map(\.space), ["space-room-other"],
                           "内容命中只有 2 轮，不够多数门槛（≥3），不补判")
            XCTAssertEqual(rows[turn]?.map(\.by), ["other"])
        }
    }
}