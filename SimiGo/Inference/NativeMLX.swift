import Foundation
import Synchronization
import MLX
import MLXLMCommon
import MLXLLM
import MLXHuggingFace

/// Native MLX runtime. Inference state is owned by the official ChatSession API.
/// SimiGo retains only service state around that API.
public final class NativeMLX: Runtime, @unchecked Sendable {
    private final class ManagedSession: @unchecked Sendable {
        let session: ChatSession
        var history: [Chat.Message]

        init(session: ChatSession, history: [Chat.Message]) {
            self.session = session
            self.history = history
        }
    }

    private struct State {
        var modelContainer: ModelContainer?
        var httpServer: HTTPServer?
        var isRunning = false
        var lifecycle: Lifecycle = .stopped
        var lastActivity = Date()
        var sessions: [String: ManagedSession] = [:]
        var activeRequestTasks: [String: Task<String, Error>] = [:]
    }

    private enum Lifecycle {
        case stopped
        case loading
        case running
        case suspended
        case resuming
    }

    private let state = Mutex(State())
    private let modelPath: String
    private let baseConfig: ModelConfig
    private let lifecycleGate = RuntimeLifecycleGate()
    private let gateHolder = Mutex(SessionGenerationGate())
    private let traceLogger = RuntimeTraceLogger.shared

    public var isInProcess: Bool { true }
    public var isGenerating: Bool { state.withLock { !$0.activeRequestTasks.isEmpty } }
    public var isRunning: Bool { state.withLock { $0.isRunning } }

    public init(info: ModelInfo, config: ModelConfig) {
        self.modelPath = info.path
        self.baseConfig = config
    }

    private func loadModelContainer(_ path: String) async throws -> ModelContainer {
        try await LLMModelFactory.shared.loadContainer(
            from: URL(fileURLWithPath: path),
            using: #huggingFaceTokenizerLoader()
        )
    }

    public func start(_ info: ModelInfo, port: Int) async throws {
        try await lifecycleGate.withLock { [weak self] in
            guard let self else { throw RuntError.notLoaded }
            guard !self.state.withLock({ $0.isRunning }) else { return }

            self.state.withLock { $0.lifecycle = .loading }
            let container = try await self.loadModelContainer(info.path)
            let modelId = modelName(from: info.path)
            let nodeConfiguration = await MainActor.run {
                let current = InferenceNodeConfiguration.shared.snapshot()
                if current.port != port {
                    InferenceNodeConfiguration.configure(
                        bindHost: current.bindHost,
                        advertisedHost: current.advertisedHost,
                        port: port,
                        bonjourEnabled: current.bonjourEnabled
                    )
                }
                return InferenceNodeConfiguration.shared.snapshot()
            }

            let server = await MainActor.run {
                HTTPServer(
                    port: nodeConfiguration.port,
                    modelId: modelId,
                    bindHost: nodeConfiguration.bindHost,
                    bonjourEnabled: nodeConfiguration.bonjourEnabled,
                    generateHandler: { [weak self] requestId, agentId, sessionId, branchId, messages, tools, config, onChunk, onToolCall in
                        guard let self else { throw RuntError.notLoaded }
                        return try await self.generate(
                            requestId: requestId,
                            agentId: agentId,
                            sessionId: sessionId,
                            logicalBranchId: branchId,
                            messages: messages,
                            tools: tools,
                            config: config,
                            onChunk: onChunk,
                            onToolCall: onToolCall
                        )
                    },
                    checkHealthHandler: { [weak self] in
                        await self?.checkHealth() ?? false
                    },
                    cancelGenerationHandler: { [weak self] requestId in
                        self?.cancelGeneration(requestId: requestId)
                    }
                )
            }

            try await MainActor.run { try server.start() }

            self.state.withLock {
                $0.modelContainer = container
                $0.httpServer = server
                $0.isRunning = true
                $0.lifecycle = .running
                $0.lastActivity = Date()
                $0.sessions.removeAll()
            }

            self.traceLogger.trace("NativeMLX ready: model=\(modelId) port=\(nodeConfiguration.port)")
        }
    }

