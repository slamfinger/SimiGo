import XCTest
@testable import SimiGo2Experimental

final class RuntimeResidencyContractL1Tests: XCTestCase {
    private func inventory() -> LayerInventory {
        LayerInventory(
            groups: [
                LayerGroup(id: "CORE", title: "Core", layerRangeDescription: "core", tensorCount: 1, byteCount: 100, alwaysResident: true),
                LayerGroup(id: "A", title: "A", layerRangeDescription: "0", tensorCount: 1, byteCount: 100),
                LayerGroup(id: "B", title: "B", layerRangeDescription: "1", tensorCount: 1, byteCount: 100),
                LayerGroup(id: "C", title: "C", layerRangeDescription: "2", tensorCount: 1, byteCount: 100)
            ],
            tensors: [],
            totalByteCount: 400
        )
    }

    func testPlannerIsDeterministic() throws {
        let planner = ExecutionResidencyPlanner(inventory: inventory())
        let arguments = (
            current: Set(["CORE", "A"]),
            required: Set(["CORE", "B"]),
            hints: [
                ResidencyDemandHint(groupID: "C", priority: 0.5),
                ResidencyDemandHint(groupID: "B", priority: 0.5)
            ],
            budget: ResidencyBudgetPolicy(fixedBytes: 300),
            recommended: Int64(400)
        )

        let first = try planner.plan(
            currentResidentGroupIDs: arguments.current,
            requiredGroupIDs: arguments.required,
            demandHints: arguments.hints,
            budget: arguments.budget,
            recommendedBytes: arguments.recommended
        )
        let second = try planner.plan(
            currentResidentGroupIDs: arguments.current,
            requiredGroupIDs: arguments.required,
            demandHints: arguments.hints,
            budget: arguments.budget,
            recommendedBytes: arguments.recommended
        )

        XCTAssertEqual(first, second)
    }

    func testPlannerWithNoHintsDoesNotInventAdditionalDemand() throws {
        let planner = ExecutionResidencyPlanner(inventory: inventory())
        let plan = try planner.plan(
            currentResidentGroupIDs: ["CORE"],
            requiredGroupIDs: ["CORE", "A"],
            demandHints: [],
            budget: ResidencyBudgetPolicy(fixedBytes: 300),
            recommendedBytes: 400
        )

        XCTAssertEqual(plan.residentGroupIDs, ["CORE", "A"])
        XCTAssertEqual(plan.loadGroupIDs, ["A"])
        XCTAssertEqual(plan.keepGroupIDs, ["CORE"])
    }

    func testOverflowIsReportedWithoutPlannerSideEffectOrImplicitExecution() throws {
        let planner = ExecutionResidencyPlanner(inventory: inventory())
        let current = Set(["CORE"])
        let plan = try planner.plan(
            currentResidentGroupIDs: current,
            requiredGroupIDs: ["CORE", "A", "B"],
            demandHints: [],
            budget: ResidencyBudgetPolicy(fixedBytes: 200),
            recommendedBytes: 400
        )

        XCTAssertEqual(plan.overflowGroupIDs, ["CORE", "A", "B"])
        XCTAssertFalse(plan.fitsBudget)
        XCTAssertEqual(current, ["CORE"])
    }

    func testPlannerReportsLoadKeepEvictAsPureSetOperations() throws {
        let planner = ExecutionResidencyPlanner(inventory: inventory())
        let plan = try planner.plan(
            currentResidentGroupIDs: ["CORE", "A"],
            requiredGroupIDs: ["CORE", "B"],
            demandHints: [],
            budget: ResidencyBudgetPolicy(fixedBytes: 300),
            recommendedBytes: 400
        )

        XCTAssertEqual(plan.loadGroupIDs, ["B"])
        XCTAssertEqual(plan.keepGroupIDs, ["CORE"])
        XCTAssertEqual(plan.evictGroupIDs, ["A"])
        XCTAssertEqual(plan.residentGroupIDs, ["CORE", "B"])
    }

    func testPlannerRejectsNonFiniteHintPriority() {
        let planner = ExecutionResidencyPlanner(inventory: inventory())

        XCTAssertThrowsError(
            try planner.plan(
                currentResidentGroupIDs: ["CORE"],
                requiredGroupIDs: ["CORE"],
                demandHints: [ResidencyDemandHint(groupID: "A", priority: .infinity)],
                budget: ResidencyBudgetPolicy(fixedBytes: 300),
                recommendedBytes: 400
            )
        )
    }
}
