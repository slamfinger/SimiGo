import Foundation

/// Ingress 形状超出 canonical IR 最小集时的显式拒绝。fail-closed：
/// 每个分支都可由样例复现，不允许「能读就读、读不出就丢」的静默降级。
nonisolated public enum IngressAdapterError: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedRole(String)
    case unsupportedContentPart(String)
    case unsupportedInputItem(String)
    case unsupportedToolType(String)
    case missingField(String)
    case malformedMessage(String)

    public var description: String {
        switch self {
        case .unsupportedRole(let role): return "unsupported role: \(role)"
        case .unsupportedContentPart(let type): return "unsupported content part type: \(type)"
        case .unsupportedInputItem(let type): return "unsupported input item type: \(type)"
        case .unsupportedToolType(let type): return "unsupported tool type: \(type)"
        case .missingField(let field): return "missing required field: \(field)"
        case .malformedMessage(let detail): return "malformed message: \(detail)"
        }
    }
}

/// Read the optional OpenAI function strict flag without confusing the
/// JSONValue.bool enum case with a computed Bool property. A present value of
/// the wrong JSON type is malformed and must not be silently ignored.
private func strictFlag(_ value: JSONValue?, field: String) throws -> Bool? {
    guard let value else { return nil }
    guard case .bool(let flag) = value else {
        throw IngressAdapterError.malformedMessage("\(field) must be a boolean")
    }
    return flag
}

