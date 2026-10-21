import Foundation

// G3 PER-ARM KV CACHE — the production wiring contract for "each arm owns its
// OWN mutable KV cache, and a refused step terminates THAT arm".
//
// WHY THIS FILE EXISTS (the trace that preceded it):
//   `G3DualArmRunner` seals the two owners and routes each arm through
//   `G3ExecutionDispatch.g3`. The MLX executor's gated method then ran
//   `continueExecution`, whose forward calls `context.model(_, cache: nil)` — the
//   RECOMPUTE path, which allocates NO persistent KV. So the write-boundary
//   observer (added in the fork) had nothing to observe, and `isolationAborted`
//   could never be checked between steps because there were no steps over a cache.
//   This file supplies the missing layer: a per-arm cache BOUNDARY (implemented by
//   the MLX layer with a real `KVCacheSimple`), a per-arm STEP LEDGER that decides
//   commit-vs-terminate, and a PAIR guard that refuses two arms sharing one
//   mutable cache. It is MLX-free so the control flow is model-free testable.
//
// THE COMMIT RULE (the reviewer's "拒绝时终止该 arm"):
//   `G3ArmCacheSession.runStep(forward:candidateToken:)` runs the forward, then
//   consults the cache's abort latch. A candidate token is committed ONLY if the
//   cache did not abort; on abort the token is DISCARDED, the arm is TERMINATED,
//   and every later step is refused without running a forward. Partial output is
//   never marked settled — `isTerminated` / `committedTokens` make that explicit.
//
// NO FALLBACK:
//   A terminated session never silently switches to another cache or to the
//   standard route; `runStep` returns `.refusedAfterTermination` and the driver
//   must surface it. The runner turns that into `settled: false` in the report.

// MARK: - The per-arm cache boundary

/// The narrow surface an arm's mutable KV cache must expose so the generation
/// loop can decide commit-vs-terminate per step. Implemented by the MLX layer
/// over a real `KVCacheSimple` (which already has `beginStep` / `isolationAborted`
/// / `isolationAbortReason` from the fork's native seam); model-free tests use a
/// fake.
///
/// `beginStep()` MUST reset the per-step abort latch so `isolationAborted` reflects
/// ONLY the step currently in flight — EXCEPT once a termination has been latched:
/// a termination is irreversible, so `beginStep()` must leave `isolationAborted`
/// true rather than make a dead arm look live. The session calls it immediately
/// before each forward, which is why the session — not the generation loop — owns
/// the reset.
///
/// One boundary may aggregate SEVERAL native caches for the same arm (a real
/// transformer needs one KV cache PER LAYER). Aggregation must be conservative:
/// `isolationAborted` is true if ANY underlying cache refused this step, and
/// `beginStep()` resets every one of them while the arm is live, so the step is
/// judged as a whole.
public protocol G3ArmCacheBoundary: AnyObject {
    func beginStep()
    var isolationAborted: Bool { get }
    var isolationAbortReason: String? { get }
    /// The arm-level termination latch held by the owning gateway, or nil while
    /// the arm is live. Distinct from a cache's per-step `isolationAborted`: this
    /// latch survives `beginStep()`. Defaults to nil for boundaries with no
    /// gateway (a bare cache, a test double).
    var terminatedReason: String? { get }
    /// Adopt the arm's adjudication domain (see ``G3Adjudication``). A boundary
    /// that returns `true` has promised to write its termination latch INSIDE
    /// that domain and to hand the latched reason to `report`, still inside it.
    /// Without that promise, "read the terminal state, then commit" is two
    /// statements with a window between them, and the commit is not linearized
    /// against termination. `report` may be invoked from any thread.
    @discardableResult
    func adoptTerminationAdjudication(
        _ domain: G3Adjudication, report: @escaping @Sendable (String) -> Void
    ) -> Bool
}

public extension G3ArmCacheBoundary {
    var terminatedReason: String? { nil }
    /// The default is NOT participation. A boundary that leaves this unimplemented
    /// can still publish a latch, but nothing serializes that write against the
    /// commit region — so `G3ArmCacheSession.commitDelivery` refuses it
    /// fail-closed rather than claiming a linearization it does not have.
    @discardableResult
    func adoptTerminationAdjudication(
        _ domain: G3Adjudication, report: @escaping @Sendable (String) -> Void
    ) -> Bool { false }
}

// MARK: - Step outcome

/// What happened to one generation step. Only `.committed` may advance the arm's
/// output/state; the other cases mean the step must not be settled.
public enum G3ArmStepOutcome: Equatable, Sendable {
    /// The forward completed and the cache did NOT abort: the token is committed.
    case committed(token: Int)
    /// The cache refused this step's KV write: the token is DISCARDED and the arm
    /// is terminated. No partial output from this step is kept.
    case aborted(reason: String)
    /// The arm was already terminated by an earlier step: no forward was run.
    case refusedAfterTermination(reason: String)
}

// MARK: - Errors

public enum G3PerArmCacheError: Error, Equatable, Sendable {
    /// The two arms were handed the SAME boundary object (one mutable cache).
    case armsShareMutableCache(String)
    /// Both sessions claim the same arm identity, so one arm could overwrite the other.
    case armsShareArmIdentity(String)
    /// A driver tried to run a cache-backed step on an arm with no cache session.
    case missingCacheSession(String)
    /// The arm's cache refused a step; the arm is terminated and its output is
    /// NOT settled. Carries the refusal reason exactly.
    case armTerminated(reason: String)
    /// At least one of the arm's native caches exposes no write-boundary seam, so
    /// the arm cannot be gated. Refused BEFORE any forward (fail closed) rather
    /// than silently running with an unobserved mutable cache.
    case unobservableCache(String)
    /// A second continuation would prefill the same session/cache again, appending
    /// the prefix twice. The session is one continuation; refused fail closed.
    case cacheSessionAlreadyUsed(String)
    /// A run tried to settle (consume) its bound prefix a second time. The consume
    /// is one-way and must happen at most once per run; refused fail closed.
    case bindingAlreadySettled(String)
}

