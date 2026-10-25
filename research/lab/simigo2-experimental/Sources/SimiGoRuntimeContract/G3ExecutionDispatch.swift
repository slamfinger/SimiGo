import Foundation

// G3 EXECUTION ROUTING — the single dispatch funnel that turns the gate into a
// control point the *call path* must traverse, not just a method that happens
// to exist on the executor.
//
// Why this file exists:
//   * The real MLX executor exposes two continuation entry points: the unchanged
//     `continueExecution` (normal inference, deliberately NOT gated) and the
//     G3-specific `continueExecutionG3` (gate strictly before generation).
//   * A protected method only protects an execution if the caller actually
//     routes to it. This module makes that routing decision explicit and
//     unavoidable: a G3 request is expressed as ``G3ExecutionRoute/g3`` and the
//     dispatcher's `.g3` branch calls ONLY the gated method. There is no branch
//     that quietly falls back to `continueExecution` or to a fixture.
//
// The dispatcher is written against ``G3RoutableContinuation`` so it is
// exercised model-free at the contract layer (a spy/fake router proves the
// control flow), while the production MLX executor conforms to the very same
// protocol — the compile-time conformance is the evidence that a real G3 caller
// going through this funnel reaches the gate-protected forward.
//
// The `.g3` route also carries the arm's ``G3AllocationRegistrar`` — the channel
// through which resources materialized DURING generation (KV blocks, advanced
// prefix state, runtime scratch) are re-registered against the sealed ownership
// set. It is part of the route's payload so a G3 request cannot be expressed
// without stating where its allocations go.

// MARK: - Routing surface

/// The two continuation operations a routable executor must offer. Signatures
/// mirror ``MLXPrefixRecomputeExecutor`` exactly, so the real executor conforms
/// with an empty `extension … {}` and cannot drift from this contract.
public protocol G3RoutableContinuation: Sendable {
    associatedtype ContinuationResult
    /// Normal, ungated inference. Never used by a G3 route.
    func continueExecution(
        _ state: ExecutionStateHandle,
        nextInputTokens: [Int],
        maxTokens: Int
    ) async throws -> ContinuationResult
    /// G3-gated inference: the isolation gate runs before any generation.
    func continueExecutionG3(
        _ state: ExecutionStateHandle,
        nextInputTokens: [Int],
        maxTokens: Int,
        provider: any RuntimeAttestationProvider,
        request: AttestationRequest
    ) async throws -> ContinuationResult
    /// G3-gated inference that must also feed its during-generation allocations
    /// through the arm's registrar. The default implementation forwards to the
    /// gate-only form so existing conformers keep working; an executor that
    /// actually allocates runtime state overrides it and registers what it
    /// materializes — a registrar it ignores means the run reports no violation
    /// for a buffer only the executor itself can see, which is why the MLX layer
    /// (not this contract) is what observes real arrays.
    func continueExecutionG3(
        _ state: ExecutionStateHandle,
        nextInputTokens: [Int],
        maxTokens: Int,
        provider: any RuntimeAttestationProvider,
        request: AttestationRequest,
        registrar: G3AllocationRegistrar?
    ) async throws -> ContinuationResult
}

extension G3RoutableContinuation {
    public func continueExecutionG3(
        _ state: ExecutionStateHandle,
        nextInputTokens: [Int],
        maxTokens: Int,
        provider: any RuntimeAttestationProvider,
        request: AttestationRequest,
        registrar: G3AllocationRegistrar?
    ) async throws -> ContinuationResult {
        // Ignoring the registrar is only safe because the gate decision itself
        // never depended on it: this overload exists to give an executor a
        // registration channel, not to change when generation is allowed.
        return try await continueExecutionG3(
            state, nextInputTokens: nextInputTokens, maxTokens: maxTokens,
            provider: provider, request: request)
    }
}

// MARK: - Route

/// Which route a continuation request takes. The case carries its own inputs so
/// a G3 request cannot be built without the provider and attestation request the
/// gate needs — the type system enforces that the gated path is the only way to
/// express "run this as a G3 execution". The registrar is the channel a sealed
/// arm hands to its generation path so post-check allocations are re-validated
/// instead of invisible; passing `nil` states explicitly that the caller has no
/// during-generation registry to write to (the model-free preflight entry), which
/// is why it is a required argument rather than an omitted one.
public enum G3ExecutionRoute: Sendable {
    case standard
    case g3(provider: any RuntimeAttestationProvider, request: AttestationRequest,
            registrar: G3AllocationRegistrar?)
}

// MARK: - The one funnel

