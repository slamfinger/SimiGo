import Foundation
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

public typealias MLXChatContainerLoader = @Sendable (URL) async throws -> ModelContainer

/// Option A GUI host path (approved in
/// docs/08-research-memory/SIMIGO_GUI_PROMOTION_BOUNDARY_REVIEW_20261014.md):
/// a small-scale ChatSession runtime that runs PARALLEL to the
/// `OversizedSegmentedEngine`, never instead of it.
///
/// Scope, deliberately narrow:
/// - The host serves only the model directory it is explicitly activated
///   with. It holds no reference to the segmented engine path, shares no
///   execution state with it, and cannot silently reroute requests — the
///   model-applicability decision belongs to the caller (UI), not to this
///   type.
/// - Lifecycle: `activate` (fail-closed; refuses to displace another active
///   model — use ``switchModel(to:)`` for the explicit switch), `switchModel`
///   (load new → ownership takeover → drop the previous container),
///   `deactivate`. One hook owner per process, enforced by the
///   `MLXPrefixCrossSessionCache` ownership layer.
/// - Model identity is content-derived (``MLXModelContentIdentity``): two
///   directories with the same name but different model content land in
///   different cache namespaces and can never adopt each other's snapshots.
/// - DCC-1 Tier-1 recovery semantics are untouched: this type does not
///   reference, persist into, or recover from the engine's session baseline.
public final class MLXSmallScaleChatHost: @unchecked Sendable {
    public enum HostError: Error, Equatable, Sendable {
        case modelDirectoryMissing(URL)
        case modelDirectoryRevisionUnavailable(URL)
        case modelDirectoryChangedDuringActivation(URL)
        case alreadyActive(URL)
        case notActive
        /// A session issued under an earlier host generation attempted to
        /// generate after a model switch (F4 caller-identity closure at the
        /// host API boundary).
        case sessionStale(issuedFor: URL, currentlyActive: URL?)
        /// switchModel could not drain in-flight generations within its
        /// bound; the switch is refused with the previous state untouched
        /// rather than overlapping the next model's load with a running
        /// generation.
        case inFlightGenerationBlockedSwitch
    }

    /// The host's durable cache base directory; per-model store roots are
    /// derived under it and survive process restarts.
    public let base: URL
    private let containerLoader: MLXChatContainerLoader
    /// Injectable only through the module-internal initializer so activation
    /// drift can be fault-tested without a multi-gigabyte model or timing race.
    private let modelDirectoryRevisionProvider: @Sendable (URL) -> String?
    /// Serializes the async lifecycle transitions (load → install → swap).
    private let lifecycleGate = AsyncLock()
    /// Guards synchronous observation of `state` against the async writer
    /// (reads never suspend, so they take this lock, not the gate).
    private let stateLock = NSLock()
    private var state: ActiveModel?
    /// Bumped on every activate/switch/deactivate. Issued sessions carry the
    /// generation they were created under; the hook's admission guard refuses
    /// any lookup from a stale generation even if a session slips past the
    /// wrapper check (TOCTOU closure).
    private var generation = 0
    /// In-flight generations issued through this host, keyed by task. A
    /// switch must not overlap the next model's load with a still-running
    /// old-model generation: switchModel CANCELS these tasks and WAITS for
    /// them to drain before releasing the container (F4 reopen: release
    /// must be provable, not implied).
    private var inFlightTasks: Set<Task<String, Error>> = []

    private func currentGeneration() -> Int {
        stateLock.withLock { generation }
    }

    /// The admission guard installed with every cache: refuse lookups unless
    /// the host is still in the generation the cache was installed under.
    private func admissionGuard(for installedGeneration: Int) -> @Sendable () -> Bool {
        { [weak self] in self?.currentGeneration() == installedGeneration }
    }

    private struct ActiveModel {
        let directory: URL
        let contentIdentity: MLXPrefixCrossSessionCache.MLXModelContentIdentity
        let container: ModelContainer
        let cache: MLXPrefixCrossSessionCache
    }

