import XCTest
import MLXLMCommon

@testable import SimiGo

/// Model-free regression tests for hot-path transcript comparisons.
final class NativeMLXHotPathTests: XCTestCase {

    func testDirectMessageComparisonMatchesLegacySignatureContract() {
        let messages: [Chat.Message] = [
            .system("system"),
            .user("same"),
            .user("different"),
            .user("separator\u{1f}tool"),
            .assistant("assistant"),
            .assistant("assistant", toolCalls: []),
            .tool("result", id: "call-a"),
            .tool("result", id: "call-b"),
            .assistant(String(repeating: "long-content-", count: 2_048)),
        ]

        func legacySignature(_ message: Chat.Message) -> String {
            let toolFlag = message.tool == nil ? "-" : "tool"
            return "\(message.role.rawValue)\u{1f}\(message.content)\u{1f}\(toolFlag)"
        }

        for lhs in messages {
            for rhs in messages {
                XCTAssertEqual(
                    NativeMLX.messagesMatchForReuse(lhs, rhs),
                    legacySignature(lhs) == legacySignature(rhs),
                    "direct comparison must preserve the previous role/content/tool-presence contract")
            }
        }
    }
}
