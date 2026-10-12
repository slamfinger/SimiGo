import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

/// A controllable backend that suspends the first physical fork derivation.
/// It lets the test hold the coordinator between validation and commit while
/// competing requests attempt to claim the same child ID.
private actor PausingForkBackend: ExecutionStateBackend {
    private var representations: [ExecutionID: ExecutionRepresentation] = [:]
    private var derivations = 0
    private var firstDerivationStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseFirstDerivation: CheckedContinuation<Void, Never>?

    func waitForFirstDerivationToStart() async {
        if firstDerivationStarted { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            startWaiters.append(continuation)
        }
    }

    func resumeFirstDerivation() {
        releaseFirstDerivation?.resume()
        releaseFirstDerivation = nil
    }

    func derivationCallCount() -> Int { derivations }

    func captureRepresentation(for state: ExecutionStateHandle) async throws -> ExecutionRepresentation {
        guard let representation = representations[state.id] else {
            throw ExecutionStateBackendError.noBoundRepresentation(state.id)
        }
        guard representation.position == state.position else {
            throw ExecutionStateBackendError.representationPositionMismatch(
                executionID: state.id,
                bound: representation.position,
                logical: state.position
            )
        }
        return representation
    }

    func deriveRepresentation(
        from parent: ExecutionRepresentation,
        for child: ExecutionStateHandle
    ) async throws -> ExecutionRepresentation {
        derivations += 1
        if derivations == 1 {
            firstDerivationStarted = true
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                releaseFirstDerivation = continuation
            }
        }
        guard parent.position == child.position else {
            throw ExecutionStateBackendError.representationPositionMismatch(
                executionID: child.id,
                bound: parent.position,
                logical: child.position
            )
        }
        let derived = ExecutionRepresentation(
            executionID: child.id,
            position: child.position,
            payload: parent.payload
        )
        representations[child.id] = derived
        return derived
    }

    func restoreRepresentation(_ representation: ExecutionRepresentation) async throws {
        representations[representation.executionID] = representation
    }

    func releaseRepresentation(_ representation: ExecutionRepresentation) async throws {
        guard representations[representation.executionID]?.position == representation.position else {
            return
        }
        representations.removeValue(forKey: representation.executionID)
    }
}

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

    /// Regression: after a restore rewinds the coordinator handle, the
    /// append-only representation history still ENDS at the newer position.
    /// The marker-append failure path in the oversized engine produces this
    /// exact split; a plain coordinator restore reproduces it directly. The
    /// oversized backend has no derive-position guard, so the old blind
    /// `.last` selection silently bound a position-1 prefix onto a
    /// position-0 child.
    func testForkAfterRestoreUsesRepresentationMatchingForkedPosition() async throws {
        let backend = OversizedSegmentedStateBackend(releaseAll: {})
        let coordinator = ExecutionContinuityCoordinator(backend: backend)
        let state = try await coordinator.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        backend.bind(executionID: state.id, position: state.position, prefix: [1, 2, 3])
        try await coordinator.bindRepresentation(
            executionID: state.id,
            position: state.position,
            payload: OversizedPrefixPayload(tokenPrefix: [1, 2, 3])
        )
        let advanced = try await coordinator.continueExecution(
            state,
            continuation: ExecutionContinuation(nextInput: "A-next-2", continuationID: "A-cont-2")
        )
        backend.bind(executionID: advanced.id, position: advanced.position, prefix: [1, 2, 3, 4, 5])
        try await coordinator.bindRepresentation(
            executionID: advanced.id,
            position: advanced.position,
            payload: OversizedPrefixPayload(tokenPrefix: [1, 2, 3, 4, 5])
        )

        // Restore succeeds: coordinator handle moves to position 0 while
        // history.last stays at the position-1 representation.
        let restored = try await coordinator.restore(
            advanced,
            request: ExecutionRestoreRequest(
                targetPosition: ExecutionPosition(0),
                continuation: ExecutionContinuation(nextInput: "A-rewind", continuationID: "A-cont-r")
            )
        )
        XCTAssertEqual(restored.position, ExecutionPosition(0))

        // Fork the coordinator's CURRENT restored handle at the target
        // position: the child must derive from the position-0 representation.
        let child = try await coordinator.fork(
            ExecutionForkRequest(
                parent: restored,
                childID: ExecutionID("B"),
                childPosition: ExecutionPosition(0),
                childContinuation: ExecutionContinuation(nextInput: "B-next", continuationID: "B-cont")
            )
        )
        let rep = try await backend.captureRepresentation(for: child)
        XCTAssertEqual(rep.position, ExecutionPosition(0))
        let payload = try XCTUnwrap(rep.payload as? OversizedPrefixPayload)
        XCTAssertEqual(payload.tokenPrefix, [1, 2, 3])
    }

    /// Regression: when representations exist but none at the forked
    /// position, the fork must fail closed before mutating any child state —
    /// never silently derive from (or lazily skip past) a mismatched
    /// representation.
    func testForkAtPositionWithoutRepresentationFailsClosed() async throws {
        let backend = OversizedSegmentedStateBackend(releaseAll: {})
        let coordinator = ExecutionContinuityCoordinator(backend: backend)
        let state = try await coordinator.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        backend.bind(executionID: state.id, position: state.position, prefix: [1, 2, 3])
        try await coordinator.bindRepresentation(
            executionID: state.id,
            position: state.position,
            payload: OversizedPrefixPayload(tokenPrefix: [1, 2, 3])
        )
        let advanced = try await coordinator.continueExecution(
            state,
            continuation: ExecutionContinuation(nextInput: "A-next-2", continuationID: "A-cont-2")
        )
        let beforeRecords = coordinator.recordCount

        await XCTAssertThrowsErrorAsync {
            try await coordinator.fork(
                ExecutionForkRequest(
                    parent: advanced,
                    childID: ExecutionID("B"),
                    childPosition: advanced.position,
                    childContinuation: ExecutionContinuation(nextInput: "B-next", continuationID: "B-cont")
                )
            )
        } errorHandler: { error in
            guard case ExecutionContinuityCoordinator.CoordinatorError
                .noRepresentationAtPosition(executionID: let id, position: let pos) = error
            else {
                return XCTFail("expected noRepresentationAtPosition")
            }
            XCTAssertEqual(id, ExecutionID("A"))
            XCTAssertEqual(pos, ExecutionPosition(1))
        }

        // Fail closed: no child handle, no fork record, no backend binding.
        XCTAssertNil(coordinator.handle(ExecutionID("B")))
        XCTAssertEqual(coordinator.recordCount, beforeRecords)
        XCTAssertThrowsError(
            try backend.boundPrefixLength(
                executionID: ExecutionID("B"),
                position: ExecutionPosition(1)
            )
        )
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

    /// Concurrent requests for one child identity must linearize at the
    /// coordinator boundary, even while physical derivation is suspended.
    func testConcurrentForkRequestsForSameChildCommitExactlyOnce() async throws {
        let backend = PausingForkBackend()
        let coordinator = ExecutionContinuityCoordinator(backend: backend)
        let parent = try await coordinator.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "A-next", continuationID: "A-cont")
        )
        try await coordinator.bindRepresentation(
            executionID: parent.id,
            position: parent.position,
            payload: MLXPrefixPayload(tokenPrefix: [1, 2, 3])
        )
        let recordsBeforeForks = coordinator.recordCount
        let request = ExecutionForkRequest(
            parent: parent,
            childID: ExecutionID("B"),
            childPosition: ExecutionPosition(0),
            childContinuation: ExecutionContinuation(nextInput: "B-next", continuationID: "B-cont")
        )
        let tasks = (0..<32).map { _ in
            Task { () -> Bool in
                do {
                    _ = try await coordinator.fork(request)
                    return true
                } catch {
                    return false
                }
            }
        }

        await backend.waitForFirstDerivationToStart()
        // Give every competing task an opportunity to reach the coordinator
        // while the first backend derivation remains suspended.
        for _ in 0..<64 { await Task.yield() }
        let derivationsBeforeRelease = await backend.derivationCallCount()
        XCTAssertEqual(
            derivationsBeforeRelease,
            1,
            "a second coordinator transition must not enter the backend before the first commits"
        )

        await backend.resumeFirstDerivation()
        var outcomes: [Bool] = []
        for task in tasks {
            outcomes.append(await task.value)
        }

        XCTAssertEqual(outcomes.filter { $0 }.count, 1, "only one fork may claim child B")
        XCTAssertEqual(coordinator.recordCount, recordsBeforeForks + 1)
        let child = try XCTUnwrap(coordinator.handle(ExecutionID("B")))
        XCTAssertEqual(child.lineage.parent, ExecutionID("A"))
        let representation = try await backend.captureRepresentation(for: child)
        XCTAssertEqual(representation.position, ExecutionPosition(0))
        let payload = try XCTUnwrap(representation.payload as? MLXPrefixPayload)
        XCTAssertEqual(payload.tokenPrefix, [1, 2, 3])
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
