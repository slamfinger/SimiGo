import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

/// E3 — ExecutionContinuityCoordinator + MLXExecutionStateBackend
/// (prefix-recompute representation strategy; the binding logic itself is
/// pure data — no MLX execution in these tests). Sovereignty assertion:
/// backend operations can never alter a handle's identity, lineage, or
/// continuation.
final class ExecutionContinuityCoordinatorTests: XCTestCase {
    private var backend: MLXExecutionStateBackend!
    private var coordinator: ExecutionContinuityCoordinator!

    override func setUpWithError() throws {
        backend = MLXExecutionStateBackend()
        coordinator = ExecutionContinuityCoordinator(backend: backend)
    }

    private let coreIDs = Set<String>(["CORE_NON_SWITCH"])

    private func bind(
        _ id: String,
        position: Int64,
        prompt: [Int],
        generated: [Int]
    ) async throws {
        try await coordinator.bindRepresentation(
            executionID: ExecutionID(id),
            position: ExecutionPosition(position),
            payload: MLXPrefixPayload(tokenPrefix: prompt + generated)
        )
    }

    func testBindAndCaptureRoundTrip() async throws {
        _ = try await coordinator.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        try await bind("A", position: 0, prompt: [1, 2, 3], generated: [4])

        let handle = try XCTUnwrap(coordinator.handle(ExecutionID("A")))
        let representation = try await backend.captureRepresentation(for: handle)

        XCTAssertEqual(representation.executionID, ExecutionID("A"))
        XCTAssertEqual(representation.position, ExecutionPosition(0))
        let payload = try XCTUnwrap(representation.payload as? MLXPrefixPayload)
        XCTAssertEqual(payload.tokenPrefix, [1, 2, 3, 4])
    }

    func testCaptureRejectsPositionMismatch() async throws {
        _ = try await coordinator.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        try await bind("A", position: 0, prompt: [1, 2], generated: [3])

        // The logical position advanced without a rebind: capture must
        // refuse (representation can never silently redefine position).
        let stale = ExecutionStateHandle(
            id: ExecutionID("A"),
            lineage: ExecutionLineage(root: ExecutionID("A")),
            position: ExecutionPosition(5),
            continuation: ExecutionContinuation(nextInput: "x", continuationID: "x"),
            lifecycle: .active
        )

        await XCTAssertThrowsErrorAsync {
            try await backend.captureRepresentation(for: stale)
        } errorHandler: { error in
            guard case ExecutionStateBackendError.representationPositionMismatch(
                executionID: let id, bound: let bound, logical: let logical
            ) = error else {
                return XCTFail("expected representationPositionMismatch")
            }
            XCTAssertEqual(id, ExecutionID("A"))
            XCTAssertEqual(bound, ExecutionPosition(0))
            XCTAssertEqual(logical, ExecutionPosition(5))
        }
    }

    func testForkDerivesChildRepresentationFromParent() async throws {
        let parent = try await coordinator.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        try await bind("A", position: 0, prompt: [1, 2, 3], generated: [4, 5])

        let child = try await coordinator.fork(
            ExecutionForkRequest(
                parent: parent,
                childID: ExecutionID("B"),
                childPosition: ExecutionPosition(0),
                childContinuation: ExecutionContinuation(nextInput: "B-next", continuationID: "B-cont")
            )
        )

        // The child's physical representation derives from the parent's.
        let childRep = try await backend.captureRepresentation(for: child)
        let payload = try XCTUnwrap(childRep.payload as? MLXPrefixPayload)
        XCTAssertEqual(payload.tokenPrefix, [1, 2, 3, 4, 5])
        XCTAssertEqual(childRep.position, ExecutionPosition(0))

        // Sovereignty: derivation did not alter the parent handle or the
        // child's logical identity/lineage/continuation.
        let parentAfter = try XCTUnwrap(coordinator.handle(ExecutionID("A")))
        XCTAssertEqual(parentAfter.continuation.nextInput, "A-next")
        XCTAssertEqual(child.lineage.parent, ExecutionID("A"))
        XCTAssertEqual(child.continuation.nextInput, "B-next")
    }

    func testForkWithoutParentBindingIsLazy() async throws {
        // The parent was never bound (no generation yet): the logical fork
        // completes; the child binds lazily after its first generation.
        let parent = try await coordinator.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )

        let child = try await coordinator.fork(
            ExecutionForkRequest(
                parent: parent,
                childID: ExecutionID("B"),
                childPosition: ExecutionPosition(0),
                childContinuation: ExecutionContinuation(nextInput: "B-next", continuationID: "B-cont")
            )
        )

