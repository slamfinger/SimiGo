import XCTest
@testable import SimiGo

/// Issue #15 R2-B: four-quadrant acceptance plus the two protection classes
/// for the slot-progress monitor. All sequences are synthetic: the monitor is
/// a pure state machine over observation samples, so the scenarios exercise
/// exactly the decision table without an engine.
final class SlotProgressMonitorTests: XCTestCase {

    private let windowMS: UInt64 = 10_000
    private let tickMS: UInt64 = 500

    private func makeMonitor() -> SlotProgressMonitor {
        SlotProgressMonitor(config: .init(candidateWindowMS: windowMS))
    }

    private func obs(_ tMS: UInt64, task: Int? = 1, processing: Bool = true,
                     np: Int? = nil, total: Int? = nil, nd: Int? = nil,
                     slot: Int = 0, gen: UInt64 = 1) -> SlotProgressMonitor.Observation {
        .init(slotID: slot, engineGeneration: gen, idTask: task,
              isProcessing: processing, promptProcessed: np,
              promptTotal: total, decoded: nd, observedAtMonotonicMS: tMS)
    }

    // MARK: Quadrant 1 — normal progression (passthrough profile)

    func testNormalProgressionNeverReportsCandidateStall() {
        let m = makeMonitor()
        var t: UInt64 = 0
        // prefill: prompt counter climbing
        var states: [SlotProgressMonitor.State] = []
        for np in [100, 400, 900, 1600, 2600, 3416] {
            t += tickMS
            states.append(m.observe(obs(t, np: np, total: 3416)).state)
        }
        // prefill->decode boundary: 3 boundary ticks (well under 10s)
        for _ in 0..<3 {
            t += tickMS
            states.append(m.observe(obs(t, np: 3416, total: 3416)).state)
        }
        // decode: token counter climbing
        for nd in [1, 4, 9, 16, 25, 40] {
            t += tickMS
            states.append(m.observe(obs(t, np: 3416, total: 3416, nd: nd)).state)
        }
        XCTAssertFalse(states.contains(.candidateStall), "normal load must not stall")
        XCTAssertTrue(states.contains(.progressing))
        XCTAssertTrue(states.contains(.phaseTransitionOrUnknown),
                      "the boundary window must be labelled as a transition")
    }

    // MARK: Quadrant 2 — frozen counters (candidate detection)

    func testFrozenCountersReachCandidateStallAfterWindow() {
        let m = makeMonitor()
        var t: UInt64 = 0
        // establish a decode baseline
        t += tickMS
        _ = m.observe(obs(t, np: 3416, total: 3416, nd: 1))
        // frozen: same task, busy, counters never move
        var sawObserving = false
        var sawCandidate = false
        for _ in 0..<30 {  // 15 s of ticks against a 10 s window
            t += tickMS
            let v = m.observe(obs(t, np: 3416, total: 3416, nd: 1))
            if v.state == .observingNoProgress { sawObserving = true }
            if v.state == .candidateStall { sawCandidate = true }
            if sawCandidate { break }
        }
        XCTAssertTrue(sawObserving, "static ticks must report observing_no_progress first")
        XCTAssertTrue(sawCandidate, "frozen counters must reach candidate_stall after the window")
        XCTAssertLessThan(t, 4 * windowMS, "detection must not need an endless window")
    }

    // MARK: Quadrant 3 — id_task change resets the baseline

    func testIdTaskChangeResetsBaselineWithoutInheritingStaticTime() {
        let m = makeMonitor()
        var t: UInt64 = 0
        // task 1 goes static for 8 s (observing, under the window)
        for _ in 0..<16 {
            t += tickMS
            _ = m.observe(obs(t, task: 1, np: 3416, total: 3416, nd: 7))
        }
        // task 2 begins: the baseline must reset, static time must not carry
        t += tickMS
        let v = m.observe(obs(t, task: 2, np: 3416, total: 3416, nd: 0))
        XCTAssertEqual(v.state, .baselineReset)
        XCTAssertNil(v.noProgressMS)
        // the new task's static run starts from its own first tick
        t += tickMS
        let v2 = m.observe(obs(t, task: 2, np: 3416, total: 3416, nd: 0))
        XCTAssertEqual(v2.state, .observingNoProgress)
        XCTAssertEqual(v2.noProgressMS ?? 0, tickMS,
                       "static time must be measured from the new task's baseline")
    }

