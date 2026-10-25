import XCTest
import SimiGoRuntimeContract
import SimiGo2Experimental

/// Model-free integration regression that STITCHES the carrier-release protocol to
/// the retired-carrier tombstone (`MLXExecutionStateBackend`): a minimal
/// product-native conformer implements ``ExecutionCarrierReleasing`` against the
/// REAL backend, so release → verify-unusable → (refusal) is exercised for real —
/// no model weights, no G3 harness, no real MLX carrier.
///
/// The double drives the same public `releaseCarrier`/`isCarrierRetired`/
/// `boundPrefix` surface the production runtime uses, so passing proves the
/// protocol's fail-closed contract and the tombstone's one-way behaviour. It does
/// NOT prove that a real carrier was released or that a real KV was freed
/// (G3 D1 stays NO-GO).
final class CarrierLifecycleProtocolTests: XCTestCase {
    private func handle(_ id: String, position: Int64 = 0) -> ExecutionStateHandle {
        ExecutionStateHandle(
            id: ExecutionID(id),
            lineage: ExecutionLineage(root: ExecutionID(id)),
            position: ExecutionPosition(position),
            continuation: ExecutionContinuation(nextInput: "n", continuationID: "c"),
            lifecycle: .active)
    }

    private func ref(_ branch: String) -> ExecutionCarrierRef {
        ExecutionCarrierRef(agentID: "agent-1", sessionID: "sess-1", branchID: branch)
    }

    /// Identity-independent check: the app test bundle links the modules that
    /// define these enums twice (directly and transitively via the
    /// `SimiGo2Experimental` framework), so `as?` downcasts across the boundary
    /// yield nil; reflection still pins the exact case.
    private func reflected(_ error: Error) -> String { String(reflecting: error) }

    // A model-free conformer of the native carrier lifecycle protocol that
    // exercises the REAL retired-carrier tombstone on the shared backend.
    private final class CarrierLifecycleDouble: ExecutionCarrierReleasing {
        private let backend: MLXExecutionStateBackend
        var releaseError: Error?
        /// A prefix-recompute carrier holds no KV, so this is honestly
        /// `.noneObserved` rather than an empty set presented as "verified".
        var retiredStorage: CarrierStorageEvidence = .noneObserved
        private(set) var releaseCount = 0

        init(backend: MLXExecutionStateBackend) { self.backend = backend }

        func releaseExecutionCarrier(
            _ ref: ExecutionCarrierRef
        ) async throws -> CarrierReleaseReport {
            releaseCount += 1
            if let releaseError { throw releaseError }
            backend.releaseCarrier(for: ExecutionID(ref.branchID))
            return CarrierReleaseReport(
                carrierWasLive: true,
                clearIssued: false,
                sessionsReleased: 0,
                bindingDetached: true,
                checkpointFilesDeleted: 0,
                stillLiveAfterwards: false,
                retiredStorage: retiredStorage)
        }

        func verifyCarrierUnusable(_ ref: ExecutionCarrierRef) throws {
            guard backend.isCarrierRetired(for: ExecutionID(ref.branchID)) else {
                throw CarrierLifecycleError.releaseIncomplete(reason: "carrier not retired")
            }
            // The double is a nested type, so it rebuilds the handle from the
            // address instead of reaching into the enclosing test case.
            let state = ExecutionStateHandle(
                id: ExecutionID(ref.branchID),
                lineage: ExecutionLineage(root: ExecutionID(ref.branchID)),
                position: ExecutionPosition(0),
                continuation: ExecutionContinuation(nextInput: "n", continuationID: "c"),
                lifecycle: .active)
            do {
                _ = try backend.boundPrefix(for: state)
                // The bound read SUCCEEDED, so the old ES can still use it.
                throw CarrierLifecycleError.carrierStillUsable(executionID: ref.branchID)
            } catch let thrown as CarrierLifecycleError {
                throw thrown
            } catch {
                // boundPrefix refused; only `carrierReleased` proves the release.
                guard String(reflecting: error).contains("carrierReleased") else {
                    throw CarrierLifecycleError.releaseIncomplete(
                        reason: "bound read failed as \(error), not carrierReleased")
                }
            }
        }
    }

    func testReleaseThenVerifyAgainstRealBackend() async throws {
        let backend = MLXExecutionStateBackend()
        let h = handle("S1")
        backend.bind(executionID: h.id, position: h.position, tokenPrefix: [1, 2])
        let double = CarrierLifecycleDouble(backend: backend)

        let report = try await double.releaseExecutionCarrier(ref("S1"))
        // A release is NOT a KV-free proof: the double reports what it can see.
        XCTAssertEqual(report.retiredStorage, .noneObserved)
        XCTAssertFalse(report.stillLiveAfterwards)

        // Real tombstone engaged, so verify-unusable passes against the SAME backend.
        XCTAssertTrue(backend.isCarrierRetired(for: h.id))
        XCTAssertNoThrow(try double.verifyCarrierUnusable(ref("S1")))
    }

    func testReleaseErrorPropagatesFailClosed() async throws {
        let backend = MLXExecutionStateBackend()
        let h = handle("S2")
        backend.bind(executionID: h.id, position: h.position, tokenPrefix: [1])
        let double = CarrierLifecycleDouble(backend: backend)
        double.releaseError = NSError(domain: "boom", code: 1)

        do {
            _ = try await double.releaseExecutionCarrier(ref("S2"))
            XCTFail("a failing release must not report success")
        } catch {
            XCTAssertFalse(reflected(error).contains("carrierReleased"))
        }
        // Release never took, so the carrier is NOT retired and must not verify.
        XCTAssertFalse(backend.isCarrierRetired(for: h.id))
        XCTAssertThrowsError(try double.verifyCarrierUnusable(ref("S2"))) { error in
            XCTAssertTrue(reflected(error).contains("releaseIncomplete"), "got \(error)")
        }
    }

    /// The address, not the backend, decides what is retired: releasing the child
    /// branch of one request must leave a sibling branch's carrier untouched.
    func testRetirementIsPerBranchAddress() async throws {
        let backend = MLXExecutionStateBackend()
        let child = handle("C3")
        let sibling = handle("S3")
        backend.bind(executionID: child.id, position: child.position, tokenPrefix: [1])
        backend.bind(executionID: sibling.id, position: sibling.position, tokenPrefix: [2])
        let double = CarrierLifecycleDouble(backend: backend)

        _ = try await double.releaseExecutionCarrier(ref("C3"))

        XCTAssertTrue(backend.isCarrierRetired(for: child.id))
        XCTAssertFalse(backend.isCarrierRetired(for: sibling.id))
        XCTAssertNoThrow(try backend.boundPrefix(for: sibling))
        XCTAssertNoThrow(try double.verifyCarrierUnusable(ref("C3")))
    }
}
