import Foundation

// G3 DUAL-ARM RUNNER — the real production-shaped G3 execution entry.
//
// This is the branch that the reviewer noted was missing: a genuine G3 run that
// drives BOTH arms (ES+IS and IS-only) through the single ``G3ExecutionDispatch``
// funnel as `.g3` routes, rather than stopping at the model-free preflight
// example. It is deliberately built so that:
//
//   1. A structural OWNERSHIP-ISOLATION precondition runs first: the two arms
//      must own disjoint mutable instances (by object identity, not label). If
//      they do not, the run is refused BEFORE either arm is dispatched, so no
//      generation can happen on a shared-resource configuration.
//   2. Each arm is routed ONLY through ``G3ExecutionDispatch``'s `.g3` branch,
//      which calls only the gate-protected continuation method. There is NO
//      fallback to the standard method, a fixture, or a synthetic result.
//   3. The run never claims execution evidence. Under the intentionally-empty
//      trust registry both arms are refused before their first forward, and the
//      summed generation-call count stays zero.
//   4. Ownership is not a one-shot pre-run snapshot: after sealing, the runner
//      hands each arm's gated continuation the owner's ``G3AllocationRegistrar``,
//      so any KV/prefix/runtime resource the first generation materializes is
//      re-validated live against both arms before it is admitted. A refusal is
//      recorded by the owner and surfaces as `allocationViolations`.
//
// Normal inference does not go through this type at all; it keeps calling the
// executor's `continueExecution` directly. This file is MLX-free so the control
// flow and lifecycle are unit-testable without loading a model.

// MARK: - One arm's execution spec

/// Everything the runner needs to drive one G3 arm. The `owner` carries the
/// arm's real resource ownership (used for the isolation precondition); the
/// `executor` + `provider` + `request` are what the funnel needs to gate.
public struct G3ArmExecution<R: G3RoutableContinuation>: Sendable {
    public let owner: G3ArmResourceOwner
    public let executor: R
    public let provider: any RuntimeAttestationProvider
    public let request: AttestationRequest
    public let state: ExecutionStateHandle
    public let nextInputTokens: [Int]
    public let maxTokens: Int

    public init(
        owner: G3ArmResourceOwner,
        executor: R,
        provider: any RuntimeAttestationProvider,
        request: AttestationRequest,
        state: ExecutionStateHandle,
        nextInputTokens: [Int],
        maxTokens: Int
    ) {
        self.owner = owner
        self.executor = executor
        self.provider = provider
        self.request = request
        self.state = state
        self.nextInputTokens = nextInputTokens
        self.maxTokens = maxTokens
    }
}

// MARK: - Run report

public struct G3ArmRunRecord: Codable, Hashable, Sendable {
    public let armID: String
    public let routedVia: String          // always "G3ExecutionDispatch.g3"
    public let outcome: G3GateOutcome
    /// True only when this arm entered the one settlement gate, confirmed its
    /// binding was consumed, delivered every stage, and no termination was
    /// observed after the gate. This is NOT `!session.isTerminated`: a
    /// post-settlement cancellation consumes the binding and still is not a
    /// settled delivery, and the axes below say so.
    public let settled: Bool
    /// Axis 1: did the run enter the single-use settlement gate?
    public let settleEntered: Bool
    /// Axis 2: was the bound prefix actually consumed?
    public let bindingConsumed: Bool
    /// Axis 3: per-stage delivery results (generation/registration/decode/commit).
    public let delivery: G3DeliveryReport
    /// Where cancellation was observed relative to the settlement gate.
    public let cancellation: G3CancellationPoint
    /// All terminal sources at report time, with fixed precedence.
    public let terminal: G3TerminalSnapshot

    public init(
        armID: String, routedVia: String, outcome: G3GateOutcome, settled: Bool = false,
        settleEntered: Bool = false,
        bindingConsumed: Bool = false,
        delivery: G3DeliveryReport = .notEntered,
        cancellation: G3CancellationPoint = .notCancelled,
        terminal: G3TerminalSnapshot = .none
    ) {
        self.armID = armID
        self.routedVia = routedVia
        self.outcome = outcome
        self.settled = settled
        self.settleEntered = settleEntered
        self.bindingConsumed = bindingConsumed
        self.delivery = delivery
        self.cancellation = cancellation
        self.terminal = terminal
    }
}