    // MARK: Quadrant 4 — phase transitions and mixed ticks

    func testMixedTickIsOneProgressWithMixedPhase() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, np: 100, total: 3416))
        t += tickMS
        let v = m.observe(obs(t, np: 640, total: 3416, nd: 1))
        XCTAssertEqual(v.state, .progressing)
        XCTAssertEqual(v.phase, .mixed)
    }

    func testBoundaryWindowIsTransitionThenAccumulates() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, np: 3416, total: 3416, nd: 3))
        t += tickMS
        _ = m.observe(obs(t, np: 3416, total: 3416, nd: nil))
        var sawTransition = false
        var sawCandidate = false
        for _ in 0..<26 {  // 13 s against a 10 s window
            t += tickMS
            let v = m.observe(obs(t, np: 3416, total: 3416, nd: nil))
            if v.state == .phaseTransitionOrUnknown { sawTransition = true }
            if v.state == .candidateStall { sawCandidate = true }
        }
        XCTAssertTrue(sawTransition, "the boundary window must be labelled phase_transition_or_unknown")
        XCTAssertTrue(sawCandidate, "a boundary window exceeding the candidate window must be reported")
    }

    // MARK: Protection — missing counters are unobservable, never stalls

    func testMissingCountersAreUnobservableAndBlockCandidateStall() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, np: 3416, total: 3416, nd: 5))
        // counters go missing for 12 s (past the window)
        for _ in 0..<24 {
            t += tickMS
            let v = m.observe(obs(t, np: nil, total: nil, nd: nil))
            XCTAssertEqual(v.state, .unobservable)
        }
        // counters return unchanged: the run must still be observing, and the
        // unobservable-polluted span must NOT become a candidate stall
        var sawCandidate = false
        for _ in 0..<4 {
            t += tickMS
            let v = m.observe(obs(t, np: 3416, total: 3416, nd: 5))
            if v.state == .candidateStall { sawCandidate = true }
            XCTAssertNotEqual(v.state, .unobservable)
        }
        XCTAssertFalse(sawCandidate,
                       "a span containing unobservable samples must not be declared a stall")
    }

    // MARK: Protection — counter regression re-baselines, never stalls

    func testCounterRegressionRebaselinesInsteadOfStalling() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, np: 3000, total: 3416))
        t += tickMS
        let v = m.observe(obs(t, np: 1200, total: 3416))
        XCTAssertEqual(v.state, .baselineReset)
        // subsequent static ticks measure from the new baseline
        t += tickMS
        let v2 = m.observe(obs(t, np: 1200, total: 3416))
        XCTAssertEqual(v2.state, .observingNoProgress)
        XCTAssertEqual(v2.noProgressMS ?? 0, tickMS)
    }

    // MARK: Boundaries — idle and engine generation

    func testIdleSlotResetsBaseline() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, np: 3416, total: 3416, nd: 9))
        t += tickMS
        let v = m.observe(obs(t, task: nil, processing: false, np: 0, nd: nil))
        XCTAssertEqual(v.state, .baselineReset)
        // a fresh task afterwards starts clean
        t += tickMS
        let v2 = m.observe(obs(t, task: 2, np: 50, total: 1000))
        XCTAssertEqual(v2.state, .progressing, "baseline established")
    }

    func testEngineGenerationChangeResetsEverything() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, np: 3416, total: 3416, nd: 9, gen: 1))
        t += tickMS
        let v = m.observe(obs(t, np: 3416, total: 3416, nd: 9, gen: 2))
        XCTAssertEqual(v.state, .baselineReset)
        t += tickMS
        let v2 = m.observe(obs(t, np: 3416, total: 3416, nd: 10, gen: 2))
        XCTAssertEqual(v2.state, .progressing)
    }

    func testObserveAbsenceResetsBaseline() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, np: 3416, total: 3416, nd: 9))
        let v = m.observeAbsence(slotID: 0, engineGeneration: 1)
        XCTAssertEqual(v?.state, .baselineReset)
        XCTAssertNil(m.observeAbsence(slotID: 0, engineGeneration: 1),
                     "absence without a baseline reports nothing")
    }
}
