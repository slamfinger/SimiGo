import Foundation
import MLX
import MLXLMCommon
import SimiGoRuntimeContract

// NATIVE PER-ARM KV CACHE — the MLX implementation of the contract layer in
// `SimiGoRuntimeContract/G3PerArmKVCache.swift`.
//
// WHERE THE CACHE IS CREATED / HELD / RELEASED (the trace the reviewer asked for):
//   * CREATED: one real `KVCacheSimple` PER LAYER, for ONE arm. The array is
//     either built from the model itself (`context.model.newCache(parameters:)`,
//     the production shape — models index `cache[l]` per layer) or supplied by a
//     model-free test. A single cache for a multi-layer model is NOT a cache: the
//     model would index past it or mix layers.
//   * OBSERVER BOUND: when the boundary resolves its cache array, i.e. before the
//     cache's first use (cold start included), every layer's write hook is BOUND
//     (`bindWriteObserver`), not merely assigned, and the minted capability stays
//     inside this boundary. Every layer shares the arm's ONE
//     `G3KVAllocationGateway`, so all layers are graded by one registered set.
//   * HELD: by the arm's `MLXPrefixRecomputeExecutor` (installed through
//     `G3CacheSessionInstalling`); the session is the single handle.
//   * RELEASED: `MLXPrefixRecomputeExecutor.releaseG3KVCache()` TERMINATES the
//     session (`cache_session_released`), drops it (and with it the caches, gateway
//     and observer) and retires the executor's single-use cache slot. Terminating
//     first is what makes a release racing an in-flight step fail closed: the
//     step's commit check sees the tombstone and discards its token. A run does NOT
//     auto-release: while installed, the session refuses a second, different
//     session; after release, the slot's tombstone refuses every install. A
//     terminated or already-used arm therefore cannot be silently re-armed with a
//     fresh cache, and the gated entry refuses a retired slot instead of falling
//     into the recompute route.
//
// FAIL CLOSED ON UNOBSERVABLE CACHE TYPES:
//   Only the EXACT `KVCacheSimple` type carries the native write seam. A layer
//   whose cache is e.g. `RotatingKVCache`/`QuantizedKVCache` cannot be gated, so
//   the arm is refused before any forward (`unobservableCache`) rather than
//   running generation over mutable KV nobody observed. Subclasses are refused
//   too: `ChunkedKVCache` OVERRIDES `update` and never calls `writeObserver`, so
//   an `as? KVCacheSimple` check would install a gate that silently never fires.
//
// ONE GATED CACHE, ONE ARM:
//   A `KVCacheSimple` that already carries a write observer belongs to another
//   arm's boundary. Installing this arm's observer would OVERWRITE that gate, so
//   the second arm's writes would be graded by the wrong registrar — or by none.
//   Such a cache is refused (`armsShareMutableCache`) before any observer is
//   touched, which is the native-object form of "two arms never share mutable
//   KV". The boundary-object guard in `G3PerArmCachePair` cannot see this case;
//   it compares boundaries, not the native caches they wrap.
//
// GATE INTEGRITY (a gate any holder of the cache reference can clear is not a gate):
//   `KVCacheSimple.writeObserver` stays assignable for ordinary, UNBOUND caches, so
//   normal inference is unchanged. Once an arm BINDS its observer, the setter
//   refuses a clear or a swap and latches `write_observer_mutated_after_binding`;
//   that latch is permanent (`beginStep()` cannot reset it) and `update()` itself
//   refuses to write while it is set. `unbindWriteObserver` accepts only the
//   capability minted for that cache, which never leaves the boundary. Before
//   EVERY forward, `beginStep()` re-verifies each layer's binding id and observer
//   identity and fails closed if either changed, so a tampered cache cannot reach
//   another forward, let alone commit another token.
//
// WHAT A REFUSAL CONTAINS (and what it cannot do):
//   MLX's cache API returns a tuple, not a throwing result, so a refusal cannot
//   unwind a model forward that is already executing. What the wiring DOES
//   guarantee — pinned by the fault-injection tests in
//   `G3RefusalContainmentTests` — is:
//     * the refusing layer skips its write (offset rolled back, nothing written);
//     * every LATER layer of the same forward is refused too: the gateway keeps
//       an arm-level `terminatedReason` and refuses all subsequent writes, so a
//       partially executed forward cannot keep writing KV after the first refusal;
//     * `G3ArmCacheSession.runStep` sees `isolationAborted` after the forward,
//       discards the candidate WITHOUT calling the sampler, and latches the
//       session; no later step runs, the executor throws before `consumeBinding`,
//       so ES is not advanced and nothing is settled.
//   The remaining forward computation is not cancelled; it is INERT — it writes
//   no KV and its logits are never read. That is the strongest containment the
//   non-throwing MLX cache API permits, stated as such rather than as "the
//   forward was terminated".
//
// EVAL SEMANTICS AT THE WRITE BOUNDARY (measured, not "zero cost"):
//   `G3KVAllocationGateway.handleCacheWrite` calls `keys.eval()` / `values.eval()`
//   on the args the cache hands it, which are `self.keys` / `self.values` — the
//   cache's OWN buffer — NOT the step's incoming K/V projection and NOT the model
//   forward graph. `update` builds that buffer from a zeros leaf plus the already
//   materialized cache (`concatenated`), so its graph contains no projection:
//     * Fresh step: `self.keys = MLXArray.zeros(...)`; the eval realizes a trivial
//       leaf that is written one statement later anyway.
//     * Growth step: `self.keys = concatenated([current, zeros], axis: 2)`; the
//       eval realizes the grown copy — the same copy the following slice-assign
//       would force. It does NOT realize the step's K/V projection; that write
//       happens only after `.allow`.
//     * Reuse step: the buffer was realized when it was admitted, so eval is a
//       no-op (the common case: every step inside a 256-token window).
//     * Refusal: the grown copy is realized and then discarded (bounded: one
//       buffer per layer at a growth boundary), and NOTHING is written.
//   Unrelated lazy arrays cannot be realized because MLX evaluates only the graph
//   reachable from the evaluated array; `gatewayObserverEvaluationIsBoundedToTheKVBuffer`
//   and `incomingProjectionIsNotRealizedByWriteBoundaryEval` pin both claims.
//   Removing the eval would require a storage-identity read that does not need a
//   realized buffer; the fork does not have one, so the trade-off is documented
//   rather than hidden.
//   SCOPE OF THIS EVIDENCE: those tests run on the CPU device with one exact
//   `KVCacheSimple` per layer, along the fresh/grow/reuse paths. They support
//   "bounded synchronous materialization on the tested path"; they do NOT prove
//   near-zero cost for every MLX backend, every cache topology, or a real model
//   forward. The claim is kept at that scope.

