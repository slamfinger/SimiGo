import Foundation
import CryptoKit
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

public struct MLXPrefixHookObservation: Sendable, Equatable {
    public private(set) var calls = 0
    public private(set) var hits = 0
    public private(set) var matchedTokenCounts: [Int] = []

    mutating func record(matchedTokenCount: Int?) {
        calls += 1
        if let matchedTokenCount {
            hits += 1
            matchedTokenCounts.append(matchedTokenCount)
        }
    }

    public var lastMatchedTokenCount: Int? { matchedTokenCounts.last }
}

/// Host-side B-6 wiring: connects the pool's verified token-chain admission to
/// `ChatSession.crossSessionPrefixLookup`. A physical-use lease covers the
/// synchronous artifact read; the returned snapshot is owned by ChatSession.
///
/// Hook ownership is a process-global singleton: exactly one cache may own
/// the hook at a time. Long-lived hosts install with `install()` (fail-closed
/// while another owner exists), switch models with
/// `install(forceTakeover: true)`, and tear down with `uninstall()` — a
/// foreign uninstall is a visible no-op, never a silent theft. All ownership
/// transitions synchronize on one lock together with the hook assignment, so
/// install/uninstall from different threads cannot leave the hook alive
/// without an owner (or owned without a hook).
public final class MLXPrefixCrossSessionCache: @unchecked Sendable {
    public enum OwnershipError: Error, Equatable, Sendable {
        case hookOwnedByOther
    }

    /// The KV fingerprint convention shared by the daily (ChatSession) path:
    /// the persistence probe, the host root layout, and any long-lived host
    /// that adopts the cache must agree on it. Content-derived namespaces
    /// (see ``namespace(modelID:contentIdentity:)``) extend it with the model
    /// content digest.
    public static let dailyKVFingerprint = "chat-cross-session-v1"

    public let store: PrefixSnapshotStore
    public let namespace: PrefixPoolNamespace
    private let loader: MLXPrefixSnapshotLoader
    private let observation = Observation()

    private static let ownershipLock = NSLock()
    private static var active: MLXPrefixCrossSessionCache?

    /// FCI-OWN-01 controlled-ownership probe: a caller-origin marker no
    /// real caller can produce. The installed hook recognizes it, bumps a
    /// dedicated probe counter, and returns nil WITHOUT touching normal
    /// observations — so uninstall can verify the context slot still
    /// routes to THIS cache without perturbing or impersonating traffic.
    private static let ownershipProbeMarker = URL(
        string: "simigo-ownership-probe://context-slot")!

