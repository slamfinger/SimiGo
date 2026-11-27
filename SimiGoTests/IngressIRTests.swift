import XCTest

@testable import SimiGo

/// L35：三 ingress 形状 → canonical IR 的单测与「同输入同输出」字节稳定性自测。
/// 夹具取自三客户端真实形状（00142793 采样证据；DB 只存 user/assistant、
/// tool 结构只在 wire 面，codex 线走 responses items＋developer role）。
final class IngressIRTests: XCTestCase {

    // MARK: - 夹具

    private static let chatWireJSON = """
    {
      "messages": [
        {"role": "system", "content": "你是仓库助理。"},
        {"role": "user", "content": "读 build 目录"},
        {"role": "assistant", "content": null,
         "tool_calls": [{"id": "call_a", "type": "function",
                         "function": {"name": "read_file", "arguments": "{\\"path\\":\\"build\\"}"}}]},
        {"role": "tool", "tool_call_id": "call_a", "content": "3 files"},
        {"role": "user", "content": [{"type": "text", "text": "总结一下"}]}
      ],
      "tools": [{"type": "function", "function": {"name": "read_file",
                 "description": "读一个文件",
                 "parameters": {"type": "object", "properties": {"path": {"type": "string"}}}}}]
    }
    """

    /// 与 chatWireJSON **同一会话**的 Responses 形态：instructions＋items。
    private static let responsesWireJSON = """
    {
      "instructions": "你是仓库助理。",
      "input": [
        {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "读 build 目录"}]},
        {"type": "function_call", "call_id": "call_a", "name": "read_file", "arguments": "{\\"path\\":\\"build\\"}"},
        {"type": "function_call_output", "call_id": "call_a", "output": "3 files"},
        {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "总结一下"}]}
      ],
      "tools": [{"type": "function", "name": "read_file", "description": "读一个文件",
                 "parameters": {"type": "object", "properties": {"path": {"type": "string"}}}}]
    }
    """

