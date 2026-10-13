import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

final class OversizedSegmentedEngineRestoreAtomicityTests: XCTestCase {
    private let executionID = ExecutionID("S")

    private struct Session {
        let engine: OversizedSegmentedEngine
        let gate: AppendGate
        let currentState: () -> ExecutionStateHandle?
        let coordinatorRecordCount: () -> Int
        let backendBoundPrefixLength: (ExecutionID, ExecutionPosition) throws -> Int
        let hasUncertainBinding: () -> Bool
    }

    /// Two append calls bootstrap + turn, then fail so restore reaches its
    /// stable marker-append failure deterministically.
    private final class AppendGate: @unchecked Sendable {
        private let lock = NSLock()
        private var remaining = 0

        func allow(_ count: Int) {
            lock.lock()
            remaining = count
            lock.unlock()
        }

        func admit() throws {
            lock.lock()
            defer { lock.unlock() }
            guard remaining > 0 else {
                throw OversizedEngineError.residencyDivergence("stable marker append failure")
            }
            remaining -= 1
        }
    }

    /// Interposes between the coordinator and the engine's physical backend
    /// so a coordinator-driven restore rebind can be made to fail on a
    /// deterministic call index (the engine keeps the real backend, so both
    /// sides observe one shared physical state). Call indexes count ALL
    /// coordinator-driven rebinds: fixture binds are 1-2, a restore target
    /// rebind 3, its compensation rebind 4.
    private final class BackendRestoreFaultInjector: ExecutionStateBackend, @unchecked Sendable {
        struct InjectedRestoreFailure: Error {}
        struct UnattachedBackend: Error {}

        private let lock = NSLock()
        private var target: OversizedSegmentedStateBackend?
        private var restoreCalls = 0
        private var failingCallIndexes: Set<Int> = []

        func attach(_ backend: OversizedSegmentedStateBackend) {
            lock.lock()
            target = backend
            lock.unlock()
        }

        func failRestoreCall(_ index: Int) {
            lock.lock()
            failingCallIndexes.insert(index)
            lock.unlock()
        }

        private func attached() throws -> OversizedSegmentedStateBackend {
            try lock.withLock {
                guard let target else { throw UnattachedBackend() }
                return target
            }
        }

        func captureRepresentation(
            for state: ExecutionStateHandle
        ) async throws -> ExecutionRepresentation {
            try await attached().captureRepresentation(for: state)
        }

        func deriveRepresentation(
            from parent: ExecutionRepresentation,
            for child: ExecutionStateHandle
        ) async throws -> ExecutionRepresentation {
            try await attached().deriveRepresentation(from: parent, for: child)
        }

        func restoreRepresentation(
            _ representation: ExecutionRepresentation
        ) async throws {
            lock.lock()
            restoreCalls += 1
            let shouldFail = failingCallIndexes.contains(restoreCalls)
            lock.unlock()
            if shouldFail {
                throw InjectedRestoreFailure()
            }
            try await attached().restoreRepresentation(representation)
        }

        func releaseRepresentation(
            _ representation: ExecutionRepresentation
        ) async throws {
            try await attached().releaseRepresentation(representation)
        }
    }

    private func makeSession(gate: AppendGate) async throws -> Session {
        gate.allow(2)
        let fixture = try await OversizedSegmentedEngine.makeRestoreAtomicityTestFixture(
            executionID: executionID,
            beforeAppend: gate.admit)
        return Session(
            engine: fixture.engine,
            gate: gate,
            currentState: fixture.currentState,
            coordinatorRecordCount: fixture.coordinatorRecordCount,
            backendBoundPrefixLength: fixture.backendBoundPrefixLength,
            hasUncertainBinding: fixture.hasUncertainBinding)
    }

    /// Isolation session: a fault-injecting coordinator backend plus a
    /// residency controller with one always-resident group (CORE) and one
    /// evictable group (A), so a newSession rejection can be probed for
    /// silent evictions.
    private func makeIsolationSession(
        gate: AppendGate
    ) async throws -> (session: Session, injector: BackendRestoreFaultInjector, evictionProbe: MockResidencyMaterializer) {
        gate.allow(2)
        let injector = BackendRestoreFaultInjector()
        let probe = MockResidencyMaterializer()
        let inventory = LayerInventory(
            groups: [
                LayerGroup(id: "CORE", title: "Core", layerRangeDescription: "core", tensorCount: 1, byteCount: 100, alwaysResident: true),
                LayerGroup(id: "A", title: "A", layerRangeDescription: "0", tensorCount: 1, byteCount: 100)
            ],
            tensors: [],
            totalByteCount: 200)
        let residency = ResidencyController(
            inventory: inventory,
            materializer: probe,
            initialResidentGroupIDs: ["CORE", "A"])
        let fixture = try await OversizedSegmentedEngine.makeRestoreAtomicityTestFixture(
            executionID: executionID,
            beforeAppend: gate.admit,
            coordinatorBackendFactory: { backend in
                injector.attach(backend)
                return injector
            },
            residency: residency)
        return (
            Session(
                engine: fixture.engine,
                gate: gate,
                currentState: fixture.currentState,
                coordinatorRecordCount: fixture.coordinatorRecordCount,
                backendBoundPrefixLength: fixture.backendBoundPrefixLength,
                hasUncertainBinding: fixture.hasUncertainBinding),
            injector,
            probe
        )
    }

