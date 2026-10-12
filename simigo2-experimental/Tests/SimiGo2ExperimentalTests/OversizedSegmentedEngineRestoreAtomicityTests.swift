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
            backendBoundPrefixLength: fixture.backendBoundPrefixLength)
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

        gate.allow(1)
        try await session.engine.restoreSession(to: 0)
        XCTAssertEqual(session.currentState()?.position, ExecutionPosition(0))
        XCTAssertEqual(session.engine.sessionInfo?.position, 0)
        XCTAssertEqual(session.coordinatorRecordCount(), beforeRecords + 1)
        XCTAssertEqual(session.engine.tokenLedger?.count, 3)
    }
}
