import XCTest
@testable import SimiGo

/// Small deterministic eval primitives: cases declare expectations and the
/// scorer evaluates recorded tool names, successful outputs, and final text.
/// Real model selection/argument/grounding remains a separately gated run.
private struct AgentToolCallRecord {
    let name: String
    let argumentsJSON: String
}

private struct AgentBehaviorEvalCase {
    let id: String
    let requiredTools: Set<String>
    let forbiddenTools: Set<String>
    let expectedArguments: [String: String]
    let requiredEvidence: Set<String>

    func score(
        toolCalls: [AgentToolCallRecord],
        successfulToolOutputs: [String],
        finalAnswer: String
    ) -> [String] {
        var failures: [String] = []
        let observed = Set(toolCalls.map(\.name))
        for tool in requiredTools.subtracting(observed).sorted() {
            failures.append("missing_required_tool:\(tool)")
        }
        for tool in forbiddenTools.intersection(observed).sorted() {
            failures.append("unexpected_tool:\(tool)")
        }
        for (tool, expectedJSON) in expectedArguments.sorted(by: { $0.key < $1.key }) {
            guard let actual = toolCalls.first(where: { $0.name == tool }) else { continue }
            guard let expectedObject = try? JSONSerialization.jsonObject(with: Data(expectedJSON.utf8)),
                  let actualObject = try? JSONSerialization.jsonObject(with: Data(actual.argumentsJSON.utf8)) else {
                failures.append("invalid_tool_arguments:\(tool)")
                continue
            }
            let expectedData = try? JSONSerialization.data(withJSONObject: expectedObject, options: [.sortedKeys])
            let actualData = try? JSONSerialization.data(withJSONObject: actualObject, options: [.sortedKeys])
            if expectedData != actualData {
                failures.append("incorrect_tool_arguments:\(tool)")
            }
        }
        let evidence = successfulToolOutputs.joined(separator: "\n")
        for value in requiredEvidence.sorted() {
            guard evidence.contains(value) else {
                failures.append("missing_tool_evidence:\(value)")
                continue
            }
            if !finalAnswer.contains(value) {
                failures.append("answer_not_grounded:\(value)")
            }
        }
        return failures
    }
}

final class AgentBehaviorEvalTests: XCTestCase {
    private final class Transcript: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []

        func append(_ line: String) {
            lock.lock()
            storage.append(line)
            lock.unlock()
        }

