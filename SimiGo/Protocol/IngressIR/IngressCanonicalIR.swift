import Foundation

/// Canonical context IR 的**最小消息层**（owner 裁定 00142793 的 L2 落地）。
///
/// 三条 ingress（OpenAI Chat Completions／Responses／MCP）的语义形状先收敛到
/// 本层，再由渲染层消费；wire 形态继续沿用事实标准（OpenAI-compatible），
/// 不重造 wire。本层只收「语义结构」：role／text content／tool 调用与声明；
/// image 等非文本 part、非 function 工具、MCP isError 等超出最小集的形状
/// 一律由 adapter 显式拒绝（fail-closed），不静默降级。
///
/// 写集边界（L35）：纯新文件，不接入 HTTPServerChat／HTTPServerResponses／
/// HTTPServerMCP 的现有解析路径；接入另立票。
nonisolated public enum IRRole: String, Codable, Sendable, Equatable, CaseIterable {
    case system, developer, user, assistant, tool
}

nonisolated public enum IRContentPart: Codable, Sendable, Equatable {
    case text(String)
}

nonisolated public struct IRToolCall: Codable, Equatable, Sendable {
    public let callID: String
    public let name: String
    /// arguments 的 JSON 文本形态，逐字保留：不重排键、不重渲染。
    /// canonicalBytes 的稳定性以「入参文本本身稳定」为前提。
    public let argumentsJSON: String

    public init(callID: String, name: String, argumentsJSON: String) {
        self.callID = callID
        self.name = name
        self.argumentsJSON = argumentsJSON
    }

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case name
        case argumentsJSON = "arguments_json"
    }
}

nonisolated public struct IRToolSpec: Codable, Equatable, Sendable {
    public let name: String
    public let description: String?
    /// parameters schema 的 canonical JSON 文本形态；缺省即 nil。
    public let parametersJSON: String?
    /// Structured output enforcement requested by the caller, when supplied.
    public let strict: Bool?

    public init(
        name: String, description: String?, parametersJSON: String?, strict: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
        self.strict = strict
    }

    private enum CodingKeys: String, CodingKey {
        case name, description, strict
        case parametersJSON = "parameters_json"
    }
}

nonisolated public struct IRMessage: Codable, Equatable, Sendable {
    public let role: IRRole
    /// nil＝该消息无文本面（assistant 仅带 tool_calls、或 tool 仅带结果引用）。
    public let content: [IRContentPart]?
    public let toolCalls: [IRToolCall]?
    public let toolCallID: String?
    public let name: String?

    public init(
        role: IRRole, content: [IRContentPart]?, toolCalls: [IRToolCall]? = nil,
        toolCallID: String? = nil, name: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
        case name
    }
}

nonisolated public struct IRConversation: Codable, Equatable, Sendable {
    public let messages: [IRMessage]
    /// 客户端声明的 function 工具表；system／developer 语义由消息 role 承载。
    public let tools: [IRToolSpec]

    public init(messages: [IRMessage], tools: [IRToolSpec] = []) {
        self.messages = messages
        self.tools = tools
    }

    /// 字节稳定面：同一 conversation 恒产同一字节串（sortedKeys 全递归排序、
    /// 紧凑输出、UTF-8）。这是「同输入同输出」自测与跨 adapter 等价断言的
    /// 依据；调用方不得再对其输出做任何键序假设。
    public func canonicalBytes() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}