    public init(
        base: URL,
        containerLoader: @escaping MLXChatContainerLoader = MLXSmallScaleChatHost
            .defaultContainerLoader
    ) {
        self.init(
            base: base,
            containerLoader: containerLoader,
            revisionProvider: { modelDirectory in
                MLXPrefixCrossSessionCache.modelDirectoryRevision(
                    modelDirectory: modelDirectory)
            })
    }

    /// Module-internal seam for deterministic activation fault tests. Production
    /// callers use the public initializer and the real filesystem revision.
    init(
        base: URL,
        containerLoader: @escaping MLXChatContainerLoader,
        revisionProvider: @escaping @Sendable (URL) -> String?
    ) {
        self.base = base
        self.containerLoader = containerLoader
        self.modelDirectoryRevisionProvider = revisionProvider
    }

    public static let defaultContainerLoader: MLXChatContainerLoader = { url in
        try await MLXLLM.LLMModelFactory.shared.loadContainer(
            from: url, using: #huggingFaceTokenizerLoader())
    }

    /// The currently active model directory, if any (UI display / scope
    /// assertions).
    public var activeModelDirectory: URL? {
        stateLock.withLock {  state?.directory }
    }

    /// Cache observations of the active model, if any.
    public var activeObservations: MLXPrefixHookObservation? {
        stateLock.withLock {  state?.cache.observations }
    }

    /// The active model's prefix snapshot store (probe/inspection access).
    public var activeStore: PrefixSnapshotStore? {
        stateLock.withLock {  state?.cache.store }
    }

    /// The active model's content-derived namespace (probe/inspection).
    public var activeNamespace: PrefixPoolNamespace? {
        stateLock.withLock {  state?.cache.namespace }
    }

    /// Run a body against the active model's context (tokenizer access for
    /// probes; the container itself is Sendable and already shared by
    /// concurrent sessions).
    public func perform<T: Sendable>(
        _ body: @escaping @Sendable (ModelContext) async throws -> T
    ) async throws -> T {
        guard let container = stateLock.withLock({ state?.container }) else {
            throw HostError.notActive
        }
        return try await container.perform(body)
    }

    /// Activate a model as this host's small-scale path. Fails closed: a
    /// loader or ownership failure leaves the global hook exactly as it was.
    /// Idempotent for the already-active model; refuses a DIFFERENT model
    /// while one is active (``HostError/alreadyActive``) — the explicit
    /// switch is ``switchModel(to:)``, never a silent reroute.
    @discardableResult
    public func activate(modelDirectory: URL) async throws -> URL {
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
            throw HostError.modelDirectoryMissing(modelDirectory)
        }
        await lifecycleGate.lock()
        defer { lifecycleGate.unlock() }
        if let active = stateLock.withLock({ state }) {
            if active.directory == modelDirectory {
                return active.directory
            }
            throw HostError.alreadyActive(active.directory)
        }
        // Bump BEFORE loading so the installed admission guard binds to the
        // generation this activation creates (state is nil here, so no
        // issued session exists to invalidate).
        stateLock.withLock { generation &+= 1 }
        let loaded = try await loadAndOwn(modelDirectory: modelDirectory)
        stateLock.withLock { state = loaded }
        return modelDirectory
    }