    public func stop() async {
        await lifecycleGate.withLockVoid { [weak self] in
            guard let self else { return }

            let (server, tasks, gate) = self.state.withLock { state in
                let server = state.httpServer
                let tasks = Array(state.activeRequestTasks.values)
                let gate = self.gateHolder.withLock { $0 }
                state.httpServer = nil
                state.isRunning = false
                state.lifecycle = .stopped
                state.sessions.removeAll()
                state.modelContainer = nil
                state.activeRequestTasks.removeAll()
                return (server, tasks, gate)
            }

            if let server {
                await MainActor.run { server.stop() }
            }

            await gate.beginShutdown()
            for task in tasks { task.cancel() }
            for task in tasks { _ = try? await task.value }
            await gate.awaitDrain()

            Memory.clearCache()
            self.traceLogger.trace("NativeMLX stopped")
            self.traceLogger.flush()
        }
    }

    public func checkHealth() async -> Bool {
        state.withLock { $0.isRunning && $0.httpServer != nil }
    }

    private func ensureLoaded() async throws {
        let needsResume = state.withLock { $0.isRunning && $0.modelContainer == nil }
        guard needsResume else { return }

        try await lifecycleGate.withLock { [weak self] in
            guard let self else { throw RuntError.notLoaded }
            guard self.state.withLock({ $0.isRunning && $0.modelContainer == nil }) else { return }

            self.state.withLock { $0.lifecycle = .resuming }
            do {
                let container = try await self.loadModelContainer(self.modelPath)
                self.state.withLock {
                    $0.modelContainer = container
                    $0.lifecycle = .running
                    $0.lastActivity = Date()
                }
            } catch {
                self.state.withLock {
                    $0.lifecycle = .suspended
                    $0.modelContainer = nil
                }
                throw RuntError.loadFailed(error.localizedDescription)
            }
        }
    }

    public func suspendIfIdle(idleTimeout: TimeInterval = 300) async -> Bool {
        let eligible = state.withLock { state in
            state.isRunning &&
            state.modelContainer != nil &&
            state.activeRequestTasks.isEmpty &&
            Date().timeIntervalSince(state.lastActivity) >= idleTimeout
        }
        guard eligible else { return false }

        do {
            return try await lifecycleGate.withLock { [weak self] in
                guard let self else { return false }
                let stillEligible = self.state.withLock { state in
                    state.isRunning &&
                    state.modelContainer != nil &&
                    state.activeRequestTasks.isEmpty &&
                    Date().timeIntervalSince(state.lastActivity) >= idleTimeout
                }
                guard stillEligible else { return false }

                self.state.withLock {
                    $0.lifecycle = .suspended
                    $0.modelContainer = nil
                    $0.sessions.removeAll()
                    $0.lastActivity = Date()
                }
                Memory.clearCache()
                self.traceLogger.trace("[LIFECYCLE] suspend_done")
                return true
            }
        } catch {
            return false
        }
    }

    public func generate(
        requestId: String = "internal-\(UUID().uuidString.lowercased())",
        agentId: String? = nil,
        sessionId: String = "default",
        logicalBranchId: String = "main",
        messages: [JSONValue],
        tools: [JSONValue]?,
        config: ModelConfig,
        onChunk: @escaping @Sendable (String) -> Void,
        onToolCall: @escaping @Sendable (ParsedToolCall) -> Void = { _ in }
    ) async throws -> String {
        state.withLock { $0.lastActivity = Date() }
        try await ensureLoaded()

        let executionKey = try AgentExecutionKey.resolve(
            agentId: agentId,
            sessionId: sessionId,
            logicalBranchId: logicalBranchId
        )

        let gate = gateHolder.withLock { $0 }
        let task = Task<String, Error> { [weak self] in
            guard let self else { throw RuntError.notLoaded }
            return try await gate.withExclusive(executionKey) {
                try await self.generateUsingChatSession(
                    requestId: requestId,
                    executionKey: executionKey,
                    messages: messages,
                    tools: tools,
                    config: config,
                    onChunk: onChunk,
                    onToolCall: onToolCall
                )
            }
        }

        var registrationError: RuntError?
        state.withLock { state in
            guard state.isRunning else {
                registrationError = .notLoaded
                return
            }
            guard state.activeRequestTasks[requestId] == nil else {
                registrationError = .duplicateRequestId(requestId)
                return
            }
            state.activeRequestTasks[requestId] = task
        }

        if let registrationError {
            task.cancel()
            throw registrationError
        }

        defer {
            state.withLock {
                $0.activeRequestTasks.removeValue(forKey: requestId)
                $0.lastActivity = Date()
            }
        }

        return try await withTaskCancellationHandler(
            operation: { try await task.value },
            onCancel: { task.cancel() }
        )
    }