// MARK: - Run ledger: three independent settlement axes

/// One G3 delivery stage. The stages are recorded separately because a run can
/// ENTER settlement and CONSUME its binding and still fail to deliver: collapsing
/// them into one Boolean is exactly the false claim this ledger removes.
public enum G3DeliveryPhase: String, Codable, Hashable, Sendable, CaseIterable {
    case generation
    case registration
    case decode
    case commit
}

/// What happened to one delivery stage. `skipped` is a positive statement (for
/// example: no during-generation registrar was wired), not a disguised success.
public enum G3PhaseState: String, Codable, Hashable, Sendable {
    case notEntered
    case succeeded
    case failed
    case skipped
}

public struct G3PhaseRecord: Codable, Hashable, Sendable {
    public let state: G3PhaseState
    public let detail: String?

    public init(_ state: G3PhaseState = .notEntered, detail: String? = nil) {
        self.state = state
        self.detail = detail
    }

    public static let notEntered = G3PhaseRecord(.notEntered)

    public static func succeeded(_ detail: String? = nil) -> G3PhaseRecord {
        G3PhaseRecord(.succeeded, detail: detail)
    }

    public static func failed(_ detail: String) -> G3PhaseRecord {
        G3PhaseRecord(.failed, detail: detail)
    }

    public static func skipped(_ detail: String? = nil) -> G3PhaseRecord {
        G3PhaseRecord(.skipped, detail: detail)
    }
}

/// The four delivery stages of one arm, each with its own result. `completed`
/// is the only aggregate that may be used to claim delivery; it never stands in
/// for `settleEntered` or `bindingConsumed`.
public struct G3DeliveryReport: Codable, Hashable, Sendable {
    public let generation: G3PhaseRecord
    public let registration: G3PhaseRecord
    public let decode: G3PhaseRecord
    public let commit: G3PhaseRecord

    public init(
        generation: G3PhaseRecord = .notEntered,
        registration: G3PhaseRecord = .notEntered,
        decode: G3PhaseRecord = .notEntered,
        commit: G3PhaseRecord = .notEntered
    ) {
        self.generation = generation
        self.registration = registration
        self.decode = decode
        self.commit = commit
    }

    public static let notEntered = G3DeliveryReport()

    public func phase(_ phase: G3DeliveryPhase) -> G3PhaseRecord {
        switch phase {
        case .generation: return generation
        case .registration: return registration
        case .decode: return decode
        case .commit: return commit
        }
    }

    /// Generation, decode and commit succeeded, and registration either ran or
    /// was explicitly not applicable. A failed/skipped commit is never complete.
    public var completed: Bool {
        generation.state == .succeeded
            && decode.state == .succeeded
            && commit.state == .succeeded
            && (registration.state == .succeeded || registration.state == .skipped)
    }
}

/// Where a cancellation was observed relative to the settlement linearization
/// point. A single final `Task.isCancelled` cannot answer this: once the binding
/// has been consumed, a later cancellation cannot undo the consumption.
public enum G3CancellationPoint: String, Codable, Hashable, Sendable {
    case notCancelled
    case duringGeneration
    case beforeSettlement
    case afterSettlement
    case afterDecode
    /// Sampled INSIDE the commit adjudication region — this is the run's
    /// cancellation cutoff, the last point at which a cancellation can still
    /// refuse the delivery.
    case atCommitCutoff
    /// Observed AFTER the commit region already recorded `commit=succeeded`.
    /// The delivery stands and the consumed fact is not rolled back: a sampling
    /// point behind the cutoff cannot un-commit, and pretending otherwise would
    /// turn a position rule into a false atomic-cancel guarantee.
    case afterCommitCutoff
}

/// The settlement axis, kept distinct from both termination sources.
public enum G3SettlementPhase: String, Codable, Hashable, Sendable {
    case notEntered
    case refused
    case entered
    case bindingConsumeFailed
    case consumed
}

/// A single observation of ALL terminal sources. The precedence is fixed and
/// explicit: an external gateway termination wins over the session's own
/// tombstone, which wins over the settlement record. Reading only
/// `session.abortReason` — as the runner used to — misses an independent gateway
/// termination that never touched the session.
public struct G3TerminalSnapshot: Codable, Hashable, Sendable {
    public let gatewayTerminationReason: String?
    public let sessionTombstoneReason: String?
    public let settlementPhase: G3SettlementPhase

    public init(
        gatewayTerminationReason: String? = nil,
        sessionTombstoneReason: String? = nil,
        settlementPhase: G3SettlementPhase = .notEntered
    ) {
        self.gatewayTerminationReason = gatewayTerminationReason
        self.sessionTombstoneReason = sessionTombstoneReason
        self.settlementPhase = settlementPhase
    }

    public static let none = G3TerminalSnapshot()

    /// The ordering rule itself, recorded so a report cannot silently change it.
    public static let precedence = "gateway_latch>session_tombstone>settlement"

    public var effectiveTerminationReason: String? {
        gatewayTerminationReason ?? sessionTombstoneReason
    }

    public var isTerminated: Bool { effectiveTerminationReason != nil }
}

