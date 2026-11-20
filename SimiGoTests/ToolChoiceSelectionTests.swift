import XCTest
@testable import SimiGo

final class ToolChoiceSelectionTests: XCTestCase {
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

    private var lookupTool: [[String: Any]] {
        [[
            "type": "function",
            "function": [
                "name": "lookup",
                "description": "Look up a record.",
                "parameters": [
                    "type": "object",
                    "properties": ["key": ["type": "string"]],
                    "required": ["key"]
                ]
            ]
        ]]
    }

    func testOmittedAndNullToolChoicePreserveAuto() {
        XCTAssertEqual(ToolChoiceSelection.parse(nil)?.mode, .auto)
        XCTAssertEqual(ToolChoiceSelection.parse(NSNull())?.mode, .auto)
        XCTAssertEqual(ToolChoiceSelection.parse("auto")?.mode, .auto)
        XCTAssertTrue(
            ToolChoiceSelection(mode: .auto).isSatisfied(by: []),
            "auto must continue to permit a normal text answer")
    }

    func testStringChoicesParseWithoutChangingAutoSemantics() {
        XCTAssertEqual(ToolChoiceSelection.parse("none")?.mode, .none)
        XCTAssertEqual(ToolChoiceSelection.parse("required")?.mode, .required)
        XCTAssertNil(ToolChoiceSelection.parse("always"))
    }

    func testNamedFunctionParsesBothProtocolShapes() {
        let responsesShape: [String: Any] = [
            "type": "function",
            "name": "lookup"
        ]
        let chatShape: [String: Any] = [
            "type": "function",
            "function": ["name": "lookup"]
        ]
        XCTAssertEqual(ToolChoiceSelection.parse(responsesShape)?.mode, .function)
        XCTAssertEqual(ToolChoiceSelection.parse(responsesShape)?.functionName, "lookup")
        XCTAssertEqual(ToolChoiceSelection.parse(chatShape)?.functionName, "lookup")
        XCTAssertNil(ToolChoiceSelection.parse(["type": "function", "name": " "]))
    }

    func testRequiredChoiceRequiresAtLeastOneTool() {
        let required = ToolChoiceSelection(mode: .required)
        XCTAssertFalse(required.isSatisfied(by: []))
        XCTAssertTrue(required.isSatisfied(by: ["lookup"]))
    }

    func testNamedFunctionChoiceRequiresTheSelectedFunction() {
        let choice = ToolChoiceSelection(mode: .function, functionName: "lookup")
        XCTAssertTrue(choice.isSatisfied(by: ["lookup"]))
        XCTAssertFalse(choice.isSatisfied(by: ["exec_command"]))
        XCTAssertFalse(choice.isSatisfied(by: []))
    }

    func testChatParserPreservesRequiredAndNamedToolChoice() {
        let server = makeServer()
        let required = server.parseChatParams([
            "messages": [["role": "user", "content": "check this"]],
            "tools": lookupTool,
            "tool_choice": "required"
        ])
        XCTAssertEqual(required?.5.toolChoice?.mode, .required)

        let named = server.parseChatParams([
            "messages": [["role": "user", "content": "look this up"]],
            "tools": lookupTool,
            "tool_choice": [
                "type": "function",
                "function": ["name": "lookup"]
            ]
        ])
        XCTAssertEqual(named?.5.toolChoice?.mode, .function)
        XCTAssertEqual(named?.5.toolChoice?.functionName, "lookup")
    }

    func testChatParserRejectsUnsatisfiableToolChoiceBeforeGeneration() {
        let server = makeServer()
        XCTAssertNil(server.parseChatParams([
            "messages": [["role": "user", "content": "do it"]],
            "tool_choice": "required"
        ]))
        XCTAssertNil(server.parseChatParams([
            "messages": [["role": "user", "content": "do it"]],
            "tools": lookupTool,
            "tool_choice": [
                "type": "function",
                "function": ["name": "missing"]
            ]
        ]))
        XCTAssertNil(server.parseChatParams([
            "messages": [["role": "user", "content": "do it"]],
            "tools": lookupTool,
            "tool_choice": "always"
        ]))
    }
}
