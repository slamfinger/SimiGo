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

    /// 补摘要按钮的数据源：缺口里要带上轮号、问题和回答；补完就空。
    func testUndigestedTurnsCarryTextsAndClearAfterWrite() throws {
        let (url, db) = try open("gap")
        defer { db.close(); cleanup(url) }

        try db.recordExternalTurn(
            sessionID: "s-g", provider: "local", requestID: "g1",
            userText: "问：闸门什么时候开", model: nil, createdAt: Date())
        try db.recordExternalResponse(
            sessionID: "s-g", provider: "local", requestID: "g1",
            assistantText: "答：汛前三天", model: nil, createdAt: Date())
        try db.recordTurnIndex(
            sessionID: "s-g", turnIndex: 1, requestID: "g1", at: Date())

        let gap = try db.undigestedTurns()
        XCTAssertEqual(gap.count, 1)
        XCTAssertEqual(gap.first?.sessionID, "s-g")
        XCTAssertEqual(gap.first?.turnIndex, 1)
        XCTAssertEqual(gap.first?.question, "问：闸门什么时候开")
        XCTAssertEqual(gap.first?.answer, "答：汛前三天")

        try db.recordTurnDigest(
            sessionID: "s-g", turnIndex: 1, digest: "定了开闸时点", keywords: "闸门")
        XCTAssertTrue(try db.undigestedTurns().isEmpty)
    }

    /// 只换词：正文、来源标记、写入时间一个字都不动，旧词不再把这一轮捞出来。
    func testReplaceTurnKeywordsKeepsDigestModelAndTime() throws {
        let (url, db) = try open("kw-replace")
        defer { db.close(); cleanup(url) }

        try db.recordTurnDigest(
            sessionID: "s-k", turnIndex: 1,
            digest: "这一轮定的是泵房布置的选型口径",
            keywords: "甲 乙", model: "local:test",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let before = try XCTUnwrap(try db.turnDigest(sessionID: "s-k", turnIndex: 1))
        XCTAssertEqual(try db.count("turn_keywords"), 2)

        try db.replaceTurnKeywords(
            sessionID: "s-k", turnIndex: 1, keywords: ["甲", "乙", "丙"],
            createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        let after = try XCTUnwrap(try db.turnDigest(sessionID: "s-k", turnIndex: 1))

        XCTAssertEqual(after.digest, before.digest)
        XCTAssertEqual(after.model, before.model)
        XCTAssertEqual(after.createdAt, before.createdAt, "改词不该改写入时间")
        XCTAssertEqual(after.keywords, ["甲", "乙", "丙"])
        XCTAssertEqual(try db.count("turn_keywords"), 3)

        // 缩词也一样：旧关联要摘掉，否则改过的词还能把这一轮捞出来。
        try db.replaceTurnKeywords(sessionID: "s-k", turnIndex: 1, keywords: ["甲"])
        XCTAssertEqual(try db.count("turn_keywords"), 1)
        XCTAssertTrue(try db.turnDigestRows(matchingAny: ["乙"]).isEmpty)
        XCTAssertFalse(try db.turnDigestRows(matchingAny: ["甲"]).isEmpty)

        // 没有那一行就写不了，也不许凭空造一行。
        XCTAssertThrowsError(
            try db.replaceTurnKeywords(
                sessionID: "s-k", turnIndex: 9, keywords: ["甲"]))
        XCTAssertNil(try db.turnDigest(sessionID: "s-k", turnIndex: 9))
    }

    /// 词不够的轮次要带上问题和回答正文；补到够数之后就不再出现在列表里。
    func testThinKeywordTurnsCarryTexts() throws {
        let (url, db) = try open("kw-thin")
        defer { db.close(); cleanup(url) }

        try db.recordExternalTurn(
            sessionID: "s-t", provider: "local", requestID: "t1",
            userText: "问：消力池要多深", model: nil, createdAt: Date())
        try db.recordExternalResponse(
            sessionID: "s-t", provider: "local", requestID: "t1",
            assistantText: "答：按跃后水深加安全超高", model: nil, createdAt: Date())
        try db.verifyExternalTurn(
            sessionID: "s-t", requestID: "t1", verifiedAt: Date())
        let ids = try db.chatIndexRows(sessionIDs: ["s-t"])
        let questionID = ids.first { $0.role == "user" }?.messageID
        let answerID = ids.first { $0.role == "assistant" }?.messageID

        try db.recordTurnDigest(
            sessionID: "s-t", turnIndex: 1,
            questionMessageID: questionID, answerMessageID: answerID,
            digest: "定了消力池深度的算法", keywords: "消力池")

        let thin = try db.turnsWithThinKeywords()
        XCTAssertEqual(thin.count, 1)
        XCTAssertEqual(thin.first?.question, "问：消力池要多深")
        XCTAssertEqual(thin.first?.answer, "答：按跃后水深加安全超高")
        XCTAssertEqual(thin.first?.keywords, ["消力池"])

        try db.replaceTurnKeywords(
            sessionID: "s-t", turnIndex: 1,
            keywords: ["消力池", "跃后水深", "安全超高", "深度", "算法"])
        XCTAssertTrue(try db.turnsWithThinKeywords().isEmpty)
    }

    /// 只问词的那条提示与解析：没有关键词行就是 nil，标签里的标点都切掉。
    func testKeywordPromptAndParse() {
        let prompt = TurnDigestText.keywordPrompt(
            question: "问：闸门什么时候开", answer: "答：汛前三天")
        XCTAssertTrue(prompt.contains("只给这一轮的关键词"))
        XCTAssertTrue(prompt.contains("问：闸门什么时候开"))

        XCTAssertEqual(
            TurnDigestText.parseKeywords("关键词：闸门 汛前 三天"),
            ["闸门", "汛前", "三天"])
        XCTAssertEqual(
            TurnDigestText.parseKeywords("**关键词：**闸门，汛前、三天"),
            ["闸门", "汛前", "三天"])
        // 本机模型单行提问时不带标签（10/10）：裸的一行词要能认。
        XCTAssertEqual(
            TurnDigestText.parseKeywords("闸门 汛前 三天"), ["闸门", "汛前", "三天"])
        XCTAssertNil(TurnDigestText.parseKeywords("摘要：这一轮说了点什么"))
        XCTAssertNil(TurnDigestText.parseKeywords("关键词："))
    }

    /// 合并词：已有顺序不动、新增只去重、截到上限；**不按原文筛**。
    func testMergeKeywordsKeepsAliasesAndCaps() {
        XCTAssertEqual(
            TurnDigestText.mergeKeywords(["甲", "乙"], ["乙", "丙", "丁"]),
            ["甲", "乙", "丙", "丁"])

        // 「エイリアス」在这段原文里不存在，也不该被丢掉：词表多出来的入口
        // 就是这类词。
        let merged = TurnDigestText.mergeKeywords(["甲"], ["结算", "别名说法"])
        XCTAssertEqual(merged, ["甲", "结算", "别名说法"])

        let full = TurnDigestText.mergeKeywords(
            ["w1", "w2", "w3", "w4", "w5", "w6", "w7"], ["w8", "w9"])
        XCTAssertEqual(full.count, TurnDigestText.maxKeywords)
        XCTAssertEqual(full.last, "w8")
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

    /// 分层投喂：散文全留，代码体只留前几行 + 声明 + 报错，并给出代码概况。
    func testLayeredFeedKeepsProseAndDropsCodeBody() {
        let answer = """
        这一轮把端口检测改成了 socket bind。

        ```swift
        struct PortProbe {
            func available() -> Bool { true }
            let f1 = "占位占位占位占位占位占位占位占位占位占位"
            let f2 = "占位占位占位占位占位占位占位占位占位占位"
            let f3 = "占位占位占位占位占位占位占位占位占位占位"
            let f4 = "占位占位占位占位占位占位占位占位占位占位"
            let f5 = "占位占位占位占位占位占位占位占位占位占位"
            let f6 = "占位占位占位占位占位占位占位占位占位占位"
            let f7 = "占位占位占位占位占位占位占位占位占位占位"
        }
        ```

        结论：端口冲突已解决，未做 IPv6 分支。
        """
        let prompt = TurnDigestText.prompt(question: "问", answer: answer)
        XCTAssertTrue(prompt.contains("这一轮把端口检测改成了 socket bind"), "散文要留")
        XCTAssertTrue(prompt.contains("结论：端口冲突已解决"), "结论要留")
        XCTAssertTrue(prompt.contains("struct PortProbe"), "声明要留")
        XCTAssertTrue(prompt.contains("【代码概况】1 个代码块"), "要给代码概况")
        XCTAssertTrue(prompt.contains("这一层也不在摘要范围内"), "要说明代码完整性不在范围")

        // 没有代码块的短回答：原样进 prompt，不加代码概况、不加说明。
        let plain = TurnDigestText.prompt(question: "问", answer: "短回答，不该被动。")
        XCTAssertTrue(plain.contains("回答：\n短回答，不该被动。"))
        XCTAssertFalse(plain.contains("【代码概况】"))
        XCTAssertFalse(plain.contains("这一层也不在摘要范围内"))
    }

    /// 投喂总量封顶：再长的回答也不会把 prompt 撑爆。
    func testLayeredFeedRespectsBudget() {
        let long = (0..<400)
            .map { _ in "这是一句散文，用来把投喂撑过上限。" }
            .joined(separator: "\n")
        let prompt = TurnDigestText.prompt(question: "问", answer: long)
        XCTAssertLessThan(prompt.count, 4_000, "封顶后 prompt 不该随原文线性增长")
    }
}
