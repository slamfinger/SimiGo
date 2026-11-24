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

    private var declaredTools: [JSONValue] {
        [.object([
            "type": .string("function"),
            "function": .object([
                "name": .string("lookup"),
                "description": .string("Look up a record."),
                "parameters": .object(["type": .string("object")])
            ])
        ])]
    }

    func testOmittedAndNullToolChoicePreserveAuto() {
        XCTAssertEqual(ToolChoiceSelection.parse(nil)?.mode, .auto)
        XCTAssertEqual(ToolChoiceSelection.parse(NSNull())?.mode, .auto)
        XCTAssertEqual(ToolChoiceSelection.parse("auto")?.mode, .auto)
        let auto = ToolChoiceSelection(mode: .auto)
        XCTAssertTrue(auto.permitsToolCall)
        XCTAssertTrue(auto.isSatisfied(by: []), "auto permits a normal text answer")
        XCTAssertTrue(auto.isSatisfied(by: ["lookup"]), "auto remains unrestricted")
    }

    func testNoneForbidsWT15ToolCallShapeAndPermitsProse() {
        let none = ToolChoiceSelection(mode: .none)
        XCTAssertFalse(none.permitsToolCall)
        XCTAssertTrue(none.isSatisfied(by: []))
        XCTAssertFalse(none.isSatisfied(by: ["is_read_source"]))
    }

    func testNoneKeepsDeclaredSchemasIndependentlyOfPermission() {
        let none = ToolChoiceSelection(mode: .none)
        XCTAssertEqual(NativeMLX.toolsForChoice(declaredTools, selection: none), declaredTools)
        XCTAssertNil(NativeMLX.toolsForChoice(nil, selection: none))
    }

    func testNoneWithDeclaredToolsRemainsValidAtChatBoundary() {
        let server = makeServer()
        let parsed = server.parseChatParams([
            "messages": [["role": "user", "content": "answer without tools"]],
            "tools": lookupTool,
            "tool_choice": "none"
        ])
        XCTAssertEqual(parsed?.5.toolChoice?.mode, ToolChoiceMode.none)
    }

    func testOversizedSupportDistinguishesNoneFromToolCapableChoices() {
        let none = ToolChoiceSelection(mode: .none)
        XCTAssertNoThrow(try OversizedRuntime.validateToolChoiceSupport(none, tools: declaredTools))

        for choice in [
            ToolChoiceSelection(mode: .auto),
            ToolChoiceSelection(mode: .required),
            ToolChoiceSelection(mode: .function, functionName: "lookup")
        ] {
            XCTAssertThrowsError(
                try OversizedRuntime.validateToolChoiceSupport(choice, tools: declaredTools)
            ) { error in
                XCTAssertEqual(
                    (error as? RuntError)?.toolChoiceFailureCode,
                    "tool_calling_unsupported")
            }
        }
    }

    func testStringChoicesParseWithoutChangingAutoSemantics() {
        XCTAssertEqual(ToolChoiceSelection.parse("none")?.mode, ToolChoiceMode.none)
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
        XCTAssertNil(server.parseChatParams([
            "messages": [["role": "user", "content": "do it"]],
            "tools": [["type": "custom", "name": "lookup"]],
            "tool_choice": "required"
        ]), "required must not accept a non-function or malformed tool schema")
    }
}
