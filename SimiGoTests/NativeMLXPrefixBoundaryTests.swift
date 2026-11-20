import XCTest
import SimiGo2Experimental

@testable import SimiGo

/// Model-free regression tests for message-chain boundary accounting.
final class NativeMLXPrefixBoundaryTests: XCTestCase {

    func testMessageChainWordCountMapsToExactMessageCount() throws {
        let messages: [(role: String, content: String)] = [
            ("system", "policy"),
            ("user", "document"),
            ("assistant", "answer"),
            ("tool", "result"),
        ]
        let wordCount = PrefixMessageChain.stream(messages).count

        XCTAssertEqual(
            wordCount, messages.count * PrefixMessageChain.wordsPerMessage)
        XCTAssertEqual(
            try XCTUnwrap(PrefixMessageChain.messageCount(forWordCount: wordCount)),
            messages.count)
        XCTAssertNil(PrefixMessageChain.messageCount(forWordCount: wordCount + 1))
        XCTAssertNil(PrefixMessageChain.messageCount(forWordCount: -1))
    }
}
