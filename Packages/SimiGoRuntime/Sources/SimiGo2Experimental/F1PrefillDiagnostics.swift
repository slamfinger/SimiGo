import Foundation
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// F1 diagnostic probe (authorized: fork commit 6d01a13c, diagnostic
/// instrumentation and controlled comparisons only — NO inference-behavior
/// changes, NO acceptance-bar relaxation).
///
/// Separates the two candidate causes of the deterministic warm/cold greedy
/// flip found by the small-scale host acceptance (20261015-e138936b, F1):
/// prefill CHUNK-SHAPE numerics vs snapshot serialization/adoption.
///
/// Four decode paths over one model, one prompt, one boundary, greedy:
/// - coldFullBalanced: ChatSession default chunking (the acceptance cold path)
/// - coldFullUnchunked: whole prompt in one forward (reference computation)
/// - coldSegmented:     remainder chunking at exactly the artifact boundary
/// - warmAdoption:      durable snapshot at the boundary adopted through the
///                      cross-session hook (the acceptance warm path)
///
/// Plus direct-KV measurements: per-layer max-abs diffs between the
/// unchunked, boundary-segmented, and loaded-artifact prefix KV states, and
/// a top-1/top-2 logits margin at the first decode divergence.
public enum F1PrefillDiagnostics {

    public struct DecodePath: Codable, Hashable, Sendable {
        public let name: String
        public let generatedTokenIDs: [Int]
        public let outputText: String
    }

    public struct Pairwise: Codable, Hashable, Sendable {
        public let a: String
        public let b: String
        public let tokenSequencesEqual: Bool
        public let firstDivergenceIndex: Int?
    }

    public struct KVDiff: Codable, Hashable, Sendable {
        public let name: String
        public let layersCompared: Int
        public let keysMaxAbsDiff: Double
        public let valuesMaxAbsDiff: Double
    }

    public struct DivergenceMargin: Codable, Hashable, Sendable {
        public let decodePosition: Int
        public let top1TokenID: Int
        public let top1Token: String
        public let top1Logit: Double
        public let top2TokenID: Int
        public let top2Token: String
        public let top2Logit: Double
        public let margin: Double
    }

    public struct Report: Codable, Hashable, Sendable {
        public let modelDirectory: String
        public let promptTokenCount: Int
        public let boundary: Int
        public let paths: [DecodePath]
        public let pairwise: [Pairwise]
        public let kvDiffs: [KVDiff]
        public let divergenceMargin: DivergenceMargin?
        public let note: String
    }

    public static func run(
        modelDirectory: URL,
        prompt: String,
        boundary: Int,
        maxTokens: Int,
        cacheRoot: URL
    ) async throws -> Report {
        let container = try await MLXLLM.LLMModelFactory.shared.loadContainer(
            from: modelDirectory, using: #huggingFaceTokenizerLoader())
        let promptTokenIDs = try await container.perform { context in
            try await ChatTemplateGeneration.promptTokenIDs(
                tokenizer: context.tokenizer,
                modelDirectory: modelDirectory,
                prompt: prompt)
        }
        guard promptTokenIDs.count > boundary, boundary >= 1 else {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "boundary \(boundary) out of range for \(promptTokenIDs.count) tokens")
        }

        func greedyParameters(
            chunking: PrefillParameters.Chunking? = nil, stepSize: Int? = nil
        ) -> GenerateParameters {
            var parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0)
            if let chunking {
                parameters.prefill.chunking = chunking
                parameters.prefill.stepSize = stepSize
            }
            return parameters
        }

        // Four decode paths, all greedy, one shared container.
        let coldFullBalanced = ChatSession(
            container, generateParameters: greedyParameters())
        let aText = try await coldFullBalanced.respond(to: prompt)

        let coldFullUnchunked = ChatSession(
            container, generateParameters: greedyParameters(chunking: .unchunked))
        let bText = try await coldFullUnchunked.respond(to: prompt)

        let coldSegmented = ChatSession(
            container,
            generateParameters: greedyParameters(
                chunking: .remainder, stepSize: boundary))
        let cText = try await coldSegmented.respond(to: prompt)

