import XCTest
@testable import SimiGo

final class HTTPChatParamsTests: XCTestCase {
    func testNullToolsDoesNotThrowAndParsesAsNil() {
        let server = HTTPServer(
            port: 0,
            modelId: "test-model",
            generateHandler: { _, _, _, _, _, _, _, _, _ in
                GenerationResult(text: "", usage: nil)
            },
            forkBranchHandler: { _, _, _, _ in
                SessionCacheMetadata(
                    storageKey: "test/main",
                    modelId: "test-model",
                    savedAt: Date(),
                    history: [])
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true }
        )

        let parsed = server.parseChatParams([
            "messages": [["role": "user", "content": "ok"]],
            "tools": NSNull(),
        ])

        XCTAssertNotNil(parsed)
        XCTAssertNil(parsed?.4)
    }

    /// #8 回归：messages 从 data→JSONDecoder 往返改为 JSONValue.any 逐元素
    /// 转换。锁类型保真——布尔/数字/嵌套数组/arguments 字符串形态逐值一致。
    func testMessagesConversionPreservesTypesAndStructure() {
        let server = makeServer()

        let parsed = server.parseChatParams([
            "messages": [
                ["role": "system", "content": "sys"],
                ["role": "user", "content": [["type": "text", "text": "hello"]]],
                ["role": "assistant", "content": "", "tool_calls": [
                    ["id": "call-1", "type": "function",
                     "function": ["name": "f", "arguments": "{\"x\":true}"]],
                ]],
                ["role": "tool", "content": "result", "tool_call_id": "call-1",
                 "ok": true, "score": 7],
            ],
        ])

        let messages = try! XCTUnwrap(parsed?.3)
        XCTAssertEqual(messages.count, 4)

        guard case .object(let system) = messages[0] else { return XCTFail("system shape") }
        XCTAssertEqual(system["role"], .string("system"))

        guard case .object(let user) = messages[1],
              case .array(let parts)? = user["content"],
              parts.count == 1,
              case .object(let part)? = parts.first,
              case .string("hello")? = part["text"] else { return XCTFail("multimodal shape") }

        guard case .object(let assistant) = messages[2],
              case .array(let calls)? = assistant["tool_calls"],
              case .object(let call)? = calls.first,
              case .object(let function)? = call["function"],
              case .string(let rawArguments)? = function["arguments"] else {
            return XCTFail("tool_calls shape")
        }
        XCTAssertEqual(rawArguments, "{\"x\":true}")

        guard case .object(let tool) = messages[3] else { return XCTFail("tool shape") }
        XCTAssertEqual(tool["ok"], .bool(true))
        XCTAssertEqual(tool["score"], .number(7))
        XCTAssertEqual(tool["tool_call_id"], .string("call-1"))
    }

    /// #8 回归：退化输入与旧解码路径行为一致。
    func testMessagesDegenerateInputsPreserveOldBehavior() {
        let server = makeServer()

        XCTAssertNil(server.parseChatParams(["messages": "hello"]))
        XCTAssertNil(server.parseChatParams(["messages": ["role": "user"]]))
        XCTAssertNil(server.parseChatParams(["messages": []]))
        XCTAssertNil(server.parseChatParams([:]))

        // 非 object 元素仍被接受并转为对应 JSONValue（旧解码路径同行为）
        let parsed = server.parseChatParams(["messages": ["plain"]])
        XCTAssertEqual(parsed?.3, [.string("plain")])
    }

    private func makeServer() -> HTTPServer {
        HTTPServer(
            port: 0,
            modelId: "test-model",
            generateHandler: { _, _, _, _, _, _, _, _, _ in
                GenerationResult(text: "", usage: nil)
            },
            forkBranchHandler: { _, _, _, _ in
                SessionCacheMetadata(
                    storageKey: "test/main",
                    modelId: "test-model",
                    savedAt: Date(),
                    history: [])
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true }
        )
    }
}
