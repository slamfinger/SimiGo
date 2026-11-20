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
            generateHandler: { _, _, _, _, _, _, _, _, _, _ in
                GenerationResult(text: "", usage: nil, completion: .complete)
            },
            forkBranchHandler: { _, _, _, _ in
                SessionCacheMetadata(
                    storageKey: "test/main",
                    modelId: "test-model",
                    savedAt: Date(),
                    history: [])
            },
            deleteBranchHandler: { _, _, _, _ in
                BranchDeletionOutcome(
                    deletedBranch: "", hadLiveSession: false,
                    hadCheckpointFile: false, generation: 1,
                    remainingLiveBranches: [],
                    remainingCheckpointBranches: [])
            },
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

    private func parseInputItems(_ items: [[String: Any]]) -> ResponsesParsedRequest? {
        makeServer().parseResponsesParams(["input": items])
    }

    func testResponsesFunctionCallRecordsRequireIdentityAndObjectArguments() {
        let valid: [[String: Any]] = [[
            "type": "function_call",
            "call_id": "call-valid",
            "name": "lookup",
            "arguments": "{}",
        ]]
        XCTAssertNotNil(parseInputItems(valid),
                        "an empty arguments object is valid")

        XCTAssertNil(parseInputItems([[
            "type": "function_call",
            "name": "lookup",
            "arguments": "{}",
        ]]), "missing call_id must not be replaced with a random ID")

        XCTAssertNil(parseInputItems([[
            "type": "function_call",
            "call_id": "call-bad",
            "name": "lookup",
            "arguments": "not-json",
        ]]), "invalid JSON must reject the request instead of dropping the item")

        XCTAssertNil(parseInputItems([[
            "type": "function_call",
            "call_id": "call-array",
            "name": "lookup",
            "arguments": "[]",
        ]]), "tool arguments must be a JSON object")
    }

    func testResponsesFunctionCallOutputRejectsMissingAndDuplicateRecords() {
        XCTAssertNil(parseInputItems([[
            "type": "function_call_output",
            "output": "42",
        ]]), "missing call_id must not be skipped")

        XCTAssertNil(parseInputItems([[
            "type": "function_call_output",
            "call_id": "call-1",
            "output": "42",
        ], [
            "type": "function_call_output",
            "call_id": "call-1",
            "output": "42",
        ]]), "duplicate output records must not be silently deduplicated")
    }


    func testResponsesParserRetainsRequiredAndNamedToolChoice() {
        let tools: [[String: Any]] = [[
            "type": "function",
            "name": "lookup",
            "description": "Look up a record.",
            "parameters": [
                "type": "object",
                "properties": ["key": ["type": "string"]],
                "required": ["key"]
            ]
        ]]

        let required = makeServer().parseResponsesParams([
            "input": "check this",
            "tools": tools,
            "tool_choice": "required"
        ])
        XCTAssertEqual(required?.config.toolChoice?.mode, .required)

        let named = makeServer().parseResponsesParams([
            "input": "look this up",
            "tools": tools,
            "tool_choice": ["type": "function", "name": "lookup"]
        ])
        XCTAssertEqual(named?.config.toolChoice?.mode, .function)
        XCTAssertEqual(named?.config.toolChoice?.functionName, "lookup")

        let none = makeServer().parseResponsesParams([
            "input": "answer without tools",
            "tools": tools,
            "tool_choice": "none"
        ])
        XCTAssertEqual(none?.config.toolChoice?.mode, ToolChoiceMode.none)
    }

    func testResponsesParserRejectsUnsatisfiableToolChoiceBeforeGeneration() {
        let tools: [[String: Any]] = [[
            "type": "function",
            "name": "lookup",
            "parameters": ["type": "object"]
        ]]

        XCTAssertNil(makeServer().parseResponsesParams([
            "input": "do it",
            "tool_choice": "required"
        ]))
        XCTAssertNil(makeServer().parseResponsesParams([
            "input": "do it",
            "tools": tools,
            "tool_choice": ["type": "function", "name": "missing"]
        ]))
        XCTAssertNil(makeServer().parseResponsesParams([
            "input": "do it",
            "tools": tools,
            "tool_choice": "always"
        ]))
    }
}