/// One arm's real KV caches — one per layer — exposed through the contract's
/// `G3ArmCacheBoundary`, with the write observer installed on every layer before
/// first use.
public final class MLXKVCacheBoundary: G3ArmCacheBoundary, @unchecked Sendable {
    /// The arm's single admission gate; every layer's write observer and the
    /// post-forward registration hook share it, so all layers are graded by one
    /// rule and one registered-buffer set.
    public let gateway: G3KVAllocationGateway

    /// The capability minted by `gateway`. Kept private: `terminateArm` is the only
    /// public use of it, so the boundary cannot hand another arm (or external code)
    /// the authority to terminate this one.
    private let gatewayTerminationGrant: G3GatewayTerminationGrant

    private let lock = NSLock()
    private var _caches: [KVCache]?

    /// One layer's gate: the cache, the observer BOUND to it, and the capability
    /// that binding was minted with. The capability never leaves this type, so no
    /// other arm can unbind or replace this arm's gate.
    private struct GatedLayer {
        let cache: KVCacheSimple
        let observer: G3KVCacheWriteObserver
        let binding: KVCacheWriteObserverBinding
    }

    private var _gated: [GatedLayer] = []
    /// Latched when pre-execution verification finds a layer whose write gate is
    /// no longer the observer/binding this boundary installed. Permanent for the
    /// arm: a tampered gate must fail closed, never resume writing.
    private var _bindingViolation: String?
    /// The arm's adjudication domain, adopted from the session that wraps this
    /// boundary. It is forwarded to the gateway (whose latch is the commit region's
    /// terminal read) and used for the binding-violation latch, so no termination
    /// this boundary can produce is written outside the domain.
    private var _terminationDomain: G3Adjudication?
    private let build: ((ModelContext) throws -> [KVCache])?

    /// Eager form: caches already exist (model-free tests, or a composition root
    /// that built them from the model). Throws when any layer cannot be gated.
    public init(
        armLabel: String, registrar: G3AllocationRegistrar, caches: [KVCache]
    ) throws {
        let gateway = G3KVAllocationGateway(registrar: registrar, armLabel: armLabel)
        self.gateway = gateway
        self.gatewayTerminationGrant = gateway.terminationGrant
        self.build = nil
        self._caches = caches
        self._gated = try Self.installObserver(
            gateway.makeWriteObserver(), on: caches)
    }

