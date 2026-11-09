import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// 论文骨架 §3 要求的两个分歧臂，跑在产品路径上：
/// Arm A —— 直出复用（零调用、不诞生结算、只写复用事件）；
/// Arm B —— 朴素键缓存基线，同一次上游变更下返回陈旧值且静默。
/// 两臂都打印一行读数，供研究记录引用。
final class ESISArmsTests: XCTestCase {

    private let identity = SettlementIdentityBinding.Identity(
        model: "arm-model", tokenizer: "arm-tokenizer")

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-arms-\(UUID().uuidString)-\(name).sqlite3")
    }

    private func cleanup(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-arms-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    /// Arm A：同 demand 上的第二次提问走直出，零模型调用，且不新增任何结算、
    /// 执行状态或消费行——判别的唯一载体是复用事件本身。
    func testArmAReadOnlyReuseWritesEventAndNoSettlement() throws {
        let url = tempURL("arm-a")
        defer { cleanup(url) }
        let db = try ESISDatabase(url: url)
        defer { db.close() }
        try db.runMigrations()
        let loop = InformationLoop(database: db)
        let q = "arm a question"

        let first = try loop.resolve(.init(
            sessionID: "s-arm-a", query: q, includeChat: false, limit: 10))
        let turn = try loop.settleTurn(
            generatedText: "arm a answer", resolution: first, stateID: "S-arm-a",
            parentStateID: nil, position: 1, modelIdentity: identity.model,
            identity: identity, sessionID: "s-arm-a", summaryQuery: q)

        let again = try loop.resolve(.init(
            sessionID: "s-arm-a", query: q, includeChat: false, limit: 10))
        XCTAssertEqual(again.demandID, first.demandID, "same basis, same demand")
        let reuse = try XCTUnwrap(loop.reusableAnswer(
            sessionID: "s-arm-a", query: q,
            expectedDemandID: again.demandID, identity: identity))
        XCTAssertEqual(reuse.text, "arm a answer")

        let before = (settlements: try db.count("settlements"),
                      states: try db.count("execution_states"),
                      consumptions: try db.count("settlement_consumptions"))
        _ = try db.recordInformationReuse(
            sourceSettlementID: reuse.settlementID,
            sourceStateID: reuse.sourceStateID,
            demandID: reuse.demandID,
            sessionID: "s-arm-a", query: q)
        let after = (settlements: try db.count("settlements"),
                     states: try db.count("execution_states"),
                     consumptions: try db.count("settlement_consumptions"))
        XCTAssertEqual(after.settlements, before.settlements)
        XCTAssertEqual(after.states, before.states)
        XCTAssertEqual(after.consumptions, before.consumptions)

        let event = try XCTUnwrap(db.informationReuseEvent(demandID: reuse.demandID))
        XCTAssertEqual(event.modelCalls, 0)
        XCTAssertEqual(try db.count("information_reuse_events"), 1)
        print("ARM_A reuse_hit=1 model_calls=0 settlements_delta=0 "
            + "states_delta=0 consumptions_delta=0 source=\(turn.settlementID.prefix(8))")
    }

    /// Arm B：同一个查询、同一次上游变更。朴素键缓存命中陈旧的 5.6；产品路径
    /// 产生新 demand、读到 7.2，并把旧的检索结算与旧答案结算一起判为 invalid。
    func testArmBNaiveKeyCacheIsSilentlyStaleWhereProductInvalidates() throws {
        let url = tempURL("arm-b")
        let root = try makeRoot()
        defer {
            cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        let db = try ESISDatabase(url: url)
        defer { db.close() }
        try db.runMigrations()
        let loop = InformationLoop(database: db)
        let file = root.appendingPathComponent("doc.txt")

        try Data("alpha distance 5.6m".utf8).write(to: file)
        _ = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)

        // 朴素基线：以查询文本为键，第一次"调用"后永久命中。
        var naiveCache: [String: String] = [:]
        func naiveAnswer(_ query: String) throws -> String {
            if let cached = naiveCache[query] { return cached }
            let text = try String(contentsOf: file, encoding: .utf8)
            naiveCache[query] = text
            return text
        }
        XCTAssertTrue(try naiveAnswer("alpha").contains("5.6"))

        let first = try loop.resolve(.init(
            query: "alpha", includeChat: false, limit: 10))
        XCTAssertTrue(first.hits.contains { $0.lineText.contains("5.6") })
        let answer = try loop.settleTurn(
            generatedText: "alpha distance is 5.6m", resolution: first,
            stateID: "S-alpha", parentStateID: nil, position: 1,
            modelIdentity: identity.model, identity: identity,
            sessionID: "s-arm-b", summaryQuery: "alpha")

        // 上游变更：值从 5.6 变成 7.2。
        try Data("alpha distance 7.2m".utf8).write(to: file)
        let scan = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)
        XCTAssertEqual(scan.changed, 1)
        XCTAssertEqual(scan.invalidatedSettlements, 2,
                       "retrieval settlement and the answer built on it")
        XCTAssertEqual(try db.settlementValidity(first.retrievalSettlementID), "invalid")
        XCTAssertEqual(try db.settlementValidity(answer.settlementID), "invalid")

        // 朴素缓存：命中，返回旧值，无任何标记。
        let stale = try naiveAnswer("alpha")
        XCTAssertTrue(stale.contains("5.6"))
        XCTAssertFalse(stale.contains("7.2"))

        // 产品：同一查询落到新 demand，读到新值。
        let second = try loop.resolve(.init(
            query: "alpha", includeChat: false, limit: 10))
        XCTAssertNotEqual(second.demandID, first.demandID)
        XCTAssertTrue(second.hits.contains { $0.lineText.contains("7.2") })
        XCTAssertFalse(second.hits.contains { $0.lineText.contains("5.6") })
        print("ARM_B naive=stale_silent:5.6 product invalidated=2 "
            + "new_demand=\(second.demandID.prefix(8)) fresh=7.2")
    }
}
