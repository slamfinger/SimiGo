import Foundation
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
    /// that adopts the cache must agree on it.
    public static let dailyKVFingerprint = "chat-cross-session-v1"

    public let store: PrefixSnapshotStore
    private let loader: MLXPrefixSnapshotLoader
    private let namespace: PrefixPoolNamespace
    private let observation = Observation()

    private static let ownershipLock = NSLock()
    private static var active: MLXPrefixCrossSessionCache?

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

    /// Long-lived host adoption path: durable per-model store root under a
    /// host-chosen base directory and the daily KV fingerprint convention.
    /// Snapshots survive host restarts — the property that makes the cache
    /// cross-session across process lifetimes, not just session lifetimes.
    public convenience init(modelDirectory: URL, base: URL) {
        let namespace = PrefixPoolNamespace(
            modelID: modelDirectory.lastPathComponent,
            kvFingerprint: Self.dailyKVFingerprint)
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
    public func install(forceTakeover: Bool = false) throws {
        try Self.ownershipLock.withLock {
            if Self.active === self {
                installed = true
                return
            }
            if Self.active != nil && !forceTakeover {
                throw OwnershipError.hookOwnedByOther
            }
            Self.active = self
            installed = true
            ChatSession.crossSessionPrefixLookup = { [weak self] promptTokenIDs in
                self?.lookup(promptTokenIDs)
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
            ChatSession.crossSessionPrefixLookup = nil
            Self.active = nil
            return true
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