    private static func decode(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    private static func arrayOrNil(_ value: JSONValue?) -> [JSONValue]? {
        guard case .array(let items)? = value else { return nil }
        return items
    }

    private static func array(_ value: JSONValue?) throws -> [JSONValue] {
        guard case .array(let items)? = value else {
            XCTFail("expected array in wire fixture")
            return []
        }
        return items
    }

    private static func chatConversation() throws -> IRConversation {
        let object = try XCTUnwrap(try decode(chatWireJSON).object)
        return try ChatCompletionsIngressAdapter().adapt(
            messages: try array(object["messages"]),
            tools: Self.arrayOrNil(object["tools"]))
    }

    private static func responsesConversation() throws -> IRConversation {
        let object = try XCTUnwrap(try decode(responsesWireJSON).object)
        return try ResponsesIngressAdapter().adapt(
            input: object["input"] ?? .null,
            instructions: object["instructions"]?.string,
            tools: Self.arrayOrNil(object["tools"]))
    }

    // MARK: - Chat Completions adapter

    func testChatAdapterCoversFullShape() throws {
        let conversation = try Self.chatConversation()
        XCTAssertEqual(conversation.messages.count, 5)
        XCTAssertEqual(conversation.messages[0].role, .system)
        XCTAssertEqual(conversation.messages[2].toolCalls?.count, 1)
        XCTAssertEqual(conversation.messages[2].toolCalls?.first?.name, "read_file")
        XCTAssertEqual(conversation.messages[2].toolCalls?.first?.argumentsJSON, "{\"path\":\"build\"}")
        XCTAssertNil(conversation.messages[2].content)
        XCTAssertEqual(conversation.messages[3].role, .tool)
        XCTAssertEqual(conversation.messages[3].toolCallID, "call_a")
        XCTAssertEqual(conversation.messages[4].content, [.text("总结一下")])
        XCTAssertEqual(conversation.tools.count, 1)
        XCTAssertEqual(conversation.tools[0].name, "read_file")
        XCTAssertTrue(conversation.tools[0].parametersJSON?.contains("\"path\"") == true)
    }

    // MARK: - Responses adapter

    func testResponsesAdapterCoversCodexShape() throws {
        let conversation = try Self.responsesConversation()
        XCTAssertEqual(conversation.messages.count, 5)
        XCTAssertEqual(conversation.messages[0].role, .system)
        XCTAssertEqual(conversation.messages[0].content, [.text("你是仓库助理。")])
        XCTAssertEqual(conversation.messages[2].toolCalls?.first?.callID, "call_a")
        XCTAssertEqual(conversation.messages[3].role, .tool)
        XCTAssertEqual(conversation.messages[3].content, [.text("3 files")])
        XCTAssertEqual(conversation.tools[0].name, "read_file")
    }

    /// 跨 adapter 等价：同一会话的 chat 形与 responses 形归一后**字节全同**。
    /// 这是 canonical IR「语义相同 ⇒ 字节相同」的正控制。
    func testCrossAdapterCanonicalEquivalence() throws {
        let chat = try Self.chatConversation()
        let responses = try Self.responsesConversation()
        XCTAssertEqual(chat, responses)
        XCTAssertEqual(try chat.canonicalBytes(), try responses.canonicalBytes())
    }

    // MARK: - MCP adapter

    func testMCPAdapterMapsCallAndResult() throws {
        let adapter = MCPIngressAdapter()
        let call = try adapter.adaptCall(
            name: "simigo_is_search",
            arguments: .object(["query": .string("digest fork")]),
            callID: "req-1")
        XCTAssertEqual(call.role, .assistant)
        XCTAssertEqual(call.toolCalls?.first?.name, "simigo_is_search")
        XCTAssertTrue(call.toolCalls?.first?.argumentsJSON.contains("\"query\"") == true)
        let result = adapter.adaptResult(text: "2 hits", callID: "req-1")
        XCTAssertEqual(result.role, .tool)
        XCTAssertEqual(result.toolCallID, "req-1")
        XCTAssertEqual(result.content, [.text("2 hits")])
    }

    // MARK: - 字节稳定性（同输入同输出）

    func testCanonicalBytesAreStableAcrossRuns() throws {
        let conversation = try Self.chatConversation()
        let first = try conversation.canonicalBytes()
        for _ in 0..<3 {
            XCTAssertEqual(try conversation.canonicalBytes(), first)
        }
        // 字节面是合法 UTF-8 JSON 且顶层键序确定（sortedKeys）。
        let text = String(data: first, encoding: .utf8) ?? ""
        XCTAssertTrue(text.hasPrefix("{\"messages\":["))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: first, options: [.fragmentsAllowed]) as? [String: Any] != nil, true)
    }

    /// 同一会话、wire 键插入序不同——canonical 输出必须逐字节同。
    func testCanonicalBytesIgnoreWireKeyOrder() throws {
        let reordered = """
        {
          "tools": [{"function": {"parameters": {"properties": {"path": {"type": "string"}}, "type": "object"},
                     "description": "读一个文件", "name": "read_file"}, "type": "function"}],
          "messages": [
            {"content": "你是仓库助理。", "role": "system"},
            {"content": "读 build 目录", "role": "user"},
            {"tool_calls": [{"function": {"arguments": "{\\"path\\":\\"build\\"}", "name": "read_file"},
                             "id": "call_a", "type": "function"}],
             "content": null, "role": "assistant"},
            {"content": "3 files", "tool_call_id": "call_a", "role": "tool"},
            {"content": [{"text": "总结一下", "type": "text"}], "role": "user"}
          ]
        }
        """
        let object = try XCTUnwrap(try Self.decode(reordered).object)
        let conversation = try ChatCompletionsIngressAdapter().adapt(
            messages: try Self.array(object["messages"]),
            tools: Self.arrayOrNil(object["tools"]))
        XCTAssertEqual(try conversation.canonicalBytes(), try Self.chatConversation().canonicalBytes())
    }

    // MARK: - fail-closed 拒绝面

    func testChatAdapterRejectsOutOfRangeShapes() {
        let adapter = ChatCompletionsIngressAdapter()
        XCTAssertThrowsError(try adapter.adapt(
            messages: [.object(["role": .string("engine"), "content": .string("x")])])) { error in
            XCTAssertEqual(error as? IngressAdapterError, .unsupportedRole("engine"))
        }
        XCTAssertThrowsError(try adapter.adapt(messages: [.object([
            "role": .string("user"),
            "content": .array([.object(["type": .string("image_url"), "url": .string("https://x")])]),
        ])])) { error in
            XCTAssertEqual(error as? IngressAdapterError, .unsupportedContentPart("image_url"))
        }
        XCTAssertThrowsError(try adapter.adapt(
            messages: [.object(["role": .string("tool"), "content": .string("r")])])) { error in
            XCTAssertEqual(error as? IngressAdapterError, .missingField("tool_call_id"))
        }
    }

    func testResponsesAdapterRejectsUnsupportedItems() {
        let adapter = ResponsesIngressAdapter()
        XCTAssertThrowsError(try adapter.adapt(
            input: .array([.object(["type": .string("reasoning")])]))) { error in
            XCTAssertEqual(error as? IngressAdapterError, .unsupportedInputItem("reasoning"))
        }
        XCTAssertThrowsError(try adapter.adapt(
            input: .string("q"), tools: [.object(["type": .string("web_search")])])) { error in
            XCTAssertEqual(error as? IngressAdapterError, .unsupportedToolType("web_search"))
        }
    }

    // MARK: - parameters schema 的 canonical 键序

    func testParametersJSONIsCanonical() {
        let a = ChatCompletionsIngressAdapter.canonicalJSON(
            .object(["type": .string("object"), "properties": .object(["path": .object(["type": .string("string")])])]))
        let b = ChatCompletionsIngressAdapter.canonicalJSON(
            .object(["properties": .object(["path": .object(["type": .string("string")])]), "type": .string("object")]))
        XCTAssertEqual(a, b)
        XCTAssertTrue(a?.hasPrefix("{\"properties\":") == true)
    }
}
