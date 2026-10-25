import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

/// Native execution-carrier lifecycle tests: the explicit release of the old
/// carrier, the proof it is unusable, the pure storage-isolation decision, and
/// the settle → release → fresh-carrier recover → continue sequence — all with
/// model weights NOT loaded. Passing proves the lifecycle protocol and its
/// fail-closed behavior only; actually releasing a real MLX carrier, resuming a
/// brand-new ES independently and continuing on a real model remains unproven,
/// and D1 stays NO-GO.
final class NativeCarrierLifecycleTests: XCTestCase {
    override func setUpWithError() throws {
        // The end-to-end lifecycle cases settle through the production bridge,
        // which requires the deployment trust root under the `required`
        // provenance policy.
        try SettlementTrustFixture.install()
    }

    private func handle(_ id: String, position: Int64 = 0) -> ExecutionStateHandle {
        ExecutionStateHandle(
            id: ExecutionID(id),
            lineage: ExecutionLineage(root: ExecutionID(id)),
            position: ExecutionPosition(position),
            continuation: ExecutionContinuation(nextInput: "n", continuationID: "c"),
            lifecycle: .active)
    }

    // IS-bridge harness helpers (mirrors ProductionRuntimeInformationIntegrationTests
    // so the end-to-end lifecycle test runs against the real production bridge).
    private func makeTemporaryDatabase() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-ncl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("production_runtime.sqlite")
    }

    private func makeIsolatedConfiguration(
        defaultValidity: String = "2030-12-31T23:59:59Z"
    ) throws -> (configuration: ProductionRuntimeLaunchConfiguration, directory: URL) {
        let labRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-ncl-policy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let policy = directory.appendingPathComponent("validity-policy.json")
        let policyObject: [String: Any] = [
            "schema_id": "SIMIGO-INFO-VALIDITY-POLICY-V1",
            "policy_version": "native-carrier-lifecycle-test",
            "policy_source": "ISOLATED_TEST_ONLY",
            "missing_policy": "REJECT",
            "dependency_propagation": "ALL_TRANSITIVE",
            "default_valid_until_utc": defaultValidity,
        ]
        try JSONSerialization.data(withJSONObject: policyObject).write(to: policy)
        let configuration = ProductionRuntimeLaunchConfiguration(
            runtimeRoot: labRoot.appendingPathComponent("execution-information-loop"),
            pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"),
            snapshotPath: labRoot.appendingPathComponent(
                "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"),
            validityPolicyPath: policy)
        return (configuration, directory)
    }

    // MARK: Backend retired-carrier tombstone

    func testReleaseCarrierMakesBoundReadFailClosed() throws {
        let backend = MLXExecutionStateBackend()
        let h = handle("E1")
        backend.bind(executionID: h.id, position: h.position, tokenPrefix: [1, 2, 3])
        XCTAssertNoThrow(try backend.boundPrefix(for: h))

        backend.releaseCarrier(for: h.id)

        XCTAssertTrue(backend.isCarrierRetired(for: h.id))
        XCTAssertThrowsError(try backend.boundPrefix(for: h)) { error in
            guard case ExecutionStateBackendError.carrierReleased(let id) = error else {
                return XCTFail("expected carrierReleased, got \(error)")
            }
            XCTAssertEqual(id, h.id)
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
            guard case ExecutionStateBackendError.carrierReleased = error else {
                return XCTFail("expected carrierReleased after a re-bind attempt")
            }
        }

        // Recovery-style restore into the retired carrier is refused.
        let rep = ExecutionRepresentation(
            executionID: h.id, position: h.position,
            payload: MLXPrefixPayload(tokenPrefix: [1, 2, 3]))
        do {
            try await backend.restoreRepresentation(rep)
            XCTFail("restore into a retired carrier must be refused")
        } catch let error as ExecutionStateBackendError {
            guard case .carrierReleased = error else {
                return XCTFail("expected carrierReleased on restore, got \(error)")
            }
        }
        do {
            _ = try await backend.captureRepresentation(for: h)
            XCTFail("capture on a retired carrier must be refused")
        } catch let error as ExecutionStateBackendError {
            guard case .carrierReleased = error else {
                return XCTFail("expected carrierReleased on capture, got \(error)")
            }
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

    // MARK: Pure storage-isolation evaluator

    func testStorageIsolationEvaluatorCases() {
        // Nothing registered on the retired carrier → honestly isolated.
        XCTAssertEqual(
            CarrierStorageIsolationEvaluator.evaluate(retired: [], adopting: []), .isolated)
        XCTAssertEqual(
            CarrierStorageIsolationEvaluator.evaluate(retired: [], adopting: ["x"]), .isolated)
        // Retired held mutable storage, fresh exposes none confirmable → unproven.
        XCTAssertEqual(
            CarrierStorageIsolationEvaluator.evaluate(retired: ["x"], adopting: []), .unobservable)
        // Disjoint confirmed storage → isolated.
        XCTAssertEqual(
            CarrierStorageIsolationEvaluator.evaluate(retired: ["a"], adopting: ["b"]), .isolated)
        // Any shared confirmed id → refused with exactly the overlap.
        let shared = CarrierStorageIsolationEvaluator.evaluate(
            retired: ["a", "b"], adopting: ["b", "c"])
        XCTAssertEqual(shared, .shared(["b"]))
    }

    // MARK: Stub carrier lifecycle (drives the real backend tombstone)

    func testStubReleaseAndVerifyAgainstRealBackend() throws {
        let backend = MLXExecutionStateBackend()
        let h = handle("S1")
        backend.bind(executionID: h.id, position: h.position, tokenPrefix: [1, 2])
        let stub = ProductionRuntimeModelExecutorStub(representationBackend: backend)
        stub.simulatedRetiredStorageIDs = ["mlx:d=1:b=2"]

        XCTAssertNoThrow(try stub.releaseExecutionCarrier(for: h))
        XCTAssertNoThrow(try stub.verifyCarrierUnusable(for: h))
        XCTAssertEqual(stub.retiredCarrierStorageIDs(for: h), ["mlx:d=1:b=2"])
        XCTAssertTrue(backend.isCarrierRetired(for: h.id))
    }

    func testStubReleaseErrorPropagatesFailClosed() throws {
        let backend = MLXExecutionStateBackend()
        let h = handle("S2")
        backend.bind(executionID: h.id, position: h.position, tokenPrefix: [1])
        let stub = ProductionRuntimeModelExecutorStub(representationBackend: backend)
        stub.releaseCarrierError = NSError(domain: "boom", code: 1)

        XCTAssertThrowsError(try stub.releaseExecutionCarrier(for: h))
        // Release never took, so the carrier is NOT retired and must not verify.
        XCTAssertFalse(backend.isCarrierRetired(for: h.id))
    }

    func testHandoffIsolationRefusesSharedAndUnobservable() throws {
        let backend = MLXExecutionStateBackend()
        let h = handle("S3")
        let stub = ProductionRuntimeModelExecutorStub(representationBackend: backend)

        stub.simulatedAdoptedStorageIDs = ["a", "shared"]
        XCTAssertThrowsError(
            try stub.verifyAdoptedCarrierIsolated(from: ["shared"], for: h)) { error in
            guard case CarrierLifecycleError.carriersShareStorage(_, let ids) = error else {
                return XCTFail("expected carriersShareStorage, got \(error)")
            }
            XCTAssertEqual(ids, ["shared"])
        }

        stub.simulatedAdoptedStorageIDs = []
        XCTAssertThrowsError(
            try stub.verifyAdoptedCarrierIsolated(from: ["x"], for: h)) { error in
            guard case CarrierLifecycleError.carrierStorageIsolationUnobservable = error else {
                return XCTFail("expected unobservable, got \(error)")
            }
        }

        // Empty retired set (no KV) passes without claiming verified isolation.
        XCTAssertNoThrow(try stub.verifyAdoptedCarrierIsolated(from: [], for: h))
    }

    // MARK: End-to-end native lifecycle (real IS bridge, model weights NOT loaded)

    func testNativeCarrierLifecycleSettlesReleasesThenRecoversOnFreshCarrier() async throws {
        let database = try makeTemporaryDatabase()
        let isolated = try makeIsolatedConfiguration()
        let stateDirectory = isolated.directory.appendingPathComponent("es-state", isDirectory: true)

        let firstBackend = MLXExecutionStateBackend()
        let firstExecutor = ProductionRuntimeModelExecutorStub(representationBackend: firstBackend)
        let first = try ProductionRuntimeInformationIntegration(
            configuration: isolated.configuration,
            modelExecutor: firstExecutor,
            backend: firstBackend,
            semanticStateDirectory: stateDirectory)
        try first.initialize(database: database, validUntil: "2030-12-31T23:59:59Z")
        let phaseOne = try await first.continueWithRealInformation(
            database: database, handle: nil,
            advancementID: "lc-001", evaluatedAtUTC: "2026-10-09T00:00:00Z")
        XCTAssertEqual(phaseOne.handle.position, ExecutionPosition(1))

        // Explicitly release + verify the OLD carrier is unusable (recompute path:
        // no mutable KV registered, so the retired storage id set is empty).
        let retired = try first.releaseExecutionCarrier(for: phaseOne.handle)
        XCTAssertTrue(retired.isEmpty)
        XCTAssertThrowsError(try firstBackend.boundPrefix(for: phaseOne.handle)) { error in
            guard case ExecutionStateBackendError.carrierReleased = error else {
                return XCTFail("old carrier must be reported released, got \(error)")
            }
        }

        // A brand-new ES on a FRESH carrier recovers the settled work and continues
        // it WITHOUT re-tokenizing the seed — proven reuse, not recompute.
        let recoveredBackend = MLXExecutionStateBackend()
        let recoveredExecutor = ProductionRuntimeModelExecutorStub(representationBackend: recoveredBackend)
        let second = try ProductionRuntimeInformationIntegration(
            configuration: isolated.configuration,
            modelExecutor: recoveredExecutor,
            backend: recoveredBackend,
            semanticStateDirectory: stateDirectory)
        let recovered = try await second.recoverExecutionState(
            database: database, carrierIsolationAgainst: retired)
        XCTAssertEqual(recovered.position, ExecutionPosition(1))
        let bound = try recoveredBackend.boundPrefix(for: recovered)
        XCTAssertEqual(bound.prefix, [9, 18, 27])

        let phaseTwo = try await second.continueWithRealInformation(
            database: database, handle: recovered,
            advancementID: "lc-002", evaluatedAtUTC: "2026-10-09T00:01:00Z")
        XCTAssertEqual(phaseTwo.report.state, "ADVANCED")
        XCTAssertEqual(phaseTwo.report.reusedItemIDs.count, 9)
        XCTAssertEqual(recoveredExecutor.tokenizeSeedCallCount, 0)
        XCTAssertEqual(recoveredExecutor.continueExecutionCallCount, 1)
    }

    func testReleaseFailureRefusesBeforeAnyFreshCarrierRecovery() async throws {
        let database = try makeTemporaryDatabase()
        let isolated = try makeIsolatedConfiguration()
        let stateDirectory = isolated.directory.appendingPathComponent("es-state", isDirectory: true)

        let firstBackend = MLXExecutionStateBackend()
        let firstExecutor = ProductionRuntimeModelExecutorStub(representationBackend: firstBackend)
        let first = try ProductionRuntimeInformationIntegration(
            configuration: isolated.configuration,
            modelExecutor: firstExecutor,
            backend: firstBackend,
            semanticStateDirectory: stateDirectory)
        try first.initialize(database: database, validUntil: "2030-12-31T23:59:59Z")
        let phaseOne = try await first.continueWithRealInformation(
            database: database, handle: nil,
            advancementID: "lc-010", evaluatedAtUTC: "2026-10-09T00:00:00Z")

        // A carrier that cannot be released must refuse the handoff and leave the
        // old carrier intact (NOT retired) — the caller can never proceed to a
        // recovery that assumes the old state was released.
        firstExecutor.releaseCarrierError = NSError(domain: "release-refused", code: 7)
        XCTAssertThrowsError(try first.releaseExecutionCarrier(for: phaseOne.handle))
        XCTAssertFalse(firstBackend.isCarrierRetired(for: phaseOne.handle.id))
    }
}
