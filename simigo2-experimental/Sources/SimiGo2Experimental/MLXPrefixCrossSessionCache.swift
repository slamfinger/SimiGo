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
public final class MLXPrefixCrossSessionCache: @unchecked Sendable {
    public let store: PrefixSnapshotStore
    private let loader: MLXPrefixSnapshotLoader
    private let namespace: PrefixPoolNamespace
    private let observation = Observation()

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

    private static var active: MLXPrefixCrossSessionCache?

    public init(store: PrefixSnapshotStore, namespace: PrefixPoolNamespace) {
        self.store = store
        self.loader = MLXPrefixSnapshotLoader(store: store)
        self.namespace = namespace
    }

    public func install() {
        Self.active = self
        ChatSession.crossSessionPrefixLookup = { [weak self] promptTokenIDs in
            guard let self else { return nil }
            let admission = self.store.pool.admit(
                namespace: self.namespace, promptTokens: promptTokenIDs)
            guard let admission, admission.coveredTokens > 0,
                admission.coveredTokens < promptTokenIDs.count
            else {
                self.observation.record(matchedTokenCount: nil)
                return nil
            }
            do {
                let snapshot = try self.loader.loadSync(admission)
                self.observation.record(matchedTokenCount: admission.coveredTokens)
                return (snapshot, admission.coveredTokens)
            } catch {
                self.observation.record(matchedTokenCount: nil)
                return nil
            }
        }
    }

    public func uninstall() {
        guard Self.active === self else { return }
        ChatSession.crossSessionPrefixLookup = nil
        Self.active = nil
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
            kvFingerprint: "chat-cross-session-v1")
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
        runtime.install()
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
