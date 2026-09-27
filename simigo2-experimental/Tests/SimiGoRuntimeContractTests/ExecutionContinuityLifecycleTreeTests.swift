import XCTest
import SimiGoRuntimeContract
@testable import SimiGoRuntimeContract

/// E2 — lifecycle-tree verification of the E1 Execution Continuity contract
/// against the FakeExecutionBackend. No MLX, no residency, no physical
/// representation. The eight registered constraints are asserted over the
/// full fork/continue/restore/reattach/discard tree.
final class ExecutionContinuityLifecycleTreeTests: XCTestCase {
    private var runtime: FakeExecutionContinuityRuntime!

    override func setUpWithError() throws {
        runtime = FakeExecutionContinuityRuntime()
    }

    private func makeHandle(
        _ id: String,
        position: Int64,
        nextInput: String,
        continuationID: String
    ) -> ExecutionStateHandle {
        ExecutionStateHandle(
            id: ExecutionID(id),
            lineage: ExecutionLineage(root: ExecutionID(id)),
            position: ExecutionPosition(position),
            continuation: ExecutionContinuation(nextInput: nextInput, continuationID: continuationID),
            lifecycle: .attached
        )
    }

    // ① ② — fork keeps the parent's identity and lineage stable; the child's
    // identity is distinct and its lineage traces to the parent.
    func testForkKeepsParentIdentityStableAndChildTraceable() async throws {
        let parent = try await runtime.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        let originalParent = parent

        let child = try await runtime.fork(
            ExecutionForkRequest(
                parent: parent,
                childID: ExecutionID("B"),
                childPosition: ExecutionPosition(0),
                childContinuation: ExecutionContinuation(nextInput: "B-next", continuationID: "B-cont")
            )
        )

        // ① parent identity stable
        let parentAfter = try XCTUnwrap(runtime.handles[ExecutionID("A")])
        XCTAssertEqual(parentAfter.id, originalParent.id)
        XCTAssertEqual(parentAfter.lineage, originalParent.lineage)
        XCTAssertEqual(parentAfter.continuation, originalParent.continuation)

        // ② child identity/lineage distinct and traceable
        XCTAssertEqual(child.id, ExecutionID("B"))
        XCTAssertNotEqual(child.id, parent.id)
        XCTAssertEqual(child.lineage.root, parent.lineage.root)
        XCTAssertEqual(child.lineage.parent, parent.id)
    }

    // ③ — child continuation is independent of the parent's.
    func testChildContinuationIsIndependent() async throws {
        let parent = try await runtime.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        let child = try await runtime.fork(
            ExecutionForkRequest(
                parent: parent,
                childID: ExecutionID("B"),
                childPosition: ExecutionPosition(0),
                childContinuation: ExecutionContinuation(nextInput: "B-next", continuationID: "B-cont")
            )
        )

        // The child continues; the parent's continuation must not move.
        let childAfter = try await runtime.continueExecution(
            child,
            continuation: ExecutionContinuation(nextInput: "B-next-2", continuationID: "B-cont-2")
        )
        XCTAssertEqual(childAfter.continuation.nextInput, "B-next-2")

        let parentAfter = try XCTUnwrap(runtime.handles[ExecutionID("A")])
        XCTAssertEqual(parentAfter.continuation.nextInput, "A-next")
        XCTAssertEqual(parentAfter.continuation.continuationID, "A-cont")
        XCTAssertEqual(parentAfter.position, ExecutionPosition(0))
    }

    // ④ — after discarding the child, the parent continues from ITS OWN
    // continuation, unaffected by the discarded branch.
    func testDiscardChildThenParentContinuesFromOwnContinuation() async throws {
        let parent = try await runtime.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        let child = try await runtime.fork(
            ExecutionForkRequest(
                parent: parent,
                childID: ExecutionID("B"),
                childPosition: ExecutionPosition(0),
                childContinuation: ExecutionContinuation(nextInput: "B-next", continuationID: "B-cont")
            )
        )
        _ = try await runtime.continueExecution(
            child,
            continuation: ExecutionContinuation(nextInput: "B-next-2", continuationID: "B-cont-2")
        )
        try await runtime.discard(child)

        // The discarded branch is terminal.
        do {
            _ = try await runtime.continueExecution(
                child,
                continuation: ExecutionContinuation(nextInput: "zombie", continuationID: "zombie")
            )
            XCTFail("expected discardedExecution")
        } catch let error as FakeExecutionContinuityRuntime.FakeError {
            XCTAssertEqual(error, .discardedExecution(ExecutionID("B")))
        }

        // The parent continues from ITS OWN continuation only.
        let parentAfter = try await runtime.continueExecution(
            parent,
            continuation: ExecutionContinuation(nextInput: "A-next-2", continuationID: "A-cont-2")
        )
        XCTAssertEqual(parentAfter.id, ExecutionID("A"))
        XCTAssertEqual(parentAfter.continuation.nextInput, "A-next-2")
        XCTAssertEqual(parentAfter.position, ExecutionPosition(1))
        XCTAssertNotEqual(parentAfter.continuation.nextInput, "B-next-2")
    }

