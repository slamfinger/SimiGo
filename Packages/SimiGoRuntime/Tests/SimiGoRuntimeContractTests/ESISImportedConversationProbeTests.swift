import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// 真正的对照组：文字信息本身，不带媒介。
///
/// docx 抽取只是「怎么把字弄进来」的一种方式；会话导入是另一种，而且没有
/// 文件、没有路径、没有根。这组只问一件事：把依赖落在**那段文字**上，
/// 它能不能被依赖、能不能被复用、什么时候会失效。
///
///   swift test --filter ESISImportedConversationProbeTests 2>&1 | grep '^IMPORT_'
final class ESISImportedConversationProbeTests: XCTestCase {

    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/format-swap")

    /// 与 docx 抽出来的字逐字相同（含行尾换行）。
    private let importedText = "合同额：100万元\n"

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-import-\(UUID().uuidString)-\(name).sqlite3")
    }

    private func cleanup(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func makeWorkRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-import-work-\(UUID().uuidString)")
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

    /// 导入一轮会话，返回 user 行的对象地址。
    @discardableResult
    private func importRound(_ db: ESISDatabase, session: String, text: String,
                             reply: String) throws -> String {
        let user = try db.appendChatMessage(sessionID: session, role: "user", content: text,
                                            model: "m", createdAt: Date())
        _ = try db.commitChatTurn(sessionID: session, userMessageID: user,
                                  assistantText: reply, model: "m", createdAt: Date())
        return try db.resolveIndexIdentity("chat:\(session)/\(user)")?.objectID ?? "-"
    }

    private func probe(_ name: String, _ fields: [String: String]) {
        var parts: [String] = []
        for key in fields.keys.sorted() { parts.append("\(key)=\(fields[key]!)") }
        print("IMPORT_\(name) " + parts.joined(separator: " "))
    }

    // G1：导入一段会话文字，把结算的依赖落在它上面。全程没有文件。
    func testG1DependOnImportedConversation() throws {
        let (url, db) = try open("g1")
        defer { db.close(); cleanup(url) }

        let addr = try importRound(db, session: "imp", text: importedText,
                                   reply: "记下：合同额=1000000 元")
        let s = try mkSettlement(db, stateID: "G1", value: "v1")
        try db.appendDependency(dependencyID: "settlement:\(s) -> chat:imp",
                                contentAddress: addr, reason: "imported-conversation")

        let readable = (try? db.readObject(addr)).flatMap { String(data: $0, encoding: .utf8) } ?? "UNREADABLE"
        try probe("G1", [
            "addr": String(addr.prefix(12)),
            "addr_eq_sha": addr == NativeSHA256.hexDigest(Data(importedText.utf8)) ? "yes" : "no",
            "bytes": readable.trimmingCharacters(in: .whitespacesAndNewlines),
            "validity": try db.settlementValidity(s),
            "chat_hits": "\(try db.searchChatMessages(query: "合同额", sessionID: "imp").count)",
            "file_contents": "\(try db.count("file_contents"))",
            "external_files": "\(try db.count("external_files"))",
            "information_items": "\(try db.count("information_items"))",
            "objects": "\(try db.count("is_objects"))",
        ])
    }

    // G2：同一段字，一种从 docx 抽、一种从会话导入——是不是同一个地址。
    func testG2SameTextTwoOrigins() throws {
        let (url, db) = try open("g2")
        defer { db.close(); cleanup(url) }

        let fromChat = try importRound(db, session: "imp2", text: importedText, reply: "ok")
        let extraction = try String(contentsOf: Self.fixtures
            .appendingPathComponent("contract-v1.docx.extract.txt"), encoding: .utf8)
        let fromDocx = try db.writeObject(Data(extraction.utf8))
        let fromTxt = try db.writeObject(Data(try String(contentsOf: Self.fixtures
            .appendingPathComponent("contract-v1.txt.extract.txt"), encoding: .utf8).utf8))

        try probe("G2", [
            "chat_addr": String(fromChat.prefix(12)),
            "docx_addr": String(fromDocx.prefix(12)),
            "txt_addr": String(fromTxt.prefix(12)),
            "chat_eq_docx": fromChat == fromDocx ? "yes" : "no",
            "same_text": extraction == importedText ? "yes" : "no",
            "objects": "\(try db.count("is_objects"))",
        ])
    }

    // G3：同一段字导入两次（两个会话）——对象几个、索引几条。
    func testG3ImportTwiceSameText() throws {
        let (url, db) = try open("g3")
        defer { db.close(); cleanup(url) }
        let before = try db.count("is_objects")
        let a = try importRound(db, session: "imp3a", text: importedText, reply: "ok a")
        let b = try importRound(db, session: "imp3b", text: importedText, reply: "ok b")
        try probe("G3", [
            "addr_a": String(a.prefix(12)), "addr_b": String(b.prefix(12)),
            "same_addr": a == b ? "yes" : "no",
            "objects_added": "\(try db.count("is_objects") - before)",
            "chat_rows": "\(try db.listChatMessages(sessionID: "imp3a").count + db.listChatMessages(sessionID: "imp3b").count)",
            "information_items": "\(try db.count("information_items"))",
        ])
    }

    // G4：会话里改口——同一句话改成 200 万。旧依赖有没有被碰。
    func testG4ConversationRestated() throws {
        let (url, db) = try open("g4")
        defer { db.close(); cleanup(url) }
        let first = try importRound(db, session: "imp4", text: importedText, reply: "记下 100 万")
        let s = try mkSettlement(db, stateID: "G4", value: "v1")
        try db.appendDependency(dependencyID: "settlement:\(s) -> chat:imp4",
                                contentAddress: first, reason: "imported-conversation")

        let second = try importRound(db, session: "imp4", text: "合同额：200万元\n",
                                     reply: "改记 200 万")

        let firstReadable = (try? db.readObject(first)) != nil
        try probe("G4", [
            "first_addr": String(first.prefix(12)),
            "second_addr": String(second.prefix(12)),
            "addr_changed": first == second ? "no" : "yes",
            "first_still_readable": firstReadable ? "yes" : "no",
            "validity": try db.settlementValidity(s),
            "history_rows": "\(try db.listChatMessages(sessionID: "imp4").count)",
        ])
    }

    // G5：同一个结算两种来源——删掉文件，会话那条还在。
    func testG5FileGoneConversationStays() throws {
        let (url, db) = try open("g5")
        defer { db.close(); cleanup(url) }
        let root = try makeWorkRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try Data(importedText.utf8).write(to: root.appendingPathComponent("doc.txt"))
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)

        let fromChat = try importRound(db, session: "imp5", text: importedText, reply: "ok")
        let fileBound = try mkSettlement(db, stateID: "G5file", value: "vf")
        try db.linkSettlementToExternalFile(settlementID: fileBound, binding: "content",
                                            rootID: "work", relativePath: "doc.txt")
        let chatBound = try mkSettlement(db, stateID: "G5chat", value: "vc")
        try db.appendDependency(dependencyID: "settlement:\(chatBound) -> chat:imp5",
                                contentAddress: fromChat, reason: "imported-conversation")

        try FileManager.default.removeItem(at: root.appendingPathComponent("doc.txt"))
        _ = try db.settleWorkRootContents(rootID: "work", rootURL: root)

        try probe("G5", [
            "file_bound": try db.settlementValidity(fileBound),
            "chat_bound": try db.settlementValidity(chatBound),
            "chat_addr_readable": (try? db.readObject(fromChat)) != nil ? "yes" : "no",
            "chat_hits": "\(try db.searchChatMessages(query: "合同额", sessionID: "imp5").count)",
        ])
    }
}
