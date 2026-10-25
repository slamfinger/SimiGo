import Foundation
import MLX
import MLXLMCommon
import SimiGoRuntimeContract

/// E3/L4 — the Prefix-Recompute Executor: consumes a bound execution
/// representation (token prefix) and continues it with real MLX execution.
///
/// This is the component the E5 audit required: real generation CONSUMES the
/// Execution State's representation instead of reconstructing an equivalent
/// input from chat messages. The executor is Backend-side: it owns the
/// forward/generation semantics; the Runtime owns identity, lineage,
/// position, and continuation.

/// Result of a representation-consuming continuation.
public struct ExecutionContinuationResult: Sendable {
    public let executionID: ExecutionID
    /// Length of the physical prefix that was consumed.
    public let consumedPrefixLength: Int
    public let nextInputTokenCount: Int
    public let generatedTokenIDs: [Int]
    public let generatedText: String
    /// The advanced physical representation (prefix + next input +
    /// generated). The Runtime rebinds its logical position to this payload.
    public let updatedPayload: any ExecutionRepresentationPayload

    public init(
        executionID: ExecutionID,
        consumedPrefixLength: Int,
        nextInputTokenCount: Int,
        generatedTokenIDs: [Int],
        generatedText: String,
        updatedPayload: any ExecutionRepresentationPayload
    ) {
        self.executionID = executionID
        self.consumedPrefixLength = consumedPrefixLength
        self.nextInputTokenCount = nextInputTokenCount
        self.generatedTokenIDs = generatedTokenIDs
        self.generatedText = generatedText
        self.updatedPayload = updatedPayload
    }
}

public final class MLXPrefixRecomputeExecutor: @unchecked Sendable {
    private let container: ModelContainer
    private let backend: MLXExecutionStateBackend

    /// The arm's during-generation registration hook, installed by the MLX probe
    /// wiring (`G3MLXRuntimeResourceProbe.bind(to:)`). It is a settable seam
    /// rather than a subclass override so the executor stays the single production
    /// type the runner routes, and so an executor with no probe bound performs no
    /// registration — which is recorded honestly instead of pretending a snapshot
    /// proves live isolation.
    public var duringGenerationRegistration:
        (@Sendable (ExecutionContinuationResult, G3AllocationRegistrar) async throws -> Void)?

    /// The cooperative cancellation predicate used at EVERY G4 check point.
    /// Production keeps the default (`Task.isCancelled`). The internal seam lets
    /// a model-free test place cancellation at an exact point instead of racing a
    /// timer, which is the only way to adjudicate pre-settlement / post-settlement
    /// / post-decode ordering deterministically. It is not a public bypass: the
    /// production call sites are the same four checks either way.
    var isCancelled: @Sendable () -> Bool = { Task.isCancelled }

    // MARK: Per-arm G3 KV cache (created after sealing, used only by the G3 path)

    /// This arm's private G3 KV cache session: its per-layer `KVCacheSimple` array,
    /// one gateway, one write observer per layer. Installed by ``G3DualArmRunner``
    /// AFTER the owners are sealed and BEFORE dispatch, so the cache's FIRST use is
    /// gated. `nil` means this arm still runs the recompute path (`cache: nil`) —
    /// honestly "no KV observed", never "verified isolated".
    ///
    /// The slot is SINGLE-USE: `releaseG3KVCache()` terminates the session
    /// (`cache_session_released`), drops the cache and retires the slot, so
    /// `installG3CacheSession` can never re-arm this executor afterwards and an
    /// in-flight step cannot commit after the release. That is what makes a
    /// terminated arm's termination survive release.
    private let g3CacheSlot = G3CacheSessionSlot()

    /// The CONFIRMED mutable-storage ids each released carrier held, captured at
    /// ``releaseExecutionCarrier(for:)`` so a following ``verifyAdoptedCarrierIsolated``
    /// can prove the new carrier is disjoint from the retired one. Keyed by
    /// execution id; empty set means the carrier observed no mutable KV storage.
    private var retiredCarrierStorage: [ExecutionID: Set<String>] = [:]

    public var g3CacheSession: G3ArmCacheSession? { g3CacheSlot.installed }

