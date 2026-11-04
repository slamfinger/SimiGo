import XCTest
@testable import SimiGo

/// 工具回声归一化的形态等价：split 形态（文本位 + 连续调用位）被账本
/// 权威形态吸收，同位调用只在 `tool_calls` 形态不同时对齐。
///
/// `content` 的 null↔"" 编码差**不**触发替换，也不参与前缀判定：
/// `makeChatMessages` 把两者都折成空文本，同键复用门与跨键采纳门共用的
/// `isPrefix` 因此观察不到该差（2026-10-29 真机 trace 与源码复核，
/// ACCEPTANCE §3.34「归因更正」）。
final class ToolEchoShapeNormalizationTests: XCTestCase {
    private func call(id: String, arguments: String) -> JSONValue {
        .object([
            "id": .string(id),
            "type": .string("function"),
            "function": .object([
                "name": .string("echo"),
                "arguments": .string(arguments),
            ]),
        ])
    }

    private func assistant(
        content: JSONValue? = nil,
        calls: [JSONValue] = []
    ) -> JSONValue {
        var object: [String: JSONValue] = ["role": .string("assistant")]
        if let content { object["content"] = content }
        if !calls.isEmpty { object["tool_calls"] = .array(calls) }
        return .object(object)
    }

    private func user(_ text: String) -> JSONValue {
        .object(["role": .string("user"), "content": .string(text)])
    }

    private func toolResult(id: String, text: String) -> JSONValue {
        .object([
            "role": .string("tool"),
            "tool_call_id": .string(id),
            "content": .string(text),
        ])
    }

    private var ledger: [JSONValue] {
        [
            user("现在几点？"),
            assistant(content: .null, calls: [call(id: "call_1", arguments: "{}")]),
            toolResult(id: "call_1", text: "12:00"),
        ]
    }

    /// 原样回显（含 null）不做无谓替换。
    func testFaithfulEchoIsUnchanged() {
        let result = NativeMLX.normalizeToolEcho(ledger, against: ledger)

        XCTAssertFalse(result.changed)
        XCTAssertEqual(result.replacedCalls, 0)
        XCTAssertEqual(result.messages, ledger)
    }

    /// 调用 id 不同 = 真实前缀变化，不得借归一化掩盖。
    func testDifferentCallIdentityIsNotNormalized() {
        var incoming = ledger
        incoming[1] = assistant(content: .null, calls: [call(id: "call_other", arguments: "{}")])

        let result = NativeMLX.normalizeToolEcho(incoming, against: ledger)

        XCTAssertFalse(result.changed)
        XCTAssertEqual(result.messages, incoming)
    }

    /// 文本位与调用位拆分形态（多数客户端）仍按吸收路径合并。
    func testSplitFormIsStillMerged() {
        let incoming: [JSONValue] = [
            user("现在几点？"),
            assistant(content: .string("")),
            assistant(calls: [call(id: "call_1", arguments: "{}")]),
            toolResult(id: "call_1", text: "12:00"),
        ]

        let result = NativeMLX.normalizeToolEcho(incoming, against: ledger)

        XCTAssertEqual(result.mergedPairs, 1)
        XCTAssertEqual(result.messages, ledger)
    }
}