/// OpenAI Chat Completions ingress → IR。qoder／zcode／owner 脚本走本线。
nonisolated public struct ChatCompletionsIngressAdapter: Sendable {
    public init() {}

    public func adapt(messages: [JSONValue], tools: [JSONValue]? = nil) throws -> IRConversation {
        let adapted = try messages.map { try adaptMessage($0) }
        let specs = try tools.map { try adaptToolList($0) } ?? []
        return IRConversation(messages: adapted, tools: specs)
    }

    private func adaptMessage(_ value: JSONValue) throws -> IRMessage {
        guard let object = value.object else {
            throw IngressAdapterError.malformedMessage("chat message is not an object")
        }
        guard let roleRaw = object["role"]?.string else {
            throw IngressAdapterError.missingField("role")
        }
        guard let role = IRRole(rawValue: roleRaw) else {
            throw IngressAdapterError.unsupportedRole(roleRaw)
        }
        let content = try adaptContent(object["content"])
        var toolCalls: [IRToolCall]?
        if let rawCalls = object["tool_calls"] {
            guard case .array(let calls) = rawCalls else {
                throw IngressAdapterError.malformedMessage("tool_calls is not an array")
            }
            toolCalls = try calls.map { try adaptToolCall($0) }
        }
        let toolCallID = object["tool_call_id"]?.string
        if role == .tool && toolCallID == nil {
            throw IngressAdapterError.missingField("tool_call_id")
        }
        return IRMessage(
            role: role, content: content, toolCalls: toolCalls,
            toolCallID: toolCallID, name: object["name"]?.string)
    }

    private func adaptContent(_ value: JSONValue?) throws -> [IRContentPart]? {
        switch value {
        case .none, .some(.null):
            return nil
        case .some(.string(let text)):
            return [.text(text)]
        case .some(.array(let parts)):
            return try parts.map { part in
                guard let object = part.object, let type = object["type"]?.string else {
                    throw IngressAdapterError.malformedMessage("content part is not an object")
                }
                guard type == "text" else {
                    throw IngressAdapterError.unsupportedContentPart(type)
                }
                guard let text = object["text"]?.string else {
                    throw IngressAdapterError.missingField("content part text")
                }
                return .text(text)
            }
        case .some:
            throw IngressAdapterError.malformedMessage("content is neither string nor array")
        }
    }

    private func adaptToolCall(_ value: JSONValue) throws -> IRToolCall {
        guard let object = value.object else {
            throw IngressAdapterError.malformedMessage("tool_calls entry is not an object")
        }
        guard let id = object["id"]?.string else {
            throw IngressAdapterError.missingField("tool_calls.id")
        }
        guard let function = object["function"]?.object else {
            throw IngressAdapterError.missingField("tool_calls.function")
        }
        guard let name = function["name"]?.string else {
            throw IngressAdapterError.missingField("tool_calls.function.name")
        }
        guard let arguments = function["arguments"]?.string else {
            throw IngressAdapterError.missingField("tool_calls.function.arguments")
        }
        return IRToolCall(callID: id, name: name, argumentsJSON: arguments)
    }

    private func adaptToolList(_ value: [JSONValue]) throws -> [IRToolSpec] {
        try value.map { tool in
            guard let object = tool.object else {
                throw IngressAdapterError.malformedMessage("tools entry is not an object")
            }
            let type = object["type"]?.string ?? "function"
            guard type == "function" else {
                throw IngressAdapterError.unsupportedToolType(type)
            }
            guard let function = object["function"]?.object else {
                throw IngressAdapterError.missingField("tools.function")
            }
            guard let name = function["name"]?.string else {
                throw IngressAdapterError.missingField("tools.function.name")
            }
            return IRToolSpec(
                name: name,
                description: function["description"]?.string,
                parametersJSON: Self.canonicalJSON(function["parameters"]),
                strict: try strictFlag(function["strict"], field: "tools.function.strict"))
        }
    }

    /// JSONValue → canonical JSON 文本（sortedKeys、紧凑）。nil → nil。
    static func canonicalJSON(_ value: JSONValue?) -> String? {
        guard let value, value != .null else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Responses ingress → IR。codex 走本线：`instructions` 归 system，
/// input items 归消息／function_call／function_call_output 三类，其余显式拒绝。
nonisolated public struct ResponsesIngressAdapter: Sendable {
    public init() {}

    public func adapt(
        input: JSONValue, instructions: String? = nil, tools: [JSONValue]? = nil
    ) throws -> IRConversation {
        var messages: [IRMessage] = []
        if let instructions, !instructions.isEmpty {
            messages.append(IRMessage(role: .system, content: [.text(instructions)]))
        }
        switch input {
        case .string(let text):
            messages.append(IRMessage(role: .user, content: [.text(text)]))
        case .array(let items):
            messages += try items.map { try adaptItem($0) }
        case .null:
            throw IngressAdapterError.missingField("input")
        case .object, .bool, .number:
            throw IngressAdapterError.malformedMessage("input is neither string nor array")
        }
        let specs = try tools.map { try adaptToolList($0) } ?? []
        return IRConversation(messages: messages, tools: specs)
    }

    private func adaptItem(_ value: JSONValue) throws -> IRMessage {
        guard let object = value.object else {
            throw IngressAdapterError.malformedMessage("input item is not an object")
        }
        switch object["type"]?.string ?? "message" {
        case "message":
            guard let roleRaw = object["role"]?.string else {
                throw IngressAdapterError.missingField("input item role")
            }
            guard let role = IRRole(rawValue: roleRaw) else {
                throw IngressAdapterError.unsupportedRole(roleRaw)
            }
            return IRMessage(role: role, content: try adaptContent(object["content"]))
        case "function_call":
            guard let callID = object["call_id"]?.string else {
                throw IngressAdapterError.missingField("function_call.call_id")
            }
            guard let name = object["name"]?.string else {
                throw IngressAdapterError.missingField("function_call.name")
            }
            guard let arguments = object["arguments"]?.string else {
                throw IngressAdapterError.missingField("function_call.arguments")
            }
            return IRMessage(
                role: .assistant,
                content: nil,
                toolCalls: [IRToolCall(callID: callID, name: name, argumentsJSON: arguments)])
        case "function_call_output":
            guard let callID = object["call_id"]?.string else {
                throw IngressAdapterError.missingField("function_call_output.call_id")
            }
            guard let output = object["output"]?.string else {
                throw IngressAdapterError.missingField("function_call_output.output")
            }
            return IRMessage(
                role: .tool, content: [.text(output)], toolCallID: callID)
        case let type:
            throw IngressAdapterError.unsupportedInputItem(type)
        }
    }

    private func adaptContent(_ value: JSONValue?) throws -> [IRContentPart]? {
        switch value {
        case .none, .some(.null):
            return nil
        case .some(.string(let text)):
            return [.text(text)]
        case .some(.array(let parts)):
            return try parts.map { part in
                guard let object = part.object, let type = object["type"]?.string else {
                    throw IngressAdapterError.malformedMessage("content part is not an object")
                }
                // Responses 的文本 part 三形态：input_text／output_text／text。
                guard type == "input_text" || type == "output_text" || type == "text" else {
                    throw IngressAdapterError.unsupportedContentPart(type)
                }
                guard let text = object["text"]?.string else {
                    throw IngressAdapterError.missingField("content part text")
                }
                return .text(text)
            }
        case .some:
            throw IngressAdapterError.malformedMessage("content is neither string nor array")
        }
    }

    private func adaptToolList(_ value: [JSONValue]) throws -> [IRToolSpec] {
        try value.map { tool in
            guard let object = tool.object else {
                throw IngressAdapterError.malformedMessage("tools entry is not an object")
            }
            let type = object["type"]?.string ?? "function"
            guard type == "function" else {
                throw IngressAdapterError.unsupportedToolType(type)
            }
            guard let name = object["name"]?.string else {
                throw IngressAdapterError.missingField("tools.name")
            }
            return IRToolSpec(
                name: name,
                description: object["description"]?.string,
                parametersJSON: ChatCompletionsIngressAdapter.canonicalJSON(object["parameters"]),
                strict: try strictFlag(object["strict"], field: "tools.strict"))
        }
    }
}

/// MCP ingress → IR。MCP 不是会话型 ingress：一次 tools/call 是
/// (name, arguments) → text 块结果 的工具交互片段。isError 是投递面
/// 元数据，不入消息层（结算／错误记账另有路径）。
nonisolated public struct MCPIngressAdapter: Sendable {
    public init() {}

    public func adaptCall(name: String, arguments: JSONValue, callID: String) throws -> IRMessage {
        guard !name.isEmpty else {
            throw IngressAdapterError.missingField("mcp tool name")
        }
        let argumentsJSON = ChatCompletionsIngressAdapter.canonicalJSON(arguments) ?? "{}"
        return IRMessage(
            role: .assistant,
            content: nil,
            toolCalls: [IRToolCall(callID: callID, name: name, argumentsJSON: argumentsJSON)])
    }

    public func adaptResult(text: String, callID: String) -> IRMessage {
        IRMessage(role: .tool, content: [.text(text)], toolCallID: callID)
    }
}