    /// The admission gate behind this arm's write observer, when a cache session is
    /// installed. ``G3MLXRuntimeResourceProbe/bind(to:)`` reuses it so the
    /// write-boundary observer and the post-forward registration hook share ONE
    /// registered-buffer set instead of re-admitting the same KV block.
    public var g3CacheGateway: G3KVAllocationGateway? {
        (g3CacheSlot.installed?.boundary as? MLXKVCacheBoundary)?.gateway
    }

    /// Install this arm's single cache session. Returns `false` when a DIFFERENT
    /// session is already installed — replacing it would give one arm two caches —
    /// or when the slot was released. A terminated or already-used arm therefore
    /// cannot be silently re-armed with a fresh cache.
    @discardableResult
    public func installG3CacheSession(_ session: G3ArmCacheSession) -> Bool {
        g3CacheSlot.install(session)
    }

    /// Release this arm's G3 cache: terminate the session, drop the per-layer
    /// caches, their gateway and their observers, and RETIRE the slot. Termination
    /// makes a release that races an in-flight step fail closed (the step's commit
    /// check sees the tombstone); the in-flight call itself still holds the session
    /// until it returns, so the actual deallocation is bounded by that call, not
    /// instantaneous. Deliberately NOT called automatically after a run: while
    /// installed, the session keeps a second, different session from being
    /// installed; after release, the tombstone keeps every later install out. A
    /// terminated/used arm can never be re-armed.
    public func releaseG3KVCache() {
        g3CacheSlot.release()
    }

    public init(container: ModelContainer, backend: MLXExecutionStateBackend) {
        self.container = container
        self.backend = backend
    }

    /// Tokenize next-input text (Backend-owned tokenization).
    public func tokenizeText(_ text: String) async throws -> [Int] {
        await container.perform { (context: ModelContext) -> [Int] in
            context.tokenizer.encode(text: text, addSpecialTokens: false)
        }
    }

    /// Seed-text encoding for the scenario bootstrap: raw text encoding WITH
    /// special tokens (BOS) — the one text-seeded generation.
    public func tokenizeSeedText(_ text: String) async throws -> [Int] {
        await container.perform { (context: ModelContext) -> [Int] in
            context.tokenizer.encode(text: text, addSpecialTokens: true)
        }
    }

    /// Continue the execution: consume the state's CURRENT bound prefix plus
    /// the next-input tokens, forward through MLX, and greedily generate up
    /// to `maxTokens`. Returns the advanced physical representation for the
    /// Runtime to rebind after advancing the logical position.
    public func continueExecution(
        _ state: ExecutionStateHandle,
        nextInputTokens: [Int],
        maxTokens: Int
    ) async throws -> ExecutionContinuationResult {
        let bound = try backend.boundPrefix(for: state)
        let inputTokens = bound.prefix + nextInputTokens

        let generated = await container.perform { (context: ModelContext) -> [Int] in
            var generated: [Int] = []
            var tokens = inputTokens
            var running = MLXArray(tokens, [1, tokens.count])
            for _ in 0..<maxTokens {
                let logits = context.model(running, cache: nil)[0, -1]
                let nextToken = logits.argMax().item(Int.self)
                generated.append(nextToken)
                if nextToken == context.tokenizer.eosTokenId ?? -1 {
                    break
                }
                tokens = tokens + [nextToken]
                running = MLXArray(tokens, [1, tokens.count])
                eval(logits)
            }
            return generated
        }

        let extended = inputTokens + generated
        // The physical prefix has advanced; the bound position goes stale
        // until the Runtime advances the logical position and rebinds.
        backend.consumeBinding(for: state)

        let text: String = await container.perform { (context: ModelContext) -> String in
            context.tokenizer.decode(tokenIds: generated, skipSpecialTokens: true)
        }

        return ExecutionContinuationResult(
            executionID: state.id,
            consumedPrefixLength: bound.prefix.count,
            nextInputTokenCount: nextInputTokens.count,
            generatedTokenIDs: generated,
            generatedText: text,
            updatedPayload: MLXPrefixPayload(tokenPrefix: extended)
        )
    }

