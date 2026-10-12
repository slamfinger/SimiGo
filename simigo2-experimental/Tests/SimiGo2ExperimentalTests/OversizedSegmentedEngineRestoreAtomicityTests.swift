import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

final class OversizedSegmentedEngineRestoreAtomicityTests: XCTestCase {
    private let executionID = ExecutionID("S")

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

    private func makeEngine(
        backend: OversizedSegmentedStateBackend,
        ledger: OversizedTokenLedger
    ) async throws -> (engine: OversizedSegmentedEngine, state: ExecutionStateHandle) {
        let engine = OversizedSegmentedEngine(modelDirectory: URL(fileURLWithPath: "/unused"))
        let coordinator = ExecutionContinuityCoordinator(backend: backend)
        let state = try await coordinator.create(
            id: executionID,
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "", continuationID: "cont-0")
        )
        engine.coordinator = coordinator
        engine.stateBackend = backend
        engine.currentState = state
        engine.tokenLedger = ledger
        return (engine, state)
    }

    /// Mirror the committed part of generate(): bind/represent 0, advance to
    /// 1, then append its committed turn. No model or inference is used.
    private func seedHistory(
        _ engine: OversizedSegmentedEngine,
        ledger: OversizedTokenLedger
    ) async throws {
        guard let coordinator = engine.coordinator,
              let backend = engine.stateBackend,
              let state = engine.currentState else {
            return XCTFail("engine session was not installed")
        }

        backend.bind(
            executionID: state.id, position: state.position, prefix: [1, 2, 3])
        try await coordinator.bindRepresentation(
            executionID: state.id,
            position: state.position,
            payload: OversizedPrefixPayload(tokenPrefix: [1, 2, 3]))
        try ledger.append(OversizedTokenLedgerEntry(
            executionID: state.id, position: 0,
            kind: .bootstrap, prefixLength: 3))

        let advanced = try await coordinator.continueExecution(
            state,
            continuation: ExecutionContinuation(nextInput: "", continuationID: "cont-1"))
        backend.bind(
            executionID: advanced.id, position: advanced.position, prefix: [1, 2, 3, 4, 5])
        try await coordinator.bindRepresentation(
            executionID: advanced.id,
            position: advanced.position,
            payload: OversizedPrefixPayload(tokenPrefix: [1, 2, 3, 4, 5]))
        try ledger.append(OversizedTokenLedgerEntry(
            executionID: advanced.id, position: 1, kind: .turn, prefixLength: 5))
        engine.currentState = advanced
    }

    private func makeSession(gate: AppendGate) async throws -> (
        engine: OversizedSegmentedEngine,
        state: ExecutionStateHandle,
        gate: AppendGate
    ) {
        let backend = OversizedSegmentedStateBackend(releaseAll: {})
        let ledger = OversizedTokenLedger { _, position in
            try gate.admit()
            return position == 0 ? 3 : 5
        }
        let session = try await makeEngine(backend: backend, ledger: ledger)
        gate.allow(2)
        try await seedHistory(session.engine, ledger: ledger)
        session.engine.sessionInfo = OversizedSessionInfo(
            executionID: executionID.rawValue, position: 1, turns: 1, records: 2)
        return (session.engine, session.state, gate)
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

        let restored = try XCTUnwrap(session.engine.currentState)
        XCTAssertEqual(restored.position, ExecutionPosition(0))
        XCTAssertEqual(restored.lifecycle, .restored)
        XCTAssertEqual(session.engine.sessionInfo?.executionID, executionID.rawValue)
        XCTAssertEqual(session.engine.sessionInfo?.position, 0)
        XCTAssertEqual(session.engine.sessionInfo?.turns, 0)
        XCTAssertEqual(session.engine.sessionInfo?.records, 3)
        XCTAssertEqual(try session.engine.stateBackend?.boundPrefixLength(
            executionID: executionID, position: ExecutionPosition(0)), 3)
        let entries = try XCTUnwrap(session.engine.tokenLedger?.entries(for: executionID))
        XCTAssertEqual(entries.map(\.kind), [.bootstrap, .turn, .restoreMarker])
        XCTAssertEqual(entries.map(\.superseded), [false, true, false])
    }

    func testTargetAheadRejectedBeforeCoordinatorMutation() async throws {
        let session = try await makeSession(gate: AppendGate())
        let beforeRecords = session.engine.coordinator?.recordCount

        do {
            try await session.engine.restoreSession(to: 3)
            XCTFail("restore ahead of committed history should throw")
        } catch {
            assertDivergence(error, contains: "restore target beyond committed history")
        }

        let state = try XCTUnwrap(session.engine.currentState)
        XCTAssertEqual(session.engine.coordinator?.recordCount, beforeRecords)
        XCTAssertEqual(state.position, ExecutionPosition(1))
        XCTAssertEqual(state.lifecycle, .active)
        XCTAssertEqual(session.engine.sessionInfo?.position, 1)
        XCTAssertEqual(session.engine.tokenLedger?.count, 2)
        XCTAssertEqual(try session.engine.stateBackend?.boundPrefixLength(
            executionID: executionID, position: ExecutionPosition(1)), 5)

        // A valid target still works after the rejected read-only precheck.
        session.gate.allow(1)
        try await session.engine.restoreSession(to: 0)
        XCTAssertEqual(session.engine.currentState?.position, ExecutionPosition(0))
    }

    func testStableMarkerAppendFailureLeavesRetryablePartialWindow() async throws {
        let gate = AppendGate()
        let session = try await makeSession(gate: gate)

        do {
            try await session.engine.restoreSession(to: 0)
            XCTFail("stable marker failure should throw")
        } catch {
            assertDivergence(error, contains: "stable marker append failure")
        }

        // Coordinator and physical rebind happened; logical/audit state stayed
        // at the pre-restore commit point.
        let unchanged = try XCTUnwrap(session.engine.currentState)
        XCTAssertEqual(unchanged.position, ExecutionPosition(1))
        XCTAssertEqual(unchanged.lifecycle, .active)
        XCTAssertEqual(session.engine.sessionInfo?.position, 1)
        XCTAssertEqual(session.engine.coordinator?.recordCount, 3)
        XCTAssertEqual(try session.engine.stateBackend?.boundPrefixLength(
            executionID: executionID, position: ExecutionPosition(0)), 3)
        let entries = try XCTUnwrap(session.engine.tokenLedger?.entries(for: executionID))
        XCTAssertEqual(entries.map(\.kind), [.bootstrap, .turn])
        XCTAssertEqual(entries.map(\.superseded), [false, false])

        gate.allow(1)
        try await session.engine.restoreSession(to: 0)
        XCTAssertEqual(session.engine.currentState?.position, ExecutionPosition(0))
        XCTAssertEqual(session.engine.sessionInfo?.position, 0)
        XCTAssertEqual(session.engine.tokenLedger?.count, 3)
    }
}
