import Foundation

/// 极简 JSON 值类型定义
nonisolated public enum JSONValue: Codable, Equatable, Sendable, CustomStringConvertible {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let val = try? single.decode(Bool.self) {
            self = .bool(val)
        } else if let val = try? single.decode(Double.self) {
            self = .number(val)
        } else if let val = try? single.decode(String.self) {
            self = .string(val)
        } else if let val = try? single.decode([String: JSONValue].self) {
            self = .object(val)
        } else if let val = try? single.decode([JSONValue].self) {
            self = .array(val)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .string(let v): try single.encode(v)
        case .number(let v): try single.encode(v)
        case .bool(let v): try single.encode(v)
        case .object(let v): try single.encode(v)
        case .array(let v): try single.encode(v)
        case .null: try single.encodeNil()
        }
    }

    public var description: String {
        switch self {
        case .string(let v): return v
        case .number(let v): return v.description
        case .bool(let v): return v.description
        case .object(let v): return v.description
        case .array(let v): return v.description
        case .null: return "null"
        }
    }

    public var object: [String: JSONValue]? {
        guard case .object(let dict) = self else { return nil }
        return dict
    }

    public var string: String? {
        guard case .string(let s) = self else { return nil }
        return s
    }

    /// 将 Foundation Any（来自 JSON 反序列化）规整为 JSONValue
    public static func any(_ value: Any?) -> JSONValue {
        guard let value else { return .null }
        switch value {
        case let s as String:
            return .string(s)
        case let n as NSNumber:
            // JSON 布尔按 CFBoolean 类型 ID 严格判别。不能用 `as? Bool`：
            // 该条件转型对数值型 NSNumber(0/1) 也会成功，会把客户端 JSON
            // 数字折叠成布尔（MessagesConversionEquivalenceTests 差分实证，
            // 2026-09-29）。JSONSerialization 的布尔恒为 CFBoolean、数值
            // 恒为 CFNumber，类型 ID 判别对两条来源都精确。
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            return .number(n.doubleValue)
        case let d as Double:
            return .number(d)
        case let i as Int:
            return .number(Double(i))
        case let dict as [String: Any]:
            return .object(dict.mapValues { any($0) })
        case let arr as [Any]:
            return .array(arr.map { any($0) })
        default:
            return .null
        }
    }

    public func toAny() -> Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .null: return NSNull()
        case .object(let dict): return dict.mapValues { $0.toAny() }
        case .array(let arr): return arr.map { $0.toAny() }
        }
    }
}

/// 解析后的工具调用结构
nonisolated public struct ParsedToolCall: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let arguments: [String: JSONValue]
    /// arguments 的 JSON 字符串形态。构造时渲染一次；此前是无缓存计算属性，
    /// 每次访问全量重序列化（Responses 流式路径单次调用访问 3 次）。
    public let argumentsJSON: String

    public init(id: String, name: String, arguments: [String: JSONValue]) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.argumentsJSON = ParsedToolCall.renderArgumentsJSON(arguments)
    }

    private static func renderArgumentsJSON(
        _ arguments: [String: JSONValue]
    ) -> String {
        guard !arguments.isEmpty else { return "{}" }
        let dict = arguments.mapValues { $0.toAny() }
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    /// argumentsJSON 是派生值，不进 Codable wire——契约保持 id/name/arguments
    /// 三字段，与缓存引入前的编码形态逐字节一致。
    private enum CodingKeys: String, CodingKey {
        case id, name, arguments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        arguments = try container.decode([String: JSONValue].self, forKey: .arguments)
        argumentsJSON = ParsedToolCall.renderArgumentsJSON(arguments)
    }
}

/// GFTokenizer 兼容命名空间
nonisolated public enum GFTokenizer {
    nonisolated public struct FunctionDefinition: Codable, Equatable, Sendable {
        public let name: String
        public let description: String
        public let parameters: [String: JSONValue]

        public init(name: String, description: String, parameters: [String: JSONValue]) {
            self.name = name
            self.description = description
            self.parameters = parameters
        }
    }
}
