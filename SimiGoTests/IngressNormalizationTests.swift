import XCTest

@testable import SimiGo

/// L41：三面接入同一 IR 的验收自测。
///
/// 三条验收对应三组用例：
/// ①三面映射同一内部表达＋字段完备性（role／内容段／工具定义／附件）；
/// ②归一化幂等（归一→渲染→再归一逐字节同）；
/// ③真机 8 轮不退化＝真机项，不在本文件（候 :8000 排队）。
final class IngressNormalizationTests: XCTestCase {

    // MARK: - 夹具（三面描述同一会话）

    private static let chatJSON = """
    [
      {"role": "system", "content": "你是仓库助理。"},
      {"role": "developer", "content": "先读再答。"},
      {"role": "user", "content": "读 build 目录"},
      {"role": "assistant", "content": null,
       "tool_calls": [{"id": "call_a", "type": "function",
                       "function": {"name": "read_file", "arguments": "{\\"path\\":\\"build\\"}"}}]},
      {"role": "tool", "tool_call_id": "call_a", "content": "3 files"},
      {"role": "user", "content": [{"type": "text", "text": "总结一下"}]}
    ]
    """

    private static let toolsJSON = """
    [{"type": "function", "function": {"name": "read_file", "description": "读一个文件",
      "parameters": {"type": "object", "properties": {"path": {"type": "string"}}}}}]
    """

    private static func decode<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private static func chatMessages() throws -> [JSONValue] {
        try decode(chatJSON, as: [JSONValue].self)
    }

    private static func tools() throws -> [JSONValue] {
        try decode(toolsJSON, as: [JSONValue].self)
    }

    // MARK: - ① 三面同一表达＋字段完备性

    func testChatAndResponsesConvergeOnOneCanonicalConversation() throws {
        let messages = try Self.chatMessages()
        let tools = try Self.tools()
        // Responses 解析层把 items 落成 chat-form，故两面用同一 adapter 合流。
        let chat = try XCTUnwrap(
            IngressNormalization.chat(messages: messages, tools: tools))
        let responses = try XCTUnwrap(
            IngressNormalization.responses(chatFormMessages: messages, tools: tools))

        XCTAssertEqual(chat.surface, .chatCompletions)
        XCTAssertEqual(responses.surface, .responses)
        XCTAssertEqual(try chat.canonicalBytes(), try responses.canonicalBytes())
    }

    func testFieldCompletenessAcrossRolesContentCallsAndTools() throws {
        let ingress = try XCTUnwrap(
            IngressNormalization.chat(messages: try Self.chatMessages(), tools: try Self.tools()))
        let conversation = ingress.conversation

        XCTAssertEqual(
            conversation.messages.map(\.role),
            [.system, .developer, .user, .assistant, .tool, .user])
        // 内容段：string 与 parts 两形态归一为同一文本面。
        XCTAssertEqual(conversation.messages[2].content, [.text("读 build 目录")])
        XCTAssertEqual(conversation.messages[5].content, [.text("总结一下")])
        // assistant 无文本面，只带 tool_calls（arguments 逐字保留）。
        XCTAssertNil(conversation.messages[3].content)
        XCTAssertEqual(
            conversation.messages[3].toolCalls,
            [IRToolCall(callID: "call_a", name: "read_file", argumentsJSON: #"{"path":"build"}"#)])
        // tool 结果：role=.tool＋toolCallID。
        XCTAssertEqual(conversation.messages[4].toolCallID, "call_a")
        // 工具定义：名称／描述／parameters 齐全。
        XCTAssertEqual(conversation.tools.count, 1)
        XCTAssertEqual(conversation.tools[0].name, "read_file")
        XCTAssertEqual(conversation.tools[0].description, "读一个文件")
        XCTAssertNotNil(conversation.tools[0].parametersJSON)
    }

    /// 附件（image part）在最小集外：不静默丢弃，也不改判请求是否接受——
    /// 结果只是「这条请求没有 IR 语义面」，由调用方回落 wire。
    func testAttachmentPartYieldsNoIRInsteadOfSilentDrop() throws {
        let messages = try Self.decode(
            """
            [{"role": "user", "content": [
              {"type": "text", "text": "看图"},
              {"type": "image_url", "image_url": {"url": "data:image/png;base64,AA"}}]}]
            """, as: [JSONValue].self)
        XCTAssertNil(IngressNormalization.chat(messages: messages, tools: nil))
        XCTAssertNil(IngressNormalization.responses(chatFormMessages: messages, tools: nil))
    }

    func testMCPFragmentCarriesCallAndResult() throws {
        let arguments = try Self.decode(#"{"ticket": "L41"}"#, as: JSONValue.self)
        let ingress = try XCTUnwrap(
            IngressNormalization.mcp(
                name: "simigo_project_brief", arguments: arguments,
                callID: "mcp:brief", resultText: "ok"))
        XCTAssertEqual(ingress.surface, .mcp)
        XCTAssertEqual(ingress.conversation.messages.count, 2)
        XCTAssertEqual(ingress.conversation.messages[0].role, .assistant)
        XCTAssertEqual(ingress.conversation.messages[0].toolCalls?.first?.name, "simigo_project_brief")
        XCTAssertEqual(ingress.conversation.messages[1].role, .tool)
        XCTAssertEqual(ingress.renderedText, "ok")
    }

    // MARK: - ② 归一化幂等

    func testNormalizationIsIdempotentThroughChatFormRendering() throws {
        let tools = try Self.tools()
        let first = try XCTUnwrap(
            IngressNormalization.chat(messages: try Self.chatMessages(), tools: tools))
        let again = try XCTUnwrap(
            IngressNormalization.chat(
                messages: first.conversation.renderChatMessages(),
                tools: first.conversation.renderChatTools()))

        XCTAssertEqual(first.conversation, again.conversation)
        XCTAssertEqual(try first.canonicalBytes(), try again.canonicalBytes())
        // 渲染结果本身也要稳定：再渲染一次逐字节同。
        XCTAssertEqual(
            first.conversation.renderChatMessages(), again.conversation.renderChatMessages())
    }

    // MARK: - tool 续跑：IR 判定与 wire 判定一致（差分）

    func testIRToolContinuationMatchesWirePredicate() throws {
        let samples = [
            // 尾段有 tool 结果
            Self.chatJSON,
            // 尾段只有 assistant 的 tool_calls
            """
            [{"role": "user", "content": "读文件"},
             {"role": "assistant", "content": null,
              "tool_calls": [{"id": "c1", "type": "function",
                              "function": {"name": "read_file", "arguments": "{}"}}]}]
            """,
            // 普通续聊
            """
            [{"role": "user", "content": "你好"}, {"role": "assistant", "content": "在"}]
            """,
        ]
        for sample in samples {
            let messages = try Self.decode(sample, as: [JSONValue].self)
            let ingress = try XCTUnwrap(IngressNormalization.chat(messages: messages, tools: nil))
            XCTAssertEqual(
                ingress.conversation.continuesToolExchange,
                HTTPServer.isCurrentToolContinuation(messages))
        }
    }

    func testResponsesTailToolResultMatchesWireTail() throws {
        let messages = try Self.chatMessages()
        let ingress = try XCTUnwrap(
            IngressNormalization.responses(chatFormMessages: messages, tools: nil))
        let lastUser = messages.lastIndex { $0.object?["role"]?.string == "user" }
        let tail = lastUser.map { messages[($0 + 1)...] } ?? messages[...]
        XCTAssertEqual(
            ingress.conversation.tailHasToolResult,
            tail.contains { $0.object?["role"]?.string == "tool" })
    }
}
