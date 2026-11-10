import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// 换尺子：同一组动作，改按「信息」量，不再按「状态」量。
///
/// 失效判据现在落在位置上（文件行在不在、路径对不对）。这里只量三件与位置
/// 无关的事：
///   1. 结算当初绑定的那个内容地址，字节还在不在库里（readObject 自带 digest 校验）；
///   2. 那个地址里的字节，和现在该路径上的字节，是不是同一份；
///   3. 同一份内容出现在两个文件里时，库里是一个对象还是两个。
/// 打印 `PROBE_*`，不断言语义，只交读数。
///
///   swift test --filter ESISContentIdentityProbeTests 2>&1 | grep '^PROBE_'
final class ESISContentIdentityProbeTests: XCTestCase {

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-probe-\(UUID().uuidString)-\(name).sqlite3")
    }

    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func makeWorkRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-probe-work-\(UUID().uuidString)")
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

    /// 结算当初绑定的内容地址（依赖边的 content_address）。
    private func boundAddress(_ db: ESISDatabase, _ settlement: String, _ path: String) throws -> String {
        try db.dependencyHistory("settlement:\(settlement) -> file:work/\(path)")
            .last?.contentAddress ?? "-"
    }

    private func text(_ db: ESISDatabase, _ address: String) -> String {
        guard address != "-", let data = try? db.readObject(address) else { return "UNREADABLE" }
        return String(data: data, encoding: .utf8) ?? "BINARY"
    }

    private func atPath(_ db: ESISDatabase, _ path: String) throws -> String {
        try db.resolveIndexIdentity("file:work/\(path)")?.objectID ?? "-"
    }

    private func probe(_ name: String, _ db: ESISDatabase, _ settlement: String?,
                       _ fields: [String: String]) throws {
        let validity = try settlement.map { try db.settlementValidity($0) } ?? "n/a"
        var parts = ["validity=\(validity)",
                     "file_contents=\(try db.count("file_contents"))",
                     "objects=\(try db.count("is_objects"))",
                     "dep_entries=\(try db.count("is_dependency_entries"))"]
        for key in fields.keys.sorted() { parts.append("\(key)=\(fields[key]!)") }
        print("PROBE_\(name) " + parts.joined(separator: " "))
    }

    // C1：同字节改名 —— 位置变了，绑定的地址该不该跟着变。
    func testC1RenameSameBytes() throws {
        let (url, db) = try open("c1")
        defer { db.close(); cleanup(url) }
        let root = try makeWorkRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("settled text", to: root, name: "old.md")
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let s = try mkSettlement(db, stateID: "C1", value: "v1")
        try db.linkSettlementToExternalFile(settlementID: s, binding: "content",
                                            rootID: "work", relativePath: "old.md")
        let bound = try boundAddress(db, s, "old.md")
        try FileManager.default.moveItem(at: root.appendingPathComponent("old.md"),
                                         to: root.appendingPathComponent("new.md"))
        let r = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let now = try atPath(db, "new.md")
        try probe("C1", db, s, [
            "bound_addr": String(bound.prefix(12)),
            "newpath_addr": String(now.prefix(12)),
            "same_addr": bound == now ? "yes" : "no",
            "bound_bytes": text(db, bound),
            "reused": "\(r.reused)", "changed": "\(r.changed)",
            "removed": "\(r.removed)", "invalidated": "\(r.invalidatedSettlements)",
            "search_old": "\(try db.searchSettledContent(query: "settled text", rootID: "work").count)",
        ])
    }

    // C2：同路径换内容 —— 绑定的旧地址里的字节，还在不在。
    func testC2SamePathDifferentContent() throws {
        let (url, db) = try open("c2")
        defer { db.close(); cleanup(url) }
        let root = try makeWorkRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("settled v1", to: root, name: "doc.md")
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let s = try mkSettlement(db, stateID: "C2", value: "v1")
        try db.linkSettlementToExternalFile(settlementID: s, binding: "content",
                                            rootID: "work", relativePath: "doc.md")
        let bound = try boundAddress(db, s, "doc.md")
        try write("settled v2", to: root, name: "doc.md")
        let r = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let now = try atPath(db, "doc.md")
        try probe("C2", db, s, [
            "bound_addr": String(bound.prefix(12)),
            "now_addr": String(now.prefix(12)),
            "same_addr": bound == now ? "yes" : "no",
            "bound_bytes": text(db, bound),
            "now_bytes": text(db, now),
            "changed": "\(r.changed)", "invalidated": "\(r.invalidatedSettlements)",
            "search_v1": "\(try db.searchSettledContent(query: "settled v1", rootID: "work").count)",
            "search_v2": "\(try db.searchSettledContent(query: "settled v2", rootID: "work").count)",
        ])
    }

    // C3：两个文件同内容 —— 去重：一个对象还是两个。
    func testC3TwoFilesSameBytes() throws {
        let (url, db) = try open("c3")
        defer { db.close(); cleanup(url) }
        let root = try makeWorkRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("shared text", to: root, name: "a.md")
        try write("shared text", to: root, name: "b.md")
        let r = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let sa = try mkSettlement(db, stateID: "C3a", value: "va")
        let sb = try mkSettlement(db, stateID: "C3b", value: "vb")
        try db.linkSettlementToExternalFile(settlementID: sa, binding: "content",
                                            rootID: "work", relativePath: "a.md")
        try db.linkSettlementToExternalFile(settlementID: sb, binding: "content",
                                            rootID: "work", relativePath: "b.md")
        let addrA = try atPath(db, "a.md")
        let addrB = try atPath(db, "b.md")
        try probe("C3", db, sa, [
            "addr_a": String(addrA.prefix(12)), "addr_b": String(addrB.prefix(12)),
            "same_addr": addrA == addrB ? "yes" : "no",
            "objects_created": "\(r.objectsCreated)", "deduplicated": "\(r.deduplicated)",
            "settled": "\(r.settled)", "reused": "\(r.reused)",
            "b_switch_reused": "\(try db.settlementValidity(sb))",
        ])
    }

    // C4：删掉源文件 —— 地址里的字节还在不在，检索还找不找得到。
    func testC4SourceDeleted() throws {
        let (url, db) = try open("c4")
        defer { db.close(); cleanup(url) }
        let root = try makeWorkRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("settled text", to: root, name: "doc.md")
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let s = try mkSettlement(db, stateID: "C4", value: "v1")
        try db.linkSettlementToExternalFile(settlementID: s, binding: "content",
                                            rootID: "work", relativePath: "doc.md")
        let bound = try boundAddress(db, s, "doc.md")
        try FileManager.default.removeItem(at: root.appendingPathComponent("doc.md"))
        let r = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let status = try db.listExternalFiles(rootID: "work")
            .first(where: { $0.relativePath == "doc.md" })?.status ?? "?"
        let stillIndexed = try atPath(db, "doc.md")
        try probe("C4", db, s, [
            "bound_addr": String(bound.prefix(12)),
            "bound_bytes": text(db, bound),
            "index_addr_still_there": stillIndexed == "-" ? "no" : "yes",
            "removed": "\(r.removed)", "invalidated": "\(r.invalidatedSettlements)",
            "status": status,
            "search_exact": "\(try db.searchSettledContent(query: "settled text", rootID: "work").count)",
        ])
    }
    // C5：两个文件同内容 —— 检索层去不去重。
    func testC5SearchDuplicates() throws {
        let (url, db) = try open("c5")
        defer { db.close(); cleanup(url) }
        let root = try makeWorkRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("shared text", to: root, name: "a.md")
        try write("shared text", to: root, name: "b.md")
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let hits = try db.searchSettledContent(query: "shared text", rootID: "work")
        try probe("C5", db, nil, [
            "search_hits": "\(hits.count)",
            "distinct_paths": "\(Set(hits.map { $0.relativePath }).count)",
            "distinct_text": "\(Set(hits.map { $0.lineText }).count)",
        ])
    }

    // C6：改名后把结算重挂到新路径 —— 拓扑里是一条边的两个版本，还是两条边。
    func testC6RelinkAfterRename() throws {
        let (url, db) = try open("c6")
        defer { db.close(); cleanup(url) }
        let root = try makeWorkRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("settled text", to: root, name: "old.md")
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let s = try mkSettlement(db, stateID: "C6", value: "v1")
        try db.linkSettlementToExternalFile(settlementID: s, binding: "content",
                                            rootID: "work", relativePath: "old.md")
        try FileManager.default.moveItem(at: root.appendingPathComponent("old.md"),
                                         to: root.appendingPathComponent("new.md"))
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        try db.linkSettlementToExternalFile(settlementID: s, binding: "content",
                                            rootID: "work", relativePath: "new.md")
        let oldHist = try db.dependencyHistory("settlement:\(s) -> file:work/old.md")
        let newHist = try db.dependencyHistory("settlement:\(s) -> file:work/new.md")
        var addrSame = "-"
        if let a = oldHist.last?.contentAddress, let b = newHist.last?.contentAddress {
            addrSame = a == b ? "yes" : "no"
        }
        try probe("C6", db, s, [
            "dep_ids_old": "\(oldHist.count)", "dep_ids_new": "\(newHist.count)",
            "addr_same": addrSame,
            "validity_after_relink": "\(try db.settlementValidity(s))",
        ])
    }
}
