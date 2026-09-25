import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

final class ResidencyControllerTests: XCTestCase {
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

    private func assertInvariants(
        _ controller: ResidencyController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            controller.auditReplay().residentGroupIDs,
            controller.residentGroupIDs,
            "INV-1 violated: transfer-log replay diverges from bookkeeping",
            file: file,
            line: line
        )
    }

    func testAdmitLoadsMissingGroupsInDeterministicOrder() throws {
        let mock = MockResidencyMaterializer()
        let controller = ResidencyController(inventory: inventory(), materializer: mock)

        let outcome = try controller.admit(
            requiredGroupIDs: ["CORE", "A", "B"],
            budget: ResidencyBudgetPolicy(fixedBytes: 400)
        )

        XCTAssertFalse(outcome.cancelled)
        XCTAssertEqual(mock.calls, ["load:A", "load:B"])
        XCTAssertEqual(controller.residentGroupIDs, ["CORE", "A", "B"])
        XCTAssertEqual(controller.state, .clean)
        assertInvariants(controller)
    }

    func testFailFastOnRequiredOverflowBeforeAnyTransfer() {
        let mock = MockResidencyMaterializer()
        let controller = ResidencyController(inventory: inventory(), materializer: mock)

        XCTAssertThrowsError(
            try controller.admit(
                requiredGroupIDs: ["CORE", "A", "B"],
                budget: ResidencyBudgetPolicy(fixedBytes: 200)
            )
        ) { error in
            guard case ResidencyControllerError.requiredOverflow(let plan) = error else {
                return XCTFail("expected requiredOverflow")
            }
            XCTAssertFalse(plan.fitsBudget)
            XCTAssertEqual(plan.overflowGroupIDs, ["CORE", "A", "B"])
        }

        // Zero transfers: fail-fast happens before the materializer runs.
        XCTAssertTrue(mock.calls.isEmpty)
        XCTAssertTrue(controller.transferLog.count == 0)
        XCTAssertEqual(controller.residentGroupIDs, ["CORE"])
        XCTAssertEqual(controller.state, .clean)
        assertInvariants(controller)
    }

    func testLoadFailureCommitsPriorGroupsOnlyAndStaysClean() {
        let mock = MockResidencyMaterializer()
        mock.failLoadsOf = ["B"]
        let controller = ResidencyController(inventory: inventory(), materializer: mock)

        XCTAssertThrowsError(
            try controller.admit(
                requiredGroupIDs: ["CORE", "A", "B"],
                budget: ResidencyBudgetPolicy(fixedBytes: 400)
            )
        ) { error in
            XCTAssertEqual(error as? ResidencyControllerError, .loadFailed(groupID: "B"))
        }

        // Per-group commit: A is resident, B is not; state stays CLEAN (R3.12).
        XCTAssertEqual(controller.residentGroupIDs, ["CORE", "A"])
        XCTAssertEqual(controller.state, .clean)
        assertInvariants(controller)
    }

    func testEvictFailureEntersDirtyAndRejectsFurtherAdmission() throws {
        let mock = MockResidencyMaterializer()
        let controller = ResidencyController(inventory: inventory(), materializer: mock)

        _ = try controller.admit(
            requiredGroupIDs: ["CORE", "A"],
            budget: ResidencyBudgetPolicy(fixedBytes: 400)
        )

        // A release failure means the group is STILL resident — the
        // bookkeeping must keep it and the controller must go DIRTY (R3.13).
        mock.failReleasesOf = ["A"]
        XCTAssertThrowsError(
            try controller.admit(
                requiredGroupIDs: ["CORE"],
                budget: ResidencyBudgetPolicy(fixedBytes: 400)
            )
        ) { error in
            XCTAssertEqual(error as? ResidencyControllerError, .evictFailed(groupID: "A"))
        }

        XCTAssertEqual(controller.state, .dirty)
        XCTAssertEqual(controller.residentGroupIDs, ["CORE", "A"])
        assertInvariants(controller)

        XCTAssertThrowsError(
            try controller.admit(
                requiredGroupIDs: ["CORE", "A"],
                budget: ResidencyBudgetPolicy(fixedBytes: 400)
            )
        ) { error in
            XCTAssertEqual(error as? ResidencyControllerError, .dirty)
        }
    }

    func testCancellationCommitsCompletedGroupsOnly() throws {
        let mock = MockResidencyMaterializer()
        let controller = ResidencyController(inventory: inventory(), materializer: mock)

        let counter = CheckCounter()
        let token = ResidencyCancellationToken { counter.increment() > 1 }

        let outcome = try controller.admit(
            requiredGroupIDs: ["CORE", "A", "B"],
            budget: ResidencyBudgetPolicy(fixedBytes: 400),
            cancellationToken: token
        )

        XCTAssertTrue(outcome.cancelled)
        XCTAssertEqual(mock.calls, ["load:A"])
        XCTAssertEqual(controller.residentGroupIDs, ["CORE", "A"])
        XCTAssertEqual(controller.state, .clean)
        assertInvariants(controller)
    }

    func testReconcileMismatchEntersDirtyAndRecoveryRestores() throws {
        let mock = MockResidencyMaterializer()
        let controller = ResidencyController(inventory: inventory(), materializer: mock)
        _ = try controller.admit(
            requiredGroupIDs: ["CORE", "A"],
            budget: ResidencyBudgetPolicy(fixedBytes: 400)
        )

        // residentBytes = 200; a 10 MiB deviation is far beyond ε.
        let matched = controller.reconcile(
            observedIdleBytes: controller.residentBytes + 10 * 1024 * 1024,
            epsilonBytes: 5 * 1024 * 1024
        )
        XCTAssertFalse(matched)
        XCTAssertEqual(controller.state, .dirty)

        XCTAssertThrowsError(
            try controller.admit(
                requiredGroupIDs: ["CORE", "A"],
                budget: ResidencyBudgetPolicy(fixedBytes: 400)
            )
        ) { error in
            XCTAssertEqual(error as? ResidencyControllerError, .dirty)
        }

        controller.recover()
        XCTAssertEqual(controller.state, .clean)
        XCTAssertEqual(controller.residentGroupIDs, ["CORE", "A"])
        assertInvariants(controller)

        let matchedAgain = controller.reconcile(
            observedIdleBytes: controller.residentBytes,
            epsilonBytes: 5 * 1024 * 1024
        )
        XCTAssertTrue(matchedAgain)
        XCTAssertEqual(controller.state, .clean)
    }

    func testLogReplayEquivalenceHoldsAcrossMixedOperationSequence() throws {
        let mock = MockResidencyMaterializer()
        let controller = ResidencyController(inventory: inventory(), materializer: mock)

        _ = try controller.admit(
            requiredGroupIDs: ["CORE", "A", "B"],
            budget: ResidencyBudgetPolicy(fixedBytes: 400)
        )
        assertInvariants(controller)

        _ = try controller.admit(
            requiredGroupIDs: ["CORE"],
            budget: ResidencyBudgetPolicy(fixedBytes: 400)
        )
        assertInvariants(controller)

        // CORE-only retention evicts A and B.
        XCTAssertEqual(controller.residentGroupIDs, ["CORE"])
        XCTAssertEqual(controller.transferLog.count, 4) // 2 loads + 2 evicts

        _ = try controller.admit(
            requiredGroupIDs: ["CORE", "C"],
            budget: ResidencyBudgetPolicy(fixedBytes: 400)
        )
        assertInvariants(controller)
        XCTAssertEqual(controller.residentGroupIDs, ["CORE", "C"])
    }
}