    /// Probe hit counter for the currently installed hook (recreated on
    /// every install so stale hooks cannot answer for a newer one).
    private final class ProbeCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }
        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }
    private var probeCounter: ProbeCounter?

    /// The cache that currently owns the global `ChatSession` hook, if any.
    public static var activeInstance: MLXPrefixCrossSessionCache? {
        ownershipLock.lock()
        defer { ownershipLock.unlock() }
        return active
    }

    private var installed = false

    /// Whether this instance currently owns the global hook.
    public var isInstalled: Bool {
        type(of: self).ownershipLock.lock()
        defer { type(of: self).ownershipLock.unlock() }
        return installed
    }

    private final class Observation: @unchecked Sendable {
        private let lock = NSLock()
        private var value = MLXPrefixHookObservation()

        func record(matchedTokenCount: Int?) {
            lock.lock()
            defer { lock.unlock() }
            value.record(matchedTokenCount: matchedTokenCount)
        }

        var snapshot: MLXPrefixHookObservation {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    public init(store: PrefixSnapshotStore, namespace: PrefixPoolNamespace) {
        self.store = store
        self.loader = MLXPrefixSnapshotLoader(store: store)
        self.namespace = namespace
    }

    /// Model identity at the strength the engine path already uses:
    /// content digests of the weights and tokenizer files, NOT the directory
    /// name. Two directories with the same name but different model content
    /// produce different identities, so they can never share a cache
    /// namespace.
    public struct MLXModelContentIdentity: Sendable, Equatable {
        public let weightsDigest: String
        public let tokenizerDigest: String

        /// One combined digest over both components; this is what the
        /// namespace fingerprint carries.
        public var combinedDigest: String {
            var hasher = SHA256()
            hasher.update(data: Data("weights:\(weightsDigest)\n".utf8))
            hasher.update(data: Data("tokenizer:\(tokenizerDigest)".utf8))
            return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
        }
    }

    /// Compute the content identity of a model directory (streaming SHA-256
    /// over weights + tokenizer files; identical scheme to the engine path's
    /// `EngineModelIdentity`). A missing or unreadable directory yields the
    /// empty-content identity — deterministic, but hosts should validate the
    /// directory exists before activating.
    public static func contentIdentity(
        modelDirectory: URL
    ) -> MLXModelContentIdentity {
        let identity = EngineModelIdentity.compute(modelDirectory: modelDirectory)
        return MLXModelContentIdentity(
            weightsDigest: identity.weights,
            tokenizerDigest: identity.tokenizer)
    }

    /// Content-derived namespace: same model ID (directory name), but the
    /// fingerprint carries the combined content digest. Namespace equality —
    /// the pool's first admission filter — therefore requires EQUAL MODEL
    /// CONTENT, closing the same-name-different-model adoption hole that a
    /// directory-name namespace leaves open.
    public static func namespace(
        modelID: String, contentIdentity: MLXModelContentIdentity
    ) -> PrefixPoolNamespace {
        PrefixPoolNamespace(
            modelID: modelID,
            kvFingerprint: "\(dailyKVFingerprint)-\(contentIdentity.combinedDigest)")
    }

    public static func namespace(
        modelDirectory: URL, contentIdentity: MLXModelContentIdentity
    ) -> PrefixPoolNamespace {
        namespace(
            modelID: modelDirectory.lastPathComponent,
            contentIdentity: contentIdentity)
    }

    /// Canonical-profile namespace (F1 adjudication): the fingerprint
    /// carries the model content digest AND the canonical prefill profile.
    /// A profile change (version bump or stride change) therefore moves
    /// every artifact into a new namespace — old artifacts become
    /// unreachable rather than silently reused across execution-protocol
    /// changes.
    public static func namespace(
        modelID: String,
        contentIdentity: MLXModelContentIdentity,
        profile: CanonicalPrefillProfile
    ) -> PrefixPoolNamespace {
        PrefixPoolNamespace(
            modelID: modelID,
            kvFingerprint: "\(dailyKVFingerprint)-\(contentIdentity.combinedDigest)-\(profile.fingerprint)")
    }

    /// Long-lived host adoption path: durable per-model store root under a
    /// host-chosen base directory and a CONTENT-derived namespace. Snapshots
    /// survive host restarts — the property that makes the cache
    /// cross-session across process lifetimes. Computing the content
    /// identity reads (hashes) the model's weights files; activate on a
    /// background path.
    public convenience init(modelDirectory: URL, base: URL) {
        let contentIdentity = Self.contentIdentity(modelDirectory: modelDirectory)
        let namespace = Self.namespace(
            modelDirectory: modelDirectory, contentIdentity: contentIdentity)
        self.init(
            store: PrefixSnapshotStore(
                root: Self.hostRoot(base: base, namespace: namespace),
                pool: ExecutionStatePrefixPool(tokenBudget: 100_000_000)),
            namespace: namespace)
    }

    /// Durable per-model root convention: `<base>/<model>-<fingerprint>/`.
    /// Path-hostile characters are sanitized to `-`; namespace separation
    /// inside the pool remains exact regardless.
    public static func hostRoot(base: URL, namespace: PrefixPoolNamespace) -> URL {
        base.appendingPathComponent(
            "\(sanitized(namespace.modelID))-\(sanitized(namespace.kvFingerprint))",
            isDirectory: true)
    }

    private static func sanitized(_ value: String) -> String {
        String(value.map { character in
            character.isLetter || character.isNumber
                || character == "-" || character == "." || character == "_"
                ? character : "-"
        })
    }

    /// Install this cache as the owner of the global `ChatSession` hook.
    /// Idempotent for the already-installed instance; fails closed with
    /// `OwnershipError/hookOwnedByOther` while another live cache owns the
    /// hook unless `forceTakeover` marks the deliberate model-switch.
    ///
    /// `admissionGuard` closes the caller-identity gap (F4): the fork's hook
    /// signature carries only prompt tokens, so a session created under a
    /// PREVIOUS host generation could otherwise adopt this cache's snapshots
    /// after a model switch. The guard is evaluated inside the hook — a
    /// refused call records an observed miss and returns nil (cold path) —
    /// and it covers the window between any higher-level session check and
    /// the hook invocation itself.
    public func install(
        forceTakeover: Bool = false,
        admissionGuard: (@Sendable () -> Bool)? = nil,
        allowedModelDirectory: URL? = nil
    ) throws {
        try Self.ownershipLock.withLock {
            if Self.active === self {
                installed = true
                return
            }
            // FCI-OWN-01: refuse to overwrite a FOREIGN context-slot owner.
            // The internal registry alone is not authority: an external
            // installer that assigned the static directly leaves `active`
            // empty while the slot is occupied — a plain install must fail
            // closed, not clobber it. Only an explicit takeover may.
            if Self.active == nil,
                ChatSession.crossSessionPrefixLookupWithContext != nil,
                !forceTakeover
            {
                throw OwnershipError.hookOwnedByOther
            }
            if Self.active != nil && !forceTakeover {
                throw OwnershipError.hookOwnedByOther
            }
            Self.active = self
            installed = true
            // FORK-HOOK-CALLER-IDENTITY-01: the host owns the CONTEXT slot
            // (preferred by the fork's consultation point and carrying the
            // calling session's model origin). The legacy slot is left to
            // whoever owns it — release verification must check BOTH slots.
            let allowed = allowedModelDirectory?.standardizedFileURL
            let probe = ProbeCounter()
            probeCounter = probe
            ChatSession.crossSessionPrefixLookupWithContext = {
                [weak self] promptTokenIDs, caller in
                guard let self else { return nil }
                if caller.modelDirectory == Self.ownershipProbeMarker {
                    probe.increment()
                    return nil
                }
                if let admissionGuard, !admissionGuard() {
                    self.observation.record(matchedTokenCount: nil)
                    return nil
                }
                // Caller-identity refusal (fail closed, cold path): when a
                // directory binding exists, a nil origin (unresolved hub
                // id) or a foreign directory never adopts this cache's
                // snapshots. An unbound install stays identity-agnostic
                // (legacy behavior for non-host callers).
                if let allowed {
                    guard let origin = caller.modelDirectory?.standardizedFileURL,
                        origin == allowed
                    else {
                        self.observation.record(matchedTokenCount: nil)
                        return nil
                    }
                }
                return self.lookup(promptTokenIDs)
            }
        }
    }

    /// Remove this cache's ownership of the global hook. Returns true when
    /// this instance owned and cleared the hook; false when another owner or
    /// nobody holds it.
    @discardableResult
    public func uninstall() -> Bool {
        Self.ownershipLock.withLock {
            installed = false
            guard Self.active === self else { return false }
            Self.active = nil
            // FCI-OWN-01: clear the context slot ONLY when it verifiably
            // still routes to THIS cache (probe marker, inert to real
            // traffic). If an external party replaced the slot while we
            // were active, the replacement belongs to THEM: leave it
            // installed, report the inconsistency, return false.
            if let probe = probeCounter {
                let before = probe.value
                _ = ChatSession.crossSessionPrefixLookupWithContext?(
                    [0],
                    ChatSession.CrossSessionCallerContext(
                        modelDirectory: Self.ownershipProbeMarker))
                guard probe.value == before + 1 else {
                    ownershipInconsistencyDetected = true
                    return false
                }
            }
            ChatSession.crossSessionPrefixLookupWithContext = nil
            probeCounter = nil
            return true
        }
    }

    /// FCI-OWN-01: an uninstall detected that the context slot no longer
    /// routes to this cache — an external party replaced it while this
    /// cache was active. The replacement was preserved (not cleared);
    /// hosts surface this instead of treating release as complete.
    public private(set) var ownershipInconsistencyDetected: Bool = false

    /// Complete hook release from THIS cache's perspective: true when this
    /// cache no longer owns the context slot and no context hook remains.
    /// GUI teardown verification must additionally check the legacy slot —
    /// a nil legacy slot alone is NOT complete release.
    public var ownsNoHookSlot: Bool {
        Self.ownershipLock.withLock {
            Self.active !== self
                && ChatSession.crossSessionPrefixLookupWithContext == nil
        }
    }

    func lookup(
        _ promptTokenIDs: [Int]
    ) -> (cache: PromptCacheSnapshot, matchedTokenCount: Int)? {
        let admission = store.pool.admit(
            namespace: namespace, promptTokens: promptTokenIDs)
        guard let admission, admission.coveredTokens > 0,
            admission.coveredTokens < promptTokenIDs.count
        else {
            observation.record(matchedTokenCount: nil)
            return nil
        }
        do {
            let snapshot = try loader.loadSync(admission)
            observation.record(matchedTokenCount: admission.coveredTokens)
            return (cache: snapshot, matchedTokenCount: admission.coveredTokens)
        } catch {
            observation.record(matchedTokenCount: nil)
            return nil
        }
    }

    public var observations: MLXPrefixHookObservation {
        observation.snapshot
    }
}

public struct MLXPrefixCacheRuntimeProbeReport: Codable, Hashable, Sendable {
    public let promptTokenCount: Int
    public let prefixTokenCount: Int
    public let baselineOutput: String
    public let warmOutput: String
    public let hookCalls: Int
    public let hookHits: Int
    public let matchedTokenCount: Int?
    public let outputsMatch: Bool
    public let crossSessionHitObserved: Bool
    public let pass: Bool
}

extension MLXPrefixCrossSessionCache {
    /// Real-model acceptance probe: source session renders and generates the
    /// full prompt, exports a strict prefix of its rendered token IDs, then a
    /// fresh ChatSession consumes that artifact through the installed host hook.
    public static func persistenceProbe(
        modelDirectory: URL,
        root: URL,
        prompt: String,
        prefixTokenCount: Int,
        maxTokens: Int
    ) async throws -> MLXPrefixCacheRuntimeProbeReport {
        let container = try await MLXLLM.LLMModelFactory.shared.loadContainer(
            from: modelDirectory,
            using: #huggingFaceTokenizerLoader())
        let fullPromptTokenIDs = try await container.perform { context in
            try await ChatTemplateGeneration.promptTokenIDs(
                tokenizer: context.tokenizer,
                modelDirectory: modelDirectory,
                prompt: prompt)
        }
        guard fullPromptTokenIDs.count > 1 else {
            throw PrefixSnapshotStoreError.artifactUnreadable("rendered prompt is empty")
        }
        let boundary = min(max(prefixTokenCount, 1), fullPromptTokenIDs.count - 1)
        let namespace = PrefixPoolNamespace(
            modelID: modelDirectory.lastPathComponent,
            kvFingerprint: Self.dailyKVFingerprint)
        let pool = ExecutionStatePrefixPool(tokenBudget: 100_000_000)
        let store = PrefixSnapshotStore(root: root, pool: pool)

        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0)
        let source = ChatSession(container, generateParameters: parameters)
        let baselineOutput = try await source.respond(to: prompt)
        let sourceArtifact = try await store.export(
            namespace: namespace,
            tokens: Array(fullPromptTokenIDs.prefix(boundary))
        ) { url in
            try await source.savePrefixSnapshot(to: url, upTo: boundary)
        }
        let sourceArtifactGeneration = (sourceArtifact.artifact as? DiskPrefixArtifact)?.generation

        let runtime = MLXPrefixCrossSessionCache(store: store, namespace: namespace)
        try runtime.install()
        defer { runtime.uninstall() }

        let warm = ChatSession(container, generateParameters: parameters)
        let warmOutput = try await warm.respond(to: prompt)
        let observations = runtime.observations

        let report = MLXPrefixCacheRuntimeProbeReport(
            promptTokenCount: fullPromptTokenIDs.count,
            prefixTokenCount: boundary,
            baselineOutput: baselineOutput,
            warmOutput: warmOutput,
            hookCalls: observations.calls,
            hookHits: observations.hits,
            matchedTokenCount: observations.lastMatchedTokenCount,
            outputsMatch: baselineOutput == warmOutput,
            crossSessionHitObserved: observations.hits > 0
                && observations.lastMatchedTokenCount == boundary,
            pass: baselineOutput == warmOutput
                && observations.hits > 0
                && observations.lastMatchedTokenCount == boundary
                && sourceArtifactGeneration != nil)
        return report
    }
}
