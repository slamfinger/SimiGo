import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// 分歧臂：来源变了，结算该不该失效。
///
/// 两套判据在同一组动作上给出不同预期：
///   * 位置判据（现状）：结算绑在外部文件行上，来源一消失/一变化就播失效；
///   * 信息判据（已裁）：结算依赖的是内容对象，对象还在 → 旧结算仍是历史。
///
/// 本文件**只测量、不裁决**：断言只写结构性的东西（不崩、计数可读），
/// 分歧量一律打印成 `ARM_*` 行，供人比对。同一份测试在 main 与本分支上
/// 各跑一次，两次打印的差异就是这两套判据的差。
///
///   swift test --filter ESISSourceInvalidationArmsTests 2>&1 | grep '^ARM_'
final class ESISSourceInvalidationArmsTests: XCTestCase {

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-arms-\(UUID().uuidString)-\(name).sqlite3")
    }

    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func makeWorkRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-arms-work-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    private func write(_ text: String, to root: URL, name: String) throws {
        try Data(text.utf8).write(to: root.appendingPathComponent(name))
    }

    private func open(_ name: String) throws -> (URL, ESISDatabase) {
        let url = tempURL(name)
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        return (url, db)
    }

    private static let contract =
        #"{"schema_version":"simigo.result-contract/v1","fields":{"content":{"pattern":"^RESULT=(.+)$","capture_group":1,"type":"string","normalize":"trim","nonempty":true}},"constraints":[{"kind":"equals_binding","field":"content","binding":"next_input"}]}"#

    @discardableResult
    private func mkSettlement(_ db: ESISDatabase, stateID: String, value: String) throws -> String {
        try db.recordExecutionState(id: stateID, parentID: nil, modelIdentity: "m",
                                    position: 1, continuationID: "C", anchor: "a",
                                    lifecycle: "active", createdAt: Date())
        let settled = try SettlementAuthority.authorize(
            generatedText: "RESULT=\(value)", contractJSON: Data(Self.contract.utf8),
            verifiedBindings: ["next_input": .string(value)])
        return try db.recordNativeSettlement(settled, stateID: stateID)
    }

    private func report(_ arm: String, _ db: ESISDatabase, _ settlement: String,
                        _ fields: [String: String]) throws {
        var parts = ["validity=\(try db.settlementValidity(settlement))",
                     "settlements=\(try db.count("settlements"))",
                     "file_contents=\(try db.count("file_contents"))",
                     "edges=\(try db.count("dependency_edges"))"]
        for key in fields.keys.sorted() { parts.append("\(key)=\(fields[key]!)") }
        print("ARM_\(arm) " + parts.joined(separator: " "))
    }

    // A0：改了文件但不对账 —— 惰性：什么都不该发生。
    func testA0ChangedSourceWithoutReconcileChangesNothing() throws {
        let (url, db) = try open("a0")
        defer { db.close(); cleanup(url) }
        let root = try makeWorkRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("settled v1", to: root, name: "doc.md")
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let s = try mkSettlement(db, stateID: "A0", value: "v1")
        try db.linkSettlementToExternalFile(settlementID: s, binding: "content",
                                            rootID: "work", relativePath: "doc.md")
        try write("settled v2", to: root, name: "doc.md")
        // 不对账，直接读。
        try report("A0", db, s, ["reconcile": "none"])
    }

    // A1：同字节改名 —— 位置变了、信息没变。
    func testA1RenameSameBytes() throws {
        let (url, db) = try open("a1")
        defer { db.close(); cleanup(url) }
        let root = try makeWorkRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("settled text", to: root, name: "old.md")
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let s = try mkSettlement(db, stateID: "A1", value: "v1")
        try db.linkSettlementToExternalFile(settlementID: s, binding: "content",
                                            rootID: "work", relativePath: "old.md")
        try FileManager.default.moveItem(at: root.appendingPathComponent("old.md"),
                                         to: root.appendingPathComponent("new.md"))
        let r = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        try report("A1", db, s, ["changed": "\(r.changed)", "removed": "\(r.removed)",
                                 "invalidated": "\(r.invalidatedSettlements)"])
    }

    // A2：同路径换内容 —— 信息变了，实体没换。
    func testA2SamePathDifferentContent() throws {
        let (url, db) = try open("a2")
        defer { db.close(); cleanup(url) }
        let root = try makeWorkRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("settled v1", to: root, name: "doc.md")
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let s = try mkSettlement(db, stateID: "A2", value: "v1")
        try db.linkSettlementToExternalFile(settlementID: s, binding: "content",
                                            rootID: "work", relativePath: "doc.md")
        let oldAddress = try XCTUnwrap(db.resolveIndexIdentity("file:work/doc.md")).objectID
        try write("settled v2", to: root, name: "doc.md")
        let r = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let history = try db.dependencyHistory("file:work/doc.md")
        var fields = ["changed": "\(r.changed)",
                      "invalidated": "\(r.invalidatedSettlements)",
                      "history": history.map { "\($0.reason)@\($0.revision)" }.joined(separator: ",")]
        if let readable = try? db.readObject(oldAddress) {
            fields["old_bytes"] = String(data: readable, encoding: .utf8) ?? "?"
        }
        try report("A2", db, s, fields)
    }

    // A4：删掉源文件 —— 原件不可达，信息还在不在。
    func testA4SourceDeleted() throws {
        let (url, db) = try open("a4")
        defer { db.close(); cleanup(url) }
        let root = try makeWorkRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("settled text", to: root, name: "doc.md")
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let s = try mkSettlement(db, stateID: "A4", value: "v1")
        try db.linkSettlementToExternalFile(settlementID: s, binding: "content",
                                            rootID: "work", relativePath: "doc.md")
        try FileManager.default.removeItem(at: root.appendingPathComponent("doc.md"))
        let r = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let status = try db.listExternalFiles(rootID: "work")
            .first(where: { $0.relativePath == "doc.md" })?.status ?? "?"
        let hits = try db.searchSettledContent(query: "settled", rootID: "work").count
        try report("A4", db, s, ["removed": "\(r.removed)",
                                 "invalidated": "\(r.invalidatedSettlements)",
                                 "status": status, "search_hits": "\(hits)"])
    }

    // A6：负控 —— 改一个没被依赖的文件，什么都不该发生。
    func testA6UnrelatedFileChanged() throws {
        let (url, db) = try open("a6")
        defer { db.close(); cleanup(url) }
        let root = try makeWorkRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("bound v1", to: root, name: "bound.md")
        try write("other v1", to: root, name: "other.md")
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let s = try mkSettlement(db, stateID: "A6", value: "v1")
        try db.linkSettlementToExternalFile(settlementID: s, binding: "content",
                                            rootID: "work", relativePath: "bound.md")
        try write("other v2", to: root, name: "other.md")
        let r = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        try report("A6", db, s, ["changed": "\(r.changed)",
                                 "invalidated": "\(r.invalidatedSettlements)"])
    }
}