/// One immutable view of the three axes. `settleEntered`, `bindingConsumed` and
/// `delivery` are facts about different transitions and must not be collapsed.
public struct G3RunLedgerSnapshot: Codable, Hashable, Sendable {
    public let armID: String
    public let settleEntered: Bool
    public let bindingConsumed: Bool
    public let settlementPhase: G3SettlementPhase
    public let settlementRefusal: String?
    public let bindingConsumeFailure: String?
    public let delivery: G3DeliveryReport
    public let cancellation: G3CancellationPoint
    public let postSettlementTermination: String?
    /// Ordered transition names (`settlement.entered`, `binding.consumed`, ...).
    /// They make the G4/G5 ordering inspectable instead of inferable.
    public let transitions: [String]

    public init(
        armID: String,
        settleEntered: Bool = false,
        bindingConsumed: Bool = false,
        settlementPhase: G3SettlementPhase = .notEntered,
        settlementRefusal: String? = nil,
        bindingConsumeFailure: String? = nil,
        delivery: G3DeliveryReport = .notEntered,
        cancellation: G3CancellationPoint = .notCancelled,
        postSettlementTermination: String? = nil,
        transitions: [String] = []
    ) {
        self.armID = armID
        self.settleEntered = settleEntered
        self.bindingConsumed = bindingConsumed
        self.settlementPhase = settlementPhase
        self.settlementRefusal = settlementRefusal
        self.bindingConsumeFailure = bindingConsumeFailure
        self.delivery = delivery
        self.cancellation = cancellation
        self.postSettlementTermination = postSettlementTermination
        self.transitions = transitions
    }

    public static func notEntered(armID: String) -> G3RunLedgerSnapshot {
        G3RunLedgerSnapshot(armID: armID)
    }

    /// The only aggregate the runner may use for `settled`: the run entered the
    /// one gate, its binding was consumed, every delivery stage completed, and no
    /// termination was observed after the gate.
    public var isFullyDelivered: Bool {
        settleEntered && bindingConsumed && delivery.completed
            && postSettlementTermination == nil
    }
}

// MARK: - Shared adjudication domain

/// ONE serialization domain for the transitions that must not interleave:
/// settlement entry, termination latching (session tombstone AND gateway latch),
/// and the delivery commit.
///
/// WHY A DOMAIN INSTEAD OF A PRE-COMMIT CHECK. `guard terminal == nil else {…}`
/// followed by `commit()` is two statements. Another thread may latch a
/// termination in between, and the run then reports `commit=succeeded` for an arm
/// that died first; no amount of passing tests rules that out, because the
/// window is a scheduling accident. The window closes only when the read of every
/// terminal source, the decision, and the state transition live in ONE mutually
/// exclusive region that every participant enters. The participants are:
///   * ``G3RunSettlement/settle(_:)`` — terminal read → single-use transition → consume;
///   * ``G3ArmCacheSession/terminate(reason:)`` and ``G3ArmCacheSession/commitDelivery(isCancelled:finalize:)``;
///   * ``G3RunLedger`` — its transitions take THIS lock, not a second one;
///   * the boundary's gateway latch, through
///     ``G3ArmCacheBoundary/adoptTerminationAdjudication(_:report:)``.
///
/// The lock is RECURSIVE by design: adjudicated regions are composed of helpers
/// that each enter the domain (the commit region reads the terminal snapshot,
/// which reads the ledger and the gateway). Recursion stays on one thread inside
/// read-modify-write helpers: no region performs I/O or awaits while holding the
/// domain, and the only nested lock acquired is a boundary's own short latch
/// lock. Lock order is always domain → boundary/gateway lock, never the reverse.
public final class G3Adjudication: @unchecked Sendable {
    /// Human-readable identity, recorded in the ledger so evidence names the
    /// domain a commit was adjudicated under instead of asserting one.
    public let domain: String
    let lock = NSRecursiveLock()

    public init(domain: String) { self.domain = domain }

    public func adjudicate<R>(_ body: () throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    /// Non-blocking entry. The linearization tests use it to prove two
    /// participants genuinely exclude each other instead of merely happening to
    /// interleave favourably: while one holds the domain, the other must fail to
    /// enter.
    @discardableResult
    public func tryAdjudicate<R>(_ body: () throws -> R) rethrows -> R? {
        guard lock.try() else { return nil }
        defer { lock.unlock() }
        return try body()
    }
}

/// A mutable, per-attempt ledger owned by one arm's cache session. The runner
/// starts a fresh ledger before dispatch; the production executor records into
/// it. The three axes are independently readable and independently snapshotted.
public final class G3RunLedger: @unchecked Sendable {
    public let armID: String
    /// The domain this ledger's transitions are adjudicated under. A ledger owned
    /// by a session shares the session's domain, which is what makes the commit
    /// transition and the terminal read one region; a standalone ledger (tests,
    /// a refused attempt with no session) creates its own.
    public let adjudication: G3Adjudication
    private var lock: NSRecursiveLock { adjudication.lock }
    private var _settleEntered = false
    private var _bindingConsumed = false
    private var _settlementRefusal: String?
    private var _bindingConsumeFailure: String?
    private var _generation = G3PhaseRecord.notEntered
    private var _registration = G3PhaseRecord.notEntered
    private var _decode = G3PhaseRecord.notEntered
    private var _commit = G3PhaseRecord.notEntered
    private var _cancellation = G3CancellationPoint.notCancelled
    private var _postSettlementTermination: String?
    private var _transitions: [String] = []

    public init(armID: String, adjudication: G3Adjudication? = nil) {
        self.armID = armID
        self.adjudication = adjudication ?? G3Adjudication(domain: "run:\(armID)")
    }