    /// G3-only execution path: run the native isolation gate BEFORE the first
    /// forward, then generate over THIS arm's installed per-arm KV cache.
    ///
    /// The gate is evaluated on the provider's genuine runtime observations.
    /// A live `ModelContext` existing does NOT imply the two arms are isolated
    /// — having sampled resource ids is not the same as proving no resource is
    /// shared; that claim is decided only by `requireIsolation`. With the trusted
    /// live-provider registry empty, this refuses at the provider-trust check and
    /// never awaits the generate closure, so the real generation-call count stays
    /// zero. Normal inference keeps calling `continueExecution` directly and is
    /// completely unaffected.
    public func continueExecutionG3(
        _ state: ExecutionStateHandle,
        nextInputTokens: [Int],
        maxTokens: Int,
        provider: RuntimeAttestationProvider,
        request: AttestationRequest
    ) async throws -> ExecutionContinuationResult {
        try await continueExecutionG3(
            state, nextInputTokens: nextInputTokens, maxTokens: maxTokens,
            provider: provider, request: request, registrar: nil)
    }

    /// Registrar-aware G3 entry — the production shape of "ownership is live, not
    /// a pre-run snapshot".
    ///
    /// `G3DualArmRunner` seals the arm's owner and passes its registration channel
    /// here, so once (and only once) the gate clears, the forward's newly
    /// materialized runtime state is offered to ``duringGenerationRegistration``
    /// for re-validation against BOTH arms' confirmed mutable storage. A refused
    /// allocation throws out of the gated method: the runner records it in
    /// `allocationViolations` and fails the run closed rather than letting an
    /// unregistered buffer advance the execution.
    ///
    /// `registrar == nil`, or no hook installed, means no during-generation
    /// registration is claimed for this arm — the shape the model-free preflight
    /// entry uses, and a fixture, and any executor not yet bound to a probe. It
    /// must not be read as "allocations verified isolated"; it means "not observed".
    public func continueExecutionG3(
        _ state: ExecutionStateHandle,
        nextInputTokens: [Int],
        maxTokens: Int,
        provider: RuntimeAttestationProvider,
        request: AttestationRequest,
        registrar: G3AllocationRegistrar?
    ) async throws -> ExecutionContinuationResult {
        let run = try await G3FirstGenerationEntry.runAsync(
            provider: provider,
            request: request,
            generate: {
                try await self.runGatedGeneration(
                    state, nextInputTokens: nextInputTokens,
                    maxTokens: maxTokens, registrar: registrar)
            })
        return run.value
    }

