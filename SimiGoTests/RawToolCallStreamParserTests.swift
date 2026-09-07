import XCTest
@testable import SimiGo

/// Tool Protocol 最低回归集（README_base §8.3 B/C/D/E）。
/// 锚定铁律：67（增量状态机解析，标签可被 chunk 任意切分）、
/// 68（通道互斥，Tool Body 不得泄漏进 onText）、18（`{}` 合法零参数）、
/// 70/73（Malformed 必须 Fail-Fast，不得猜测）、79（EOS 未闭合 = Protocol Failure）。
final class RawToolCallStreamParserTests: XCTestCase {

    private func drain(_ chunks: [String]) -> (
        text: String,
        calls: [ParsedToolCall],
        failure: RawToolCallParserFailure?
    ) {
        let parser = RawToolCallStreamParser()
        var text = ""
        var calls: [ParsedToolCall] = []

        for chunk in chunks {
            parser.feed(
                chunk,
                onText: { text += $0 },
                onToolCall: { calls.append($0) }
            )
        }

        parser.flush { text += $0 }

        return (text, calls, parser.failure)
    }

    // B：Raw Fallback —— 标签前普通文本必须完整输出（2026-09-08 P1 回归锚点）
    func testTextBeforeToolCallIsEmitted() {
        let result = drain([
            "正在查询天气。<tool_call>{\"name\":\"get_weather\",\"arguments\":{\"city\":\"北京\"}}</tool_call>后续"
        ])

        XCTAssertEqual(result.text, "正在查询天气。后续")
        XCTAssertEqual(result.calls.count, 1)
        XCTAssertEqual(result.calls.first?.name, "get_weather")
        XCTAssertEqual(result.calls.first?.arguments["city"], .string("北京"))
        XCTAssertNil(result.failure)
    }

    // C：Chunk Split —— 标签被 decode chunk 任意切分仍必须正确解析（铁律 67）
    func testChunkSplitTagAcrossFeeds() {
        let result = drain([
            "前文<to",
            "ol_call>{\"na",
            "me\":\"f\",\"argum",
            "ents\":{}}</tool_c",
            "all>尾部"
        ])

        XCTAssertEqual(result.text, "前文尾部")
        XCTAssertEqual(result.calls.count, 1)
        XCTAssertEqual(result.calls.first?.name, "f")
        // 铁律 18：`{}` 是合法零参数 Tool Call
        XCTAssertEqual(result.calls.first?.arguments, [:])
        XCTAssertNil(result.failure)
    }

    // D：Malformed —— 非法 JSON 必须 Fail-Fast（铁律 70/73），Body 不得泄漏（铁律 68）
    func testMalformedJSONFailsFast() {
        let result = drain(["<tool_call>not-json</tool_call>"])

        XCTAssertNotNil(result.failure)
        XCTAssertTrue(result.calls.isEmpty)
        XCTAssertEqual(result.text, "")
    }

    // E：Incomplete at EOS —— 未闭合标签必须判定 Protocol Failure（铁律 79），
    // 不得解析半成品、不得当作 Assistant Text 泄漏（铁律 68/72）
    func testUnclosedAtEOSIsProtocolFailure() {
        let result = drain(["说明<tool_call>{\"name\":\"f\""])

        XCTAssertNotNil(result.failure)
        XCTAssertTrue(result.calls.isEmpty)
        // 仅 open 标签前的说明文字可输出；未完成的 Tool Body 不得进入文本通道
        XCTAssertEqual(result.text, "说明")
    }

    // Attribute 模板：多参数语法契约
    func testAttributeTemplateMultiParameters() {
        let result = drain([
            "调用<function=run>\n<parameter=cmd>ls -la\n<parameter=timeout>30\n</function>完毕"
        ])

        XCTAssertEqual(result.text, "调用完毕")
        XCTAssertEqual(result.calls.count, 1)
        XCTAssertEqual(result.calls.first?.name, "run")
        XCTAssertEqual(result.calls.first?.arguments["cmd"], .string("ls -la"))
        XCTAssertEqual(result.calls.first?.arguments["timeout"], .string("30"))
        XCTAssertNil(result.failure)
    }
}
