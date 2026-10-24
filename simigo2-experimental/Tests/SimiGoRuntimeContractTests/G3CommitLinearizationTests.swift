// SPDX-License-Identifier: MIT

// G5 — TERMINATION AND COMMIT ARE LINEARIZED BY ONE MECHANISM, NOT BY ONE MORE READ.
//
// The reviewer's objection was specific and correct: a pre-commit check is two
// statements — `guard terminal == nil` and then `commit()` — and a termination
// that lands between them is invisible to the commit while being real. Passing
// tests cannot rule that out, because whether it happens is a scheduling
// accident. This suite pins the mechanism that replaced the check:
//
//   * settlement, every termination latch, and the commit transition all enter
//     ONE `G3Adjudication` domain (the same recursive lock object);
//   * a termination therefore either happens BEFORE the commit region (the commit
//     refuses and the reason is preserved) or AFTER it (the commit stands, the
//     consumed fact is NOT rolled back, and the latch itself files the
//     termination as post-settlement — the mechanism records it, nobody samples it);
//   * the run's cancellation cutoff IS the commit region; a cancellation observed
//     behind it is recorded and changes nothing;
//   * a boundary that does not adopt the domain is refused fail-closed, because
//     its latch would not be serialized against the commit.
//
// Model-free by construction: the boundary is a stand-in that copies the
// production gateway's protocol (domain first, then its own latch lock). No MLX,
// no model, no G3 execution evidence is claimed here.

import Foundation
import SimiGoRuntimeContract
import XCTest

final class G3CommitLinearizationTests: XCTestCase {

    // MARK: Fakes

    /// A boundary that behaves like `MLXKVCacheBoundary` + its gateway regarding
    /// termination: it adopts the arm's domain, writes its latch INSIDE the
    /// domain, and reports the latched reason back from inside the domain.
    private final class AdjudicatingBoundary: G3ArmCacheBoundary, @unchecked Sendable {
        private let latchLock = NSLock()
        private var _reason: String?
        private var _domain: G3Adjudication?
        private var _report: (@Sendable (String) -> Void)?
        private(set) var adoptionCalls = 0

        func beginStep() {}
        var isolationAborted: Bool { terminatedReason != nil }
        var isolationAbortReason: String? { terminatedReason }
        var terminatedReason: String? {
            latchLock.lock(); defer { latchLock.unlock() }
            return _reason
        }

        @discardableResult
        func adoptTerminationAdjudication(
            _ domain: G3Adjudication, report: @escaping @Sendable (String) -> Void
        ) -> Bool {
            domain.adjudicate {
                latchLock.lock()
                _domain = domain
                _report = report
                adoptionCalls += 1
                let existing = _reason
                latchLock.unlock()
                if let existing { report(existing) }
            }
            return true
        }

        private var domainSnapshot: G3Adjudication? {
            latchLock.lock(); defer { latchLock.unlock() }
            return _domain
        }

        /// The production-shaped latch entry: domain, then latch lock, then report.
        /// Returns true if THIS call was the one that latched the arm.
        @discardableResult
        func latch(reason: String) -> Bool {
            guard let domain = domainSnapshot else { return false }
            return domain.adjudicate {
                latchLock.lock()
                if _reason != nil {
                    latchLock.unlock()
                    return false
                }
                _reason = reason
                let report = _report
                latchLock.unlock()
                report?(reason)
                return true
            }
        }
    }

    /// A boundary that does NOT adopt the domain (the protocol default).
    private final class SilentBoundary: G3ArmCacheBoundary {
        func beginStep() {}
        var isolationAborted: Bool { false }
        var isolationAbortReason: String? { nil }
    }

    private struct ConsumeFailed: Error {}

