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


    private func executeRawSQLite(_ url: URL, _ sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
            throw NSError(domain: "raw", code: 1)
        }
        defer { sqlite3_close_v2(handle) }
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &message) == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? "unknown SQLite error"
            sqlite3_free(message)
            throw NSError(domain: "raw", code: 2, userInfo: [
                NSLocalizedDescriptionKey: detail,
            ])
        }
    }

    private func rawSQLiteScalar(_ url: URL, _ sql: String) throws -> Int {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
            throw NSError(domain: "raw", code: 3)
        }
        defer { sqlite3_close_v2(handle) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else {
            throw NSError(domain: "raw", code: 4, userInfo: [
                NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(handle)),
            ])
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw NSError(domain: "raw", code: 5, userInfo: [
                NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(handle)),
            ])
        }
        return Int(sqlite3_column_int64(stmt, 0))
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

    /// A v43-style full-source FTS rebuild is repaired by v44, and a later
    /// rebuild remains bounded because external content is the registered view.
    func testMigration44BoundsLegacyFTSRebuildWithoutDeletingObjects() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-fts-v44-\(UUID().uuidString).sqlite3")
        scratch.append(url)

        let initial = try ESISDatabase(url: url)
        try initial.runMigrations()
        initial.close()

        let settledID = String(repeating: "a", count: 64)
        let unreferencedID = String(repeating: "b", count: 64)
        try executeRawSQLite(url, """
        INSERT INTO is_objects(object_id, byte_size, content, created_order, created_at)
        VALUES ('\(settledID)', length('SETTLEDONLYTOKEN payload'),
                'SETTLEDONLYTOKEN payload', 900001, '2026-11-18T00:00:00Z');
        INSERT INTO is_objects(object_id, byte_size, content, created_order, created_at)
        VALUES ('\(unreferencedID)', length('UNSETTLEDONLYTOKEN payload'),
                'UNSETTLEDONLYTOKEN payload', 900002, '2026-11-18T00:00:00Z');
        INSERT INTO settlement_summaries(
            settlement_id, session_id, query, summary, summary_sha256,
            summary_object_id, source_payload_digest, created_at
        ) VALUES (
            'S-FTS-REPAIR', 's-fts-repair', 'query', 'summary', 'summary-sha',
            '\(settledID)', 'source-sha', '2026-11-18T00:00:00Z'
        );

        -- Recreate the v43 physical layout: its external content points at all
        -- is_objects rows, so a normal FTS5 rebuild admits the unreferenced row.
        DROP TRIGGER IF EXISTS is_fts_search_indexed_ai;
        DROP TRIGGER IF EXISTS is_fts_settlements_ai;
        DROP TRIGGER IF EXISTS is_fts_settlements_au;
        DROP TRIGGER IF EXISTS is_fts_summaries_ai;
        DROP TRIGGER IF EXISTS is_fts_summaries_au;
        DROP TRIGGER IF EXISTS is_fts_retrieval_ai;
        DROP TRIGGER IF EXISTS is_fts_retrieval_au;
        DROP VIEW IF EXISTS is_searchable_objects;
        DROP TABLE IF EXISTS is_objects_fts;
        DROP TABLE IF EXISTS is_search_indexed;
        CREATE TABLE is_search_indexed(
            object_rowid INTEGER PRIMARY KEY,
            object_id TEXT NOT NULL
        );
        INSERT INTO is_search_indexed(object_rowid, object_id)
        SELECT rowid, object_id FROM is_objects WHERE object_id='\(settledID)';
        CREATE VIRTUAL TABLE is_objects_fts USING fts5(
            content, content='is_objects', content_rowid='rowid', tokenize='trigram'
        );
        INSERT INTO is_objects_fts(is_objects_fts) VALUES('rebuild');
        DELETE FROM schema_migrations WHERE version=44;
        """)
        XCTAssertEqual(try rawSQLiteScalar(
            url, "SELECT COUNT(*) FROM is_objects_fts WHERE is_objects_fts MATCH 'UNSETTLEDONLYTOKEN';"
        ), 1, "the simulated v43 external-content table rebuilds the full source")

        let repaired = try ESISDatabase(url: url, createIfNeeded: false)
        try repaired.runMigrations()
        XCTAssertEqual(try repaired.schemaVersion(), 44)
        repaired.close()

        XCTAssertEqual(try rawSQLiteScalar(
            url, "SELECT COUNT(*) FROM is_objects_fts WHERE is_objects_fts MATCH 'SETTLEDONLYTOKEN';"
        ), 1)
        XCTAssertEqual(try rawSQLiteScalar(
            url, "SELECT COUNT(*) FROM is_objects_fts WHERE is_objects_fts MATCH 'UNSETTLEDONLYTOKEN';"
        ), 0)
        XCTAssertEqual(try rawSQLiteScalar(url, "SELECT COUNT(*) FROM is_search_indexed;"), 1)
        XCTAssertEqual(try rawSQLiteScalar(url, "SELECT COUNT(*) FROM is_objects;"), 2,
                       "FTS repair must not delete original payloads")

        // The invariant must survive the maintenance command that exposed v43.
        try executeRawSQLite(url, """
        INSERT INTO is_objects_fts(is_objects_fts) VALUES('rebuild');
        INSERT INTO is_objects_fts(is_objects_fts, rank) VALUES('integrity-check', 1);
        """)
        XCTAssertEqual(try rawSQLiteScalar(
            url, "SELECT COUNT(*) FROM is_objects_fts WHERE is_objects_fts MATCH 'UNSETTLEDONLYTOKEN';"
        ), 0, "a post-migration rebuild must still see only registered objects")
    }

    func testReferenceUpdatesRemoveOnlyObjectsWithNoRemainingReferences() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-fts-reference-lifecycle-\(UUID().uuidString).sqlite3")
        scratch.append(url)
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        db.close()

        let shared = String(repeating: "a", count: 64)
        let moved = String(repeating: "b", count: 64)
        let replacement = String(repeating: "c", count: 64)
        try executeRawSQLite(url, """
        INSERT INTO is_objects(object_id, byte_size, content, created_order, created_at) VALUES
          ('\(shared)', length('SHAREDREFERENCEOLDTOKEN'), 'SHAREDREFERENCEOLDTOKEN', 920001, '2026-11-18T00:00:00Z'),
          ('\(moved)', length('MOVEDREFERENCEOLDTOKEN'), 'MOVEDREFERENCEOLDTOKEN', 920002, '2026-11-18T00:00:00Z'),
          ('\(replacement)', length('NEWREFERENCEOBJECTTOKEN'), 'NEWREFERENCEOBJECTTOKEN', 920003, '2026-11-18T00:00:00Z');
        INSERT INTO settlements(settlement_id, payload_object_id)
        VALUES ('S-FTS-SHARED', '\(shared)');
        INSERT INTO settlement_summaries(
            settlement_id, session_id, query, summary, summary_sha256,
            summary_object_id, source_payload_digest, created_at
        ) VALUES (
            'S-FTS-SHARED', 's-fts-shared', 'q', 'summary', 'sha',
            '\(shared)', 'source', '2026-11-18T00:00:00Z'
        );
        INSERT INTO retrieval_settlements(
            demand_id, query, root_ids, inputs_digest, result_sha256, result_json,
            hit_count, status, settled_at, result_object_id
        ) VALUES (
            'R-FTS-MOVE', 'q', '[]', 'inputs', 'result', '{}',
            0, 'valid', '2026-11-18T00:00:00Z', '\(moved)'
        );
        """)
        XCTAssertEqual(try rawSQLiteScalar(url, "SELECT COUNT(*) FROM is_search_indexed;"), 2)

        try executeRawSQLite(url, """
        UPDATE settlement_summaries
           SET summary_object_id='\(replacement)'
         WHERE settlement_id='S-FTS-SHARED';
        UPDATE settlements SET payload_object_id='\(replacement)'
         WHERE settlement_id='S-FTS-SHARED';
        UPDATE retrieval_settlements SET result_object_id='\(replacement)'
         WHERE demand_id='R-FTS-MOVE';
        """)
        XCTAssertEqual(try rawSQLiteScalar(url, "SELECT COUNT(*) FROM is_search_indexed;"), 1)
        XCTAssertEqual(try rawSQLiteScalar(
            url, "SELECT COUNT(*) FROM is_objects_fts WHERE is_objects_fts MATCH 'SHAREDREFERENCEOLDTOKEN';"
        ), 0, "shared object leaves only after its last reference moves")
        XCTAssertEqual(try rawSQLiteScalar(
            url, "SELECT COUNT(*) FROM is_objects_fts WHERE is_objects_fts MATCH 'MOVEDREFERENCEOLDTOKEN';"
        ), 0, "retrieval replacement removes its previous object")
        XCTAssertEqual(try rawSQLiteScalar(
            url, "SELECT COUNT(*) FROM is_objects_fts WHERE is_objects_fts MATCH 'NEWREFERENCEOBJECTTOKEN';"
        ), 1)

        try executeRawSQLite(url, """
        INSERT INTO is_objects_fts(is_objects_fts) VALUES('rebuild');
        INSERT INTO is_objects_fts(is_objects_fts, rank) VALUES('integrity-check', 1);
        """)
        XCTAssertEqual(try rawSQLiteScalar(
            url, "SELECT COUNT(*) FROM is_objects_fts WHERE is_objects_fts MATCH 'SHAREDREFERENCEOLDTOKEN';"
        ), 0, "rebuild preserves current-reference membership")
    }

    func testV45MigrationRemovesV44StaleReferenceRows() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-fts-v45-repair-\(UUID().uuidString).sqlite3")
        scratch.append(url)
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        db.close()

        let oldID = String(repeating: "d", count: 64)
        let newID = String(repeating: "e", count: 64)
        try executeRawSQLite(url, """
        INSERT INTO is_objects(object_id, byte_size, content, created_order, created_at) VALUES
          ('\(oldID)', length('V44STALEPROJECTIONTOKEN'), 'V44STALEPROJECTIONTOKEN', 930001, '2026-11-18T00:00:00Z'),
          ('\(newID)', length('V45CURRENTREFERENCE'), 'V45CURRENTREFERENCE', 930002, '2026-11-18T00:00:00Z');
        INSERT INTO settlements(settlement_id, payload_object_id)
        VALUES ('S-V45-REPAIR', '\(oldID)');
        DROP TRIGGER IF EXISTS is_fts_search_indexed_ad;
        DROP TRIGGER IF EXISTS is_fts_settlements_au;
        CREATE TRIGGER is_fts_settlements_au
        AFTER UPDATE OF payload_object_id ON settlements BEGIN
            INSERT OR IGNORE INTO is_search_indexed(object_rowid, object_id)
            SELECT o.rowid, o.object_id FROM is_objects o
             WHERE o.object_id = new.payload_object_id;
        END;
        UPDATE settlements SET payload_object_id='\(newID)'
         WHERE settlement_id='S-V45-REPAIR';
        DELETE FROM schema_migrations WHERE version=45;
        """)
        XCTAssertEqual(try rawSQLiteScalar(url, "SELECT COUNT(*) FROM is_search_indexed;"), 2)

        let repaired = try ESISDatabase(url: url, createIfNeeded: false)
        try repaired.runMigrations()
        XCTAssertEqual(try repaired.schemaVersion(), 45)
        repaired.close()

        XCTAssertEqual(try rawSQLiteScalar(url, "SELECT COUNT(*) FROM is_search_indexed;"), 1)
        XCTAssertEqual(try rawSQLiteScalar(
            url, "SELECT COUNT(*) FROM is_objects_fts WHERE is_objects_fts MATCH 'V44STALEPROJECTIONTOKEN';"
        ), 0, "v45 removes stale postings through the FTS delete trigger")
        XCTAssertEqual(try rawSQLiteScalar(
            url, "SELECT COUNT(*) FROM is_objects_fts WHERE is_objects_fts MATCH 'V45CURRENTREFERENCE';"
        ), 1)
        XCTAssertEqual(try rawSQLiteScalar(url, "SELECT COUNT(*) FROM is_objects;"), 2,
                       "repair preserves immutable source objects")
    }

    /// All reference families register through the same map-triggered FTS write;
    /// the public chat search then combines indexed matches with LIKE fallback.
    func testBoundedProjectionIndexesEveryReferencePathAndPublicSearchFallback() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-fts-paths-\(UUID().uuidString).sqlite3")
        scratch.append(url)

        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        try commit(db, session: "indexed-session", "SETTLEDCHATSEARCHTOKEN in committed chat")
        try commit(db, session: "fallback-session", "UNSETTLEDCHATSEARCHTOKEN in committed chat")
        db.close()

        let settlementInsertID = String(repeating: "c", count: 64)
        let settlementUpdateID = String(repeating: "d", count: 64)
        let retrievalInsertID = String(repeating: "e", count: 64)
        let retrievalUpdateID = String(repeating: "f", count: 64)
        try executeRawSQLite(url, """
        INSERT INTO is_objects(object_id, byte_size, content, created_order, created_at) VALUES
          ('\(settlementInsertID)', length('SETTLEMENTINSERTTOKEN'), 'SETTLEMENTINSERTTOKEN', 910001, '2026-11-18T00:00:00Z'),
          ('\(settlementUpdateID)', length('SETTLEMENTUPDATETOKEN'), 'SETTLEMENTUPDATETOKEN', 910002, '2026-11-18T00:00:00Z'),
          ('\(retrievalInsertID)', length('RETRIEVALINSERTTOKEN'), 'RETRIEVALINSERTTOKEN', 910003, '2026-11-18T00:00:00Z'),
          ('\(retrievalUpdateID)', length('RETRIEVALUPDATETOKEN'), 'RETRIEVALUPDATETOKEN', 910004, '2026-11-18T00:00:00Z'),
          ('\(String(repeating: "7", count: 64))', length('SUMMARYINSERTTOKEN'), 'SUMMARYINSERTTOKEN', 910005, '2026-11-18T00:00:00Z'),
          ('\(String(repeating: "8", count: 64))', length('SUMMARYUPDATETOKEN'), 'SUMMARYUPDATETOKEN', 910006, '2026-11-18T00:00:00Z');

        -- Summary insertion registers the object already owned by a committed chat row.
        INSERT INTO settlement_summaries(
            settlement_id, session_id, query, summary, summary_sha256,
            summary_object_id, source_payload_digest, created_at
        )
        SELECT 'S-FTS-CHAT', 'indexed-session', 'query', 'summary', 'summary-sha',
               content_object_id, 'source-sha', '2026-11-18T00:00:00Z'
          FROM chat_messages
         WHERE session_id='indexed-session' AND role='assistant';

        -- Exercise summary INSERT and UPDATE triggers independently.
        INSERT INTO settlement_summaries(
            settlement_id, session_id, query, summary, summary_sha256,
            summary_object_id, source_payload_digest, created_at
        ) VALUES(
            'S-FTS-SUMMARY-UPDATE', 'summary-session', 'query', 'summary',
            'summary-sha', '\(String(repeating: "7", count: 64))',
            'source-sha', '2026-11-18T00:00:00Z'
        );
        UPDATE settlement_summaries
           SET summary_object_id='\(String(repeating: "8", count: 64))'
         WHERE settlement_id='S-FTS-SUMMARY-UPDATE';

        -- Exercise settlement INSERT and UPDATE triggers independently.
        INSERT INTO settlements(settlement_id, payload_object_id)
        VALUES('S-FTS-INSERT', '\(settlementInsertID)');
        INSERT INTO settlements(settlement_id) VALUES('S-FTS-UPDATE');
        UPDATE settlements SET payload_object_id='\(settlementUpdateID)'
         WHERE settlement_id='S-FTS-UPDATE';

        -- Exercise retrieval INSERT and UPDATE triggers independently.
        INSERT INTO retrieval_settlements(
            demand_id, query, root_ids, inputs_digest, result_sha256, result_json,
            hit_count, status, settled_at, result_object_id
        ) VALUES(
            'R-FTS-INSERT', 'query', '[]', 'inputs', 'result', '{}',
            0, 'valid', '2026-11-18T00:00:00Z', '\(retrievalInsertID)'
        );
        INSERT INTO retrieval_settlements(
            demand_id, query, root_ids, inputs_digest, result_sha256, result_json,
            hit_count, status, settled_at
        ) VALUES(
            'R-FTS-UPDATE', 'query', '[]', 'inputs', 'result', '{}',
            0, 'valid', '2026-11-18T00:00:00Z'
        );
        UPDATE retrieval_settlements SET result_object_id='\(retrievalUpdateID)'
         WHERE demand_id='R-FTS-UPDATE';
        """)

        XCTAssertEqual(try rawSQLiteScalar(url, "SELECT COUNT(*) FROM is_search_indexed;"), 6, "updated-away objects leave the projection when no reference remains")
        try executeRawSQLite(url, """
        INSERT INTO is_objects_fts(is_objects_fts) VALUES('rebuild');
        INSERT INTO is_objects_fts(is_objects_fts, rank) VALUES('integrity-check', 1);
        """)
        for token in [
            "SETTLEDCHATSEARCHTOKEN", "SETTLEMENTINSERTTOKEN",
            "SETTLEMENTUPDATETOKEN", "RETRIEVALINSERTTOKEN", "RETRIEVALUPDATETOKEN",
            "SUMMARYINSERTTOKEN", "SUMMARYUPDATETOKEN",
        ] {
            XCTAssertEqual(try rawSQLiteScalar(
                url, "SELECT COUNT(*) FROM is_objects_fts WHERE is_objects_fts MATCH '\(token)';"
            ), 1, "reference path must index \(token)")
        }
        XCTAssertEqual(try rawSQLiteScalar(
            url, "SELECT COUNT(*) FROM is_objects_fts WHERE is_objects_fts MATCH 'UNSETTLEDCHATSEARCHTOKEN';"
        ), 0, "unreferenced chat objects must stay outside FTS postings")

        let searched = try ESISDatabase(url: url, createIfNeeded: false)
        let indexedHits = try searched.chatIndexRows(
            sessionIDs: ["indexed-session"], matchingAny: ["SETTLEDCHATSEARCHTOKEN"])
        XCTAssertEqual(indexedHits.map(\.sessionID), ["indexed-session"])
        XCTAssertTrue(indexedHits.contains { $0.content.contains("SETTLEDCHATSEARCHTOKEN") })

        let fallbackHits = try searched.chatIndexRows(
            sessionIDs: ["fallback-session"], matchingAny: ["UNSETTLEDCHATSEARCHTOKEN"])
        XCTAssertEqual(fallbackHits.map(\.sessionID), ["fallback-session"])
        XCTAssertTrue(fallbackHits.contains { $0.content.contains("UNSETTLEDCHATSEARCHTOKEN") })
        searched.close()
    }

}
