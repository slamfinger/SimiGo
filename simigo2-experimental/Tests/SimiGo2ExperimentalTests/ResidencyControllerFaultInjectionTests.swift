import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

/// L3 fault injection (verification design catalog F1–F8) against the
/// production ResidencyController with a mock materializer. F6/F7/F8
/// verify the controller's contractual responses only — no new
/// Memory Pressure / Budget / Concurrency entities.
final class ResidencyControllerFaultInjectionTests: XCTestCase {
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

    // F1 — load fails mid-plan: prior groups committed, failed group not,
    // state stays CLEAN, retry completes.
    func testF1LoadMidFailureCommitsPriorGroupsAndRetries() throws {
        let mock = MockResidencyMaterializer()
        let controller = ResidencyController(inventory: inventory(), materializer: mock)
        mock.failLoadsOf = ["C"]

        XCTAssertThrowsError(
            try controller.admit(
                requiredGroupIDs: ["CORE", "A", "B", "C"],
                budget: ResidencyBudgetPolicy(fixedBytes: 400)
            )
        ) { error in
            XCTAssertEqual(error as? ResidencyControllerError, .loadFailed(groupID: "C"))
        }

        XCTAssertEqual(controller.residentGroupIDs, ["CORE", "A", "B"])
        XCTAssertEqual(controller.state, .clean)
        assertInvariants(controller)

        // Retry without the fault completes the request.
        mock.failLoadsOf = []
        _ = try controller.admit(
            requiredGroupIDs: ["CORE", "A", "B", "C"],
            budget: ResidencyBudgetPolicy(fixedBytes: 400)
        )
        XCTAssertEqual(controller.residentGroupIDs, ["CORE", "A", "B", "C"])
        assertInvariants(controller)
    }

    // F2 — evict failure: the group stays resident, controller goes DIRTY,
    // admissions are refused until recovery.
    func testF2EvictFailureEntersDirtyAndBlocksAdmission() throws {
        let mock = MockResidencyMaterializer()
        let controller = ResidencyController(inventory: inventory(), materializer: mock)
        _ = try controller.admit(
            requiredGroupIDs: ["CORE", "A", "B"],
            budget: ResidencyBudgetPolicy(fixedBytes: 400)
        )

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
        XCTAssertEqual(controller.residentGroupIDs, ["CORE", "A", "B"])
        assertInvariants(controller)

        controller.recover()
        XCTAssertEqual(controller.state, .clean)

        // Clear the injected fault, then the re-admission succeeds.
        mock.failReleasesOf = []
        _ = try controller.admit(
            requiredGroupIDs: ["CORE"],
            budget: ResidencyBudgetPolicy(fixedBytes: 400)
        )
        XCTAssertEqual(controller.residentGroupIDs, ["CORE"])
        assertInvariants(controller)
    }

    // F3 — cancellation during load: committed groups stay, state CLEAN.
    func testF3CancellationDuringLoadKeepsCommittedGroupsOnly() throws {
        let mock = MockResidencyMaterializer()
        let controller = ResidencyController(inventory: inventory(), materializer: mock)

        let counter = CheckCounter()
        let token = ResidencyCancellationToken { counter.increment() > 1 }

        let outcome = try controller.admit(
            requiredGroupIDs: ["CORE", "A", "B", "C"],
            budget: ResidencyBudgetPolicy(fixedBytes: 400),
            cancellationToken: token
        )

        XCTAssertTrue(outcome.cancelled)
        XCTAssertEqual(controller.residentGroupIDs, ["CORE", "A"])
        XCTAssertEqual(controller.state, .clean)
        assertInvariants(controller)

        // After cancellation the next request plans against the true state.
        _ = try controller.admit(
            requiredGroupIDs: ["CORE", "A", "B", "C"],
            budget: ResidencyBudgetPolicy(fixedBytes: 400)
        )
        XCTAssertEqual(controller.residentGroupIDs, ["CORE", "A", "B", "C"])
        assertInvariants(controller)
    }

