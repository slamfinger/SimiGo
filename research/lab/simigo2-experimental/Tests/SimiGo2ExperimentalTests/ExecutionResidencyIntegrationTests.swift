import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

/// E4 — Continuity + Residency integration.
///
/// Composes the two validated capabilities and proves the integration
/// invariant: changing the PHYSICAL resource state (group eviction,
/// re-materialization, representation release) does not change the logical
/// EXECUTION STATE (identity, lineage, position semantics, continuation).
///
/// The answer to "an Execution State was evicted — is it still the same
/// Execution State?" is YES, with engineering evidence.
final class ExecutionResidencyIntegrationTests: XCTestCase {
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

    private func assertResidencyInvariants(
        _ controller: ResidencyController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            controller.auditReplay().residentGroupIDs,
            controller.residentGroupIDs,
            "residency INV-1 violated",
            file: file,
            line: line
        )
    }

    func testEvictionAndRematerializationPreserveExecutionState() async throws {
        let inventory = inventory()
        let allGroups = Set(inventory.groups.map(\.id))
        let coreIDs = Set(inventory.groups.filter(\.alwaysResident).map(\.id))

        // Residency side: controller + mock materializer.
        let mock = MockResidencyMaterializer()
        let residency = ResidencyController(inventory: inventory, materializer: mock)

        // Continuity side: coordinator + prefix representation backend.
        let backend = MLXExecutionStateBackend()
        let coordinator = ExecutionContinuityCoordinator(backend: backend)

        // 1. CREATE — the logical execution state comes into existence.
        let created = try await coordinator.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        let identityBefore = created.id
        let lineageBefore = created.lineage

        // 2. GENERATE — the request executes; the residency controller makes
        // all groups resident, and the representation (token prefix) is
        // bound at position 0.
        _ = try await residency.admit(
            requiredGroupIDs: allGroups,
            budget: ResidencyBudgetPolicy(fixedBytes: inventory.totalByteCount)
        )
        try await coordinator.bindRepresentation(
            executionID: ExecutionID("A"),
            position: ExecutionPosition(0),
            payload: MLXPrefixPayload(tokenPrefix: [11, 12, 13, 14])
        )
        XCTAssertEqual(residency.residentGroupIDs, allGroups)

        // Checkpoint: capture the representation at position 0. This
        // snapshot survives everything that happens to residency below.
        let checkpoint = try await backend.captureRepresentation(
            for: try XCTUnwrap(coordinator.handle(ExecutionID("A")))
        )

        // 3. RESIDENT — full residency confirmed.
        XCTAssertTrue(residency.residentGroupIDs.contains("A"))

        // 4. EVICT — pressure shrinks residency to the core floor, and the
        // execution's live representation is released as well. Both sides
        // of the physical state are now gone; the logical state must not
        // notice.
        _ = try await residency.respondToMemoryPressure(
            targetBytes: coreIDs.reduce(Int64(0)) { partial, id in
                partial + (inventory.groups.first(where: { $0.id == id })?.byteCount ?? 0)
            }
        )
        XCTAssertEqual(residency.residentGroupIDs, coreIDs)

        let liveRepresentation = try await backend.captureRepresentation(
            for: try XCTUnwrap(coordinator.handle(ExecutionID("A")))
        )
        try await backend.releaseRepresentation(liveRepresentation)
        // The execution's physical representation is gone:
        await XCTAssertThrowsErrorAsync {
            try await backend.captureRepresentation(
                for: try XCTUnwrap(coordinator.handle(ExecutionID("A")))
            )
        } errorHandler: { error in
            guard case ExecutionStateBackendError.noBoundRepresentation(let id) = error else {
                return XCTFail("expected noBoundRepresentation")
            }
            XCTAssertEqual(id, ExecutionID("A"))
        }

        // The logical execution state did not move:
        XCTAssertEqual(
            try XCTUnwrap(coordinator.handle(ExecutionID("A"))).id,
            identityBefore
        )
        XCTAssertEqual(
            try XCTUnwrap(coordinator.handle(ExecutionID("A"))).lineage,
            lineageBefore
        )
        XCTAssertEqual(
            try XCTUnwrap(coordinator.handle(ExecutionID("A"))).position,
            ExecutionPosition(0)
        )
        XCTAssertEqual(
            try XCTUnwrap(coordinator.handle(ExecutionID("A"))).continuation,
            ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        assertResidencyInvariants(residency)

        // 5. RE-MATERIALIZE — residency restores all groups (the mock
        // materializer commits the loads).
        _ = try await residency.admit(
            requiredGroupIDs: allGroups,
            budget: ResidencyBudgetPolicy(fixedBytes: inventory.totalByteCount)
        )
        XCTAssertEqual(residency.residentGroupIDs, allGroups)

        // 6. RESTORE + REATTACH — the logical state is restored from the
        // checkpoint representation taken BEFORE the eviction, and
        // re-activated. Identity/lineage unchanged; position/continuation
        // per the restore request.
        let restored = try await coordinator.restore(
            try XCTUnwrap(coordinator.handle(ExecutionID("A"))),
            request: ExecutionRestoreRequest(
                targetPosition: ExecutionPosition(0),
                continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
            )
        )
        XCTAssertEqual(restored.id, identityBefore)
        XCTAssertEqual(restored.lineage, lineageBefore)
        XCTAssertEqual(restored.position, ExecutionPosition(0))
        XCTAssertEqual(restored.lifecycle, .restored)

        let reattached = try await coordinator.reattach(restored)
        XCTAssertEqual(reattached.lifecycle, .active)
        XCTAssertEqual(reattached.continuation.nextInput, "A-next")

        // 7. CONTINUE — the execution advances from the restored position
        // on its own timeline, with its identity intact after the whole
        // evict/re-materialize cycle.
        let continued = try await coordinator.continueExecution(
            reattached,
            continuation: ExecutionContinuation(nextInput: "A-next-2", continuationID: "A-cont-2")
        )
        XCTAssertEqual(continued.id, identityBefore)
        XCTAssertEqual(continued.lineage, lineageBefore)
        XCTAssertEqual(continued.position, ExecutionPosition(1))
        XCTAssertEqual(continued.continuation.nextInput, "A-next-2")

        // Final invariants on both sides.
        assertResidencyInvariants(residency)

        // Representation CHANGED (released + re-bound from the checkpoint);
        // Residency CHANGED (full → core → full, two full re-materializations
        // through the mock); Execution State UNCHANGED.
        XCTAssertEqual(mock.calls.filter { $0.hasPrefix("load:") }.count, 6)
        XCTAssertEqual(mock.calls.filter { $0.hasPrefix("release:") }.count, 3)
        XCTAssertEqual(coordinator.recordsSnapshot.count, 4) // create, restore, reattach, continue
    }

    func testResidencyAndContinuityRecordsAreIndependent() async throws {
        let inventory = inventory()
        let allGroups = Set(inventory.groups.map(\.id))
        let mock = MockResidencyMaterializer()
        let residency = ResidencyController(inventory: inventory, materializer: mock)
        let backend = MLXExecutionStateBackend()
        let coordinator = ExecutionContinuityCoordinator(backend: backend)

        _ = try await coordinator.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        let continuityRecordsAfterCreate = coordinator.recordCount
        let residencyLogAfterCreate = residency.transferLog.count

        // Residency operations multiply the residency log and touch zero
        // continuity records.
        _ = try await residency.admit(
            requiredGroupIDs: allGroups,
            budget: ResidencyBudgetPolicy(fixedBytes: inventory.totalByteCount)
        )
        _ = try await residency.respondToMemoryPressure(targetBytes: 100)
        XCTAssertEqual(coordinator.recordCount, continuityRecordsAfterCreate)
        XCTAssertGreaterThan(residency.transferLog.count, residencyLogAfterCreate)

        // A continuity transition appends exactly one continuity record and
        // issues zero residency transfers.
        let residencyLogBefore = residency.transferLog.count
        let residencyCallsBefore = mock.calls.count
        _ = try await coordinator.continueExecution(
            try XCTUnwrap(coordinator.handle(ExecutionID("A"))),
            continuation: ExecutionContinuation(nextInput: "A-next-2", continuationID: "A-cont-2")
        )
        XCTAssertEqual(coordinator.recordCount, continuityRecordsAfterCreate + 1)
        XCTAssertEqual(residency.transferLog.count, residencyLogBefore)
        XCTAssertEqual(mock.calls.count, residencyCallsBefore)
    }

    func testEvictedExecutionStateSurvivesRestoreAndContinues() async throws {
        // Direct answer to the integration question: after the execution's
        // representation AND its residency are fully evicted, the captured
        // checkpoint restores the logical state, which then continues.
        let inventory = inventory()
        let allGroups = Set(inventory.groups.map(\.id))
        let mock = MockResidencyMaterializer()
        let residency = ResidencyController(inventory: inventory, materializer: mock)
        let backend = MLXExecutionStateBackend()
        let coordinator = ExecutionContinuityCoordinator(backend: backend)

        _ = try await coordinator.create(
            id: ExecutionID("E"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "E-next", continuationID: "E-cont")
        )
        _ = try await residency.admit(
            requiredGroupIDs: allGroups,
            budget: ResidencyBudgetPolicy(fixedBytes: inventory.totalByteCount)
        )
        try await coordinator.bindRepresentation(
            executionID: ExecutionID("E"),
            position: ExecutionPosition(0),
            payload: MLXPrefixPayload(tokenPrefix: [7, 8])
        )
        let checkpoint = try await backend.captureRepresentation(
            for: try XCTUnwrap(coordinator.handle(ExecutionID("E")))
        )

        // Full eviction: residency floor + representation release.
        _ = try await residency.respondToMemoryPressure(targetBytes: 100)
        let live = try await backend.captureRepresentation(
            for: try XCTUnwrap(coordinator.handle(ExecutionID("E")))
        )
        try await backend.releaseRepresentation(live)

        // Restore from the checkpoint, reattach, continue.
        let restored = try await coordinator.restore(
            try XCTUnwrap(coordinator.handle(ExecutionID("E"))),
            request: ExecutionRestoreRequest(
                targetPosition: ExecutionPosition(0),
                continuation: ExecutionContinuation(nextInput: "E-next", continuationID: "E-cont")
            )
        )
        try await backend.restoreRepresentation(checkpoint)
        let reattached = try await coordinator.reattach(restored)

        let continued = try await coordinator.continueExecution(
            reattached,
            continuation: ExecutionContinuation(nextInput: "E-next-2", continuationID: "E-cont-2")
        )
        XCTAssertEqual(continued.id, ExecutionID("E"))
        XCTAssertEqual(continued.position, ExecutionPosition(1))
        XCTAssertEqual(continued.lineage.root, ExecutionID("E"))
    }
}
