import XCTest
@testable import SimiGo

/// Issue #15 R2-B: four-quadrant acceptance plus the two protection classes
/// for the slot-progress monitor, and the P1–P7 audit regressions (review
/// 2026-11-08). All sequences are synthetic: the monitor is a pure state
/// machine over observation samples, so the scenarios exercise exactly the
/// decision table without an engine.
///
/// Phase-correction fixtures (owner ruling 2026-11-08):
/// - Phase follows n_decoded only: known zero = pre-decode, positive =
///   decode, missing = no phase claim. n_prompt_tokens (total) is never a
///   phase input; live b11720 lets it grow during decode and carry a stale
///   value at a new task's start.
/// - zero -> zero -> positive confirms the boundary exactly once, on the
///   first positive tick. A first positive sample with no preceding zero is
///   decode with an UNKNOWN boundary (phaseTransitionOrUnknown on a fresh
///   task baseline; baselineReset carrying phase decode when a generation or
///   task baseline is established), never a fabricated transition.
/// - Candidate-stall detection remains counter-advance based and is not
///   part of this phase ruling.
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

    private func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    // MARK: Quadrant 1 — normal progression (passthrough profile)

    func testNormalProgressionNeverReportsCandidateStall() {
        let m = makeMonitor()
        var t: UInt64 = 0
        // pre-decode: the prompt counter climbs while n_decoded stays a
        // known zero (live schema: the field is present with value 0)
        var states: [SlotProgressMonitor.State] = []
        var phases: [SlotProgressMonitor.Phase] = []
        for np in [100, 400, 900, 1600, 2600, 3416] {
            t += tickMS
            let v = m.observe(obs(t, np: np, total: 3416, nd: 0))
            states.append(v.state)
            phases.append(v.phase)
        }
        // zero -> positive confirms the boundary exactly once
        t += tickMS
        let boundary = m.observe(obs(t, np: 3416, total: 3416, nd: 1))
        XCTAssertEqual(boundary.state, .phaseBoundaryConfirmed)
        XCTAssertEqual(boundary.phase, .decode)
        // decode: token counter climbing, n_prompt_tokens growing with it
        for nd in [4, 9, 16, 25, 40] {
            t += tickMS
            let v = m.observe(obs(t, np: 3416, total: 3416 + nd, nd: nd))
            states.append(v.state)
            phases.append(v.phase)
            XCTAssertEqual(v.phase, .decode,
                           "decode ticks must stay decode while total grows")
        }
        XCTAssertFalse(states.contains(.candidateStall), "normal load must not stall")
        XCTAssertTrue(states.contains(.progressing))
        XCTAssertFalse(states.contains(.phaseBoundaryConfirmed),
                       "the boundary is confirmed only once")
        XCTAssertTrue(phases.prefix(6).allSatisfy { $0 == .prefill },
                      "a known zero is pre-decode")
    }

    // MARK: Quadrant 2 — frozen counters (candidate detection, P7 positive control)

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
        XCTAssertEqual(v.phase, .prefill,
                       "the reset tick still reads its own n_decoded zero")
        XCTAssertNil(v.noProgressMS)
        // the new task's static run starts from its own first tick
        t += tickMS
        let v2 = m.observe(obs(t, task: 2, np: 3416, total: 3416, nd: 0))
        XCTAssertEqual(v2.state, .observingNoProgress)
        XCTAssertEqual(v2.noProgressMS ?? 0, tickMS,
                       "static time must be measured from the new task's baseline")
    }

    // MARK: Quadrant 4 — phase transitions and mixed ticks

    /// Requirement 3: during decode the prompt counters may keep growing
    /// (live n_prompt_tokens = prompt + n_decoded). That growth must not
    /// re-trigger a phase transition or flip the phase away from decode.
    func testDecodePhaseIsNotReopenedByGrowingPromptCounters() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, np: 19, total: 3416, nd: 0))
        t += tickMS
        let boundary = m.observe(obs(t, np: 20, total: 3417, nd: 1))
        XCTAssertEqual(boundary.state, .phaseBoundaryConfirmed)
        var states: [SlotProgressMonitor.State] = []
        var phases: [SlotProgressMonitor.Phase] = []
        for nd in 2...12 {
            t += tickMS
            let v = m.observe(obs(t, np: 20, total: 3416 + nd, nd: nd))
            states.append(v.state)
            phases.append(v.phase)
        }
        XCTAssertTrue(states.allSatisfy { $0 == .progressing },
                      "decode growth stays progressing")
        XCTAssertTrue(phases.allSatisfy { $0 == .decode },
                      "prompt-total growth must not flip the phase")
        XCTAssertFalse(states.contains(.phaseBoundaryConfirmed),
                       "the boundary must not be confirmed again")
        XCTAssertFalse(states.contains(.phaseTransitionOrUnknown))
    }

    /// A decode counter that never appears cannot support a phase claim:
    /// `n_prompt_tokens >= n_prompt_tokens_processed` is not evidence of a
    /// completed prefill (live schema). The static span still accumulates and
    /// must still reach the candidate window unchanged.
    func testNeverSeenDecodeCounterMakesNoPhaseClaimButStillAccumulates() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, np: 3416, total: 3416, nd: nil))
        t += tickMS
        _ = m.observe(obs(t, np: 3416, total: 3416, nd: nil))
        var sawPhaseLabel = false
        var sawCandidate = false
        for _ in 0..<26 {  // 13 s against a 10 s window
            t += tickMS
            let v = m.observe(obs(t, np: 3416, total: 3416, nd: nil))
            if v.state == .phaseTransitionOrUnknown
                || v.state == .phaseBoundaryConfirmed || v.phase != .unknown {
                sawPhaseLabel = true
            }
            if v.state == .candidateStall { sawCandidate = true }
        }
        XCTAssertFalse(sawPhaseLabel,
                       "a never-seen decode counter must not claim a phase")
        XCTAssertTrue(sawCandidate,
                      "a never-seen decode counter must not disable the stall window")
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
    // MARK: Review additions (2026-11-08) — input boundaries

    func testBusySampleWithoutTaskIDIsUnobservableAndNeverStalls() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, np: 3416, total: 3416, nd: 5))
        // the task id disappears on a busy sample: unobservable, baseline kept
        for _ in 0..<24 {
            t += tickMS
            let v = m.observe(obs(t, task: nil, np: 3416, total: 3416, nd: 5))
            XCTAssertEqual(v.state, .unobservable)
            XCTAssertNil(v.idTask)
        }
        // even past the window, no candidate stall may come from these
        t += tickMS
        let v = m.observe(obs(t, task: nil, np: 3416, total: 3416, nd: 5))
        XCTAssertEqual(v.state, .unobservable)
    }

    func testInitialBusySampleWithoutTaskIDEstablishesNothing() {
        let m = makeMonitor()
        var t: UInt64 = 0
        for i in 0..<6 {
            t += tickMS
            let v = m.observe(obs(t, task: nil, np: 100 + i, total: 3416, nd: nil))
            XCTAssertEqual(v.state, .unobservable)
            XCTAssertNil(v.idTask)
        }
        // no baseline was fabricated: a later real task starts fresh
        t += tickMS
        let v = m.observe(obs(t, task: 1, np: 200, total: 3416, nd: nil))
        XCTAssertEqual(v.state, .progressing, "baseline established")
        XCTAssertEqual(v.idTask, 1)
    }

    func testDecodeCounterFirstAppearanceIsNotGrowth() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, np: 3416, total: 3416))
        // the decode counter appears with 1: appearance is not advancement,
        // but the phase conclusion is decode with an unknown boundary
        t += tickMS
        let v = m.observe(obs(t, np: 3416, total: 3416, nd: 1))
        XCTAssertNotEqual(v.state, .progressing)
        XCTAssertEqual(v.state, .phaseTransitionOrUnknown)
        XCTAssertEqual(v.phase, .decode)
    }

    func testFirstPositiveAppearanceWithPromptAdvanceIsDecodeBoundaryUnknown() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, np: 3416, total: 3416))
        // The decode counter appears positive for the first time while the
        // prompt advances: decode is observed, but no zero sample preceded
        // it, so the boundary must stay unknown (never fabricated).
        t += tickMS
        let v = m.observe(obs(t, np: 3500, total: 3416, nd: 1))
        XCTAssertEqual(v.state, .phaseTransitionOrUnknown)
        XCTAssertEqual(v.phase, .decode)
        XCTAssertTrue(v.reason.contains("boundary unknown"))
    }

    func testDecodeCounterSeenThenMissingBlocksTheStallSpan() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, np: 3416, total: 3416, nd: 5))
        // decode seen before, missing now: unobservable (not a boundary),
        // and the span must not reach candidate_stall through these samples
        var sawCandidate = false
        for _ in 0..<24 {
            t += tickMS
            let v = m.observe(obs(t, np: 3416, total: 3416, nd: nil))
            XCTAssertEqual(v.state, .unobservable,
                           "a vanished seen-counter is unobservable, not a boundary")
            if v.state == .candidateStall { sawCandidate = true }
        }
        XCTAssertFalse(sawCandidate)
        XCTAssertNotEqual(
            m.observe(obs(t, np: 3416, total: 3416, nd: nil)).state,
            .phaseTransitionOrUnknown)
    }

    func testProbeFailureBlocksCandidateStallAcrossTheOutage() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, np: 3416, total: 3416, nd: 5))
        // outage: the sampler cannot observe anything for 12 s (past the window)
        let verdicts = m.observeProbeFailure(engineGeneration: 1)
        XCTAssertEqual(verdicts.count, 1)
        XCTAssertEqual(verdicts.first?.state, .unobservable)
        t += 12_000
        // counters return unchanged: the span crossed the outage, so no
        // candidate stall may be declared from it
        var sawCandidate = false
        for _ in 0..<4 {
            t += tickMS
            let v = m.observe(obs(t, np: 3416, total: 3416, nd: 5))
            if v.state == .candidateStall { sawCandidate = true }
            XCTAssertEqual(v.state, .observingNoProgress)
        }
        XCTAssertFalse(sawCandidate)
    }

    func testMultipleSlotsDoNotPolluteEachOther() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, np: 1000, total: 2000, nd: 3, slot: 0))
        _ = m.observe(obs(t, np: 500, total: 2000, nd: 8, slot: 1))
        // slot 0 goes static while slot 1 keeps decoding
        t += tickMS
        let v0 = m.observe(obs(t, np: 1000, total: 2000, nd: 3, slot: 0))
        let v1 = m.observe(obs(t, np: 500, total: 2000, nd: 9, slot: 1))
        XCTAssertEqual(v0.state, .observingNoProgress)
        XCTAssertEqual(v1.state, .progressing)
        // slot 1's progress must not clear slot 0's accumulated static time
        t += tickMS
        let v0b = m.observe(obs(t, np: 1000, total: 2000, nd: 3, slot: 0))
        XCTAssertEqual(v0b.state, .observingNoProgress)
        XCTAssertEqual(v0b.noProgressMS ?? 0, 2 * tickMS)
    }

    func testVerdictCarriesTaskIdentityForCandidateStall() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, task: 777, np: 3416, total: 3416, nd: 1))
        var verdict: SlotProgressMonitor.Verdict?
        for _ in 0..<24 {
            t += tickMS
            let v = m.observe(obs(t, task: 777, np: 3416, total: 3416, nd: 1))
            if v.state == .candidateStall { verdict = v; break }
        }
        XCTAssertEqual(verdict?.idTask, 777,
                       "the candidate evidence must name the frozen task")
    }

    // MARK: Ingest-level tests — HTTP status and field parsing

    private func frozenBody() -> Data {
        let slot: [String: Any] = [
            "id": 0, "is_processing": true, "id_task": 424242,
            "n_prompt_tokens": 3416, "n_prompt_tokens_processed": 3416,
            "next_token": [["n_decoded": 777, "n_remain": 100]],
        ]
        return try! JSONSerialization.data(withJSONObject: [slot])
    }

    /// A non-200 response with a syntactically valid frozen body observes no
    /// counters at all: unobservable, never candidate_stall. The baseline is
    /// established through a real 200 first, so the outage genuinely crosses
    /// a tracked run (a fresh monitor has nothing to mark unobservable).
    func testNon200WithValidFrozenBodyNeverStalls() {
        let m = makeMonitor()
        let body = frozenBody()
        let seed = SlotProgressIngest.ingest(
            data: body, statusCode: 200, engineGeneration: 1, into: m)
        XCTAssertEqual(seed.first?.state, .baselineReset,
                       "first observation establishes the generation baseline")
        XCTAssertEqual(m.trackedSlots(engineGeneration: 1), [0])
        var sawUnobservable = false
        var sawCandidate = false
        for _ in 0..<30 {
            let verdicts = SlotProgressIngest.ingest(
                data: body, statusCode: 503, engineGeneration: 1, into: m)
            XCTAssertEqual(verdicts.count, 1, "the tracked slot must be reported")
            for v in verdicts {
                XCTAssertEqual(v.state, .unobservable)
                if v.state == .unobservable { sawUnobservable = true }
                if v.state == .candidateStall { sawCandidate = true }
            }
        }
        XCTAssertTrue(sawUnobservable)
        XCTAssertFalse(sawCandidate,
                       "a 503 response must never accumulate toward a stall")
        // after the status recovers, the unchanged frozen body resumes the
        // polluted run: observing, and the outage blocks any candidate
        let recovered = SlotProgressIngest.ingest(
            data: body, statusCode: 200, engineGeneration: 1, into: m)
        XCTAssertEqual(recovered.first?.state, .observingNoProgress)
        XCTAssertNotEqual(recovered.first?.state, .candidateStall)
        // genuine decode advance clears the pollution and reports progress
        let advanced = json([[
            "id": 0, "is_processing": true, "id_task": 424242,
            "n_prompt_tokens": 3416, "n_prompt_tokens_processed": 3416,
            "next_token": [["n_decoded": 778, "n_remain": 99]],
        ] as [String: Any]])
        let v = SlotProgressIngest.ingest(
            data: advanced, statusCode: 200, engineGeneration: 1, into: m)
        XCTAssertEqual(v.first?.state, .progressing)
        XCTAssertEqual(v.first?.phase, .decode)
    }

    /// A lone slot with a missing id cannot be attributed: it observes no
    /// counters (unobservable for tracked slots) and must not pollute slot 0.
    func testMalformedLoneSlotIDIsUnobservableNotSlotZero() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, np: 3416, total: 3416, nd: 5, slot: 0))
        // payload with a slot whose id field is missing
        let body = try! JSONSerialization.data(withJSONObject: [
            ["is_processing": true, "n_prompt_tokens_processed": 3416]
        ])
        let verdicts = SlotProgressIngest.ingest(
            data: body, statusCode: 200, engineGeneration: 1, into: m)
        XCTAssertTrue(verdicts.contains { $0.state == .unobservable },
                      "a lone malformed slot must block the span as unobservable")
        XCTAssertFalse(verdicts.contains { $0.slotID == 0 && $0.state != .unobservable },
                       "the malformed slot must not be folded into slot 0")
    }

    // MARK: Audit regressions (2026-11-08) — P1/P2: decode visibility

    /// P1 + requirement 1: zero -> zero -> positive confirms the boundary
    /// exactly at the first positive tick; the zero ticks merely establish
    /// and keep the pre-decode baseline (never "prefill complete").
    func testZeroThenFirstTokenConfirmsBoundaryExactlyOnce() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        let seed = m.observe(obs(t, np: 3416, total: 3416, nd: 0))
        XCTAssertEqual(seed.state, .baselineReset)
        XCTAssertEqual(seed.phase, .prefill)
        t += tickMS
        let stillZero = m.observe(obs(t, np: 3416, total: 3416, nd: 0))
        XCTAssertEqual(stillZero.state, .observingNoProgress)
        XCTAssertEqual(stillZero.phase, .prefill)
        XCTAssertNotEqual(stillZero.state, .phaseBoundaryConfirmed)
        XCTAssertNotEqual(stillZero.state, .phaseTransitionOrUnknown)
        // first positive tick confirms the boundary
        t += tickMS
        let first = m.observe(obs(t, np: 3416, total: 3416, nd: 1))
        XCTAssertEqual(first.state, .phaseBoundaryConfirmed)
        XCTAssertEqual(first.phase, .decode)
        XCTAssertEqual(first.noProgressMS, 0)
        // later growth is ordinary decode progress, not another boundary
        t += tickMS
        let grown = m.observe(obs(t, np: 3416, total: 3416, nd: 2))
        XCTAssertEqual(grown.state, .progressing)
        XCTAssertEqual(grown.phase, .decode)
        XCTAssertNotEqual(grown.state, .phaseBoundaryConfirmed)
    }

    /// Requirement 2: a first sample that is already positive observes decode
    /// but must not fabricate a transition. The first sample of a generation
    /// is the identity event (baseline_reset); its phase still follows
    /// n_decoded and its reason states that the boundary is unknown.
    func testFirstSamplePositiveReportsBoundaryUnknown() {
        let m = makeMonitor()
        let v = m.observe(obs(tickMS, np: 3416, total: 3416, nd: 7))
        XCTAssertEqual(v.state, .baselineReset)
        XCTAssertEqual(v.phase, .decode)
        XCTAssertNil(v.noProgressMS)
        XCTAssertTrue(v.reason.contains("boundary unknown"))
        XCTAssertFalse(v.reason.contains("confirmed"))
    }

    /// Requirement 2/6: a new task whose FIRST observation is already positive
    /// (the health probe can first sample a task mid-decode) is a reset that
    /// observes decode with an unknown boundary — never a confirmed transition.
    func testNewTaskFirstSightPositiveReportsBoundaryUnknown() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, task: 1, np: 3416, total: 3416, nd: 40))
        t += tickMS
        let v = m.observe(obs(t, task: 2, np: 1032, total: 1032, nd: 3))
        XCTAssertEqual(v.state, .baselineReset)
        XCTAssertEqual(v.phase, .decode)
        XCTAssertNil(v.noProgressMS)
        XCTAssertTrue(v.reason.contains("boundary unknown"))
        XCTAssertFalse(v.reason.contains("confirmed"))
        // growth after the reset is ordinary decode progress
        t += tickMS
        let grown = m.observe(obs(t, task: 2, np: 1032, total: 1035, nd: 4))
        XCTAssertEqual(grown.state, .progressing)
        XCTAssertEqual(grown.phase, .decode)
        XCTAssertNotEqual(grown.state, .phaseBoundaryConfirmed)
    }

    /// Requirement 4: a new task carrying the previous task's prompt counters
    /// (live: stale n_prompt_tokens during early prefill) must not confirm
    /// decode before its own n_decoded turns positive.
    func testNewTaskWithStalePromptCountersDoesNotConfirmDecodeEarly() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, task: 1, np: 3416, total: 3416, nd: 10))
        t += tickMS
        let reset = m.observe(obs(t, task: 2, np: 1032, total: 1032, nd: 0))
        XCTAssertEqual(reset.state, .baselineReset)
        t += tickMS
        let stillPreDecode = m.observe(obs(t, task: 2, np: 1040, total: 1048, nd: 0))
        XCTAssertEqual(stillPreDecode.state, .progressing)
        XCTAssertEqual(stillPreDecode.phase, .prefill)
        XCTAssertNotEqual(stillPreDecode.state, .phaseBoundaryConfirmed)
        t += tickMS
        let confirmed = m.observe(obs(t, task: 2, np: 1048, total: 1050, nd: 1))
        XCTAssertEqual(confirmed.state, .phaseBoundaryConfirmed)
        XCTAssertEqual(confirmed.phase, .decode)
    }

    /// Requirement 5: a known zero that later disappears is unobservable,
    /// never a boundary and never a confirmed transition.
    func testKnownZeroThenMissingDecodeCounterIsUnobservable() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, np: 3416, total: 3416, nd: 0))
        t += tickMS
        let v = m.observe(obs(t, np: 3416, total: 3416, nd: nil))
        XCTAssertEqual(v.state, .unobservable)
        XCTAssertNotEqual(v.state, .phaseTransitionOrUnknown)
        XCTAssertNotEqual(v.state, .phaseBoundaryConfirmed)
    }

    /// Requirement 6: decode-counter rollback re-baselines (never a stall),
    /// and the re-established baseline is a clean pre-decode baseline.
    func testDecodeCounterRollbackRebaselines() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, np: 3416, total: 3416, nd: 5))
        t += tickMS
        let v = m.observe(obs(t, np: 3416, total: 3416, nd: 0))
        XCTAssertEqual(v.state, .baselineReset)
        XCTAssertEqual(v.phase, .prefill,
                       "a rollback to a known zero is a pre-decode baseline")
        XCTAssertNil(v.noProgressMS)
        t += tickMS
        let v2 = m.observe(obs(t, np: 3416, total: 3416, nd: 0))
        XCTAssertEqual(v2.state, .observingNoProgress)
        XCTAssertEqual(v2.phase, .prefill)
        XCTAssertEqual(v2.noProgressMS ?? 0, tickMS)
        t += tickMS
        let v3 = m.observe(obs(t, np: 3416, total: 3416, nd: 3))
        XCTAssertEqual(v3.state, .phaseBoundaryConfirmed)
    }

    /// P2: a healthy decode stream must never be falsely labelled a stall.
    /// Under the inverted branch the first appearance was never recorded, so
    /// every later value looked static and a candidate stall accumulated.
    func testHealthyDecodeStreamNeverFalselyStalls() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, np: 3416, total: 3416, nd: 0))
        var states: [SlotProgressMonitor.State] = []
        var phases: [SlotProgressMonitor.Phase] = []
        for nd in 1...40 {  // 20 s of decode against a 10 s window
            t += tickMS
            let v = m.observe(obs(t, np: 3416, total: 3416, nd: nd))
            states.append(v.state)
            phases.append(v.phase)
        }
        XCTAssertFalse(states.contains(.candidateStall),
                       "advancing decode must never be a candidate stall")
        XCTAssertFalse(states.contains(.unobservable))
        // the first positive tick confirms the boundary; every later
        // advancing tick is ordinary decode progress
        XCTAssertEqual(states.first, .phaseBoundaryConfirmed)
        XCTAssertTrue(states.dropFirst().allSatisfy { $0 == .progressing },
                      "growth after the first sight must be visible")
        XCTAssertTrue(phases.allSatisfy { $0 == .decode })
    }

    /// Owner-required independent direction check: once decode has been
    /// SEEN, a brief missing spell must not re-enter the never-seen
    /// transition window — neither while missing nor after the value returns.
    func testSeenDecodeBrieflyMissingNeverReentersTransitionWindow() {
        let m = makeMonitor()
        var t: UInt64 = 0
        t += tickMS
        _ = m.observe(obs(t, np: 3416, total: 3416, nd: 5))
        // brief missing spell: unobservable, never the transition label
        for _ in 0..<4 {
            t += tickMS
            let v = m.observe(obs(t, np: 3416, total: 3416, nd: nil))
            XCTAssertEqual(v.state, .unobservable)
            XCTAssertNotEqual(v.state, .phaseTransitionOrUnknown)
        }
        // the value returns unchanged: still no transition label, and the
        // polluted span cannot confirm a stall
        t += tickMS
        let back = m.observe(obs(t, np: 3416, total: 3416, nd: 5))
        XCTAssertNotEqual(back.state, .phaseTransitionOrUnknown)
        XCTAssertNotEqual(back.state, .candidateStall)
        XCTAssertEqual(back.state, .observingNoProgress)
        // growth after the spell is visible again
        t += tickMS
        let grown = m.observe(obs(t, np: 3416, total: 3416, nd: 6))
        XCTAssertEqual(grown.state, .progressing)
        XCTAssertEqual(grown.phase, .decode)
    }

    // MARK: Audit regressions — P3: no fabricated task identity

    /// P3: busy samples without id_task mid-run fabricate nothing — no
    /// sentinel baseline, no inherited identity — and the first genuinely
    /// identified task is reported as a fresh baseline, not an id change
    /// away from a sentinel.
    func testMissingTaskIDFabricatesNoSentinelBaseline() {
        let m = makeMonitor()
        var t: UInt64 = 0
        for _ in 0..<6 {
            t += tickMS
            let v = m.observe(obs(t, task: nil, np: 3416, total: 3416, nd: 5))
            XCTAssertEqual(v.state, .unobservable)
            XCTAssertNil(v.idTask)
        }
        t += tickMS
        let v = m.observe(obs(t, task: 9, np: 3416, total: 3416, nd: 5))
        XCTAssertEqual(v.state, .phaseTransitionOrUnknown,
                       "a first positive sample is decode with an unknown boundary")
        XCTAssertTrue(v.reason.hasPrefix("baseline established"),
                      "no sentinel baseline may exist to change away from")
        XCTAssertEqual(v.idTask, 9)
    }

    // MARK: Audit regressions — P4: strict integer/boolean parsing

    /// P4a: a boolean or float `id` is not an integer identity — the slot is
    /// unidentifiable and must not be folded into slot 0.
    func testBooleanAndFloatSlotIDsAreUnidentifiable() {
        for badID in [true, false, 0.5] as [Any] {
            let m = makeMonitor()
            var t: UInt64 = 0
            t += tickMS
            _ = m.observe(obs(t, np: 3416, total: 3416, nd: 5, slot: 0))
            let body = json([[
                "id": badID, "is_processing": true, "id_task": 1,
                "n_prompt_tokens_processed": 3416,
            ] as [String: Any]])
            let verdicts = SlotProgressIngest.ingest(
                data: body, statusCode: 200, engineGeneration: 1, into: m)
            XCTAssertTrue(verdicts.contains { $0.state == .unobservable },
                          "id=\(badID) must leave the tracked slot unobservable")
            XCTAssertFalse(verdicts.contains { $0.slotID == 0 && $0.state == .progressing },
                           "id=\(badID) must not be truncated into slot 0")
            XCTAssertEqual(m.trackedSlots(engineGeneration: 1), [0],
                           "the real baseline must survive the malformed tick")
        }
    }

    /// P4b: non-integer id_task / n_decoded degrade to nil (unobservable),
    /// never to a truncated identity or count; a numeric is_processing is
    /// not a boolean and degrades the same way.
    func testNonIntegerCountersAndNumericProcessingDegradeToUnobservable() {
        let m = makeMonitor()
        let seed = SlotProgressIngest.ingest(
            data: frozenBody(), statusCode: 200, engineGeneration: 1, into: m)
        XCTAssertEqual(seed.first?.state, .baselineReset)
        // float id_task: busy sample without a usable task id
        let floatTask = json([[
            "id": 0, "is_processing": true, "id_task": 1.5,
            "n_prompt_tokens": 3416, "n_prompt_tokens_processed": 3416,
            "next_token": [["n_decoded": 777]],
        ] as [String: Any]])
        let v1 = SlotProgressIngest.ingest(
            data: floatTask, statusCode: 200, engineGeneration: 1, into: m)
        XCTAssertEqual(v1.first?.state, .unobservable)
        XCTAssertNil(v1.first?.idTask)
        // boolean n_decoded: the decode field is nil, a seen counter vanished
        let boolDecoded = json([[
            "id": 0, "is_processing": true, "id_task": 424242,
            "n_prompt_tokens": 3416, "n_prompt_tokens_processed": 3416,
            "next_token": [["n_decoded": true]],
        ] as [String: Any]])
        let v2 = SlotProgressIngest.ingest(
            data: boolDecoded, statusCode: 200, engineGeneration: 1, into: m)
        XCTAssertEqual(v2.first?.state, .unobservable)
        // numeric is_processing: not a boolean -> unobservable, never idle
        let numericProcessing = json([[
            "id": 0, "is_processing": 1, "id_task": 424242,
            "n_prompt_tokens": 3416, "n_prompt_tokens_processed": 3416,
        ] as [String: Any]])
        let v3 = SlotProgressIngest.ingest(
            data: numericProcessing, statusCode: 200, engineGeneration: 1, into: m)
        XCTAssertEqual(v3.first?.state, .unobservable)
        XCTAssertNotEqual(v3.first?.state, .baselineReset,
                          "a malformed is_processing must never read as idle")
        XCTAssertEqual(m.trackedSlots(engineGeneration: 1), [0],
                       "the baseline survives malformed ticks")
    }

    // MARK: Audit regressions — P6: explicit slot absence

    /// P6a: a tracked slot missing from a fully identifiable /slots list is
    /// explicitly reset (not left to an identity change on reappearance);
    /// reappearance starts a fresh baseline with no inherited static time.
    func testIngestAbsenceResetsBaselineAndReappearanceStartsFresh() {
        let m = makeMonitor()
        let seed = SlotProgressIngest.ingest(
            data: frozenBody(), statusCode: 200, engineGeneration: 1, into: m)
        XCTAssertEqual(seed.first?.state, .baselineReset)
        XCTAssertEqual(m.trackedSlots(engineGeneration: 1), [0])
        // the list now identifies only slot 1: slot 0 is gone -> reset
        let other = json([[
            "id": 1, "is_processing": true, "id_task": 2,
            "n_prompt_tokens": 100, "n_prompt_tokens_processed": 50,
        ] as [String: Any]])
        let absence = SlotProgressIngest.ingest(
            data: other, statusCode: 200, engineGeneration: 1, into: m)
        XCTAssertTrue(absence.contains {
            $0.slotID == 0 && $0.state == .baselineReset && $0.idTask == 424242
        }, "the vanished slot must be explicitly reset with its last identity")
        XCTAssertEqual(m.trackedSlots(engineGeneration: 1), [1])
        // slot 0 returns: a fresh baseline, not an id_task-change verdict
        let back = SlotProgressIngest.ingest(
            data: frozenBody(), statusCode: 200, engineGeneration: 1, into: m)
        let v0 = back.first { $0.slotID == 0 }
        XCTAssertEqual(v0?.state, .phaseTransitionOrUnknown,
                       "a fresh positive baseline is decode, boundary unknown")
        XCTAssertTrue(v0?.reason.hasPrefix("baseline established") ?? false)
        // static time starts from the new baseline, nothing inherited
        let again = SlotProgressIngest.ingest(
            data: frozenBody(), statusCode: 200, engineGeneration: 1, into: m)
        let v0b = again.first { $0.slotID == 0 }
        XCTAssertEqual(v0b?.state, .observingNoProgress)
        XCTAssertLessThan(v0b?.noProgressMS ?? .max, windowMS)
    }

    /// P6b: with an unidentifiable sibling present, absence is ambiguous —
    /// the malformed entry might BE the missing slot — so no reset happens.
    func testIngestAbsenceIsConservativeWithMalformedSibling() {
        let m = makeMonitor()
        let seed = SlotProgressIngest.ingest(
            data: frozenBody(), statusCode: 200, engineGeneration: 1, into: m)
        XCTAssertEqual(seed.first?.state, .baselineReset)
        // slot 1 is identified; a second entry has no id at all
        let mixed = json([
            ["id": 1, "is_processing": true, "id_task": 2,
             "n_prompt_tokens": 100, "n_prompt_tokens_processed": 50] as [String: Any],
            ["is_processing": true, "n_prompt_tokens_processed": 3416] as [String: Any],
        ])
        let verdicts = SlotProgressIngest.ingest(
            data: mixed, statusCode: 200, engineGeneration: 1, into: m)
        XCTAssertFalse(verdicts.contains { $0.slotID == 0 && $0.state == .baselineReset },
                       "ambiguous absence must not reset the tracked slot")
        XCTAssertEqual(m.trackedSlots(engineGeneration: 1), [0, 1],
                       "slot 0's baseline is retained until absence is provable")
    }

    /// P6c: an empty slots list proves nothing — unobservable for tracked
    /// slots, never an absence reset and never idle.
    func testEmptySlotsListIsUnobservableNotAbsence() {
        let m = makeMonitor()
        let seed = SlotProgressIngest.ingest(
            data: frozenBody(), statusCode: 200, engineGeneration: 1, into: m)
        XCTAssertEqual(seed.first?.state, .baselineReset)
        let verdicts = SlotProgressIngest.ingest(
            data: json([Any]()), statusCode: 200, engineGeneration: 1, into: m)
        XCTAssertEqual(verdicts.count, 1)
        XCTAssertEqual(verdicts.first?.state, .unobservable)
        XCTAssertNotEqual(verdicts.first?.state, .baselineReset)
        XCTAssertEqual(m.trackedSlots(engineGeneration: 1), [0])
    }
}
