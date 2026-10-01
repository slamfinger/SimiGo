import Foundation
import MLX
import MLXLMCommon
import Tokenizers

/// Builds generation prompts using the checkpoint's own chat template when one is
/// available. Supports both `tokenizer_config.json` templates and the newer
/// standalone `chat_template.jinja` file.
public struct GenerationOutcome: Sendable {
    public let tokenIDs: [Int]
    public let text: String
}

public enum ChatTemplateGeneration {
    public static func promptTokenIDs(
        tokenizer: MLXLMCommon.Tokenizer,
        modelDirectory: URL,
        prompt: String
    ) async throws -> [Int] {
        let messages: [[String: any Sendable]] = [
            ["role": "user", "content": prompt]
        ]

        let externalTemplate = modelDirectory.appendingPathComponent("chat_template.jinja")
        if FileManager.default.fileExists(atPath: externalTemplate.path) {
            let template = try String(contentsOf: externalTemplate, encoding: .utf8)
            let checkpointTokenizer = try await Tokenizers.AutoTokenizer.from(
                modelFolder: modelDirectory
            )
            let ids = try checkpointTokenizer.applyChatTemplate(
                messages: messages,
                chatTemplate: .literal(template),
                addGenerationPrompt: true,
                truncation: false,
                maxLength: nil,
                tools: nil,
                additionalContext: ["enable_thinking": false]
            )
            return ids
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
        try await generateWithTokens(
            container: container,
            modelDirectory: modelDirectory,
            prompt: prompt,
            maxTokens: maxTokens
        ).text
    }

    public static func generateWithTokens(
        container: ModelContainer,
        modelDirectory: URL,
        prompt: String,
        maxTokens: Int
    ) async throws -> GenerationOutcome {
        try await container.perform { context -> GenerationOutcome in
            let promptTokenIDs = try await promptTokenIDs(
                tokenizer: context.tokenizer,
                modelDirectory: modelDirectory,
                prompt: prompt
            )

            var generated: [Int] = []
            var input = MLXArray(promptTokenIDs, [1, promptTokenIDs.count])

            for _ in 0 ..< maxTokens {
                let logits = context.model(input, cache: nil)[0, -1]
                let nextToken = logits.argMax().item(Int.self)
                generated.append(nextToken)
                if nextToken == context.tokenizer.eosTokenId ?? -1 {
                    break
                }
                input = MLXArray(
                    promptTokenIDs + generated,
                    [1, promptTokenIDs.count + generated.count]
                )
                eval(logits)
            }
            let text = context.tokenizer.decode(
                tokenIds: generated,
                skipSpecialTokens: true
            )
            return GenerationOutcome(tokenIDs: generated, text: text)
        }
    }
}