    /// The explicit model switch with a TRUE single-resident memory
    /// discipline (F4 revision): the previous container is RELEASED BEFORE
    /// the next one loads — two 4bit 30B-class models do not fit this
    /// machine's memory, and a successful round trip does not bound the
    /// switch-time peak. Sequence: bump the generation (every session issued
    /// under the old model becomes stale at the API boundary and the hook
    /// admission guard goes cold), release hook ownership, DROP the old
    /// container, then load the new one. Rollback on failure RELOADS the
    /// previous model instead of relying on still holding it; if even the
    /// reload fails, the host reports itself deactivated (state nil) with
    /// the original error — never a silently half-switched state. The
    /// previous model's cache artifacts stay durable under their own
    /// content-derived root and are re-adopted when it is switched back.
    @discardableResult
    public func switchModel(to modelDirectory: URL) async throws -> URL {
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
            throw HostError.modelDirectoryMissing(modelDirectory)
        }
        await lifecycleGate.lock()
        defer { lifecycleGate.unlock() }
        // Capture the DIRECTORY only (F4 reopen): holding the ActiveModel
        // value here would keep the old ModelContainer alive across the
        // next load through this local, defeating single residency at the
        // very switch that promises it.
        let previousDirectory = stateLock.withLock({ state?.directory })
        if let previousDirectory, previousDirectory == modelDirectory {
            return previousDirectory
        }
        // Invalidate issued sessions FIRST (stale at the API boundary and
        // at the hook guard), then cancel and DRAIN in-flight generations —
        // a switch must not overlap the next load with a still-running
        // old-model generation. A drain past the bound fails the switch
        // with the old state untouched rather than risking the overlap.
        stateLock.withLock { generation &+= 1 }
        guard await cancelAndWaitForInFlightDrain(limit: .seconds(120)) else {
            throw HostError.inFlightGenerationBlockedSwitch
        }
        stateLock.withLock { state }?.cache.uninstall()
        // Drop the container reference BEFORE loading the next model; from
        // here a still-resident old model can only be caller-held sessions
        // the host cannot reach (documented boundary, see HostSession).
        stateLock.withLock { state = nil }
        do {
            let next = try await loadAndOwn(modelDirectory: modelDirectory)
            stateLock.withLock { state = next }
            return modelDirectory
        } catch {
            // Rollback = re-load the previous model (its container is gone).
            if let previousDirectory {
                do {
                    let restored = try await loadAndOwn(
                        modelDirectory: previousDirectory)
                    stateLock.withLock { state = restored }
                } catch {
                    // Even the rollback reload failed: report the host as
                    // deactivated with the ORIGINAL switch error visible.
                    stateLock.withLock {
                        generation &+= 1
                        state = nil
                    }
                }
            }
            throw error
        }
    }

    /// Deactivate: bump the generation (issued sessions become stale),
    /// release hook ownership, and drop the container. Durable artifacts
    /// stay on disk.
    public func deactivate() {
        stateLock.withLock {
            generation &+= 1
            if let active = state {
                active.cache.uninstall()
            }
            state = nil
        }
    }

    /// A session bound to the active model, carrying the host generation it
    /// was issued under (F4 caller-identity closure at the host API
    /// boundary): after a model switch its generate attempts are REJECTED —
    /// a pre-switch session can never evaluate against, and thereby adopt,
    /// the next model's snapshots.
    public struct HostSession {
        let session: ChatSession
        let issuedGeneration: Int
        let issuedFor: URL
        unowned let host: MLXSmallScaleChatHost

        public func respond(to prompt: String) async throws -> String {
            let (text, _) = try await respondWithObservations(to: prompt, maxTokens: nil)
            return text
        }

        public func respond(to prompt: String, maxTokens: Int) async throws -> String {
            let (text, _) = try await respondWithObservations(
                to: prompt, maxTokens: maxTokens)
            return text
        }

        public func respondWithObservations(
            to prompt: String, maxTokens: Int?
        ) async throws -> (text: String, observations: MLXPrefixHookObservation) {
            guard let (active, currentGeneration) = host.stateLock.withLock({
                host.state.map { ($0.directory, host.generation) }
            }) else {
                throw HostError.notActive
            }
            guard currentGeneration == issuedGeneration, active == issuedFor else {
                throw HostError.sessionStale(
                    issuedFor: issuedFor, currentlyActive: active)
            }
            _ = maxTokens // parameters already bound at session construction
            return try await host.runInFlight {
                try await self.session.respond(to: prompt)
            }
        }

        /// Probe passthrough: durable prefix export of the underlying
        /// session (generation-checked like any other use).
        func savePrefixSnapshot(to url: URL, upTo tokenCount: Int) async throws {
            guard let (active, currentGeneration) = host.stateLock.withLock({
                host.state.map { ($0.directory, host.generation) }
            }) else {
                throw HostError.notActive
            }
            guard currentGeneration == issuedGeneration, active == issuedFor else {
                throw HostError.sessionStale(
                    issuedFor: issuedFor, currentlyActive: active)
            }
            try await session.savePrefixSnapshot(to: url, upTo: tokenCount)
        }
    }

    /// A session bound to the active model. Cross-session cache adoption
    /// flows through the globally installed hook while this host owns it and
    /// this generation is current.
    public func makeSession(
        generateParameters: GenerateParameters = GenerateParameters(
            maxTokens: 256, temperature: 0)
    ) throws -> HostSession {
        guard let (container, directory, issuedGeneration) = stateLock.withLock({
            state.map { ($0.container, $0.directory, generation) }
        }) else {
            throw HostError.notActive
        }
        return HostSession(
            session: ChatSession(container, generateParameters: generateParameters),
            issuedGeneration: issuedGeneration,
            issuedFor: directory,
            host: self)
    }

    /// One small-scale turn through the active model.
    public func respond(
        to prompt: String, maxTokens: Int
    ) async throws -> (text: String, observations: MLXPrefixHookObservation) {
        let session = try makeSession(
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0))
        return try await session.respondWithObservations(to: prompt, maxTokens: maxTokens)
    }

    /// Runs a generation body registered as in-flight so a model switch can
    /// cancel and drain it instead of overlapping it with the next load.
    private func runInFlight(
        _ body: @escaping @Sendable () async throws -> String
    ) async throws -> (text: String, observations: MLXPrefixHookObservation) {
        let task = Task {
            try await body()
        }
        stateLock.withLock { inFlightTasks.insert(task) }
        defer { stateLock.withLock { inFlightTasks.remove(task) } }
        let text = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        guard let observations = activeObservations else {
            throw HostError.notActive
        }
        return (text, observations)
    }

    /// Cancel every in-flight generation and wait for the drain. Bounded by
    /// `limit`; returns false when a generation ignored cancellation past
    /// the bound (the caller fails the switch rather than risking a
    /// two-model residency overlap).
    private func cancelAndWaitForInFlightDrain(limit: Duration) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while true {
            let pending = stateLock.withLock { inFlightTasks }
            if pending.isEmpty { return true }
            for task in pending { task.cancel() }
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// Load the container, derive the content identity, build the
    /// content-namespaced cache, and take hook ownership. The caller must
    /// already hold the lifecycle gate and must have released any previous
    /// ownership (``switchModel(to:)`` restores it on failure).
    private func loadAndOwn(modelDirectory: URL) async throws -> ActiveModel {
        // Capture the relevant model-file metadata before hashing. Confirm it
        // stayed stable across the O(model-bytes) content identity and load
        // phases; this prevents ordinary in-place updates from binding an old
        // content namespace to a newly replaced directory revision.
        guard let directoryRevision = modelDirectoryRevisionProvider(modelDirectory) else {
            throw HostError.modelDirectoryRevisionUnavailable(modelDirectory)
        }
        let contentIdentity = await Task.detached(priority: .userInitiated) {
            MLXPrefixCrossSessionCache.contentIdentity(modelDirectory: modelDirectory)
        }.value
        guard modelDirectoryRevisionProvider(modelDirectory) == directoryRevision else {
            throw HostError.modelDirectoryChangedDuringActivation(modelDirectory)
        }
        let container = try await containerLoader(modelDirectory)
        guard modelDirectoryRevisionProvider(modelDirectory) == directoryRevision else {
            throw HostError.modelDirectoryChangedDuringActivation(modelDirectory)
        }
        let namespace = MLXPrefixCrossSessionCache.namespace(
            modelDirectory: modelDirectory, contentIdentity: contentIdentity)
        let store = PrefixSnapshotStore(
            root: MLXPrefixCrossSessionCache.hostRoot(
                base: base, namespace: namespace),
            pool: ExecutionStatePrefixPool(tokenBudget: 100_000_000))
        // Pool population from disk is the ACTIVATION duty of a host: the
        // in-memory pool starts empty even when durable artifacts exist, so
        // without this rescan a model switched back (or a restarted host)
        // would cold-miss every lookup. Rescan honors durable quarantine
        // tombstones, and a corrupt durable root fails the activation here
        // instead of silently missing later.
        _ = try store.rescan()
        let cache = MLXPrefixCrossSessionCache(
            store: store,
            namespace: namespace)
        // The ownership install is the last step that can fail; a failed
        // install throws before ownership transfers, so the hook is left
        // exactly as the caller arranged it. The admission guard binds the
        // hook to THIS generation: a session issued earlier can never adopt
        // this model's snapshots, closing the caller-identity gap inside the
        // hook itself.
        // A final check closes changes during store rescan. The installed
        // hook repeats this metadata comparison on each lookup, so a change
        // after this point becomes a cold miss instead of stale prefix reuse.
        guard modelDirectoryRevisionProvider(modelDirectory) == directoryRevision else {
            throw HostError.modelDirectoryChangedDuringActivation(modelDirectory)
        }
        let installedGeneration = currentGeneration()
        try cache.install(
            admissionGuard: admissionGuard(for: installedGeneration),
            allowedModelDirectory: modelDirectory,
            allowedModelDirectoryRevision: directoryRevision)
        return ActiveModel(
            directory: modelDirectory,
            contentIdentity: contentIdentity,
            container: container,
            cache: cache)
    }
}

