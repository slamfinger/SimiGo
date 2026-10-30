import Foundation
import XCTest
@testable import SimiGo

/// The forwarded-request extractors decide what text an external turn is
/// recorded under and whether the upstream answer counts as complete. They are
/// pure functions over wire JSON / SSE bytes, so they are pinned here.
final class RemoteISExtractionTests: XCTestCase {

    // MARK: - Route classification

    func testPathToWireMapping() {
        XCTAssertEqual(HTTPServer.externalWire(forPath: "/v1/chat/completions"), .chat)
        XCTAssertEqual(HTTPServer.externalWire(forPath: "/chat/completions"), .chat)
        XCTAssertEqual(HTTPServer.externalWire(forPath: "/v1/completions"), .completions)
        XCTAssertEqual(HTTPServer.externalWire(forPath: "/completions"), .completions)
        XCTAssertEqual(HTTPServer.externalWire(forPath: "/v1/responses"), .responses)
        XCTAssertNil(HTTPServer.externalWire(forPath: "/v1/models"))
        XCTAssertNil(HTTPServer.externalWire(forPath: "/v1/embeddings"))
    }

    // MARK: - Request side

    func testChatRequestUsesLastUserTurn() {
        let json: [String: Any] = [
            "messages": [
                ["role": "system", "content": "system prompt"],
                ["role": "user", "content": "第一个问题"],
                ["role": "assistant", "content": "第一个回答"],
                ["role": "user", "content": [
                    ["type": "text", "text": "第二个问题"],
                ]],
                ["role": "tool", "content": "tool output"],
            ],
        ]
        XCTAssertEqual(
            HTTPServer.externalRequestUserText(wire: .chat, json: json),
            "第二个问题")
    }

    func testChatRequestSkipsBlankUserTurns() {
        let json: [String: Any] = [
            "messages": [
                ["role": "user", "content": "有内容的问题"],
                ["role": "user", "content": "   "],
            ],
        ]
        XCTAssertEqual(
            HTTPServer.externalRequestUserText(wire: .chat, json: json),
            "有内容的问题")
    }

    func testCompletionsRequestPromptForms() {
        XCTAssertEqual(
            HTTPServer.externalRequestUserText(
                wire: .completions, json: ["prompt": "补全提示"]),
            "补全提示")
        XCTAssertEqual(
            HTTPServer.externalRequestUserText(
                wire: .completions, json: ["prompt": ["第一段", "第二段"]]),
            "第一段第二段")
        XCTAssertNil(
            HTTPServer.externalRequestUserText(
                wire: .completions, json: ["prompt": ["a": 1]]))
    }

    func testResponsesRequestInputForms() {
        XCTAssertEqual(
            HTTPServer.externalRequestUserText(
                wire: .responses, json: ["input": "直接输入"]),
            "直接输入")
        XCTAssertEqual(
            HTTPServer.externalRequestUserText(
                wire: .responses,
                json: ["input": [
                    ["role": "developer", "content": "instructions"],
                    ["role": "user", "content": [
                        ["type": "input_text", "text": "结构化输入"],
                    ]],
                    ["type": "function_call_output", "output": "tool 结果"],
                ]]),
            "结构化输入")
    }

    // MARK: - Response side (non-streaming)

    func testNonStreamingChatExtractionDistinguishesStopAndLength() {
        let stop: [String: Any] = [
            "choices": [[
                "message": ["role": "assistant", "content": "完整回答"],
                "finish_reason": "stop",
            ]],
        ]
        let extracted = HTTPServer.externalResponseExtract(wire: .chat, json: stop)
        XCTAssertEqual(extracted.text, "完整回答")
        XCTAssertTrue(extracted.complete)

        let length: [String: Any] = [
            "choices": [[
                "message": ["content": "被截断的回答"],
                "finish_reason": "length",
            ]],
        ]
        let truncated = HTTPServer.externalResponseExtract(wire: .chat, json: length)
        XCTAssertEqual(truncated.text, "被截断的回答")
        XCTAssertFalse(truncated.complete)

        XCTAssertEqual(
            HTTPServer.externalResponseExtract(wire: .chat, json: [:]).text, "")
        XCTAssertFalse(
            HTTPServer.externalResponseExtract(wire: .chat, json: [:]).complete)
    }

