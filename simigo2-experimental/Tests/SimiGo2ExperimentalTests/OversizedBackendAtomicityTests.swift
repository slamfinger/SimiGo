import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

/// Review-directed fault-injection verification (backend physical
/// atomicity): a FAILED release must leave the binding intact and
/// retryable, and a successful release must commit the binding cleanup.
/// Coordinator.discard must propagate the failure without mutating the
/// logical state, lifecycle records, or the binding.
private final class ReleaseGate: @unchecked Sendable {
    var failRelease = true
    var attempts = 0
}

final class OversizedBackendAtomicityTests: XCTestCase {
    private func makeBackend(gate: ReleaseGate) -> OversizedSegmentedStateBackend {
        OversizedSegmentedStateBackend(releaseAll: {
            gate.attempts += 1
            if gate.failRelease {
                throw ReleaseGateError()
            }
        })
    }

    private func makeState(_ id: String) throws -> ExecutionStateHandle {
        ExecutionStateHandle(
            id: ExecutionID(id),
            lineage: ExecutionLineage(root: ExecutionID(id), parent: nil),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "", continuationID: "\(id)-c0"),
            lifecycle: .active
        )
    }

    private struct ReleaseGateError: Error {}

    func testBackendFailedReleaseLeavesBindingIntactAndRetryable() async throws {
        let gate = ReleaseGate()
        gate.failRelease = false
        let backend = makeBackend(gate: gate)
        let state = try makeState("X")
        backend.bind(executionID: state.id, position: state.position, prefix: [7, 7])

        let representation = try await backend.captureRepresentation(for: state)
        XCTAssertEqual(representation.payload as! OversizedPrefixPayload,
                       OversizedPrefixPayload(tokenPrefix: [7, 7]))

        // Forced failure: the physical release throws AFTER the foreign
        // guard and BEFORE the binding cleanup — the binding must be intact.
        gate.failRelease = true
        do {
            _ = try await backend.releaseRepresentation(representation)
            XCTFail("expected release failure")
        } catch { /* expected */ }
        let intact = try backend.boundPrefix(for: state)
        XCTAssertEqual(intact.prefix, [7, 7])

        // Retry with the failure cleared: the release commits and the
        // binding is gone.
        gate.failRelease = false
        try await backend.releaseRepresentation(representation)
        XCTAssertThrowsError(try backend.boundPrefix(for: state))
        XCTAssertEqual(gate.attempts, 2, "failed release + successful retry; the foreign-payload rejection is proven zero-mutation by the count staying flat across its rejection")

        // Zero-mutation guard: a foreign payload throws before anything.
        do {
            let foreign = ExecutionRepresentation(
                executionID: ExecutionID("X"), position: ExecutionPosition(1),
                payload: ForeignTestPayload())
            _ = try await backend.releaseRepresentation(foreign)
            XCTFail("expected foreign-payload rejection")
        } catch { /* expected */ }
    }

    func testCoordinatorDiscardPropagatesFailedReleaseWithoutMutatingState() async throws {
        let gate = ReleaseGate()
        gate.failRelease = false
        let backend = makeBackend(gate: gate)
        let coordinator = ExecutionContinuityCoordinator(backend: backend)
        let state = try await coordinator.create(
            id: ExecutionID("S"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "", continuationID: "S-c0")
        )
        try await coordinator.bindRepresentation(
            executionID: state.id, position: state.position,
            payload: OversizedPrefixPayload(tokenPrefix: [1, 2, 3])
        )
        let recordsAfterBootstrap = coordinator.recordCount

        gate.failRelease = true
        do {
            _ = try await coordinator.discard(state)
            XCTFail("expected discard failure")
        } catch { /* expected */ }

        // Five sources unchanged by the FAILED discard: handle (position +
        // lifecycle NOT discarded), records (no .discarded entry), binding.
        let retained = coordinator.handle(state.id)
        XCTAssertNotNil(retained)
        XCTAssertEqual(retained?.position, state.position)
        XCTAssertEqual(retained?.lifecycle, state.lifecycle)
        XCTAssertEqual(coordinator.recordCount, recordsAfterBootstrap)
        XCTAssertNoThrow(try backend.boundPrefix(for: state))

        // Successful retry: discard commits.
        gate.failRelease = false
        try await coordinator.discard(state)
        let discarded = try coordinator.handle(state.id)
        XCTAssertEqual(discarded?.lifecycle, .discarded)
        XCTAssertEqual(discarded?.position, state.position)
    }
}

private struct ForeignTestPayload: ExecutionRepresentationPayload {}


