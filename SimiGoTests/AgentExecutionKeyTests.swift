import XCTest
@testable import SimiGo

final class AgentExecutionKeyTests: XCTestCase {
    func testNilAgentIdFallsBackToDefault() throws {
        let key = try AgentExecutionKey(agentId: nil, sessionId: "s1", logicalBranchId: "b1")
        XCTAssertEqual(key.agentId, "default")
    }

    func testWhitespaceOnlyAgentIdFallsBackToDefault() throws {
        let key = try AgentExecutionKey(agentId: "   ", sessionId: "s1", logicalBranchId: "b1")
        XCTAssertEqual(key.agentId, "default")
    }

    func testAgentIdIsTrimmed() throws {
        let key = try AgentExecutionKey(agentId: "  agent-a  ", sessionId: "s1", logicalBranchId: "b1")
        XCTAssertEqual(key.agentId, "agent-a")
    }

    func testBlankSessionIdThrows() {
        XCTAssertThrowsError(try AgentExecutionKey(agentId: nil, sessionId: "  ", logicalBranchId: "b1"))
        XCTAssertThrowsError(try AgentExecutionKey(agentId: nil, sessionId: "", logicalBranchId: "b1"))
    }

    func testBlankBranchIdThrows() {
        XCTAssertThrowsError(try AgentExecutionKey(agentId: nil, sessionId: "s1", logicalBranchId: ""))
    }

    func testStorageKeyIncludesBranchBecauseChatSessionOwnsKV() throws {
        let key = try AgentExecutionKey(agentId: "agent", sessionId: "session", logicalBranchId: "branch")
        XCTAssertEqual(key.storageKey, "agent/session/branch")
    }

    func testTraceKeyIsCompactAndKeepsBranch() throws {
        let key = try AgentExecutionKey(
            agentId: "default",
            sessionId: "9dc81004-675e-44f1-939d-2c93f1662007",
            logicalBranchId: "main")
        XCTAssertEqual(key.traceKey, "662007/main")

        let short = try AgentExecutionKey(agentId: "agent", sessionId: "s1", logicalBranchId: "b1")
        XCTAssertEqual(short.traceKey, "agent/s1/b1")

        let otherBranch = try AgentExecutionKey(
            agentId: "default",
            sessionId: "9dc81004-675e-44f1-939d-2c93f1662007",
            logicalBranchId: "side")
        XCTAssertNotEqual(key.traceKey, otherBranch.traceKey)
    }

    func testKeysWithSameFieldsAreEqualAndHashAlike() throws {
        let a = try AgentExecutionKey(agentId: "agent", sessionId: "session", logicalBranchId: "branch")
        let b = try AgentExecutionKey(agentId: "agent", sessionId: "session", logicalBranchId: "branch")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func testKeysDifferOnlyByBranch() throws {
        let a = try AgentExecutionKey(agentId: "agent", sessionId: "session", logicalBranchId: "branch-1")
        let b = try AgentExecutionKey(agentId: "agent", sessionId: "session", logicalBranchId: "branch-2")
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a.storageKey, b.storageKey)
        XCTAssertNotEqual(a.traceKey, b.traceKey)
    }
}