    public var settleEntered: Bool {
        lock.lock(); defer { lock.unlock() }
        return _settleEntered
    }

    public var bindingConsumed: Bool {
        lock.lock(); defer { lock.unlock() }
        return _bindingConsumed
    }

    public var cancellation: G3CancellationPoint {
        lock.lock(); defer { lock.unlock() }
        return _cancellation
    }

    public var postSettlementTermination: String? {
        lock.lock(); defer { lock.unlock() }
        return _postSettlementTermination
    }

    public var settlementPhase: G3SettlementPhase {
        lock.lock(); defer { lock.unlock() }
        if _bindingConsumed { return .consumed }
        if _bindingConsumeFailure != nil { return .bindingConsumeFailed }
        if _settleEntered { return .entered }
        if _settlementRefusal != nil { return .refused }
        return .notEntered
    }

    public var delivery: G3DeliveryReport {
        lock.lock(); defer { lock.unlock() }
        return G3DeliveryReport(
            generation: _generation, registration: _registration,
            decode: _decode, commit: _commit)
    }

    public var snapshot: G3RunLedgerSnapshot {
        lock.lock(); defer { lock.unlock() }
        return G3RunLedgerSnapshot(
            armID: armID,
            settleEntered: _settleEntered,
            bindingConsumed: _bindingConsumed,
            settlementPhase: settlementPhaseLocked(),
            settlementRefusal: _settlementRefusal,
            bindingConsumeFailure: _bindingConsumeFailure,
            delivery: deliveryLocked(),
            cancellation: _cancellation,
            postSettlementTermination: _postSettlementTermination,
            transitions: _transitions)
    }

    public func recordPhase(_ phase: G3DeliveryPhase, _ record: G3PhaseRecord) {
        lock.lock()
        switch phase {
        case .generation: _generation = record
        case .registration: _registration = record
        case .decode: _decode = record
        case .commit: _commit = record
        }
        _transitions.append("delivery.\(phase.rawValue)=\(record.state.rawValue)")
        lock.unlock()
    }

    public func recordCancellation(_ point: G3CancellationPoint, detail: String? = nil) {
        lock.lock()
        if _cancellation == .notCancelled { _cancellation = point }
        let suffix = detail.map { ":\($0)" } ?? ""
        _transitions.append("cancellation=\(point.rawValue)\(suffix)")
        lock.unlock()
    }

    public func markSettlementRefused(_ reason: String) {
        lock.lock()
        if !_settleEntered && _settlementRefusal == nil {
            _settlementRefusal = reason
            _transitions.append("settlement.refused:\(reason)")
        }
        lock.unlock()
    }

    public func markSettleEntered() {
        lock.lock()
        if !_settleEntered {
            _settleEntered = true
            _transitions.append("settlement.entered")
        }
        lock.unlock()
    }

    public func markBindingConsumed() {
        lock.lock()
        _bindingConsumed = true
        _transitions.append("binding.consumed")
        lock.unlock()
    }

    public func markBindingConsumeFailed(_ reason: String) {
        lock.lock()
        _bindingConsumeFailure = reason
        _transitions.append("binding.consume_failed:\(reason)")
        lock.unlock()
    }

    public func markPostSettlementTermination(_ reason: String) {
        lock.lock()
        if _postSettlementTermination == nil {
            _postSettlementTermination = reason
            _transitions.append("termination.after_settlement:\(reason)")
        }
        lock.unlock()
    }

    /// Records WHICH domain serialized the commit. Kept as a transition so a
    /// report can point at the mechanism rather than at a check.
    public func markCommitAdjudicatedUnder(_ domain: String) {
        lock.lock()
        _transitions.append("commit.adjudicated_under=\(domain)")
        lock.unlock()
    }

    /// Lock-held forms are kept because the domain is recursive but the aggregate
    /// readers still want one acquisition for a consistent multi-field snapshot.
    private func settlementPhaseLocked() -> G3SettlementPhase {
        if _bindingConsumed { return .consumed }
        if _bindingConsumeFailure != nil { return .bindingConsumeFailed }
        if _settleEntered { return .entered }
        if _settlementRefusal != nil { return .refused }
        return .notEntered
    }

    private func deliveryLocked() -> G3DeliveryReport {
        G3DeliveryReport(
            generation: _generation, registration: _registration,
            decode: _decode, commit: _commit)
    }
}

// MARK: - Per-arm step ledger

/// A weak, thread-safe late-binding hop from a boundary's latch report back to
/// the session that adopted the domain. The boundary is constructed BEFORE the
/// session (a gateway belongs to the cache, the session wraps the cache), so the
/// report closure cannot capture `self` during initialization.
final class G3TerminationHop: @unchecked Sendable {
    private let lock = NSLock()
    weak var target: G3ArmCacheSession?

    func report(_ reason: String) {
        lock.lock()
        let session = target
        lock.unlock()
        session?.noteExternallyLatchedTermination(reason)
    }
}

/// One arm's private KV cache plus the commit/terminate ledger for its steps.
///
/// Driven sequentially by that arm's generation loop (one step at a time), which
/// is the only access pattern the production executor uses; it is `@unchecked
/// Sendable` for the same reason the gateway is — it crosses the async boundary
/// into `container.perform` but is touched by one arm only.
public final class G3ArmCacheSession: @unchecked Sendable {
    public let armID: String
    public let boundary: G3ArmCacheBoundary

    /// THE arm's adjudication domain. It replaces the session's own lock, and the
    /// run ledger and the settlement seam are handed the SAME domain, so
    /// settlement / termination / commit are serialized by one mechanism rather
    /// than by three locks that happen to be held at the same time.
    public let adjudication: G3Adjudication
    private var lock: NSRecursiveLock { adjudication.lock }

