import XCTest
@testable import SimiGo2Experimental

final class ExecutionResidencyPlannerTests: XCTestCase {
    private func inventory() -> LayerInventory {
        LayerInventory(
            groups: [
                LayerGroup(id: "CORE", title: "Core", layerRangeDescription: "core", tensorCount: 1, byteCount: 100, alwaysResident: true),
                LayerGroup(id: "A", title: "A", layerRangeDescription: "0-15", tensorCount: 1, byteCount: 100),
                LayerGroup(id: "B", title: "B", layerRangeDescription: "16-31", tensorCount: 1, byteCount: 100),
                LayerGroup(id: "C", title: "C", layerRangeDescription: "32-47", tensorCount: 1, byteCount: 100)
            ],
            tensors: [],
            totalByteCount: 400
        )
    }

    private func qwenSequenceInventory() -> LayerInventory {
        LayerInventory(
            groups: [
                LayerGroup(id: "CORE_NON_SWITCH", title: "Core", layerRangeDescription: "core", tensorCount: 1, byteCount: 100, alwaysResident: true),
                LayerGroup(id: "SWITCH_MLP_L00_15", title: "A", layerRangeDescription: "0-15", tensorCount: 1, byteCount: 100),
                LayerGroup(id: "SWITCH_MLP_L16_31", title: "B", layerRangeDescription: "16-31", tensorCount: 1, byteCount: 100),
                LayerGroup(id: "SWITCH_MLP_L32_47", title: "C", layerRangeDescription: "32-47", tensorCount: 1, byteCount: 100)
            ],
            tensors: [],
            totalByteCount: 400
        )
    }

    func testCoreAndRequiredGroupsArePreserved() throws {
        let planner = ExecutionResidencyPlanner(inventory: inventory())
        let plan = try planner.plan(
            currentResidentGroupIDs: ["CORE", "A"],
            requiredGroupIDs: ["CORE", "B"],
            demandHints: [],
            budget: ResidencyBudgetPolicy(fixedBytes: 200),
            recommendedBytes: 400
        )

        XCTAssertEqual(plan.residentGroupIDs, ["CORE", "B"])
        XCTAssertEqual(plan.loadGroupIDs, ["B"])
        XCTAssertEqual(plan.evictGroupIDs, ["A"])
        XCTAssertTrue(plan.fitsBudget)
    }

    func testHighestPriorityWorkingSetFitsBudget() throws {
        let planner = ExecutionResidencyPlanner(inventory: inventory())
        let plan = try planner.plan(
            currentResidentGroupIDs: ["CORE"],
            requiredGroupIDs: ["CORE"],
            demandHints: [
                ResidencyDemandHint(groupID: "A", priority: 0.2),
                ResidencyDemandHint(groupID: "B", priority: 0.9),
                ResidencyDemandHint(groupID: "C", priority: 0.8)
            ],
            budget: ResidencyBudgetPolicy(fixedBytes: 300),
            recommendedBytes: 400
        )

        XCTAssertEqual(plan.residentGroupIDs, ["CORE", "B", "C"])
        XCTAssertEqual(plan.residentBytes, 300)
    }

    func testRequiredOverflowIsReported() throws {
        let planner = ExecutionResidencyPlanner(inventory: inventory())
        let plan = try planner.plan(
            currentResidentGroupIDs: ["CORE"],
            requiredGroupIDs: ["CORE", "A", "B"],
            demandHints: [],
            budget: ResidencyBudgetPolicy(fixedBytes: 200),
            recommendedBytes: 400
        )

        XCTAssertFalse(plan.fitsBudget)
        XCTAssertEqual(plan.overflowGroupIDs, ["CORE", "A", "B"])
    }

    func testUnknownGroupsAndNonFinitePriorityFail() {
        let planner = ExecutionResidencyPlanner(inventory: inventory())

        XCTAssertThrowsError(
            try planner.plan(
                currentResidentGroupIDs: [],
                requiredGroupIDs: ["NOPE"],
                demandHints: [],
                budget: ResidencyBudgetPolicy(fixedBytes: 200),
                recommendedBytes: 400
            )
        )

        XCTAssertThrowsError(
            try planner.plan(
                currentResidentGroupIDs: [],
                requiredGroupIDs: ["CORE"],
                demandHints: [ResidencyDemandHint(groupID: "A", priority: .infinity)],
                budget: ResidencyBudgetPolicy(fixedBytes: 200),
                recommendedBytes: 400
            )
        )
    }

    func testBudgetSweepRejectsInvalidBudgets() {
        let inventory = inventory()

        XCTAssertThrowsError(
            try PlannerBudgetSweep.run(inventory: inventory, budgetPercents: [])
        )
        XCTAssertThrowsError(
            try PlannerBudgetSweep.run(inventory: inventory, budgetPercents: [0, 50])
        )
    }

    func testBudgetSweepProducesOneEntryPerSequenceAndBudget() throws {
        let report = try PlannerBudgetSweep.run(
            inventory: qwenSequenceInventory(),
            sequenceIDs: ["LOCALITY_A", "ALTERNATE_AB"],
            budgetPercents: [25, 100]
        )

        XCTAssertEqual(report.entries.count, 4)
        XCTAssertTrue(report.boundary.contains("NOT_PREDICTION"))

        let locality = report.entries.filter { $0.sequenceID == "LOCALITY_A" }
        XCTAssertEqual(locality.map(\.budgetPercent), [25, 100])
        XCTAssertEqual(locality.map(\.overflowTransitionCount), [5, 0])
    }
}