    /// The body of the cleared-gate closure. INTERNAL, not public: production's
    /// only call site is inside `G3FirstGenerationEntry.runAsync` above. The
    /// internal visibility exists so a model-free test can prove this admission
    /// guard runs before cache resolution, `context.model`, `claimContinuation`,
    /// `G3RunSettlement` and `consumeBinding` — without registering a fictitious
    /// live provider. It is not a public bypass: code outside this module cannot
    /// reach it, and the module itself is the reviewed Case-A boundary.
    func runGatedGeneration(
        _ state: ExecutionStateHandle,
        nextInputTokens: [Int],
        maxTokens: Int,
        registrar: G3AllocationRegistrar?
    ) async throws -> ExecutionContinuationResult {
        // A released slot is retired for G3 even though `g3CacheSession`
        // is now nil: falling through to any other generation path would
        // make a terminated arm's termination reversible through release.
        // The gate still runs first in the public entry; this only closes the
        // post-gate re-entry route.
        guard !self.g3CacheSlot.isRetired else {
            throw G3PerArmCacheError.armTerminated(
                reason: "cache_session_released")
        }
        // G8a: the gated route has NO recompute fallback. A gated call on
        // an executor with no per-arm session used to call
        // `continueExecution`, which forwards with `cache: nil`, consumes
        // the bound prefix and reports a result with no claim, no step
        // ledger and no settlement decision. That is the hole this guard
        // closes: it runs BEFORE `continueExecution` — therefore before
        // any `context.model` forward and before `consumeBinding` — so a
        // sessionless G3 call cannot generate, consume, claim or settle.
        guard let session = self.g3CacheSession else {
            throw G3PerArmCacheError.missingCacheSession(
                "g3_route_requires_per_arm_cache_session")
        }
        // Per-arm cache path: every step runs over THIS arm's own
        // KVCacheSimple and is committed only if the write-boundary
        // observer did not refuse it. A refusal terminates the arm and
        // throws out of the gated method — never a fallback.
        let ledger = session.runLedger
        let result = try await self.continueExecutionG3WithPerArmCache(
            state, nextInputTokens: nextInputTokens,
            maxTokens: maxTokens, session: session)
        // Reached only after a cleared gate: register what this forward
        // materialized before the caller may treat the arm as isolated. This
        // stage happens AFTER settlement, so a throw here must leave the
        // consumed fact visible instead of reporting a clean refusal.
        if let registrar, let hook = self.duringGenerationRegistration {
            do {
                try await hook(result, registrar)
                ledger.recordPhase(.registration, .succeeded())
            } catch {
                ledger.recordPhase(.registration, .failed("\(error)"))
                throw error
            }
        } else {
            ledger.recordPhase(
                .registration,
                .skipped(registrar == nil ? "no_registrar" : "no_during_generation_hook"))
        }
        // G5: commit is the LAST linearization point of delivery, and it is
        // adjudicated — the terminal read, the cancellation sample, and the
        // commit transition all happen inside the arm's ONE domain, together with
        // every termination latch (session tombstone, gateway latch, binding
        // violation). A `guard terminal == nil` here followed by a separate
        // `recordPhase(.commit, .succeeded)` would leave the window the reviewer
        // named: a termination landing between the two statements.
        let commit = try session.commitDelivery(
            isCancelled: { self.isCancelled() },
            finalize: {}
        )
        switch commit {
        case .refusedBoundaryNotAdjudicating:
            throw G3PerArmCacheError.missingCacheSession(
                "\(session.armID):boundary_does_not_adopt_adjudication")
        case .refusedTermination(let reason):
            throw G3PerArmCacheError.armTerminated(reason: reason)
        case .refusedCancellation:
            throw CancellationError()
        case .committed:
            break
        }
        // G4: the cutoff is the region above. A cancellation observed AFTER it is
        // recorded for audit and changes nothing — the delivery already committed
        // and the binding is consumed. Treating a later sample as an atomic cancel
        // guarantee would be a false claim, so the protocol defines the cutoff and
        // this line only reports what fell behind it.
        if self.isCancelled() {
            ledger.recordCancellation(.afterCommitCutoff, detail: "observed_after_cutoff")
        }
        return result
    }

    // MARK: - Per-arm cache-backed G3 generation

