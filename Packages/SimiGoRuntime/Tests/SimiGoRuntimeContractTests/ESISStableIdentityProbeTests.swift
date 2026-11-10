import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// 把身份从「路径」换成「条目名」，改名和改内容各测一次。
///
/// 现状：依赖身份 = `settlement:<id> -> file:work/<path>`，路径内嵌。
/// 这里试另一种取法：身份 = `item:合同额`，路径只作来源写进 reason。
/// 只量一件事：这样换过之后，改名会不会碰它、改内容会不会留下版本。
///
///   swift test --filter ESISStableIdentityProbeTests 2>&1 | grep '^STABLE_'
final class ESISStableIdentityProbeTests: XCTestCase {

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-stable-\(UUID().uuidString)-\(name).sqlite3")
    }

    private func cleanup(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func makeWorkRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-stable-work-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
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

    private func probe(_ name: String, _ fields: [String: String]) {
        var parts: [String] = []
        for key in fields.keys.sorted() { parts.append("\(key)=\(fields[key]!)") }
        print("STABLE_\(name) " + parts.joined(separator: " "))
    }

    // H1：身份 = 条目名，然后改名。看它动不动。
    func testH1RenameWithStableIdentity() throws {
        let (url, db) = try open("h1")
        defer { db.close(); cleanup(url) }
        let root = try makeWorkRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("合同额：100万元\n".utf8).write(to: root.appendingPathComponent("old.md"))
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)

        let s = try mkSettlement(db, stateID: "H1", value: "v1")
        let addr = try db.writeObject(Data("合同额：100万元\n".utf8))
        try db.appendDependency(dependencyID: "item:合同额", contentAddress: addr,
                                reason: "来源:file:work/old.md")

        try FileManager.default.moveItem(at: root.appendingPathComponent("old.md"),
                                         to: root.appendingPathComponent("new.md"))
        let r = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let hist = try db.dependencyHistory("item:合同额")
        try probe("H1", [
            "validity": try db.settlementValidity(s),
            "revision": "\(hist.last?.revision ?? 0)",
            "entries": "\(hist.count)",
            "reconcile_changed": "\(r.changed)", "reconcile_removed": "\(r.removed)",
            "reconcile_invalidated": "\(r.invalidatedSettlements)",
            "reason": hist.last?.reason ?? "-",
        ])
    }

    // H2：同一身份，内容改成 200 万，另起一个版本。谁判旧版本失效。
    func testH2ContentChangeWithStableIdentity() throws {
        let (url, db) = try open("h2")
        defer { db.close(); cleanup(url) }
        let root = try makeWorkRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("合同额：100万元\n".utf8).write(to: root.appendingPathComponent("doc.md"))
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)

        let s = try mkSettlement(db, stateID: "H2", value: "v1")
        let v1 = try db.writeObject(Data("合同额：100万元\n".utf8))
        try db.appendDependency(dependencyID: "item:合同额", contentAddress: v1,
                                reason: "来源:file:work/doc.md")

        // 人改口，ES 抽到新值，登记成同一身份的下一版。
        try Data("合同额：200万元\n".utf8).write(to: root.appendingPathComponent("doc.md"))
        let r = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let v2 = try db.writeObject(Data("合同额：200万元\n".utf8))
        try db.appendDependency(dependencyID: "item:合同额", contentAddress: v2,
                                reason: "来源:file:work/doc.md")

        let hist = try db.dependencyHistory("item:合同额")
        let v1Readable = (try? db.readObject(v1)) != nil
        try probe("H2", [
            "validity": try db.settlementValidity(s),
            "entries": "\(hist.count)",
            "revisions": hist.map { "\($0.revision)" }.joined(separator: ","),
            "v1_still_readable": v1Readable ? "yes" : "no",
            "v1_eq_v2": v1 == v2 ? "yes" : "no",
            "reconcile_changed": "\(r.changed)",
            "reconcile_invalidated": "\(r.invalidatedSettlements)",
        ])
    }

    // H3：身份用内容地址，两个来源的同一段字会合并成一个身份。
    func testH3ContentAddressAsIdentity() throws {
        let (url, db) = try open("h3")
        defer { db.close(); cleanup(url) }
        let a = try db.writeObject(Data("合同额：100万元\n".utf8))
        let b = try db.writeObject(Data("合同额：100万元\n".utf8))
        try db.appendDependency(dependencyID: "addr:\(a)", contentAddress: a, reason: "来源:A")
        try db.appendDependency(dependencyID: "addr:\(b)", contentAddress: b, reason: "来源:B")
        let sameIdentity = "addr:\(a)" == "addr:\(b)"
        let histA = try db.dependencyHistory("addr:\(a)")
        let histB = try db.dependencyHistory("addr:\(b)")
        try probe("H3", [
            "addr_a": String(a.prefix(12)), "addr_b": String(b.prefix(12)),
            "same_identity": sameIdentity ? "yes" : "no",
            "entries_a": "\(histA.count)", "entries_b": "\(histB.count)",
            "two_origins_one_object": sameIdentity ? "yes" : "no",
        ])
    }
}
