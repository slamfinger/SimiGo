import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// 目录导入（复核）：图形界面里选一个目录 = 把这个目录的文件按（目录，文件名）落进 IS。
///
/// 量的是四件事：
/// 1. 二进制文件也有一行（只落档，内容为空）——这是 v1.5 记的那个缺口；
/// 2. 再导入一次是幂等的，不新增行；
/// 3. 磁盘上没了就标 missing，**不删**；改名就是旧行 missing + 新行新增；
/// 4. 人改过的标题，重新导入不覆盖。
final class ESISDirectoryNameImportTests: XCTestCase {

    private var scratch: [URL] = []

    override func tearDown() {
        for url in scratch {
            try? FileManager.default.removeItem(at: url)
        }
        scratch = []
        super.tearDown()
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        scratch.append(root)
        return root
    }

    private func open() throws -> ESISDatabase {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-import-\(UUID().uuidString).sqlite3")
        scratch.append(url)
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        return db
    }

    private func touch(_ root: URL, _ names: [String]) throws {
        for name in names {
            let url = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data("正文".utf8).write(to: url)
        }
    }

    private func rows(_ db: ESISDatabase, rootID: String) throws -> [String: String] {
        var out: [String: String] = [:]
        for row in try db.listExternalFiles(rootID: rootID) {
            out[row.relativePath] = row.status
        }
        return out
    }

    func testEveryFileLandsEvenWhenBinary() throws {
        let db = try open()
        let root = try makeRoot()
        try touch(root, ["合同法.docx", "台账.xlsx", "说明.txt", "第四季度/附件1：报表.docx"])
        // 二进制样子的文件：内容不是 UTF-8 文本
        try Data([0xFF, 0xFE, 0x00, 0x01, 0x02]).write(
            to: root.appendingPathComponent("扫描件.pdf"))

        let report = try db.importDirectoryNames(rootID: "work-a", rootURL: root)
        XCTAssertEqual(report.files, 5)
        XCTAssertEqual(report.inserted, 5)
        XCTAssertEqual(report.missing, 0)

        let files = try rows(db, rootID: "work-a")
        XCTAssertEqual(Set(files.keys), [
            "合同法.docx", "台账.xlsx", "说明.txt", "扫描件.pdf", "第四季度/附件1：报表.docx",
        ])
        XCTAssertEqual(files.values.filter { $0 == "present" }.count, 5)
        XCTAssertEqual(try db.externalFileTitle(rootID: "work-a", relativePath: "合同法.docx"),
                       "合同法")
        XCTAssertEqual(
            try db.externalFileTitle(rootID: "work-a", relativePath: "第四季度/附件1：报表.docx"),
            "报表")
    }

    func testReimportIsIdempotent() throws {
        let db = try open()
        let root = try makeRoot()
        try touch(root, ["a.txt", "b.txt"])

        _ = try db.importDirectoryNames(rootID: "work-a", rootURL: root)
        let again = try db.importDirectoryNames(rootID: "work-a", rootURL: root)
        XCTAssertEqual(again.files, 2)
        XCTAssertEqual(again.inserted, 0)
        XCTAssertEqual(again.refreshed, 2)
        XCTAssertEqual(try db.listExternalFiles(rootID: "work-a").count, 2)
    }

    func testRenameLeavesTheOldRowMissingAndAddsANewOne() throws {
        let db = try open()
        let root = try makeRoot()
        try touch(root, ["旧名.txt"])
        _ = try db.importDirectoryNames(rootID: "work-a", rootURL: root)

        try FileManager.default.moveItem(at: root.appendingPathComponent("旧名.txt"),
                                         to: root.appendingPathComponent("新名.txt"))
        let report = try db.importDirectoryNames(rootID: "work-a", rootURL: root)
        XCTAssertEqual(report.inserted, 1)
        XCTAssertEqual(report.missing, 1)

        let files = try rows(db, rootID: "work-a")
        XCTAssertEqual(files["旧名.txt"], "missing")
        XCTAssertEqual(files["新名.txt"], "present")
    }

    func testDeletedFileIsMarkedMissingNotRemoved() throws {
        let db = try open()
        let root = try makeRoot()
        try touch(root, ["留着.txt", "删掉.txt"])
        _ = try db.importDirectoryNames(rootID: "work-a", rootURL: root)

        try FileManager.default.removeItem(at: root.appendingPathComponent("删掉.txt"))
        let report = try db.importDirectoryNames(rootID: "work-a", rootURL: root)
        XCTAssertEqual(report.files, 1)
        XCTAssertEqual(report.missing, 1)
        XCTAssertEqual(try db.listExternalFiles(rootID: "work-a").count, 2)
        XCTAssertEqual(try rows(db, rootID: "work-a")["删掉.txt"], "missing")
    }

