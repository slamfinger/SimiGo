import XCTest
import MLXLMCommon
@testable import SimiGo

final class SessionCachePersistenceTests: XCTestCase {
    private let encoder = JSONEncoder()

    func testCacheFileNameFlattensStorageKey() {
        XCTAssertEqual(
            NativeMLX.cacheFileName(for: "default/9dc81004-abc/main"),
            "default_9dc81004-abc_main"
        )
    }

    func testAssistantToJSONContentOnly() throws {
        let json = NativeMLX.assistantToJSON(content: "你好", toolCalls: [])
        guard case .object(let object) = json else {
            return XCTFail("expected object")
        }
        XCTAssertEqual(object["role"], .string("assistant"))
        XCTAssertEqual(object["content"], .string("你好"))
        XCTAssertNil(object["tool_calls"])

        // 回灌必须还原为同一条 assistant 消息（会话连续性契约）
        let messages = NativeMLX.makeChatMessages([json])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.role.rawValue, "assistant")
        XCTAssertEqual(messages.first?.content, "你好")
    }

    func testAssistantToJSONWithToolCallsRoundTripsThroughReingest() throws {
        let toolCall = ToolCall(
            function: .init(
                name: "search",
                arguments: ["query": .string("swift concurrency"), "limit": .int(10)]
            ),
            id: "call-123"
        )

        let json = NativeMLX.assistantToJSON(content: "", toolCalls: [toolCall])
        guard case .object(let object) = json else {
            return XCTFail("expected object")
        }
        guard case .array(let calls)? = object["tool_calls"] else {
            return XCTFail("expected tool_calls array")
        }
        XCTAssertEqual(calls.count, 1)

        // 回灌：makeChatMessages → parseToolCalls 必须保住工具身份与参数
        let messages = NativeMLX.makeChatMessages([json])
        XCTAssertEqual(messages.count, 1)
        XCTAssertNotNil(messages[0].tool)

        let reparsed = try JSONDecoder().decode(
            [ToolCall].self, from: try encoder.encode(calls))
        XCTAssertEqual(reparsed.count, 1)
        XCTAssertEqual(reparsed.first?.function.name, "search")
        XCTAssertEqual(reparsed.first?.id, "call-123")
        XCTAssertEqual(
            reparsed.first?.function.arguments["query"],
            MLXLMCommon.JSONValue.string("swift concurrency")
        )
    }

    func testSessionCacheMetadataCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let metadata = SessionCacheMetadata(
            storageKey: "default/9dc81004/main",
            modelId: "Nail-Qwen3.6-35B-A3B-MLX",
            savedAt: Date(timeIntervalSince1970: 1_789_000_000),
            history: [
                .object(["role": .string("user"), "content": .string("hi")]),
                .object(["role": .string("assistant"), "content": .string("hello")])
            ]
        )

        let decoded = try decoder.decode(
            SessionCacheMetadata.self, from: encoder.encode(metadata))
        XCTAssertEqual(decoded.storageKey, metadata.storageKey)
        XCTAssertEqual(decoded.modelId, metadata.modelId)
        XCTAssertEqual(decoded.history, metadata.history)
    }
}