public struct G3DualArmRunReport: Codable, Hashable, Sendable {
    public let gate: String
    public let isolationPrecondition: G3OwnershipIsolationReport
    /// True once both arms were sealed against each other after the precondition
    /// passed; every later allocation is then re-checked live, not against a snapshot.
    public let armsSealed: Bool
    public let arms: [G3ArmRunRecord]
    public let totalGenerationCallCount: Int
    public let anyArmClearedGate: Bool
    /// Reasons recorded when a resource allocated DURING the first generation was
    /// refused for breaking isolation. Non-empty means the pre-generation snapshot
    /// passed but a post-seal allocation violated it — the run is fail-closed.
    public let allocationViolations: [String]
    public let isolationCompromisedAfterAllocation: Bool
    /// Always false: a routing/ownership result is not real execution evidence.
    public let isExecutionEvidence: Bool
    /// The single funnel both arms traversed — recorded so a reviewer can see the
    /// arms reached generation ONLY via the dispatcher, never via a fallback.
    public let routedVia: String
    public let fellBackToStandard: Bool
    /// True when BOTH arms were handed distinct per-arm cache sessions before
    /// dispatch (the production wiring this report is meant to prove).
    public let perArmCacheWired: Bool
    /// True when the pair guard confirmed the two cache boundaries are distinct
    /// objects — never one mutable cache serving both arms.
    public let cacheBoundariesDistinct: Bool
    /// armID -> effective termination reason (gateway latch first, then session
    /// tombstone) for every arm that is dead by EITHER source.
    public let armTerminations: [String: String]
    /// The two terminal sources, kept separate so "the gateway stopped this arm"
    /// is never conflated with "this arm's KV step refused".
    public let gatewayTerminations: [String: String]
    public let sessionTombstones: [String: String]
    /// True ONLY when a per-arm cache was wired, EVERY arm's record entered the
    /// settlement gate, consumed its binding and completed delivery, and NEITHER
    /// arm is terminated by EITHER source. A gate refusal (no steps ran) or a
    /// post-settlement cancellation makes this false.
    public let eachArmSettled: Bool

    public init(
        gate: String,
        isolationPrecondition: G3OwnershipIsolationReport,
        armsSealed: Bool,
        arms: [G3ArmRunRecord],
        totalGenerationCallCount: Int,
        anyArmClearedGate: Bool,
        allocationViolations: [String],
        isolationCompromisedAfterAllocation: Bool,
        isExecutionEvidence: Bool,
        routedVia: String,
        fellBackToStandard: Bool,
        perArmCacheWired: Bool = false,
        cacheBoundariesDistinct: Bool = false,
        armTerminations: [String: String] = [:],
        gatewayTerminations: [String: String] = [:],
        sessionTombstones: [String: String] = [:],
        eachArmSettled: Bool = false
    ) {
        self.gate = gate
        self.isolationPrecondition = isolationPrecondition
        self.armsSealed = armsSealed
        self.arms = arms
        self.totalGenerationCallCount = totalGenerationCallCount
        self.anyArmClearedGate = anyArmClearedGate
        self.allocationViolations = allocationViolations
        self.isolationCompromisedAfterAllocation = isolationCompromisedAfterAllocation
        self.isExecutionEvidence = isExecutionEvidence
        self.routedVia = routedVia
        self.fellBackToStandard = fellBackToStandard
        self.perArmCacheWired = perArmCacheWired
        self.cacheBoundariesDistinct = cacheBoundariesDistinct
        self.armTerminations = armTerminations
        self.gatewayTerminations = gatewayTerminations
        self.sessionTombstones = sessionTombstones
        self.eachArmSettled = eachArmSettled
    }
}

// MARK: - Runner

