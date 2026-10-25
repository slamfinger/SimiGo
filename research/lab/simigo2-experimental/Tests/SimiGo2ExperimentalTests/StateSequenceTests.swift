import XCTest
@testable import SimiGo2Experimental

final class StateSequenceTests: XCTestCase {
    func testCatalogContainsBaselineAndLocalityCases() throws {
        let ids = Set(StateSequenceCatalog.cases.map(\.id))
        XCTAssertTrue(ids.contains("BASELINE_ABA"))
        XCTAssertTrue(ids.contains("LOCALITY_A"))
        XCTAssertTrue(ids.contains("ALTERNATE_AB"))
        XCTAssertTrue(ids.contains("CYCLE_ABC"))
        XCTAssertTrue(ids.contains("ALTERNATE_A_AB"))
        XCTAssertTrue(ids.contains("FULL_PARTIAL"))
    }

    func testNamedSequencePreservesDeclaredOrder() throws {
        let sequence = try StateSequenceCatalog.named("ALTERNATE_AB")
        XCTAssertEqual(
            sequence.states,
            [.stateA, .stateB, .stateA, .stateB, .stateA]
        )
    }

    func testUnknownSequenceFails() {
        XCTAssertThrowsError(try StateSequenceCatalog.named("NO_SUCH_SEQUENCE"))
    }
}