    private func generateUsingChatSession(
        requestId: String,
        executionKey: AgentExecutionKey,
        messages: [JSONValue],
        tools: [JSONValue]?,
        config: ModelConfig,
        onChunk: @escaping @Sendable (String) -> Void,
        onToolCall: @escaping @Sendable (ParsedToolCall) -> Void
    ) async throws -> String {
        guard let container = state.withLock({ $0.modelContainer }) else {
            throw RuntError.notLoaded
        }

        let incoming = Self.makeChatMessages(messages)
        guard !incoming.isEmpty else { return "" }

        let thinkingDisabled = config.disableThinking || baseConfig.disableThinking
        let params = GenerateParameters(
            maxTokens: config.maxTokens > 0 ? config.maxTokens : baseConfig.maxTokens,
            maxKVSize: nil,
            temperature: config.temperature,
            topP: config.topP,
            topK: config.topK,
            minP: config.minP,
            repetitionPenalty: config.repeatPenalty,
            presencePenalty: config.presencePenalty
        )
        let toolSpecs = Self.makeToolSpecs(tools)
        let additionalContext: [String: any Sendable]? = thinkingDisabled ? ["enable_thinking": false] : nil

        let existing = state.withLock { $0.sessions[executionKey.storageKey] }
        let managed: ManagedSession

        if let existing, Self.isPrefix(existing.history, of: incoming), incoming.count > existing.history.count {
            managed = existing
        } else {
            let history = Array(incoming.dropLast())
            let session = ChatSession(
                container,
                history: history,
                generateParameters: params,
                additionalContext: additionalContext,
                tools: toolSpecs
            )
            managed = ManagedSession(session: session, history: history)
            state.withLock { $0.sessions[executionKey.storageKey] = managed }
        }

        managed.session.generateParameters = params
        managed.session.tools = toolSpecs
        managed.session.additionalContext = additionalContext

        let delta: [Chat.Message]
        if existing === managed,
           Self.isPrefix(managed.history, of: incoming),
           incoming.count > managed.history.count {
            delta = Array(incoming.dropFirst(managed.history.count))
        } else {
            delta = incoming.last.map { [$0] } ?? []
        }

        guard !delta.isEmpty else { return "" }

        var completedText = ""
        var toolCalls: [ToolCall] = []
        let filter = StreamTokenFilter(disableThinking: thinkingDisabled)

        for try await generation in managed.session.streamDetails(to: delta) {
            switch generation {
            case .chunk(let text):
                filter.feed(text) { chunk in
                    completedText.append(chunk)
                    onChunk(chunk)
                }
            case .toolCall(let call):
                toolCalls.append(call)
                let arguments: [String: JSONValue]
                if let data = try? JSONEncoder().encode(call.function.arguments),
                   let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data) {
                    arguments = decoded
                } else {
                    arguments = [:]
                }
                onToolCall(
                    ParsedToolCall(
                        id: call.id ?? UUID().uuidString,
                        name: call.function.name,
                        arguments: arguments
                    )
                )
            case .info:
                break
            }
        }

        filter.flush { chunk in
            completedText.append(chunk)
            onChunk(chunk)
        }

        let assistant = Chat.Message.assistant(
            completedText,
            toolCalls: toolCalls.isEmpty ? nil : toolCalls
        )
        managed.history = incoming + [assistant]
        state.withLock {
            if let current = $0.sessions[executionKey.storageKey], current === managed {
                current.history = managed.history
            }
            $0.lastActivity = Date()
        }

