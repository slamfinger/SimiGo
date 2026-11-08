import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// 互斥的两次结算必须同时留在 IS 里、同时可被检索。IS 只提供身份与出处，
/// 不在两者之间选一个“正确答案”：这里钉住的是并列，不是最新者胜。
final class SimiGoConflictingSettlementTests: XCTestCase {

    private var url: URL!
    private var db: SimiGoESISDatabase!
    private var loop: SimiGoInformationLoop!

    private let identity = SimiGoSettlementIdentityBinding.Identity(
        model: "model-a", tokenizer: "tokenizer-a")
    private let question = "harbor depth"

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-conflict-\(UUID().uuidString).sqlite3")
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

    @discardableResult
    private func answer(
        _ text: String, session: String, state: String
    ) throws -> (demandID: String, settlementID: String) {
        let resolution = try loop.resolve(.init(
            sessionID: session, query: question, includeChat: false, limit: 10))
        let settlementID = try loop.settleTurn(
            generatedText: text, resolution: resolution, stateID: state,
            parentStateID: nil, position: 0, modelIdentity: identity.model,
            identity: identity, sessionID: session,
            summaryQuery: question).settlementID
        return (resolution.demandID, settlementID)
    }

    func testMutuallyExclusiveSettlementsBothRemainRetrievable() throws {
        let alpha = try answer(
            "harbor depth is five meters", session: "s-alpha", state: "S-alpha")
        let beta = try answer(
            "harbor depth is nine meters", session: "s-beta", state: "S-beta")
        XCTAssertNotEqual(alpha.demandID, beta.demandID)
        XCTAssertNotEqual(alpha.settlementID, beta.settlementID)

        // 四次写入都在（两次检索 + 两次回答）：同一个问题不会合并结算行。
        XCTAssertEqual(try db.count("settlements"), 4)
        XCTAssertEqual(try db.citableSettlementSummaries(sessionID: nil).count, 2)
        XCTAssertEqual(try db.settlementValidity(alpha.settlementID), "valid")
        XCTAssertEqual(try db.settlementValidity(beta.settlementID), "valid")

        // 第三方空间检索同时命中两条，各自带 settlement:<id> 身份。
        let resolution = try loop.resolve(.init(
            sessionID: "s-gamma", query: question, includeChat: false, limit: 10))
        let ids = Set(resolution.itemIDs)
        XCTAssertTrue(ids.contains("settlement:\(alpha.settlementID)"))
        XCTAssertTrue(ids.contains("settlement:\(beta.settlementID)"))
        XCTAssertEqual(resolution.hits.filter { $0.kind == "settlement" }.count, 2)

        // 没有一方被提升为“答案”：s-gamma 自己没有发布过任何结算。
        XCTAssertNil(try db.answeredDemand(sessionID: "s-gamma", query: question))
    }
}
