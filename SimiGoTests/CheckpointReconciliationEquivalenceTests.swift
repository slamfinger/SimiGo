import XCTest
import MLXLMCommon
@testable import SimiGo

/// 实验 A（null-equivalence，BETA4-PROD-FINDINGS-1 §3）：纯工具轮 assistant
/// content 由 `""` 改写为 null。锁四层：
///   1. 形态：空 → .null，非空不变；
///   2. 渲染不变式：null 形态回灌 makeChatMessages 仍得 content == ""；
///   3. 对账目标：新 checkpoint（null）与新客户端回显（null）reconcile 成功；
///   4. 存量瞬态：旧 checkpoint（""）对 null 回显保持 stale（文档化的一次
///      瞬态预期，不静默吞掉）。
final class CheckpointReconciliationEquivalenceTests: XCTestCase {
    private let toolCall = ToolCall(
        function: .init(name: "search", arguments: ["query": .string("x")]),
        id: "call-123")

    /// Codex 同款客户端回显形态：tool_call assistant 消息 content 为 null、
    /// function.arguments 为字符串化 JSON（OpenAI wire 形态）。
    private func clientEcho(content: SimiGo.JSONValue) -> SimiGo.JSONValue {
        .object([
            "role": .string("assistant"),
            "content": content,
            "tool_calls": .array([.object([
                "id": .string("call-123"),
                "type": .string("function"),
                "function": .object([
                    "name": .string("search"),
                    "arguments": .string("{\"query\":\"x\"}"),
                ]),
            ])]),
        ])
    }

    private func userTurn(_ text: String) -> SimiGo.JSONValue {
        return .object([
            "role": .string("user"),
            "content": .string(text),
        ])
    }

    private func legacyCheckpoint(content: SimiGo.JSONValue) -> SimiGo.JSONValue {
        .object([
            "role": .string("assistant"),
            "content": content,
            "tool_calls": .array([.object([
                "id": .string("call-123"),
                "type": .string("function"),
                "function": .object([
                    "name": .string("search"),
                    "arguments": .string("{\"query\":\"x\"}"),
                ]),
            ])]),
        ])
    }

    func testEmptyContentWritesNullAndNonEmptyUnchanged() {
        let empty = NativeMLX.assistantToJSON(content: "", toolCalls: [toolCall])
        guard case .object(let object) = empty else { return XCTFail("expected object") }
        XCTAssertEqual(object["content"], .null)

        let nonEmpty = NativeMLX.assistantToJSON(content: "你好", toolCalls: [])
        guard case .object(let object2) = nonEmpty else { return XCTFail("expected object") }
        XCTAssertEqual(object2["content"], .string("你好"))
    }

    /// 渲染不变式：null 形态与旧 "" 形态必须产生同一条 Chat.Message
    /// （coerceContent(.null) == ""）——渲染与 isPrefix 零变化。
    func testNullFormRoundTripsToEmptyRenderContent() {
        let json = NativeMLX.assistantToJSON(content: "", toolCalls: [toolCall])
        let messages = NativeMLX.makeChatMessages([json])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.content, "")
        XCTAssertNotNil(messages.first?.tool)
    }

    /// A 的成功条件（对账层）：新 checkpoint（null）与新客户端回显（null）
    /// 必须通过渲染路径字段对账 → 条件恢复不再必然 stale。
    func testNewCheckpointReconcilesWithNullEcho() {
        let checkpoint = NativeMLX.assistantToJSON(content: "", toolCalls: [toolCall])
        let incoming: [SimiGo.JSONValue] = [
            clientEcho(content: .null),
            userTurn("go"),
        ]
        XCTAssertTrue(
            ExecutionPolicy.rollforwardCompatible(incoming: incoming, restoredHistory: [checkpoint]),
            "null 形态两侧必须 reconcile")
    }

    /// 存量瞬态（文档化预期）：旧 checkpoint（""）对 null 回显保持 stale——
    /// 锁定"瞬态只发生一轮、且不静默吞掉"的行为。
    func testLegacyEmptyStringCheckpointStaysStaleAgainstNullEcho() {
        let incoming: [SimiGo.JSONValue] = [
            clientEcho(content: .null),
            userTurn("go"),
        ]
        XCTAssertFalse(
            ExecutionPolicy.rollforwardCompatible(
                incoming: incoming,
                restoredHistory: [legacyCheckpoint(content: .string(""))]))
    }

    /// 旧 checkpoint（""）对旧形态回显（""）：行为不变（兼容性不回退）。
    func testLegacyPairRemainsCompatible() {
        let incoming: [SimiGo.JSONValue] = [
            clientEcho(content: .string("")),
            userTurn("go"),
        ]
        XCTAssertTrue(
            ExecutionPolicy.rollforwardCompatible(
                incoming: incoming,
                restoredHistory: [legacyCheckpoint(content: .string(""))]))
    }
}
