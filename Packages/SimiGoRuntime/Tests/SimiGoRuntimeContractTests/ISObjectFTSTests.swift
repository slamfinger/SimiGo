import Foundation
import SQLite3
import XCTest
@testable import SimiGoRuntimeContract

/// 检索 A 方案：`is_objects` 的 trigram 索引。
///
/// 量的是三件事：
/// 1. 3 字以上走索引、1–2 字回落 LIKE，两条路的**命中集合相同**；
/// 2. 索引进得去也删得掉（内容是只增的，靠一条 INSERT 触发器）；
/// 3. 回执里说得出这次走没走索引（`unindexedTerms`）。
final class ISObjectFTSTests: XCTestCase {

    private var scratch: [URL] = []

    override func tearDown() {
        for url in scratch {
            try? FileManager.default.removeItem(at: url)
        }
        scratch = []
        super.tearDown()
    }

    private func open() throws -> ESISDatabase {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-fts-\(UUID().uuidString).sqlite3")
        scratch.append(url)
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        return db
    }

    private func commit(_ db: ESISDatabase, session: String, _ text: String) throws {
        let userID = try db.appendChatMessage(
            sessionID: session, role: "user", content: "问：\(session)",
            model: nil, createdAt: Date())
        try db.commitChatTurn(
            sessionID: session, userMessageID: userID, assistantText: text,
            model: nil, createdAt: Date())
    }

    func testSchemaHeadMatchesDeclaredVersion() throws {
        let db = try open()
        XCTAssertEqual(try db.schemaVersion(), ESISDatabase.currentSchemaVersion)
    }

    func testThreeCharacterTermFindsSubstringThroughIndex() throws {
        let db = try open()
        try commit(db, session: "s1", "本合同额为一千万元，含税。")
        try commit(db, session: "s1", "另一段毫不相干的文字。")

        let hits = try db.chatIndexRows(sessionIDs: nil, matchingAny: ["合同额"])
        XCTAssertEqual(hits.compactMap(\.sessionID), ["s1"])
        XCTAssertTrue(hits.contains { $0.content.contains("合同额") })
        XCTAssertTrue(ESISDatabase.isFTSEligible("合同额"))
    }

    func testTwoCharacterTermIsNotEligibleButStillMatches() throws {
        let db = try open()
        try commit(db, session: "s1", "本合同额为一千万元。")

        XCTAssertFalse(ESISDatabase.isFTSEligible("合同"))
        let hits = try db.chatIndexRows(sessionIDs: nil, matchingAny: ["合同"])
        XCTAssertEqual(hits.count, 1, "1–2 字回落 LIKE，仍然命中")
    }

    func testIndexedAndLinearPathsAgreeRowForRow() throws {
        let db = try open()
        try commit(db, session: "s1", "合同额 10000000 元，含税。")
        try commit(db, session: "s1", "折扣后金额 9000000 元。")
        try commit(db, session: "s2", "合同金额与合同额不是同一个写法。")
        try commit(db, session: "s2", "完全无关的一段。")

        let all = try db.chatIndexRows(sessionIDs: nil, matchingAny: nil)
        for term in ["合同额", "金额", "元", "合同", "折扣后金额"] {
            let indexed = try db.chatIndexRows(sessionIDs: nil, matchingAny: [term])
                .map(\.messageID).sorted()
            let linear = all.filter { $0.content.contains(term) }
                .map(\.messageID).sorted()
            XCTAssertEqual(indexed, linear, "「\(term)」两条路的命中集合必须逐个相同")
        }
    }

    func testQueryTextWithFTSSyntaxCharactersStaysLiteral() throws {
        let db = try open()
        try commit(db, session: "s1", "括号 (a\"b) 与百分号 5% 都在这一行。")
        // 这些字符如果被当查询语法，FTS 会报错，而不是返回 0 命中。
        for term in ["(a\"b)", "5%", "a\"b"] {
            let hits = try db.chatIndexRows(sessionIDs: nil, matchingAny: [term])
            XCTAssertEqual(hits.count, 1, "「\(term)」应作为字面量命中")
        }
    }

    func testResolutionReportsWhichTermsMissedTheIndex() throws {
        let db = try open()
        try commit(db, session: "s1", "本合同额为一千万元。")
        let loop = InformationLoop(database: db)

        let short = try loop.resolve(.init(sessionID: "r1", query: "合同", limit: 5))
        XCTAssertEqual(short.unindexedTerms, ["合同"])

        // 中文长词会被拆成全体 bigram：整词（合同额）走 trigram，两个字（合同 / 同额）
        // 只能回落 LIKE。这不是缺陷，是 trigram 的边界——如实报出来。
        let long = try loop.resolve(.init(sessionID: "r2", query: "合同额", limit: 5))
        XCTAssertEqual(Set(long.unindexedTerms), Set(["合同", "同额"]))
        XCTAssertTrue(ESISDatabase.isFTSEligible("合同额"))

        // 全 ASCII 的词没有拆词，整词都走索引。
        let ascii = try loop.resolve(.init(sessionID: "r3", query: "contract", limit: 5))
        XCTAssertTrue(ascii.unindexedTerms.isEmpty)
    }

    /// v28：索引只覆盖结算引用过的对象，其余行靠 LIKE 回落。
    /// 造两条消息，只让一条被结算摘要引用，看索引里是不是只有这一条。
    func testOnlySettledObjectsEnterTheIndex() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-fts-\(UUID().uuidString).sqlite3")
        scratch.append(url)
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        db.close()

        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        func exec(_ sql: String) throws {
            var message: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(handle, sql, nil, nil, &message) == SQLITE_OK else {
                throw NSError(domain: "raw", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: message.map { String(cString: $0) } ?? "?",
                ])
            }
        }
        func scalar(_ sql: String) throws -> Int {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK,
                let stmt
            else { throw NSError(domain: "raw", code: 2) }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else {
                throw NSError(domain: "raw", code: 3)
            }
            return Int(sqlite3_column_int64(stmt, 0))
        }

        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM is_search_indexed;"), 0,
                       "没进过结算的对象不该在索引里")
        // 两个内容对象：只让第一个被结算摘要引用。
        try exec("""
        INSERT INTO is_objects(object_id, byte_size, content, created_order, created_at)
        SELECT 'aaaa000000000000000000000000000000000000000000000000000000000001',
               length('本合同额为一千万元。'),
               '本合同额为一千万元。', 900001, '2026-11-11T00:00:00Z';
        INSERT INTO is_objects(object_id, byte_size, content, created_order, created_at)
        SELECT 'aaaa000000000000000000000000000000000000000000000000000000000002',
               length('另一段毫不相干的话。'),
               '另一段毫不相干的话。', 900002, '2026-11-11T00:00:00Z';
        """)
        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM is_search_indexed;"), 0,
                       "对象进库本身不等于进索引")
        try exec("""
        INSERT INTO settlement_summaries(
            settlement_id, session_id, query, summary, summary_sha256,
            summary_object_id, source_payload_digest, created_at)
        VALUES('S1', 's1', 'q', '摘要：本合同额', 'x',
               'aaaa000000000000000000000000000000000000000000000000000000000001',
               'x', '2026-11-11T00:00:00Z');
        """)
        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM is_search_indexed;"), 1,
                       "结算摘要引用的对象应被触发器放进索引")
        XCTAssertEqual(
            try scalar("SELECT COUNT(*) FROM is_objects_fts WHERE is_objects_fts MATCH '合同额';"),
            1)
    }
}
