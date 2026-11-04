import Foundation

// 引擎同款 JSONValue（Value.swift 语义：object=[String: JSONValue] 无序字典）
enum JSONValue: Codable {
    case null, bool(Bool), int(Int), double(Double), string(String)
    case array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil().self ? true : (try? c.decodeNil()) == true { self = .null; return }
        // 按引擎顺序试探
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad")
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

// TodoWrite 形态：模型生成的工具调用参数（多键嵌套 + 中文 + 两键子对象）
let original = """
{"todos":[{"id":"1","content":"生成第一章：楼道相遇","status":"completed","deps":["preface"]},{"id":"2","content":"生成第二章：冷战与和解","status":"in_progress","deps":["1"]}],"meta":{"style":"原著续写","round":3}}
"""
print("原始串:      \(original)")

let value = try JSONDecoder().decode(JSONValue.self, from: Data(original.utf8))
let reEncoded = try JSONEncoder().encode(value)
let reStr = String(decoding: reEncoded, as: UTF8.self)
print("重编码串:    \(reStr)")
print("字符串相等:  \(reStr == original)")

// 逐键序对比（顶层第一子对象）
if let orig = try? JSONSerialization.jsonObject(with: Data(original.utf8)) as? [String: Any],
   let todos = orig["todos"] as? [[String: Any]],
   let first = todos.first,
   let re = try? JSONSerialization.jsonObject(with: reEncoded) as? [String: Any],
   let reTodos = re["todos"] as? [[String: Any]],
   let reFirst = reTodos.first {
    print("原始首项键序: \(first.keys.sorted())")
    print("重编码键序:   \(reFirst.keys.sorted())")
}
