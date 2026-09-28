import XCTest
@testable import SimiGo

final class SessionGenerationGateMultiKeyTests: XCTestCase {
    private func key(_ branch: String) -> AgentExecutionKey {
        try! AgentExecutionKey(
            agentId: nil,
            sessionId: "gate-test",
            logicalBranchId: branch
        )
    }

    func testOppositeMultiKeyOrderDoesNotDeadlock() async throws {
        let gate = SessionGenerationGate()
        let a = key("a")
        let b = key("b")
        let start = Date()

        async let first: Void = gate.withExclusive([a, b]) {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        async let second: Void = gate.withExclusive([b, a]) {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        _ = try await (first, second)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }

    func testMultiKeyTransactionBlocksBothSingleKeys() async throws {
        let gate = SessionGenerationGate()
        let a = key("a")
        let b = key("b")
        let acquired = Locked(false)

        let holder = Task {
            try await gate.withExclusive([a, b]) {
                acquired.set(true)
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        while !acquired.value {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        let blockedA = Task {
            try await gate.withExclusive(a) { true }
        }
        let blockedB = Task {
            try await gate.withExclusive(b) { true }
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertFalse(blockedA.isCancelled)
        XCTAssertFalse(blockedB.isCancelled)

        _ = try await holder.value
        XCTAssertTrue(try await blockedA.value)
        XCTAssertTrue(try await blockedB.value)
    }
}
