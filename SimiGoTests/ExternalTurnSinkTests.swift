import Foundation
import SQLite3
import XCTest
import SimiGoRuntimeContract
@testable import SimiGo
@testable import SimiGoCollection

/// 采集桥 → IS 的落库后果：一条采集到的云端会话按外部轮次合同入库，
/// 三档 disposition 分别落到 `committed` / `recorded` / `internal`，
/// 且重投同一候选不会追加行。
final class ExternalTurnSinkTests: XCTestCase {

    private var dir: URL!
    private var dbURL: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qoder-sink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("simigo.sqlite3")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testEligibleTurnBecomesCommittedAndRetrievable() throws {
        let sink = ExternalTurnSink(databaseURL: dbURL)
        try sink.deliver([delivery(disposition: .eligible, turnID: "u-1")])

        XCTAssertEqual(try text("SELECT count(*) FROM chat_messages"), "2")
        XCTAssertEqual(
            try text("SELECT count(*) FROM chat_messages WHERE turn_state='committed'"), "2")
        XCTAssertEqual(
            try text("""
                SELECT count(*) FROM chat_messages
                WHERE source_kind='external' AND source_provider='qoder'
                  AND request_id IS NOT NULL AND verified_at IS NOT NULL
                """), "2")
        XCTAssertEqual(
            try text("SELECT group_concat(role) FROM (SELECT role FROM chat_messages ORDER BY role)"),
            "assistant,user")
    }

    func testUnreviewedTurnIsRecordedButNeverRetrievable() throws {
        let sink = ExternalTurnSink(databaseURL: dbURL)
        try sink.deliver([
            delivery(disposition: .requiresReview(.interrupted), turnID: "u-2")
        ])

        XCTAssertEqual(try text("SELECT count(*) FROM chat_messages"), "2")
        XCTAssertEqual(
            try text("SELECT count(*) FROM chat_messages WHERE turn_state='recorded'"), "2")
        XCTAssertEqual(
            try text("SELECT count(*) FROM chat_messages WHERE verified_at IS NOT NULL"), "0")
    }

    /// 压缩之后父链断裂，但「这条答案跟在这个问题后面」仍是文件事实：
    /// 采集的是历史，不该因为缺一条 parent 边就变成死信息。
    func testCompactionAttributedTurnIsStillRetrievable() throws {
        let sink = ExternalTurnSink(databaseURL: dbURL)
        try sink.deliver([
            delivery(disposition: .requiresReview(.fileOrderNoChain), turnID: "u-9"),
            delivery(disposition: .requiresReview(.fileOrderAfterCompaction), turnID: "u-10"),
        ])

        XCTAssertEqual(
            try text("SELECT count(*) FROM chat_messages WHERE turn_state='committed'"), "4")
    }

    /// 排队命令是人写的问题，答案完整 → 可检索；
    /// agent 自造的「继续」/ 通知 / 回调不是对话 → 只入库。
    func testQueuedCommandIsRetrievableButSelfPromptedTurnsAreNot() throws {
        let sink = ExternalTurnSink(databaseURL: dbURL)
        try sink.deliver([
            delivery(disposition: .deferredAutoTurn(.queuedCommand), turnID: "u-11"),
            delivery(disposition: .deferredAutoTurn(.continuationPrompt), turnID: "u-12"),
        ])

        XCTAssertEqual(
            try text("SELECT count(*) FROM chat_messages WHERE turn_state='committed'"), "2")
        XCTAssertEqual(
            try text("SELECT count(*) FROM chat_messages WHERE turn_state='recorded'"), "2")
    }

    func testSubagentTurnStaysInternal() throws {
        let sink = ExternalTurnSink(databaseURL: dbURL)
        try sink.deliver([delivery(disposition: .internalRecord, turnID: "u-3")])

        XCTAssertEqual(
            try text("SELECT count(*) FROM chat_messages WHERE turn_state='internal'"), "2")
        XCTAssertEqual(
            try text("SELECT count(*) FROM chat_messages WHERE verified_at IS NOT NULL"), "0")
    }