// MARK: - GUI promotion acceptance probe (items 1, 2, 3, 4, 5)

public struct MLXSmallScaleHostAcceptanceReport: Codable, Hashable, Sendable {
    public struct SwitchLeg: Codable, Hashable, Sendable {
        public let switchTarget: String
        public let switchedAway: Bool
        public let switchedBack: Bool
        public let reAdoptedHitObserved: Bool
        public let reAdoptedMatchedTokenCount: Int?
        /// F4 caller-identity closure: a session issued BEFORE the switch
        /// must be rejected with `sessionStale` after it, never evaluated
        /// against the new model's snapshots.
        public let staleSessionRejected: Bool?
        /// F4 residual-risk observation: a RAW hook call (simulating a
        /// foreign pre-switch ChatSession that evaded the host wrapper)
        /// against the re-activated model's cache. Nil when not measured.
        public let foreignHookCold: Bool?
    }

    public let modelDirectory: String
    public let identityDigest: String
    public let promptTokenCount: Int
    public let prefixTokenCount: Int
    public let coldSeconds: Double
    public let warmSeconds: Double
    public let savingsSeconds: Double
    public let savingsRatio: Double
    public let baselineOutput: String
    public let warmOutput: String
    public let outputsMatch: Bool
    public let hookCalls: Int
    public let hookHits: Int
    public let matchedTokenCount: Int?
    public let crossSessionHitObserved: Bool
    public let boundaryRespected: Bool
    public let switchLeg: SwitchLeg?
    public let pass: Bool
}