    /// Drives one hooked restore to the double-failure branch: the marker
    /// hook fails on the closed append gate AND the compensation rebind fails
    /// on the injected fault (call 4), leaving the engine with an uncertain
    /// backend binding (physical at target 0, logical still at 1).
    private func enterUncertainState(
        _ session: Session,
        injector: BackendRestoreFaultInjector
    ) async throws {
        injector.failRestoreCall(4)
        do {
            try await session.engine.restoreSession(to: 0)
            XCTFail("restore must fail when both marker commit and compensation fail")
        } catch {
            let description = String(describing: error)
            XCTAssertTrue(
                description.contains("stable marker append failure"),
                "missing hook failure: \(description)")
            XCTAssertTrue(
                description.contains("InjectedRestoreFailure"),
                "missing compensation failure: \(description)")
        }
        XCTAssertTrue(session.hasUncertainBinding())
        XCTAssertEqual(
            try session.backendBoundPrefixLength(executionID, ExecutionPosition(0)), 3)
        XCTAssertThrowsError(try session.backendBoundPrefixLength(
            executionID, ExecutionPosition(1)))
    }

    private func assertDivergence(
        _ error: Error,
        contains detail: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case OversizedEngineError.residencyDivergence(let message) = error else {
            return XCTFail("expected residencyDivergence, got \(error)", file: file, line: line)
        }
        XCTAssertTrue(message.contains(detail), message, file: file, line: line)
    }

    func testValidRewindAlignsCoordinatorLedgerAndSession() async throws {
        let session = try await makeSession(gate: AppendGate())
        session.gate.allow(1)

        try await session.engine.restoreSession(to: 0)

        let restored = try XCTUnwrap(session.currentState())
        XCTAssertEqual(restored.position, ExecutionPosition(0))
        XCTAssertEqual(restored.lifecycle, .restored)
        XCTAssertEqual(session.engine.sessionInfo?.executionID, executionID.rawValue)
        XCTAssertEqual(session.engine.sessionInfo?.position, 0)
        XCTAssertEqual(session.engine.sessionInfo?.turns, 0)
        XCTAssertEqual(session.engine.sessionInfo?.records, 3)
        XCTAssertEqual(try session.backendBoundPrefixLength(
            executionID, ExecutionPosition(0)), 3)
        let entries = try XCTUnwrap(session.engine.tokenLedger?.entries(for: executionID))
        XCTAssertEqual(entries.map(\.kind), [.bootstrap, .turn, .restoreMarker])
        XCTAssertEqual(entries.map(\.superseded), [false, true, false])
    }

    func testTargetAheadRejectedBeforeCoordinatorMutation() async throws {
        let session = try await makeSession(gate: AppendGate())
        let beforeRecords = session.coordinatorRecordCount()

        do {
            try await session.engine.restoreSession(to: 3)
            XCTFail("restore ahead of committed history should throw")
        } catch {
            assertDivergence(error, contains: "restore target beyond committed history")
        }

        let state = try XCTUnwrap(session.currentState())
        XCTAssertEqual(session.coordinatorRecordCount(), beforeRecords)
        XCTAssertEqual(state.position, ExecutionPosition(1))
        XCTAssertEqual(state.lifecycle, .active)
        XCTAssertEqual(session.engine.sessionInfo?.position, 1)
        XCTAssertEqual(session.engine.tokenLedger?.count, 2)
        XCTAssertEqual(try session.backendBoundPrefixLength(
            executionID, ExecutionPosition(1)), 5)

        // A valid target still works after the rejected read-only precheck.
        session.gate.allow(1)
        try await session.engine.restoreSession(to: 0)
        XCTAssertEqual(session.currentState()?.position, ExecutionPosition(0))
    }