    /// Ordered entry/exit journal shared by the racing threads. Non-overlapping
    /// intervals give a provable happens-before relation; overlapping intervals
    /// leave the order genuinely undecided and both outcomes are allowed.
    private final class Journal: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String] = []
        func append(_ entry: String) {
            lock.lock(); entries.append(entry); lock.unlock()
        }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return entries }
        func index(of entry: String) -> Int? { all.firstIndex(of: entry) }
    }

    // MARK: Harness

    /// A settled arm: settlement entered, binding consumed, generation/decode
    /// succeeded, commit still pending. This is the state a termination and a
    /// commit can genuinely race over.
    private func settledArm(
        _ boundary: AdjudicatingBoundary, arm: String = "ES+IS"
    ) throws -> (session: G3ArmCacheSession, ledger: G3RunLedger) {
        let session = G3ArmCacheSession(armID: arm, boundary: boundary)
        let ledger = session.beginRunLedger()
        let settlement = G3RunSettlement(armID: arm, session: session)
        try settlement.settle { }
        ledger.recordPhase(.generation, .succeeded("committed=1"))
        ledger.recordPhase(.registration, .skipped("no_registrar"))
        ledger.recordPhase(.decode, .succeeded("tokens=1"))
        XCTAssertTrue(ledger.snapshot.bindingConsumed)
        return (session, ledger)
    }

    // MARK: 1. Scenario "termination before commit"

    func testTerminationBeforeCommitRefusesAndPreservesReason() throws {
        let boundary = AdjudicatingBoundary()
        let (session, ledger) = try settledArm(boundary)
        XCTAssertTrue(boundary.latch(reason: "gateway_stop"))

        let outcome = try session.commitDelivery(isCancelled: { false }, finalize: {})

        XCTAssertEqual(outcome, .refusedTermination(reason: "gateway_stop"))
        let snap = ledger.snapshot
        XCTAssertEqual(snap.delivery.commit.state, .failed)
        XCTAssertEqual(snap.postSettlementTermination, "gateway_stop")
        XCTAssertTrue(snap.bindingConsumed, "the consume is a fact and is not rolled back")
        XCTAssertFalse(snap.isFullyDelivered)
    }

    // MARK: 2. Scenario "commit before termination" — recorded by the mechanism

    func testTerminationAfterCommitKeepsTheCommittedFactAndIsFiledByTheLatchItself() throws {
        let boundary = AdjudicatingBoundary()
        let (session, ledger) = try settledArm(boundary)

        let outcome = try session.commitDelivery(isCancelled: { false }, finalize: {})
        XCTAssertEqual(outcome, .committed)
        var snap = ledger.snapshot
        XCTAssertTrue(snap.delivery.commit.state == .succeeded)
        XCTAssertNil(snap.postSettlementTermination)
        XCTAssertTrue(snap.isFullyDelivered, "before the late termination there is a clean run")

        // No re-read, no sampling, no report pass: the latch records it itself.
        XCTAssertTrue(boundary.latch(reason: "late_gateway_stop"))
        snap = ledger.snapshot
        XCTAssertEqual(snap.postSettlementTermination, "late_gateway_stop")
        XCTAssertEqual(snap.delivery.commit.state, .succeeded, "the commit is not undone")
        XCTAssertTrue(snap.bindingConsumed)
        XCTAssertFalse(
            snap.isFullyDelivered,
            "protocol: a termination after the commit keeps the facts but disqualifies "
            + "the run from clean evidence")
    }

    // MARK: 3. Scenario "concurrent" — one adjudication, exactly one winner

    func testConcurrentTerminationAndCommitIsAlwaysClassified() throws {
        var committed = 0
        var refused = 0
        let iterations = 240

        for i in 0..<iterations {
            let boundary = AdjudicatingBoundary()
            let (session, ledger) = try settledArm(boundary)
            let journal = Journal()
            let start = DispatchSemaphore(value: 0)
            let done = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var outcome = G3ArmCacheSession.G3CommitOutcome
                .refusedBoundaryNotAdjudicating
            nonisolated(unsafe) var latched = false

            // Bias the head start alternately so BOTH interleavings actually occur.
            let delayLatch = i % 3 == 0 ? 200 : 0
            let delayCommit = i % 3 == 1 ? 200 : 0

            let latchThread = Thread {
                start.wait()
                if delayLatch > 0 { usleep(UInt32(delayLatch)) }
                journal.append("latch:enter")
                latched = boundary.latch(reason: "race_stop")
                journal.append("latch:exit")
                done.signal()
            }
            let commitThread = Thread {
                start.wait()
                if delayCommit > 0 { usleep(UInt32(delayCommit)) }
                journal.append("commit:enter")
                do {
                    outcome = try session.commitDelivery(
                        isCancelled: { false }, finalize: {})
                } catch {
                    XCTFail("commitDelivery threw \(error)")
                }
                journal.append("commit:exit")
                done.signal()
            }
            latchThread.start()
            commitThread.start()
            start.signal(); start.signal()
            done.wait(); done.wait()

            let snap = ledger.snapshot
            XCTAssertTrue(latched, "a fresh arm always accepts the first latch")
            // No termination is ever lost: the ledger knows about it either way.
            XCTAssertEqual(snap.postSettlementTermination, "race_stop", "iteration \(i)")
            XCTAssertTrue(snap.bindingConsumed, "iteration \(i)")
            XCTAssertFalse(snap.isFullyDelivered, "a raced arm is never clean evidence")

            switch outcome {
            case .committed:
                committed += 1
                XCTAssertEqual(snap.delivery.commit.state, .succeeded, "iteration \(i)")
            case .refusedTermination(let reason):
                refused += 1
                XCTAssertEqual(reason, "race_stop", "iteration \(i)")
                XCTAssertEqual(snap.delivery.commit.state, .failed, "iteration \(i)")
                XCTAssertEqual(
                    snap.delivery.commit.detail,
                    "terminated_at_commit_cutoff:race_stop", "iteration \(i)")
            default:
                XCTFail("iteration \(i): unclassified commit outcome \(outcome)")
            }

            // The two brackets may overlap legitimately: they include the time each
            // participant spent WAITING to enter the domain. What is provable is the
            // happens-before case: a latch that had already finished when the commit
            // attempted can never be missed by the commit.
            if outcome == .committed,
               let exitIdx = journal.index(of: "latch:exit"),
               let enterIdx = journal.index(of: "commit:enter") {
                XCTAssertGreaterThan(
                    exitIdx, enterIdx,
                    "iteration \(i) journal=\(journal.all): a termination that "
                    + "happened-before the commit region was missed")
            }
            if let exitIdx = journal.index(of: "latch:exit"),
               let enterIdx = journal.index(of: "commit:enter"),
               exitIdx < enterIdx {
                XCTAssertEqual(
                    outcome, .refusedTermination(reason: "race_stop"),
                    "iteration \(i) journal=\(journal.all): the latch finished before "
                    + "the commit region opened, so the commit had to refuse")
            }
        }

        XCTAssertGreaterThan(committed, 0, "the commit must win at least once")
        XCTAssertGreaterThan(refused, 0, "the termination must win at least once")
        XCTAssertEqual(committed + refused, iterations)
    }

    // MARK: 4. The exclusion is real, not a favourable interleaving

    func testDomainHeldByOneParticipantBlocksTheOther() throws {
        let boundary = AdjudicatingBoundary()
        let (session, _) = try settledArm(boundary)
        let inside = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let closed = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var enteredWhileHeld = false

        let holder = Thread {
            _ = try? session.commitDelivery(isCancelled: { false }, finalize: {
                inside.signal()
                release.wait()
            })
            closed.signal()
        }
        holder.start()
        inside.wait()
        // While the commit region is open, nobody else may enter the domain.
        _ = session.adjudication.tryAdjudicate { enteredWhileHeld = true }
        XCTAssertFalse(
            enteredWhileHeld,
            "a second participant entered while the commit region held the domain")
        release.signal()
        closed.wait()
        nonisolated(unsafe) var enteredAfterRelease = false
        _ = session.adjudication.tryAdjudicate { enteredAfterRelease = true }
        XCTAssertTrue(
            enteredAfterRelease,
            "the domain must be free again once the region closed")
    }

    // MARK: 5. A non-adopting boundary cannot claim a linearization

    func testBoundaryThatDoesNotAdoptTheDomainIsRefusedFailClosed() throws {
        let session = G3ArmCacheSession(armID: "ES+IS", boundary: SilentBoundary())
        let ledger = session.beginRunLedger()
        XCTAssertFalse(session.boundaryAdoptsAdjudication)

        let outcome = try session.commitDelivery(isCancelled: { false }, finalize: {})

        XCTAssertEqual(outcome, .refusedBoundaryNotAdjudicating)
        XCTAssertEqual(ledger.snapshot.delivery.commit.state, .failed)
        XCTAssertEqual(ledger.snapshot.delivery.commit.detail, "boundary_not_adjudicating")
        XCTAssertFalse(ledger.snapshot.isFullyDelivered)
    }

    // MARK: 6. The cancellation cutoff IS the commit region

    func testCancellationAtTheCommitCutoffRefusesTheCommit() throws {
        let boundary = AdjudicatingBoundary()
        let (session, ledger) = try settledArm(boundary)

        let outcome = try session.commitDelivery(isCancelled: { true }, finalize: {})

        XCTAssertEqual(outcome, .refusedCancellation)
        let snap = ledger.snapshot
        XCTAssertEqual(snap.cancellation, .atCommitCutoff)
        XCTAssertEqual(snap.delivery.commit.state, .failed)
        XCTAssertEqual(snap.delivery.commit.detail, "cancelled_at_commit_cutoff")
        XCTAssertTrue(snap.bindingConsumed, "the consume happened before the cutoff")
    }

    func testCancellationObservedAfterTheCutoffDoesNotUndoTheDelivery() throws {
        let boundary = AdjudicatingBoundary()
        let (session, ledger) = try settledArm(boundary)
        XCTAssertEqual(
            try session.commitDelivery(isCancelled: { false }, finalize: {}), .committed)

        // Behind the cutoff a sample is only an observation, never an un-commit.
        ledger.recordCancellation(.afterCommitCutoff, detail: "observed_after_cutoff")
        let snap = ledger.snapshot
        XCTAssertEqual(snap.cancellation, .afterCommitCutoff)
        XCTAssertEqual(snap.delivery.commit.state, .succeeded)
        XCTAssertTrue(snap.delivery.completed)
        XCTAssertTrue(snap.isFullyDelivered)
        XCTAssertTrue(snap.transitions.contains("cancellation=afterCommitCutoff:observed_after_cutoff"))
    }

    // MARK: 7. The gate itself is adjudicated against a racing latch

    func testSettlementGateAndLatchRaceIsAlwaysClassified() throws {
        var settled = 0
        var refused = 0
        for i in 0..<160 {
            let boundary = AdjudicatingBoundary()
            let session = G3ArmCacheSession(armID: "ES+IS", boundary: boundary)
            let ledger = session.beginRunLedger()
            let settlement = G3RunSettlement(armID: "ES+IS", session: session)
            let start = DispatchSemaphore(value: 0)
            let done = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var threw: Error?
            nonisolated(unsafe) var consumeCalls = 0
            let delayLatch = i % 2 == 0 ? 100 : 0

            let latchThread = Thread {
                start.wait()
                if delayLatch > 0 { usleep(UInt32(delayLatch)) }
                boundary.latch(reason: "gate_race_stop")
                done.signal()
            }
            let settleThread = Thread {
                start.wait()
                do {
                    try settlement.settle { consumeCalls += 1 }
                } catch {
                    threw = error
                }
                done.signal()
            }
            latchThread.start(); settleThread.start()
            start.signal(); start.signal()
            done.wait(); done.wait()

            let snap = ledger.snapshot
            XCTAssertEqual(consumeCalls, threw == nil ? 1 : 0, "iteration \(i)")
            if threw == nil {
                settled += 1
                XCTAssertTrue(snap.settleEntered)
                XCTAssertTrue(snap.bindingConsumed)
                // A consume is never rolled back by the latch that arrived after it.
                XCTAssertEqual(snap.postSettlementTermination, "gate_race_stop")
            } else {
                refused += 1
                guard case .armTerminated(let reason)? = threw as? G3PerArmCacheError else {
                    XCTFail("iteration \(i): unexpected \(String(describing: threw))")
                    continue
                }
                XCTAssertEqual(reason, "gate_race_stop")
                XCTAssertFalse(snap.settleEntered)
                XCTAssertFalse(snap.bindingConsumed)
                XCTAssertEqual(snap.settlementRefusal, "gate_race_stop")
            }
        }
        XCTAssertGreaterThan(settled, 0)
        XCTAssertGreaterThan(refused, 0)
    }

    // MARK: 8. A consume that throws keeps "entered" and "not consumed" distinct

    func testThrowingConsumeInsideTheDomainKeepsTheAxesDistinct() throws {
        let boundary = AdjudicatingBoundary()
        let session = G3ArmCacheSession(armID: "ES+IS", boundary: boundary)
        let ledger = session.beginRunLedger()
        let settlement = G3RunSettlement(armID: "ES+IS", session: session)

        XCTAssertThrowsError(try settlement.settle { throw ConsumeFailed() })

        let snap = ledger.snapshot
        XCTAssertTrue(snap.settleEntered)
        XCTAssertFalse(snap.bindingConsumed)
        XCTAssertNotNil(snap.bindingConsumeFailure)
        XCTAssertEqual(snap.settlementPhase, .bindingConsumeFailed)
        // The production body throws out of `settle` in this case, so the commit
        // region is never reached: no delivery stage may be recorded.
        XCTAssertFalse(snap.delivery.completed)
        XCTAssertFalse(snap.isFullyDelivered)
    }
}
