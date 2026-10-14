import Foundation
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// F1 canonical-prefill acceptance (adjudicated 2026-10-15): under ONE
/// canonical profile (remainder chunking at a fixed stride; boundaries only
/// at stride multiples), the warm adoption path must produce EXACTLY the
/// same generation as the cold path — same chunk-by-chunk stream, same
/// completion token counts, same text. No semantic-equivalence relaxation.
///
/// Strictness note (fork API gap, registered): ChatSession does not expose
/// generated token IDs; the chunk sequence plus `GenerateCompletionInfo`
/// token counts are the finest publicly observable generation record. Equal
/// chunk sequences + equal token counts under the same emission machinery is
/// the strongest strict comparison the public API affords; a token-ID-level
/// API remains a registered fork-side need (alongside the F4 session
/// identity).
public enum CanonicalPrefillAcceptance {

    public struct StrictRecord: Codable, Hashable, Sendable {
        public let chunkSequence: [String]
        public let tokenCount: Int?
        public let text: String
    }

    public struct CaseReport: Codable, Hashable, Sendable {
        public let stride: Int
        public let boundary: Int
        public let promptTokenCount: Int
        public let boundaryIsStable: Bool
        public let hookCalls: Int
        public let hookHits: Int
        public let matchedTokenCount: Int?
        public let cold: StrictRecord
        public let warm: StrictRecord
        public let chunkSequencesEqual: Bool
        public let tokenCountsEqual: Bool
        public let textsEqual: Bool
        public let strictPass: Bool
    }

    public struct Report: Codable, Hashable, Sendable {
        public let modelDirectory: String
        public let profileVersion: String
        public let cases: [CaseReport]
        public let allStrictPass: Bool
        public let note: String
    }

    @discardableResult
    public static func run(
        modelDirectory: URL,
        base: URL,
        prompt: String,
        strides: [Int],
        boundaries: [Int],
        maxTokens: Int
    ) async throws -> Report {
        let profileStrideList = strides.isEmpty ? [256] : strides
        let container = try await MLXLLM.LLMModelFactory.shared.loadContainer(
            from: modelDirectory, using: #huggingFaceTokenizerLoader())
        let promptTokenIDs = try await container.perform { context in
            try await ChatTemplateGeneration.promptTokenIDs(
                tokenizer: context.tokenizer,
                modelDirectory: modelDirectory,
                prompt: prompt)
        }

        var cases: [CaseReport] = []
        for stride in profileStrideList {
            let profile = CanonicalPrefillProfile(stride: stride)
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

            for requestedBoundary in boundaries {
                let boundary = profile.stableBoundary(atOrBelow: requestedBoundary)
                guard boundary >= 1, boundary < promptTokenIDs.count else { continue }

                func canonicalParameters() -> GenerateParameters {
                    var parameters = GenerateParameters(
                        maxTokens: maxTokens, temperature: 0)
                    parameters.prefill.chunking = .remainder
                    parameters.prefill.stepSize = stride
                    return parameters
                }

                // COLD: canonical remainder chunking over the full prompt.
                let cold = ChatSession(
                    container, generateParameters: canonicalParameters())
                let coldRecord = try await strictRecord(session: cold, prompt: prompt)

                // Durable artifact at the stable boundary from the SAME cold
                // session (the artifact therefore carries exactly the
                // canonical plan's KV for those rows).
                _ = try await store.export(
                    namespace: namespace,
                    tokens: Array(promptTokenIDs.prefix(boundary))
                ) { url in
                    try await cold.savePrefixSnapshot(to: url, upTo: boundary)
                }

                // WARM: fresh session, SAME canonical parameters; adoption
                // flows through the installed hook.
                let runtime = MLXPrefixCrossSessionCache(
                    store: store, namespace: namespace)
                try runtime.install()
                defer { runtime.uninstall() }
                let warm = ChatSession(
                    container, generateParameters: canonicalParameters())
                let warmRecord = try await strictRecord(session: warm, prompt: prompt)
                let observations = runtime.observations

                let chunksEqual = coldRecord.chunkSequence == warmRecord.chunkSequence
                let countsEqual = coldRecord.tokenCount == warmRecord.tokenCount
                let textsEqual = coldRecord.text == warmRecord.text
                let hitAtBoundary = observations.hits > 0
                    && observations.lastMatchedTokenCount == boundary
                cases.append(CaseReport(
                    stride: stride,
                    boundary: boundary,
                    promptTokenCount: promptTokenIDs.count,
                    boundaryIsStable: profile.isStableBoundary(boundary),
                    hookCalls: observations.calls,
                    hookHits: observations.hits,
                    matchedTokenCount: observations.lastMatchedTokenCount,
                    cold: coldRecord,
                    warm: warmRecord,
                    chunkSequencesEqual: chunksEqual,
                    tokenCountsEqual: countsEqual,
                    textsEqual: textsEqual,
                    strictPass: chunksEqual && countsEqual && textsEqual
                        && hitAtBoundary))
            }
        }

        return Report(
            modelDirectory: modelDirectory.path,
            profileVersion: "canonical-remainder-v1",
            cases: cases,
            allStrictPass: cases.allSatisfy(\.strictPass),
            note: "Strict cold==warm equality under one canonical remainder-stride profile; artifacts namespace-bound to (content identity, profile). Token IDs are not exposed by ChatSession — chunk sequence + completion token counts are the finest public strictness. Diagnostic/acceptance harness; no inference behavior modified.")
    }

    private static func strictRecord(
        session: ChatSession, prompt: String
    ) async throws -> StrictRecord {
        var chunks: [String] = []
        var tokenCount: Int?
        for try await generation in session.streamDetails(to: prompt) {
            if let chunk = generation.chunk {
                chunks.append(chunk)
            }
            if let info = generation.info {
                tokenCount = info.generationTokenCount
            }
        }
        return StrictRecord(
            chunkSequence: chunks,
            tokenCount: tokenCount,
            text: chunks.joined())
    }
}