    /// Run the G3 generation loop over THIS arm's private KV cache.
    ///
    /// It differs from ``continueExecution`` in exactly three G3-only ways:
    ///   1. the forward passes `cache: [thisArmCache]` — the arm's PER-LAYER cache
    ///      array, so attention routes through `attentionWithCacheUpdate` and the
    ///      fork's write-boundary observer on every layer;
    ///   2. the sequence is prefilled ONCE and every later step feeds ONLY the new
    ///      token — feeding the whole prefix again would append it to the cache a
    ///      second time and corrupt both the attention window and the offsets;
    ///   3. each step commits through the arm's ``G3ArmCacheSession``, which
    ///      DISCARDs the token and TERMINATES the arm if the cache aborted.
    ///
    /// A terminated arm throws ``G3PerArmCacheError/armTerminated(reason:)`` out of
    /// the gated method; the runner records `settled: false` and nothing falls back
    /// to the standard route or to the peer's cache.
    private func continueExecutionG3WithPerArmCache(
        _ state: ExecutionStateHandle,
        nextInputTokens: [Int],
        maxTokens: Int,
        session: G3ArmCacheSession
    ) async throws -> ExecutionContinuationResult {
        guard let boundary = session.boundary as? MLXKVCacheBoundary else {
            throw G3PerArmCacheError.missingCacheSession(session.armID)
        }
        // One ledger per run: it records the three INDEPENDENT axes — whether the
        // settlement gate was entered, whether the binding was actually consumed,
        // and each delivery stage's result. The settlement seam below writes the
        // first two; this body writes delivery.
        let ledger = session.runLedger
        // A session terminated by an earlier setup/step — or an arm explicitly
        // terminated at its gateway — must not re-enter the generation flow at
        // all. `terminalSnapshot` reads the gateway latch first and the session
        // tombstone second, here before cache resolution and the prefill claim, so
        // an explicit refusal stops the arm before one more (inert) forward.
        let entryTerminal = session.terminalSnapshot()
        if let reason = entryTerminal.effectiveTerminationReason {
            session.terminate(reason: reason)
            throw G3PerArmCacheError.armTerminated(reason: reason)
        }
        // G4: a caller already cancelled when the gated body is entered must not
        // claim a prefill or generate. This is a PRE-settlement cancellation; it
        // leaves both settlement axes false.
        if self.isCancelled() {
            session.terminate(reason: "task_cancelled")
            ledger.recordCancellation(.beforeSettlement, detail: "before_generation")
            throw CancellationError()
        }
        // One session = one prefill. The claim is atomic and taken BEFORE cache
        // resolution, so two gated calls racing this executor cannot both pass a
        // `stepCount == 0` check and feed the same cache twice. A claim is not
        // released: a failed continuation terminates the session through the
        // gated path, and a completed one has already used its prefill.
        let bound = try backend.boundPrefix(for: state)
        guard session.claimContinuation() else {
            throw G3PerArmCacheError.cacheSessionAlreadyUsed(session.armID)
        }
        let inputTokens = bound.prefix + nextInputTokens

        let (generated, abortReason, resolveError): ([Int], String?, G3PerArmCacheError?)
        do {
            (generated, abortReason, resolveError) = try await container.perform {
                (context: ModelContext) -> ([Int], String?, G3PerArmCacheError?) in
                let caches: [KVCache]
                do {
                    // Per-layer caches from the model, observer installed on every
                    // layer before its first use. An ungated cache type refuses here.
                    caches = try boundary.resolveCaches(context)
                } catch let error as G3PerArmCacheError {
                    return ([], nil, error)
                } catch {
                    return ([], nil, .unobservableCache("\(error)"))
                }

                var generated: [Int] = []
                // Step 1 consumes the whole prefix; later steps consume one token.
                var stepInput = MLXArray(inputTokens, [1, inputTokens.count])
                for _ in 0..<maxTokens {
                    // Cooperative cancellation: a cancelled caller must not start a
                    // new step, commit its token, or settle the ES below.
                    if self.isCancelled() {
                        session.terminate(reason: "task_cancelled")
                        return (generated, "task_cancelled", nil)
                    }
                    var logits: MLXArray?
                    let outcome = try session.runStep(
                        forward: {
                            // A cancellation observed inside the step must stop the
                            // token from being committed; runStep terminates and
                            // rethrows before candidateToken.
                            if self.isCancelled() { throw CancellationError() }
                            // THIS arm's caches only — never the peer's, never a
                            // shared one. The observer inside update() decides
                            // before writing, on every layer.
                            logits = context.model(stepInput, cache: caches)[0, -1]
                        },
                        candidateToken: {
                            // Reached only when no layer aborted, so a refused
                            // step's logits are never read, let alone committed.
                            if self.isCancelled() { throw CancellationError() }
                            return logits!.argMax().item(Int.self)
                        })
                    switch outcome {
                    case .committed(let token):
                        // Same token set as the recompute path: the produced token is
                        // part of the advanced representation, and a produced EOS
                        // ends generation AFTER being recorded.
                        generated.append(token)
                        // The cache already holds the prefix and this token.
                        stepInput = MLXArray([token], [1, 1])
                        if let logits { eval(logits) }
                        if token == (context.tokenizer.eosTokenId ?? -1) {
                            return (generated, nil, nil)
                        }
                    case .aborted(let reason), .refusedAfterTermination(let reason):
                        return (generated, reason, nil)
                    }
                }
                return (generated, nil, nil)
            }
        } catch {
            // The perform block can throw from the model container itself, not
            // only from runStep (which already terminated the session). A step
            // that was entered but could not complete leaves no live arm.
            session.terminate(reason: "g3_execution_threw(\(error))")
            ledger.recordPhase(.generation, .failed("g3_execution_threw(\(error))"))
            if error is CancellationError {
                ledger.recordCancellation(.duringGeneration, detail: "step_threw")
            }
            throw error
        }
        if let resolveError {
            // Cache creation / observer installation failed before any step ran.
            // Terminate so the same session cannot be retried into resolution.
            session.terminate(reason: "cache_resolution_failed(\(resolveError))")
            ledger.recordPhase(
                .generation, .failed("cache_resolution_failed: \(resolveError)"))
            throw resolveError
        }
        if let abortReason {
            // ES MUST NOT ADVANCE HERE. Everything below this throw settles the
            // run (`consumeBinding` turns the bound prefix stale, the result carries
            // the generated tokens). By returning the abort reason out of the
            // perform block and throwing BEFORE those statements, a refused arm
            // leaves the bound prefix untouched and has no settled output at all.
            ledger.recordPhase(.generation, .failed(abortReason))
            if abortReason == "task_cancelled" {
                ledger.recordCancellation(.duringGeneration)
            }
            throw G3PerArmCacheError.armTerminated(reason: abortReason)
        }
        ledger.recordPhase(.generation, .succeeded("committed=\(generated.count)"))
        // A release (or an external terminate) can land after the last committed
        // step but before this run settles. The settlement seam re-checks the
        // terminal latch and throws BEFORE the consume body runs, so settling an
        // arm whose owner already released it — or whose gateway was terminated —
        // is impossible. The executor still drives one arm sequentially; release is
        // expected to be serialized with that driver, but if it is not, the run
        // throws instead of reporting a settled result.
        //
        // G4: a cancellation observed after the last step but BEFORE the
        // settlement gate must refuse here. Checking only after the consume (the
        // old order) cannot undo an already-consumed binding.
        if self.isCancelled() {
            session.terminate(reason: "task_cancelled")
            ledger.recordCancellation(.beforeSettlement)
            throw CancellationError()
        }
        // This is the ONLY call site of `consumeBinding` in the G3 path. The
        // session-backed init re-reads ALL terminal sources at the gate, so an
        // independent gateway latch refuses just like this session's tombstone.
        let settlement = G3RunSettlement(armID: session.armID, session: session)
        do {
            try settlement.settle {
                backend.consumeBinding(for: state)
            }
        } catch let error as G3PerArmCacheError {
            if case let .armTerminated(reason) = error {
                session.terminate(reason: reason)
            }
            throw error
        }
        // G5: a termination that lands AFTER the settlement linearization point
        // does not undo `bindingConsumed`, but it must stop delivery. This is the
        // case a single tombstone check could not express.
        if let postSettlement = ledger.postSettlementTermination {
            ledger.recordPhase(
                .commit, .failed("terminated_after_settlement:\(postSettlement)"))
            session.terminate(reason: postSettlement)
            throw G3PerArmCacheError.armTerminated(reason: postSettlement)
        }
        // The last step can commit in the window between its `candidateToken`
        // cancellation check and the settlement gate. A cancelled caller must
        // not deliver a result; the ledger keeps the consumed fact explicit.
        if self.isCancelled() {
            session.terminate(reason: "task_cancelled")
            ledger.recordCancellation(.afterSettlement)
            ledger.recordPhase(.commit, .failed("cancelled_after_settlement"))
            throw CancellationError()
        }

        let extended = inputTokens + generated
        let text: String = await container.perform { (context: ModelContext) -> String in
            context.tokenizer.decode(tokenIds: generated, skipSpecialTokens: true)
        }
        ledger.recordPhase(.decode, .succeeded("tokens=\(generated.count)"))
        // G4: decode is synchronous and non-interruptible; cancellation is
        // observed at its boundary, after the decode completed but before the
        // result is handed back. The decode stage stays `succeeded`.
        if self.isCancelled() {
            session.terminate(reason: "task_cancelled")
            ledger.recordCancellation(.afterDecode)
            ledger.recordPhase(.commit, .failed("cancelled_after_decode"))
            throw CancellationError()
        }
        return ExecutionContinuationResult(
            executionID: state.id,
            consumedPrefixLength: bound.prefix.count,
            nextInputTokenCount: nextInputTokens.count,
            generatedTokenIDs: generated,
            generatedText: text,
            updatedPayload: MLXPrefixPayload(tokenPrefix: extended))
    }

