import XCTest
@testable import SimiGo

/// AgentExecutionKey 身份模型契约（审计 🟠 第 3 条的落地锚点）：
/// storageKey（agent/session）= KV 与 Session storage 粒度；
/// gateKey（agent/session/branch）= generation 串行化粒度。
/// 二者的语义差是架构不变量：任何修改 sessionCaches 的代码必须意识到
/// 同 Session 的不同 branch 可以并发运行。
final class AgentExecutionKeyTests: XCTestCase {
    // MARK: - Normalization

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

    // MARK: - Key Shape Contract

    func testStorageKeyIsAgentAndSessionOnly() throws {
        let key = try AgentExecutionKey(agentId: "agent", sessionId: "session", logicalBranchId: "branch")
        XCTAssertEqual(key.storageKey, "agent/session")
    }

    func testGateKeyIncludesBranch() throws {
        let key = try AgentExecutionKey(agentId: "agent", sessionId: "session", logicalBranchId: "branch")
        XCTAssertEqual(key.gateKey, "agent/session/branch")
        XCTAssertEqual(key.traceKey, key.gateKey)
    }

    // MARK: - Identity

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
        // 关键架构语义：不同 branch → 不同 gateKey（可并行），但相同 storageKey（共享 Session state）
        XCTAssertEqual(a.storageKey, b.storageKey)
        XCTAssertNotEqual(a.gateKey, b.gateKey)
    }
}
