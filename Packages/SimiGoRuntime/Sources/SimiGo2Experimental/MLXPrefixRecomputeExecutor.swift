import Foundation
import MLX
import MLXLMCommon
import SimiGoRuntimeContract

/// E3/L4 — the Prefix-Recompute Executor: consumes a bound execution
/// representation (token prefix) and continues it with real MLX execution.
///
/// This is the component the E5 audit required: real generation CONSUMES the
/// Execution State's representation instead of reconstructing an equivalent
/// input from chat messages. The executor is Backend-side: it owns the
/// forward/generation semantics; the Runtime owns identity, lineage,
/// position, and continuation.

/// Result of a representation-consuming continuation.
public struct ExecutionContinuationResult: Sendable {
    public let executionID: ExecutionID
    /// Length of the physical prefix that was consumed.
    public let consumedPrefixLength: Int
    public let nextInputTokenCount: Int
    public let generatedTokenIDs: [Int]
    public let generatedText: String
    /// The advanced physical representation (prefix + next input +
    /// generated). The Runtime rebinds its logical position to this payload.
    public let updatedPayload: any ExecutionRepresentationPayload

    public init(
        executionID: ExecutionID,
        consumedPrefixLength: Int,
        nextInputTokenCount: Int,
        generatedTokenIDs: [Int],
        generatedText: String,
        updatedPayload: any ExecutionRepresentationPayload
    ) {
        self.executionID = executionID
        self.consumedPrefixLength = consumedPrefixLength
        self.nextInputTokenCount = nextInputTokenCount
        self.generatedTokenIDs = generatedTokenIDs
        self.generatedText = generatedText
        self.updatedPayload = updatedPayload
    }
}

public final class MLXPrefixRecomputeExecutor: @unchecked Sendable {
    private let container: ModelContainer
    private let backend: MLXExecutionStateBackend

    public init(container: ModelContainer, backend: MLXExecutionStateBackend) {
        self.container = container
        self.backend = backend
    }

    /// Tokenize next-input text (Backend-owned tokenization).
    public func tokenizeText(_ text: String) async throws -> [Int] {
        await container.perform { (context: ModelContext) -> [Int] in
            context.tokenizer.encode(text: text, addSpecialTokens: false)
        }
    }

    /// Seed-text encoding for the scenario bootstrap: raw text encoding WITH
    /// special tokens (BOS) — the one text-seeded generation.
    public func tokenizeSeedText(_ text: String) async throws -> [Int] {
        await container.perform { (context: ModelContext) -> [Int] in
            context.tokenizer.encode(text: text, addSpecialTokens: true)
        }
    }

    /// Continue the execution: consume the state's CURRENT bound prefix plus
    /// the next-input tokens, forward through MLX, and greedily generate up
    /// to `maxTokens`. Returns the advanced physical representation for the
    /// Runtime to rebind after advancing the logical position.
    public func continueExecution(
        _ state: ExecutionStateHandle,
        nextInputTokens: [Int],
        maxTokens: Int
    ) async throws -> ExecutionContinuationResult {
        let bound = try backend.boundPrefix(for: state)
        let inputTokens = bound.prefix + nextInputTokens

        let generated = await container.perform { (context: ModelContext) -> [Int] in
            var generated: [Int] = []
            var tokens = inputTokens
            var running = MLXArray(tokens, [1, tokens.count])
            for _ in 0..<maxTokens {
                let logits = context.model(running, cache: nil)[0, -1]
                let nextToken = logits.argMax().item(Int.self)
                generated.append(nextToken)
                if nextToken == context.tokenizer.eosTokenId ?? -1 {
                    break
                }
                tokens = tokens + [nextToken]
                running = MLXArray(tokens, [1, tokens.count])
                eval(logits)
            }
            return generated
        }

        let extended = inputTokens + generated
        // The physical prefix has advanced; the bound position goes stale
        // until the Runtime advances the logical position and rebinds.
        backend.consumeBinding(for: state)

        let text: String = await container.perform { (context: ModelContext) -> String in
            context.tokenizer.decode(tokenIds: generated, skipSpecialTokens: true)
        }

        return ExecutionContinuationResult(
            executionID: state.id,
            consumedPrefixLength: bound.prefix.count,
            nextInputTokenCount: nextInputTokens.count,
            generatedTokenIDs: generated,
            generatedText: text,
            updatedPayload: MLXPrefixPayload(tokenPrefix: extended)
        )
    }
}