    /// Lazy production form: the per-layer array is built from the loaded model
    /// (`context.model.newCache(parameters:)`) on FIRST resolution inside
    /// `container.perform` — still before the cache's first use. The model, not
    /// this type, decides how many caches a layer topology needs.
    public init(
        armLabel: String, registrar: G3AllocationRegistrar,
        makeCaches: @escaping (ModelContext) throws -> [KVCache]
    ) {
        let gateway = G3KVAllocationGateway(registrar: registrar, armLabel: armLabel)
        self.gateway = gateway
        self.gatewayTerminationGrant = gateway.terminationGrant
        self.build = makeCaches
    }

    /// Single-layer convenience (single-layer models and model-free tests).
    public convenience init(
        armLabel: String, registrar: G3AllocationRegistrar, step: Int = 256
    ) throws {
        let cache = KVCacheSimple()
        cache.step = step
        try self.init(armLabel: armLabel, registrar: registrar, caches: [cache])
    }

    /// Resolve this arm's per-layer caches, installing the write observer on every
    /// layer exactly once. Must be called inside `container.perform`, before the
    /// first forward. Throws `unobservableCache` for a layer with no write seam.
    public func resolveCaches(_ context: ModelContext) throws -> [KVCache] {
        lock.lock(); defer { lock.unlock() }
        if let caches = _caches { return caches }
        guard let build else {
            throw G3PerArmCacheError.missingCacheSession("no cache builder")
        }
        let caches = try build(context)
        _gated = try Self.installObserver(gateway.makeWriteObserver(), on: caches)
        _caches = caches
        return caches
    }

    /// The resolved per-layer array (empty before resolution).
    public var caches: [KVCache] {
        lock.lock(); defer { lock.unlock() }
        return _caches ?? []
    }

    public var isResolved: Bool {
        lock.lock(); defer { lock.unlock() }
        return _caches != nil
    }

