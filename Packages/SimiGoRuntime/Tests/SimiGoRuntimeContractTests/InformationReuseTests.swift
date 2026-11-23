import Foundation
import SQLite3
import XCTest
@testable import SimiGoRuntimeContract

/// The gate that decides whether a turn may be served from an already-settled
/// answer instead of a model call. These are the rejection cases: every one of
/// them must fall through to generation, never to a best-effort answer.
final class InformationReuseTests: XCTestCase {

    private var url: URL!
    private var db: ESISDatabase!
    private var loop: InformationLoop!

    private let identity = SettlementIdentityBinding.Identity(
        model: "reference-model", tokenizer: "reference-tokenizer")
    private let query = "where is the exit"

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-reuse-\(UUID().uuidString).sqlite3")
        db = try ESISDatabase(url: url)
        loop = InformationLoop(database: db)
        try db.runMigrations()
    }

    override func tearDownWithError() throws {
        db?.close()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: url.path + suffix))
        }
        db = nil; loop = nil; url = nil
    }

    /// One answered turn, exactly as the chat path settles it: resolve creates
    /// the demand and retrieval settlement, settleTurn records the answer and the
    /// advancement that ties the two together.
    @discardableResult
    private func settleAnsweredTurn(
        sessionID: String = "info-a", stateID: String = "S-1",
        answer: String = "the exit is north"
    ) throws -> InformationLoop.Resolution {
        let exclusions = try loop.answerReuseExclusions(
            sessionID: sessionID, query: query)
        let resolution = try loop.resolve(.init(
            sessionID: sessionID, query: query, includeChat: true,
            chatSessionIDs: [], excludeItemIDs: exclusions, limit: 5))
        XCTAssertFalse(resolution.demandID.isEmpty)
        XCTAssertFalse(resolution.retrievalSettlementID.isEmpty)
        // Match the product order: resolve first, then commit the user/assistant
        // chat rows and settle the generated answer against that exact demand.
        let userID = try db.appendChatMessage(
            sessionID: sessionID, role: "user", content: query,
            model: nil, createdAt: Date())
        try db.commitChatTurn(
            sessionID: sessionID, userMessageID: userID, assistantText: answer,
            model: nil, createdAt: Date())
        _ = try loop.settleTurn(
            generatedText: answer, resolution: resolution,
            stateID: stateID, parentStateID: nil, position: 1,
            modelIdentity: identity.model, identity: identity,
            sessionID: sessionID, summaryQuery: query)
        return resolution
    }

    private func currentReuseResolution(
        sessionID: String = "info-a"
    ) throws -> InformationLoop.Resolution {
        let exclusions = try loop.answerReuseExclusions(
            sessionID: sessionID, query: query)
        return try loop.resolve(.init(
            sessionID: sessionID, query: query, includeChat: true,
            chatSessionIDs: [], excludeItemIDs: exclusions, limit: 5))
    }

    private func corruptObject(_ objectID: String) throws {
        var handle: OpaquePointer?
        let openRC = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil)
        guard openRC == SQLITE_OK, let handle else {
            throw NSError(domain: "InformationReuseTests", code: Int(openRC))
        }
        defer { sqlite3_close_v2(handle) }
        // 源对象表是 write-once（触发器 ABORT），先摘触发器再改字节，
        // 与真实磁盘损坏绕开 SQL 层一致；字节数不变，CHECK 约束仍通过。
        let sql = """
        DROP TRIGGER IF EXISTS is_objects_append_only_update;
        UPDATE is_objects SET content=x'00', byte_size=1 WHERE object_id='\(objectID)';
        """
        var error: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &error)
        guard rc == SQLITE_OK, sqlite3_changes(handle) == 1 else {
            let message = error.map { String(cString: $0) } ?? "sqlite rc=\(rc)"
            if let error { sqlite3_free(error) }
            throw NSError(
                domain: "InformationReuseTests", code: Int(rc),
                userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func replaceSettlementPayloadObject(
        settlementID: String, objectID: String
    ) throws {
        var handle: OpaquePointer?
        let openRC = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil)
        guard openRC == SQLITE_OK, let handle else {
            throw NSError(domain: "InformationReuseTests", code: Int(openRC))
        }
        defer { sqlite3_close_v2(handle) }
        let sql = """
        UPDATE settlements SET payload_object_id='\(objectID)'
         WHERE settlement_id='\(settlementID)';
        """
        var error: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &error)
        guard rc == SQLITE_OK, sqlite3_changes(handle) == 1 else {
            let message = error.map { String(cString: $0) } ?? "sqlite rc=\(rc)"
            if let error { sqlite3_free(error) }
            throw NSError(
                domain: "InformationReuseTests", code: Int(rc),
                userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func recordTurnDigestFixture(
        sessionID: String = "digest-source"
    ) throws -> (
        sessionID: String, questionMessageID: Int64, answerMessageID: Int64,
        questionSHA256: String, answerSHA256: String,
        question: String, answer: String
    ) {
        let requestID = "digest-request-\(UUID().uuidString.lowercased())"
        let question = "Where should we evacuate?"
        let answer = "Use the west corridor and leave through the blue door."
        let questionMessageID = try db.appendChatMessage(
            sessionID: sessionID, role: "user", content: question,
            model: nil, createdAt: Date(), requestID: requestID)
        let answerMessageID = try db.commitChatTurn(
            sessionID: sessionID, userMessageID: questionMessageID,
            assistantText: answer, model: nil, createdAt: Date(), requestID: requestID)
        _ = try db.recordTurnIndex(
            sessionID: sessionID, turnIndex: 1, requestID: requestID)
        let rows = try db.chatIndexRows(sessionIDs: [sessionID])
        let questionRow = try XCTUnwrap(rows.first { $0.messageID == questionMessageID })
        let answerRow = try XCTUnwrap(rows.first { $0.messageID == answerMessageID })
        // Deliberately omit both message IDs: the read path must recover them
        // from the authoritative turn ledger, as the warm-digest writer does.
        try db.recordTurnDigest(
            sessionID: sessionID, turnIndex: 1,
            digest: "The emergency stairwell is reached through the west corridor.",
            keywords: "stairwell emergency west corridor",
            expectedQuestionSHA256: questionRow.contentSHA256,
            expectedAnswerSHA256: answerRow.contentSHA256)
        return (
            sessionID, questionMessageID, answerMessageID,
            questionRow.contentSHA256, answerRow.contentSHA256, question, answer)
    }

    func testTurnDigestHitCarriesVerifiedQASourceAnchors() throws {
        let source = try recordTurnDigestFixture()
        let resolution = try loop.resolve(.init(
            clientIdentityID: nil, sessionID: source.sessionID,
            query: "stairwell", includeChat: true, limit: 5))
        let hit = try XCTUnwrap(resolution.hits.first { $0.kind == "turn" })

        XCTAssertEqual(hit.itemID, "turn:\(source.sessionID)/1")
        XCTAssertEqual(hit.locator, "session:\(source.sessionID)#t1",
                       "keep the established public turn locator; exact message IDs are separate provenance fields")
        XCTAssertEqual(hit.sourceSessionID, source.sessionID)
        XCTAssertEqual(hit.sourceQuestionMessageID, source.questionMessageID)
        XCTAssertEqual(hit.sourceMessageID, source.answerMessageID)
        XCTAssertNotNil(hit.sourceQuestionObjectID)
        XCTAssertNotNil(hit.sourceObjectID)
        XCTAssertEqual(hit.sourceQuestionSHA256, source.questionSHA256)
        XCTAssertEqual(hit.sourceQuestionText, source.question)
        XCTAssertEqual(hit.lineText, source.answer,
                       "the digest is only the lookup index; the hit quotes original answer text")
        XCTAssertEqual(hit.sourceSHA256, source.answerSHA256)
        XCTAssertNotNil(hit.indexSHA256)

        let context = loop.contextBlock(resolution)
        XCTAssertTrue(context.contains("[indexed-by:turn-digest"))
        XCTAssertTrue(context.contains("原始问题节选：\(source.question)"))
        XCTAssertTrue(context.contains("原始回答节选：\(source.answer)"))
        XCTAssertFalse(context.contains("The emergency stairwell is reached"),
                       "the retrieval digest must not be injected as source text")
        XCTAssertTrue(context.contains("question=session:\(source.sessionID)#\(source.questionMessageID)"))
        XCTAssertTrue(context.contains("answer=session:\(source.sessionID)#\(source.answerMessageID)"))
    }

    func testTurnDigestWithoutCurrentSourceReceiptIsNotCitable() throws {
        let source = try recordTurnDigestFixture()
        try execSQL("""
        DELETE FROM turn_digest_sources
         WHERE session_id='\(source.sessionID)' AND turn_index=1;
        """)
        let resolution = try loop.resolve(.init(
            clientIdentityID: nil, sessionID: source.sessionID,
            query: "stairwell", includeChat: true, limit: 5))
        XCTAssertFalse(
            resolution.hits.contains { $0.kind == "turn" },
            "a digest without its Q&A source receipt must fail closed")
    }

    func testTurnDigestRejectsCorruptOriginalAnswerObject() throws {
        let source = try recordTurnDigestFixture()
        let demand = InformationLoop.Demand(
            clientIdentityID: nil, sessionID: source.sessionID,
            query: "stairwell", includeChat: true, limit: 5)
        let resolution = try loop.resolve(demand)
        let hit = try XCTUnwrap(resolution.hits.first { $0.kind == "turn" })
        let objectID = try XCTUnwrap(hit.sourceObjectID)
        try corruptObject(objectID)

        XCTAssertThrowsError(try loop.resolve(demand)) { error in
            guard let databaseError = error as? ESISDatabase.DatabaseError,
                  case .sourceChangedWhileBeingRead = databaseError else {
                return XCTFail("expected corrupt source object to be rejected, got: \(error)")
            }
        }
    }

    func testInformationRetrievalPayloadPropagatesCorruptObjectRead() throws {
        let resolution = try loop.resolve(.init(
            sessionID: "info-a", query: query, includeChat: false, limit: 5))
        let receipt = try XCTUnwrap(try db.settlementReceipt(resolution.retrievalSettlementID))
        let objectID = try XCTUnwrap(receipt.payloadObjectID)
        try corruptObject(objectID)

        XCTAssertThrowsError(try db.informationRetrievalPayload(demandID: resolution.demandID),
                             "a corrupt retrieval object is a persistence failure, not a cache miss")
    }


    func testReusableAnswerPropagatesCorruptSettlementObjectRead() throws {
        let resolution = try settleAnsweredTurn()
        let answer = try XCTUnwrap(try db.answeredDemand(sessionID: "info-a", query: query))
        let receipt = try XCTUnwrap(try db.settlementReceipt(answer.answerSettlementID))
        let objectID = try XCTUnwrap(receipt.payloadObjectID)
        try corruptObject(objectID)

        XCTAssertThrowsError(try loop.reusableAnswer(
            sessionID: "info-a",
            query: query,
            expectedDemandID: resolution.demandID,
            identity: identity),
            "a corrupt answer receipt is a persistence error, not a cache miss")
    }

    func testAnswerReuseExclusionsRejectReceiptWithoutAnswerContent() throws {
        _ = try settleAnsweredTurn()
        let answer = try XCTUnwrap(try db.answeredDemand(sessionID: "info-a", query: query))
        let malformedObjectID = try db.writeObject(Data("{}".utf8))
        try replaceSettlementPayloadObject(
            settlementID: answer.answerSettlementID, objectID: malformedObjectID)

        XCTAssertThrowsError(try loop.answerReuseExclusions(
            sessionID: "info-a", query: query),
            "an answered demand with an unreadable receipt shape must not silently re-enter chat rows")
    }

    /// t9 option 3 (self-reference exclusion): a tool loop commits its question
    /// and narration mid-demand without settling. Those rows are the demand's own
    /// output, not new knowledge — excluding them keeps the candidate (and thus the
    /// frozen KV prefix) byte-stable across continuation legs. Before this fix the
    /// unanswered early-return left them in, every leg's retrieval drifted, refresh
    /// rewrote the frozen block, and the prefix cold-prefilled (accept11:
    /// frozenRefresh=1 per leg, commonPrefix 681B, ttft 2.4-3.1s). External
    /// information must still move the demand so the reuse gate stays fail-closed.
    func testUnansweredOwnQuestionAndNarrationAreExcludedAndDoNotDriftTheDemand() throws {
        let session = "info-loop"
        let before = try loop.resolve(.init(
            sessionID: session, query: query, includeChat: true,
            chatSessionIDs: [], excludeItemIDs: [], limit: 5))

        // The turn commits its own question + tool-loop narration but settles
        // nothing (the producedToolCalls path): no answered demand exists.
        let userID = try db.appendChatMessage(
            sessionID: session, role: "user", content: query,
            model: nil, createdAt: Date())
        try db.commitChatTurn(
            sessionID: session, userMessageID: userID,
            assistantText: "I will look for the exit now.", model: nil, createdAt: Date())
        XCTAssertNil(try db.answeredDemand(sessionID: session, query: query),
                     "the tool loop has not settled an answer")

        let exclusions = try loop.answerReuseExclusions(sessionID: session, query: query)
        for row in try db.chatIndexRows(sessionIDs: [session]) {
            XCTAssertTrue(exclusions.contains(row.itemID),
                          "the demand's own \(row.role) row must be excluded even unanswered: \(row.itemID)")
        }
        let after = try loop.resolve(.init(
            sessionID: session, query: query, includeChat: true,
            chatSessionIDs: [], excludeItemIDs: exclusions, limit: 5))
        XCTAssertEqual(after.demandID, before.demandID,
                       "own question + narration must not drift the demand (KV prefix stability)")

        // Genuine external information still moves the demand (#7 freshness).
        let externalUser = try db.appendChatMessage(
            sessionID: "info-loop-external", role: "user",
            content: "The exit location changed", model: nil, createdAt: Date())
        try db.commitChatTurn(
            sessionID: "info-loop-external", userMessageID: externalUser,
            assistantText: "The exit is now in the east wing.", model: nil, createdAt: Date())
        let moved = try loop.resolve(.init(
            sessionID: session, query: query, includeChat: true,
            chatSessionIDs: [], excludeItemIDs: exclusions, limit: 5))
        XCTAssertNotEqual(moved.demandID, before.demandID,
                          "external information must still change the demand")
    }

    /// build21 acceptance (session 95841d, 2026-11-23): prior turns from the
    /// injecting session were re-injected as external settled fragments. By
    /// turns 7/8, 11-12 of 30 fragments were the session's own Q&A/digests,
    /// framing a new question as already answered. Exclude the whole session;
    /// external sessions must still affect the demand freshness basis.
    func testPriorTurnsOfInjectingSessionAreExcludedFromInjection() throws {
        let session = "info-self"
        let priorUser = try db.appendChatMessage(
            sessionID: session, role: "user", content: "where is the exit in the old wing",
            model: nil, createdAt: Date())
        try db.commitChatTurn(
            sessionID: session, userMessageID: priorUser,
            assistantText: "the exit in the old wing is north", model: nil, createdAt: Date())
        try db.recordTurnDigest(
            sessionID: session, turnIndex: 1,
            digest: "where is the exit in the old wing — the exit is north", keywords: "exit north")

        let exclusions = try loop.answerReuseExclusions(sessionID: session, query: query)
        for row in try db.chatIndexRows(sessionIDs: [session]) {
            XCTAssertTrue(exclusions.contains(row.itemID),
                          "own prior chat row must be excluded: \(row.itemID)")
        }
        XCTAssertTrue(exclusions.contains("turn:\(session)/1"),
                      "own prior turn digest must be excluded")

        let resolution = try loop.resolve(.init(
            sessionID: session, query: query, includeChat: true,
            chatSessionIDs: [], excludeItemIDs: exclusions, limit: 30))
        for hit in resolution.hits {
            XCTAssertFalse(hit.itemID.hasPrefix("chat:\(session)/"),
                           "self chat fragment leaked into injection: \(hit.itemID)")
            XCTAssertFalse(hit.itemID.hasPrefix("turn:\(session)/"),
                           "self turn digest leaked into injection: \(hit.itemID)")
        }

        // Additional turns from this session do not drift the demand. A new
        // external session still must change it (the preceding test covers that).
        let secondUser = try db.appendChatMessage(
            sessionID: session, role: "user", content: "where is the exit in the new wing",
            model: nil, createdAt: Date())
        try db.commitChatTurn(
            sessionID: session, userMessageID: secondUser,
            assistantText: "the exit in the new wing is east", model: nil, createdAt: Date())
        try db.recordTurnDigest(
            sessionID: session, turnIndex: 2,
            digest: "where is the exit in the new wing — the exit is east", keywords: "exit east")
        let grownExclusions = try loop.answerReuseExclusions(sessionID: session, query: query)
        let grown = try loop.resolve(.init(
            sessionID: session, query: query, includeChat: true,
            chatSessionIDs: [], excludeItemIDs: grownExclusions, limit: 30))
        XCTAssertEqual(grown.demandID, resolution.demandID,
                       "more self turns must not drift the demand (KV prefix stability)")
    }

    func testExactRepeatInSameScopeIsServableWithoutWritingASettlement() throws {
        let source = try settleAnsweredTurn()
        let current = try currentReuseResolution()
        XCTAssertEqual(current.demandID, source.demandID,
                       "the source answer’s question, answer, and summary do not change its exact-repeat demand")
        let settlementsBefore = try db.count("settlements")

        let reuse = try XCTUnwrap(try loop.reusableAnswer(
            sessionID: "info-a", query: query,
            expectedDemandID: current.demandID, identity: identity))
        XCTAssertEqual(reuse.text, "the exit is north")
        XCTAssertEqual(reuse.sessionID, "info-a")
        XCTAssertEqual(reuse.query, query)
        XCTAssertFalse(reuse.settlementID.isEmpty)
        XCTAssertFalse(reuse.demandID.isEmpty)
        XCTAssertEqual(reuse.sourceStateID, "S-1")
        // Serving a reuse is a read: it never adds a settlement of its own.
        XCTAssertEqual(try db.count("settlements"), settlementsBefore)
    }


    func testChangedCurrentDemandCannotReuseHistoricalAnswer() throws {
        let original = try settleAnsweredTurn()
        let changed = try loop.resolve(.init(
            sessionID: "info-a",
            requestIdentity: "new-turn-after-scope-change",
            query: query, includeChat: false, limit: 5))

        XCTAssertNotEqual(changed.demandID, original.demandID)
        XCTAssertNil(try loop.reusableAnswer(
            sessionID: "info-a", query: query,
            expectedDemandID: changed.demandID, identity: identity))
    }

    func testNewSharedChatInformationInvalidatesReuseButReplacementStaysStable() throws {
        let original = try settleAnsweredTurn()
        XCTAssertEqual(try currentReuseResolution().demandID, original.demandID)

        let externalSession = "new-information-\(UUID().uuidString)"
        let externalUser = try db.appendChatMessage(
            sessionID: externalSession, role: "user",
            content: "The exit location changed", model: nil, createdAt: Date())
        try db.commitChatTurn(
            sessionID: externalSession, userMessageID: externalUser,
            assistantText: "The exit is now in the east wing.",
            model: nil, createdAt: Date())

        let changed = try currentReuseResolution()
        XCTAssertNotEqual(changed.demandID, original.demandID,
                          "new committed information in another session changes shared-space demand")
        XCTAssertNil(try loop.reusableAnswer(
            sessionID: "info-a", query: query,
            expectedDemandID: changed.demandID, identity: identity))

        let replacement = try settleAnsweredTurn(
            sessionID: "info-a", stateID: "S-2",
            answer: "the exit moved to the east wing")
        let stableRepeat = try currentReuseResolution()
        XCTAssertEqual(stableRepeat.demandID, replacement.demandID,
                       "all prior exact answers stay excluded after a replacement is settled")
        let latest = try XCTUnwrap(try loop.reusableAnswer(
            sessionID: "info-a", query: query,
            expectedDemandID: stableRepeat.demandID, identity: identity))
        XCTAssertEqual(latest.sourceStateID, "S-2")
        XCTAssertEqual(latest.text, "the exit moved to the east wing")
    }

    func testMissingCurrentDemandCannotReuseHistoricalAnswer() throws {
        try settleAnsweredTurn()
        XCTAssertNil(try loop.reusableAnswer(
            sessionID: "info-a", query: query, identity: identity))
    }

    /// Rule 1: nothing was ever answered for this question.
    func testUnansweredDemandIsNotServable() throws {
        try db.recordExecutionState(
            id: "S-1", parentID: nil, modelIdentity: identity.model,
            position: 1, continuationID: "C-1", anchor: "a1",
            lifecycle: "active", createdAt: Date())
        // A demand resolved but never settled: retrieval alone is not an answer.
        let resolution = try loop.resolve(.init(
            sessionID: "info-a", query: query, includeChat: false, limit: 5))

        XCTAssertNil(try loop.reusableAnswer(
            sessionID: "info-a", query: query, expectedDemandID: resolution.demandID,
            identity: identity))
    }

    /// Rule 2 (and the dependency rule with it): once the settled chain is
    /// invalidated, the question falls back to generation. Invalidation cascades
    /// along the recorded dependency edge, so this asserts the closed outcome
    /// rather than isolating one of the two settlements.
    func testInvalidatedSettlementChainIsNotServable() throws {
        let resolution = try settleAnsweredTurn()
        let answer = try XCTUnwrap(
            try db.answeredDemand(sessionID: "info-a", query: query))
        _ = try db.invalidateSettlement(resolution.retrievalSettlementID)
        XCTAssertEqual(
            try db.settlementValidity(answer.answerSettlementID), "invalid")

        XCTAssertNil(try loop.reusableAnswer(
            sessionID: "info-a", query: query, expectedDemandID: resolution.demandID,
            identity: identity))
    }

    func testAnsweredDemandRechecksSettlementValidityInsideTransaction() throws {
        let turn = try loop.settleTurn(
            generatedText: "the exit is north",
            resolution: nil,
            stateID: "S-ANSWERED-RACE",
            parentStateID: nil,
            position: 1,
            modelIdentity: identity.model,
            identity: identity,
            sessionID: nil,
            summaryQuery: nil)

        // Force the race window: the settlement is valid when the caller starts
        // publishing, but source invalidation commits before the write transaction
        // acquires its lock. Publication must re-read validity under that lock.
        let database = try XCTUnwrap(db)
        database.beforeAnsweredDemandTransactionForTesting = { [weak database] in
            _ = try? database?.invalidateSettlement(turn.settlementID)
        }

        XCTAssertThrowsError(try db.recordAnsweredDemand(
            stateID: turn.stateID,
            sessionID: "info-a",
            query: query,
            settlementID: turn.settlementID,
            actions: ["test"]
        )) { error in
            guard let databaseError = error as? ESISDatabase.DatabaseError,
                  case .sql(let detail) = databaseError else {
                return XCTFail("expected invalid-settlement refusal, got: \(error)")
            }
            XCTAssertTrue(detail.contains("not valid"), detail)
        }
        XCTAssertEqual(try db.settlementValidity(turn.settlementID), "invalid")
        XCTAssertNil(try db.answeredDemand(sessionID: "info-a", query: query))
        XCTAssertEqual(try db.count("information_demands"), 0)
    }


    func testAnsweredDemandRejectsSettlementBoundToDifferentState() throws {
        _ = try settleAnsweredTurn()
        let answer = try XCTUnwrap(try db.answeredDemand(sessionID: "info-a", query: query))

        XCTAssertThrowsError(try db.recordAnsweredDemand(
            stateID: "S-WRONG",
            sessionID: "info-other",
            query: query,
            settlementID: answer.answerSettlementID,
            actions: ["test"]
        )) { error in
            guard let databaseError = error as? ESISDatabase.DatabaseError,
                  case .sql(let detail) = databaseError else {
                return XCTFail("expected settlement/state mismatch, got: \(error)")
            }
            XCTAssertTrue(detail.contains("bound to state"), detail)
        }
        XCTAssertNil(try db.answeredDemand(sessionID: "info-other", query: query))
    }

    /// A settled answer is a semantic result, not a KV state: producer identity
    /// is provenance, never a reuse condition (P2 §5.32). A different engine —
    /// named differently, differently tokenized, or unnamed — reads the same
    /// settled text, and the consuming model is recorded on the reuse row.
    func testDifferentEngineIdentityStillServesSettledText() throws {
        let source = try settleAnsweredTurn()
        let engines: [(String, SettlementIdentityBinding.Identity)] = [
            ("other model", .init(model: "other-model", tokenizer: identity.tokenizer)),
            ("other tokenizer", .init(model: identity.model, tokenizer: "other-tokenizer")),
            ("unspecified", .init(model: "unspecified", tokenizer: "unspecified")),
            ("absent", .absent),
        ]
        for (label, engine) in engines {
            let reuse = try loop.reusableAnswer(
                sessionID: "info-a", query: query,
                expectedDemandID: source.demandID, identity: engine)
            XCTAssertEqual(reuse?.text, "the exit is north", label)
        }
    }

    /// Scope isolation: the same wording in a different information scope is a
    /// different demand and must not be answered from another scope's settlement.
    func testSameQuestionInAnotherScopeIsNotServable() throws {
        let source = try settleAnsweredTurn()

        XCTAssertNil(try loop.reusableAnswer(
            sessionID: "info-b", query: query,
            expectedDemandID: source.demandID,
            identity: identity))
        // Case and whitespace are NOT normalized away — only exact repeats reuse.
        XCTAssertNil(try loop.reusableAnswer(
            sessionID: "info-a", query: "Where is the exit?",
            expectedDemandID: source.demandID,
            identity: identity))
    }

    /// A producer that recorded no identity leaves no claim to compare — but it
    /// still leaves a settled result, and that result stays rereadable. The
    /// comparison itself is unchanged; this path simply no longer consults it.
    func testAbsentProducerIdentityStillServesWhileEvaluateBlocks() throws {
        let resolution = try loop.resolve(.init(
            sessionID: "info-a", query: query, includeChat: false, limit: 5))
        _ = try loop.settleTurn(
            generatedText: "the exit is in the east wing", resolution: resolution,
            stateID: "S-absent", parentStateID: nil, position: 1,
            modelIdentity: "unresolved", identity: .absent,
            sessionID: "info-a", summaryQuery: query)

        XCTAssertEqual(try loop.reusableAnswer(
            sessionID: "info-a", query: query, expectedDemandID: resolution.demandID,
            identity: .absent)?.text, "the exit is in the east wing")
        XCTAssertEqual(try loop.reusableAnswer(
            sessionID: "info-a", query: query, expectedDemandID: resolution.demandID,
            identity: identity)?.text, "the exit is in the east wing")

        // evaluate() still refuses: it remains the comparison a task opts into
        // when it declares identity to be a semantic dependency.
        let absentOnly = SettlementIdentityBinding.evaluate(
            recorded: SettlementIdentityBinding.bindings(for: .absent),
            consumer: .absent)
        XCTAssertEqual(absentOnly.status, .blocked)
        XCTAssertEqual(
            absentOnly.code,
            SettlementIdentityBinding.Refusal.consumerAbsent.rawValue)
        let emptyRecorded = SettlementIdentityBinding.evaluate(
            recorded: [:], consumer: identity)
        XCTAssertEqual(emptyRecorded.status, .blocked)
        XCTAssertEqual(
            emptyRecorded.code,
            SettlementIdentityBinding.Refusal.modelAbsent.rawValue)
    }
    
    func testReuseEventRetryIsIdempotentOnlyForTheSameSourceAndScope() throws {
        let resolution = try settleAnsweredTurn()
        let answer = try XCTUnwrap(try db.answeredDemand(sessionID: "info-a", query: query))
        let first = try db.recordInformationReuse(
            sourceSettlementID: answer.answerSettlementID,
            sourceStateID: "S-1",
            demandID: resolution.demandID,
            sessionID: "info-a",
            query: query)
        let exactRetry = try db.recordInformationReuse(
            sourceSettlementID: answer.answerSettlementID,
            sourceStateID: "S-1",
            demandID: resolution.demandID,
            sessionID: "info-a",
            query: query)
        XCTAssertEqual(exactRetry, first, "an exact retry remains idempotent")

        let other = try loop.settleTurn(
            generatedText: "a different settled value",
            resolution: nil,
            stateID: "S-OTHER",
            parentStateID: nil,
            position: 1,
            modelIdentity: identity.model,
            identity: identity,
            sessionID: nil,
            summaryQuery: nil)
        XCTAssertThrowsError(try db.recordInformationReuse(
            sourceSettlementID: other.settlementID,
            sourceStateID: other.stateID,
            demandID: resolution.demandID,
            sessionID: "info-a",
            query: query)) { error in
                XCTAssertEqual(
                    error as? ESISDatabase.InformationReuseError,
                    .idempotencyConflict(resolution.demandID))
            }

        XCTAssertThrowsError(try db.recordInformationReuse(
            sourceSettlementID: answer.answerSettlementID,
            sourceStateID: "S-1",
            demandID: resolution.demandID,
            sessionID: "different-session",
            query: query)) { error in
                XCTAssertEqual(
                    error as? ESISDatabase.InformationReuseError,
                    .idempotencyConflict(resolution.demandID))
            }
        XCTAssertEqual(try db.informationReuseEvent(demandID: resolution.demandID), first)
    }


    func testReuseEventRejectsSourceStateThatDoesNotOwnSettlement() throws {
        let resolution = try settleAnsweredTurn()
        let answer = try XCTUnwrap(try db.answeredDemand(sessionID: "info-a", query: query))

        XCTAssertThrowsError(try db.recordInformationReuse(
            sourceSettlementID: answer.answerSettlementID,
            sourceStateID: "S-WRONG",
            demandID: resolution.demandID,
            sessionID: "info-a",
            query: query)) { error in
                XCTAssertEqual(
                    error as? ESISDatabase.InformationReuseError,
                    .sourceStateMismatch(answer.answerSettlementID))
            }
        XCTAssertNil(try db.informationReuseEvent(demandID: resolution.demandID))
    }

    func testIdempotentReuseRetryRechecksSourceValidity() throws {
        let resolution = try settleAnsweredTurn()
        let answer = try XCTUnwrap(try db.answeredDemand(sessionID: "info-a", query: query))
        let first = try db.recordInformationReuse(
            sourceSettlementID: answer.answerSettlementID,
            sourceStateID: "S-1",
            demandID: resolution.demandID,
            sessionID: "info-a",
            query: query)

        _ = try db.invalidateSettlement(answer.answerSettlementID)
        XCTAssertThrowsError(try db.recordInformationReuse(
            sourceSettlementID: answer.answerSettlementID,
            sourceStateID: "S-1",
            demandID: resolution.demandID,
            sessionID: "info-a",
            query: query)) { error in
                XCTAssertEqual(
                    error as? ESISDatabase.InformationReuseError,
                    .sourceNotValid(answer.answerSettlementID))
            }
        XCTAssertEqual(try db.informationReuseEvent(demandID: resolution.demandID), first)
    }

    // MARK: - Settlement demand rebind (build21 fix B)

    private func execSQL(_ sql: String) throws {
        var handle: OpaquePointer?
        let openRC = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil)
        guard openRC == SQLITE_OK, let handle else {
            throw NSError(domain: "InformationReuseTests", code: Int(openRC))
        }
        defer { sqlite3_close_v2(handle) }
        var error: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &error)
        guard rc == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "sqlite rc=\(rc)"
            if let error { sqlite3_free(error) }
            throw NSError(domain: "InformationReuseTests", code: Int(rc),
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    /// A newer RESOLVED demand for the same question, as a retry's retrieval
    /// would commit. The rebind guard reads only the demand state, so the row
    /// needs no retrieval settlement linkage here.
    private func makeCandidateDemand(
        sessionID: String, like rendered: InformationLoop.Resolution
    ) throws -> String {
        let d2 = "rebind-\(UUID().uuidString)"
        try execSQL("""
        INSERT INTO information_demands(
            demand_id, session_id, continuation_point, query,
            required_item_ids_json, pending_obligations_json, continuation_conditions_json,
            input_digest, state, created_at)
        VALUES('\(d2)', '\(sessionID)', 'information-retrieval', 'where is the exit',
            '[]', '[]', '[]', '\(rendered.inputDigest)', 'RESOLVED', '0');
        """)
        return d2
    }

    private func candidate(
        _ d2: String, like rendered: InformationLoop.Resolution,
        resultSHA256: String? = nil
    ) -> InformationLoop.Resolution {
        InformationLoop.Resolution(
            demandID: d2, stateID: rendered.stateID, reused: false, hits: rendered.hits,
            inputDigest: rendered.inputDigest,
            resultSHA256: resultSHA256 ?? rendered.resultSHA256,
            retrievalSettlementID: rendered.retrievalSettlementID, itemIDs: rendered.itemIDs)
    }

    /// The mid-generation race: a retry supersedes the rendered demand; the
    /// current candidate is still RESOLVED on a byte-identical retrieval basis,
    /// so settlement re-binds to it instead of discarding the answer.
    func testSettlementRebindsSupersededRenderedDemand() throws {
        let session = "info-rebind"
        let rendered = try currentReuseResolution(sessionID: session)
        let d2 = try makeCandidateDemand(sessionID: session, like: rendered)
        try execSQL("UPDATE information_demands SET state='SUPERSEDED' WHERE demand_id='\(rendered.demandID)';")
        let (res, rebound) = try loop.settlementResolution(
            rendered: rendered, candidate: candidate(d2, like: rendered))
        XCTAssertTrue(rebound, "superseded rendered + RESOLVED candidate on same basis must rebind")
        XCTAssertEqual(res.demandID, d2)
    }

    /// No supersede (rendered still RESOLVED, no candidate) → keep rendered.
    func testSettlementKeepsRenderedWhenNotSuperseded() throws {
        let rendered = try currentReuseResolution(sessionID: "info-keep")
        let (res, rebound) = try loop.settlementResolution(rendered: rendered, candidate: nil)
        XCTAssertFalse(rebound)
        XCTAssertEqual(res.demandID, rendered.demandID)
    }

    /// Candidate also superseded → fail closed to the rendered demand.
    func testSettlementFailsClosedWhenCandidateAlsoSuperseded() throws {
        let session = "info-fc"
        let rendered = try currentReuseResolution(sessionID: session)
        let d2 = try makeCandidateDemand(sessionID: session, like: rendered)
        try execSQL("UPDATE information_demands SET state='SUPERSEDED' WHERE demand_id='\(d2)';")
        let (res, rebound) = try loop.settlementResolution(
            rendered: rendered, candidate: candidate(d2, like: rendered))
        XCTAssertFalse(rebound, "a superseded candidate must fail closed")
        XCTAssertEqual(res.demandID, rendered.demandID)
    }

    /// A different retrieval content basis must never rebind.
    func testSettlementFailsClosedOnDifferentBasis() throws {
        let session = "info-basis"
        let rendered = try currentReuseResolution(sessionID: session)
        let d2 = try makeCandidateDemand(sessionID: session, like: rendered)
        try execSQL("UPDATE information_demands SET state='SUPERSEDED' WHERE demand_id='\(rendered.demandID)';")
        let (res, rebound) = try loop.settlementResolution(
            rendered: rendered, candidate: candidate(d2, like: rendered, resultSHA256: "divergent-basis"))
        XCTAssertFalse(rebound, "a different retrieval basis must fail closed")
        XCTAssertEqual(res.demandID, rendered.demandID)
    }
}
