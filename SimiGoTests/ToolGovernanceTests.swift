import XCTest
@testable import SimiGo

/// P1-3 Tool Governance Contract v1（docs/decisions/TOOL_GOVERNANCE_CONTRACT.md）
/// 状态机契约测试：合法转移、非法转移拒绝、幂等、终态唯一。
final class ToolGovernanceTests: XCTestCase {
    private final class LineRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func append(_ line: String) {
            lock.lock(); lines.append(line); lock.unlock()
        }
        var all: [String] {
            lock.lock(); defer { lock.unlock() }; return lines
        }
        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return lines.count
        }
        func contains(_ needle: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return lines.contains { $0.contains(needle) }
        }
    }

    private var recorder: LineRecorder!
    private var governance: ToolGovernance!

    override func setUp() {
        super.setUp()
        recorder = LineRecorder()
        governance = ToolGovernance { [recorder] line in
            recorder.append(line)
        }
    }

    // MARK: - 合法转移

    func testValidatedPathRequestedValidatedDispatchedResult() {
        governance.requested(requestId: "r1", generationId: "r1", toolCallId: "c1", tool: "shell", argumentsRaw: "{}")
        governance.validated(requestId: "r1", generationId: "r1", toolCallId: "c1")
        governance.dispatched(requestId: "r1", generationId: "r1", toolCallId: "c1")
        governance.resultObserved(requestId: "r1", generationId: "r1", toolCallId: "c1", sizeBytes: nil)

        // v1.1 发射策略：正常路径只发 RESULT 摘要一行（带 durMs）；
        // 中间转移折叠，事实核验转 state(of:)。
        XCTAssertEqual(recorder.count, 1)
        XCTAssertTrue(recorder.contains("event=TOOL_RESULT"))
        XCTAssertTrue(recorder.contains("durMs="))
        XCTAssertFalse(recorder.contains("event=TOOL_REQUESTED"))
        XCTAssertFalse(recorder.contains("event=TOOL_VALIDATED"))
        XCTAssertFalse(recorder.contains("anomaly="))
        XCTAssertEqual(governance.state(of: "c1"), .result)
    }

    func testPreDispatchCancelRejectsWithCancelledCode() {
        governance.requested(requestId: "r1", generationId: "r1", toolCallId: "c1", tool: "shell", argumentsRaw: "{}")
        governance.validated(requestId: "r1", generationId: "r1", toolCallId: "c1")
        governance.rejected(requestId: "r1", generationId: "r1", toolCallId: "c1", code: .cancelled, message: "client abort")

        XCTAssertTrue(recorder.contains("event=TOOL_REJECTED"))
        XCTAssertTrue(recorder.contains("code=cancelled"))
        XCTAssertFalse(recorder.contains("event=TOOL_DISPATCHED"))
    }

    func testPostDispatchCancelFailsWithCancelledCode() {
        governance.requested(requestId: "r1", generationId: "r1", toolCallId: "c1", tool: "shell", argumentsRaw: "{}")
        governance.validated(requestId: "r1", generationId: "r1", toolCallId: "c1")
        governance.dispatched(requestId: "r1", generationId: "r1", toolCallId: "c1")
        governance.failed(requestId: "r1", generationId: "r1", toolCallId: "c1", code: .cancelled, message: "client abort")

        XCTAssertTrue(recorder.contains("event=TOOL_FAILED"))
        XCTAssertTrue(recorder.contains("code=cancelled"))
    }

    // MARK: - 非法转移（不伪造终态）

    func testRequestedToResultIsIllegalAndStateUnchanged() {
        governance.requested(requestId: "r1", generationId: "r1", toolCallId: "c1", tool: "shell", argumentsRaw: "{}")
        governance.resultObserved(requestId: "r1", generationId: "r1", toolCallId: "c1", sizeBytes: nil)

        XCTAssertTrue(recorder.contains("anomaly=unexpected_state"))
        // 状态未被伪造：后续合法 validated 仍可走通（v1.1：折叠不发 Validation 行，核验转状态）
        governance.validated(requestId: "r1", generationId: "r1", toolCallId: "c1")
        XCTAssertEqual(governance.state(of: "c1"), .validated)
    }

    func testRequestedToFailedIsIllegal() {
        governance.requested(requestId: "r1", generationId: "r1", toolCallId: "c1", tool: "shell", argumentsRaw: "{}")
        governance.failed(requestId: "r1", generationId: "r1", toolCallId: "c1", code: .executionError, message: "x")

        XCTAssertTrue(recorder.contains("anomaly=illegal_transition"))
        XCTAssertFalse(recorder.contains("event=TOOL_FAILED"))
    }

    func testRejectedToDispatchedIsIllegal() {
        governance.requested(requestId: "r1", generationId: "r1", toolCallId: "c1", tool: "shell", argumentsRaw: "{}")
        governance.rejected(requestId: "r1", generationId: "r1", toolCallId: "c1", code: .unknownTool, message: "undeclared")
        governance.dispatched(requestId: "r1", generationId: "r1", toolCallId: "c1")

        XCTAssertTrue(recorder.contains("anomaly=illegal_transition from=rejected"))
        // 终态未被推翻
        XCTAssertTrue(recorder.contains("event=TOOL_REJECTED"))
        XCTAssertFalse(recorder.contains("event=TOOL_DISPATCHED"))
    }

    func testTerminalStatesAreSticky() {
        governance.requested(requestId: "r1", generationId: "r1", toolCallId: "c1", tool: "shell", argumentsRaw: "{}")
        governance.validated(requestId: "r1", generationId: "r1", toolCallId: "c1")
        governance.rejected(requestId: "r1", generationId: "r1", toolCallId: "c1", code: .policyDenied, message: "deny")
        // 终态之后的任何转移都被拒绝
        governance.validated(requestId: "r1", generationId: "r1", toolCallId: "c1")
        governance.resultObserved(requestId: "r1", generationId: "r1", toolCallId: "c1", sizeBytes: nil)

        XCTAssertTrue(recorder.contains("anomaly=illegal_transition from=rejected"))
    }

    // MARK: - 幂等

    func testResultReobservationIsNoOp() {
        governance.requested(requestId: "r1", generationId: "r1", toolCallId: "c1", tool: "shell", argumentsRaw: "{}")
        governance.validated(requestId: "r1", generationId: "r1", toolCallId: "c1")
        governance.resultObserved(requestId: "r1", generationId: "r1", toolCallId: "c1", sizeBytes: nil)
        let countAfterFirst = recorderContainsCount("event=TOOL_RESULT")
        governance.resultObserved(requestId: "r1", generationId: "r1", toolCallId: "c1", sizeBytes: nil)

        XCTAssertEqual(countAfterFirst, 1, "重复 RESULT 观测不应产生新事件行")
    }

    private func recorderContainsCount(_ needle: String) -> Int {
        recorder.all.filter { $0.contains(needle) }.count
    }

    // MARK: - 未知 / 重复

    func testUnknownToolCallIdResultIsAnomaly() {
        governance.resultObserved(requestId: "rX", generationId: "rX", toolCallId: "nope", sizeBytes: nil)
        XCTAssertTrue(recorder.contains("anomaly=unknown_tc"))
    }

    func testDuplicateRequestedIsAnomaly() {
        governance.requested(requestId: "r1", generationId: "r1", toolCallId: "c1", tool: "shell", argumentsRaw: "{}")
        governance.requested(requestId: "r1", generationId: "r1", toolCallId: "c1", tool: "shell", argumentsRaw: "{}")

        XCTAssertTrue(recorder.contains("anomaly=dup_tc"))
    }


    func testExpiredInvocationsArePruned() {
        let start = Date()
        let subject = ToolGovernance(
            emit: { _ in },
            retentionInterval: 10,
            maxRetainedInvocations: 10)
        subject.requested(
            requestId: "r-expired", generationId: "g-expired",
            toolCallId: "expired-call", tool: "shell", argumentsRaw: "{}")
        subject.validated(
            requestId: "r-expired", generationId: "g-expired",
            toolCallId: "expired-call")
        XCTAssertEqual(subject.state(of: "expired-call"), .validated)

        XCTAssertEqual(subject.pruneExpired(now: start.addingTimeInterval(11)), 1)
        XCTAssertNil(subject.state(of: "expired-call"))
        XCTAssertEqual(subject.retainedInvocationCount, 0)
    }

    func testRetentionBoundEvictsTerminalBeforePendingCalls() {
        let subject = ToolGovernance(
            emit: { _ in },
            retentionInterval: 3_600,
            maxRetainedInvocations: 2)

        subject.requested(
            requestId: "r1", generationId: "g1",
            toolCallId: "terminal", tool: "shell", argumentsRaw: "{}")
        subject.rejected(
            requestId: "r1", generationId: "g1", toolCallId: "terminal",
            code: .policyDenied, message: "denied")

        subject.requested(
            requestId: "r2", generationId: "g2",
            toolCallId: "pending-1", tool: "shell", argumentsRaw: "{}")
        subject.requested(
            requestId: "r3", generationId: "g3",
            toolCallId: "pending-2", tool: "shell", argumentsRaw: "{}")

        XCTAssertNil(subject.state(of: "terminal"),
                     "old terminal records are the first capacity eviction candidates")
        XCTAssertEqual(subject.state(of: "pending-1"), .requested)
        XCTAssertEqual(subject.state(of: "pending-2"), .requested)
        XCTAssertEqual(subject.retainedInvocationCount, 2)
    }

}

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
            expectedArguments: [:],
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
            expectedArguments: [:],
            requiredEvidence: ["18C"])

        let failures = eval.score(
            toolCalls: [AgentToolCallRecord(name: "weather", argumentsJSON: #"{"city":"Bratislava"}"#)],
            successfulToolOutputs: [],
            finalAnswer: "The measured temperature is 18C.")

        XCTAssertEqual(failures, ["missing_tool_evidence:18C"])
    }
}