    // F4 — cancellation during eviction: completes the current group,
    // skips the remainder at the group boundary, state CLEAN (R3.17's
    // "complete or DIRTY" applies per group; none is half-applied).
    func testF4CancellationDuringEvictionSkipsRemainderAtGroupBoundary() throws {
        let mock = MockResidencyMaterializer()
        let controller = ResidencyController(inventory: inventory(), materializer: mock)
        _ = try controller.admit(
            requiredGroupIDs: ["CORE", "A", "B"],
            budget: ResidencyBudgetPolicy(fixedBytes: 400)
        )

        // This admission evicts A and B; the token fires before the second.
        let counter = CheckCounter()
        let token = ResidencyCancellationToken { counter.increment() > 1 }

        let outcome = try controller.admit(
            requiredGroupIDs: ["CORE"],
            budget: ResidencyBudgetPolicy(fixedBytes: 400),
            cancellationToken: token
        )

        XCTAssertTrue(outcome.cancelled)
        // Evictions run in sorted order: A was released first, so B is what
        // remains after the boundary cancellation.
        XCTAssertEqual(controller.residentGroupIDs, ["CORE", "B"])
        XCTAssertEqual(controller.state, .clean)
        assertInvariants(controller)
    }

    // F5 — audit deviation beyond ε enters DIRTY; recovery restores.
    func testF5AuditDeviationBeyondEpsilonEntersDirty() throws {
        let mock = MockResidencyMaterializer()
        let controller = ResidencyController(inventory: inventory(), materializer: mock)
        _ = try controller.admit(
            requiredGroupIDs: ["CORE", "A"],
            budget: ResidencyBudgetPolicy(fixedBytes: 400)
        )

        let matched = controller.reconcile(
            observedIdleBytes: controller.residentBytes + 64 * 1024 * 1024,
            epsilonBytes: 5 * 1024 * 1024
        )
        XCTAssertFalse(matched)
        XCTAssertEqual(controller.state, .dirty)

        controller.recover()
        XCTAssertEqual(controller.state, .clean)
        assertInvariants(controller)
    }

    // F6 — host budget shrink mid-run: the next admission with a shrunken
    // budget fail-fasts on required overflow with zero transfers; the
    // in-flight (already completed) state is unaffected.
    func testF6BudgetShrinkMidRunFailsFastOnNextOverflow() throws {
        let mock = MockResidencyMaterializer()
        let controller = ResidencyController(inventory: inventory(), materializer: mock)
        _ = try controller.admit(
            requiredGroupIDs: ["CORE", "A"],
            budget: ResidencyBudgetPolicy(fixedBytes: 400)
        )

        let logCountBefore = controller.transferLog.count
        XCTAssertThrowsError(
            try controller.admit(
                requiredGroupIDs: ["CORE", "A", "B", "C"],
                budget: ResidencyBudgetPolicy(fixedBytes: 200)
            )
        ) { error in
            guard case ResidencyControllerError.requiredOverflow = error else {
                return XCTFail("expected requiredOverflow after budget shrink")
            }
        }

        XCTAssertEqual(controller.transferLog.count, logCountBefore)
        XCTAssertEqual(controller.residentGroupIDs, ["CORE", "A"])
        XCTAssertEqual(controller.state, .clean)
        assertInvariants(controller)

        // A request that fits the shrunken budget still succeeds.
        _ = try controller.admit(
            requiredGroupIDs: ["CORE", "B"],
            budget: ResidencyBudgetPolicy(fixedBytes: 200)
        )
        XCTAssertEqual(controller.residentGroupIDs, ["CORE", "B"])
        assertInvariants(controller)
    }

    // F7 — memory-pressure event: proactive shrink, largest-byte-first
    // victims, every eviction logged, core floor respected, no speculative
    // reload afterwards.
    func testF7MemoryPressureShrinksLargestFirstWithoutSpeculativeReload() throws {
        let mock = MockResidencyMaterializer()
        let controller = ResidencyController(inventory: inventory(), materializer: mock)
        _ = try controller.admit(
            requiredGroupIDs: ["CORE", "A", "B", "C"],
            budget: ResidencyBudgetPolicy(fixedBytes: 400)
        )

        let logCountBefore = controller.transferLog.count
        let evicted = try controller.respondToMemoryPressure(targetBytes: 200)

        // All optional groups are 100 bytes; ties break by group ID.
        XCTAssertEqual(evicted, ["A", "B"])
        XCTAssertEqual(controller.residentGroupIDs, ["CORE", "C"])
        XCTAssertEqual(controller.transferLog.count, logCountBefore + 2)
        XCTAssertEqual(controller.state, .clean)
        assertInvariants(controller)

        // Shrink to the core floor: every optional group goes, no error.
        let floorEvicted = try controller.respondToMemoryPressure(targetBytes: 50)
        XCTAssertEqual(floorEvicted, ["C"])
        XCTAssertEqual(controller.residentGroupIDs, ["CORE"])
        assertInvariants(controller)

        // No speculative re-materialization (R3.24): the only load calls
        // ever issued are the three original admissions — pressure events
        // added evictions only.
        XCTAssertEqual(mock.calls.filter { $0.hasPrefix("load:") }.count, 3)
        XCTAssertEqual(mock.calls.filter { $0.hasPrefix("release:") }.count, 3)
    }

