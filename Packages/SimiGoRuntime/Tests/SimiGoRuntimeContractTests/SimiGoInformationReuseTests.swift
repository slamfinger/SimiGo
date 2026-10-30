import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// The gate that decides whether a turn may be served from an already-settled
/// answer instead of a model call. These are the rejection cases: every one of
/// them must fall through to generation, never to a best-effort answer.
final class SimiGoInformationReuseTests: XCTestCase {

    private var url: URL!
    private var db: SimiGoESISDatabase!
    private var loop: SimiGoInformationLoop!

    private let identity = SimiGoSettlementIdentityBinding.Identity(
        model: "reference-model", tokenizer: "reference-tokenizer")
    private let query = "where is the exit"

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-reuse-\(UUID().uuidString).sqlite3")
        db = try SimiGoESISDatabase(url: url)
        loop = SimiGoInformationLoop(database: db)
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
        sessionID: String = "info-a", stateID: String = "S-1"
    ) throws -> SimiGoInformationLoop.Resolution {
        let resolution = try loop.resolve(.init(
            sessionID: sessionID, query: query, includeChat: false, limit: 5))
        XCTAssertFalse(resolution.demandID.isEmpty)
        XCTAssertFalse(resolution.retrievalSettlementID.isEmpty)
        _ = try loop.settleTurn(
            generatedText: "the exit is north", resolution: resolution,
            stateID: stateID, parentStateID: nil, position: 1,
            modelIdentity: identity.model, identity: identity,
            sessionID: sessionID, summaryQuery: query)
        return resolution
    }

    func testExactRepeatInSameScopeIsServableWithoutWritingASettlement() throws {
        try settleAnsweredTurn()
        let settlementsBefore = try db.count("settlements")

        let reuse = try XCTUnwrap(loop.reusableAnswer(
            sessionID: "info-a", query: query, identity: identity))
        XCTAssertEqual(reuse.text, "the exit is north")
        XCTAssertEqual(reuse.sessionID, "info-a")
        XCTAssertEqual(reuse.query, query)
        XCTAssertFalse(reuse.settlementID.isEmpty)
        XCTAssertFalse(reuse.demandID.isEmpty)
        XCTAssertEqual(reuse.sourceStateID, "S-1")
        // Serving a reuse is a read: it never adds a settlement of its own.
        XCTAssertEqual(try db.count("settlements"), settlementsBefore)
    }

    /// Rule 1: nothing was ever answered for this question.
    func testUnansweredDemandIsNotServable() throws {
        try db.recordExecutionState(
            id: "S-1", parentID: nil, modelIdentity: identity.model,
            position: 1, continuationID: "C-1", anchor: "a1",
            lifecycle: "active", createdAt: Date())
        // A demand resolved but never settled: retrieval alone is not an answer.
        _ = try loop.resolve(.init(
            sessionID: "info-a", query: query, includeChat: false, limit: 5))

        XCTAssertNil(loop.reusableAnswer(
            sessionID: "info-a", query: query, identity: identity))
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
            sessionID: "info-a", query: query, identity: identity))
    }

    /// Rule 4: a different engine never inherits settled text, and neither does
    /// an engine whose identity was not resolved.
    func testDifferentOrUnresolvedProducerIdentityIsNotServable() throws {
        try settleAnsweredTurn()

        XCTAssertNil(loop.reusableAnswer(
            sessionID: "info-a", query: query,
            identity: .init(model: "other-model", tokenizer: identity.tokenizer)))
        XCTAssertNil(loop.reusableAnswer(
            sessionID: "info-a", query: query,
            identity: .init(model: identity.model, tokenizer: "other-tokenizer")))
        XCTAssertNil(loop.reusableAnswer(
            sessionID: "info-a", query: query,
            identity: .init(model: "unspecified", tokenizer: "unspecified")))
    }

    /// Scope isolation: the same wording in a different information scope is a
    /// different demand and must not be answered from another scope's settlement.
    func testSameQuestionInAnotherScopeIsNotServable() throws {
        try settleAnsweredTurn()

        XCTAssertNil(loop.reusableAnswer(
            sessionID: "info-b", query: query, identity: identity))
        // Case and whitespace are NOT normalized away — only exact repeats reuse.
        XCTAssertNil(loop.reusableAnswer(
            sessionID: "info-a", query: "Where is the exit?", identity: identity))
    }

    /// An unresolved producer identity is an absence of a claim, not a wildcard:
    /// two unnamed engines are not the same engine, so 「未识别」 must never let
    /// one model inherit another model's settled text.
    func testAbsentProducerIdentityIsNeverServable() throws {
        let resolution = try loop.resolve(.init(
            sessionID: "info-a", query: query, includeChat: false, limit: 5))
        _ = try loop.settleTurn(
            generatedText: "the exit is north", resolution: resolution,
            stateID: "S-absent", parentStateID: nil, position: 1,
            modelIdentity: "unresolved", identity: .absent,
            sessionID: "info-a", summaryQuery: query)

        XCTAssertNil(loop.reusableAnswer(
            sessionID: "info-a", query: query, identity: .absent))
        XCTAssertNil(loop.reusableAnswer(
            sessionID: "info-a", query: query, identity: identity))

        // The refusal is in the binding rule itself, not only in the gate.
        let absentOnly = SimiGoSettlementIdentityBinding.evaluate(
            recorded: SimiGoSettlementIdentityBinding.bindings(for: .absent),
            consumer: .absent)
        XCTAssertEqual(absentOnly.status, .blocked)
        XCTAssertEqual(
            absentOnly.code,
            SimiGoSettlementIdentityBinding.Refusal.consumerAbsent.rawValue)
        let emptyRecorded = SimiGoSettlementIdentityBinding.evaluate(
            recorded: [:], consumer: identity)
        XCTAssertEqual(emptyRecorded.status, .blocked)
        XCTAssertEqual(
            emptyRecorded.code,
            SimiGoSettlementIdentityBinding.Refusal.modelAbsent.rawValue)
    }
}