public enum G3DualArmRunner {
    public enum RunError: Error, Equatable {
        /// Ownership isolation failed, so the run was refused before dispatch.
        case preconditionRefused(G3OwnershipIsolationReport)
        /// Per-arm cache wiring failed (shared boundary, unsealed owner, or an
        /// executor that cannot hold its own session) — refused BEFORE dispatch.
        case cacheWiringRefused(String)
    }

    /// Drive both G3 arms through the dispatcher, gated by an ownership-isolation
    /// precondition AND per-arm cache wiring. Throws ``preconditionRefused(_:)``
    /// (before any dispatch) if the two arms are not provably isolated, and
    /// ``cacheWiringRefused(_:)`` if a session cannot be built or installed.
    /// `makeCacheSession` is REQUIRED, not optional: a G3 run without a per-arm
    /// cache is exactly the G8a hole (recompute path, no settlement ledger), so
    /// it cannot be expressed at this entry at all.
    public static func run<R: G3RoutableContinuation>(
        _ first: G3ArmExecution<R>,
        _ second: G3ArmExecution<R>,
        makeCacheSession: G3PerArmCacheSessionFactory
    ) async throws -> G3DualArmRunReport {
        // (1) Structural isolation — decided on the normalized underlying-storage
        // identity each resource reports, before dispatch.
        let isolation = G3OwnershipIsolation.check(first.owner, second.owner)
        guard isolation.passed else {
            throw RunError.preconditionRefused(isolation)
        }

        // (2) Seal both arms against each other. From here a mutable resource that
        // the first generation materializes must be registered through
        // `registerDuringGeneration`, which re-checks it live against both arms —
        // the precondition is not just a pre-run snapshot.
        first.owner.seal(against: second.owner)
        second.owner.seal(against: first.owner)

        // (3) Per-arm mutable KV cache. Built AFTER sealing (it needs each arm's
        // registrar) and BEFORE dispatch (so the cache's FIRST use is gated). The
        // pair guard refuses one cache shared by both arms; a shared cache can
        // therefore never reach generation. Both allocations happen here, so a
        // refusal is raised before either arm is dispatched.
        guard let esRegistrar = first.owner.makeRegistrar(),
              let isRegistrar = second.owner.makeRegistrar()
        else {
            throw RunError.cacheWiringRefused(
                "owner_not_sealed: cannot build a per-arm cache session")
        }
        let esSession: G3ArmCacheSession
        let isSession: G3ArmCacheSession
        let cachePair: G3PerArmCachePair
        do {
            esSession = try makeCacheSession(first.owner.armID, esRegistrar)
            isSession = try makeCacheSession(second.owner.armID, isRegistrar)
            cachePair = try G3PerArmCachePair(es: esSession, isOnly: isSession)
        } catch {
            throw RunError.cacheWiringRefused("\(error)")
        }
        guard let esSink = first.executor as? G3CacheSessionInstalling,
              esSink.installG3CacheSession(esSession)
        else {
            throw RunError.cacheWiringRefused(
                "executor_cannot_install_cache_session(\(first.owner.armID.rawValue))")
        }
        guard let isSink = second.executor as? G3CacheSessionInstalling,
              isSink.installG3CacheSession(isSession)
        else {
            throw RunError.cacheWiringRefused(
                "executor_cannot_install_cache_session(\(second.owner.armID.rawValue))")
        }

        // (4) One fresh ledger per arm per attempt. A gate refusal therefore
        // reports `notEntered` axes instead of inheriting a previous attempt.
        cachePair.es.beginRunLedger()
        cachePair.isOnly.beginRunLedger()

        // (5) Route each arm ONLY through the dispatcher's `.g3` branch.
        let a = await drive(first, session: cachePair.es)
        let b = await drive(second, session: cachePair.isOnly)

        let records = [a, b]
        let totalGeneration = records.reduce(0) { $0 + $1.outcome.generationCallCount }
        let anyCleared = records.contains { $0.outcome.stage == "cleared" && $0.outcome.passed }
        // Any allocation refused after sealing means isolation was broken during
        // the run even though the snapshot passed — surface it fail-closed. A KV
        // cache that terminated its arm is the same class of event.
        let violations = first.owner.allocationViolations + second.owner.allocationViolations
        let terminations = cachePair.terminations

        return G3DualArmRunReport(
            gate: RuntimeIsolationGate.gateID,
            isolationPrecondition: isolation,
            armsSealed: true,
            arms: records,
            totalGenerationCallCount: totalGeneration,
            anyArmClearedGate: anyCleared,
            allocationViolations: violations,
            isolationCompromisedAfterAllocation: !violations.isEmpty || !terminations.isEmpty,
            isExecutionEvidence: false,
            routedVia: "G3ExecutionDispatch.g3",
            fellBackToStandard: false,
            perArmCacheWired: true,
            cacheBoundariesDistinct: cachePair.boundariesAreDistinct,
            armTerminations: terminations,
            gatewayTerminations: cachePair.gatewayTerminations,
            sessionTombstones: cachePair.sessionTombstones,
            eachArmSettled: cachePair.allSettled
                && records.allSatisfy(\.settled))
    }

