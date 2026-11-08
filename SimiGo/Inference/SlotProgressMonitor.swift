import Foundation

/// Slot-level inference-progress monitor (Issue #15 R2-B).
///
/// MONITOR ONLY. It observes `/slots` samples and classifies progress per
/// (engine generation, slot, task); it never restarts anything, never
/// terminates a task and never alters the Service's busy-protection policy.
/// A `candidateStall` verdict is structured evidence for operators and tests
/// — restart authorisation remains a separate, unmade decision.
///
/// Observational semantics (owner ruling 2026-11-08):
/// - Identity is (engineGeneration, slotID, idTask). Any of these changing
///   resets the observation baseline; the reset itself is reported as
///   `baselineReset` and never as a stall.
/// - Progress: the prefill counter advanced, or the decode counter advanced,
///   or both advanced in one tick (one progress, phase `mixed`).
/// - No progress: same task, busy, neither counter advanced. The reported
///   duration is the monotonic span since the last advancing sample —
///   including the closing tick's own dt.
/// - A candidate stall requires the no-progress span to reach the configured
///   window AND the span to contain no `unobservable` sample (a missing
///   counter can never be the reason a stall is declared).
/// - Counter regression or reset establishes a new baseline
///   (`baselineReset`), never a stall.
/// - Missing counters, malformed samples and probe failures are
///   `unobservable`; they cannot create or confirm a stall.
/// - A busy tick where prefill is complete (`promptProcessed ==
///   promptTotal`) but no decode token has appeared yet is reported as
///   `phaseTransitionOrUnknown` — the prefill→decode boundary window. It
///   still accumulates monotonic time toward the candidate window.
///
/// All timestamps are monotonic-clock milliseconds supplied by the caller
/// (the Service stamps them when it receives the `/slots` response). The
/// type is not thread-safe by design: the health loop serialises its calls.
public final class SlotProgressMonitor {

    public struct Config: Sendable {
        /// Candidate-stall window in monotonic milliseconds. Explicitly
        /// injected by tests (e.g. 10_000 for the R2-B validation); nothing
        /// in production reads a default as a restart threshold.
        public var candidateWindowMS: UInt64
        public init(candidateWindowMS: UInt64) {
            self.candidateWindowMS = candidateWindowMS
        }
    }

    public enum State: String, Sendable {
        case progressing
        case observingNoProgress = "observing_no_progress"
        case candidateStall = "candidate_stall"
        case baselineReset = "baseline_reset"
        case unobservable
        case phaseTransitionOrUnknown = "phase_transition_or_unknown"
    }

    public enum Phase: String, Sendable {
        case prefill, decode, mixed, unknown
    }

    public struct Observation: Sendable {
        public let slotID: Int
        public let engineGeneration: UInt64
        public let idTask: Int?
        /// nil = the field was missing or malformed: the sample is
        /// unobservable for this slot.
        public let isProcessing: Bool?
        /// `n_prompt_tokens_processed`; nil means the field was missing.
        public let promptProcessed: Int?
        /// `n_prompt_tokens`; nil means the field was missing.
        public let promptTotal: Int?
        /// `next_token[0].n_decoded`; nil when absent (idle slot, prefill in
        /// flight, or a schema without the token view).
        public let decoded: Int?
        public let observedAtMonotonicMS: UInt64

        public init(slotID: Int, engineGeneration: UInt64, idTask: Int?,
                    isProcessing: Bool?, promptProcessed: Int?,
                    promptTotal: Int?, decoded: Int?,
                    observedAtMonotonicMS: UInt64) {
            self.slotID = slotID
            self.engineGeneration = engineGeneration
            self.idTask = idTask
            self.isProcessing = isProcessing
            self.promptProcessed = promptProcessed
            self.promptTotal = promptTotal
            self.decoded = decoded
            self.observedAtMonotonicMS = observedAtMonotonicMS
        }
    }

    public struct Verdict: Sendable {
        public let slotID: Int
        public let engineGeneration: UInt64
        public let state: State
        public let phase: Phase
        /// Monotonic ms since the last advancing sample while the current
        /// no-progress run lasts; nil outside a run.
        public let noProgressMS: UInt64?
        public let reason: String
    }

    struct Baseline {
        var idTask: Int
        var promptProcessed: Int
        var decoded: Int?
        var decodedKnown: Bool
        var sinceMonoMS: UInt64
        var lastPhase: Phase
        var unobservableInRun: Bool
    }