    /// Whether the boundary accepted the domain, i.e. whether its termination
    /// latch is written INSIDE the region the commit reads. `false` means the
    /// boundary publishes a latch nothing serializes against the commit, so
    /// ``commitDelivery(isCancelled:finalize:)`` refuses the run fail-closed.
    public private(set) var boundaryAdoptsAdjudication: Bool = false
    /// Late-binding hop: a boundary is built before the session that owns it, so
    /// the latch report is routed through this box instead of `self`.
    private let terminationHop = G3TerminationHop()

    /// The lock protects the ledger. The production executor drives a session
    /// sequentially, but a SECOND concurrent `runStep` is a wiring error: it is
    /// detected and refused instead of racing the commit, and a concurrent
    /// `terminate` is observed before the token is appended.
    private var _committedTokens: [Int] = []
    private var _abortReason: String?
    private var _stepCount = 0
    private var _isStepping = false
    private var _continuationClaimed = false
    /// One fresh ledger per run attempt. The runner replaces it before dispatch;
    /// the executor writes the three axes into the object it finds here.
    private var _runLedger: G3RunLedger?

    /// Tokens committed by steps that completed WITHOUT an abort. On termination
    /// this is the partial prefix — deliberately NOT a settled result.
    public var committedTokens: [Int] {
        lock.lock(); defer { lock.unlock() }
        return _committedTokens
    }
    /// Non-nil once any step was refused (or the owner terminated explicitly).
    public var abortReason: String? {
        lock.lock(); defer { lock.unlock() }
        return _abortReason
    }
    /// Number of steps whose forward was actually entered.
    public var stepCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _stepCount
    }

    public init(
        armID: String, boundary: G3ArmCacheBoundary,
        adjudication: G3Adjudication? = nil
    ) {
        self.armID = armID
        self.boundary = boundary
        let domain = adjudication ?? G3Adjudication(domain: "arm:\(armID)")
        self.adjudication = domain
        self.boundaryAdoptsAdjudication = boundary.adoptTerminationAdjudication(
            domain
        ) { [terminationHop] reason in
            terminationHop.report(reason)
        }
        // Phase 2: now that every stored property is set, the hop can route back
        // to this session. Weak, because the boundary (and therefore the gateway)
        // may outlive an arm that was dropped without being released.
        terminationHop.target = self
    }

    /// What ``commitDelivery(isCancelled:finalize:)`` decided, so the caller can
    /// map the adjudication onto its own error type instead of re-deriving it.
    public enum G3CommitOutcome: Equatable, Sendable {
        case committed
        case refusedTermination(reason: String)
        case refusedCancellation
        case refusedBoundaryNotAdjudicating
    }

    /// The effective predicate: a gateway latch is a termination even when this
    /// session never wrote a tombstone. Reading only `abortReason` (the old
    /// definition) is exactly the G5 hole.
    public var isTerminated: Bool { terminalSnapshot().isTerminated }

    /// The gateway's arm-level latch, kept separately so a report can show which
    /// source fired instead of collapsing both into one string.
    public var gatewayTerminationReason: String? { boundary.terminatedReason }

    /// This session's own refusal reason (a refused KV step, a cancellation, a
    /// release). Independent of the gateway latch.
    public var sessionTombstoneReason: String? { abortReason }

    /// One observation of ALL terminal sources, using the fixed precedence
    /// `gateway_latch > session_tombstone > settlement`. The provider-backed
    /// settlement gate calls this immediately before consuming, which makes the
    /// gate entry the linearization point: a terminal observed before it refuses
    /// the settle; one observed after it is recorded and cannot undo the consume.
    public func terminalSnapshot() -> G3TerminalSnapshot {
        lock.lock()
        let gateway = boundary.terminatedReason
        let tombstone = _abortReason
        let settlement = _runLedger?.settlementPhase ?? .notEntered
        lock.unlock()
        return G3TerminalSnapshot(
            gatewayTerminationReason: gateway,
            sessionTombstoneReason: tombstone,
            settlementPhase: settlement)
    }

    /// The reason the production executor must refuse this arm BEFORE entering a
    /// generation flow and again BEFORE settling the run: an explicit termination
    /// latched at the owning gateway wins, otherwise this session's own tombstone.
    /// One property so the two gates cannot drift apart.
    public var terminalAbortReason: String? {
        terminalSnapshot().effectiveTerminationReason
    }

    /// Start a fresh ledger for ONE run attempt. The runner calls this before
    /// dispatch, so a refused attempt reports `notEntered` axes instead of the
    /// previous attempt's facts.
    @discardableResult
    public func beginRunLedger() -> G3RunLedger {
        lock.lock()
        let ledger = G3RunLedger(armID: armID, adjudication: adjudication)
        _runLedger = ledger
        lock.unlock()
        return ledger
    }

    /// The current run ledger, created on first use for a caller that bypasses
    /// the runner (the production executor itself).
    public var runLedger: G3RunLedger {
        lock.lock()
        if let existing = _runLedger {
            lock.unlock()
            return existing
        }
        let ledger = G3RunLedger(armID: armID, adjudication: adjudication)
        _runLedger = ledger
        lock.unlock()
        return ledger
    }