    /// Send one arm through the funnel. Refusal (or any dispatch error) is
    /// captured as a structured outcome — it never re-routes to the standard path.
    private static func drive<R: G3RoutableContinuation>(
        _ arm: G3ArmExecution<R>, session: G3ArmCacheSession? = nil
    ) async -> G3ArmRunRecord {
        let routedVia = "G3ExecutionDispatch.g3"
        // The owner was sealed by `run` before this call, so it hands out a real
        // registration channel. A nil here would mean the seal never happened —
        // the generation path then has no way to register an allocation and the
        // run's snapshot-only guarantee would be silently lost, so the absence is
        // itself recorded fail-closed rather than passed over.
        guard let registrar = arm.owner.makeRegistrar() else {
            return Self.record(
                for: arm, routedVia: routedVia, session: session,
                outcome: Self.refusedOutcome(
                    for: arm,
                    reason: "owner_not_sealed: no during-generation registration channel"))
        }
        do {
            let value = try await G3ExecutionDispatch.run(
                arm.executor,
                route: .g3(provider: arm.provider, request: arm.request, registrar: registrar),
                state: arm.state,
                nextInputTokens: arm.nextInputTokens,
                maxTokens: arm.maxTokens)
            // Cleared only if the gate actually let generation through. When the
            // concrete result is not a gate outcome (e.g. the MLX executor), a
            // successful return means the gated method ran exactly one generation.
            let outcome: G3GateOutcome
            if let gateOutcome = (value as? G3GateOutcome) {
                outcome = gateOutcome
            } else {
                outcome = Self.clearedOutcome(for: arm)
            }
            return Self.record(
                for: arm, routedVia: routedVia, session: session, outcome: outcome)
        } catch G3FirstGenerationEntry.EntryError.refused(let outcome) {
            return Self.record(
                for: arm, routedVia: routedVia, session: session, outcome: outcome)
        } catch let cacheError as G3PerArmCacheError {
            // A refused KV step terminated this arm. It is recorded as a distinct
            // outcome — never as a cleared generation, never re-routed. The axes
            // still distinguish a pre-settlement refusal from a post-settlement
            // cancellation/termination that already consumed the binding.
            return Self.record(
                for: arm, routedVia: routedVia, session: session,
                outcome: Self.abortedOutcome(for: arm, error: cacheError))
        } catch {
            // Unexpected dispatch failure: record it fail-closed, still no fallback.
            return Self.record(
                for: arm, routedVia: routedVia, session: session,
                outcome: Self.refusedOutcome(for: arm, reason: "dispatch_error: \(error)"))
        }
    }