public enum G3ExecutionDispatch {
    /// Route a continuation request through the executor it belongs to.
    ///
    /// Invariants this function is responsible for (all covered by tests):
    ///   1. `.g3` calls ONLY `continueExecutionG3` — never `continueExecution`.
    ///   2. `.standard` calls ONLY `continueExecution` — never the gate.
    ///   3. A refused `.g3` gate propagates the throw out of the dispatcher; it
    ///      does NOT fall back to `.standard`, a fixture, or a synthetic result.
    ///   4. Generation inside the gated method happens strictly AFTER a cleared
    ///      gate (enforced by `G3FirstGenerationEntry.runAsync`; see executor).
    ///   5. The arm's allocation registrar — whatever the sealed owner produced —
    ///      reaches the gated method, so during-generation allocations have a
    ///      path back into the live ownership registry.
    public static func run<R: G3RoutableContinuation>(
        _ executor: R,
        route: G3ExecutionRoute,
        state: ExecutionStateHandle,
        nextInputTokens: [Int],
        maxTokens: Int
    ) async throws -> R.ContinuationResult {
        switch route {
        case .standard:
            return try await executor.continueExecution(
                state, nextInputTokens: nextInputTokens, maxTokens: maxTokens)
        case let .g3(provider, request, registrar):
            // Single gated entry. No `catch` that re-routes to the standard path:
            // a gate refusal must surface to the caller unchanged.
            return try await executor.continueExecutionG3(
                state,
                nextInputTokens: nextInputTokens,
                maxTokens: maxTokens,
                provider: provider,
                request: request,
                registrar: registrar)
        }
    }
}

// MARK: - Model-free G3 worker (the native entry's live caller)

/// A model-free implementation of ``G3RoutableContinuation`` used by the native
/// G3 entry executable and by control-flow tests. It performs exactly the gate
/// control flow the production executor does — gate strictly before the generate
/// closure for `.g3`, ungated for `.standard` — without owning a model. Trust is
/// never granted here: the empty registry still refuses, so this cannot produce a
/// passing production gate. The `standard` route is exercised only by tests that
/// prove routing; the shipped G3 entry always selects `.g3`.
///
/// The optional `allocateDuringGeneration` hook reproduces the production
/// executor's second obligation: after the gate clears, any state the forward
/// materializes must be offered to the arm's registrar before it is used. Tests
/// drive the hook with model-free resources to prove the channel is live; the
/// shipped native entry passes no hook, so its behavior is unchanged.
public struct G3IsolatedWorker: G3RoutableContinuation {
    public typealias ContinuationResult = G3GateOutcome

    /// The real generation step. In the native entry this is a canary that must
    /// never run under the empty registry; in production it is the forward loop.
    private let generate: @Sendable () async throws -> Void
    /// The production executor's "register what I just allocated" step, model-free.
    private let allocateDuringGeneration: @Sendable (G3AllocationRegistrar?) async throws -> Void

    public init(
        generate: @escaping @Sendable () async throws -> Void,
        allocateDuringGeneration: @escaping @Sendable (G3AllocationRegistrar?) async throws -> Void = { _ in }
    ) {
        self.generate = generate
        self.allocateDuringGeneration = allocateDuringGeneration
    }

    public func continueExecution(
        _ state: ExecutionStateHandle,
        nextInputTokens: [Int],
        maxTokens: Int
    ) async throws -> G3GateOutcome {
        // Normal inference: no gate consulted. Returns a non-evidence outcome so
        // callers can never mistake this for a cleared isolation gate.
        try await generate()
        return G3GateOutcome(
            gate: RuntimeIsolationGate.gateID,
            stage: "standard_ungated",
            passed: false,
            eligibleForRuntimeEvidence: false,
            evidenceClass: "not_a_g3_run",
            generationCallCount: 1,
            modelGenerationStartedByGate: false,
            isExecutionEvidence: false,
            reason: "normal inference route; isolation gate not consulted",
            failedChecks: [],
            runID: "n/a",
            challengeNonce: "n/a",
            providerID: "n/a",
            providerKind: "n/a",
            trustedLiveProviderCount: RuntimeProviderTrustPolicy.registeredLiveProviderTypes.count)
    }

    public func continueExecutionG3(
        _ state: ExecutionStateHandle,
        nextInputTokens: [Int],
        maxTokens: Int,
        provider: any RuntimeAttestationProvider,
        request: AttestationRequest
    ) async throws -> G3GateOutcome {
        try await continueExecutionG3(
            state, nextInputTokens: nextInputTokens, maxTokens: maxTokens,
            provider: provider, request: request, registrar: nil)
    }

    public func continueExecutionG3(
        _ state: ExecutionStateHandle,
        nextInputTokens: [Int],
        maxTokens: Int,
        provider: any RuntimeAttestationProvider,
        request: AttestationRequest,
        registrar: G3AllocationRegistrar?
    ) async throws -> G3GateOutcome {
        let run = try await G3FirstGenerationEntry.runAsync(
            provider: provider,
            request: request,
            generate: {
                try await self.generate()
                // Reached only after a cleared gate: this is where the production
                // forward would hand its newly materialized KV/prefix/scratch
                // buffers to the sealed arm for live re-validation.
                try await self.allocateDuringGeneration(registrar)
            })
        return run.outcome
    }
}

extension ExecutionStateHandle {
    /// A placeholder handle for gate-only routing where no bound execution state
    /// exists yet (the native entry preflight and control-flow tests). It carries
    /// no meaning beyond satisfying the routing signature — the isolation gate
    /// never reads it, and a refused route never reaches generation.
    public static let g3RoutingPlaceholder = ExecutionStateHandle(
        id: ExecutionID("g3-routing-placeholder"),
        lineage: ExecutionLineage(root: ExecutionID("g3-routing-placeholder")),
        position: ExecutionPosition(0),
        continuation: ExecutionContinuation(nextInput: "", continuationID: ""),
        lifecycle: .attached)
}
