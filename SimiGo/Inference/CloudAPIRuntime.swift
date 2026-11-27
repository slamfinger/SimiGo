import Foundation
import Synchronization

/// OpenAI-compatible streaming client used by CloudAPIRuntime. It deliberately
/// performs one upstream request per SimiGo generation: retries are left to the
/// Agent because a lost response may still have incurred provider-side work.
nonisolated final class OpenAICompatibleClient: @unchecked Sendable {
    private struct ToolDraft {
        var id = ""
        var name = ""
        var arguments = ""
    }

    enum Failure: LocalizedError {
        case nonHTTPResponse
        case upstreamStatus(Int)
        case providerStreamError

        var errorDescription: String? {
            switch self {
            case .nonHTTPResponse:
                return "Cloud API returned a non-HTTP response"
            case .upstreamStatus(let status):
                return "Cloud API returned HTTP \(status)"
            case .providerStreamError:
                return "Cloud API reported an error inside the event stream"
            }
        }
    }

    private let profile: CloudAPIProfile
    private let apiKey: String
    private let endpoint: URL
    private let session: URLSession
    private let tasks = Mutex<[String: Task<GenerationResult, Error>]>([:])

    var activeRequestCount: Int { tasks.withLock { $0.count } }

    init(profile: CloudAPIProfile, apiKey: String) throws {
        try profile.validate()
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw CloudAPIProfileError.missingRequiredField
        }
        self.profile = profile
        self.apiKey = trimmedKey
        endpoint = try profile.chatCompletionsURL()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
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
        onToolCall: @escaping @Sendable (ParsedToolCall) -> Void,
        onReasoning: @escaping @Sendable (String) -> Void
    ) async throws -> GenerationResult {
        let task = Task<GenerationResult, Error> {
            try await self.stream(
                messages: messages,
                tools: tools,
                config: config,
                onChunk: onChunk,
                onToolCall: onToolCall,
                onReasoning: onReasoning)
        }
        tasks.withLock { $0[requestId] = task }
        defer { tasks.withLock { $0[requestId] = nil } }

        do {
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

    static func makeRequest(
        profile: CloudAPIProfile,
        apiKey: String,
        messages: [JSONValue],
        tools: [JSONValue]?,
        config: ModelConfig
    ) throws -> URLRequest {
        try profile.validate()
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw CloudAPIProfileError.missingRequiredField }

        var body: [String: Any] = [
            "model": profile.model,
            "messages": messages.map { $0.toAny() },
            "stream": true,
            "stream_options": ["include_usage": true],
            "temperature": config.temperature,
            "top_p": config.topP,
            "max_tokens": config.maxTokens,
            "presence_penalty": config.presencePenalty,
        ]
        if let tools, !tools.isEmpty {
            body["tools"] = tools.map { $0.toAny() }
        }
        if let choice = config.toolChoice {
            switch choice.mode {
            case .auto, .none, .required:
                body["tool_choice"] = choice.mode.rawValue
            case .function:
                if let name = choice.functionName, !name.isEmpty {
                    body["tool_choice"] = [
                        "type": "function",
                        "function": ["name": name],
                    ]
                }
            }
        }

        var request = URLRequest(url: try profile.chatCompletionsURL())
        request.httpMethod = "POST"
        request.timeoutInterval = 3600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: body, options: [.sortedKeys])
        return request
    }

    private func stream(
        messages: [JSONValue],
        tools: [JSONValue]?,
        config: ModelConfig,
        onChunk: @escaping @Sendable (String) -> Void,
        onToolCall: @escaping @Sendable (ParsedToolCall) -> Void,
        onReasoning: @escaping @Sendable (String) -> Void
    ) async throws -> GenerationResult {
        let request = try Self.makeRequest(
            profile: profile, apiKey: apiKey,
            messages: messages, tools: tools, config: config)

        let startedAt = Date()
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Failure.nonHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Failure.upstreamStatus(http.statusCode)
        }

        var lineBuffer = Data()
        var text = ""
        var finishReason: String?
        var usage: (prompt: Int, generation: Int, cached: Int?)?
        var drafts: [Int: ToolDraft] = [:]
        var firstTokenAt: Date?

        func consumeLine(_ data: Data) throws {
            let line = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("data:") else { return }
            let payload = line.dropFirst("data:".count)
                .trimmingCharacters(in: .whitespaces)
            if payload.isEmpty || payload == "[DONE]" { return }
            guard let eventData = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: eventData)
                    as? [String: Any]
            else { return }

            if event["error"] != nil { throw Failure.providerStreamError }

            if let rawUsage = event["usage"] as? [String: Any],
               let prompt = (rawUsage["prompt_tokens"] as? NSNumber)?.intValue,
               let generation = (rawUsage["completion_tokens"] as? NSNumber)?.intValue {
                let details = rawUsage["prompt_tokens_details"] as? [String: Any]
                let cached = (details?["cached_tokens"] as? NSNumber)?.intValue
                usage = (prompt, generation, cached)
            }

            guard let choice = (event["choices"] as? [[String: Any]])?.first else {
                return
            }
            if let delta = choice["delta"] as? [String: Any] {
                if let content = delta["content"] as? String, !content.isEmpty {
                    if firstTokenAt == nil { firstTokenAt = Date() }
                    text += content
                    onChunk(content)
                }
                if let reasoning = delta["reasoning_content"] as? String,
                   !reasoning.isEmpty {
                    onReasoning(reasoning)
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
                                draft.name += name
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

        for try await byte in bytes {
            if Task.isCancelled { throw CancellationError() }
            if byte == UInt8(ascii: "\n") {
                try consumeLine(lineBuffer)
                lineBuffer.removeAll(keepingCapacity: true)
            } else if byte != UInt8(ascii: "\r") {
                lineBuffer.append(byte)
            }
        }
        if !lineBuffer.isEmpty { try consumeLine(lineBuffer) }
        if Task.isCancelled { throw CancellationError() }

        for (_, draft) in drafts.sorted(by: { $0.key < $1.key })
        where !draft.name.isEmpty {
            onToolCall(ParsedToolCall(
                id: draft.id.isEmpty ? UUID().uuidString : draft.id,
                name: draft.name,
                arguments: Self.arguments(from: draft.arguments)))
        }

        let finishedAt = Date()
        let completion: GenerationCompletion
        switch finishReason {
        case "stop", "tool_calls":
            completion = .complete
        case "length":
            completion = .capped
        default:
            completion = .unconfirmed
        }

        let usageReport: GenerationUsageReport? = usage.map { value in
            let ttft = firstTokenAt.map { $0.timeIntervalSince(startedAt) }
            let decodeSeconds = max(0.001, finishedAt.timeIntervalSince(
                firstTokenAt ?? startedAt))
            return GenerationUsageReport(
                promptTokens: value.prompt,
                generationTokens: value.generation,
                cachedPromptTokens: value.cached,
                cacheEfficiency: value.cached.map { Double($0) / Double(max(1, value.prompt)) },
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
}

/// Remote provider runtime. It owns the product HTTPServer just like the local
/// runtimes, so every caller still passes through SimiGo's identity, IS,
/// Digest-substitution, settlement, and answer-reuse path before generation.
final class CloudAPIRuntime: Runtime, @unchecked Sendable {
    private struct State: @unchecked Sendable {
        var server: HTTPServer?
        var client: OpenAICompatibleClient?
        var running = false
    }

    private let profile: CloudAPIProfile
    private let apiKey: String
    private let state = Mutex(State())

    init(profile: CloudAPIProfile, apiKey: String) {
        self.profile = profile
        self.apiKey = apiKey
    }

    var isRunning: Bool { state.withLock { $0.running } }
    var isGenerating: Bool { state.withLock { $0.client?.activeRequestCount ?? 0 > 0 } }
    var isInProcess: Bool { false }

    func start(_ info: ModelInfo, port: Int) async throws {
        try await start(port: port)
    }

    func start(port: Int) async throws {
        let node = await MainActor.run {
            InferenceNodeConfiguration.shared.snapshot()
        }
        let client = try OpenAICompatibleClient(profile: profile, apiKey: apiKey)
        let server = await MainActor.run {
            HTTPServer(
                port: port,
                modelId: profile.model,
                bindHost: node.bindHost,
                bonjourEnabled: node.bonjourEnabled,
                generateHandler: { requestId, _, _, _, messages, tools, config,
                    onChunk, onToolCall, onReasoning in
                    try await client.generate(
                        requestId: requestId,
                        messages: messages,
                        tools: tools,
                        config: config,
                        onChunk: onChunk,
                        onToolCall: onToolCall,
                        onReasoning: onReasoning)
                },
                forkBranchHandler: { _, _, _, _ in
                    throw RuntError.generationFailed(
                        "Cloud API backend does not expose local KV branch snapshots")
                },
                deleteBranchHandler: { _, _, _, _ in
                    throw RuntError.generationFailed(
                        "Cloud API backend does not expose local KV branch snapshots")
                },
                listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
                checkHealthHandler: { [weak self] in
                    await self?.checkHealth() ?? false
                },
                cancelGenerationHandler: { requestId in
                    client.cancel(requestId: requestId)
                },
                baseConfigProvider: { ModelConfig() }
            )
        }

        try LOCALBHostRuntime.applyDefault(
            to: server,
            bindHost: node.bindHost,
            hostDirectory: nil,
            plaintextCompatibilityPort: node.localCompatibilityPort)
        do {
            try await server.startAndWaitUntilReady()
        } catch {
            client.cancelAll()
            await MainActor.run { server.stop() }
            throw error
        }
        state.withLock {
            $0.server = server
            $0.client = client
            $0.running = true
        }
    }

    func stop() async {
        let (server, client) = state.withLock { current -> (HTTPServer?, OpenAICompatibleClient?) in
            let snapshot = (current.server, current.client)
            current.server = nil
            current.client = nil
            current.running = false
            return snapshot
        }
        client?.cancelAll()
        if let server {
            await MainActor.run { server.stop() }
        }
    }

    /// This is a local runtime-liveness check only. It intentionally does not
    /// issue provider probes, which could consume quota or create hidden calls.
    func checkHealth() async -> Bool { isRunning }
}
