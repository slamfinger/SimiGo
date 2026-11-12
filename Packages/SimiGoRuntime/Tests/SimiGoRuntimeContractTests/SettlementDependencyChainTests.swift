import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// 多级派生结算的失效传播。审核把这一项列为「待验证」：递归闭包和依赖边
/// 都能在代码里读到，但没有一条测试真的搭过 A → B → C 再动最上游。
///
/// 这里把两种失效分开测，因为它们的语义不同：
///   * 改源文件：整条链（含中间的派生结算）一起失效，无关结算不动；
///   * 只废中间那层派生结算：下游跟着失效，上游仍然有效。
final class SettlementDependencyChainTests: XCTestCase {

    private let identity = SettlementIdentityBinding.Identity(
        model: "chain-model", tokenizer: "chain-tokenizer")
    private let query = "alpha facts"

    private struct Fixture {
        let directory: URL
        let rootURL: URL
        let db: ESISDatabase
    }

    private func makeFixture(_ name: String) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-chain-\(UUID().uuidString)-\(name)")
        let rootURL = directory.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL, withIntermediateDirectories: true)
        try Data("alpha beta gamma".utf8)
            .write(to: rootURL.appendingPathComponent("notes.md"))
        let db = try ESISDatabase(url: directory.appendingPathComponent("esis.sqlite3"))
        try db.runMigrations()
        try db.settleWorkRootContents(rootID: "work", rootURL: rootURL)
        return Fixture(directory: directory, rootURL: rootURL, db: db)
    }

    private func cleanup(_ fixture: Fixture) {
        fixture.db.close()
        try? FileManager.default.removeItem(at: fixture.directory)
    }

    /// 一个模型产出的结算。`linkFile` 为真时它直接绑定在源文件上，是链的根。
    @discardableResult
    private func makeSource(_ f: Fixture, linkFile: Bool, state: String) throws -> String {
        try f.db.recordExecutionState(
            id: state, parentID: nil, modelIdentity: identity.model, position: 0,
            continuationID: UUID().uuidString, anchor: "anchor-\(state)",
            lifecycle: "active", createdAt: Date())
        let settled = try SettlementAuthority.authorize(
            generatedText: "alpha beta gamma",
            contractJSON: InformationLoop.chatResultContractJSON,
            verifiedBindings: [:])
        let settlement = try f.db.recordNativeSettlement(settled, stateID: state)
        if linkFile {
            try f.db.linkSettlementToExternalFile(
                settlementID: settlement, binding: "content",
                rootID: "work", relativePath: "notes.md")
        }
        try declare(f, settlement: settlement)
        return settlement
    }

    private func declare(_ f: Fixture, settlement: String) throws {
        try f.db.declareSettlementReuseContract(
            settlementID: settlement,
            contractID: SettlementConsumption.Contract.contractID,
            demandClass: SettlementConsumption.Contract.demandClass,
            contractVersion: SettlementConsumption.Contract.version,
            query: query,
            rootIDs: ["work"],
            extractField: SettlementConsumption.Contract.defaultExtractField)
    }

    /// 零模型调用地消费上游，返回派生结算的 id（下游依赖边由此建立）。
    private func consume(_ f: Fixture, source: String, state: String) throws -> String {
        let outcome = try SettlementConsumption.consume(db: f.db, request: .init(
            sourceSettlementID: source,
            consumerStateID: state,
            consumerModelIdentity: identity.model,
            consumerIdentity: identity,
            query: query,
            rootIDs: ["work"]))
        guard case .consumed(let value) = outcome else {
            XCTFail("expected a consumption, got \(outcome)")
            throw SettlementConsumption.Refusal.missingField("outcome")
        }
        return value.consumerSettlementID
    }

    /// A 绑在文件上，B 消费 A，C 消费 B。改文件 → 三层全废，无关结算不动。
    func testSourceChangeInvalidatesEveryDerivedLevel() throws {
        let f = try makeFixture("source")
        defer { cleanup(f) }

        let a = try makeSource(f, linkFile: true, state: "A")
        let b = try consume(f, source: a, state: "B")
        try declare(f, settlement: b)
        let c = try consume(f, source: b, state: "C")
        let unrelated = try makeSource(f, linkFile: false, state: "U")

        let invalidated = Set(try f.db.invalidateSourceFile(
            rootID: "work", relativePath: "notes.md"))
        XCTAssertTrue(invalidated.isSuperset(of: [a, b, c]),
                      "最上游文件变了，中间的派生结算也要跟着失效")
        XCTAssertFalse(invalidated.contains(unrelated), "没依赖这个文件的不能误伤")

        XCTAssertEqual(try f.db.settlementValidity(a), "invalid")
        XCTAssertEqual(try f.db.settlementValidity(b), "invalid")
        XCTAssertEqual(try f.db.settlementValidity(c), "invalid")
        XCTAssertEqual(try f.db.settlementValidity(unrelated), "valid")

        // 失效只翻状态账，依赖图本身还在。
        XCTAssertTrue(Set(try f.db.upstreamDependencyClosure(ofSettlement: c))
            .isSuperset(of: [a, b]))
    }

    /// 只废中间那层：下游跟着失效，上游仍是有效历史。
    func testInvalidatingMiddleDerivedSettlementLeavesUpstreamValid() throws {
        let f = try makeFixture("middle")
        defer { cleanup(f) }

        let a = try makeSource(f, linkFile: true, state: "A")
        let b = try consume(f, source: a, state: "B")
        try declare(f, settlement: b)
        let c = try consume(f, source: b, state: "C")

        let invalidated = Set(try f.db.invalidateSettlement(b))
        XCTAssertEqual(invalidated, [b, c])
        XCTAssertEqual(try f.db.settlementValidity(a), "valid", "上游不受下游失效牵连")
        XCTAssertEqual(try f.db.settlementValidity(b), "invalid")
        XCTAssertEqual(try f.db.settlementValidity(c), "invalid")
    }
}