        var lines: [String] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func count(containing fragment: String) -> Int {
            lines.filter { $0.contains(fragment) }.count
        }
    }

    private func makeGovernance() -> (ToolGovernance, Transcript) {
        let transcript = Transcript()
        let governance = ToolGovernance { transcript.append($0) }
        return (governance, transcript)
    }

    private func request(
        _ governance: ToolGovernance,
        id: String,
        generation: String,
        tool: String
    ) {
        governance.requested(
            requestId: generation,
            generationId: generation,
            toolCallId: id,
            tool: tool,
            argumentsRaw: "{}")
        governance.validated(
            requestId: generation, generationId: generation, toolCallId: id)
    }

    func testEvalInterleavedToolCallsKeepResultAssociation() {
        let (governance, transcript) = makeGovernance()
        request(governance, id: "call-A", generation: "gen-1", tool: "lookup")
        request(governance, id: "call-B", generation: "gen-1", tool: "calculate")

        governance.resultObserved(
            requestId: "gen-1", generationId: "gen-1",
            toolCallId: "call-B", sizeBytes: 4)
        governance.resultObserved(
            requestId: "gen-1", generationId: "gen-1",
            toolCallId: "call-A", sizeBytes: 8)

        XCTAssertEqual(governance.state(of: "call-A"), .result)
        XCTAssertEqual(governance.state(of: "call-B"), .result)
        XCTAssertEqual(transcript.count(containing: "event=TOOL_RESULT"), 2)
        XCTAssertTrue(transcript.lines.contains { $0.contains("tc=call-A") && $0.contains("tool=lookup") })
        XCTAssertTrue(transcript.lines.contains { $0.contains("tc=call-B") && $0.contains("tool=calculate") })
        XCTAssertFalse(transcript.lines.contains { $0.contains("anomaly=") })
    }

    func testEvalHistoricalToolOutputReplayIsIdempotent() {
        let (governance, transcript) = makeGovernance()
        request(governance, id: "call-replay", generation: "gen-replay", tool: "search")
        governance.resultObserved(
            requestId: "gen-replay", generationId: "gen-replay",
            toolCallId: "call-replay", sizeBytes: 12)
        let firstResultCount = transcript.count(containing: "event=TOOL_RESULT")

        governance.resultObserved(
            requestId: "gen-replay-next", generationId: "gen-replay-next",
            toolCallId: "call-replay", sizeBytes: 12)

        XCTAssertEqual(firstResultCount, 1)
        XCTAssertEqual(transcript.count(containing: "event=TOOL_RESULT"), 1)
        XCTAssertEqual(governance.state(of: "call-replay"), .result)
    }

    func testEvalRejectedCallCannotBecomeGroundingEvidence() {
        let (governance, transcript) = makeGovernance()
        governance.requested(
            requestId: "gen-denied", generationId: "gen-denied",
            toolCallId: "call-denied", tool: "shell", argumentsRaw: "{}")
        governance.rejected(
            requestId: "gen-denied", generationId: "gen-denied",
            toolCallId: "call-denied", code: .policyDenied, message: "denied")

        XCTAssertNotEqual(governance.state(of: "call-denied"), .result)
        XCTAssertEqual(governance.state(of: "call-denied"), .rejected)
        XCTAssertEqual(transcript.count(containing: "event=TOOL_REJECTED"), 1)
        XCTAssertEqual(transcript.count(containing: "event=TOOL_RESULT"), 0)
    }

    func testEvalScorerPassesWhenRequiredToolAndEvidenceArePresent() {
        let eval = AgentBehaviorEvalCase(
            id: "weather-grounding",
            requiredTools: ["weather"],
            forbiddenTools: ["shell"],
            expectedArguments: ["weather": #"{"city":"Bratislava"}"#],
            expectedArguments: ["weather": #"{"city":"Bratislava"}"#],
            expectedArguments: ["weather": #"{"city":"Bratislava"}"#],
            requiredEvidence: ["18C"])

        let failures = eval.score(
            toolCalls: [AgentToolCallRecord(name: "weather", argumentsJSON: #"{"city":"Bratislava"}"#)],
            successfulToolOutputs: ["temperature=18C"],
            finalAnswer: "The measured temperature is 18C.")

        XCTAssertTrue(failures.isEmpty, "Unexpected eval failures: \(failures)")
    }

    func testEvalScorerDetectsWrongToolMissingEvidenceAndUngroundedAnswer() {
        let eval = AgentBehaviorEvalCase(
            id: "weather-grounding",
            requiredTools: ["weather"],
            forbiddenTools: ["shell"],
            requiredEvidence: ["18C"])

        let failures = eval.score(
            toolCalls: [AgentToolCallRecord(name: "shell", argumentsJSON: #"{"command":"x"}"#)],
            successfulToolOutputs: ["temperature=18C"],
            finalAnswer: "The temperature is 23C.")

        XCTAssertEqual(
            failures,
            ["missing_required_tool:weather", "unexpected_tool:shell", "answer_not_grounded:18C"])
    }

    func testEvalScorerDetectsIncorrectToolArguments() {
        let eval = AgentBehaviorEvalCase(
            id: "weather-arguments",
            requiredTools: ["weather"],
            forbiddenTools: [],
            expectedArguments: ["weather": #"{"city":"Bratislava"}"#],
            requiredEvidence: [])

        let failures = eval.score(
            toolCalls: [AgentToolCallRecord(name: "weather", argumentsJSON: #"{"city":"Vienna"}"#)],
            successfulToolOutputs: [],
            finalAnswer: "")

        XCTAssertEqual(failures, ["incorrect_tool_arguments:weather"])
    }

    func testEvalScorerDoesNotAcceptEvidenceAbsentFromSuccessfulToolOutputs() {
        let eval = AgentBehaviorEvalCase(
            id: "weather-grounding",
            requiredTools: ["weather"],
            forbiddenTools: [],
            requiredEvidence: ["18C"])

        let failures = eval.score(
            toolCalls: [AgentToolCallRecord(name: "weather", argumentsJSON: #"{"city":"Bratislava"}"#)],
            successfulToolOutputs: [],
            finalAnswer: "The measured temperature is 18C.")

        XCTAssertEqual(failures, ["missing_tool_evidence:18C"])
    }
}