    /// Number of layers whose cache is actually gated by this arm's observer.
    public var observedCacheCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _gated.count
    }

    // MARK: G3ArmCacheBoundary (aggregated over every layer)

    /// Adopt the arm's adjudication domain and hand it to the gateway. Returns
    /// `true` to declare participation: from here on, this boundary's termination
    /// latches (gateway arm-level latch and binding violation) are written inside
    /// the SAME region the session's commit decision runs in. Without that
    /// declaration `G3ArmCacheSession.commitDelivery` refuses the run.
    @discardableResult
    public func adoptTerminationAdjudication(
        _ domain: G3Adjudication, report: @escaping @Sendable (String) -> Void
    ) -> Bool {
        domain.adjudicate {
            lock.lock()
            _terminationDomain = domain
            let violation = _bindingViolation
            lock.unlock()
            gateway.adoptTerminationAdjudication(domain, report: report)
            // A violation latched before adoption is likewise reported, so the
            // session never loses a termination that already happened.
            if let violation { report(violation) }
        }
        return true
    }

    /// Terminate THIS arm through the gateway capability minted for this boundary.
    /// The first accepted reason is permanent; a second arm's grant is rejected by
    /// the gateway and leaves both arms untouched.
    @discardableResult
    public func terminateArm(reason: String) -> G3GatewayTerminationOutcome {
        gateway.terminate(reason: reason, grant: gatewayTerminationGrant)
    }

    /// The arm-level termination reason, or nil while the arm is live. This is the
    /// same latch `handleCacheWrite` consults, so a terminated arm's later steps are
    /// refused before a forward even when no layer has latched a per-step abort.
    public var terminatedReason: String? { gateway.terminatedReason }

    public func beginStep() {
        lock.lock(); let gated = _gated; let violation = _bindingViolation; lock.unlock()
        if violation != nil { return }
        // Pre-execution verification: every layer must still carry THIS boundary's
        // observer under THIS binding. A cleared, replaced or re-bound gate is
        // caught here, BEFORE the step's forward runs — so a tampered cache can
        // never reach another forward, let alone commit a token.
        for (index, layer) in gated.enumerated() {
            guard layer.cache.observerBindingViolation == nil,
                  layer.cache.writeObserverBindingID == layer.binding.id,
                  layer.cache.writeObserver === layer.observer else {
                latchBindingViolation(
                    layer.cache.observerBindingViolation
                        ?? "observer_binding_lost(layer \(index))")
                return
            }
        }
        // A per-step reset must NEVER clear a termination. Once any layer latched an
        // abort the arm is dead, so this leaves the native latch (and therefore
        // `isolationAborted`) set: a stray reset cannot make the arm look live again.
        // The gateway's own `terminatedReason` is a second, unresetable latch.
        guard gateway.terminatedReason == nil else { return }
        guard !gated.contains(where: { $0.cache.isolationAborted }) else { return }
        for layer in gated { layer.cache.beginStep() }
    }

    private func latchBindingViolation(_ reason: String) {
        // Inside the domain when one is installed, so a tampered-gate latch is
        // serialized against settlement and commit like every other termination.
        lock.lock(); let domain = _terminationDomain; lock.unlock()
        if let domain {
            domain.adjudicate {
                lock.lock()
                if _bindingViolation == nil { _bindingViolation = reason }
                lock.unlock()
            }
            return
        }
        lock.lock()
        if _bindingViolation == nil { _bindingViolation = reason }
        lock.unlock()
    }

    /// Conservative aggregation: a refusal in ANY layer — or an explicit gateway
    /// termination — aborts the step. The gateway latch is checked FIRST so an
    /// external `terminateArm` is visible before any forward runs (the session's
    /// pre-step check), not only after the next write boundary is reached.
    public var isolationAborted: Bool {
        if gateway.terminatedReason != nil { return true }
        lock.lock(); let violation = _bindingViolation; let gated = _gated; lock.unlock()
        if violation != nil { return true }
        return gated.contains { $0.cache.isolationAborted }
    }

    public var isolationAbortReason: String? {
        if let reason = gateway.terminatedReason { return reason }
        lock.lock(); let violation = _bindingViolation; let gated = _gated; lock.unlock()
        if let violation { return violation }
        return gated.first { $0.cache.isolationAborted }?.cache.isolationAbortReason
    }

    private static func installObserver(
        _ observer: G3KVCacheWriteObserver, on caches: [KVCache]
    ) throws -> [GatedLayer] {
        // Validate EVERY layer first, so a refusal cannot leave half an arm gated.
        let simples = try caches.enumerated().map { index, cache -> KVCacheSimple in
            guard let simple = cache as? KVCacheSimple else {
                throw G3PerArmCacheError.unobservableCache(
                    "layer \(index) is \(type(of: cache)); only KVCacheSimple exposes the write boundary")
            }
            // The seam lives in `KVCacheSimple.update`. A SUBCLASS can override
            // `update` and never call the observer — `ChunkedKVCache` does exactly
            // that — so accepting it would install a gate that never fires and
            // report an arm as gated while its KV was written unobserved. Only the
            // exact type the seam was added to is accepted.
            guard type(of: simple) == KVCacheSimple.self else {
                throw G3PerArmCacheError.unobservableCache(
                    "layer \(index) is \(type(of: simple)); it overrides update() and bypasses "
                    + "the KVCacheSimple write boundary, so the arm would be silently ungated")
            }
            // A cache that already carries a write observer is gated by another
            // arm's boundary; assigning here would replace that gate. Refuse the
            // shared native cache instead of silently re-arming it.
            guard simple.writeObserver == nil else {
                throw G3PerArmCacheError.armsShareMutableCache(
                    "layer \(index)'s KVCacheSimple already carries a write observer: "
                    + "one mutable cache cannot be gated by two arms")
            }
            return simple
        }
        // Two layer slots must not share one mutable cache: every layer writes its
        // own KV range, so a shared instance would mix layers inside one arm before
        // the cross-arm check ever runs.
        guard Set(simples.map { ObjectIdentifier($0) }).count == simples.count else {
            throw G3PerArmCacheError.armsShareMutableCache(
                "the same KVCacheSimple instance appears in two layer slots of one arm")
        }
        // BIND, do not assign: the returned capability is the only way to remove
        // or replace this gate later, and it stays inside this boundary. If a
        // layer was gated between validation and binding, roll back the layers
        // already bound here so a refusal never leaves half an arm gated.
        var gated: [GatedLayer] = []
        for simple in simples {
            guard let binding = simple.bindWriteObserver(observer) else {
                for layer in gated { layer.cache.unbindWriteObserver(layer.binding) }
                throw G3PerArmCacheError.armsShareMutableCache(
                    "a layer was gated by another boundary before this one could bind it")
            }
            gated.append(GatedLayer(cache: simple, observer: observer, binding: binding))
        }
        return gated
    }
}