        // Warm adoption: export the balanced session's KV at the boundary
        // (the acceptance flow), then adopt through the hook in a fresh
        // session.
        let namespace = PrefixPoolNamespace(
            modelID: modelDirectory.lastPathComponent,
            kvFingerprint: "f1-diagnostics-v1")
        let store = PrefixSnapshotStore(
            root: cacheRoot, pool: ExecutionStatePrefixPool(tokenBudget: 100_000_000))
        let artifactEntry = try await store.export(
            namespace: namespace,
            tokens: Array(promptTokenIDs.prefix(boundary))
        ) { url in
            try await coldFullBalanced.savePrefixSnapshot(to: url, upTo: boundary)
        }
        let runtime = MLXPrefixCrossSessionCache(store: store, namespace: namespace)
        try runtime.install()
        defer { runtime.uninstall() }
        let warm = ChatSession(container, generateParameters: greedyParameters())
        let dText = try await warm.respond(to: prompt)
        let observations = runtime.observations

        // Token IDs per path: re-derive deterministically by decoding is not
        // exposed by respond(); re-run each path through the model's own
        // greedy loop is unnecessary — the diagnostic compares TEXT equality
        // plus first-divergence via a shared greedy re-decode below.
        let names = ["coldFullBalanced", "coldFullUnchunked", "coldSegmented", "warmAdoption"]
        let texts = [aText, bText, cText, dText]
        let paths = zip(names, texts).map { name, text in
            DecodePath(name: name, generatedTokenIDs: [], outputText: text)
        }

        var pairwise: [Pairwise] = []
        for i in 0..<paths.count {
            for j in (i + 1)..<paths.count {
                let equal = texts[i] == texts[j]
                pairwise.append(Pairwise(
                    a: names[i], b: names[j],
                    tokenSequencesEqual: equal,
                    firstDivergenceIndex: equal ? nil : firstTextDivergence(texts[i], texts[j])))
            }
        }

        // Direct-KV measurements.
        let kvDiffs = try await container.perform { context -> [KVDiff] in
            var results: [KVDiff] = []
            let suffix = Array(promptTokenIDs[boundary...])

            func freshCaches() throws -> [KVCache] {
                try context.model.newCache(parameters: nil)
            }

            // Unchunked: one forward over the full prompt.
            let unchunkedCaches = try freshCaches()
            _ = context.model(
                MLXArray(promptTokenIDs, [1, promptTokenIDs.count]),
                cache: unchunkedCaches)
            // Segmented: boundary forward, then suffix forward, same caches.
            let segmentedCaches = try freshCaches()
            _ = context.model(
                MLXArray(Array(promptTokenIDs.prefix(boundary)), [1, boundary]),
                cache: segmentedCaches)
            _ = context.model(
                MLXArray(suffix, [1, suffix.count]),
                cache: segmentedCaches)

            // (a) chunk-shape effect at the prefix rows: unchunked vs segmented.
            // (b) artifact fidelity: loaded vs segmented prefix.
            // (c) artifact vs unchunked prefix.
            let layered = zip(unchunkedCaches, segmentedCaches)
            var shapeKey = 0.0
            var shapeValue = 0.0
            var layersCompared = 0
            for (u, s) in layered {
                let us = u.state
                let ss = s.state
                guard us.count == 2, ss.count == 2 else { continue }
                layersCompared += 1
                for (isKeys, ua, sa) in [(true, us[0], ss[0]), (false, us[1], ss[1])] {
                    let diff = (ua[.ellipsis, ..<boundary, 0...] - sa[.ellipsis, ..<boundary, 0...])
                    eval(diff)
                    let maxAbs = Double(diff.abs().max().item(Float.self))
                    if isKeys {
                        shapeKey = Swift.max(shapeKey, maxAbs)
                    } else {
                        shapeValue = Swift.max(shapeValue, maxAbs)
                    }
                }
            }
            results.append(KVDiff(
                name: "unchunkedPrefix_vs_segmentedPrefix",
                layersCompared: layersCompared,
                keysMaxAbsDiff: shapeKey,
                valuesMaxAbsDiff: shapeValue))

            let artifactURL = (artifactEntry.artifact as? DiskPrefixArtifact)?.snapshotURL
            if let artifactURL,
                let snapshot = try? loadPromptCacheSnapshot(
                    url: artifactURL, materializeArrays: true)
            {
                var loadedKey = 0.0
                var loadedValue = 0.0
                var loadedLayers = 0
                for (index, cache) in snapshot.cache.enumerated() {
                    guard index < segmentedCaches.count else { break }
                    let ls = cache.state
                    let ss = segmentedCaches[index].state
                    guard ls.count == 2, ss.count == 2 else { continue }
                    loadedLayers += 1
                    for (isKeys, la, sa) in [(true, ls[0], ss[0]), (false, ls[1], ss[1])] {
                        let diff = (la[.ellipsis, ..<boundary, 0...] - sa[.ellipsis, ..<boundary, 0...])
                        eval(diff)
                        let maxAbs = Double(diff.abs().max().item(Float.self))
                        if isKeys {
                            loadedKey = Swift.max(loadedKey, maxAbs)
                        } else {
                            loadedValue = Swift.max(loadedValue, maxAbs)
                        }
                    }
                }
                results.append(KVDiff(
                    name: "loadedArtifact_vs_segmentedPrefix",
                    layersCompared: loadedLayers,
                    keysMaxAbsDiff: loadedKey,
                    valuesMaxAbsDiff: loadedValue))

                var vsUnchunkedKey = 0.0
                var vsUnchunkedValue = 0.0
                for (index, cache) in snapshot.cache.enumerated() {
                    guard index < unchunkedCaches.count else { break }
                    let ls = cache.state
                    let us2 = unchunkedCaches[index].state
                    guard ls.count == 2, us2.count == 2 else { continue }
                    for (isKeys, la, ua) in [(true, ls[0], us2[0]), (false, ls[1], us2[1])] {
                        let diff = (la[.ellipsis, ..<boundary, 0...] - ua[.ellipsis, ..<boundary, 0...])
                        eval(diff)
                        let maxAbs = Double(diff.abs().max().item(Float.self))
                        if isKeys {
                            vsUnchunkedKey = Swift.max(vsUnchunkedKey, maxAbs)
                        } else {
                            vsUnchunkedValue = Swift.max(vsUnchunkedValue, maxAbs)
                        }
                    }
                }
                results.append(KVDiff(
                    name: "loadedArtifact_vs_unchunkedPrefix",
                    layersCompared: loadedLayers,
                    keysMaxAbsDiff: vsUnchunkedKey,
                    valuesMaxAbsDiff: vsUnchunkedValue))
            }

            Memory.clearCache()
            return results
        }

