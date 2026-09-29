import XCTest
@testable import SimiGo

/// #6 encode-once 回归：ParsedToolCall.argumentsJSON 从计算属性改为构造时
/// 渲染一次的缓存。锁三件事——渲染结果与按需序列化一致（wire 不变）、
/// 空参数 "{}"、Codable 契约保持 id/name/arguments 三字段。
final class TypesBridgeTests: XCTestCase {
    func testArgumentsJSONMatchesOnDemandSerialization() {
        let call = ParsedToolCall(
            id: "call_1",
            name: "search",
            arguments: ["query": .string("swift concurrency"), "limit": .number(5)]
        )
        let dict = call.arguments.mapValues { $0.toAny() }
        let expected = String(
            data: try! JSONSerialization.data(withJSONObject: dict),
            encoding: .utf8
        )
        XCTAssertEqual(call.argumentsJSON, expected)
    }

    func testArgumentsJSONEmptyArgumentsRendersEmptyObject() {
        let call = ParsedToolCall(id: "call_2", name: "noop", arguments: [:])
        XCTAssertEqual(call.argumentsJSON, "{}")
    }

    func testArgumentsJSONStableAndRoundTrips() {
        let call = ParsedToolCall(
            id: "call_3",
            name: "write",
            arguments: [
                "text": .string("引号\"与\\反斜杠\n换行"),
                "中文键": .string("值"),
                "count": .number(3),
                "ok": .bool(true),
            ]
        )
        let first = call.argumentsJSON
        XCTAssertEqual(call.argumentsJSON, first)
        let decoded = try! JSONDecoder().decode(
            [String: JSONValue].self, from: first.data(using: .utf8)!)
        XCTAssertEqual(decoded, call.arguments)
    }

    func testCodableContractKeepsThreeFields() throws {
        let call = ParsedToolCall(id: "call_4", name: "run", arguments: ["a": .bool(true)])
        let data = try JSONEncoder().encode(call)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(Set(obj.keys), ["id", "name", "arguments"])

        let back = try JSONDecoder().decode(ParsedToolCall.self, from: data)
        XCTAssertEqual(back, call)
        XCTAssertEqual(back.argumentsJSON, call.argumentsJSON)
    }
}
