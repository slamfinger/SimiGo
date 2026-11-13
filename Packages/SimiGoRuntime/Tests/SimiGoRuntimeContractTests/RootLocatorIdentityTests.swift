import Foundation
import XCTest

@testable import SimiGoRuntimeContract

final class RootLocatorIdentityTests: XCTestCase {
    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-root-identity-\(name)-\(UUID().uuidString)")
    }

    func testReplacedRootDoesNotPublishUntilExplicitAdoption() throws {
        let parent = temporaryURL("parent")
        let root = parent.appendingPathComponent("registered-root", isDirectory: true)
        let movedRoot = parent.appendingPathComponent("original-root", isDirectory: true)
        let databaseURL = temporaryURL("database.sqlite3")
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: parent); try? fm.removeItem(at: databaseURL) }
        try Data("old-root-content-token".utf8)
            .write(to: root.appendingPathComponent("source.txt"))

        let db = try ESISDatabase(url: databaseURL)
        defer { db.close() }
        try db.runMigrations()
        let initial = try db.settleWorkRootContents(
            rootID: "root-identity", rootURL: root, carryText: false)
        XCTAssertFalse(initial.locatorIdentityChanged)
        let oldDigest = try XCTUnwrap(
            try db.settledFileRows(rootID: "root-identity").first?.digest)

        let loop = InformationLoop(database: db)
        let oldResolution = try loop.resolve(.init(
            requestIdentity: "before-root-replacement",
            query: "old-root-content-token", includeChat: false))
        XCTAssertEqual(oldResolution.hits.map(\.itemID), ["file:root-identity/source.txt"])
        let oldPayload = try XCTUnwrap(
            db.informationRetrievalPayload(demandID: oldResolution.demandID))
        XCTAssertEqual(try db.settlementValidity(oldResolution.retrievalSettlementID), "valid")

        // Same path, different directory inode, with the same relative file name
        // but different bytes. The old directory remains elsewhere, so the inode
        // cannot be immediately recycled by the filesystem.
        try fm.moveItem(at: root, to: movedRoot)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("new-root-content-token".utf8)
            .write(to: root.appendingPathComponent("source.txt"))

        let refused = try db.settleWorkRootContents(
            rootID: "root-identity", rootURL: root, carryText: false)
        XCTAssertTrue(refused.locatorIdentityChanged)
        XCTAssertEqual(refused.scanned, 0)
        XCTAssertEqual(refused.changed, 0)
        XCTAssertEqual(refused.removed, 0)
        XCTAssertEqual(refused.invalidatedSettlements, 0)
        XCTAssertEqual(
            try db.settledFileRows(rootID: "root-identity").first?.digest, oldDigest)
        XCTAssertEqual(
            try db.informationRetrievalPayload(demandID: oldResolution.demandID), oldPayload)
        XCTAssertEqual(
            try db.settlementValidity(oldResolution.retrievalSettlementID), "valid")
        XCTAssertEqual(
            try db.listExternalFiles(rootID: "root-identity")
                .first(where: { $0.relativePath == "source.txt" })?.status,
            "present")

        // Only the explicit adoption changes the recorded inode and permits the
        // next scan to publish the replacement directory's content.
        try db.adoptRootLocatorIdentity(rootID: "root-identity")
        let adopted = try db.settleWorkRootContents(
            rootID: "root-identity", rootURL: root, carryText: false)
        XCTAssertFalse(adopted.locatorIdentityChanged)
        XCTAssertEqual(adopted.changed, 1)
        XCTAssertNotEqual(
            try db.settledFileRows(rootID: "root-identity").first?.digest, oldDigest)
        XCTAssertNil(try db.informationRetrievalPayload(demandID: oldResolution.demandID))
        XCTAssertEqual(
            try db.settlementValidity(oldResolution.retrievalSettlementID), "invalidated")
    }
}
