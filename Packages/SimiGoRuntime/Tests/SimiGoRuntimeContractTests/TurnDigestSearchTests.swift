import XCTest

@testable import SimiGoRuntimeContract

final class TurnDigestSearchTests: XCTestCase {
    private func tempURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("simigo-digest-search-\(name)-\(UUID().uuidString).sqlite3")
    }

    private func cleanup(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func open(_ name: String) throws -> (URL, ESISDatabase) {
        let url = tempURL(name)
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        return (url, db)
    }

    /// 摘要进检索：只在摘要里出现的词也能捞到那一轮，而且引用落在原文上。
    func testDigestIsFindableAndCitesTheRound() throws {
        let (url, db) = try open("hit")
        defer { db.close(); cleanup(url) }
        let loop = InformationLoop(database: db)

        try db.recordExternalTurn(
            sessionID: "s-d", provider: "local", requestID: "r1",
            userText: "外部请求：泵房那条线", model: nil, createdAt: Date())
        try db.recordExternalResponse(
            sessionID: "s-d", provider: "local", requestID: "r1",
            assistantText: "外部回答：泵房按两台一备布置", model: nil, createdAt: Date())
        _ = try db.verifyExternalTurn(
            sessionID: "s-d", requestID: "r1", verifiedAt: Date())
        let answerID = try db.chatIndexRows(sessionIDs: ["s-d"])
            .first { $0.role == "assistant" }?.messageID

        try db.recordTurnDigest(
            sessionID: "s-d", turnIndex: 1, answerMessageID: answerID,
            digest: "这一轮定的是泵房布置的选型口径", keywords: "选型口径 泵房")

        // 「选型口径」只在摘要里，原文没有——只有摘要这一路能命中。
        let hits = try loop.resolve(.init(
            sessionID: "s-d", query: "选型口径", includeChat: true,
            chatSessionIDs: ["s-d"]))
        XCTAssertTrue(
            hits.hits.contains { $0.kind == "turn" && $0.locator == "session:s-d#t1" },
            "摘要命中要给出一条 turn 引用，实际：\(hits.hits.map(\.itemID))")

        // 不要 chat 的人，也不该拿到 chat 的摘要。
        let withoutChat = try loop.resolve(.init(
            sessionID: "s-d", query: "选型口径", includeChat: false,
            chatSessionIDs: ["s-d"]))
        XCTAssertFalse(withoutChat.hits.contains { $0.kind == "turn" })
    }

    /// 两行输出解析：正常、缺行、多余标点。
    func testDigestParse() {
        let ok = TurnDigestText.parse(
            "摘要：这一轮把区间的两个时钟分开了。\n关键词：双时钟 区间 断点")
        XCTAssertEqual(ok?.digest, "这一轮把区间的两个时钟分开了。")
        XCTAssertEqual(ok?.keywords, ["双时钟", "区间", "断点"])

        XCTAssertNil(TurnDigestText.parse("这一轮说了点什么"))
        XCTAssertNil(TurnDigestText.parse("摘要：只有摘要没有关键词"))
        XCTAssertNil(TurnDigestText.parse("摘要：\n关键词：空摘要"))

        let messy = TurnDigestText.parse("**摘要：**带星号的一行\n**关键词：**甲，乙、丙")
        XCTAssertEqual(messy?.keywords, ["甲", "乙", "丙"])
    }
}
