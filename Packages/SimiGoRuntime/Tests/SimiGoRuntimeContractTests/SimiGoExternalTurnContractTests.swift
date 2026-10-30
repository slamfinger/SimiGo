import Foundation
import SQLite3
import XCTest
@testable import SimiGoRuntimeContract

/// External-provider turns: keeping the information, settling it and letting a
/// later request consume it are three separate questions. A turn forwarded to
/// an upstream API is recorded with its provenance at arrival, verified as a
/// whole request, and only then becomes retrievable history.
final class SimiGoExternalTurnContractTests: XCTestCase {

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-external-\(UUID().uuidString)-\(name).sqlite3")
    }

    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func open(_ name: String) throws -> (URL, SimiGoESISDatabase) {
        let url = tempURL(name)
        let db = try SimiGoESISDatabase(url: url)
        try db.runMigrations()
        return (url, db)
    }

    private func recordTurn(
        _ db: SimiGoESISDatabase, sessionID: String = "s-ext",
        provider: String = "openai-compatible", requestID: String,
        question: String, answer: String
    ) throws {
        try db.recordExternalTurn(
            sessionID: sessionID, provider: provider, requestID: requestID,
            userText: question, model: "gpt-x", createdAt: Date())
        try db.recordExternalResponse(
            sessionID: sessionID, provider: provider, requestID: requestID,
            assistantText: answer, model: "gpt-x", createdAt: Date())
    }

    /// Recorded is not retrievable: the upstream text and its provenance are
    /// in the space as soon as the request arrives, but they are not history
    /// another request may consume.
    func testRecordedExternalTurnIsKeptWithProvenanceButNotRetrievable() throws {
        let (url, db) = try open("recorded")
        defer { db.close(); cleanup(url) }
        let loop = SimiGoInformationLoop(database: db)

        let userID = try db.recordExternalTurn(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-1",
            userText: "外部请求：关键线路 节点工期", model: "gpt-x", createdAt: Date())
        try db.recordExternalResponse(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-1",
            assistantText: "外部回答：节点工期 42 天", model: "gpt-x", createdAt: Date())

        // Recorded: bytes and provenance are readable back.
        let stored = try db.listChatMessages(sessionID: "s-ext")
        XCTAssertEqual(stored.map(\.role), ["user", "assistant"])
        let provenance = try db.chatTurnProvenance(
            sessionID: "s-ext", requestID: "req-1")
        XCTAssertEqual(provenance.map(\.messageID).first, userID)
        XCTAssertEqual(provenance.map(\.turnState), ["recorded", "recorded"])
        XCTAssertEqual(provenance.map(\.sourceKind), ["external", "external"])
        XCTAssertEqual(
            provenance.compactMap(\.sourceProvider),
            ["openai-compatible", "openai-compatible"])
        XCTAssertEqual(provenance.compactMap(\.requestID), ["req-1", "req-1"])
        XCTAssertTrue(provenance.allSatisfy { $0.verifiedAt == nil && !$0.isEligible })

        // Not retrievable: arrival wrote no standing.
        XCTAssertTrue(try db.chatIndexRows(sessionIDs: ["s-ext"]).isEmpty)
        let resolution = try loop.resolve(.init(
            sessionID: "s-ext", query: "节点工期", includeChat: true,
            chatSessionIDs: ["s-ext"]))
        XCTAssertTrue(resolution.hits.isEmpty)
        XCTAssertEqual(loop.contextBlock(resolution), "")
    }

    /// Verification promotes exactly the request's own question/answer pair,
    /// making it ordinary retrievable history.
    func testVerifiedExternalTurnBecomesRetrievableHistory() throws {
        let (url, db) = try open("verified")
        defer { db.close(); cleanup(url) }
        let loop = SimiGoInformationLoop(database: db)

        try recordTurn(
            db, requestID: "req-2",
            question: "外部请求：关键线路 节点工期",
            answer: "外部回答：节点工期 42 天")

        XCTAssertEqual(
            try db.verifyExternalTurn(
                sessionID: "s-ext", requestID: "req-2", verifiedAt: Date()),
            2)

        let provenance = try db.chatTurnProvenance(
            sessionID: "s-ext", requestID: "req-2")
        XCTAssertEqual(provenance.map(\.turnState), ["committed", "committed"])
        XCTAssertTrue(provenance.allSatisfy { $0.verifiedAt != nil && $0.isEligible })

        let rows = try db.chatIndexRows(sessionIDs: ["s-ext"])
        XCTAssertEqual(rows.map(\.role), ["user", "assistant"])
        let resolution = try loop.resolve(.init(
            sessionID: "s-ext", query: "节点工期", includeChat: true,
            chatSessionIDs: ["s-ext"]))
        XCTAssertEqual(Set(resolution.hits.map(\.itemID)), Set(rows.map(\.itemID)))
    }

    /// A half-turn is never verified: the answer cannot become memory without
    /// the question it answers.
    func testVerificationRequiresBothSidesOfTheRequest() throws {
        let (url, db) = try open("half")
        defer { db.close(); cleanup(url) }

        try db.recordExternalTurn(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-3",
            userText: "只有问题", model: nil, createdAt: Date())
        XCTAssertEqual(
            try db.verifyExternalTurn(
                sessionID: "s-ext", requestID: "req-3", verifiedAt: Date()),
            0)
        XCTAssertEqual(
            try db.chatTurnProvenance(sessionID: "s-ext", requestID: "req-3")
                .map(\.turnState),
            ["recorded"])

        try db.recordExternalResponse(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-3",
            assistantText: "现在有答案了", model: nil, createdAt: Date())
        XCTAssertEqual(
            try db.verifyExternalTurn(
                sessionID: "s-ext", requestID: "req-3", verifiedAt: Date()),
            2)
    }

    /// Two concurrent external requests on one session: verifying one must not
    /// grant standing to the other's still-unanswered input.
    func testVerifyingOneRequestNeverPromotesAnotherInFlightTurn() throws {
        let (url, db) = try open("concurrent")
        defer { db.close(); cleanup(url) }
        let loop = SimiGoInformationLoop(database: db)

        try recordTurn(
            db, requestID: "req-a",
            question: "请求 A：关键线路 节点工期", answer: "回答 A：42 天")
        try db.recordExternalTurn(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-b",
            userText: "请求 B：后台汇总 rollout_summary", model: nil, createdAt: Date())

        XCTAssertEqual(
            try db.verifyExternalTurn(
                sessionID: "s-ext", requestID: "req-a", verifiedAt: Date()),
            2)

        // B is recorded, not verified, and never visible to A's retrieval.
        let resolution = try loop.resolve(.init(
            sessionID: "s-ext", query: "rollout_summary", includeChat: true,
            chatSessionIDs: ["s-ext"]))
        XCTAssertTrue(resolution.hits.isEmpty)
        XCTAssertEqual(
            try db.chatTurnProvenance(sessionID: "s-ext", requestID: "req-b")
                .map(\.turnState),
            ["recorded"])
        XCTAssertEqual(
            try db.chatIndexRows(sessionIDs: ["s-ext"]).map(\.role),
            ["user", "assistant"])
        XCTAssertEqual(
            try db.verifyExternalTurn(
                sessionID: "s-ext", requestID: "req-b", verifiedAt: Date()),
            0)
    }

    /// Retries of the same upstream request reuse their rows instead of
    /// appending duplicates.
    func testRepeatingTheSameRequestDoesNotDuplicateRows() throws {
        let (url, db) = try open("idempotent")
        defer { db.close(); cleanup(url) }

        let firstUser = try db.recordExternalTurn(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-4",
            userText: "同一条外部请求", model: nil, createdAt: Date())
        let secondUser = try db.recordExternalTurn(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-4",
            userText: "同一条外部请求", model: nil, createdAt: Date())
        XCTAssertEqual(firstUser, secondUser)

        let firstAssistant = try db.recordExternalResponse(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-4",
            assistantText: "同一条外部回答", model: nil, createdAt: Date())
        let secondAssistant = try db.recordExternalResponse(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-4",
            assistantText: "同一条外部回答", model: nil, createdAt: Date())
        XCTAssertEqual(firstAssistant, secondAssistant)

        XCTAssertEqual(try db.listChatMessages(sessionID: "s-ext").count, 2)
        XCTAssertEqual(
            try db.verifyExternalTurn(
                sessionID: "s-ext", requestID: "req-4", verifiedAt: Date()),
            2)
    }

    /// A client-declared internal operation keeps its text but can never be
    /// promoted to retrievable knowledge by verification.
    func testInternalOperationIsKeptButNeverPromoted() throws {
        let (url, db) = try open("internal")
        defer { db.close(); cleanup(url) }

        try db.recordExternalTurn(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-6",
            userText: "内部记账：会话摘要", model: nil, createdAt: Date(),
            eligibility: .internalOperation)
        try db.recordExternalResponse(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-6",
            assistantText: "内部答复", model: nil, createdAt: Date(),
            eligibility: .internalOperation)

        XCTAssertEqual(
            try db.chatTurnProvenance(sessionID: "s-ext", requestID: "req-6")
                .map(\.turnState),
            ["internal", "internal"])
        XCTAssertEqual(
            try db.verifyExternalTurn(
                sessionID: "s-ext", requestID: "req-6", verifiedAt: Date()),
            0)
        XCTAssertTrue(try db.chatIndexRows(sessionIDs: ["s-ext"]).isEmpty)
        XCTAssertEqual(try db.listChatMessages(sessionID: "s-ext").count, 2)
    }

    /// Local retry reuse stays inside the local lineage: it must not adopt an
    /// external row, nor promote it by committing the local turn.
    func testLocalRetryReuseNeverAdoptsAnExternalRow() throws {
        let (url, db) = try open("lineage")
        defer { db.close(); cleanup(url) }

        let externalID = try db.recordExternalTurn(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-5",
            userText: "同一句话", model: nil, createdAt: Date())

        let localID = try db.appendChatMessage(
            sessionID: "s-ext", role: "user", content: "同一句话",
            model: nil, createdAt: Date())
        XCTAssertNotEqual(localID, externalID)
        try db.commitChatTurn(
            sessionID: "s-ext", userMessageID: localID,
            assistantText: "本地回答", model: nil, createdAt: Date())

        XCTAssertEqual(
            try db.chatTurnProvenance(sessionID: "s-ext", requestID: "req-5")
                .map(\.turnState),
            ["recorded"])
        XCTAssertEqual(
            try db.chatIndexRows(sessionIDs: ["s-ext"]).map(\.role),
            ["user", "assistant"])
    }
}