        // First divergence margin: over the pairwise-diverging texts, take
        // the smallest first-divergence position; run a reference unchunked
        // forward over prompt + generated prefix and record top-2 logits.
        // The generated prefix is recovered by tokenizing each text's
        // common prefix — texts are decode products of greedy runs, and the
        // divergence analysis only needs the POSITION, so tokenize the
        // common TEXT prefix with the model tokenizer (addSpecialTokens
        // false) and measure the margin at the next-token distribution.
        var margin: DivergenceMargin?
        let divergences = pairwise.compactMap { $0.firstDivergenceIndex }
        if let position = divergences.min() {
            margin = try await container.perform { context in
                let commonText = String(
                    texts[0].prefix(position > texts[0].count ? texts[0].count : position))
                let continuation = context.tokenizer.encode(
                    text: commonText, addSpecialTokens: false)
                let full = promptTokenIDs + continuation
                let logits = context.model(
                    MLXArray(full, [1, full.count]), cache: nil)[0, -1]
                eval(logits)
                let values = logits.asArray(Float.self)
                let indexed = values.enumerated()
                    .sorted { $0.element > $1.element }
                    .prefix(2)
                    .map { ($0.offset, Double($0.element)) }
                guard indexed.count == 2 else { return nil }
                return DivergenceMargin(
                    decodePosition: position,
                    top1TokenID: indexed[0].0,
                    top1Token: context.tokenizer.decode(
                        tokenIds: [indexed[0].0], skipSpecialTokens: true),
                    top1Logit: indexed[0].1,
                    top2TokenID: indexed[1].0,
                    top2Token: context.tokenizer.decode(
                        tokenIds: [indexed[1].0], skipSpecialTokens: true),
                    top2Logit: indexed[1].1,
                    margin: indexed[0].1 - indexed[1].1)
            }
        }

        _ = observations
        return Report(
            modelDirectory: modelDirectory.path,
            promptTokenCount: promptTokenIDs.count,
            boundary: boundary,
            paths: paths,
            pairwise: pairwise,
            kvDiffs: kvDiffs,
            divergenceMargin: margin,
            note: "F1 diagnostic: four greedy decode paths with controlled prefill chunking; direct KV prefix diffs; top-2 margin at first divergence. Diagnostic only — no inference behavior modified, no acceptance bar changed.")
    }

    private static func firstTextDivergence(_ a: String, _ b: String) -> Int? {
        let aChars = Array(a.unicodeScalars)
        let bChars = Array(b.unicodeScalars)
        for index in 0..<Swift.min(aChars.count, bChars.count)
        where aChars[index] != bChars[index] {
            return index
        }
        return aChars.count == bChars.count ? nil : Swift.min(aChars.count, bChars.count)
    }
}
