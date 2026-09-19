import XCTest
@testable import SimiGo

final class HTTPChatParamsTests: XCTestCase {
    func testNullToolsDoesNotThrowAndParsesAsNil() {
        let server = HTTPServer(
            port: 0,
            modelId: "test-model",
            generateHandler: { _, _, _, _, _, _, _, _, _ in
                GenerationResult(text: "", usage: nil)
            },
            forkBranchHandler: { _, _, _, _ in
                SessionCacheMetadata(
                    storageKey: "test/main",
                    modelId: "test-model",
                    savedAt: Date(),
                    history: [])
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true }
        )

        let parsed = server.parseChatParams([
            "messages": [["role": "user", "content": "ok"]],
            "tools": NSNull(),
        ])

        XCTAssertNotNil(parsed)
        XCTAssertNil(parsed?.4)
    }
}
