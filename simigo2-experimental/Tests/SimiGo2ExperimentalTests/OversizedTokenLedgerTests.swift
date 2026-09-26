import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

/// Token Ledger Gate unit battery — I-L1 (committed-only shapes), I-L2
/// (forward growth within an execution; restore markers may rewind the
/// growth point), I-L3 (every entry cross-checked against the backend's
/// own binding record), and the append-only superseded audit.
final class OversizedTokenLedgerTests: XCTestCase {
    private let exec = ExecutionID("T")

    /// Independent stand-in for the backend binding record. Deliberately
    /// NOT derived from ledger entries — deriving the authority's answer
    /// from the ledger itself would recreate the self-referential gap the
    /// I-L3 gate closes.
    private final class StubBackendBindings {
        private var lengths: [ExecutionID: [Int: Int]] = [:]

        func bind(_ id: ExecutionID, _ position: Int, _ prefixLength: Int) {
            lengths[id, default: [:]][position] = prefixLength
        }

        func boundPrefixLength(_ id: ExecutionID, _ position: Int) throws -> Int {
            guard let positionTable = lengths[id], let length = positionTable[position] else {
                throw ExecutionStateBackendError.noBoundRepresentation(id)
            }
            return length
        }
    }

    /// Mirrors every real commit sequence: the physical rebind lands in the
    /// backend FIRST, the ledger append (with its I-L3 cross-check) second.
    private func commit(
        _ e: OversizedTokenLedgerEntry,
        ledger: OversizedTokenLedger,
        bindings: StubBackendBindings
    ) throws {
        bindings.bind(e.executionID, e.position, e.prefixLength)
        try ledger.append(e)
    }

    private func makeLedger(_ bindings: StubBackendBindings) -> OversizedTokenLedger {
        OversizedTokenLedger { id, position in
            try bindings.boundPrefixLength(id, position)
        }
    }

    private func entry(
        _ position: Int, _ kind: OversizedTokenLedgerEntry.Kind, _ prefix: Int
    ) -> OversizedTokenLedgerEntry {
        OversizedTokenLedgerEntry(
            executionID: exec, position: position, kind: kind, prefixLength: prefix
        )
    }

    private func assertDivergence(_ error: Error) {
        guard case OversizedEngineError.residencyDivergence = error else {
            return XCTFail("expected residencyDivergence, got \(error)")
        }
    }

    func testBootstrapThenTurnForwardGrowth() throws {
        let bindings = StubBackendBindings()
        let ledger = makeLedger(bindings)
        try commit(entry(0, .bootstrap, 18), ledger: ledger, bindings: bindings)
        try commit(entry(1, .turn, 19), ledger: ledger, bindings: bindings)
        XCTAssertEqual(ledger.entries(for: exec).map { $0.kind }, [.bootstrap, .turn])
    }

    func testNonIncreasingTurnRejected() throws {
        let bindings = StubBackendBindings()
        let ledger = makeLedger(bindings)
        try commit(entry(0, .bootstrap, 18), ledger: ledger, bindings: bindings)
        // A turn at the bootstrap position is not forward growth.
        bindings.bind(exec, 0, 18)
        XCTAssertThrowsError(try ledger.append(entry(0, .turn, 18)))
        // The rejected entry never became a growth point, so the
        // legitimate turn at position 1 is still accepted.
        try commit(entry(1, .turn, 19), ledger: ledger, bindings: bindings)
        XCTAssertEqual(ledger.count, 2)
    }

    func testRestoreMarkerRewindsGrowthPoint() throws {
        let bindings = StubBackendBindings()
        let ledger = makeLedger(bindings)
        try commit(entry(0, .bootstrap, 18), ledger: ledger, bindings: bindings)
        try commit(entry(1, .turn, 19), ledger: ledger, bindings: bindings)
        // Rewind to the bootstrap position — the committed-only tail is
        // retained and flagged, the marker records the rollback point.
        // The backend's binding is back at position 0 with 18 tokens
        // (coordinator.restore re-binds the historical representation).
        bindings.bind(exec, 0, 18)
        ledger.markSuperseded(beyond: 0, executionID: exec)
        try ledger.append(entry(0, .restoreMarker, 18))
        // Growth resumes from the rewound point.
        try commit(entry(1, .turn, 19), ledger: ledger, bindings: bindings)
        let all = ledger.entries(for: exec)
        XCTAssertEqual(all.map(\.kind), [.bootstrap, .turn, .restoreMarker, .turn])
        XCTAssertEqual(all[1].superseded, true)
        XCTAssertEqual(all[3].superseded, false)
        XCTAssertEqual(ledger.allEntries().count, 4, "append-only: nothing deleted")
    }

    func testRestoreMarkerBeyondCommittedHistoryRejected() throws {
        let bindings = StubBackendBindings()
        let ledger = makeLedger(bindings)
        try commit(entry(0, .bootstrap, 18), ledger: ledger, bindings: bindings)
        bindings.bind(exec, 3, 21)
        XCTAssertThrowsError(try ledger.append(entry(3, .restoreMarker, 21)))
    }

