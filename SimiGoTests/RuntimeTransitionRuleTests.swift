import XCTest
@testable import SimiGo

/// LC 状态机契约测试：合法迁移表边界（SimiGo架构收敛.md §3 + 实测补充边）。
final class RuntimeTransitionRuleTests: XCTestCase {
    func testNormalLadderIsLegal() {
        XCTAssertTrue(RuntimeTransitionRule.isValid(from: .created, to: .queued))
        XCTAssertTrue(RuntimeTransitionRule.isValid(from: .queued, to: .running))
        XCTAssertTrue(RuntimeTransitionRule.isValid(from: .running, to: .completing))
        XCTAssertTrue(RuntimeTransitionRule.isValid(from: .completing, to: .completed))
        XCTAssertTrue(RuntimeTransitionRule.isValid(from: .completed, to: .releasing))
        XCTAssertTrue(RuntimeTransitionRule.isValid(from: .releasing, to: .released))
    }

    /// 2026-09-12 断链修复：协议层 QUEUED 补位缺失的入口，请求持有 generation gate
    /// 即事实 RUNNING——表必须承认，否则每个请求死于 INVALID→cancelled_internally。
    func testCreatedToRunningIsLegal() {
        XCTAssertTrue(RuntimeTransitionRule.isValid(from: .created, to: .running))
    }

    func testSSEDirectDispatchEdgeIsLegal() {
        XCTAssertTrue(RuntimeTransitionRule.isValid(from: .created, to: .completing))
    }

    func testCancelPipeReachableFromAnyNonReleasedState() {
        for from in RuntimeState.allCases where from != .released {
            XCTAssertTrue(
                RuntimeTransitionRule.isValid(from: from, to: .cancelling),
                "CANCELLING 必须从 \(from.rawValue) 可达"
            )
        }
        XCTAssertFalse(RuntimeTransitionRule.isValid(from: .released, to: .cancelling))
    }

    func testTableShortcutsAndTerminalStickiness() {
        // 非流式请求没有 STREAMING 阶段
        XCTAssertFalse(RuntimeTransitionRule.isValid(from: .created, to: .streaming))
        // 终态不可逆
        for to in RuntimeState.allCases where to != .released {
            XCTAssertFalse(
                RuntimeTransitionRule.isValid(from: .released, to: to),
                "RELEASED 不可迁移到 \(to.rawValue)"
            )
        }
        // 账本不可回退
        XCTAssertFalse(RuntimeTransitionRule.isValid(from: .running, to: .queued))
        XCTAssertFalse(RuntimeTransitionRule.isValid(from: .completed, to: .running))
    }
}
