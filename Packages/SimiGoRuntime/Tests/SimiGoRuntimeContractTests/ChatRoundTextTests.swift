import XCTest
@testable import SimiGoRuntimeContract

/// A round keeps its reply verbatim, carries the boundary under one heading,
/// and reports a missing boundary instead of reading as if it had none.
final class ChatRoundTextTests: XCTestCase {
    func testBoundaryIsAppendedAfterTheFullReply() {
        let reply = "五个断言，两个偏：提交清单漏一项，旧检出把 10 个新文件数成 7 个。"
        let text = ChatRoundText.compose(
            assistant: reply,
            boundary: "旧检出的行数是数测试文件得来的，不是全量。")
        XCTAssertTrue(text.hasPrefix(reply), "the reply is kept as given")
        XCTAssertTrue(text.hasSuffix("不是全量。"))
        XCTAssertTrue(text.contains(ChatRoundText.boundaryHeading))
    }

    func testNoBoundaryLeavesTheTextUntouched() {
        XCTAssertEqual(
            ChatRoundText.compose(assistant: "同上。", boundary: nil), "同上。")
        XCTAssertEqual(
            ChatRoundText.compose(assistant: "同上。", boundary: "   \n "), "同上。",
            "whitespace is not a boundary")
    }

    func testBoundaryStatedIsVisibleEitherWay() {
        XCTAssertTrue(ChatRoundText.statesBoundary(assistant: "x", boundary: "未跑"))
        XCTAssertTrue(
            ChatRoundText.statesBoundary(
                assistant: "结论：…\n边界：E1/E2 未跑。", boundary: nil),
            "a boundary written into the reply counts")
        XCTAssertFalse(
            ChatRoundText.statesBoundary(assistant: "全部验证通过。", boundary: nil),
            "a round with no boundary must not pass as unlimited")
    }
}