    func testRestoreMarkerMayResumeSupersededPosition() throws {
        let bindings = StubBackendBindings()
        let ledger = makeLedger(bindings)
        try commit(entry(0, .bootstrap, 18), ledger: ledger, bindings: bindings)
        try commit(entry(1, .turn, 19), ledger: ledger, bindings: bindings)
        // Rewind to bootstrap, re-commit the turn (the E5 replay shape)…
        bindings.bind(exec, 0, 18)
        ledger.markSuperseded(beyond: 0, executionID: exec)
        try ledger.append(entry(0, .restoreMarker, 18))
        try commit(entry(1, .turn, 19), ledger: ledger, bindings: bindings)
        // …then RESUME the previously committed position — a forward restore
        // is a legitimate marker (undo of a rewind), not forward growth.
        bindings.bind(exec, 1, 19)
        try ledger.append(entry(1, .restoreMarker, 19))
        try commit(entry(2, .turn, 20), ledger: ledger, bindings: bindings)
        let all = ledger.entries(for: exec)
        XCTAssertEqual(
            all.map(\.kind),
            [.bootstrap, .turn, .restoreMarker, .turn, .restoreMarker, .turn])
        XCTAssertEqual(all.last?.position, 2)
    }

    func testMarkSupersededRetainsAndFlags() throws {
        let bindings = StubBackendBindings()
        let ledger = makeLedger(bindings)
        try commit(entry(0, .bootstrap, 10), ledger: ledger, bindings: bindings)
        try commit(entry(1, .turn, 11), ledger: ledger, bindings: bindings)
        try commit(entry(2, .turn, 12), ledger: ledger, bindings: bindings)
        ledger.markSuperseded(beyond: 1, executionID: exec)
        let all = ledger.entries(for: exec)
        XCTAssertEqual(all.map(\.superseded), [false, false, true])
        XCTAssertEqual(ledger.allEntries().count, 3)
    }

    func testExecutionsAreIsolated() throws {
        let bindings = StubBackendBindings()
        let ledger = makeLedger(bindings)
        let other = ExecutionID("U")
        try commit(entry(0, .bootstrap, 18), ledger: ledger, bindings: bindings)
        try commit(
            OversizedTokenLedgerEntry(
                executionID: other, position: 0, kind: .bootstrap, prefixLength: 5),
            ledger: ledger, bindings: bindings)
        // The other execution's independent growth point permits its own
        // position 1 while `exec` is also at 1.
        try commit(
            OversizedTokenLedgerEntry(
                executionID: other, position: 1, kind: .turn, prefixLength: 6),
            ledger: ledger, bindings: bindings)
        XCTAssertEqual(ledger.entries(for: other).count, 2)
        XCTAssertEqual(ledger.entries(for: exec).count, 1)
    }

    // MARK: I-L3 — the cross-check against the backend binding record

    func testIL3PrefixMismatchRejected() throws {
        let bindings = StubBackendBindings()
        let ledger = makeLedger(bindings)
        // Backend really bound 18 tokens; the entry claims 19.
        bindings.bind(exec, 0, 18)
        XCTAssertThrowsError(try ledger.append(entry(0, .bootstrap, 19)), "", assertDivergence)
        // The rejected entry was never recorded.
        XCTAssertEqual(ledger.count, 0)
        // The honest entry for the same binding is still accepted.
        try ledger.append(entry(0, .bootstrap, 18))
        XCTAssertEqual(ledger.count, 1)
    }

    func testIL3MissingBindingRejected() throws {
        let bindings = StubBackendBindings()
        let ledger = makeLedger(bindings)
        // No backend binding at all — the ledger must fail loudly, not
        // record an unverifiable claim.
        XCTAssertThrowsError(try ledger.append(entry(0, .bootstrap, 18)), "", assertDivergence)
        XCTAssertEqual(ledger.count, 0)
    }

    func testIL3BindingPositionDriftRejected() throws {
        let bindings = StubBackendBindings()
        let ledger = makeLedger(bindings)
        // Backend bound at position 1 while the entry claims position 0 —
        // the position-mismatch guard must surface as divergence.
        bindings.bind(exec, 1, 18)
        XCTAssertThrowsError(try ledger.append(entry(0, .bootstrap, 18)), "", assertDivergence)
        XCTAssertEqual(ledger.count, 0)
    }

    func testIL3RestoreMarkerCrossChecked() throws {
        let bindings = StubBackendBindings()
        let ledger = makeLedger(bindings)
        try commit(entry(0, .bootstrap, 18), ledger: ledger, bindings: bindings)
        try commit(entry(1, .turn, 26), ledger: ledger, bindings: bindings)
        // Rewind: the backend re-bound the historical prefix (18) at
        // position 0; a marker claiming anything else must throw.
        bindings.bind(exec, 0, 18)
        ledger.markSuperseded(beyond: 0, executionID: exec)
        XCTAssertThrowsError(try ledger.append(entry(0, .restoreMarker, 26)), "", assertDivergence)
        XCTAssertEqual(ledger.allEntries().last?.kind, .turn, "marker not recorded")
        try ledger.append(entry(0, .restoreMarker, 18))
        XCTAssertEqual(ledger.allEntries().last?.kind, .restoreMarker)
    }
}
