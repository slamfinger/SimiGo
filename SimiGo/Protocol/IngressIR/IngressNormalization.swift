import Foundation

/// 三面 ingress 的唯一归一化入口（L41 接入层）。
///
/// wire 不重造（ADR 00142793：L1 用事实标准）：Chat Completions 与 Responses
/// 解析层继续按原形状把消息交给既有管线；本层只负责把「同一请求」在三面各写
/// 一遍的语义形状收敛成一个 `IRConversation`，让下游有一个可比较、可渲染、
/// 可复算的表示。
///
/// Responses 线在解析层已落成 chat-form messages（ADR_INGRESS_CANONICAL_IR
/// §一.5），所以它与 chat 共用 `ChatCompletionsIngressAdapter`：两条线在此合流。
///
/// 失败策略：adapter 对最小集外形状 fail-closed（抛错）；本层把错误折成 nil，
/// 因为 wire 侧今天仍可能合法携带无消费方的形状（image part 等）——「请求是否
/// 接受」由既有解析器决定，不在这里改判。调用方拿到 nil 时沿用原 wire 判定，
/// 不得把 nil 当「无 tool 交互」之类的负结论。
nonisolated public enum IngressSurface: String, Sendable, Equatable {
    case chatCompletions = "chat.completions"
    case responses
    case mcp
}

nonisolated public struct IngressNormalization: Sendable, Equatable {
    public let surface: IngressSurface
    public let conversation: IRConversation

    public init(surface: IngressSurface, conversation: IRConversation) {
        self.surface = surface
        self.conversation = conversation
    }

    /// 语义面字节：同一 conversation 恒同（sortedKeys、紧凑 UTF-8）。
    public func canonicalBytes() throws -> Data {
        try conversation.canonicalBytes()
    }

    /// 片段末条的文本面（MCP content 块从这里渲染）。
    public var renderedText: String? {
        guard case .text(let text)? = conversation.messages.last?.content?.first else {
            return nil
        }
        return text
    }

    /// Chat Completions wire：messages（string／parts 双形态）＋tools（嵌套 function）。
    public static func chat(
        messages: [JSONValue], tools: [JSONValue]?
    ) -> IngressNormalization? {
        guard
            let conversation = try? ChatCompletionsIngressAdapter().adapt(
                messages: messages, tools: tools)
        else { return nil }
        return IngressNormalization(surface: .chatCompletions, conversation: conversation)
    }

    /// Responses wire：解析层给出的就是 chat-form messages，故复用同一 adapter。
    public static func responses(
        chatFormMessages: [JSONValue], tools: [JSONValue]?
    ) -> IngressNormalization? {
        guard
            let conversation = try? ChatCompletionsIngressAdapter().adapt(
                messages: chatFormMessages, tools: tools)
        else { return nil }
        return IngressNormalization(surface: .responses, conversation: conversation)
    }

    /// MCP tools/call：非会话型，一段 (call → result) 工具交互片段。
    public static func mcp(
        name: String, arguments: JSONValue, callID: String, resultText: String? = nil
    ) -> IngressNormalization? {
        let adapter = MCPIngressAdapter()
        guard let call = try? adapter.adaptCall(name: name, arguments: arguments, callID: callID)
        else { return nil }
        let messages =
            resultText.map { [call, adapter.adaptResult(text: $0, callID: callID)] } ?? [call]
        return IngressNormalization(surface: .mcp, conversation: IRConversation(messages: messages))
    }
}

extension IRConversation {
    /// tool 续跑判定，三面共用同一语义。wire 版（`HTTPServer.isCurrentToolContinuation`）
    /// 只在本层拿不到 IR 时回落。
    public var continuesToolExchange: Bool {
        tailAfterLastUser.contains { $0.role == .tool || !($0.toolCalls ?? []).isEmpty }
    }

    /// 末条 user 之后是否已有 tool 结果（不含 assistant 的 tool_calls）。
    /// Responses 的 tool-continuation 判定用这一条（chat 用上面的全量形态）。
    public var tailHasToolResult: Bool {
        tailAfterLastUser.contains { $0.role == .tool }
    }

    private var tailAfterLastUser: ArraySlice<IRMessage> {
        let tail: ArraySlice<IRMessage>
        if let lastUser = messages.lastIndex(where: { $0.role == .user }) {
            tail = messages[(lastUser + 1)...]
        } else {
            tail = messages[...]
        }
        return tail
    }

    /// chat-form 渲染：与 `ChatCompletionsIngressAdapter` 互为逆映射的最小面。
    /// 供「归一化幂等」自测（归一→渲染→再归一必须逐字节同）与接线前对比。
    public func renderChatMessages() -> [JSONValue] {
        messages.map { message in
            var object: [String: JSONValue] = ["role": .string(message.role.rawValue)]
            if let content = message.content {
                object["content"] = .array(content.map { part in
                    switch part {
                    case .text(let text):
                        return .object(["type": .string("text"), "text": .string(text)])
                    }
                })
            } else {
                object["content"] = .null
            }
            if let calls = message.toolCalls, !calls.isEmpty {
                object["tool_calls"] = .array(calls.map { call in
                    .object([
                        "id": .string(call.callID),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string(call.name),
                            "arguments": .string(call.argumentsJSON),
                        ]),
                    ])
                })
            }
            if let callID = message.toolCallID { object["tool_call_id"] = .string(callID) }
            if let name = message.name { object["name"] = .string(name) }
            return .object(object)
        }
    }

    /// chat-form 工具表渲染（同上，嵌套 function 形态）。
    public func renderChatTools() -> [JSONValue] {
        tools.map { spec in
            var function: [String: JSONValue] = ["name": .string(spec.name)]
            if let description = spec.description {
                function["description"] = .string(description)
            }
            if let parametersJSON = spec.parametersJSON,
               let parameters = try? JSONDecoder().decode(
                   JSONValue.self, from: Data(parametersJSON.utf8)) {
                function["parameters"] = parameters
            }
            return .object(["type": .string("function"), "function": .object(function)])
        }
    }
}