    // ⑤ — restore returns the LOGICAL execution state (identity/lineage
    // preserved, position/continuation set to the logical target); no
    // tensor or snapshot type exists in the contract.
    func testRestoreReturnsLogicalExecutionState() async throws {
        let state = try await runtime.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        _ = try await runtime.continueExecution(
            state,
            continuation: ExecutionContinuation(nextInput: "A-next-2", continuationID: "A-cont-2")
        )

        let restored = try await runtime.restore(
            state,
            request: ExecutionRestoreRequest(
                targetPosition: ExecutionPosition(0),
                continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
            )
        )

        XCTAssertEqual(restored.id, ExecutionID("A"))
        XCTAssertEqual(restored.lineage, state.lineage)
        XCTAssertEqual(restored.position, ExecutionPosition(0))
        XCTAssertEqual(restored.continuation.nextInput, "A-next")
        XCTAssertEqual(restored.lifecycle, .restored)
    }

    // ⑥ — reattach re-activates without changing the continuation contract.
    func testReattachPreservesContinuationContract() async throws {
        let state = try await runtime.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(3),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        let restored = try await runtime.restore(
            state,
            request: ExecutionRestoreRequest(
                targetPosition: ExecutionPosition(1),
                continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
            )
        )

        let reattached = try await runtime.reattach(restored)

        XCTAssertEqual(reattached.lifecycle, .active)
        XCTAssertEqual(reattached.id, restored.id)
        XCTAssertEqual(reattached.position, restored.position)
        XCTAssertEqual(reattached.continuation, restored.continuation)
    }

    // ⑦ — a representation migration must not touch identity, position, or
    // continuation, and must not create a lifecycle record.
    func testRepresentationMigrationIsOrthogonalToExecutionState() async throws {
        let state = try await runtime.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(2),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        let recordsBefore = runtime.records.count

        try runtime.migrateRepresentation(of: ExecutionID("A"), to: "checkpoint-copy")
        try runtime.migrateRepresentation(of: ExecutionID("A"), to: "re-materialized")

        let after = try XCTUnwrap(runtime.handles[ExecutionID("A")])
        XCTAssertEqual(after.id, state.id)
        XCTAssertEqual(after.position, state.position)
        XCTAssertEqual(after.continuation, state.continuation)
        XCTAssertEqual(after.lifecycle, state.lifecycle)
        XCTAssertEqual(runtime.records.count, recordsBefore)
        XCTAssertEqual(runtime.representationMigrations.count, 2)
        XCTAssertEqual(runtime.representationMigrations.first?.representation, "checkpoint-copy")
    }

    // ⑧ — exactly one authoritative lifecycle record per transition, and
    // the records fully determine the final handles.
    func testLifecycleRecordsAreSingleAuthoritativeHistory() async throws {
        let parent = try await runtime.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        let child = try await runtime.fork(
            ExecutionForkRequest(
                parent: parent,
                childID: ExecutionID("B"),
                childPosition: ExecutionPosition(0),
                childContinuation: ExecutionContinuation(nextInput: "B-next", continuationID: "B-cont")
            )
        )
        _ = try await runtime.continueExecution(
            child,
            continuation: ExecutionContinuation(nextInput: "B-next-2", continuationID: "B-cont-2")
        )
        try await runtime.discard(child)
        _ = try await runtime.continueExecution(
            parent,
            continuation: ExecutionContinuation(nextInput: "A-next-2", continuationID: "A-cont-2")
        )

        // Five lifecycle operations → exactly five records, in order.
        XCTAssertEqual(runtime.records.count, 5)
        XCTAssertEqual(
            runtime.records.map(\.operation),
            [.created, .forked, .continued, .discarded, .continued]
        )
        XCTAssertEqual(runtime.records.map(\.sequence), [1, 2, 3, 4, 5])

        // The fork record names the parent as relatedID.
        XCTAssertEqual(runtime.records[1].operation, .forked)
        XCTAssertEqual(runtime.records[1].relatedID, ExecutionID("A"))

        // The records determine the final handles (authoritative history):
        // replaying the operations' recorded results must match the live
        // registry for every non-discarded execution.
        XCTAssertEqual(
            runtime.handles[ExecutionID("B")]?.lifecycle,
            .discarded
        )
        let finalParent = try XCTUnwrap(runtime.handles[ExecutionID("A")])
        XCTAssertEqual(
            finalParent,
            ExecutionStateHandle(
                id: ExecutionID("A"),
                lineage: ExecutionLineage(root: ExecutionID("A")),
                position: ExecutionPosition(1),
                continuation: ExecutionContinuation(nextInput: "A-next-2", continuationID: "A-cont-2"),
                lifecycle: .active
            )
        )
        // The last record for A describes exactly that final state.
        let lastARecord = runtime.records.last(where: { $0.executionID == ExecutionID("A") })
        XCTAssertEqual(lastARecord?.resultPosition, finalParent.position)
        XCTAssertEqual(lastARecord?.resultContinuation, finalParent.continuation)
    }