    func testTargetRebindFailureKeepsPriorStateWithoutIsolation() async throws {
        let gate = AppendGate()
        let (session, injector, evictionProbe) = try await makeIsolationSession(gate: gate)
        // Call 3 is the restore target rebind: it fails BEFORE the marker
        // hook ever runs, so no compensation is needed and no isolation may
        // be entered.
        injector.failRestoreCall(3)
        let beforeRecords = session.coordinatorRecordCount()

        do {
            try await session.engine.restoreSession(to: 0)
            XCTFail("restore must fail when the target rebind fails")
        } catch {
            guard error is BackendRestoreFaultInjector.InjectedRestoreFailure else {
                return XCTFail("expected the raw rebind failure, got \(error)")
            }
        }

        // Unlike a compensation failure, the physical binding never moved:
        // it stays at the PRIOR position, and the logical, ledger, and
        // session state are untouched with NO isolation entered.
        XCTAssertFalse(session.hasUncertainBinding())
        XCTAssertEqual(try session.backendBoundPrefixLength(
            executionID, ExecutionPosition(1)), 5)
        XCTAssertThrowsError(try session.backendBoundPrefixLength(
            executionID, ExecutionPosition(0)))
        XCTAssertEqual(session.coordinatorRecordCount(), beforeRecords)
        XCTAssertEqual(session.currentState()?.position, ExecutionPosition(1))
        XCTAssertEqual(session.currentState()?.lifecycle, .active)
        XCTAssertEqual(session.engine.sessionInfo?.position, 1)
        XCTAssertEqual(session.engine.tokenLedger?.count, 2)
        let entries = try XCTUnwrap(session.engine.tokenLedger?.entries(for: executionID))
        XCTAssertEqual(entries.map(\.kind), [.bootstrap, .turn])
        XCTAssertEqual(entries.map(\.superseded), [false, false])

        // Not isolated: teardown stays available even before any recovery.
        try await session.engine.newSession()
        XCTAssertEqual(evictionProbe.calls, ["release:A"])
        XCTAssertNil(session.currentState())
        XCTAssertNil(session.engine.sessionInfo)
    }

    func testStableMarkerAppendFailureRollsBackBeforeLogicalCommit() async throws {
        let gate = AppendGate()
        let session = try await makeSession(gate: gate)
        let beforeRecords = session.coordinatorRecordCount()

        do {
            try await session.engine.restoreSession(to: 0)
            XCTFail("stable marker failure should throw")
        } catch {
            assertDivergence(error, contains: "stable marker append failure")
        }

        // The failed marker append is compensated before the logical restore
        // commits: handle, coordinator record count, ledger and backend all
        // remain at the pre-restore position.
        let unchanged = try XCTUnwrap(session.currentState())
        XCTAssertEqual(unchanged.position, ExecutionPosition(1))
        XCTAssertEqual(unchanged.lifecycle, .active)
        XCTAssertEqual(session.engine.sessionInfo?.position, 1)
        XCTAssertEqual(session.engine.sessionInfo?.records, beforeRecords)
        XCTAssertEqual(session.coordinatorRecordCount(), beforeRecords)
        XCTAssertEqual(try session.backendBoundPrefixLength(
            executionID, ExecutionPosition(1)), 5)
        XCTAssertThrowsError(try session.backendBoundPrefixLength(
            executionID, ExecutionPosition(0)))
        let entries = try XCTUnwrap(session.engine.tokenLedger?.entries(for: executionID))
        XCTAssertEqual(entries.map(\.kind), [.bootstrap, .turn])
        XCTAssertEqual(entries.map(\.superseded), [false, false])
        // The physical compensation succeeded, so NO isolation was entered:
        // the original retry behavior is untouched.
        XCTAssertFalse(session.hasUncertainBinding())

        gate.allow(1)
        try await session.engine.restoreSession(to: 0)
        XCTAssertEqual(session.currentState()?.position, ExecutionPosition(0))
        XCTAssertEqual(session.engine.sessionInfo?.position, 0)
        XCTAssertEqual(session.coordinatorRecordCount(), beforeRecords + 1)
        XCTAssertEqual(session.engine.tokenLedger?.count, 3)
    }