    /// Claim this session's ONE continuation before cache resolution / prefill.
    /// The claim is atomic, so two racing gated calls cannot both pass a
    /// `stepCount == 0` check and prefill the same cache twice: the loser is
    /// refused with ``G3PerArmCacheError/cacheSessionAlreadyUsed(_:)``. The claim
    /// is never released — a session is single-use even if the first continuation
    /// failed, because a failure terminates the session through the gated path.
    public func claimContinuation() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !_continuationClaimed else { return false }
        _continuationClaimed = true
        return true
    }

    /// Explicitly terminate the arm (used when an owner outside the cache decides
    /// the arm must stop). Idempotent; the first reason is kept.
    ///
    /// The write happens inside the adjudication domain, and a termination that
    /// arrives AFTER this run consumed its binding is filed as
    /// `postSettlementTermination` HERE — by the mechanism, not by whoever happens
    /// to sample the state later. The consumed fact is never rolled back.
    public func terminate(reason: String) {
        adjudication.adjudicate {
            if _abortReason == nil { _abortReason = reason }
            if let ledger = _runLedger, ledger.bindingConsumed {
                ledger.markPostSettlementTermination(reason)
            }
        }
    }

    /// A termination latched by the boundary (gateway) rather than by this
    /// session. Called from inside the domain through the hop, so an external
    /// latch and a commit cannot both win.
    func noteExternallyLatchedTermination(_ reason: String) {
        adjudication.adjudicate {
            if let ledger = _runLedger, ledger.bindingConsumed {
                ledger.markPostSettlementTermination(reason)
            }
        }
    }

    /// THE commit linearization point.
    ///
    /// Inside ONE region of the arm's domain this reads every terminal source
    /// (gateway latch, session tombstone, the native write-gate aggregate),
    /// samples the cancellation predicate, runs `finalize`, and records the
    /// commit transition. Because a termination can only be latched by entering
    /// the same domain, it either lands BEFORE this region (this read sees it and
    /// the commit is refused) or AFTER it (the latch's own domain entry sees the
    /// recorded commit and files it as a late termination). There is no state in
    /// between, which is exactly what a `guard terminal == nil` followed by a
    /// separate `commit()` could not promise.
    ///
    /// `isCancelled` is sampled at the same point: this is the run's cancellation
    /// cutoff. A cancellation observed after this region returns
    /// ``G3CommitOutcome/committed`` is recorded as
    /// ``G3CancellationPoint/afterCommitCutoff`` for audit and does NOT undo the
    /// delivery — a later sample is not an atomic cancel guarantee, and the
    /// protocol says so instead of implying one.
    @discardableResult
    public func commitDelivery(
        isCancelled: @escaping () -> Bool,
        finalize: () throws -> Void
    ) rethrows -> G3CommitOutcome {
        let ledger = runLedger
        return try adjudication.adjudicate {
            guard boundaryAdoptsAdjudication else {
                ledger.recordPhase(.commit, .failed("boundary_not_adjudicating"))
                return .refusedBoundaryNotAdjudicating
            }
            if let reason = terminalSnapshot().effectiveTerminationReason {
                if _abortReason == nil { _abortReason = reason }
                ledger.markPostSettlementTermination(reason)
                ledger.recordPhase(
                    .commit, .failed("terminated_at_commit_cutoff:\(reason)"))
                return .refusedTermination(reason: reason)
            }
            // The native write-gate is a second view of the same arm's death (a
            // per-layer abort that no latch surfaced yet). Refusing on it here
            // costs nothing and cannot produce a false pass.
            if boundary.isolationAborted {
                let reason = boundary.isolationAbortReason ?? "kv_isolation_abort"
                if _abortReason == nil { _abortReason = reason }
                ledger.markPostSettlementTermination(reason)
                ledger.recordPhase(
                    .commit, .failed("kv_abort_at_commit_cutoff:\(reason)"))
                return .refusedTermination(reason: reason)
            }
            if isCancelled() {
                if _abortReason == nil { _abortReason = "task_cancelled" }
                ledger.recordCancellation(.atCommitCutoff)
                ledger.recordPhase(.commit, .failed("cancelled_at_commit_cutoff"))
                return .refusedCancellation
            }
            do {
                try finalize()
            } catch {
                ledger.recordPhase(.commit, .failed("finalize_threw(\(error))"))
                throw error
            }
            ledger.recordPhase(.commit, .succeeded("result_delivered"))
            ledger.markCommitAdjudicatedUnder(adjudication.domain)
            return .committed
        }
    }

    /// Run ONE generation step against this arm's cache.
    ///
    /// - `forward` performs the model step. In production it calls
    ///   `context.model(tokens, cache: [thisArmCache])`, which routes through the
    ///   fork's `attentionWithCacheUpdate`, where a refused KV write latches the
    ///   cache's abort.
    /// - `candidateToken` yields the token the forward produced. It is invoked
    ///   ONLY when the cache did not abort, so a token derived from a refused step
    ///   is never even read, let alone committed.
    ///
    /// A terminated session refuses without calling either closure. A THROW from
    /// `forward` or `candidateToken` also terminates the arm: a step that was
    /// entered but could not be completed must never be retried against a cache it
    /// may already have advanced. `CancellationError` is recorded as
    /// `task_cancelled` so a cancelled caller leaves a recognisable tombstone.
    ///
    /// A second CONCURRENT `runStep` is refused and terminates the arm with
    /// `concurrent_runStep`: two generation loops over one mutable cache could
    /// otherwise commit the same step twice. The session is single-use per arm.
    @discardableResult
    public func runStep(
        forward: () throws -> Void,
        candidateToken: () throws -> Int
    ) rethrows -> G3ArmStepOutcome {
        lock.lock()
        if let reason = _abortReason {
            lock.unlock()
            return .refusedAfterTermination(reason: reason)
        }
        if _isStepping {
            if _abortReason == nil { _abortReason = "concurrent_runStep" }
            let reason = _abortReason!
            lock.unlock()
            return .refusedAfterTermination(reason: reason)
        }
        _isStepping = true
        lock.unlock()
        defer {
            lock.lock(); _isStepping = false; lock.unlock()
        }

        boundary.beginStep()
        // A boundary that keeps `isolationAborted` set after beginStep() is
        // already dead (an earlier native abort, or a cache setup failure). Do not
        // run a forward on it: that would be a new step on a terminated arm.
        if boundary.isolationAborted {
            let reason = boundary.isolationAbortReason ?? "kv_isolation_abort"
            terminate(reason: reason)
            return .refusedAfterTermination(reason: reason)
        }

        lock.lock(); _stepCount += 1; lock.unlock()
        do {
            try forward()
        } catch {
            if error is CancellationError {
                terminate(reason: "task_cancelled")
            } else {
                terminate(reason: "forward_threw(\(error))")
            }
            throw error
        }
        if boundary.isolationAborted {
            let reason = boundary.isolationAbortReason ?? "kv_isolation_abort"
            terminate(reason: reason)
            return .aborted(reason: reason)
        }
        // A concurrent runStep/terminate may have killed the arm while forward ran.
        if let reason = abortReason {
            return .aborted(reason: reason)
        }
        let token: Int
        do {
            token = try candidateToken()
        } catch {
            if error is CancellationError {
                terminate(reason: "task_cancelled")
            } else {
                terminate(reason: "candidate_token_threw(\(error))")
            }
            throw error
        }
        // Cancellation or a concurrent terminate between sampling and commit.
        lock.lock()
        if let reason = _abortReason {
            lock.unlock()
            return .aborted(reason: reason)
        }
        _committedTokens.append(token)
        lock.unlock()
        return .committed(token: token)
    }
}