    /// Build the report record from the arm's OWN ledger and terminal snapshot.
    /// The three axes are read, never inferred from a Boolean; a session that
    /// never reached the gated body reports all-`notEntered`.
    private static func record<R: G3RoutableContinuation>(
        for arm: G3ArmExecution<R>, routedVia: String,
        session: G3ArmCacheSession?, outcome: G3GateOutcome
    ) -> G3ArmRunRecord {
        let ledger = session?.runLedger.snapshot
            ?? G3RunLedgerSnapshot.notEntered(armID: arm.owner.armID.rawValue)
        let terminal = session?.terminalSnapshot() ?? .none
        return G3ArmRunRecord(
            armID: arm.owner.armID.rawValue, routedVia: routedVia, outcome: outcome,
            settled: ledger.isFullyDelivered,
            settleEntered: ledger.settleEntered,
            bindingConsumed: ledger.bindingConsumed,
            delivery: ledger.delivery,
            cancellation: ledger.cancellation,
            terminal: terminal)
    }

    private static func clearedOutcome<R: G3RoutableContinuation>(for arm: G3ArmExecution<R>) -> G3GateOutcome {
        G3GateOutcome(
            gate: RuntimeIsolationGate.gateID, stage: "cleared", passed: true,
            eligibleForRuntimeEvidence: true,
            evidenceClass: "registered_live_runtime_attestation",
            generationCallCount: 1, modelGenerationStartedByGate: false,
            isExecutionEvidence: false,
            reason: "gated method returned after a cleared gate",
            failedChecks: [],
            runID: arm.request.runID, challengeNonce: arm.request.challengeNonce,
            providerID: arm.provider.providerID, providerKind: arm.provider.providerKind.rawValue,
            trustedLiveProviderCount: RuntimeProviderTrustPolicy.registeredLiveProviderTypes.count)
    }

    private static func refusedOutcome<R: G3RoutableContinuation>(
        for arm: G3ArmExecution<R>, reason: String
    ) -> G3GateOutcome {
        G3GateOutcome(
            gate: RuntimeIsolationGate.gateID, stage: "dispatch_error", passed: false,
            eligibleForRuntimeEvidence: false, evidenceClass: "gate_refused_before_generation",
            generationCallCount: 0, modelGenerationStartedByGate: false, isExecutionEvidence: false,
            reason: reason, failedChecks: [],
            runID: arm.request.runID, challengeNonce: arm.request.challengeNonce,
            providerID: arm.provider.providerID, providerKind: arm.provider.providerKind.rawValue,
            trustedLiveProviderCount: RuntimeProviderTrustPolicy.registeredLiveProviderTypes.count)
    }

    /// The arm's own KV cache refused a step: generation STARTED but was terminated,
    /// so the count is 1 (not a settled generation) and `settled` stays false.
    private static func abortedOutcome<R: G3RoutableContinuation>(
        for arm: G3ArmExecution<R>, error: G3PerArmCacheError
    ) -> G3GateOutcome {
        let reason: String
        switch error {
        case .armTerminated(let r): reason = r
        case .armsShareMutableCache(let r): reason = "arms_share_mutable_cache: \(r)"
        case .armsShareArmIdentity(let r): reason = "arms_share_arm_identity: \(r)"
        case .missingCacheSession(let r): reason = "missing_cache_session: \(r)"
        case .unobservableCache(let r): reason = "unobservable_cache: \(r)"
        case .cacheSessionAlreadyUsed(let r): reason = "cache_session_already_used: \(r)"
        case .bindingAlreadySettled(let r): reason = "binding_already_settled: \(r)"
        }
        return G3GateOutcome(
            gate: RuntimeIsolationGate.gateID, stage: "kv_isolation_abort", passed: false,
            eligibleForRuntimeEvidence: false,
            evidenceClass: "gate_refused_after_generation_start",
            generationCallCount: 1, modelGenerationStartedByGate: false, isExecutionEvidence: false,
            reason: reason, failedChecks: [],
            runID: arm.request.runID, challengeNonce: arm.request.challengeNonce,
            providerID: arm.provider.providerID, providerKind: arm.provider.providerKind.rawValue,
            trustedLiveProviderCount: RuntimeProviderTrustPolicy.registeredLiveProviderTypes.count)
    }
}
