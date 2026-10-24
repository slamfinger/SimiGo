import XCTest
@testable import SimiGoRuntimeContract

// G3 — THE THREE AXES ARE INDEPENDENT FACTS, NOT ONE BOOLEAN.
//
// `settleEntered` (did the run enter the single-use gate), `bindingConsumed`
// (was the bound prefix actually removed) and `delivery` (generation /
// registration / decode / commit) answer different questions. These tests pin
// each transition separately, including the two cases the old `settled` flag
// could not express:
//   * the consume body was entered but threw -> entered=true, consumed=false;
//   * delivery failed after the consume       -> consumed=true, delivery failed.
//
// G5 — terminal sources are linearized by ONE adjudication domain, not by one
// more read: the settlement gate, the session tombstone and the commit
// transition all enter the arm's `G3Adjudication` (see
// `G3CommitLinearizationTests`). The source precedence stays as the reporting
// rule: gateway latch > session tombstone > settlement. A gateway termination is
// visible even when the session never wrote a tombstone, and it refuses the
// settlement gate.
//
// G4 — cancellation is adjudicated by WHERE it was observed. A cancellation
// after the gate cannot undo the consume; the ledger keeps that fact.
final class G3SettlementAxesTests: XCTestCase {

    final class Boundary: G3ArmCacheBoundary {
        var gatewayReason: String?
        func beginStep() {}
        var isolationAborted: Bool { false }
        var isolationAbortReason: String? { nil }
        var terminatedReason: String? { gatewayReason }
    }

    private struct ConsumeFailed: Error {}

    private func makeSession(
        _ arm: String = "ES+IS"
    ) -> (session: G3ArmCacheSession, boundary: Boundary, ledger: G3RunLedger) {
        let boundary = Boundary()
        let session = G3ArmCacheSession(armID: arm, boundary: boundary)
        let ledger = session.beginRunLedger()
        return (session, boundary, ledger)
    }

    // MARK: 1. A refused gate enters neither axis

    func testRefusedSettlementLeavesBothAxesFalse() {
        let (session, boundary, ledger) = makeSession()
        boundary.gatewayReason = "gateway_stop"
        let settlement = G3RunSettlement(armID: "ES+IS", session: session)
        var consumeCalls = 0

        XCTAssertThrowsError(try settlement.settle { consumeCalls += 1 }) { error in
            XCTAssertEqual(
                error as? G3PerArmCacheError,
                .armTerminated(reason: "gateway_stop"))
        }

        XCTAssertEqual(consumeCalls, 0, "a terminated arm must not enter the consume body")
        let snap = ledger.snapshot
        XCTAssertFalse(snap.settleEntered)
        XCTAssertFalse(snap.bindingConsumed)
        XCTAssertEqual(snap.settlementRefusal, "gateway_stop")
        XCTAssertEqual(snap.delivery, .notEntered)
    }

    // MARK: 2. G5 — the gateway latch alone is a termination

    func testGatewayOnlyTerminationIsVisibleWithoutASessionTombstone() {
        let (session, boundary, _) = makeSession()
        XCTAssertFalse(session.isTerminated, "gateway is still live")

        boundary.gatewayReason = "gateway_stop"

        let snap = session.terminalSnapshot()
        XCTAssertNil(snap.sessionTombstoneReason)
        XCTAssertEqual(snap.gatewayTerminationReason, "gateway_stop")
        XCTAssertEqual(snap.effectiveTerminationReason, "gateway_stop")
        XCTAssertTrue(
            session.isTerminated,
            "the effective predicate must include an independent gateway termination")
        XCTAssertEqual(session.terminalAbortReason, "gateway_stop")
    }

    // MARK: 3. G5 — precedence is explicit and both sources remain visible

    func testGatewayPrecedesSessionTombstoneAndBothRemainVisible() {
        let (session, boundary, _) = makeSession()
        session.terminate(reason: "kv_refused")
        boundary.gatewayReason = "gateway_stop"

        let snap = session.terminalSnapshot()
        XCTAssertEqual(snap.gatewayTerminationReason, "gateway_stop")
        XCTAssertEqual(snap.sessionTombstoneReason, "kv_refused")
        XCTAssertEqual(snap.effectiveTerminationReason, "gateway_stop")
        XCTAssertEqual(
            G3TerminalSnapshot.precedence,
            "gateway_latch>session_tombstone>settlement")
    }

    // MARK: 4. Entered but not consumed

    func testThrowingConsumeRecordsEnteredWithoutConsumed() {
        let (session, _, ledger) = makeSession()
        let settlement = G3RunSettlement(armID: "ES+IS", session: session)

        XCTAssertThrowsError(try settlement.settle { throw ConsumeFailed() })

        let snap = ledger.snapshot
        XCTAssertTrue(snap.settleEntered)
        XCTAssertFalse(snap.bindingConsumed)
        XCTAssertEqual(snap.settlementPhase, .bindingConsumeFailed)
        XCTAssertNotNil(snap.bindingConsumeFailure)
        XCTAssertFalse(snap.isFullyDelivered)
    }

    // MARK: 5. Consumed is independent of delivery

    func testConsumedIsIndependentOfDelivery() throws {
        let (session, _, ledger) = makeSession()
        let settlement = G3RunSettlement(armID: "ES+IS", session: session)

        try settlement.settle { }

        var snap = ledger.snapshot
        XCTAssertTrue(snap.settleEntered)
        XCTAssertTrue(snap.bindingConsumed)
        XCTAssertFalse(
            snap.isFullyDelivered,
            "no delivery stage was recorded; consumption alone is not delivery")

        ledger.recordPhase(.generation, .succeeded("committed=2"))
        ledger.recordPhase(.decode, .succeeded("tokens=2"))
        ledger.recordPhase(.registration, .skipped("no_registrar"))
        ledger.recordPhase(.commit, .succeeded("result_delivered"))
        snap = ledger.snapshot
        XCTAssertTrue(snap.delivery.completed)
        XCTAssertTrue(snap.isFullyDelivered)
    }

