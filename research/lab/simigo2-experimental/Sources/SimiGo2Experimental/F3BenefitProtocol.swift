import Foundation
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// F3 benefit protocol (adjudicated ordering 2026-10-15): prove ACTUAL
/// prefill savings under controlled, repeatable conditions — not hook hits,
/// and not bare min-of-N wall time.
///
/// Controls:
/// - ONE model load for the whole run (fixed residency); a warm-up leg
///   pages the weights in before any timed region.
/// - Every timed leg runs the CANONICAL profile (the shape whose strict
///   cold==warm equality already passed), so the measurement describes the
///   accepted execution protocol.
/// - Cold legs never adopt (the hook is uninstalled); warm legs adopt the
///   one durable artifact seeded before pairing.
/// - Swap is sampled before/after each phase; a growing swap footprint
///   flags uncontrolled conditions in the report (pass requires it stable).
///
/// Metrics: per-leg `GenerateCompletionInfo.promptTime` (the prefill
/// metric — what adoption actually saves) plus wall time; the report
/// carries full distributions and per-pair savings.
public enum F3BenefitProtocol {

    public struct Leg: Codable, Hashable, Sendable {
        public let kind: String
        /// Fork-reported prompt metric. MEASUREMENT CAVEAT (first controlled
        /// run, 20261015): this is asyncEval graph-SUBMISSION time, not
        /// prefill compute wall time — it under-reports and must not be
        /// used as the benefit verdict on its own.
        public let promptSubmissionSeconds: Double
        public let wallSeconds: Double
        public let generationTokenCount: Int
        /// Attribution instrumentation (20261015 unit): where does the warm
        /// leg's time actually go?
        public let firstChunkLatencySeconds: Double
        public let lastChunkAtSeconds: Double
        public let chunkCount: Int
        public let hookCalls: Int
        public let hookHits: Int
        public let matchedTokenCount: Int?
    }

    public struct Pair: Codable, Hashable, Sendable {
        public let index: Int
        public let cold: Leg
        public let warm: Leg
        public let promptSubmissionSavings: Double
        public let wallSavings: Double
    }

    public struct Distribution: Codable, Hashable, Sendable {
        public let values: [Double]
        public let mean: Double
        public let median: Double
        public let minimum: Double
        public let maximum: Double
    }

    public struct Report: Codable, Hashable, Sendable {
        public let modelDirectory: String
        public let profileVersion: String
        public let stride: Int
        public let boundary: Int
        public let promptTokenCount: Int
        public let pairs: [Pair]
        public let coldPromptTime: Distribution
        public let warmPromptTime: Distribution
        public let coldWall: Distribution
        public let warmWall: Distribution
        public let swapAtStart: Int
        public let swapAtEnd: Int
        public let swapStable: Bool
        public let allPairsSavePromptTime: Bool
        public let pass: Bool
        public let note: String

