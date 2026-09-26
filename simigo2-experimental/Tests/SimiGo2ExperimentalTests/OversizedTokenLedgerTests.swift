import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

/// Token Ledger Gate unit battery — I-L1 (committed-only shapes), I-L2
/// (forward growth within an execution; restore markers may rewind the
/// growth point), and the append-only superseded audit.
final class OversizedTokenLedgerTests: XCTestCase {
    private let exec = ExecutionID("T")

    private func entry(
        _ position: Int, _ kind: OversizedTokenLedgerEntry.Kind, _ prefix: Int
    ) -> OversizedTokenLedgerEntry {
        OversizedTokenLedgerEntry(
            executionID: exec, position: position, kind: kind, prefixLength: prefix
        )
    }

    func testBootstrapThenTurnForwardGrowth() throws {
        let ledger = OversizedTokenLedger()
        try ledger.append(entry(0, .bootstrap, 18))
        try ledger.append(entry(1, .turn, 19))
        XCTAssertEqual(ledger.entries(for: exec).map { $0.kind }, [.bootstrap, .turn])
    }

    func testNonIncreasingTurnRejected() throws {
        let ledger = OversizedTokenLedger()
        try ledger.append(entry(0, .bootstrap, 18))
        // A turn at the bootstrap position is not forward growth.
        XCTAssertThrowsError(try ledger.append(entry(0, .turn, 18)))
        // The rejected entry never became a growth point, so the
        // legitimate turn at position 1 is still accepted.
        try ledger.append(entry(1, .turn, 19))
        XCTAssertEqual(ledger.count, 2)
    }

    func testRestoreMarkerRewindsGrowthPoint() throws {
        let ledger = OversizedTokenLedger()
        try ledger.append(entry(0, .bootstrap, 18))
        try ledger.append(entry(1, .turn, 19))
        // Rewind to the bootstrap position — the committed-only tail is
        // retained and flagged, the marker records the rollback point.
        ledger.markSuperseded(beyond: 0, executionID: exec)
        try ledger.append(entry(0, .restoreMarker, 18))
        // Growth resumes from the rewound point.
        try ledger.append(entry(1, .turn, 19))
        let all = ledger.entries(for: exec)
        XCTAssertEqual(all.map(\.kind), [.bootstrap, .turn, .restoreMarker, .turn])
        XCTAssertEqual(all[1].superseded, true)
        XCTAssertEqual(all[3].superseded, false)
        XCTAssertEqual(ledger.allEntries().count, 4, "append-only: nothing deleted")
    }

    func testRestoreMarkerBeyondCommittedHistoryRejected() throws {
        let ledger = OversizedTokenLedger()
        try ledger.append(entry(0, .bootstrap, 18))
        XCTAssertThrowsError(try ledger.append(entry(3, .restoreMarker, 21)))
    }

    func testRestoreMarkerMayResumeSupersededPosition() throws {
        let ledger = OversizedTokenLedger()
        try ledger.append(entry(0, .bootstrap, 18))
        try ledger.append(entry(1, .turn, 19))
        // Rewind to bootstrap, re-commit the turn (the E5 replay shape)…
        ledger.markSuperseded(beyond: 0, executionID: exec)
        try ledger.append(entry(0, .restoreMarker, 18))
        try ledger.append(entry(1, .turn, 19))
        // …then RESUME the previously committed position — a forward restore
        // is a legitimate marker (undo of a rewind), not forward growth.
        try ledger.append(entry(1, .restoreMarker, 19))
        try ledger.append(entry(2, .turn, 20))
        let all = ledger.entries(for: exec)
        XCTAssertEqual(
            all.map(\.kind),
            [.bootstrap, .turn, .restoreMarker, .turn, .restoreMarker, .turn])
        XCTAssertEqual(all.last?.position, 2)
    }

    func testMarkSupersededRetainsAndFlags() throws {
        let ledger = OversizedTokenLedger()
        try ledger.append(entry(0, .bootstrap, 10))
        try ledger.append(entry(1, .turn, 11))
        try ledger.append(entry(2, .turn, 12))
        ledger.markSuperseded(beyond: 1, executionID: exec)
        let all = ledger.entries(for: exec)
        XCTAssertEqual(all.map(\.superseded), [false, false, true])
        XCTAssertEqual(ledger.allEntries().count, 3)
    }

    func testExecutionsAreIsolated() throws {
        let ledger = OversizedTokenLedger()
        let other = ExecutionID("U")
        try ledger.append(entry(0, .bootstrap, 18))
        try ledger.append(OversizedTokenLedgerEntry(
            executionID: other, position: 0, kind: .bootstrap, prefixLength: 5
        ))
        // The other execution's independent growth point permits its own
        // position 1 while `exec` is also at 1.
        try ledger.append(OversizedTokenLedgerEntry(
            executionID: other, position: 1, kind: .turn, prefixLength: 6
        ))
        XCTAssertEqual(ledger.entries(for: other).count, 2)
        XCTAssertEqual(ledger.entries(for: exec).count, 1)
    }
}
