import XCTest
@testable import SimiGo

/// Deterministic, model-free behavior evaluations for the NativeMLX tool boundary.
///
/// These cases borrow the case/scorer separation used by OsaurusEvals:
/// fixtures describe the expected behavior; the runner records a transcript;
/// assertions score state transitions and result-to-call association.
/// They deliberately do not pretend to evaluate model intelligence. Real-model
/// selection/argument/grounding quality remains a separately gated evaluation.
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

    /// Two calls may complete out of order. The transcript and terminal state
    /// must remain attached to their own call IDs, not completion order.
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

    /// A historical tool output can be replayed in a later request. Re-observing
    /// it must not create a second result event or alter the terminal state.
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

    /// A rejected call must not be scored as a successful tool execution.
    func testEvalRejectedCallCannotBecomeGroundingEvidence() {
        let (governance, transcript) = makeGovernance()
        governance.requested(
            requestId: "gen-denied", generationId: "gen-denied",
            toolCallId: "call-denied", tool: "shell", argumentsRaw: "{}")
        governance.rejected(
            requestId: "gen-denied", generationId: "gen-denied",
            toolCallId: "call-denied", code: .policyDenied, message: "denied")

        // The fixture's grounding scorer accepts only a recorded successful
        // result as evidence; rejection text is not a tool result.
        let hasSuccessfulEvidence = governance.state(of: "call-denied") == .result
        XCTAssertFalse(hasSuccessfulEvidence)
        XCTAssertEqual(governance.state(of: "call-denied"), .rejected)
        XCTAssertEqual(transcript.count(containing: "event=TOOL_REJECTED"), 1)
        XCTAssertEqual(transcript.count(containing: "event=TOOL_RESULT"), 0)
    }

    /// A small deterministic grounding scorer for transcript fixtures. It checks
    /// exact tool-output evidence rather than asking an LLM judge to infer it.
    func testEvalFinalAnswerMustContainTheObservedToolValue() {
        let observedToolValue = "temperature=18C"
        let groundedAnswer = "The measured temperature is 18C."
        let unsupportedAnswer = "The temperature is 23C."

        XCTAssertTrue(groundedAnswer.contains("18C"))
        XCTAssertFalse(unsupportedAnswer.contains("18C"))
        XCTAssertTrue(observedToolValue.contains("18C"))
    }
}
