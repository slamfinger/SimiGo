import XCTest
@testable import SimiGoRuntimeContract

/// 钉住「记账类请求不装配上下文」这条判定。
///
/// 它同时钉住线上的值：客户端发的就是 `internal`，改名会让所有已发的标记
/// 失效，那是另一件事，不该被顺手做掉。
final class TurnEligibilityContextTests: XCTestCase {
    func testInternalBookkeepingSkipsContextAssembly() {
        XCTAssertTrue(ESISDatabase.ChatTurnEligibility.internalOperation.skipsContextAssembly)
    }

    func testOrdinaryConversationAssemblesContext() {
        XCTAssertFalse(ESISDatabase.ChatTurnEligibility.ordinary.skipsContextAssembly)
    }

    func testWireValueOfInternalStandingIsUnchanged() {
        XCTAssertEqual(ESISDatabase.ChatTurnEligibility.internalOperation.rawValue, "internal")
    }
}