    // MARK: 6. G5 — a post-settlement termination does not roll back the consume

    func testPostSettlementTerminationDoesNotUndoConsumption() throws {
        let (session, boundary, ledger) = makeSession()
        let settlement = G3RunSettlement(armID: "ES+IS", session: session)
        var consumed = false

        try settlement.settle {
            consumed = true
            boundary.gatewayReason = "gateway_released"   // lands during the consume
        }

        XCTAssertTrue(consumed)
        let snap = ledger.snapshot
        XCTAssertTrue(snap.settleEntered)
        XCTAssertTrue(snap.bindingConsumed)
        XCTAssertEqual(snap.postSettlementTermination, "gateway_released")
        XCTAssertFalse(
            snap.isFullyDelivered,
            "the termination does not undo the consume, but it does stop delivery")
    }

    // MARK: 7. G4 — post-settlement cancellation keeps the consumed fact

    func testCancellationAfterSettlementKeepsTheConsumedFact() throws {
        let (session, _, ledger) = makeSession()
        let settlement = G3RunSettlement(armID: "ES+IS", session: session)

        try settlement.settle { }
        ledger.recordCancellation(.afterSettlement)
        ledger.recordPhase(.commit, .failed("cancelled_after_settlement"))

        let snap = ledger.snapshot
        XCTAssertTrue(snap.settleEntered)
        XCTAssertTrue(snap.bindingConsumed)
        XCTAssertEqual(snap.cancellation, .afterSettlement)
        XCTAssertEqual(snap.delivery.commit.state, .failed)
        XCTAssertFalse(snap.delivery.completed)
        XCTAssertFalse(snap.isFullyDelivered)
    }

    // MARK: 8. G4 — pre-settlement cancellation never enters the gate

    func testPreSettlementCancellationLeavesBothAxesFalse() {
        let (_, _, ledger) = makeSession()
        ledger.recordCancellation(.beforeSettlement)

        let snap = ledger.snapshot
        XCTAssertFalse(snap.settleEntered)
        XCTAssertFalse(snap.bindingConsumed)
        XCTAssertEqual(snap.cancellation, .beforeSettlement)
        XCTAssertEqual(snap.delivery, .notEntered)
    }

    // MARK: 9. G4 — decode succeeded, commit blocked at the decode boundary

    func testDecodeBoundaryCancellationRecordsSucceededDecodeAndFailedCommit() {
        let (_, _, ledger) = makeSession()
        ledger.markSettleEntered()
        ledger.markBindingConsumed()
        ledger.recordPhase(.generation, .succeeded("committed=1"))
        ledger.recordPhase(.decode, .succeeded("tokens=1"))
        ledger.recordCancellation(.afterDecode)
        ledger.recordPhase(.commit, .failed("cancelled_after_decode"))

        let snap = ledger.snapshot
        XCTAssertEqual(snap.cancellation, .afterDecode)
        XCTAssertEqual(snap.delivery.decode.state, .succeeded)
        XCTAssertEqual(snap.delivery.commit.state, .failed)
        XCTAssertFalse(snap.delivery.completed)
        XCTAssertTrue(snap.bindingConsumed)
    }

    // MARK: 10. A post-consume registration failure is visible, not a clean refusal

    func testPostConsumeRegistrationFailureLeavesConsumedAndDeliveryFailed() throws {
        let (session, _, ledger) = makeSession()
        let settlement = G3RunSettlement(armID: "ES+IS", session: session)

        try settlement.settle { }
        ledger.recordPhase(.generation, .succeeded("committed=1"))
        ledger.recordPhase(.decode, .succeeded("tokens=1"))
        ledger.recordPhase(.registration, .failed("shared_mutable_storage(kv_cache)"))

        let snap = ledger.snapshot
        XCTAssertTrue(snap.settleEntered)
        XCTAssertTrue(snap.bindingConsumed)
        XCTAssertEqual(snap.delivery.registration.state, .failed)
        XCTAssertEqual(snap.delivery.commit.state, .notEntered)
        XCTAssertFalse(snap.delivery.completed)
        XCTAssertFalse(snap.isFullyDelivered)
    }

    // MARK: 11. A decode failure after the consume keeps both facts

    func testPostConsumeDecodeFailureKeepsConsumedAndMarksDecodeFailed() throws {
        let (session, _, ledger) = makeSession()
        let settlement = G3RunSettlement(armID: "ES+IS", session: session)

        try settlement.settle { }
        ledger.recordPhase(.generation, .succeeded("committed=1"))
        ledger.recordPhase(.registration, .skipped("no_registrar"))
        ledger.recordPhase(.decode, .failed("nan_in_logits"))

        let snap = ledger.snapshot
        XCTAssertTrue(snap.settleEntered)
        XCTAssertTrue(snap.bindingConsumed, "the consume is not rolled back by a later failure")
        XCTAssertEqual(snap.delivery.decode.state, .failed)
        XCTAssertEqual(snap.delivery.decode.detail, "nan_in_logits")
        XCTAssertEqual(snap.delivery.commit.state, .notEntered)
        XCTAssertFalse(snap.delivery.completed)
        XCTAssertFalse(snap.isFullyDelivered)
    }
}