    // F7b — pressure is refused while DIRTY (R3.6).
    func testF7bPressureRefusedWhileDirty() throws {
        let mock = MockResidencyMaterializer()
        let controller = ResidencyController(inventory: inventory(), materializer: mock)
        _ = try controller.admit(
            requiredGroupIDs: ["CORE", "A"],
            budget: ResidencyBudgetPolicy(fixedBytes: 400)
        )

        controller.reconcile(
            observedIdleBytes: controller.residentBytes + 64 * 1024 * 1024,
            epsilonBytes: 5 * 1024 * 1024
        )
        XCTAssertEqual(controller.state, .dirty)

        XCTAssertThrowsError(
            try controller.respondToMemoryPressure(targetBytes: 100)
        ) { error in
            XCTAssertEqual(error as? ResidencyControllerError, .dirty)
        }
    }

    // F8 — concurrent admission serializes through the single writer.
    // Both requests hold residency windows (R3.20): each required set is
    // jointly resident for the whole window, neither admission evicts the
    // other's groups, and INV-1 holds across the serialized stream.
    func testF8ConcurrentAdmissionSerializesThroughSingleWriter() throws {
        let mock = MockResidencyMaterializer()
        let controller = ResidencyController(inventory: inventory(), materializer: mock)

        let startGate = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "l3-f8", attributes: .concurrent)
        final class ErrorBox: @unchecked Sendable {
            var error: Error?
        }
        final class IDBox: @unchecked Sendable {
            var id: UUID?
        }
        let box1 = ErrorBox()
        let box2 = ErrorBox()
        let id1 = IDBox()
        let id2 = IDBox()

        group.enter()
        queue.async {
            startGate.wait()
            defer { group.leave() }
            do {
                let outcome = try controller.admit(
                    requiredGroupIDs: ["CORE", "A"],
                    budget: ResidencyBudgetPolicy(fixedBytes: 400),
                    holdsResidencyWindow: true
                )
                id1.id = outcome.requestID
            } catch {
                box1.error = error
            }
        }
        group.enter()
        queue.async {
            startGate.wait()
            defer { group.leave() }
            do {
                let outcome = try controller.admit(
                    requiredGroupIDs: ["CORE", "B"],
                    budget: ResidencyBudgetPolicy(fixedBytes: 400),
                    holdsResidencyWindow: true
                )
                id2.id = outcome.requestID
            } catch {
                box2.error = error
            }
        }

        startGate.signal()
        startGate.signal()
        group.wait()

        XCTAssertNil(box1.error)
        XCTAssertNil(box2.error)
        XCTAssertNotNil(id1.id)
        XCTAssertNotNil(id2.id)
        XCTAssertEqual(controller.state, .clean)
        XCTAssertEqual(controller.activeResidencyWindowCount, 2)

        // Joint residency (R3.20): neither window lost its group, and no
        // eviction was needed to serve the second admission.
        XCTAssertTrue(controller.residentGroupIDs.contains("A"))
        XCTAssertTrue(controller.residentGroupIDs.contains("B"))
        assertInvariants(controller)

        // Closing a window makes its groups reclaimable at the NEXT
        // admission; closing alone performs no transfers.
        let logBefore = controller.transferLog.count
        controller.closeResidencyWindow(id1.id!)
        XCTAssertEqual(controller.transferLog.count, logBefore)

        _ = try controller.admit(
            requiredGroupIDs: ["CORE", "B"],
            budget: ResidencyBudgetPolicy(fixedBytes: 400)
        )
        XCTAssertEqual(controller.activeResidencyWindowCount, 1)
        XCTAssertFalse(controller.residentGroupIDs.contains("A"))
        XCTAssertTrue(controller.residentGroupIDs.contains("B"))
        assertInvariants(controller)
    }
}
