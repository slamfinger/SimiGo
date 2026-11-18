import Foundation
import SQLite3
import XCTest
@testable import SimiGoRuntimeContract

/// E3：同一个幂等键只标识「同一次提交」，不标识「这一格可以换成任何正文」。
///
/// 事故原型（2026-11-14，真实使用中发生）：t54 的 assistant 正文第一次写成了
/// 字面量 `$(cat /tmp/reply54.txt)`，用真实正文重提时，旧实现直接返回既有行，
/// 既没报冲突也没写入新内容。这里把那一次事故固定成回归样本。
final class ExternalTurnCorrectionTests: XCTestCase {

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-correction-\(UUID().uuidString)-\(name).sqlite3")
    }

    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func open(_ name: String) throws -> (URL, ESISDatabase) {
        let url = tempURL(name)
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        return (url, db)
    }

    private func sha(_ text: String) -> String {
        NativeSHA256.hexDigest(Data(text.utf8))
    }

    private let wrongText = "$(cat /tmp/reply54.txt)"
    private let rightText = "这一轮验到了两条此前只有合成测试的正例：重开恢复会触发，协议升版只重投自己那份。"

    private func record(
        _ db: ESISDatabase, request: String = "t54",
        question: String = "我关闭 Codex 重新打开后进入，查看是否触发了 SessionStart",
        answer: String
    ) throws {
        try db.recordExternalTurn(
            sessionID: "s-t54", provider: "openai", requestID: request,
            userText: question, model: "gpt-5-codex", createdAt: Date())
        try db.recordExternalResponse(
            sessionID: "s-t54", provider: "openai", requestID: request,
            assistantText: answer, model: "gpt-5-codex", createdAt: Date())
    }

    /// Insert legacy derived state to verify correction replay still cleans rows
    /// left behind by older writers that predate the source-fingerprint contract.
    private func runRawSQL(_ url: URL, _ sql: String) throws {
        var handle: OpaquePointer?
        let openRC = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil)
        guard openRC == SQLITE_OK, let handle else {
            throw NSError(domain: "ExternalTurnCorrectionTests", code: Int(openRC))
        }
        defer { sqlite3_close_v2(handle) }
        var error: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &error)
        guard rc == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "sqlite rc=\(rc)"
            sqlite3_free(error)
            throw NSError(
                domain: "ExternalTurnCorrectionTests", code: Int(rc),
                userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func assistantRow(_ db: ESISDatabase) throws -> ESISDatabase.ChatMessageRow? {
        try db.listChatMessages(sessionID: "s-t54").first { $0.role == "assistant" }
    }

    private func assistantMessageID(_ db: ESISDatabase) throws -> Int64 {
        try XCTUnwrap(
            try db.chatTurnProvenance(sessionID: "s-t54", requestID: "t54")
                .first { $0.role == "assistant" }?.messageID)
    }

    /// 测试一 + 测试二：先记错误正文，再用不同正文重提同一幂等键。
    /// 必须明确冲突；旧行一个字节都不能变，也不能凭空多出更正记录。
    func testDifferentTextOnSameRequestIsRefusedNotSwallowed() throws {
        let (url, db) = try open("conflict")
        defer { db.close(); cleanup(url) }

        try record(db, answer: wrongText)
        let before = try assistantRow(db)
        let beforeID = try assistantMessageID(db)

        XCTAssertThrowsError(
            try db.recordExternalResponse(
                sessionID: "s-t54", provider: "openai", requestID: "t54",
                assistantText: rightText, model: "gpt-5-codex", createdAt: Date())
        ) { error in
            guard let conflict = error as? ESISDatabase.ExternalTurnConflict else {
                return XCTFail("expected ExternalTurnConflict, got \(error)")
            }
            XCTAssertEqual(conflict.role, "assistant")
            XCTAssertEqual(conflict.messageID, beforeID)
            XCTAssertEqual(conflict.storedDigest, self.sha(self.wrongText))
            XCTAssertEqual(conflict.incomingDigest, self.sha(self.rightText))
            XCTAssertTrue(
                conflict.description.contains("content-conflict"),
                "冲突信息要能被机器与人同时读出：\(conflict.description)")
        }

        let after = try assistantRow(db)
        XCTAssertEqual(after?.content, wrongText, "冲突不得改写已存正文")
        XCTAssertEqual(after?.contentSHA256, before?.contentSHA256)
        XCTAssertEqual(
            try db.listChatMessages(sessionID: "s-t54").count, 2, "冲突不得追加新行")
        XCTAssertTrue(
            try db.chatCorrections(sessionID: "s-t54", requestID: "t54", role: "assistant")
                .isEmpty,
            "被拒的提交不是更正，不能留下更正记录")
    }

    /// 同正文重试仍然幂等：返回同一行，也不制造更正。
    func testSameTextRetryStaysIdempotent() throws {
        let (url, db) = try open("idempotent")
        defer { db.close(); cleanup(url) }

        try record(db, answer: wrongText)
        let firstID = try assistantMessageID(db)
        let second = try db.recordExternalResponse(
            sessionID: "s-t54", provider: "openai", requestID: "t54",
            assistantText: wrongText, model: "gpt-5-codex", createdAt: Date())

        XCTAssertEqual(firstID, second)
        XCTAssertEqual(try db.listChatMessages(sessionID: "s-t54").count, 2)
    }

    /// 测试三：更正写入后——原记录可查、更正后的正文可读、两者关系留痕。
    func testCorrectionKeepsOriginalAndServesCorrectedText() throws {
        let (url, db) = try open("correct")
        defer { db.close(); cleanup(url) }

        try record(db, answer: wrongText)
        let messageID = try assistantMessageID(db)

        let correction = try db.correctChatMessage(
            sessionID: "s-t54", requestID: "t54", role: "assistant",
            correctedText: rightText, reason: "工具入参传成了 shell 替换字面量",
            actor: "codex")

        XCTAssertEqual(correction.messageID, messageID)
        XCTAssertEqual(correction.previousSHA256, sha(wrongText))
        XCTAssertEqual(correction.correctedSHA256, sha(rightText))

        // 读回的是更正后的正文与摘要。
        let row = try assistantRow(db)
        XCTAssertEqual(row?.content, rightText)
        XCTAssertEqual(row?.contentSHA256, sha(rightText))

        let provenance = try db.chatTurnProvenance(sessionID: "s-t54", requestID: "t54")
        XCTAssertEqual(provenance.first { $0.role == "assistant" }?.contentSHA256, sha(rightText))

        // 原记录没消失：更正行记着原 digest，而对象库里对象按 digest 命名、不可变。
        let records = try db.chatCorrections(
            sessionID: "s-t54", requestID: "t54", role: "assistant")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].previousSHA256, sha(wrongText))
        XCTAssertEqual(records[0].reason, "工具入参传成了 shell 替换字面量")
        XCTAssertEqual(records[0].actor, "codex")
        XCTAssertEqual(records[0].correctionID, correction.correctionID)
    }

    /// 测试四：同一次更正重试幂等；换正文就是另一次更正，不能冒充同一条。
    func testCorrectionRetryIsIdempotentAndNewTextIsAnotherCorrection() throws {
        let (url, db) = try open("retry")
        defer { db.close(); cleanup(url) }

        try record(db, answer: wrongText)
        let first = try db.correctChatMessage(
            sessionID: "s-t54", requestID: "t54", role: "assistant",
            correctedText: rightText, reason: "事故更正", actor: "codex")
        let retry = try db.correctChatMessage(
            sessionID: "s-t54", requestID: "t54", role: "assistant",
            correctedText: rightText, reason: "事故更正", actor: "codex")

        XCTAssertEqual(first.correctionID, retry.correctionID)
        XCTAssertEqual(
            try db.chatCorrections(sessionID: "s-t54", requestID: "t54", role: "assistant").count,
            1, "同一次更正重试不能留下第二条")

        let other = try db.correctChatMessage(
            sessionID: "s-t54", requestID: "t54", role: "assistant",
            correctedText: rightText + "（再说一遍）", reason: "事故更正", actor: "codex")
        XCTAssertNotEqual(other.correctionID, first.correctionID)
        XCTAssertEqual(
            try db.chatCorrections(sessionID: "s-t54", requestID: "t54", role: "assistant").count,
            2)
        XCTAssertEqual(try assistantRow(db)?.content, rightText + "（再说一遍）")
    }

    /// 更正正文会让这一轮的派生摘要失效。
    ///
    /// t54 的现场读数：正文已经更正为 8,878 B，`turn:…#t54` 仍然端出 604 B 占位符
    /// 时代的旧摘要，而且它还在候选发现路径里。派生行不是历史，正文换了它就该走。
    func testCorrectionInvalidatesStaleTurnDigest() throws {
        let (url, db) = try open("digest")
        defer { db.close(); cleanup(url) }

        try record(db, answer: wrongText)
        _ = try db.recordTurnIndex(
            sessionID: "s-t54", turnIndex: 54, requestID: "t54", at: Date())
        _ = try db.recordTurnDigest(
            sessionID: "s-t54", turnIndex: 54, digest: "旧摘要：占位符时代的结论",
            keywords: "占位符 摘要",
            expectedQuestionSHA256: TurnDigestText.sourceSHA256(
                "我关闭 Codex 重新打开后进入，查看是否触发了 SessionStart"),
            expectedAnswerSHA256: sha(wrongText))
        XCTAssertNotNil(try db.turnDigest(sessionID: "s-t54", turnIndex: 54))

        let correction = try db.correctChatMessage(
            sessionID: "s-t54", requestID: "t54", role: "assistant",
            correctedText: rightText, reason: "事故更正", actor: "codex")

        XCTAssertEqual(correction.invalidatedTurnIndex, 54)
        XCTAssertNil(
            try db.turnDigest(sessionID: "s-t54", turnIndex: 54),
            "正文换了，旧摘要必须失效，不能继续代表这一轮")
        XCTAssertEqual(try assistantRow(db)?.content, rightText, "正文仍在，被删的只是派生行")
        XCTAssertEqual(
            try db.chatTurnProvenance(sessionID: "s-t54", requestID: "t54")
                .first { $0.role == "assistant" }?.contentSHA256,
            sha(rightText))
    }

    /// 更正必须有理由与执行者：没有责任人的改写就是覆盖。
    func testCorrectionRequiresReasonAndActor() throws {
        let (url, db) = try open("reason")
        defer { db.close(); cleanup(url) }

        try record(db, answer: wrongText)
        XCTAssertThrowsError(
            try db.correctChatMessage(
                sessionID: "s-t54", requestID: "t54", role: "assistant",
                correctedText: rightText, reason: "   ", actor: "codex")
        ) { XCTAssertEqual($0 as? ESISDatabase.ChatCorrectionError, .emptyReason) }
        XCTAssertThrowsError(
            try db.correctChatMessage(
                sessionID: "s-t54", requestID: "t54", role: "assistant",
                correctedText: rightText, reason: "事故", actor: "")
        ) { XCTAssertEqual($0 as? ESISDatabase.ChatCorrectionError, .emptyActor) }
        XCTAssertThrowsError(
            try db.correctChatMessage(
                sessionID: "s-t54", requestID: "t99", role: "assistant",
                correctedText: rightText, reason: "事故", actor: "codex")
        ) { error in
            guard case .unknownMessage = (error as? ESISDatabase.ChatCorrectionError) else {
                return XCTFail("expected unknownMessage, got \(error)")
            }
        }
        XCTAssertEqual(try assistantRow(db)?.content, wrongText)
    }

    /// 重放同一次更正不是空操作：更正当时若没补算成（本地模型不在），摘要会
    /// 停在旧正文上；重放是让它再对齐一次的唯一入口。
    func testReplayingCorrectionReinvalidatesDerivedDigest() throws {
        let (url, db) = try open("replay-digest")
        defer { db.close(); cleanup(url) }

        try record(db, answer: wrongText)
        _ = try db.recordTurnIndex(
            sessionID: "s-t54", turnIndex: 54, requestID: "t54", at: Date())
        _ = try db.correctChatMessage(
            sessionID: "s-t54", requestID: "t54", role: "assistant",
            correctedText: rightText, reason: "事故更正", actor: "codex")
        // The public write path must reject an old-source result after correction.
        XCTAssertThrowsError(try db.recordTurnDigest(
            sessionID: "s-t54", turnIndex: 54, digest: "旧摘要", keywords: "旧",
            expectedQuestionSHA256: TurnDigestText.sourceSHA256(
                "我关闭 Codex 重新打开后进入，查看是否触发了 SessionStart"),
            expectedAnswerSHA256: sha(wrongText))) { error in
                guard case ESISDatabase.DatabaseError.staleTurnDigestSource = error else {
                    return XCTFail("expected stale-source rejection, got \(error)")
                }
            }

        // Simulate a legacy writer that already persisted a stale derived row:
        // correction replay must still remove it even though current writers cannot.
        try runRawSQL(url, """
        INSERT INTO turn_digests(
            session_id, turn_index, digest, keywords, created_at)
        VALUES('s-t54', 54, '旧摘要', '旧', '2026-11-18T00:00:00Z');
        """)

        let replay = try db.correctChatMessage(
            sessionID: "s-t54", requestID: "t54", role: "assistant",
            correctedText: rightText, reason: "事故更正", actor: "codex")

        XCTAssertEqual(replay.invalidatedTurnIndex, 54)
        XCTAssertNil(try db.turnDigest(sessionID: "s-t54", turnIndex: 54))
        XCTAssertEqual(try db.chatCorrections(
            sessionID: "s-t54", requestID: "t54", role: "assistant").count, 1,
            "重放不制造第二条更正记录")
    }

    /// 没更正过的行，提交与已存正文相同的文本：什么都不该发生，摘要不能被动。
    func testUnchangedTextOnNeverCorrectedRowLeavesDigestAlone() throws {
        let (url, db) = try open("noop")
        defer { db.close(); cleanup(url) }

        try record(db, answer: rightText)
        _ = try db.recordTurnIndex(
            sessionID: "s-t54", turnIndex: 54, requestID: "t54", at: Date())
        _ = try db.recordTurnDigest(
            sessionID: "s-t54", turnIndex: 54, digest: "现有摘要", keywords: "现有",
            expectedQuestionSHA256: TurnDigestText.sourceSHA256(
                "我关闭 Codex 重新打开后进入，查看是否触发了 SessionStart"),
            expectedAnswerSHA256: sha(rightText))

        let noop = try db.correctChatMessage(
            sessionID: "s-t54", requestID: "t54", role: "assistant",
            correctedText: rightText, reason: "例行核对", actor: "codex")

        XCTAssertNil(noop.invalidatedTurnIndex)
        XCTAssertNotNil(try db.turnDigest(sessionID: "s-t54", turnIndex: 54))
        XCTAssertTrue(try db.chatCorrections(
            sessionID: "s-t54", requestID: "t54", role: "assistant").isEmpty)
    }
}