    func testUncertainBindingRejectsNewSessionWithoutSideEffectsUntilExplicitRestore() async throws {
        let gate = AppendGate()
        let (session, injector, evictionProbe) = try await makeIsolationSession(gate: gate)
        try await enterUncertainState(session, injector: injector)
        let beforeRecords = session.coordinatorRecordCount()

        // newSession is rejected BEFORE any teardown: no eviction fires, and
        // coordinator, ledger, session info, and backend binding are untouched.
        do {
            try await session.engine.newSession()
            XCTFail("newSession must be rejected while the backend binding is uncertain")
        } catch {
            guard case OversizedEngineError.backendBindingUncertain(let flagged) = error else {
                return XCTFail("expected backendBindingUncertain, got \(error)")
            }
            XCTAssertEqual(flagged, executionID)
        }
        XCTAssertEqual(evictionProbe.calls, [])
        XCTAssertEqual(session.engine.residencyTransferCount, 0)
        XCTAssertEqual(session.coordinatorRecordCount(), beforeRecords)
        XCTAssertEqual(session.currentState()?.position, ExecutionPosition(1))
        XCTAssertEqual(session.engine.sessionInfo?.position, 1)
        XCTAssertEqual(session.engine.tokenLedger?.count, 2)
        XCTAssertTrue(session.hasUncertainBinding())

        // Explicit recovery: restoreSession stays available in the uncertain
        // state and realigns backend, coordinator, ledger, currentState, and
        // sessionInfo — lifting the isolation.
        session.gate.allow(1)
        try await session.engine.restoreSession(to: 0)
        XCTAssertFalse(session.hasUncertainBinding())
        let restored = try XCTUnwrap(session.currentState())
        XCTAssertEqual(restored.position, ExecutionPosition(0))
        XCTAssertEqual(restored.lifecycle, .restored)
        XCTAssertEqual(session.engine.sessionInfo?.position, 0)
        XCTAssertEqual(session.engine.sessionInfo?.records, session.coordinatorRecordCount())
        XCTAssertEqual(try session.backendBoundPrefixLength(
            executionID, ExecutionPosition(0)), 3)
        XCTAssertThrowsError(try session.backendBoundPrefixLength(
            executionID, ExecutionPosition(1)))
        let entries = try XCTUnwrap(session.engine.tokenLedger?.entries(for: executionID))
        XCTAssertEqual(entries.map(\.kind), [.bootstrap, .turn, .restoreMarker])
        XCTAssertEqual(entries.map(\.superseded), [false, true, false])

        // The originally blocked operation is retryable after recovery. The
        // eviction probe now fires, proving it was silent earlier only
        // because the rejection preceded teardown — not because the probe
        // is inert.
        try await session.engine.newSession()
        XCTAssertEqual(evictionProbe.calls, ["release:A"])
        XCTAssertNil(session.currentState())
        XCTAssertNil(session.engine.sessionInfo)
    }

    func testRepeatedCompensationFailureKeepsEngineIsolatedAndReported() async throws {
        let gate = AppendGate()
        let (session, injector, evictionProbe) = try await makeIsolationSession(gate: gate)
        try await enterUncertainState(session, injector: injector)
        let beforeRecords = session.coordinatorRecordCount()

        // Second attempt: the marker hook fails on the still-closed gate AND
        // the compensation rebind fails again (call 6 = second restore's
        // compensation). Both failures stay visible; the isolation persists.
        injector.failRestoreCall(6)
        do {
            try await session.engine.restoreSession(to: 0)
            XCTFail("second restore must fail again when compensation fails again")
        } catch {
            let description = String(describing: error)
            XCTAssertTrue(
                description.contains("stable marker append failure"),
                "missing hook failure: \(description)")
            XCTAssertTrue(
                description.contains("InjectedRestoreFailure"),
                "missing compensation failure: \(description)")
        }

        // No Ledger, lifecycle, or session state moved; the physical binding
        // remains at the restore target; the isolation still rejects teardown
        // with zero eviction side effects.
        XCTAssertTrue(session.hasUncertainBinding())
        XCTAssertEqual(session.coordinatorRecordCount(), beforeRecords)
        XCTAssertEqual(session.currentState()?.position, ExecutionPosition(1))
        XCTAssertEqual(session.currentState()?.lifecycle, .active)
        XCTAssertEqual(session.engine.sessionInfo?.position, 1)
        XCTAssertEqual(session.engine.tokenLedger?.count, 2)
        let entries = try XCTUnwrap(session.engine.tokenLedger?.entries(for: executionID))
        XCTAssertEqual(entries.map(\.kind), [.bootstrap, .turn])
        XCTAssertEqual(entries.map(\.superseded), [false, false])
        XCTAssertEqual(try session.backendBoundPrefixLength(
            executionID, ExecutionPosition(0)), 3)

        do {
            try await session.engine.newSession()
            XCTFail("newSession must stay rejected after a repeated compensation failure")
        } catch {
            guard case OversizedEngineError.backendBindingUncertain = error else {
                return XCTFail("expected backendBindingUncertain, got \(error)")
            }
        }
        XCTAssertEqual(evictionProbe.calls, [])
        XCTAssertEqual(session.engine.residencyTransferCount, 0)
    }

