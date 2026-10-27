import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// v12 storage proof: a settlement may reference the immutable `final` snapshot
/// written in the same commit, the reference is never backfilled, and a
/// settlement cannot point at an object that does not exist.
final class SimiGoSnapshotStorageTests: XCTestCase {
    private typealias Snapshot = SimiGoSnapshotContract

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-snapshot-\(UUID().uuidString)-\(name).sqlite3")
    }

    private func cleanup(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func makeDatabase(_ name: String) throws -> (SimiGoESISDatabase, URL) {
        let url = tempURL(name)
        let db = try SimiGoESISDatabase(url: url)
        try db.runMigrations()
        return (db, url)
    }

    private func settled(_ text: String) throws -> SimiGoSettlementAuthority.SettledResult {
        let contract = #"{"schema_version":"simigo.result-contract/v1","fields":{"secret":{"pattern":"^SECRET=(.+)$","type":"string"}},"constraints":[{"kind":"digest_equals_binding","field":"secret","binding":"secret_commitment"}]}"#
        return try SimiGoSettlementAuthority.authorize(
            generatedText: text,
            contractJSON: Data(contract.utf8),
            verifiedBindings: ["secret_commitment": .string("2b1a5d9f0a1183c966ce8325a252424579a625c1b2314654dd6aaebaf9c334a8")])
    }

    private func makeFinal(declaredBytes: String) throws -> (Snapshot.Declared, Data) {
        let data = Data(declaredBytes.utf8)
        let entry = try Snapshot.DeclaredEntry(
            fileRootID: "root-1", relativePath: "Sources/A.swift",
            sha256: Snapshot.sha256Hex(data), byteSource: .embedded(data),
            size: data.count, modified: "2026-10-27T00:00:00.000Z",
            statIdentity: .init(device: "1", inode: "2", modificationNanoseconds: "3"))
        let declared = Snapshot.Declared(
            capturedAt: Date(timeIntervalSince1970: 1_790_000_000),
            request: Snapshot.Request(
                kind: "chat", rootIDs: ["root-1"],
                contractJSON: Data(#"{"schema_version":"simigo.result-contract/v1","fields":{}}"#.utf8),
                recomputePolicy: "allow_safe_recompute", idempotencyKey: "idem-1"),
            anchor: Snapshot.Anchor(
                stateID: "state-1", settlementID: "settlement-1",
                payloadDigest: Snapshot.sha256Hex(Data("payload".utf8))),
            entries: [entry])
        let final = try Snapshot.Final.make(
            declared: declared,
            declaredSnapshotID: Snapshot.sha256Hex(try declared.encoded()),
            used: [Snapshot.UsedItem.from(declared: entry, injectedAs: "context[0]")],
            verifiedAsOf: Date(timeIntervalSince1970: 1_790_000_100),
            recheck: ["sources": "unchanged", "closure": "unchanged"],
            capturedAt: Date(timeIntervalSince1970: 1_790_000_001))
        return (declared, try final.encoded())
    }

    func testHeadIsThirteenAndSnapshotReferenceIsNullable() throws {
        let (db, url) = try makeDatabase("head")
        defer { db.close(); cleanup(url) }
        XCTAssertEqual(try db.schemaVersion(), 13)

        try db.recordExecutionState(id: "state-1", parentID: nil, modelIdentity: "m",
                                    position: 1, continuationID: "C-1", anchor: "a1",
                                    lifecycle: "saved", createdAt: Date())
        let settlementID = try db.recordNativeSettlement(try settled("SECRET=NORTH>EAST"), stateID: "state-1")
        XCTAssertNil(try db.settlementInputSnapshotObjectID(settlementID: settlementID),
                     "historical rows carry no snapshot reference and are never backfilled")
    }

    func testSettlementReferencesTheFinalSnapshotItCommittedWith() throws {
        let (db, url) = try makeDatabase("reference")
        defer { db.close(); cleanup(url) }

        try db.recordExecutionState(id: "state-1", parentID: nil, modelIdentity: "m",
                                    position: 1, continuationID: "C-1", anchor: "a1",
                                    lifecycle: "saved", createdAt: Date())

        let (declared, finalBytes) = try makeFinal(declaredBytes: "let a = 1\n")
        let declaredID = try db.writeObject(try declared.encoded())
        let finalID = try db.writeObject(finalBytes)
        XCTAssertNotEqual(declaredID, finalID)

        let settlementID = try db.recordNativeSettlementWithIdentity(
            try settled("SECRET=NORTH>EAST"),
            stateID: "state-1",
            identity: .init(model: "mlx:m", tokenizer: "tok:t"),
            inputSnapshotObjectID: finalID)

        XCTAssertEqual(try db.settlementInputSnapshotObjectID(settlementID: settlementID.uuidString), finalID)

        let stored = try db.readObject(finalID)
        let decoded = try Snapshot.Final.decode(stored)
        XCTAssertEqual(decoded.declaredSnapshotID, declaredID)
        XCTAssertTrue(decoded.replayable)
        XCTAssertNoThrow(try decoded.verify(against: Snapshot.Declared.decode(try db.readObject(declaredID))))

        // The declared object that never reached P2 is retained as an orphan.
        XCTAssertTrue(db.verifyObject(declaredID))
    }

    func testSettlementCannotReferenceAMissingSnapshotObject() throws {
        let (db, url) = try makeDatabase("missing")
        defer { db.close(); cleanup(url) }

        try db.recordExecutionState(id: "state-1", parentID: nil, modelIdentity: "m",
                                    position: 1, continuationID: "C-1", anchor: "a1",
                                    lifecycle: "saved", createdAt: Date())
        let before = try db.count("settlements")
        let ghost = Snapshot.sha256Hex(Data("never written".utf8))

        XCTAssertThrowsError(try db.recordNativeSettlementWithIdentity(
            try settled("SECRET=NORTH>EAST"),
            stateID: "state-1",
            identity: .init(model: "mlx:m", tokenizer: "tok:t"),
            inputSnapshotObjectID: ghost))
        XCTAssertEqual(try db.count("settlements"), before,
                       "a rejected reference must roll the settlement row back")
    }
}
