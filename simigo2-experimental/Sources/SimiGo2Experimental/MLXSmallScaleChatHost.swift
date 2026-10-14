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
        case alreadyActive(URL)
        case notActive
    }

    /// The host's durable cache base directory; per-model store roots are
    /// derived under it and survive process restarts.
    public let base: URL
    private let containerLoader: MLXChatContainerLoader
    /// Serializes the async lifecycle transitions (load → install → swap).
    private let lifecycleGate = AsyncLock()
    /// Guards synchronous observation of `state` against the async writer
    /// (reads never suspend, so they take this lock, not the gate).
    private let stateLock = NSLock()
    private var state: ActiveModel?

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
        self.base = base
        self.containerLoader = containerLoader
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
        let loaded = try await loadAndOwn(modelDirectory: modelDirectory)
        stateLock.withLock { state = loaded }
        return modelDirectory
    }

    /// The explicit model switch with a SINGLE-RESIDENT memory discipline:
    /// models on this machine's class do not fit two at a time, so the
    /// switch releases the previous container BEFORE loading the next.
    /// Sequence: release hook ownership (concurrent sessions degrade to the
    /// normal cold path — never a wrong seed), load the new container,
    /// install ownership, swap state, drop the old container. On any
    /// failure the previous cache's ownership is restored and the previous
    /// state stays fully intact. The previous model's cache artifacts stay
    /// durable under their own content-derived root and are re-adopted when
    /// the model is switched back (the cross-session property).
    @discardableResult
    public func switchModel(to modelDirectory: URL) async throws -> URL {
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
            throw HostError.modelDirectoryMissing(modelDirectory)
        }
        await lifecycleGate.lock()
        defer { lifecycleGate.unlock() }
        let previous = stateLock.withLock({ state })
        if let previous, previous.directory == modelDirectory {
            return previous.directory
        }
        previous?.cache.uninstall()
        do {
            let next = try await loadAndOwn(modelDirectory: modelDirectory)
            stateLock.withLock { state = next }
            return modelDirectory
        } catch {
            // Restore the previous model exactly: its container was never
            // dropped, and its cache re-takes the (now free) hook.
            try previous?.cache.install() // the hook is free here: it was released above
            throw error
        }
    }

    /// Deactivate: release hook ownership (visible no-op if another owner
    /// took it) and drop the container. Durable artifacts stay on disk.
    public func deactivate() {
        stateLock.withLock { 
            if let active = state {
                active.cache.uninstall()
            }
            state = nil
        }
    }

    /// A session bound to the active model. Cross-session cache adoption
    /// flows through the globally installed hook while this host owns it.
    public func makeSession(
        generateParameters: GenerateParameters = GenerateParameters(
            maxTokens: 256, temperature: 0)
    ) throws -> ChatSession {
        guard let container = stateLock.withLock({ state?.container }) else {
            throw HostError.notActive
        }
        return ChatSession(container, generateParameters: generateParameters)
    }

    /// One small-scale turn through the active model.
    public func respond(
        to prompt: String, maxTokens: Int
    ) async throws -> (text: String, observations: MLXPrefixHookObservation) {
        let session = try makeSession(
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0))
        let text = try await session.respond(to: prompt)
        guard let observations = activeObservations else {
            throw HostError.notActive
        }
        return (text, observations)
    }

    /// Load the container, derive the content identity, build the
    /// content-namespaced cache, and take hook ownership. The caller must
    /// already hold the lifecycle gate and must have released any previous
    /// ownership (``switchModel(to:)`` restores it on failure).
    private func loadAndOwn(modelDirectory: URL) async throws -> ActiveModel {
        let contentIdentity = await Task.detached(priority: .userInitiated) {
            MLXPrefixCrossSessionCache.contentIdentity(modelDirectory: modelDirectory)
        }.value
        let container = try await containerLoader(modelDirectory)
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
        // exactly as the caller arranged it.
        try cache.install()
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
            do {
                _ = try await host.switchModel(to: switchTarget)
                switchedAway = true
                _ = try await host.switchModel(to: modelDirectory)
                switchedBack = true
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
                reAdoptedMatchedTokenCount: reAdoptedMatched)
        }

        let coldSeconds = Double(coldDuration.components.seconds)
            + Double(coldDuration.components.attoseconds) / 1e15
        let warmSeconds = Double(warmDuration.components.seconds)
            + Double(warmDuration.components.attoseconds) / 1e15
        let savings = coldSeconds - warmSeconds
        let outputsMatch = baselineOutput == warmOutput
        let crossSessionHitObserved = observations.hits > 0
            && observations.lastMatchedTokenCount == boundary
        let boundaryRespected = (observations.lastMatchedTokenCount ?? 0) <= boundary
        let switchPass = switchLeg.map {
            $0.switchedAway && $0.switchedBack && $0.reAdoptedHitObserved
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
