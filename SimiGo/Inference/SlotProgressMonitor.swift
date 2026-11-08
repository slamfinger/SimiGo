import Foundation

/// Slot-level inference-progress monitor (Issue #15 R2-B).
///
/// MONITOR ONLY. It observes `/slots` samples and classifies progress per
/// (engine generation, slot, task); it never restarts anything, never
/// terminates a task and never alters the Service's busy-protection policy.
/// A `candidateStall` verdict is structured evidence for operators and tests
/// — restart authorisation remains a separate, unmade decision.
///
/// Observational semantics (owner ruling 2026-11-08, phase correction):
/// - Identity is (engineGeneration, slotID, idTask). Any of these changing
///   resets the observation baseline; the reset itself is reported as
///   `baselineReset` and never as a stall. A reset verdict still carries the
///   phase its own sample proves (known zero = pre-decode, positive =
///   decode), and a reset tick never confirms a boundary.
/// - Phase follows `next_token[0].n_decoded` only. A known zero means no
///   decode token has been observed yet (pre-decode); it is never a claim
///   that prefill completed. A positive value means decode.
///   `n_prompt_tokens` is informational: live b11720 lets it grow with
///   `n_decoded` and can carry the previous task's value during a new task's
///   early prefill, so it cannot decide the phase.
/// - Boundary: zero -> positive within one task is `phaseBoundaryConfirmed`
///   on that tick. A first positive observation with no preceding zero
///   sample is decode with an unknown boundary: `phaseTransitionOrUnknown`
///   on a fresh task baseline, or `baselineReset` (phase decode, reason
///   "boundary unknown") when it also establishes the generation baseline.
///   Neither claims a transition that was not observed.
/// - Progress: the prompt counter advanced, the decode counter advanced, or
///   both advanced in one tick. This rule is unchanged and independent of
///   the phase labels.
/// - No progress: same task, busy, neither counter advanced. The reported
///   duration is the monotonic span since the last advancing sample —
///   including the closing tick's own dt.
/// - A candidate stall requires the no-progress span to reach the configured
///   window AND the span to contain no `unobservable` sample (a missing
///   counter can never be the reason a stall is declared).
/// - Counter regression or reset establishes a new baseline
///   (`baselineReset`), never a stall.
/// - Missing counters, malformed samples and probe failures are
///   `unobservable`; they cannot create or confirm a stall. A decode counter
///   seen before and missing now is unobservable; a never-seen one leaves
///   the phase unknown without polluting the stall span.
///
/// All timestamps are monotonic-clock milliseconds supplied by the caller
/// (the Service stamps them when it receives the `/slots` response). The
/// type is not thread-safe by design: the health loop serialises its calls.
/// It is explicitly nonisolated so the health loop and the pure ingest call
/// it synchronously; actor-hopping a lock-free state machine would change
/// that serialisation contract.
public nonisolated final class SlotProgressMonitor {

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
        /// First positive decode observation after a known zero within the
        /// same task: the prefill->decode boundary is confirmed this tick.
        case phaseBoundaryConfirmed = "phase_boundary_confirmed"
        /// Positive decode observed without any preceding zero sample for
        /// this task: decode is observed, the boundary is unknown.
        case phaseTransitionOrUnknown = "phase_transition_or_unknown"
    }

    public enum Phase: String, Sendable {
        /// No decode token observed yet for the current task (n_decoded is a
        /// known zero). Not a claim that prefill has completed.
        case prefill
        /// A positive n_decoded has been observed for the current task.
        case decode
        /// No usable n_decoded yet, or no baseline.
        case unknown
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
        /// `n_prompt_tokens`; nil means the field was missing. Informational
        /// only: live b11720 reports prompt length + n_decoded and can carry
        /// the previous task's value at a new task's prefill start, so it
        /// never decides the phase (owner ruling 2026-11-08).
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
        /// The task identity this verdict is about, when it is genuinely
        /// known. A nil here means the sample did not carry a usable task id
        /// and NO stall judgement was made from it.
        public let idTask: Int?
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
        return baselines.keys.sorted().compactMap { slotID -> Verdict? in
            guard baselines[slotID] != nil else { return nil }
            baselines[slotID]?.unobservableInRun = true
            return Verdict(slotID: slotID, engineGeneration: engineGeneration,
                           idTask: baselines[slotID]?.idTask,
                           state: .unobservable, phase: .unknown,
                           noProgressMS: nil, reason: "probe failed")
        }
    }

    /// Mark one identified slot unobservable for this tick without touching
    /// its baseline (used when is_processing is missing or malformed).
    @discardableResult
    public func observeUnobservable(slotID: Int,
                                    engineGeneration: UInt64) -> Verdict? {
        guard lastGeneration == engineGeneration,
              baselines[slotID] != nil else {
            return nil
        }
        baselines[slotID]?.unobservableInRun = true
        return Verdict(slotID: slotID, engineGeneration: engineGeneration,
                       idTask: baselines[slotID]?.idTask, state: .unobservable,
                       phase: .unknown, noProgressMS: nil,
                       reason: "is_processing missing or malformed")
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
              let removed = baselines.removeValue(forKey: slotID) else {
            return nil
        }
        return Verdict(slotID: slotID, engineGeneration: engineGeneration,
                       idTask: removed.idTask,
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
                let phase = Self.phase(forDecoded: o.decoded)
                baselines[o.slotID] = Baseline(
                    idTask: idTask, promptProcessed: np, decoded: o.decoded,
                    decodedKnown: o.decoded != nil,
                    sinceMonoMS: o.observedAtMonotonicMS,
                    lastPhase: phase,
                    unobservableInRun: false)
                // The generation change is the identity event here; the phase
                // still follows n_decoded. A positive first value observes
                // decode but cannot prove the boundary was crossed this tick.
                let reason = (o.decoded ?? 0) > 0
                    ? "engine generation changed; baseline re-established; "
                        + "decode observed, prefill->decode boundary unknown"
                    : "engine generation changed; baseline re-established"
                return verdict(o, .baselineReset, phase, nil, reason)
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

        // A busy sample without a usable task id cannot be attributed to any
        // task: unobservable, whether or not a baseline exists. A sentinel
        // task id is never invented and no baseline is fabricated (review
        // 2026-11-08).
        guard let idTask = o.idTask else {
            baselines[o.slotID]?.unobservableInRun = true
            return Verdict(slotID: o.slotID, engineGeneration: o.engineGeneration,
                           idTask: nil, state: .unobservable, phase: .unknown,
                           noProgressMS: nil,
                           reason: "busy sample without id_task; unobservable")
        }

        guard let base = baselines[o.slotID] else {
            let phase = Self.phase(forDecoded: o.decoded)
            baselines[o.slotID] = Baseline(
                idTask: idTask, promptProcessed: np,
                decoded: o.decoded, decodedKnown: o.decoded != nil,
                sinceMonoMS: o.observedAtMonotonicMS,
                lastPhase: phase, unobservableInRun: false)
            // A first sample that is already positive observes decode but
            // cannot prove where the boundary was; a zero or a missing value
            // makes no claim beyond pre-decode/unknown.
            if let nd = o.decoded, nd > 0 {
                return verdict(
                    o, .phaseTransitionOrUnknown, .decode, nil,
                    "baseline established; decode observed, "
                        + "prefill->decode boundary unknown")
            }
            return verdict(o, .progressing, phase, nil,
                           "baseline established")
        }

        // Task identity changed: new baseline, nothing inherited. The reset
        // event does not fabricate a boundary, but the phase still follows
        // the value this sample carries: a first positive sight of the new
        // task is decode with an unknown boundary.
        if idTask != base.idTask {
            let phase = Self.phase(forDecoded: o.decoded)
            baselines[o.slotID] = Baseline(
                idTask: idTask, promptProcessed: np, decoded: o.decoded,
                decodedKnown: o.decoded != nil,
                sinceMonoMS: o.observedAtMonotonicMS,
                lastPhase: phase,
                unobservableInRun: false)
            let reason = (o.decoded ?? 0) > 0
                ? "id_task changed (\(base.idTask) -> \(idTask)); baseline "
                    + "reset; decode observed, prefill->decode boundary unknown"
                : "id_task changed (\(base.idTask) -> \(idTask)); baseline reset"
            return verdict(o, .baselineReset, phase, nil, reason)
        }

        let ndKnownNow = o.decoded != nil
        // Growth requires a value on BOTH ends of the interval. A counter
        // merely APPEARING this tick establishes its baseline; the field
        // becoming visible is not evidence it advanced (review 2026-11-08).
        let ndAdvanced = ndKnownNow && base.decodedKnown
            && o.decoded! > base.decoded!
        let npAdvanced = np > base.promptProcessed
        let npRegressed = np < base.promptProcessed
        let ndRegressed = ndKnownNow && base.decodedKnown
            && o.decoded! < base.decoded!
        // The decode counter was observed before and is missing now: the
        // sample is unobservable for decode and must BLOCK the current
        // static span — it is not a prefill->decode boundary.
        let ndDisappeared = base.decodedKnown && !ndKnownNow

        // Counter regression or reset: re-baseline, never a stall. Phase is
        // still read from n_decoded on this sample; a rollback to a known
        // zero is a clean pre-decode baseline.
        if npRegressed || ndRegressed {
            let phase = Self.phase(forDecoded: o.decoded)
            baselines[o.slotID] = Baseline(
                idTask: idTask, promptProcessed: np,
                decoded: o.decoded, decodedKnown: ndKnownNow,
                sinceMonoMS: o.observedAtMonotonicMS,
                lastPhase: phase,
                unobservableInRun: false)
            return verdict(o, .baselineReset, phase, nil,
                           "counter regression; baseline re-established")
        }

        if npAdvanced || ndAdvanced {
            // The boundary is confirmed only by a positive value advancing a
            // known zero of the SAME task. A missing decode field cannot
            // confirm anything; it keeps the last known phase.
            let boundaryConfirmed = ndKnownNow && base.decodedKnown
                && base.decoded == 0 && o.decoded! > 0
            let firstPositiveSight = ndKnownNow && !base.decodedKnown
                && o.decoded! > 0
            let phase: Phase
            if let nd = o.decoded {
                phase = nd == 0 ? .prefill : .decode
            } else {
                phase = base.decodedKnown ? base.lastPhase : .unknown
            }
            baselines[o.slotID] = Baseline(
                idTask: idTask, promptProcessed: np,
                decoded: o.decoded, decodedKnown: ndKnownNow,
                sinceMonoMS: o.observedAtMonotonicMS,
                lastPhase: phase, unobservableInRun: false)
            if boundaryConfirmed {
                return verdict(
                    o, .phaseBoundaryConfirmed, .decode, 0,
                    "prefill->decode boundary confirmed "
                        + "(n_decoded 0 -> \(o.decoded!))")
            }
            if firstPositiveSight {
                return verdict(
                    o, .phaseTransitionOrUnknown, .decode, 0,
                    "decode observed for the first time; "
                        + "prefill->decode boundary unknown")
            }
            return verdict(o, .progressing, phase, 0, "counters advanced")
        }
        if ndDisappeared {
            baselines[o.slotID]?.unobservableInRun = true
            return Verdict(slotID: o.slotID, engineGeneration: o.engineGeneration,
                           idTask: o.idTask, state: .unobservable,
                           phase: .unknown, noProgressMS: nil,
                           reason: "decode counter seen before is missing now; unobservable")
        }

        // First sight of the decode counter for this task. The appearance is
        // not advancement (a value must exist on both ends of the interval),
        // so the static span continues; the phase conclusion changes at once:
        // zero is pre-decode, positive is decode with the boundary known only
        // if a zero was observed earlier for this task.
        var firstPositiveDecode = false
        if ndKnownNow && !base.decodedKnown {
            let nd = o.decoded!
            baselines[o.slotID]?.decoded = nd
            baselines[o.slotID]?.decodedKnown = true
            baselines[o.slotID]?.lastPhase = nd == 0 ? .prefill : .decode
            firstPositiveDecode = nd > 0
        }

        // Neither counter advanced. The closing tick of a static run carries
        // its own dt (the R1 off-by-one-tick lesson).
        let span = o.observedAtMonotonicMS - base.sinceMonoMS
        let phaseNow = baselines[o.slotID]?.lastPhase ?? base.lastPhase

        if span >= config.candidateWindowMS && !base.unobservableInRun {
            return verdict(o, .candidateStall, phaseNow, span,
                           "candidate stall: no counter advance within the window")
        }

        // A never-seen decode counter with no zero sample cannot support a
        // prefill-complete claim: live n_prompt_tokens grows during decode
        // and can carry a stale value at a new task's start. A first positive
        // value is decode, but the boundary is unknown.
        if firstPositiveDecode {
            baselines[o.slotID]?.unobservableInRun = base.unobservableInRun
            return verdict(
                o, .phaseTransitionOrUnknown, .decode, span,
                "decode observed for the first time; "
                    + "prefill->decode boundary unknown")
        }

        baselines[o.slotID]?.unobservableInRun = base.unobservableInRun
        return verdict(o, .observingNoProgress, phaseNow, span,
                       "no counter advance yet")
    }

    /// Phase is decided by the decode counter alone (owner ruling
    /// 2026-11-08): a known zero is pre-decode, a positive value is decode,
    /// and a missing value makes no phase claim.
    private static func phase(forDecoded decoded: Int?) -> Phase {
        guard let decoded else { return .unknown }
        return decoded == 0 ? .prefill : .decode
    }

    private func verdict(_ o: Observation, _ state: State, _ phase: Phase,
                         _ noProgressMS: UInt64?, _ reason: String) -> Verdict {
        Verdict(slotID: o.slotID, engineGeneration: o.engineGeneration,
                idTask: (state == .unobservable) ? nil : o.idTask,
                state: state, phase: phase, noProgressMS: noProgressMS,
                reason: reason)
    }
}