extension MLXSmallScaleChatHost {
    /// One-shot acceptance probe for the small-scale host path, measuring
    /// CAPABILITY, not just mechanism: cold full-prefill wall time vs warm
    /// (cross-session adopted) wall time over the identical prompt and
    /// generation, output equality, hook hit at the artifact boundary, and
    /// — with `switchTarget` — a real model-switch round trip whose return
    /// must RE-ADOPT the durable snapshot.
    ///
    /// Mechanism evidence (`hookHits = 1`) alone does NOT pass; `pass`
    /// requires `savingsSeconds > 0` (the warm turn did measurably less
    /// work) on top of the hit and bit-equal outputs.
    public static func acceptanceProbe(
        modelDirectory: URL,
        base: URL,
        prompt: String,
        prefixTokenCount: Int,
        maxTokens: Int,
        switchTarget: URL? = nil
    ) async throws -> MLXSmallScaleHostAcceptanceReport {
        let clock = ContinuousClock()
        let host = MLXSmallScaleChatHost(base: base)
        _ = try await host.activate(modelDirectory: modelDirectory)
        // The probe's OWN model-A container: held across the switch leg so
        // a RAW foreign session (outside the host) can reach the real
        // evaluate consultation point while model B is active.
        let foreignContainer = try await MLXSmallScaleChatHost
            .defaultContainerLoader(modelDirectory)
        defer { host.deactivate() }
        guard let store = host.activeStore, let namespace = host.activeNamespace else {
            throw HostError.notActive
        }
        let contentIdentity = MLXPrefixCrossSessionCache.contentIdentity(
            modelDirectory: modelDirectory)

        let fullPromptTokenIDs = try await host.perform { context in
            try await ChatTemplateGeneration.promptTokenIDs(
                tokenizer: context.tokenizer,
                modelDirectory: modelDirectory,
                prompt: prompt)
        }
        guard fullPromptTokenIDs.count > 1 else {
            throw PrefixSnapshotStoreError.artifactUnreadable("rendered prompt is empty")
        }
        let boundary = min(max(prefixTokenCount, 1), fullPromptTokenIDs.count - 1)

        // WARM-UP (excluded from all timings): one tiny generation pages the
        // weights in and primes the eval path, so the cold measurement below
        // isolates prefix prefill rather than first-touch paging. The durable
        // store is still empty here, so the warm-up itself is a hook miss and
        // seeds nothing.
        let warmupSession = try host.makeSession(
            generateParameters: GenerateParameters(maxTokens: 2, temperature: 0))
        _ = try await warmupSession.respond(to: "ping")

        // COLD: hook consults the (still empty) durable store, misses, prefills
        // the whole prompt.
        let coldSession = try host.makeSession(
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0))
        let coldStart = clock.now
        let baselineOutput = try await coldSession.respond(to: prompt)
        let coldDuration = clock.now - coldStart