        traceLogger.trace(
            "[MLX] request=\(requestId) session=\(executionKey.traceKey) messages=\(incoming.count) tools=\(toolCalls.count)"
        )
        return completedText
    }

    public func cancelGeneration(requestId: String) {
        state.withLock { $0.activeRequestTasks[requestId] }?.cancel()
        traceLogger.trace("[CANCEL] request=\(requestId)")
    }

    func integrationSnapshot() -> (activeRequests: Int, activeGenerations: Int, sessions: Int) {
        state.withLock {
            ($0.activeRequestTasks.count, $0.activeRequestTasks.count, $0.sessions.count)
        }
    }

    private static nonisolated func makeChatMessages(_ messages: [JSONValue]) -> [Chat.Message] {
        messages.compactMap { value in
            guard case .object(let object) = value else { return nil }
            let role = (object["role"]?.string ?? "user").lowercased()
            let content = coerceContent(object["content"] ?? .null)

            switch role {
            case "system", "developer":
                return .system(content)
            case "assistant":
                let calls = parseToolCalls(object["tool_calls"])
                return .assistant(content, toolCalls: calls.isEmpty ? nil : calls)
            case "tool":
                return .tool(content, id: object["tool_call_id"]?.string)
            default:
                return .user(content)
            }
        }
    }

    private static nonisolated func parseToolCalls(_ value: JSONValue?) -> [ToolCall] {
        guard case .array(let items) = value else { return [] }
        return items.compactMap { item in
            guard case .object(let object) = item,
                  case .object(let function)? = object["function"],
                  let name = function["name"]?.string,
                  !name.isEmpty else { return nil }

            let argumentValue = function["arguments"] ?? .object([:])
            let arguments: [String: JSONValue]
            if case .string(let raw) = argumentValue,
               let data = raw.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data) {
                arguments = decoded
            } else if case .object(let decoded) = argumentValue {
                arguments = decoded
            } else {
                arguments = [:]
            }

            return ToolCall(
                function: .init(name: name, arguments: arguments),
                id: object["id"]?.string
            )
        }
    }

    private static nonisolated func makeToolSpecs(_ tools: [JSONValue]?) -> [ToolSpec]? {
        guard let tools, !tools.isEmpty else { return nil }
        return tools.compactMap { value in
            guard case .object(let object) = value else { return nil }
            var converted: [String: any Sendable] = [:]
            converted.reserveCapacity(object.count)
            for (key, value) in object {
                converted[key] = Self.toSendable(value)
            }
            return converted
        }
    }

    private static nonisolated func toSendable(_ value: JSONValue) -> any Sendable {
        switch value {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .null: return Optional<String>.none
        case .object(let object):
            var converted: [String: any Sendable] = [:]
            converted.reserveCapacity(object.count)
            for (key, value) in object {
                converted[key] = Self.toSendable(value)
            }
            return converted
        case .array(let array):
            return array.map { Self.toSendable($0) }
        }
    }

    private static nonisolated func isPrefix(_ prefix: [Chat.Message], of full: [Chat.Message]) -> Bool {
        guard prefix.count <= full.count else { return false }
        return zip(prefix, full).allSatisfy { signature($0) == signature($1) }
    }

    private static nonisolated func signature(_ message: Chat.Message) -> String {
        let raw = DefaultMessageGenerator().generate(message: message)
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]) else {
            return "\(message.role.rawValue)\u{1f}\(message.content)"
        }
        return data.base64EncodedString()
    }

    private static nonisolated func coerceContent(_ value: JSONValue) -> String {
        switch value {
        case .string(let value): return value
        case .number(let value): return String(value)
        case .bool(let value): return String(value)
        case .null: return ""
        case .array(let values):
            return values.compactMap { item in
                if case .object(let object) = item { return object["text"]?.string }
                return item.string
            }.joined()
        case .object(let object):
            return object["text"]?.string ?? object.description
        }
    }
}
