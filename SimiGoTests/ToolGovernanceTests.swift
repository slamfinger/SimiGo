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
            lock.lock(); defer { lock.unlock() }; return all.count
        }
        func contains(_ needle: String) -> Bool {
            all.contains { $0.contains(needle) }
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

        XCTAssertTrue(recorder.contains("event=TOOL_REQUESTED"))
        XCTAssertTrue(recorder.contains("event=TOOL_VALIDATED"))
        XCTAssertTrue(recorder.contains("event=TOOL_DISPATCHED"))
        XCTAssertTrue(recorder.contains("event=TOOL_RESULT"))
        XCTAssertFalse(recorder.contains("anomaly="))
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

        XCTAssertTrue(recorder.contains("anomaly=illegal_transition"))
        // 状态未被伪造：后续合法 validated 仍可走通
        governance.validated(requestId: "r1", generationId: "r1", toolCallId: "c1")
        XCTAssertTrue(recorder.contains("event=TOOL_VALIDATED"))
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

        XCTAssertTrue(recorder.contains("anomaly=illegal_transition_from=rejected"))
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

        XCTAssertTrue(recorder.contains("anomaly=illegal_transition_from=rejected"))
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

}