        // Durable export of the cold session's KV at the boundary.
        _ = try await store.export(
            namespace: namespace,
            tokens: Array(fullPromptTokenIDs.prefix(boundary))
        ) { url in
            try await coldSession.savePrefixSnapshot(to: url, upTo: boundary)
        }

        // WARM: fresh session adopts the artifact through the installed hook.
        let warmSession = try host.makeSession(
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0))
        let start = clock.now
        let warmOutput = try await warmSession.respond(to: prompt)
        let warmDuration = clock.now - start

        guard let observations = host.activeObservations else {
            throw HostError.notActive
        }

        var switchLeg: MLXSmallScaleHostAcceptanceReport.SwitchLeg?
        if let switchTarget {
            var switchedAway = false
            var switchedBack = false
            var reAdoptedHit = false
            var reAdoptedMatched: Int?
            var staleRejected: Bool?
            var foreignCold: Bool?
            do {
                // F4: issue a session UNDER the current generation before
                // any switch happens.
                let preSwitchSession = try host.makeSession(
                    generateParameters: GenerateParameters(
                        maxTokens: 4, temperature: 0))
                // FORK-HOOK-CALLER-IDENTITY-01: a RAW foreign session built
                // directly on model A's container — outside the host, the
                // exact caller the identity API must refuse. It reaches the
                // REAL evaluate consultation point (a direct static-hook
                // call is no longer sufficient evidence).
                let foreignSession = ChatSession(
                    foreignContainer,
                    generateParameters: GenerateParameters(
                        maxTokens: 2, temperature: 0))
                _ = try await host.switchModel(to: switchTarget)
                switchedAway = true
                guard let beforeForeign = host.activeObservations else {
                    throw HostError.notActive
                }
                // While model B is ACTUALLY active, the foreign model-A
                // session generates: its consultation carries A's origin,
                // which B's cache must refuse (recorded miss, cold path).
                let foreignOutput = try await foreignSession.respond(to: "ping")
                guard let afterForeign = host.activeObservations else {
                    throw HostError.notActive
                }
                foreignCold = afterForeign.calls == beforeForeign.calls + 1
                    && afterForeign.hits == beforeForeign.hits
                _ = foreignOutput
                _ = try await host.switchModel(to: modelDirectory)
                switchedBack = true
                // F4: the pre-switch session must now be REJECTED, not
                // evaluated (and thereby never adopt this model's cache).
                do {
                    _ = try await preSwitchSession.respond(to: "ping")
                    staleRejected = false
                } catch HostError.sessionStale {
                    staleRejected = true
                }
                // The switch-back installs a FRESH cache instance with its
                // own observation counters: compare its own before/after.
                guard let beforeReAdopt = host.activeObservations else {
                    throw HostError.notActive
                }
                let reAdopted = try host.makeSession(
                    generateParameters: GenerateParameters(
                        maxTokens: maxTokens, temperature: 0))
                _ = try await reAdopted.respond(to: prompt)
                guard let after = host.activeObservations else {
                    throw HostError.notActive
                }
                reAdoptedHit = after.hits > beforeReAdopt.hits
                    && after.lastMatchedTokenCount == boundary
                reAdoptedMatched = after.lastMatchedTokenCount
            } catch {
                // A failed switch leg is recorded, not fatal to the cold/warm
                // evidence above; pass will be false for the switch leg.
                switchedAway = false
            }
            switchLeg = MLXSmallScaleHostAcceptanceReport.SwitchLeg(
                switchTarget: switchTarget.path,
                switchedAway: switchedAway,
                switchedBack: switchedBack,
                reAdoptedHitObserved: reAdoptedHit,
                reAdoptedMatchedTokenCount: reAdoptedMatched,
                staleSessionRejected: staleRejected,
                foreignHookCold: foreignCold)
        }

        let coldSeconds = Double(coldDuration.components.seconds)
            + Double(coldDuration.components.attoseconds) / 1e18
        let warmSeconds = Double(warmDuration.components.seconds)
            + Double(warmDuration.components.attoseconds) / 1e18
        let savings = coldSeconds - warmSeconds
        let outputsMatch = baselineOutput == warmOutput
        let crossSessionHitObserved = observations.hits > 0
            && observations.lastMatchedTokenCount == boundary
        let boundaryRespected = (observations.lastMatchedTokenCount ?? 0) <= boundary
        let switchPass = switchLeg.map {
            $0.switchedAway && $0.switchedBack && $0.reAdoptedHitObserved
                && ($0.staleSessionRejected == true)
        }
        let pass = outputsMatch && crossSessionHitObserved && boundaryRespected
            && savings > 0 && (switchPass ?? true)

        return MLXSmallScaleHostAcceptanceReport(
            modelDirectory: modelDirectory.path,
            identityDigest: contentIdentity.combinedDigest,
            promptTokenCount: fullPromptTokenIDs.count,
            prefixTokenCount: boundary,
            coldSeconds: coldSeconds,
            warmSeconds: warmSeconds,
            savingsSeconds: savings,
            savingsRatio: coldSeconds > 0 ? savings / coldSeconds : 0,
            baselineOutput: baselineOutput,
            warmOutput: warmOutput,
            outputsMatch: outputsMatch,
            hookCalls: observations.calls,
            hookHits: observations.hits,
            matchedTokenCount: observations.lastMatchedTokenCount,
            crossSessionHitObserved: crossSessionHitObserved,
            boundaryRespected: boundaryRespected,
            switchLeg: switchLeg,
            pass: pass)
    }
}
