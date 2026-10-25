import Foundation
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// F1 follow-up isolation: is the durable artifact a faithful save of the
/// KV the saving session computed? Compares the loaded artifact's prefix KV
/// against a DIRECT single-forward (unchunked) computation of the same
/// prefix over the same weights. The main diagnostics run showed the
/// artifact-from-a-balanced-session differing from fresh KV by max-abs ~26;
/// this experiment removes the "balanced-session internals" confounder by
/// sourcing the artifact from an UNCHUNKED session (whose math is a single
/// forward, matching the direct call). A remaining large diff isolates the
/// save/load path itself; ~0 diff acquits it and re-points at session-side
/// prefill internals.
public enum F1ArtifactFidelity {

    public struct Report: Codable, Hashable, Sendable {
        public let modelDirectory: String
        public let promptTokenCount: Int
        public let boundary: Int
        public let layersCompared: Int
        public let keysMaxAbsDiff: Double
        public let valuesMaxAbsDiff: Double
        public let keysNonZeroRows: Int
        public let loadedPrefixRows: Int
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
            throw PrefixSnapshotStoreError.artifactUnreadable("boundary out of range")
        }

        // Source session: UNCHUNKED prefill (single forward per chunk-free
        // whole prompt), then a greedy turn so the session has a complete
        // prompt pass to save from.
        var parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0)
        parameters.prefill.chunking = .unchunked
        let session = ChatSession(container, generateParameters: parameters)
        _ = try await session.respond(to: prompt)

        let namespace = PrefixPoolNamespace(
            modelID: modelDirectory.lastPathComponent,
            kvFingerprint: "f1-artifact-fidelity-v1")
        let store = PrefixSnapshotStore(
            root: cacheRoot, pool: ExecutionStatePrefixPool(tokenBudget: 100_000_000))
        let entry = try await store.export(
            namespace: namespace,
            tokens: Array(promptTokenIDs.prefix(boundary))
        ) { url in
            try await session.savePrefixSnapshot(to: url, upTo: boundary)
        }

        return try await container.perform { context in
            // Direct reference: single forward over the boundary prefix.
            let caches = try context.model.newCache(parameters: nil)
            _ = context.model(
                MLXArray(Array(promptTokenIDs.prefix(boundary)), [1, boundary]),
                cache: caches)

            let artifactURL = (entry.artifact as? DiskPrefixArtifact)?.snapshotURL
            let snapshot = try loadPromptCacheSnapshot(
                url: artifactURL ?? cacheRoot, materializeArrays: true)

            var keysMax = 0.0
            var valuesMax = 0.0
            var nonZeroRows = 0
            var compared = 0
            var loadedRows = 0
            for (index, loaded) in snapshot.cache.enumerated() {
                guard index < caches.count else { break }
                let fresh = caches[index].state
                let loadedState = loaded.state
                guard fresh.count == 2, loadedState.count == 2 else { continue }
                compared += 1
                loadedRows = max(
                    loadedRows,
                    loadedState[0].dim(2))
                for isKeys in [true, false] {
                    let f = isKeys ? fresh[0] : fresh[1]
                    let l = isKeys ? loadedState[0] : loadedState[1]
                    let rows = min(boundary, min(f.dim(2), l.dim(2)))
                    let diff = (l[.ellipsis, ..<rows, 0...] - f[.ellipsis, ..<rows, 0...])
                    eval(diff)
                    let maxAbs = Double(diff.abs().max().item(Float.self))
                    if isKeys {
                        keysMax = max(keysMax, maxAbs)
                    } else {
                        valuesMax = max(valuesMax, maxAbs)
                    }
                    // How many ROWS of the loaded keys are entirely non-zero
                    // beyond row 0 — detects padding/offset misalignment.
                    if isKeys {
                        let lSliced = l[.ellipsis, ..<rows, 0...]
                        eval(lSliced)
                        let flat = lSliced.asArray(Float.self)
                        let perRow = rows > 0 ? flat.count / rows : 0
                        if perRow > 0 {
                            for row in 1..<rows {
                                let slice = flat[(row * perRow)..<((row + 1) * perRow)]
                                if slice.contains(where: { $0 != 0 }) {
                                    nonZeroRows += 1
                                }
                            }
                        }
                    }
                }
            }
            Memory.clearCache()
            return Report(
                modelDirectory: modelDirectory.path,
                promptTokenCount: promptTokenIDs.count,
                boundary: boundary,
                layersCompared: compared,
                keysMaxAbsDiff: keysMax,
                valuesMaxAbsDiff: valuesMax,
                keysNonZeroRows: nonZeroRows,
                loadedPrefixRows: loadedRows,
                note: "Artifact sourced from an UNCHUNKED session and compared against a direct single-forward KV over the same prefix. ~0 diff acquits save/load; large diff isolates it.")
        }
    }
}
