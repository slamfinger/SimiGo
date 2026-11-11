import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// 「格式变了、内容没变」：Word/Excel 换存法，字节全变，文字数字没变。
///
/// 上一组探针只量了「字节相同」（改名）。这一组量的是相反方向的同：
/// 字节全不同，抽出来的文字/数字完全相同。对照组在
/// `Fixtures/format-swap/`，由 `make_fixtures.py` 生成；`*.extract.txt`
/// 是**抽取结果**（python-docx / openpyxl 抽的），代表 agent 那一次动作，
/// 不代表 SimiGo 有抽取能力。
///
///   swift test --filter ESISFormatSwapProbeTests 2>&1 | grep '^SWAP_'
final class ESISFormatSwapProbeTests: XCTestCase {

    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/format-swap")

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: Self.fixtures.appendingPathComponent(name))
    }

    private func extraction(_ name: String) throws -> String {
        try String(contentsOf: Self.fixtures.appendingPathComponent(name + ".extract.txt"),
                   encoding: .utf8)
    }

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-swap-\(UUID().uuidString)-\(name).sqlite3")
    }

    private func cleanup(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func makeWorkRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-swap-work-\(UUID().uuidString)")
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

    private func digest(_ data: Data) -> String { NativeSHA256.hexDigest(data) }

    private func boundAddress(_ db: ESISDatabase, _ settlement: String, _ path: String) throws -> String {
        try db.dependencyHistory("settlement:\(settlement) -> file:work/\(path)")
            .last?.contentAddress ?? "-"
    }

    private func text(_ db: ESISDatabase, _ address: String) -> String {
        guard address != "-", let data = try? db.readObject(address) else { return "UNREADABLE" }
        return String(data: data, encoding: .utf8) ?? "BINARY"
    }

    private func swap(_ root: URL, remove: String, put fixtureName: String, as name: String) throws {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(remove))
        try fixture(fixtureName).write(to: root.appendingPathComponent(name))
    }

    private func probe(_ name: String, _ db: ESISDatabase, _ settlement: String,
                       _ fields: [String: String]) throws {
        var parts = ["validity=\(try db.settlementValidity(settlement))",
                     "file_contents=\(try db.count("file_contents"))",
                     "objects=\(try db.count("is_objects"))"]
        for key in fields.keys.sorted() { parts.append("\(key)=\(fields[key]!)") }
        print("SWAP_\(name) " + parts.joined(separator: " "))
    }

    // F1：同一份 docx 重存一次 —— 同格式、同大小、字节全变、文字没变。
    func testF1DocxResaved() throws {
        let (url, db) = try open("f1")
        defer { db.close(); cleanup(url) }
        let root = try makeWorkRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try swap(root, remove: "nothing", put: "contract-v1.docx", as: "doc.docx")
        let before = try fixture("contract-v1.docx")
        let after = try fixture("contract-v1-resaved.docx")
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let s = try mkSettlement(db, stateID: "F1", value: "v1")
        try db.linkSettlementToExternalFile(settlementID: s, binding: "content",
                                            rootID: "work", relativePath: "doc.docx")
        let bound = try boundAddress(db, s, "doc.docx")
        try swap(root, remove: "doc.docx", put: "contract-v1-resaved.docx", as: "doc.docx")
        let r = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        try probe("F1", db, s, [
            "size_before": "\(before.count)", "size_after": "\(after.count)",
            "bytes_same": digest(before) == digest(after) ? "yes" : "no",
            "text_same": try extraction("contract-v1.docx") == extraction("contract-v1-resaved.docx")
                ? "yes" : "no",
            "bound_addr": String(bound.prefix(12)),
            "has_edge": bound == "-" ? "no" : "yes",
            "changed": "\(r.changed)", "invalidated": "\(r.invalidatedSettlements)",
            "skipped": "\(r.skippedBinaryOrLarge)", "settled": "\(r.settled)",
        ])
    }

    // F2：docx 换成 txt —— 换格式，文字没变。
    func testF2DocxToTxt() throws {
        let (url, db) = try open("f2")
        defer { db.close(); cleanup(url) }
        let root = try makeWorkRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try swap(root, remove: "nothing", put: "contract-v1.docx", as: "doc.docx")
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let s = try mkSettlement(db, stateID: "F2", value: "v1")
        try db.linkSettlementToExternalFile(settlementID: s, binding: "content",
                                            rootID: "work", relativePath: "doc.docx")
        let bound = try boundAddress(db, s, "doc.docx")
        try swap(root, remove: "doc.docx", put: "contract-v1.txt", as: "doc.txt")
        let r = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        try probe("F2", db, s, [
            "bytes_same": "no",
            "text_same": try extraction("contract-v1.docx") == extraction("contract-v1.txt")
                ? "yes" : "no",
            "bound_addr": String(bound.prefix(12)),
            "has_edge": bound == "-" ? "no" : "yes",
            "removed": "\(r.removed)", "changed": "\(r.changed)",
            "invalidated": "\(r.invalidatedSettlements)",
            "skipped": "\(r.skippedBinaryOrLarge)", "settled": "\(r.settled)",
        ])
    }

    // F3：xlsx 换成 csv —— 换格式，数字没变。
    func testF3XlsxToCsv() throws {
        let (url, db) = try open("f3")
        defer { db.close(); cleanup(url) }
        let root = try makeWorkRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try swap(root, remove: "nothing", put: "amount-v1.xlsx", as: "sheet.xlsx")
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        let s = try mkSettlement(db, stateID: "F3", value: "v1")
        try db.linkSettlementToExternalFile(settlementID: s, binding: "content",
                                            rootID: "work", relativePath: "sheet.xlsx")
        try swap(root, remove: "sheet.xlsx", put: "amount-v1.csv", as: "sheet.csv")
        let r = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        try probe("F3", db, s, [
            "bytes_same": "no",
            "text_same": try extraction("amount-v1.xlsx") == extraction("amount-v1.csv")
                ? "yes" : "no",
            "removed": "\(r.removed)", "invalidated": "\(r.invalidatedSettlements)",
            "skipped": "\(r.skippedBinaryOrLarge)", "settled": "\(r.settled)",
            "search_1000000": "\(try db.searchSettledContent(query: "1000000", rootID: "work").count)",
        ])
    }

    // F4：同一份信息，两种绑法。文件级 vs 文本级，换格式后各判什么。
    func testF4FileBindingVersusTextBinding() throws {
        let (url, db) = try open("f4")
        defer { db.close(); cleanup(url) }
        let root = try makeWorkRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try swap(root, remove: "nothing", put: "contract-v1.docx", as: "doc.docx")
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)

        // 绑文件字节的结算。
        let fileBound = try mkSettlement(db, stateID: "F4file", value: "vf")
        try db.linkSettlementToExternalFile(settlementID: fileBound, binding: "content",
                                            rootID: "work", relativePath: "doc.docx")

        // 绑抽取文字的结算 —— 地址来自写进对象库的文本，不来自文件字节。
        let textAddress = try db.writeObject(Data(try extraction("contract-v1.docx").utf8))
        let textBound = try mkSettlement(db, stateID: "F4text", value: "vt")
        try db.appendDependency(dependencyID: "settlement:\(textBound) -> text:contract",
                                contentAddress: textAddress, reason: "text-extraction")

        // 换格式：docx → txt，文字一字未改。
        try swap(root, remove: "doc.docx", put: "contract-v1.txt", as: "doc.txt")
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)

        let textAddressNow = digest(Data(try extraction("contract-v1.txt").utf8))
        let parts = [
            "file_bound_validity=\(try db.settlementValidity(fileBound))",
            "text_bound_validity=\(try db.settlementValidity(textBound))",
            "text_addr=\(String(textAddress.prefix(12)))",
            "text_addr_after_swap=\(String(textAddressNow.prefix(12)))",
            "text_addr_same=\(textAddress == textAddressNow ? "yes" : "no")",
        ]
        print("SWAP_F4 " + parts.joined(separator: " "))
    }
    // F5：文本级绑定的负控 —— 文字真变了，有没有触发器把它判掉。
    func testF5TextBindingOnRealChange() throws {
        let (url, db) = try open("f5")
        defer { db.close(); cleanup(url) }
        let root = try makeWorkRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try swap(root, remove: "nothing", put: "contract-v1.txt", as: "doc.txt")
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)

        let textBound = try mkSettlement(db, stateID: "F5text", value: "vt")
        let before = try db.writeObject(Data(try extraction("contract-v1.txt").utf8))
        try db.appendDependency(dependencyID: "settlement:\(textBound) -> text:contract",
                                contentAddress: before, reason: "text-extraction")

        // 合同额从 100 万改成 200 万：信息真的变了。
        try Data("合同额：200万元\n".utf8).write(to: root.appendingPathComponent("doc.txt"))
        let r = try db.settleWorkRootContents(rootID: "work", rootURL: root)

        let after = NativeSHA256.hexDigest(Data("合同额：200万元\n".utf8))
        let parts = [
            "text_bound_validity=\(try db.settlementValidity(textBound))",
            "text_addr_before=\(String(before.prefix(12)))",
            "text_addr_after=\(String(after.prefix(12)))",
            "text_addr_same=\(before == after ? "yes" : "no")",
            "changed=\(r.changed) invalidated=\(r.invalidatedSettlements)",
        ]
        print("SWAP_F5 " + parts.joined(separator: " "))
    }
}