    func testReplayingTheSameCandidateDoesNotAppendRows() throws {
        let sink = ExternalTurnSink(databaseURL: dbURL)
        let batch = [delivery(disposition: .eligible, turnID: "u-4")]
        try sink.deliver(batch)
        try sink.deliver(batch)

        XCTAssertEqual(try text("SELECT count(*) FROM chat_messages"), "2")
        XCTAssertEqual(
            try text("SELECT count(*) FROM chat_messages WHERE turn_state='committed'"), "2")
    }

    func testDistinctTurnsInTheSameSessionStayDistinct() throws {
        let sink = ExternalTurnSink(databaseURL: dbURL)
        try sink.deliver([
            delivery(disposition: .eligible, turnID: "u-5"),
            delivery(disposition: .eligible, turnID: "u-6"),
        ])

        XCTAssertEqual(try text("SELECT count(*) FROM chat_messages"), "4")
        XCTAssertEqual(
            try text("SELECT count(DISTINCT request_id) FROM chat_messages"), "2")
    }

    /// 采集桥的目的地是 Information Space：另一个会话（本地 agent）检索时，
    /// 只有 `committed` 的那一轮能被引用，待复核的 `recorded` 轮进不来。
    func testCommittedCollectionIsCitableFromAnotherSession() throws {
        let sink = ExternalTurnSink(databaseURL: dbURL)
        try sink.deliver([
            delivery(disposition: .eligible, turnID: "u-7"),
            delivery(disposition: .requiresReview(.interrupted), turnID: "u-8"),
        ])

        let db = try ESISDatabase(url: dbURL)
        let resolution = try InformationLoop(database: db).resolve(
            .init(sessionID: "local-1", query: "回答"))
        let chatHits = resolution.hits.filter { $0.kind == "chat" }

        XCTAssertFalse(chatHits.isEmpty)
        XCTAssertTrue(
            chatHits.allSatisfy { $0.locator.contains("qoder:p-1/s-1#") },
            "只有采集会话里已提交的那一轮可被引用：\(chatHits.map(\.locator))")
        XCTAssertEqual(try text("SELECT count(*) FROM chat_messages WHERE turn_state='recorded'"), "2")
    }

    // MARK: - Fixtures

    private func delivery(
        disposition: TurnDisposition, turnID: String
    ) -> CandidateDelivery {
        let turn = CollectedTurnRecord(
            candidateID: "qoder:s-1:\(turnID):m-\(turnID)",
            identity: SourceIdentity(
                sourceSessionID: "s-1", sourceTurnID: turnID,
                sourceMessageID: "m-\(turnID)"),
            projectID: "p-1",
            sessionID: "s-1",
            isSubagent: disposition == .internalRecord,
            anchor: AnchorSummary(
                id: turnID, kind: .humanPrompt, segmentLine: 1,
                timestamp: nil, originKind: nil, isSidechain: false),
            promptRaw: "问题 \(turnID)",
            promptText: "问题 \(turnID)",
            promptRawDigest: "raw-\(turnID)",
            promptDigest: "prompt-\(turnID)",
            answerText: "回答 \(turnID)",
            answerDigest: "answer-\(turnID)",
            messageID: "m-\(turnID)",
            answerModel: "claude-sonnet-4",
            timestamp: "2026-11-05T16:00:00Z",
            relation: .parentChain,
            disposition: disposition,
            interrupted: false,
            apiErrorAttempts: 0,
            supersededEndTurns: [],
            firstSegmentLine: 1,
            lastSegmentLine: 2,
            finalizedBy: .nextAnchor)
        return CandidateDelivery(
            key: turn.identity.operationKey, kind: .turn, sequence: 0,
            event: .turn(turn))
    }

    private func text(_ sql: String) throws -> String {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &handle), SQLITE_OK)
        guard let handle else { return "" }
        defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(handle, sql, -1, &stmt, nil), SQLITE_OK)
        guard let stmt else { return "" }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return "" }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
    }
}