    func testExplicitRestoreRecoversToEveryCommittedPositionFromUncertainty() async throws {
        let gate = AppendGate()
        let (session, injector, _) = try await makeIsolationSession(gate: gate)
        try await enterUncertainState(session, injector: injector)
        let beforeRecords = session.coordinatorRecordCount()

        // Recovery target = the PRIOR position itself: forward resume of the
        // position the failed restore tried to leave behind. All five
        // components realign and the isolation lifts without a rewind.
        session.gate.allow(1)
        try await session.engine.restoreSession(to: 1)
        XCTAssertFalse(session.hasUncertainBinding())
        XCTAssertEqual(session.currentState()?.position, ExecutionPosition(1))
        XCTAssertEqual(session.currentState()?.lifecycle, .restored)
        XCTAssertEqual(session.engine.sessionInfo?.position, 1)
        XCTAssertEqual(try session.backendBoundPrefixLength(
            executionID, ExecutionPosition(1)), 5)
        XCTAssertThrowsError(try session.backendBoundPrefixLength(
            executionID, ExecutionPosition(0)))
        XCTAssertEqual(session.coordinatorRecordCount(), beforeRecords + 1)

        // And the original rewind target (backward), in the same session:
        // explicit recovery covers both directions from the uncertain state.
        session.gate.allow(1)
        try await session.engine.restoreSession(to: 0)
        XCTAssertFalse(session.hasUncertainBinding())
        XCTAssertEqual(session.currentState()?.position, ExecutionPosition(0))
        XCTAssertEqual(session.currentState()?.lifecycle, .restored)
        XCTAssertEqual(session.engine.sessionInfo?.position, 0)
        XCTAssertEqual(try session.backendBoundPrefixLength(
            executionID, ExecutionPosition(0)), 3)
        XCTAssertThrowsError(try session.backendBoundPrefixLength(
            executionID, ExecutionPosition(1)))
        let entries = try XCTUnwrap(session.engine.tokenLedger?.entries(for: executionID))
        XCTAssertEqual(
            entries.map(\.kind),
            [.bootstrap, .turn, .restoreMarker, .restoreMarker])
        XCTAssertEqual(entries.map(\.superseded), [false, true, true, false])
    }

    /// Engine-level execution-model contract: the engine serves EXACTLY ONE
    /// execution ("S", fixed in ensureSession). The only way to move to
    /// another execution is newSession() — a full teardown — and the next
    /// bootstrap builds a FRESH Coordinator + Backend + Ledger triple with
    /// the same fixed ID, so nothing (state, records, uncertainty) carries
    /// across. Coordinator-level multi-execution guarantees do NOT extend
    /// to the engine: multi-execution is UNSUPPORTED BY DESIGN.
    func testEngineIsSingleExecutionSwitchingIsFullReset() async throws {
        let gate = AppendGate()
        gate.allow(2)
        let fixture = try await OversizedSegmentedEngine.makeRestoreAtomicityTestFixture(
            executionID: executionID,
            beforeAppend: gate.admit)
        let engine = fixture.engine
        let oldLedger = try XCTUnwrap(engine.tokenLedger)
        let oldState = try XCTUnwrap(fixture.currentState())
        XCTAssertEqual(oldState.id, ExecutionID("S"))

        // The only switching primitive: newSession() tears the whole session
        // down, Coordinator included. The closed ledger is retained for
        // audit until the next bootstrap replaces it.
        try await engine.newSession()
        XCTAssertNil(fixture.currentState())
        XCTAssertNil(engine.sessionInfo)
        XCTAssertTrue(engine.tokenLedger === oldLedger)

        // Re-bootstrap through the engine's OWN private session path (the
        // one generate() drives): a fresh triple with the same fixed ID.
        let rebased = try await engine.debugEnsureSession(prefix: [9, 9])
        XCTAssertEqual(rebased.id, ExecutionID("S"))
        XCTAssertEqual(rebased.position, ExecutionPosition(0))
        XCTAssertEqual(rebased.lifecycle, .attached)
        let newLedger = try XCTUnwrap(engine.tokenLedger)
        XCTAssertFalse(newLedger === oldLedger)
        XCTAssertEqual(newLedger.count, 0)

        // One session at a time: a second bootstrap without a teardown is
        // rejected by the engine itself.
        do {
            _ = try await engine.debugEnsureSession(prefix: [1])
            XCTFail("a second session bootstrap without newSession must be rejected")
        } catch {
            guard case OversizedEngineError.notLoaded = error else {
                return XCTFail("expected notLoaded, got \(error)")
            }
        }
    }
}
