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
        let sql = "UPDATE is_objects SET content=x'00', byte_size=1 WHERE object_id='\\(objectID)'"
        var error: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &error)
        guard rc == SQLITE_OK, sqlite3_changes(handle) == 1 else {
            let message = error.map { String(cString: $0) } ?? "sqlite rc=\\(rc)"
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
        UPDATE settlements SET payload_object_id='\\(objectID)'
         WHERE settlement_id='\\(settlementID)';
        """
        var error: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &error)
        guard rc == SQLITE_OK, sqlite3_changes(handle) == 1 else {
            let message = error.map { String(cString: $0) } ?? "sqlite rc=\\(rc)"
            if let error { sqlite3_free(error) }
            throw NSError(
                domain: "InformationReuseTests", code: Int(rc),
                userInfo: [NSLocalizedDescriptionKey: message])
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

    func testExactRepeatInSameScopeIsServableWithoutWritingASettlement() throws {
        let source = try settleAnsweredTurn()
        let current = try currentReuseResolution()
        XCTAssertEqual(current.demandID, source.demandID,
                       "the source answer’s question, answer, and summary do not change its exact-repeat demand")
        let settlementsBefore = try db.count("settlements")

        let reuse = try XCTUnwrap(loop.reusableAnswer(
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
        XCTAssertNil(loop.reusableAnswer(
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
        XCTAssertNil(loop.reusableAnswer(
            sessionID: "info-a", query: query,
            expectedDemandID: changed.demandID, identity: identity))

        let replacement = try settleAnsweredTurn(
            sessionID: "info-a", stateID: "S-2",
            answer: "the exit moved to the east wing")
        let stableRepeat = try currentReuseResolution()
        XCTAssertEqual(stableRepeat.demandID, replacement.demandID,
                       "all prior exact answers stay excluded after a replacement is settled")
        let latest = try XCTUnwrap(loop.reusableAnswer(
            sessionID: "info-a", query: query,
            expectedDemandID: stableRepeat.demandID, identity: identity))
        XCTAssertEqual(latest.sourceStateID, "S-2")
        XCTAssertEqual(latest.text, "the exit moved to the east wing")
    }

    func testMissingCurrentDemandCannotReuseHistoricalAnswer() throws {
        try settleAnsweredTurn()
        XCTAssertNil(loop.reusableAnswer(
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

        XCTAssertNil(loop.reusableAnswer(
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

        XCTAssertNil(loop.reusableAnswer(
            sessionID: "info-a", query: query, expectedDemandID: resolution.demandID,
            identity: identity))
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
            let reuse = loop.reusableAnswer(
                sessionID: "info-a", query: query,
                expectedDemandID: source.demandID, identity: engine)
            XCTAssertEqual(reuse?.text, "the exit is north", label)
        }
    }

    /// Scope isolation: the same wording in a different information scope is a
    /// different demand and must not be answered from another scope's settlement.
    func testSameQuestionInAnotherScopeIsNotServable() throws {
        let source = try settleAnsweredTurn()

        XCTAssertNil(loop.reusableAnswer(
            sessionID: "info-b", query: query,
            expectedDemandID: source.demandID,
            identity: identity))
        // Case and whitespace are NOT normalized away — only exact repeats reuse.
        XCTAssertNil(loop.reusableAnswer(
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

        XCTAssertEqual(loop.reusableAnswer(
            sessionID: "info-a", query: query, expectedDemandID: resolution.demandID,
            identity: .absent)?.text, "the exit is in the east wing")
        XCTAssertEqual(loop.reusableAnswer(
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
}
