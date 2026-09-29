import XCTest
@testable import SimiGo

/// #9 回归：splitResponsesEnvelope 直接在 JSONValue 层读 role，删除
/// jsonValueDictionary 往返。锁切分语义不变——前导 system/developer 进
/// preamble，其余（含 role 缺失/非字符串/非 object 消息）进 history。
final class ResponsesSplitEnvelopeTests: XCTestCase {
    private func makeServer() -> HTTPServer {
        HTTPServer(
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
    }

    private func msg(_ role: String, _ text: String) -> JSONValue {
        .object(["role": .string(role), "content": .string(text)])
    }

    func testLeadingSystemAndDeveloperGoToPreamble() {
        let split = makeServer().splitResponsesEnvelope([
            msg("system", "s1"),
            msg("developer", "d1"),
            msg("user", "u1"),
            msg("assistant", "a1"),
        ])
        XCTAssertEqual(split.preambleMessages, [msg("system", "s1"), msg("developer", "d1")])
        XCTAssertEqual(split.historyMessages, [msg("user", "u1"), msg("assistant", "a1")])
    }

    func testSystemAfterHistoryStartStaysInHistory() {
        let split = makeServer().splitResponsesEnvelope([
            msg("user", "u1"),
            msg("system", "mid"),
        ])
        XCTAssertTrue(split.preambleMessages.isEmpty)
        XCTAssertEqual(split.historyMessages, [msg("user", "u1"), msg("system", "mid")])
    }

    func testNonObjectMessagesFallToHistory() {
        let split = makeServer().splitResponsesEnvelope([
            .string("raw"),
            .array([.number(1)]),
            .null,
            .number(3.5),
        ])
        XCTAssertTrue(split.preambleMessages.isEmpty)
        XCTAssertEqual(
            split.historyMessages,
            [.string("raw"), .array([.number(1)]), .null, .number(3.5)]
        )
    }

    func testMissingOrNonStringRoleFallsToHistory() {
        let missingRole = JSONValue.object(["content": .string("no role")])
        let numericRole = JSONValue.object(["role": .number(1), "content": .string("x")])
        let split = makeServer().splitResponsesEnvelope([missingRole, numericRole])
        XCTAssertTrue(split.preambleMessages.isEmpty)
        XCTAssertEqual(split.historyMessages, [missingRole, numericRole])
    }

    func testEmptyInputSplitsEmpty() {
        let split = makeServer().splitResponsesEnvelope([])
        XCTAssertTrue(split.preambleMessages.isEmpty)
        XCTAssertTrue(split.historyMessages.isEmpty)
    }
}
