import Foundation
import SQLite3
import XCTest

@testable import SimiGoRuntimeContract

/// P1 回归：幂等重放不得绕过失效校验。
/// 远端审查（现 main 301bc20 复核）：`settlementReuseOf` 只校依赖地址/边存在，
/// 不校旧结算 validity／上游闭包／检索一致；复用分支仍写 chat 行并返回 reused。
/// 修复后复用分支在事务内重校 `validatedSettlementDependencyObjectID`＋检索一致，
/// 失效或检索不符则拒重放（抛错、回滚、不写 chat 行）。
final class SettlementReplayInvalidationTests: XCTestCase {

    private let identity = SettlementIdentityBinding.Identity(
        model: "replay-model", tokenizer: "replay-tokenizer")

    private struct Fixture {
        let url: URL
        let db: ESISDatabase
        let loop: InformationLoop
        let root: URL
    }

    private func makeFixture(_ name: String) throws -> Fixture {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-replay-\(UUID().uuidString)-\(name).sqlite3")
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-replay-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("needle revision 0".utf8).write(to: root.appendingPathComponent("a.md"))
        try db.settleWorkRootContents(rootID: "work", rootURL: root, carryText: false)
        return Fixture(url: url, db: db, loop: InformationLoop(database: db), root: root)
    }