// MARK: - Factory

public enum MLXPerArmKVCacheFactory {
    /// Build one arm's session over caches that already exist (tests, or a caller
    /// that built them from the model). Requires the arm's SEALED registrar, which
    /// only exists after the ownership precondition passed — so a cache can never
    /// be created for an arm that was not checked.
    public static func makeSession(
        armID: RuntimeArmID,
        registrar: G3AllocationRegistrar,
        caches: [KVCache]
    ) throws -> G3ArmCacheSession {
        let boundary = try MLXKVCacheBoundary(
            armLabel: armID.rawValue, registrar: registrar, caches: caches)
        return G3ArmCacheSession(armID: armID.rawValue, boundary: boundary)
    }

    /// Production shape: one cache per layer, produced by the loaded model on
    /// first use and gated before that use.
    public static func makeSession(
        armID: RuntimeArmID,
        registrar: G3AllocationRegistrar,
        makeCaches: @escaping (ModelContext) throws -> [KVCache]
    ) -> G3ArmCacheSession {
        let boundary = MLXKVCacheBoundary(
            armLabel: armID.rawValue, registrar: registrar, makeCaches: makeCaches)
        return G3ArmCacheSession(armID: armID.rawValue, boundary: boundary)
    }

    /// The production closure: one cache array per ARM, built by the model itself
    /// (one entry per layer, honouring the model's own cache topology).
    ///
    /// `parameters: nil` deliberately requests the model's DEFAULT topology: with
    /// no capacity limit the attention layers resolve to `KVCacheSimple` (which
    /// carries the write seam). A capacity/window request can yield a rotating or
    /// quantized cache with no seam; such a layer — and any `KVCacheSimple`
    /// SUBCLASS that overrides `update` (e.g. `ChunkedKVCache`) — is then refused
    /// fail-closed (`unobservableCache`) instead of being silently left ungated.
    public static var modelCacheBuilder: (ModelContext) throws -> [KVCache] {
        { context in try context.model.newCache(parameters: nil) }
    }

    /// Single-layer convenience (single-layer models and model-free tests).
    public static func makeSession(
        armID: RuntimeArmID,
        registrar: G3AllocationRegistrar,
        step: Int = 256
    ) throws -> G3ArmCacheSession {
        let boundary = try MLXKVCacheBoundary(
            armLabel: armID.rawValue, registrar: registrar, step: step)
        return G3ArmCacheSession(armID: armID.rawValue, boundary: boundary)
    }

    /// Build BOTH arms' sessions and run the non-sharing guard. The two cache
    /// arrays are separate objects by construction; `G3PerArmCachePair` additionally
    /// refuses a shared boundary or duplicated arm identity, so "one mutable cache
    /// for both arms" cannot be wired by accident.
    public static func makePair(
        es: (armID: RuntimeArmID, registrar: G3AllocationRegistrar),
        isOnly: (armID: RuntimeArmID, registrar: G3AllocationRegistrar),
        makeCaches: @escaping (ModelContext) throws -> [KVCache]
    ) throws -> G3PerArmCachePair {
        try G3PerArmCachePair(
            es: makeSession(armID: es.armID, registrar: es.registrar, makeCaches: makeCaches),
            isOnly: makeSession(
                armID: isOnly.armID, registrar: isOnly.registrar, makeCaches: makeCaches))
    }
}

// MARK: - The production composition root

extension G3DualArmRunner {
    /// The MLX production entry: EVERY arm gets its own per-layer cache array,
    /// built by the loaded model and gated before first use. There is no argument
    /// to forget — a caller cannot run a model-level G3 pair through this entry
    /// without the per-arm cache wiring.
    ///
    /// Requires a loaded `ModelContext` at call time (authorization phase); under
    /// the current empty trust registry the gate still refuses both arms first, so
    /// no generation runs. The gate sits inside each arm's gated continuation, i.e.
    /// before the cache is resolved or any forward executes.
    public static func runMLX(
        _ first: G3ArmExecution<MLXPrefixRecomputeExecutor>,
        _ second: G3ArmExecution<MLXPrefixRecomputeExecutor>
    ) async throws -> G3DualArmRunReport {
        try await run(first, second, makeCacheSession: { armID, registrar in
            MLXPerArmKVCacheFactory.makeSession(
                armID: armID, registrar: registrar,
                makeCaches: MLXPerArmKVCacheFactory.modelCacheBuilder)
        })
    }
}
