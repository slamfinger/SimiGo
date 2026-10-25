import XCTest
import SimiGoRuntimeContract
import SimiGo2Experimental

/// Backend-level regression for the retired-carrier tombstone ported from the
/// Lab `main` branch. A physical carrier released via `releaseCarrier(for:)`
/// must be genuinely unusable for the old Execution State on THIS backend
/// instance: every bound read, restore, capture, derive and re-bind is refused
/// with `ExecutionStateBackendError.carrierReleased`, and recovery must adopt a
/// NEW backend instance.
///
/// These cases drive the pure `MLXExecutionStateBackend` data plane only — no
/// model weights are loaded, no real MLX carrier is touched and no G3 harness
/// participates. They prove the fail-closed lifecycle protocol, not that a real
/// MLX carrier was physically released and resumed on a real model (D1 stays
/// NO-GO).
final class MLXCarrierRetirementTests: XCTestCase {
    private func handle(_ id: String, position: Int64 = 0) -> ExecutionStateHandle {
        ExecutionStateHandle(
            id: ExecutionID(id),
            lineage: ExecutionLineage(root: ExecutionID(id)),
            position: ExecutionPosition(position),
            continuation: ExecutionContinuation(nextInput: "n", continuationID: "c"),
            lifecycle: .active)
    }

    /// Assert the thrown error is the retired-carrier refusal for `executionID`.
    ///
    /// The app test bundle links `SimiGoRuntimeContract` both directly and
    /// transitively through the `SimiGo2Experimental` framework, so the enum's
    /// runtime type metadata has two copies and `error as? ExecutionStateBackendError`
    /// across that boundary yields nil even when the value IS that case. We assert
    /// on the fully-qualified reflection instead, which is identity-independent
    /// and still pins the exact case (and that it is NOT the merely-unbound case).
    private func assertCarrierReleased(_ error: Error, for id: String,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let reflected = String(reflecting: error)
        XCTAssertTrue(reflected.contains("carrierReleased"),
                      "expected carrierReleased for \(id), got \(reflected)", file: file, line: line)
        XCTAssertTrue(reflected.contains("\"\(id)\""),
                      "expected carrierReleased to carry \(id), got \(reflected)", file: file, line: line)
        XCTAssertFalse(reflected.contains("noBoundRepresentation"),
                       "a retired carrier must report released, not unbound: \(reflected)", file: file, line: line)
    }

    func testReleaseCarrierMakesBoundReadFailClosed() throws {
        let backend = MLXExecutionStateBackend()
        let h = handle("E1")
        backend.bind(executionID: h.id, position: h.position, tokenPrefix: [1, 2, 3])
        XCTAssertNoThrow(try backend.boundPrefix(for: h))

        backend.releaseCarrier(for: h.id)

        XCTAssertTrue(backend.isCarrierRetired(for: h.id))
        XCTAssertThrowsError(try backend.boundPrefix(for: h)) { error in
            assertCarrierReleased(error, for: "E1")
        }
    }

    func testReleasedCarrierCannotBeReArmed() async throws {
        let backend = MLXExecutionStateBackend()
        let h = handle("E2")
        backend.bind(executionID: h.id, position: h.position, tokenPrefix: [4, 5, 6])
        backend.releaseCarrier(for: h.id)

        // A re-bind is silently dropped, and reads still report the carrier
        // released — so "unusable" cannot be walked back by rebinding.
        backend.bind(executionID: h.id, position: h.position, tokenPrefix: [7, 8, 9])
        XCTAssertThrowsError(try backend.boundPrefix(for: h)) { error in
            assertCarrierReleased(error, for: "E2")
        }

        // Recovery-style restore into the retired carrier is refused.
        let rep = ExecutionRepresentation(
            executionID: h.id, position: h.position,
            payload: MLXPrefixPayload(tokenPrefix: [1, 2, 3]))
        do {
            try await backend.restoreRepresentation(rep)
            XCTFail("restore into a retired carrier must be refused")
        } catch {
            assertCarrierReleased(error, for: "E2")
        }
        do {
            _ = try await backend.captureRepresentation(for: h)
            XCTFail("capture on a retired carrier must be refused")
        } catch {
            assertCarrierReleased(error, for: "E2")
        }
    }

    func testReleasedChildCarrierCannotBeDerived() async throws {
        // A fork whose child identity was retired on this backend cannot be
        // silently re-armed by the derivation write.
        let backend = MLXExecutionStateBackend()
        let parent = handle("P", position: 3)
        backend.bind(executionID: parent.id, position: parent.position, tokenPrefix: [10, 11])
        let parentRep = try await backend.captureRepresentation(for: parent)

        let child = handle("C", position: 3)
        backend.releaseCarrier(for: child.id)

        do {
            _ = try await backend.deriveRepresentation(from: parentRep, for: child)
            XCTFail("derive into a retired child carrier must be refused")
        } catch {
            assertCarrierReleased(error, for: "C")
        }
    }

    func testFreshBackendStillServesRecovery() async throws {
        // The old carrier is retired; a NEW backend instance (a fresh carrier) can
        // still recover the settled representation. Release is per-instance, never
        // a global ban on the execution id.
        let oldBackend = MLXExecutionStateBackend()
        let h = handle("E3", position: 1)
        oldBackend.bind(executionID: h.id, position: h.position, tokenPrefix: [9, 18, 27])
        oldBackend.releaseCarrier(for: h.id)
        XCTAssertThrowsError(try oldBackend.boundPrefix(for: h))

        let freshBackend = MLXExecutionStateBackend()
        let rep = ExecutionRepresentation(
            executionID: h.id, position: h.position,
            payload: MLXPrefixPayload(tokenPrefix: [9, 18, 27]))
        try await freshBackend.restoreRepresentation(rep)
        let bound = try freshBackend.boundPrefix(for: h)
        XCTAssertEqual(bound.prefix, [9, 18, 27])
    }

    func testCarriersAreIndependentPerExecution() {
        let backend = MLXExecutionStateBackend()
        let a = handle("A"); let b = handle("B")
        backend.bind(executionID: a.id, position: a.position, tokenPrefix: [1])
        backend.bind(executionID: b.id, position: b.position, tokenPrefix: [2])
        backend.releaseCarrier(for: a.id)
        XCTAssertThrowsError(try backend.boundPrefix(for: a))
        XCTAssertNoThrow(try backend.boundPrefix(for: b))
        XCTAssertFalse(backend.isCarrierRetired(for: b.id))
    }
}