    // Full Gate B tree: A continue → fork B → B continue → B restore →
    // B reattach → B discard → A continue, asserting every intermediate
    // state.
    func testFullLifecycleTreeScenario() async throws {
        let parent = try await runtime.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        _ = try await runtime.continueExecution(
            parent,
            continuation: ExecutionContinuation(nextInput: "A-next-2", continuationID: "A-cont-2")
        )
        let child = try await runtime.fork(
            ExecutionForkRequest(
                parent: try XCTUnwrap(runtime.handles[ExecutionID("A")]),
                childID: ExecutionID("B"),
                childPosition: ExecutionPosition(2),
                childContinuation: ExecutionContinuation(nextInput: "B-next", continuationID: "B-cont")
            )
        )
        XCTAssertEqual(child.lineage.parent, ExecutionID("A"))
        XCTAssertEqual(child.position, ExecutionPosition(2))

        _ = try await runtime.continueExecution(
            child,
            continuation: ExecutionContinuation(nextInput: "B-next-2", continuationID: "B-cont-2")
        )
        XCTAssertEqual(
            try XCTUnwrap(runtime.handles[ExecutionID("B")]).position,
            ExecutionPosition(3)
        )

        let restored = try await runtime.restore(
            try XCTUnwrap(runtime.handles[ExecutionID("B")]),
            request: ExecutionRestoreRequest(
                targetPosition: ExecutionPosition(2),
                continuation: ExecutionContinuation(nextInput: "B-next", continuationID: "B-cont")
            )
        )
        XCTAssertEqual(restored.lifecycle, .restored)
        XCTAssertEqual(restored.position, ExecutionPosition(2))

        let reattached = try await runtime.reattach(restored)
        XCTAssertEqual(reattached.lifecycle, .active)
        XCTAssertEqual(reattached.continuation, restored.continuation)

        try await runtime.discard(reattached)
        XCTAssertEqual(
            try XCTUnwrap(runtime.handles[ExecutionID("B")]).lifecycle,
            .discarded
        )

        // Parent continues on its own lineage and position: 0 → 1 → 2 on
        // its OWN timeline — the child's fork position (2) never leaks into
        // the parent's.
        let parentFinal = try await runtime.continueExecution(
            try XCTUnwrap(runtime.handles[ExecutionID("A")]),
            continuation: ExecutionContinuation(nextInput: "A-next-3", continuationID: "A-cont-3")
        )
        XCTAssertEqual(parentFinal.id, ExecutionID("A"))
        XCTAssertEqual(parentFinal.lineage.parent, nil)
        XCTAssertEqual(parentFinal.position, ExecutionPosition(2))
        XCTAssertEqual(parentFinal.continuation.nextInput, "A-next-3")

        assertInvariants()
    }

    // ⑧ auxiliary: unknown/duplicate guards keep one authoritative record
    // per execution — failed operations never create records.
    func testFailedOperationsDoNotCreateLifecycleRecords() async throws {
        let state = try await runtime.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        let countAfterCreate = runtime.records.count

        // Duplicate create fails and leaves no record.
        do {
            _ = try await runtime.create(
                id: ExecutionID("A"),
                position: ExecutionPosition(5),
                continuation: ExecutionContinuation(nextInput: "dup", continuationID: "dup")
            )
            XCTFail("expected duplicateExecution")
        } catch let error as FakeExecutionContinuityRuntime.FakeError {
            XCTAssertEqual(error, .duplicateExecution(ExecutionID("A")))
        }
        // Unknown execution fails and leaves no record.
        do {
            _ = try await runtime.continueExecution(
                makeHandle("NOPE", position: 0, nextInput: "x", continuationID: "x"),
                continuation: ExecutionContinuation(nextInput: "x", continuationID: "x")
            )
            XCTFail("expected unknownExecution")
        } catch let error as FakeExecutionContinuityRuntime.FakeError {
            XCTAssertEqual(error, .unknownExecution(ExecutionID("NOPE")))
        }

        XCTAssertEqual(runtime.records.count, countAfterCreate)
        _ = state
    }

    /// INV-1 analogue for the continuity line: the lifecycle records are the
    /// authoritative history — their per-execution tail must match the live
    /// handles for every non-discarded execution.
    private func assertInvariants(file: StaticString = #filePath, line: UInt = #line) {
        for (id, handle) in runtime.handles {
            let lastRecord = runtime.records.last(where: { $0.executionID == id })
            XCTAssertNotNil(lastRecord, "execution \(id) has no lifecycle record", file: file, line: line)
            if let lastRecord {
                XCTAssertEqual(lastRecord.resultLifecycle, handle.lifecycle, file: file, line: line)
                XCTAssertEqual(lastRecord.resultPosition, handle.position, file: file, line: line)
                XCTAssertEqual(lastRecord.resultContinuation, handle.continuation, file: file, line: line)
            }
            if handle.lifecycle != .discarded {
                XCTAssertFalse(
                    runtime.discardedIDs.contains(id),
                    "non-discarded execution found in discarded set",
                    file: file,
                    line: line
                )
            }
        }
        for id in runtime.discardedIDs {
            XCTAssertEqual(
                runtime.handles[id]?.lifecycle,
                .discarded,
                file: file,
                line: line
            )
        }
    }
}