    // MARK: - Native execution-carrier lifecycle
    //
    // Explicit release of THIS arm's carrier for one execution and the proof it
    // is genuinely unusable, reusing two published capabilities rather than
    // re-inventing them: the single-use ``G3CacheSessionSlot`` teardown (drops the
    // per-layer caches, their gateway and their write observers, and refuses any
    // re-arm) and the backend retired-carrier tombstone (drops the physical
    // representation and refuses every rebind/read). Mutable-storage isolation is
    // graded on the SAME `MLXArray.mlxStorageIdentity`-derived ids the gateway
    // already registered, so no weaker rule is applied at handoff than at
    // registration.

    /// Drop the execution's physical representation and KV/mutable references and
    /// RETIRE the carrier. Captures the retired carrier's confirmed mutable-storage
    /// ids before teardown (the gateway is gone once the session is released).
    public func releaseExecutionCarrier(for state: ExecutionStateHandle) throws {
        let gateway = g3CacheGateway
        retiredCarrierStorage[state.id] = gateway?.registeredBufferIDs ?? []
        // Release the KV session FIRST: its observers/gateway are torn down and
        // the slot retired, then the physical representation is dropped + retired.
        releaseG3KVCache()
        backend.releaseCarrier(for: state.id)
    }

    /// Prove the release took: the retired carrier refuses a bound read as
    /// `.carrierReleased` (not merely "unbound") and the cache-session slot is
    /// retired so nothing re-arms. Throws rather than reporting a false release.
    public func verifyCarrierUnusable(for state: ExecutionStateHandle) throws {
        guard backend.isCarrierRetired(for: state.id) else {
            throw CarrierLifecycleError.releaseIncomplete(
                reason: "physical representation carrier not retired")
        }
        do {
            _ = try backend.boundPrefix(for: state)
            throw CarrierLifecycleError.carrierStillUsable(executionID: state.id.rawValue)
        } catch let error as ExecutionStateBackendError {
            guard case .carrierReleased = error else {
                throw CarrierLifecycleError.releaseIncomplete(
                    reason: "bound read failed as \(error), not carrierReleased")
            }
        }
        guard g3CacheSlot.isRetired else {
            throw CarrierLifecycleError.releaseIncomplete(
                reason: "G3 cache session slot not retired")
        }
    }