    func testNonStreamingCompletionsExtraction() {
        let json: [String: Any] = [
            "choices": [["text": "续写结果", "finish_reason": "stop"]],
        ]
        let extracted = HTTPServer.externalResponseExtract(wire: .completions, json: json)
        XCTAssertEqual(extracted.text, "续写结果")
        XCTAssertTrue(extracted.complete)
    }

    func testNonStreamingResponsesExtractionJoinsOutputText() {
        let json: [String: Any] = [
            "status": "completed",
            "output": [
                ["type": "message", "content": [
                    ["type": "output_text", "text": "第一段"],
                    ["type": "output_text", "text": "第二段"],
                    ["type": "refusal", "refusal": "忽略"],
                ]],
                ["type": "function_call", "arguments": "{}"],
            ],
        ]
        let extracted = HTTPServer.externalResponseExtract(wire: .responses, json: json)
        XCTAssertEqual(extracted.text, "第一段第二段")
        XCTAssertTrue(extracted.complete)

        let incomplete = HTTPServer.externalResponseExtract(
            wire: .responses,
            json: ["status": "incomplete", "output": []])
        XCTAssertFalse(incomplete.complete)
    }

    // MARK: - Response side (streaming)

    private func sse(_ events: [String], done: Bool = true) -> Data {
        var text = events.map { "data: \($0)\n\n" }.joined()
        if done { text += "data: [DONE]\n\n" }
        return Data(text.utf8)
    }

    func testStreamingChatExtractionAccumulatesDeltasUntilDone() {
        let raw = sse([
            #"{"choices":[{"delta":{"content":"你"}}]}"#,
            #"{"choices":[{"delta":{"content":"好"},"finish_reason":"stop"}]}"#,
        ])
        let extracted = HTTPServer.externalStreamExtract(wire: .chat, raw: raw)
        XCTAssertEqual(extracted.text, "你好")
        XCTAssertTrue(extracted.complete)
    }

    func testStreamingChatLengthStaysIncomplete() {
        let raw = sse([
            #"{"choices":[{"delta":{"content":"截断"},"finish_reason":"length"}]}"#,
        ], done: false)
        let extracted = HTTPServer.externalStreamExtract(wire: .chat, raw: raw)
        XCTAssertEqual(extracted.text, "截断")
        XCTAssertFalse(extracted.complete)
    }

    func testStreamingCompletionsExtraction() {
        let raw = sse([
            #"{"choices":[{"text":"续"}]}"#,
            #"{"choices":[{"text":"写","finish_reason":"stop"}]}"#,
        ], done: false)
        let extracted = HTTPServer.externalStreamExtract(wire: .completions, raw: raw)
        XCTAssertEqual(extracted.text, "续写")
        XCTAssertTrue(extracted.complete)
    }

    func testStreamingResponsesCompletionEvents() {
        let completed = sse([
            #"{"type":"response.output_text.delta","delta":"第一段"}"#,
            #"{"type":"response.output_text.delta","delta":"第二段"}"#,
            #"{"type":"response.completed","response":{"status":"completed"}}"#,
        ], done: false)
        let extracted = HTTPServer.externalStreamExtract(wire: .responses, raw: completed)
        XCTAssertEqual(extracted.text, "第一段第二段")
        XCTAssertTrue(extracted.complete)

        let failed = sse([
            #"{"type":"response.output_text.delta","delta":"半句"}"#,
            #"{"type":"response.incomplete","response":{"status":"incomplete"}}"#,
        ], done: false)
        let incomplete = HTTPServer.externalStreamExtract(wire: .responses, raw: failed)
        XCTAssertEqual(incomplete.text, "半句")
        XCTAssertFalse(incomplete.complete)
    }

    func testStreamingIgnoresMalformedEvents() {
        let raw = Data(
            "data: not-json\n\ndata: {\"choices\":[]}\n\ndata: [DONE]\n\n".utf8)
        let extracted = HTTPServer.externalStreamExtract(wire: .chat, raw: raw)
        XCTAssertEqual(extracted.text, "")
        XCTAssertTrue(extracted.complete)
    }
}