/// Strict `/slots` ingestion for the monitor (review 2026-11-08).
///
/// Non-200 responses, unparseable payloads and probe failures observe no
/// counters at all: every tracked slot is marked unobservable, so an outage
/// can never confirm a stall. Field parsing is strict:
/// - `id` missing or non-integer -> the slot cannot be identified. A lone
///   malformed slot marks every tracked baseline unobservable; among several
///   slots it is simply skipped (its identity is unknowable).
/// - `is_processing` only a genuine JSON boolean yields true/false; anything
///   else is nil -> unobservable for that slot (never misread as idle).
/// - counter fields must be genuine JSON integers; booleans and floats are
///   nil, never truncated into a fabricated identity or count.
/// - a tracked slot missing from a fully identifiable list is reset via
///   `observeAbsence` (owner ruling: slot gone -> reset). With unidentifiable
///   entries present, absence is ambiguous and no reset is performed.
nonisolated enum SlotProgressIngest {

    static func ingest(data: Data, statusCode: Int, engineGeneration: UInt64,
                       into monitor: SlotProgressMonitor) -> [SlotProgressMonitor.Verdict] {
        guard statusCode == 200 else {
            return monitor.observeProbeFailure(engineGeneration: engineGeneration)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let slots = object as? [[String: Any]] else {
            return monitor.observeProbeFailure(engineGeneration: engineGeneration)
        }
        if slots.isEmpty {
            // An empty list cannot prove anything about the tracked slots:
            // unobservable, never idle (mirrors the lossy parser's rule).
            return monitor.observeProbeFailure(engineGeneration: engineGeneration)
        }

        /// Only a genuine JSON integer is an integer: booleans (CFBoolean)
        /// and floating-point representations are rejected, so a malformed
        /// field degrades to nil instead of a fabricated identity or count.
        func intField(_ dict: [String: Any], _ key: String) -> Int? {
            guard let n = dict[key] as? NSNumber,
                  CFGetTypeID(n) == CFNumberGetTypeID(),
                  !CFNumberIsFloatType(n) else {
                return nil
            }
            return n.intValue
        }
        /// Only a genuine JSON boolean is a boolean; integers are rejected so
        /// a malformed field degrades to unobservable, never to idle.
        func boolField(_ dict: [String: Any], _ key: String) -> Bool? {
            guard let n = dict[key] as? NSNumber,
                  CFGetTypeID(n) == CFBooleanGetTypeID() else {
                return nil
            }
            return n.boolValue
        }

        var verdicts: [SlotProgressMonitor.Verdict] = []
        var seen: Set<Int> = []
        var skippedUnidentifiable = false
        for s in slots {
            guard let slotID = intField(s, "id") else {
                skippedUnidentifiable = true
                continue // unidentifiable: handled by the malformed rule below
            }
            seen.insert(slotID)
            let processing = boolField(s, "is_processing")
            if processing == nil {
                // unidentifiable state: keep the slot's prior baseline out of
                // this tick by reporting it unobservable via a probe-style
                // block when it is tracked
                if let v = monitor.observeUnobservable(
                    slotID: slotID, engineGeneration: engineGeneration) {
                    verdicts.append(v)
                }
                continue
            }
            let nextToken = (s["next_token"] as? [[String: Any]])?.first
            let o = SlotProgressMonitor.Observation(
                slotID: slotID,
                engineGeneration: engineGeneration,
                idTask: intField(s, "id_task"),
                isProcessing: processing,
                promptProcessed: intField(s, "n_prompt_tokens_processed"),
                promptTotal: intField(s, "n_prompt_tokens"),
                decoded: nextToken.flatMap { intField($0, "n_decoded") },
                observedAtMonotonicMS: UInt64(
                    DispatchTime.now().uptimeNanoseconds / 1_000_000))
            verdicts.append(monitor.observe(o))
        }
        if seen.isEmpty {
            // every slot in the payload was unidentifiable: no tracked slot
            // was observed this tick
            verdicts.append(contentsOf: monitor.observeProbeFailure(
                engineGeneration: engineGeneration))
        } else if !skippedUnidentifiable {
            // A tracked slot that vanished from a fully identifiable list is
            // gone: reset its baseline. With an unidentifiable sibling the
            // malformed entry might BE the missing slot, so absence is
            // ambiguous and no reset is performed.
            for absent in monitor.trackedSlots(
                engineGeneration: engineGeneration) where !seen.contains(absent) {
                if let v = monitor.observeAbsence(
                    slotID: absent, engineGeneration: engineGeneration) {
                    verdicts.append(v)
                }
            }
        }
        return verdicts
    }
}
