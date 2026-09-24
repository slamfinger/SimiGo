import Foundation
import MLX
import MLXLMCommon
import Tokenizers

/// Builds generation prompts using the checkpoint's own chat template when one is
/// available. Supports both `tokenizer_config.json` templates and the newer
/// standalone `chat_template.jinja` file.
public enum ChatTemplateGeneration {
    public static func promptTokenIDs(
        tokenizer: MLXLMCommon.Tokenizer,
        modelDirectory: URL,
        prompt: String
    ) throws -> [Int] {
        let messages: [[String: any Sendable]] = [
            ["role": "user", "content": prompt]
        ]

        let externalTemplate = modelDirectory.appendingPathComponent("chat_template.jinja")
        if FileManager.default.fileExists(atPath: externalTemplate.path) {
            let template = try String(contentsOf: externalTemplate, encoding: .utf8)
            if let pretrained = tokenizer as? Tokenizers.PreTrainedTokenizer {
                return try pretrained.applyChatTemplate(
                    messages: messages,
                    chatTemplate: .literal(template),
                    addGenerationPrompt: true,
                    tools: nil,
                    additionalContext: ["enable_thinking": false]
                )
            }
        }

        if let configured = tokenizer as? Tokenizers.PreTrainedTokenizer,
           configured.hasChatTemplate {
            return try configured.applyChatTemplate(
                messages: messages,
                tools: nil,
                additionalContext: ["enable_thinking": false]
            )
        }

        return try tokenizer.applyChatTemplate(messages: messages)
    }

    public static func generate(
        container: ModelContainer,
        modelDirectory: URL,
        prompt: String,
        maxTokens: Int
    ) async throws -> String {
        try await container.perform { context -> String in
            let promptTokenIDs = try promptTokenIDs(
                tokenizer: context.tokenizer,
                modelDirectory: modelDirectory,
                prompt: prompt
            )

            let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0)
            var cache = try context.model.newCache(parameters: parameters)
            var input = MLXArray(promptTokenIDs, [1, promptTokenIDs.count])
            var generated: [Int] = []

            for _ in 0 ..< maxTokens {
                let logits = context.model(input, cache: cache)[0, -1]
                let nextToken = logits.argMax().item(Int.self)
                generated.append(nextToken)
                if nextToken == context.tokenizer.eosTokenId ?? -1 {
                    break
                }
                input = MLXArray([nextToken], [1, 1])
                eval(cache)
            }

            eval(cache)
            return context.tokenizer.decode(
                tokenIds: generated,
                skipSpecialTokens: true
            )
        }
    }
}