    func testMissingRootDoesNotMarkPreviouslyIndexedFilesMissing() throws {
        let db = try open()
        let root = try makeRoot()
        try touch(root, ["keep.txt"])
        _ = try db.importDirectoryNames(rootID: "work-a", rootURL: root)

        let missingRoot = root.appendingPathComponent("does-not-exist", isDirectory: true)
        XCTAssertThrowsError(
            try db.importDirectoryNames(rootID: "work-a", rootURL: missingRoot),
            "A missing root is an incomplete scan, not evidence that every old file vanished")
        XCTAssertEqual(try rows(db, rootID: "work-a")["keep.txt"], "present")
    }

    func testInventoryLimitFailureDoesNotMarkRemainingFilesMissing() throws {
        let db = try open()
        let root = try makeRoot()
        try touch(root, ["a.txt", "b.txt", "c.txt"])
        _ = try db.importDirectoryNames(rootID: "work-a", rootURL: root)

        XCTAssertThrowsError(
            try db.importDirectoryNames(
                rootID: "work-a", rootURL: root, maxObservedFiles: 1))
        let files = try rows(db, rootID: "work-a")
        XCTAssertEqual(files.count, 3)
        XCTAssertEqual(Set(files.values), ["present"])
    }

    func testRootIDCannotBeReusedForAnotherExistingDirectory() throws {
        let db = try open()
        let original = try makeRoot()
        let replacement = try makeRoot()
        try touch(original, ["original.txt"])
        try touch(replacement, ["replacement.txt"])
        _ = try db.importDirectoryNames(rootID: "work-a", rootURL: original)

        XCTAssertThrowsError(
            try db.importDirectoryNames(rootID: "work-a", rootURL: replacement),
            "A root ID must remain bound to its registered canonical path")
        let files = try rows(db, rootID: "work-a")
        XCTAssertEqual(files["original.txt"], "present")
        XCTAssertNil(files["replacement.txt"])
    }

    func testRootDirectoryReplacementRequiresExplicitAdoption() throws {
        let db = try open()
        let root = try makeRoot()
        let movedRoot = root.deletingLastPathComponent()
            .appendingPathComponent("original-\(UUID().uuidString)", isDirectory: true)
        try touch(root, ["old.txt"])
        _ = try db.importDirectoryNames(rootID: "work-a", rootURL: root)

        try FileManager.default.moveItem(at: root, to: movedRoot)
        scratch.append(movedRoot)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try touch(root, ["same.txt", "new.txt"])

        XCTAssertThrowsError(
            try db.importDirectoryNames(rootID: "work-a", rootURL: root),
            "A replacement inode must not be mixed into the old root inventory")
        XCTAssertEqual(try rows(db, rootID: "work-a")["old.txt"], "present")
        XCTAssertNil(try rows(db, rootID: "work-a")["same.txt"])
        XCTAssertNil(try rows(db, rootID: "work-a")["new.txt"])

        try db.adoptRootLocatorIdentity(rootID: "work-a")
        let adopted = try db.importDirectoryNames(rootID: "work-a", rootURL: root)
        XCTAssertEqual(adopted.inserted, 2)
        XCTAssertEqual(adopted.missing, 1)
        let after = try rows(db, rootID: "work-a")
        XCTAssertEqual(after["old.txt"], "missing")
        XCTAssertEqual(after["same.txt"], "present")
        XCTAssertEqual(after["new.txt"], "present")
    }

    func testHumanTitleSurvivesReimport() throws {
        let db = try open()
        let root = try makeRoot()
        try touch(root, ["2026-6标.pdf"])
        _ = try db.importDirectoryNames(rootID: "work-a", rootURL: root)

        try db.updateExternalFileTitle(
            rootID: "work-a", relativePath: "2026-6标.pdf", title: "2026年第6标段 施工组织设计")
        _ = try db.importDirectoryNames(rootID: "work-a", rootURL: root)
        XCTAssertEqual(try db.externalFileTitle(rootID: "work-a", relativePath: "2026-6标.pdf"),
                       "2026年第6标段 施工组织设计")
    }

    func testBareAttachmentTakesTheDirectoryMainFileName() throws {
        let db = try open()
        let root = try makeRoot()
        try touch(root, [
            "关于强化商务管理的通知/关于强化商务管理的通知.pdf",
            "关于强化商务管理的通知/附件.zip",
        ])

        _ = try db.importDirectoryNames(rootID: "work-a", rootURL: root)
        XCTAssertEqual(
            try db.externalFileTitle(rootID: "work-a",
                                     relativePath: "关于强化商务管理的通知/附件.zip"),
            "关于强化商务管理的通知附件")
    }

    func testDirectoryINodePropagatesMetadataReadFailure() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-missing-root-\(UUID().uuidString)")
        XCTAssertThrowsError(try ESISDatabase.directoryINode(atPath: missing.path),
                             "A failed lstat must not be treated as an unsupported inode")
    }


}

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
            try db.settlementValidity(oldResolution.retrievalSettlementID), "invalid")
    }
}