    public let config: Config
    private var lastGeneration: UInt64?
    private var baselines: [Int: Baseline] = [:]

    public init(config: Config) {
        self.config = config
    }

    /// Production wiring: a label-only window, overridable for experiments.
    /// Nothing in the product reads candidateStall to restart anything.
    public static func productionDefault() -> SlotProgressMonitor {
        let raw = ProcessInfo.processInfo.environment["SIMIGO_SLOT_PROGRESS_WINDOW_MS"]
        let window = (raw.flatMap(UInt64.init)) ?? 30_000
        return SlotProgressMonitor(config: .init(candidateWindowMS: window))
    }

    /// Drop every baseline (engine restart is also detected automatically
    /// via the generation field on the next observation).
    public func reset() {
        baselines.removeAll()
        lastGeneration = nil
    }

    /// A probe failure (transport error, non-200) observed no counters at
    /// all: every tracked slot's no-progress run is flagged unobservable so
    /// the outage can never confirm a stall.
    @discardableResult
    public func observeProbeFailure(engineGeneration: UInt64) -> [Verdict] {
        guard lastGeneration == engineGeneration else { return [] }
        return baselines.keys.sorted().compactMap { slotID in
            guard baselines[slotID] != nil else { return nil }
            baselines[slotID]?.unobservableInRun = true
            return Verdict(slotID: slotID, engineGeneration: engineGeneration,
                           state: .unobservable, phase: .unknown,
                           noProgressMS: nil, reason: "probe failed")
        }
    }

    /// Slot ids this monitor currently holds baselines for.
    public func trackedSlots(engineGeneration: UInt64) -> [Int] {
        guard lastGeneration == engineGeneration else { return [] }
        return baselines.keys.sorted()
    }

    /// A slot disappeared from the slots list: its observation baseline is
    /// reset per the ruling (slot gone -> reset), reported for visibility.
    @discardableResult
    public func observeAbsence(slotID: Int, engineGeneration: UInt64) -> Verdict? {
        guard lastGeneration == engineGeneration,
              baselines.removeValue(forKey: slotID) != nil else {
            return nil
        }
        return Verdict(slotID: slotID, engineGeneration: engineGeneration,
                       state: .baselineReset, phase: .unknown,
                       noProgressMS: nil,
                       reason: "slot absent from /slots observation")
    }