// MARK: - Two-arm non-sharing guard

/// The pair of per-arm sessions a G3 run is allowed to use. Construction is the
/// non-sharing gate: it refuses the same boundary object shared by both arms, so
/// an accidental "one cache for both arms" wiring cannot reach generation.
///
/// This is a WIRING check, not the storage check: the registrar still refuses a
/// buffer whose CONFIRMED storage id already belongs to either arm, so even a
/// boundary-wrapping bug cannot smuggle shared mutable storage past admission.
public struct G3PerArmCachePair {
    public let es: G3ArmCacheSession
    public let isOnly: G3ArmCacheSession

    public init(es: G3ArmCacheSession, isOnly: G3ArmCacheSession) throws {
        guard es.armID != isOnly.armID else {
            throw G3PerArmCacheError.armsShareArmIdentity(es.armID)
        }
        guard (es.boundary as AnyObject) !== (isOnly.boundary as AnyObject) else {
            throw G3PerArmCacheError.armsShareMutableCache(
                "both arms were handed the same mutable cache boundary")
        }
        self.es = es
        self.isOnly = isOnly
    }

    /// True by construction after a successful init (kept as an explicit field so
    /// a report can state it without re-deriving it).
    public var boundariesAreDistinct: Bool {
        (es.boundary as AnyObject) !== (isOnly.boundary as AnyObject)
    }

    /// armID -> effective refusal reason for every arm that is terminated by
    /// EITHER source (gateway latch first, then session tombstone).
    public var terminations: [String: String] {
        var out: [String: String] = [:]
        if let r = es.terminalAbortReason { out[es.armID] = r }
        if let r = isOnly.terminalAbortReason { out[isOnly.armID] = r }
        return out
    }

    /// The two terminal sources, reported separately so "gateway stopped this
    /// arm" is never conflated with "this arm's KV step refused".
    public var gatewayTerminations: [String: String] {
        var out: [String: String] = [:]
        if let r = es.gatewayTerminationReason { out[es.armID] = r }
        if let r = isOnly.gatewayTerminationReason { out[isOnly.armID] = r }
        return out
    }

    public var sessionTombstones: [String: String] {
        var out: [String: String] = [:]
        if let r = es.sessionTombstoneReason { out[es.armID] = r }
        if let r = isOnly.sessionTombstoneReason { out[isOnly.armID] = r }
        return out
    }

    /// True only when NEITHER arm is terminated by EITHER source. A terminated
    /// arm's output is partial and must not be reported as settled.
    public var allSettled: Bool { !es.isTerminated && !isOnly.isTerminated }
}

// MARK: - Executor seams

/// The one-way settlement seam the production G3 executor uses to consume a run's
/// bound prefix.
///
/// Model-free by design: it knows nothing about MLX, a model container, or the
/// backend's storage. The caller supplies the consume body; this type owns the
/// DECISION and the single-use invariant:
///   * a terminated arm throws BEFORE the body runs, so a dead arm's binding is
///     never consumed;
///   * only the first `settle` reaches the body — a second is refused, so a run
///     cannot consume its binding twice;
///   * the transition is WRITE-AHEAD: once the body starts, the run is recorded as
///     settled even if the body throws. The backend cannot roll a consume back, so
///     pretending otherwise would be a false transactional claim.
public final class G3RunSettlement: @unchecked Sendable {
    public let armID: String
    /// THE arm's domain, not a lock of its own: the gate's terminal read, its
    /// single-use transition and the consume are one region with the commit and
    /// with every termination latch.
    private let adjudication: G3Adjudication
    private var lock: NSRecursiveLock { adjudication.lock }
    private var _settled = false
    private let ledger: G3RunLedger?
    /// Re-read at the gate and again after the consume. The session-backed init
    /// makes this `terminalSnapshot().effectiveTerminationReason`, so the gateway
    /// latch participates in the same decision as the session tombstone.
    private let terminalReasonProvider: (@Sendable () -> String?)?