        XCTAssertEqual(child.id, ExecutionID("B"))
        await XCTAssertThrowsErrorAsync {
            try await backend.captureRepresentation(for: child)
        } errorHandler: { error in
            guard case ExecutionStateBackendError.noBoundRepresentation(let id) = error else {
                return XCTFail("expected noBoundRepresentation")
            }
            XCTAssertEqual(id, ExecutionID("B"))
        }
    }

    func testRestoreBindsTheCapturedRepresentationAtTheTargetPosition() async throws {
        let state = try await coordinator.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        try await bind("A", position: 0, prompt: [1, 2, 3], generated: [4])
        let captured = try await backend.captureRepresentation(
            for: try XCTUnwrap(coordinator.handle(ExecutionID("A")))
        )

        // Continue past the captured position, then restore to it.
        _ = try await coordinator.continueExecution(
            try XCTUnwrap(coordinator.handle(ExecutionID("A"))),
            continuation: ExecutionContinuation(nextInput: "A-next-2", continuationID: "A-cont-2")
        )
        try await bind("A", position: 1, prompt: [1, 2, 3, 4], generated: [9])

        let restored = try await coordinator.restore(
            try XCTUnwrap(coordinator.handle(ExecutionID("A"))),
            request: ExecutionRestoreRequest(
                targetPosition: ExecutionPosition(0),
                continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
            )
        )

        XCTAssertEqual(restored.id, ExecutionID("A"))
        XCTAssertEqual(restored.lineage, state.lineage)
        XCTAssertEqual(restored.position, ExecutionPosition(0))
        XCTAssertEqual(restored.lifecycle, .restored)

        // The backend binding is back at the restored representation.
        let rep = try await backend.captureRepresentation(
            for: try XCTUnwrap(coordinator.handle(ExecutionID("A")))
        )
        let payload = try XCTUnwrap(rep.payload as? MLXPrefixPayload)
        XCTAssertEqual(payload.tokenPrefix, [1, 2, 3, 4])
    }

    func testRestoreWithoutCapturedRepresentationFails() async throws {
        _ = try await coordinator.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        _ = try await coordinator.continueExecution(
            try XCTUnwrap(coordinator.handle(ExecutionID("A"))),
            continuation: ExecutionContinuation(nextInput: "A-next-2", continuationID: "A-cont-2")
        )

        // Nothing was ever captured at position 99.
        await XCTAssertThrowsErrorAsync {
            try await coordinator.restore(
                try XCTUnwrap(coordinator.handle(ExecutionID("A"))),
                request: ExecutionRestoreRequest(
                    targetPosition: ExecutionPosition(99),
                    continuation: ExecutionContinuation(nextInput: "x", continuationID: "x")
                )
            )
        } errorHandler: { error in
            guard case ExecutionContinuityCoordinator.CoordinatorError
                .noRepresentationAtPosition(executionID: let id, position: let pos) = error
            else {
                return XCTFail("expected noRepresentationAtPosition")
            }
            XCTAssertEqual(id, ExecutionID("A"))
            XCTAssertEqual(pos, ExecutionPosition(99))
        }
    }

    func testDiscardReleasesRepresentation() async throws {
        _ = try await coordinator.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        try await bind("A", position: 0, prompt: [1], generated: [2])
        _ = try await coordinator.discard(
            try XCTUnwrap(coordinator.handle(ExecutionID("A")))
        )

        // The logical record survives; the representation is gone.
        XCTAssertEqual(
            try XCTUnwrap(coordinator.handle(ExecutionID("A"))).lifecycle,
            .discarded
        )
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
    }

    func testOneAuthoritativeLifecycleRecordPerTransition() async throws {
        let parent = try await coordinator.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        try await bind("A", position: 0, prompt: [1], generated: [2])
        let child = try await coordinator.fork(
            ExecutionForkRequest(
                parent: parent,
                childID: ExecutionID("B"),
                childPosition: ExecutionPosition(0),
                childContinuation: ExecutionContinuation(nextInput: "B-next", continuationID: "B-cont")
            )
        )
        try await bind("B", position: 0, prompt: [1], generated: [3])
        _ = try await coordinator.continueExecution(
            child,
            continuation: ExecutionContinuation(nextInput: "B-next-2", continuationID: "B-cont-2")
        )
        try await bind("B", position: 1, prompt: [1], generated: [3, 4])

        // Two lifecycle records (create, fork) + one continue; binding calls
        // are NOT lifecycle transitions and create none.
        XCTAssertEqual(coordinator.recordCount, 3)
        XCTAssertEqual(
            coordinator.recordsSnapshot.map(\.operation),
            [.created, .forked, .continued]
        )
        XCTAssertEqual(coordinator.recordsSnapshot[1].relatedID, ExecutionID("A"))
    }
}

/// Async do/catch assertion helper for this test file.
func XCTAssertThrowsErrorAsync<T>(
    _ expression: () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("expected error", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