    private func cleanup(_ f: Fixture) {
        f.db.close()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: f.url.path + suffix))
        }
        try? FileManager.default.removeItem(at: f.root)
    }

    private func source() -> ESISDatabase.DeclaredSourceIdentity {
        .init(sourceType: "chat", sourceSessionID: "s1", sourceTurnID: "t1",
              sourceMessageID: "m1", sourceRevision: "1")
    }

    private func rawText(_ url: URL, _ sql: String) throws -> String {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let handle else { return "" }
        defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return ""
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return "" }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
    }

    private func assistantCount(_ f: Fixture) throws -> Int {
        Int(try rawText(f.url,
            "SELECT COUNT(*) FROM chat_messages WHERE session_id='s1' AND role='assistant';")) ?? -1
    }

    @discardableResult
    private func settleAnswer(
        _ f: Fixture, resolution: InformationLoop.Resolution?,
        state: String, key: String, userText: String
    ) throws -> InformationLoop.TurnSettlement {
        let userID = try f.db.appendChatMessage(
            sessionID: "s1", role: "user", content: userText, model: nil, createdAt: Date())
        return try f.loop.settleTurn(
            generatedText: "the answer", resolution: resolution, stateID: state,
            parentStateID: nil, position: 0, modelIdentity: identity.model,
            identity: identity, sessionID: "s1", summaryQuery: "needle",
            sourceIdentity: source(), operationKey: key,
            chatTurn: .init(sessionID: "s1", userMessageID: userID,
                            assistantText: "the answer", model: identity.model, createdAt: Date()))
    }

    /// 源失效后，同身份/键的幂等重放必须被拒，且不提交新的 chat 行。
    func testIdempotentSettlementRetryRejectsInvalidatedRetrieval() throws {
        let f = try makeFixture("invalidated")
        defer { cleanup(f) }
        let resolution = try f.loop.resolve(
            .init(sessionID: "s1", query: "needle", includeChat: false))
        let retrieval = resolution.retrievalSettlementID
        XCTAssertFalse(retrieval.isEmpty, "装置：须产生检索结算")

        let first = try settleAnswer(
            f, resolution: resolution, state: "S-1", key: "op-1", userText: "needle? first")
        XCTAssertFalse(first.reused)
        let answer = first.settlementID
        XCTAssertEqual(try f.db.settlementValidity(answer), "valid")
        XCTAssertEqual(try f.db.settlementValidity(retrieval), "valid")

        // 仍有效时的合法重放：返回旧结算并写一条 chat 行。
        let replay = try settleAnswer(
            f, resolution: resolution, state: "S-2", key: "op-1", userText: "needle? valid replay")
        XCTAssertTrue(replay.reused)
        XCTAssertEqual(replay.settlementID, answer)
        let committedBefore = try assistantCount(f)
        XCTAssertEqual(committedBefore, 2)

        // 源文件变更 → 失效检索结算，并沿依赖边级联到答案结算。item 作用域
        // 绑定不走文件级种子，显式按结算失效（级联其依赖方）。
        try Data("needle revision 1 changed".utf8).write(
            to: f.root.appendingPathComponent("a.md"), options: .atomic)
        let invalidated = try f.db.invalidateSettlement(retrieval)
        XCTAssertTrue(invalidated.contains(retrieval),
                      "装置：检索结算须被失效：\(invalidated)")
        XCTAssertTrue(invalidated.contains(answer),
                      "装置：答案结算须在级联闭包内，否则本轮另成因：\(invalidated)")
        XCTAssertNotEqual(try f.db.settlementValidity(retrieval), "valid")
        XCTAssertNotEqual(try f.db.settlementValidity(answer), "valid")

        // 失效后的幂等重放必须被拒，事务回滚，不写 chat 行。
        XCTAssertThrowsError(try settleAnswer(
            f, resolution: resolution, state: "S-3", key: "op-1", userText: "needle? stale replay"))
        XCTAssertEqual(try assistantCount(f), committedBefore,
                       "被拒的重放不得提交新的 assistant 行")
        XCTAssertNotEqual(try f.db.settlementValidity(answer), "valid")
    }

    /// 答案结算仍有效，但本次重放声明了不同的检索结算 → 拒（检索一致门）。
    func testIdempotentSettlementRetryRejectsMismatchedRetrieval() throws {
        let f = try makeFixture("mismatch")
        defer { cleanup(f) }
        let resolution = try f.loop.resolve(
            .init(sessionID: "s1", query: "needle", includeChat: false))
        let first = try settleAnswer(
            f, resolution: resolution, state: "S-1", key: "op-1", userText: "needle? first")
        let answer = first.settlementID
        XCTAssertEqual(try f.db.settlementValidity(answer), "valid")

        // 另一个仍有效的结算，冒充本次检索结算（同身份/键/答案，检索不符）。
        try f.db.recordExecutionState(
            id: "R-other", parentID: nil, modelIdentity: identity.model, position: 0,
            continuationID: UUID().uuidString, anchor: "anchor-other",
            lifecycle: "active", createdAt: Date())
        let settled = try SettlementAuthority.authorize(
            generatedText: "other retrieval",
            contractJSON: InformationLoop.chatResultContractJSON, verifiedBindings: [:])
        let otherRetrieval = try f.db.recordNativeSettlement(settled, stateID: "R-other")
        XCTAssertEqual(try f.db.settlementValidity(otherRetrieval), "valid")

        let mismatched = InformationLoop.Resolution(
            demandID: resolution.demandID, stateID: nil, reused: false, hits: [],
            inputDigest: "", resultSHA256: "", retrievalSettlementID: otherRetrieval,
            itemIDs: [], staleItemIDs: [])

        let committedBefore = try assistantCount(f)
        XCTAssertThrowsError(try settleAnswer(
            f, resolution: mismatched, state: "S-2", key: "op-1", userText: "needle? mismatch")) { error in
            guard case ESISDatabase.SettlementIdentityError.identityConflict = error else {
                return XCTFail("expected identityConflict, got \(error)")
            }
        }
        XCTAssertEqual(try assistantCount(f), committedBefore)
        XCTAssertEqual(try f.db.settlementValidity(answer), "valid",
                       "答案本身仍有效，拒的是检索不符")
    }

    /// 正控：仍有效的幂等重放（带 chat 行与 advancement）照常复用并提交 chat。
    func testValidIdempotentReplayWithChatTurnStillReuses() throws {
        let f = try makeFixture("valid")
        defer { cleanup(f) }
        let resolution = try f.loop.resolve(
            .init(sessionID: "s1", query: "needle", includeChat: false))
        let first = try settleAnswer(
            f, resolution: resolution, state: "S-1", key: "op-1", userText: "needle? first")
        XCTAssertFalse(first.reused)
        let before = try assistantCount(f)

        let replay = try settleAnswer(
            f, resolution: resolution, state: "S-2", key: "op-1", userText: "needle? valid replay")
        XCTAssertTrue(replay.reused)
        XCTAssertEqual(replay.settlementID, first.settlementID)
        XCTAssertEqual(try assistantCount(f), before + 1, "合法重放仍写一条 assistant 行")
        XCTAssertEqual(try f.db.settlementValidity(first.settlementID), "valid")
    }
}