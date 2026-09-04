import Foundation

/// 极简 JSON 值类型定义
public enum JSONValue: Codable, Equatable, Sendable, CustomStringConvertible {
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

    public nonisolated var description: String {
        switch self {
        case .string(let v): return v
        case .number(let v): return String(v)
        case .bool(let v): return String(v)
        case .object(let v): return v.description
        case .array(let v): return v.description
        case .null: return "null"
        }
    }

    public nonisolated var object: [String: JSONValue]? {
        guard case .object(let dict) = self else { return nil }
        return dict
    }

    public nonisolated var string: String? {
        guard case .string(let s) = self else { return nil }
        return s
    }

    /// 将 Foundation Any（来自 JSON 反序列化）规整为 JSONValue
    public nonisolated static func any(_ value: Any?) -> JSONValue {
        guard let value else { return .null }
        switch value {
        case let s as String:
            return .string(s)
        case let b as Bool:
            return .bool(b)
        case let n as NSNumber:
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

    public nonisolated func toAny() -> Any {
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
public struct ParsedToolCall: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let arguments: [String: JSONValue]

    public nonisolated init(id: String, name: String, arguments: [String: JSONValue]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    public var argumentsJSON: String {
        guard !arguments.isEmpty else { return "{}" }
        let dict = arguments.mapValues { $0.toAny() }
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}

/// GFTokenizer 兼容命名空间
public enum GFTokenizer {
    public struct FunctionDefinition: Codable, Equatable, Sendable {
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
