import Foundation
import XCTest
@testable import SimiGoRuntimeContract

final class SimiGoSettlementIdentityBindingTests: XCTestCase {

    private let producer = SimiGoSettlementIdentityBinding.Identity(model: "mlx:qwen3-coder-30b", tokenizer: "tok:6e302ea6")

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-binding-\(UUID().uuidString)-\(name).sqlite3")
    }
    private func cleanup(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    /// A valid native contract used only to produce a real settlement row.
    private func settle(_ db: SimiGoESISDatabase, stateID: String) throws -> String {
        try db.recordExecutionState(id: stateID, parentID: nil, modelIdentity: "m",
                                    position: 1, continuationID: "C-1", anchor: "a1",
                                    lifecycle: "saved", createdAt: Date())
        let route = #"{"schema_version":"simigo.result-contract/v1","fields":{"secret":{"pattern":"^SECRET=(.+)$","type":"string"}},"constraints":[{"kind":"digest_equals_binding","field":"secret","binding":"secret_commitment"}]}"#
        let settled = try SimiGoSettlementAuthority.authorize(
            generatedText: "SECRET=NORTH>EAST", contractJSON: Data(route.utf8),
            verifiedBindings: ["secret_commitment": .string("2b1a5d9f0a1183c966ce8325a252424579a625c1b2314654dd6aaebaf9c334a8")]
        )
        return try db.recordNativeSettlement(settled, stateID: stateID)
    }

    // MARK: - Pure evaluation

    func testDigestIsTheProductionSettlementDigest() {
        XCTAssertEqual(SimiGoSettlementIdentityBinding.digest("abc"),
                       SimiGoSettlementAuthority.payloadDigest(Data("abc".utf8)))
    }

    func testBindingsPublishBothKeys() {
        let bindings = SimiGoSettlementIdentityBinding.bindings(for: producer)
        XCTAssertEqual(Set(bindings.keys),
                       [SimiGoSettlementIdentityBinding.modelKey,
                        SimiGoSettlementIdentityBinding.tokenizerKey])
        XCTAssertEqual(bindings[SimiGoSettlementIdentityBinding.modelKey],
                       SimiGoSettlementIdentityBinding.digest(producer.model))
        XCTAssertEqual(bindings[SimiGoSettlementIdentityBinding.tokenizerKey],
                       SimiGoSettlementIdentityBinding.digest(producer.tokenizer))
    }

    func testEvaluateAcceptsMatchingIdentity() {
        let verdict = SimiGoSettlementIdentityBinding.evaluate(
            recorded: SimiGoSettlementIdentityBinding.bindings(for: producer), consumer: producer)
        XCTAssertEqual(verdict.status, .ok)
        XCTAssertNil(verdict.code)
        XCTAssertTrue(verdict.boundModel)
        XCTAssertTrue(verdict.boundTokenizer)
        XCTAssertEqual(verdict.evidence["settlement_binding_status"] as? String, "ok")
    }

    func testEvaluateRefusesModelMismatch() {
        let other = SimiGoSettlementIdentityBinding.Identity(model: "mlx:other-model", tokenizer: producer.tokenizer)
        let verdict = SimiGoSettlementIdentityBinding.evaluate(
            recorded: SimiGoSettlementIdentityBinding.bindings(for: producer), consumer: other)
        XCTAssertEqual(verdict.status, .blocked)
        XCTAssertEqual(verdict.code, "SETTLEMENT_BINDING_MODEL_MISMATCH")
        XCTAssertFalse(verdict.boundModel)
    }

    func testEvaluateRefusesTokenizerMismatch() {
        let other = SimiGoSettlementIdentityBinding.Identity(model: producer.model, tokenizer: "tok:different")
        let verdict = SimiGoSettlementIdentityBinding.evaluate(
            recorded: SimiGoSettlementIdentityBinding.bindings(for: producer), consumer: other)
        XCTAssertEqual(verdict.status, .blocked)
        XCTAssertEqual(verdict.code, "SETTLEMENT_BINDING_TOKENIZER_MISMATCH")
        XCTAssertTrue(verdict.boundModel)
        XCTAssertFalse(verdict.boundTokenizer)
    }

    /// A settlement written before identity binding existed has no producer rows.
    /// That must refuse, not pass: absence is not evidence of a match.
    func testEvaluateRefusesAbsentBindings() {
        let verdict = SimiGoSettlementIdentityBinding.evaluate(recorded: [:], consumer: producer)
        XCTAssertEqual(verdict.status, .blocked)
        XCTAssertEqual(verdict.code, "SETTLEMENT_BINDING_MODEL_ABSENT")

        let modelOnly = [SimiGoSettlementIdentityBinding.modelKey:
                            SimiGoSettlementIdentityBinding.digest(producer.model)]
        let tokenizerAbsent = SimiGoSettlementIdentityBinding.evaluate(recorded: modelOnly, consumer: producer)
        XCTAssertEqual(tokenizerAbsent.code, "SETTLEMENT_BINDING_TOKENIZER_ABSENT")
    }

    // MARK: - Durable binding rows

    func testIdentityBindingsRoundTripThroughStore() throws {
        let url = tempURL("roundtrip")
        let db = try SimiGoESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        let settlementID = try settle(db, stateID: "S-BIND")

        XCTAssertEqual(try db.latestSettlementID(forStateID: "S-BIND"), settlementID)
        XCTAssertTrue(try db.settlementBindings(settlementID: settlementID)
            .keys.allSatisfy { !$0.hasPrefix("producer.") })

        try db.recordIdentityBindings(settlementID: settlementID, identity: producer)
        let recorded = try db.settlementBindings(settlementID: settlementID)
        XCTAssertEqual(recorded[SimiGoSettlementIdentityBinding.modelKey],
                       SimiGoSettlementIdentityBinding.digest(producer.model))
        XCTAssertEqual(recorded[SimiGoSettlementIdentityBinding.tokenizerKey],
                       SimiGoSettlementIdentityBinding.digest(producer.tokenizer))
        XCTAssertEqual(SimiGoSettlementIdentityBinding.evaluate(recorded: recorded, consumer: producer).status, .ok)

        // Re-recording is idempotent: the same two rows, not duplicates.
        try db.recordIdentityBindings(settlementID: settlementID, identity: producer)
        let producerRows = try db.settlementBindings(settlementID: settlementID)
            .keys.filter { $0.hasPrefix("producer.") }
        XCTAssertEqual(producerRows.count, 2)
        XCTAssertTrue(try db.integrityCheck())
    }

    func testIdentityBindingsAreScopedToTheirSettlement() throws {
        let url = tempURL("scoped")
        let db = try SimiGoESISDatabase(url: url)
        defer { db.close(); cleanup(url) }
        try db.runMigrations()
        let bound = try settle(db, stateID: "S-A")
        let unbound = try settle(db, stateID: "S-B")
        try db.recordIdentityBindings(settlementID: bound, identity: producer)

        XCTAssertEqual(try db.settlementBindings(settlementID: unbound)
            .keys.filter { $0.hasPrefix("producer.") }.count, 0)
        XCTAssertNil(try db.latestSettlementID(forStateID: "S-MISSING"))
    }
}
