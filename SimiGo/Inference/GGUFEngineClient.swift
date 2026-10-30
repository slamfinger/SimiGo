import Foundation
import Synchronization

/// The managed llama.cpp engine speaks an OpenAI-compatible SSE wire. This
/// client is the single translation point between that wire and the contract
/// the protocol layer settles on (text, usage, termination), so a GGUF turn
/// runs through the same `HTTPServerChat` entry as an in-process MLX turn.
final class GGUFEngineClient: @unchecked Sendable {
    struct Endpoint: Sendable {
        let baseURL: URL
        let model: String
    }

    enum Failure: Error, LocalizedError {
        case nonHTTPResponse
        case upstream(status: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .nonHTTPResponse:
                return "llama.cpp engine returned a non-HTTP response"
            case let .upstream(status, body):
                let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                return "llama.cpp engine HTTP \(status)"
                    + (trimmed.isEmpty ? "" : ": \(trimmed.prefix(512))")
            }
        }
    }

    private struct ToolDraft {
        var id = ""
        var name = ""
        var arguments = ""
    }

    private let endpoint: Endpoint
    private let session: URLSession
    private let tasks = Mutex<[String: Task<GenerationResult, Error>]>([:])

    /// Requests currently streaming from the engine. The protocol layer's
    /// `isGenerating` signal — the health loop uses it to avoid probing a busy
    /// llama-server, whose `/health` answers 503 while a slot is active.
    var activeRequestCount: Int { tasks.withLock { $0.count } }

    init(endpoint: Endpoint) {
        self.endpoint = endpoint
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        // A cold prefill on a large GGUF can take minutes before the first
        // token; the client's own timeout is the cancel path, not this one.
        configuration.timeoutIntervalForRequest = 3600
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        session = URLSession(configuration: configuration)
    }

    func generate(
        requestId: String,
        messages: [JSONValue],
        tools: [JSONValue]?,
        config: ModelConfig,
        onChunk: @escaping @Sendable (String) -> Void,
        onToolCall: @escaping @Sendable (ParsedToolCall) -> Void
    ) async throws -> GenerationResult {
        let task = Task<GenerationResult, Error> {
            try await self.stream(
                messages: messages, tools: tools, config: config,
                onChunk: onChunk, onToolCall: onToolCall)
        }
        tasks.withLock { $0[requestId] = task }
        defer { tasks.withLock { $0[requestId] = nil } }

        do {
            // The protocol layer's own cancellation must also stop the engine
            // stream; `Task {}` does not inherit cancellation from its parent.
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
    }

    func cancel(requestId: String) {
        let task = tasks.withLock { $0.removeValue(forKey: requestId) }
        task?.cancel()
    }

    func cancelAll() {
        let running = tasks.withLock { state -> [Task<GenerationResult, Error>] in
            let values = Array(state.values)
            state.removeAll()
            return values
        }
        running.forEach { $0.cancel() }
    }

    private func stream(
        messages: [JSONValue],
        tools: [JSONValue]?,
        config: ModelConfig,
        onChunk: @escaping @Sendable (String) -> Void,
        onToolCall: @escaping @Sendable (ParsedToolCall) -> Void
    ) async throws -> GenerationResult {
        var request = URLRequest(
            url: endpoint.baseURL.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 3600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try Self.requestBody(
            model: endpoint.model, messages: messages, tools: tools, config: config)

        let startedAt = Date()
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Failure.nonHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count >= 4096 { break }
            }
            throw Failure.upstream(
                status: http.statusCode,
                body: String(decoding: body, as: UTF8.self))
        }

        var lineBuffer = Data()
        var text = ""
        var finishReason: String?
        var usage: (prompt: Int, generation: Int, cached: Int?)?
        var drafts: [Int: ToolDraft] = [:]
        var firstTokenAt: Date?

        for try await byte in bytes {
            if Task.isCancelled { throw CancellationError() }
            guard byte == UInt8(ascii: "\n") else {
                lineBuffer.append(byte)
                continue
            }
            let line = String(decoding: lineBuffer, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lineBuffer.removeAll(keepingCapacity: true)
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count)
                .trimmingCharacters(in: .whitespaces)
            if payload.isEmpty { continue }
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if let rawUsage = event["usage"] as? [String: Any],
                let prompt = (rawUsage["prompt_tokens"] as? NSNumber)?.intValue,
                let generation = (rawUsage["completion_tokens"] as? NSNumber)?.intValue
            {
                let cachedDetails = rawUsage["prompt_tokens_details"] as? [String: Any]
                let cached = (cachedDetails?["cached_tokens"] as? NSNumber)?.intValue
                usage = (prompt, generation, cached)
            }

            guard let choice = (event["choices"] as? [[String: Any]])?.first else {
                continue
            }
            if let delta = choice["delta"] as? [String: Any] {
                if let content = delta["content"] as? String, !content.isEmpty {
                    if firstTokenAt == nil { firstTokenAt = Date() }
                    text += content
                    onChunk(content)
                }
                if let calls = delta["tool_calls"] as? [[String: Any]] {
                    for call in calls {
                        let index = (call["index"] as? NSNumber)?.intValue ?? 0
                        var draft = drafts[index] ?? ToolDraft()
                        if let id = call["id"] as? String, !id.isEmpty {
                            draft.id = id
                        }
                        if let function = call["function"] as? [String: Any] {
                            if let name = function["name"] as? String, !name.isEmpty {
                                draft.name = name
                            }
                            if let arguments = function["arguments"] as? String {
                                draft.arguments += arguments
                            }
                        }
                        drafts[index] = draft
                    }
                }
            }
            if let reason = choice["finish_reason"] as? String {
                finishReason = reason
            }
        }
        if Task.isCancelled { throw CancellationError() }

        for (_, draft) in drafts.sorted(by: { $0.key < $1.key }) where !draft.name.isEmpty {
            onToolCall(ParsedToolCall(
                id: draft.id.isEmpty ? UUID().uuidString : draft.id,
                name: draft.name,
                arguments: Self.arguments(from: draft.arguments)))
        }

        let finishedAt = Date()
        let completion: GenerationCompletion
        switch finishReason {
        // "tool_calls" is a normal ending: the turn produced tool calls and the
        // protocol layer refuses settlement for it on that ground alone.
        case "stop", "tool_calls": completion = .complete
        case "length": completion = .capped
        default: completion = .unconfirmed
        }
        let usageReport: GenerationUsageReport? = usage.map { value in
            let seconds = finishedAt.timeIntervalSince(startedAt)
            let ttft = firstTokenAt.map { $0.timeIntervalSince(startedAt) }
            let decodeSeconds = max(0.001, seconds - (ttft ?? 0))
            return GenerationUsageReport(
                promptTokens: value.prompt,
                generationTokens: value.generation,
                cachedPromptTokens: value.cached,
                cacheEfficiency: value.prompt > 0
                    ? Double(value.cached ?? 0) / Double(value.prompt) : nil,
                ttftSeconds: ttft,
                tokensPerSecond: Double(value.generation) / decodeSeconds)
        }
        return GenerationResult(text: text, usage: usageReport, completion: completion)
    }

    private static func arguments(from raw: String) -> [String: JSONValue] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            let data = trimmed.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object.mapValues { JSONValue.any($0) }
    }

    private static func requestBody(
        model: String,
        messages: [JSONValue],
        tools: [JSONValue]?,
        config: ModelConfig
    ) throws -> Data {
        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { $0.toAny() },
            "stream": true,
            "stream_options": ["include_usage": true],
            "cache_prompt": true,
            "temperature": config.temperature,
            "top_p": config.topP,
            "top_k": config.topK,
            "min_p": config.minP,
            "repeat_penalty": config.repeatPenalty,
            "presence_penalty": config.presencePenalty,
            "max_tokens": config.maxTokens,
        ]
        if let tools, !tools.isEmpty {
            body["tools"] = tools.map { $0.toAny() }
        }
        if config.disableThinking {
            body["chat_template_kwargs"] = ["enable_thinking": false]
        }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }
}