    @discardableResult
    public func observe(_ o: Observation) -> Verdict {
        // Engine generation change: every baseline is dropped — observations
        // from before a restart say nothing about the new engine process.
        if lastGeneration != o.engineGeneration {
            let hadBaselines = !baselines.isEmpty
            baselines.removeAll()
            lastGeneration = o.engineGeneration
            if o.isProcessing == true, let idTask = o.idTask, let np = o.promptProcessed {
                baselines[o.slotID] = Baseline(
                    idTask: idTask, promptProcessed: np, decoded: o.decoded,
                    decodedKnown: o.decoded != nil,
                    sinceMonoMS: o.observedAtMonotonicMS,
                    lastPhase: .unknown, unobservableInRun: false)
                return verdict(o, .baselineReset, .unknown, nil,
                               "engine generation changed; baseline re-established")
            }
            return verdict(o, .unobservable, .unknown, nil,
                           "engine generation changed; slot not processing"
                               + (hadBaselines ? " (prior baselines dropped)" : ""))
        }

        // Missing is_processing is unobservable: the sample cannot say
        // whether a task is active, so it can neither confirm progress nor
        // declare a stall.
        guard let processing = o.isProcessing else {
            if baselines[o.slotID] != nil {
                baselines[o.slotID]?.unobservableInRun = true
            }
            return verdict(o, .unobservable, .unknown, nil,
                           "is_processing missing")
        }

        // Idle slot: the task ended — reset the baseline, never a stall.
        guard processing else {
            if baselines.removeValue(forKey: o.slotID) != nil {
                return verdict(o, .baselineReset, .unknown, nil,
                               "slot idle; observation baseline reset")
            }
            return verdict(o, .progressing, .unknown, nil,
                           "slot idle without a prior baseline")
        }

        // Missing primary counters are unobservable by definition.
        guard let np = o.promptProcessed else {
            if baselines[o.slotID] != nil {
                baselines[o.slotID]?.unobservableInRun = true
            }
            return verdict(o, .unobservable, .unknown, nil,
                           "n_prompt_tokens_processed missing")
        }

        guard let base = baselines[o.slotID] else {
            baselines[o.slotID] = Baseline(
                idTask: o.idTask ?? -1, promptProcessed: np,
                decoded: o.decoded, decodedKnown: o.decoded != nil,
                sinceMonoMS: o.observedAtMonotonicMS,
                lastPhase: .unknown, unobservableInRun: false)
            return verdict(o, .progressing, .unknown, nil,
                           "baseline established")
        }

        // Task identity changed: new baseline, nothing inherited.
        if let idTask = o.idTask, idTask != base.idTask {
            baselines[o.slotID] = Baseline(
                idTask: idTask, promptProcessed: np, decoded: o.decoded,
                decodedKnown: o.decoded != nil,
                sinceMonoMS: o.observedAtMonotonicMS,
                lastPhase: .unknown, unobservableInRun: false)
            return verdict(o, .baselineReset, .unknown, nil,
                           "id_task changed (\(base.idTask) -> \(idTask)); baseline reset")
        }

        let ndKnownNow = o.decoded != nil
        let ndAdvanced = ndKnownNow && base.decodedKnown
            && o.decoded! > base.decoded!
        let ndAppeared = ndKnownNow && !base.decodedKnown
        let npAdvanced = np > base.promptProcessed
        let npRegressed = np < base.promptProcessed
        let ndRegressed = ndKnownNow && base.decodedKnown
            && o.decoded! < base.decoded!

        // Counter regression or reset: re-baseline, never a stall.
        if npRegressed || ndRegressed {
            baselines[o.slotID] = Baseline(
                idTask: o.idTask ?? base.idTask, promptProcessed: np,
                decoded: o.decoded, decodedKnown: ndKnownNow,
                sinceMonoMS: o.observedAtMonotonicMS,
                lastPhase: .unknown, unobservableInRun: false)
            return verdict(o, .baselineReset, .unknown, nil,
                           "counter regression; baseline re-established")
        }

        if npAdvanced || ndAdvanced || ndAppeared {
            // One progress per tick even when both counters advance.
            let phase: Phase = (npAdvanced && (ndAdvanced || ndAppeared))
                ? .mixed : (npAdvanced ? .prefill : .decode)
            baselines[o.slotID] = Baseline(
                idTask: o.idTask ?? base.idTask, promptProcessed: np,
                decoded: o.decoded, decodedKnown: ndKnownNow,
                sinceMonoMS: o.observedAtMonotonicMS,
                lastPhase: phase, unobservableInRun: false)
            return verdict(o, .progressing, phase, 0, "counters advanced")
        }

        // Neither counter advanced. Decode evidence missing while prefill is
        // already complete is the prefill->decode boundary window: real time
        // passes with no token yet, and it counts toward the candidate window
        // (R1 measured 1.95-2.29s there on this model) but is labelled as a
        // transition until a token appears or the window is exceeded. The
        // closing tick of such a window is an advancing tick — its own dt is
        // part of the span (the R1 off-by-one-tick lesson).
        let span = o.observedAtMonotonicMS - base.sinceMonoMS
        let prefillComplete = o.promptTotal.map { np >= $0 } ?? false
        let decodeEvidenceMissing = !ndKnownNow

        if span >= config.candidateWindowMS && !base.unobservableInRun {
            return verdict(o, .candidateStall, base.lastPhase, span,
                           "candidate stall: no counter advance within the window")
        }

        if decodeEvidenceMissing && prefillComplete {
            baselines[o.slotID]?.unobservableInRun = base.unobservableInRun
            return verdict(o, .phaseTransitionOrUnknown, .unknown, span,
                           "prefill complete; first decode token pending")
        }

        baselines[o.slotID]?.unobservableInRun = base.unobservableInRun
            || decodeEvidenceMissing
        return verdict(o, .observingNoProgress, base.lastPhase, span,
                       "no counter advance yet")
    }

    private func verdict(_ o: Observation, _ state: State, _ phase: Phase,
                         _ noProgressMS: UInt64?, _ reason: String) -> Verdict {
        Verdict(slotID: o.slotID, engineGeneration: o.engineGeneration,
                state: state, phase: phase, noProgressMS: noProgressMS,
                reason: reason)
    }
}