    public init(
        armID: String,
        ledger: G3RunLedger? = nil,
        terminalReason: (@Sendable () -> String?)? = nil,
        adjudication: G3Adjudication? = nil
    ) {
        self.armID = armID
        self.ledger = ledger
        self.terminalReasonProvider = terminalReason
        self.adjudication = adjudication ?? ledger?.adjudication
            ?? G3Adjudication(domain: "settle:\(armID)")
    }

    /// Production init: the ledger, the terminal predicate AND the domain all come
    /// from the same session, so the gate decides on the same state the report
    /// reads and is serialized against the same commit.
    public convenience init(armID: String, session: G3ArmCacheSession) {
        self.init(
            armID: armID,
            ledger: session.runLedger,
            terminalReason: { session.terminalSnapshot().effectiveTerminationReason },
            adjudication: session.adjudication)
    }

    /// True once the consume body has been entered (even if it threw). This is
    /// the `settleEntered` axis — it does NOT mean `bindingConsumed`.
    public var isSettled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _settled
    }

    public var settlementPhase: G3SettlementPhase {
        if let ledger { return ledger.settlementPhase }
        lock.lock(); defer { lock.unlock() }
        return _settled ? .entered : .notEntered
    }

    /// Production call: re-evaluate ALL terminal sources at the gate.
    public func settle(_ consume: () throws -> Void) throws {
        try settle(terminalReason: terminalReasonProvider?(), consume)
    }

    /// Consume the binding at most once, and only on a live arm, INSIDE the
    /// arm's adjudication domain. The terminal check, the single-use check and
    /// the entered transition are one region: a termination latched by another
    /// thread either happens before this region (the read sees it and the settle
    /// is refused) or after it (the consume is already recorded, and the latch
    /// files it as `postSettlementTermination`). Entering the body remains the
    /// linearization point of consumption.
    public func settle(
        terminalReason: String?, _ consume: () throws -> Void
    ) throws {
        try adjudication.adjudicate {
            if let terminalReason {
                ledger?.markSettlementRefused(terminalReason)
                throw G3PerArmCacheError.armTerminated(reason: terminalReason)
            }
            lock.lock()
            guard !_settled else {
                lock.unlock()
                throw G3PerArmCacheError.bindingAlreadySettled(armID)
            }
            _settled = true
            lock.unlock()
            ledger?.markSettleEntered()
            do {
                try consume()
            } catch {
                // The body was entered but did not confirm the consume. This is NOT
                // the same fact as "binding consumed"; the ledger says exactly that.
                ledger?.markBindingConsumeFailed("\(error)")
                throw error
            }
            ledger?.markBindingConsumed()
            if let post = terminalReasonProvider?() {
                ledger?.markPostSettlementTermination(post)
            }
        }
    }
}

/// An executor that can be handed its arm's single cache session after sealing
/// and before dispatch. Returning `false` means the executor already holds a
/// DIFFERENT session — the runner treats that as a wiring refusal, never as a
/// silent replacement (replacing would be a second cache for one arm).
public protocol G3CacheSessionInstalling: AnyObject {
    @discardableResult
    func installG3CacheSession(_ session: G3ArmCacheSession) -> Bool
}

// MARK: - Single-use session slot

/// The install/release state machine for ONE arm's G3 cache session.
///
/// `install` is idempotent for the SAME session and refuses a DIFFERENT one.
/// `release` is ONE-WAY: it TERMINATES the installed session (`cache_session_released`),
/// drops it (so the caches, gateway and observers can be freed) and retires the
/// slot. Terminating on release is what makes a release racing an in-flight step
/// fail closed: the step's commit check sees the tombstone and discards its token
/// instead of settling an arm whose owner has already let go. A retired slot
/// refuses every later install, including one that would re-arm an arm terminated
/// by a refused KV write. The tombstone is a `Bool`, not a reference, so releasing
/// genuinely releases the cache; it only remembers that this executor already
/// owned an arm.
public final class G3CacheSessionSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var _session: G3ArmCacheSession?
    private var _retired = false

    public init() {}

    public var installed: G3ArmCacheSession? {
        lock.lock(); defer { lock.unlock() }
        return _session
    }

    public var isRetired: Bool {
        lock.lock(); defer { lock.unlock() }
        return _retired
    }

    /// Returns `false` when a DIFFERENT session is already installed, or when
    /// this slot was released. Re-installing the exact same session is allowed
    /// (idempotent) and does not consume a second arm.
    @discardableResult
    public func install(_ session: G3ArmCacheSession) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !_retired else { return false }
        if let existing = _session { return existing === session }
        _session = session
        return true
    }

    /// Terminate the installed session, then drop it and retire the slot.
    /// Releasing twice is harmless and still leaves the slot retired; no later
    /// install can succeed. Termination happens BEFORE the reference is dropped,
    /// so a step already inside `runStep` observes the tombstone at its commit
    /// check and does not append the token.
    public func release() {
        lock.lock()
        let session = _session
        _session = nil
        _retired = true
        lock.unlock()
        session?.terminate(reason: "cache_session_released")
    }
}

/// Creates one arm's cache session from that arm's sealed registrar. The MLX
/// implementation builds a real `KVCacheSimple`, its `G3KVAllocationGateway`, and
/// installs the write observer BEFORE the cache's first use.
public typealias G3PerArmCacheSessionFactory =
    @Sendable (_ armID: RuntimeArmID, _ registrar: G3AllocationRegistrar) throws -> G3ArmCacheSession