    /// The retired carrier's confirmed mutable-storage ids for `state`.
    public func retiredCarrierStorageIDs(for state: ExecutionStateHandle) -> Set<String> {
        retiredCarrierStorage[state.id] ?? []
    }

    /// Prove a freshly adopted carrier on this executor is isolated from a retired
    /// carrier's storage ids. Grading uses ``CarrierStorageIsolationEvaluator`` —
    /// shared or unobservable aliasing throws, so a resume over aliased or
    /// unproven memory is refused.
    public func verifyAdoptedCarrierIsolated(
        from retiredStorageIDs: Set<String>,
        for state: ExecutionStateHandle
    ) throws {
        let adopting = g3CacheGateway?.registeredBufferIDs ?? []
        switch CarrierStorageIsolationEvaluator.evaluate(
            retired: retiredStorageIDs, adopting: adopting) {
        case .isolated:
            return
        case .shared(let overlap):
            throw CarrierLifecycleError.carriersShareStorage(
                executionID: state.id.rawValue,
                sharedBufferIDs: overlap.sorted())
        case .unobservable:
            throw CarrierLifecycleError.carrierStorageIsolationUnobservable(
                executionID: state.id.rawValue)
        }
    }
}

/// The real executor satisfies the same routing contract the native G3 entry and
/// the model-free control-flow tests exercise. Conformance is checked at compile
/// time by this empty extension: `continueExecution` is the ungated route and
/// `continueExecutionG3` is the gate-before-generation route, so any caller that
/// sends a G3 request through ``G3ExecutionDispatch`` with a `.g3` route reaches
/// the isolation gate ahead of the first `context.model(...)` forward here.
extension MLXPrefixRecomputeExecutor: G3RoutableContinuation, G3CacheSessionInstalling, ExecutionCarrierReleasing {}