        static func summarize(_ values: [Double]) -> Distribution {
            let sorted = values.sorted()
            return Distribution(
                values: values,
                mean: values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count),
                median: sorted.isEmpty ? 0
                    : sorted.count % 2 == 1
                        ? sorted[sorted.count / 2]
                        : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2,
                minimum: sorted.first ?? 0,
                maximum: sorted.last ?? 0)
        }
    }

    @discardableResult
    public static func run(
        modelDirectory: URL,
        base: URL,
        prompt: String,
        stride: Int,
        boundary: Int,
        maxTokens: Int,
        pairs: Int
    ) async throws -> Report {
        let profile = CanonicalPrefillProfile(stride: stride)
        let clock = ContinuousClock()
        let container = try await MLXLLM.LLMModelFactory.shared.loadContainer(
            from: modelDirectory, using: #huggingFaceTokenizerLoader())
        let promptTokenIDs = try await container.perform { context in
            try await ChatTemplateGeneration.promptTokenIDs(
                tokenizer: context.tokenizer,
                modelDirectory: modelDirectory,
                prompt: prompt)
        }
        let stableBoundary = profile.stableBoundary(atOrBelow: boundary)
        guard stableBoundary >= 1, stableBoundary < promptTokenIDs.count else {
            throw PrefixSnapshotStoreError.artifactUnreadable("boundary out of range")
        }

        let namespace = MLXPrefixCrossSessionCache.namespace(
            modelID: modelDirectory.lastPathComponent,
            contentIdentity: MLXPrefixCrossSessionCache.contentIdentity(
                modelDirectory: modelDirectory),
            profile: profile)
        let store = PrefixSnapshotStore(
            root: MLXPrefixCrossSessionCache.hostRoot(
                base: base, namespace: namespace),
            pool: ExecutionStatePrefixPool(tokenBudget: 100_000_000))
        _ = try store.rescan()
        let runtime = MLXPrefixCrossSessionCache(store: store, namespace: namespace)

        func canonicalParameters() -> GenerateParameters {
            var parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0)
            parameters.prefill.chunking = .remainder
            parameters.prefill.stepSize = stride
            return parameters
        }

        @Sendable func timedLeg(
            _ kind: String, adopt: Bool
        ) async throws -> Leg {
            if adopt {
                try runtime.install()
            } else {
                runtime.uninstall()
            }
            let observationsBefore = runtime.observations
            let session = ChatSession(
                container, generateParameters: canonicalParameters())
            let start = clock.now
            var promptTime: Double?
            var tokenCount: Int?
            var firstChunk: Double?
            var lastChunk: Double?
            var chunks = 0
            for try await generation in session.streamDetails(to: prompt) {
                if generation.chunk != nil {
                    chunks += 1
                    let elapsed = seconds(clock.now - start)
                    if firstChunk == nil { firstChunk = elapsed }
                    lastChunk = elapsed
                }
                if let info = generation.info {
                    promptTime = info.promptTime
                    tokenCount = info.generationTokenCount
                }
            }
            let wall = clock.now - start
            let observationsAfter = runtime.observations
            Memory.clearCache()
            return Leg(
                kind: kind,
                promptSubmissionSeconds: promptTime ?? 0,
                wallSeconds: seconds(wall),
                generationTokenCount: tokenCount ?? 0,
                firstChunkLatencySeconds: firstChunk ?? 0,
                lastChunkAtSeconds: lastChunk ?? 0,
                chunkCount: chunks,
                hookCalls: observationsAfter.calls - observationsBefore.calls,
                hookHits: observationsAfter.hits - observationsBefore.hits,
                matchedTokenCount: observationsAfter.lastMatchedTokenCount)
        }

        func seconds(_ d: Duration) -> Double {
            Double(d.components.seconds)
                + Double(d.components.attoseconds) / 1e18
        }

        // Phase 0 (untimed): page weights in and seed the durable artifact.
        _ = try await timedLeg("warmup", adopt: false)
        _ = try await timedLeg("seed", adopt: false)
        // The seed leg's session is gone; re-export the artifact through a
        // dedicated session so the artifact is present before pairing.
        let seeding = ChatSession(
            container, generateParameters: canonicalParameters())
        _ = try await seeding.respond(to: prompt)
        _ = try await store.export(
            namespace: namespace,
            tokens: Array(promptTokenIDs.prefix(stableBoundary))
        ) { url in
            try await seeding.savePrefixSnapshot(to: url, upTo: stableBoundary)
        }

        let swapAtStart = globalSwapUsedBytes()
        var pairReports: [Pair] = []
        for index in 0..<max(pairs, 1) {
            let cold = try await timedLeg("cold", adopt: false)
            let warm = try await timedLeg("warm", adopt: true)
            pairReports.append(Pair(
                index: index,
                cold: cold,
                warm: warm,
                promptSubmissionSavings: cold.promptSubmissionSeconds - warm.promptSubmissionSeconds,
                wallSavings: cold.wallSeconds - warm.wallSeconds))
        }
        let swapAtEnd = globalSwapUsedBytes()
        runtime.uninstall()

        let coldPrompt = Report.summarize(pairReports.map(\.cold.promptSubmissionSeconds))
        let warmPrompt = Report.summarize(pairReports.map(\.warm.promptSubmissionSeconds))
        let coldWall = Report.summarize(pairReports.map(\.cold.wallSeconds))
        let warmWall = Report.summarize(pairReports.map(\.warm.wallSeconds))
        let allSave = pairReports.allSatisfy { $0.promptSubmissionSavings > 0 }
        // Conditions are controlled only if swap did not grow materially
        // (> 256 MiB) across the timed region.
        let swapStable = (swapAtEnd - swapAtStart) < 256 * 1024 * 1024

        return Report(
            modelDirectory: modelDirectory.path,
            profileVersion: profile.version,
            stride: stride,
            boundary: stableBoundary,
            promptTokenCount: promptTokenIDs.count,
            pairs: pairReports,
            coldPromptTime: coldPrompt,
            warmPromptTime: warmPrompt,
            coldWall: coldWall,
            warmWall: warmWall,
            swapAtStart: swapAtStart,
            swapAtEnd: swapAtEnd,
            swapStable: swapStable,
            allPairsSavePromptTime: allSave,
            pass: allSave && swapStable && warmPrompt.median < coldPrompt.median
                && warmWall.median < coldWall.median,
            note: "Paired canonical cold vs adopted-warm legs under one model load. PASS requires WALL-time savings (the capability verdict), submission-time savings, and stable swap. The first controlled run showed warm consistently SLOWER than cold at wall level — benefit not established; submission time alone must never decide the verdict.")
    }

    /// Swap used bytes via the sysctl text format (see
    /// CrossBackendTokenProbe.globalSwapUsedBytes).
    private static func globalSwapUsedBytes() -> Int {
        Int(CrossBackendTokenProbe.globalSwapUsedBytes())
    }
}
