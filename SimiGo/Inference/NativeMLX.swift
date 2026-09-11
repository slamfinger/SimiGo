import Foundation
import Synchronization
import MLX
import MLXLMCommon
import MLXLLM
import MLXHuggingFace
import Tokenizers

/// Native MLX runtime. Inference state is owned by the official ChatSession API.
/// SimiGo retains only service state around that API.
public final class NativeMLX: Runtime, @unchecked Sendable {
    private nonisolated final class ManagedSession: @unchecked Sendable {
        let session: ChatSession
        var history: [Chat.Message]
        /// Message-level transcript in SimiGo JSON form (client echo form for
        /// assistant turns). Persisted next to an official cache snapshot so a
        /// reloaded session continues the delta contract; NOT a token ledger.
        var historyJSON: [JSONValue]

        init(
            session: ChatSession,
            history: [Chat.Message],
            historyJSON: [JSONValue] = []
        ) {
            self.session = session
            self.history = history
            self.historyJSON = historyJSON
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
        Memory.memoryLimit = RuntimeTuning.mlxMemoryLimitBytes
        Memory.cacheLimit = RuntimeTuning.mlxCacheLimitBytes
    }

    public func start(_ info: ModelInfo, port: Int) async throws {
        try await lifecycleGate.withLock { [weak self] in
            guard let self else { throw RuntError.notLoaded }
            guard !self.state.withLock({ $0.isRunning }) else { return }

            self.state.withLock { $0.lifecycle = .loading }
            let container = try await LLMModelFactory.shared.loadContainer(
                from: URL(fileURLWithPath: info.path),
                using: #huggingFaceTokenizerLoader()
            )
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
                let container = try await LLMModelFactory.shared.loadContainer(
                    from: URL(fileURLWithPath: self.modelPath),
                    using: #huggingFaceTokenizerLoader()
                )
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
                registrationError = .generationFailed("Duplicate request ID: \(requestId)")
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
        let kvSettings = config.kvCache ?? baseConfig.kvCache
        let kvConfiguration = try Self.makeKVCacheConfiguration(kvSettings)
        var params = GenerateParameters(
            maxTokens: config.maxTokens > 0 ? config.maxTokens : baseConfig.maxTokens,
            maxKVSize: nil,
            temperature: config.temperature,
            topP: config.topP,
            topK: config.topK,
            minP: config.minP,
            repetitionPenalty: config.repeatPenalty,
            presencePenalty: config.presencePenalty
        )
        params.kvCache = kvConfiguration
        let toolSpecs = Self.makeToolSpecs(tools)
        let additionalContext: [String: any Sendable]? = thinkingDisabled ? ["enable_thinking": false] : nil

        let existing = state.withLock { $0.sessions[executionKey.storageKey] }
        let managed: ManagedSession
        let reusedSession: Bool

        if let existing,
           incoming.count > existing.history.count,
           Self.isPrefix(existing.history, of: incoming) {
            managed = existing
            reusedSession = true
        } else {
            if let existing,
               incoming.count > existing.history.count,
               let mismatch = Self.firstPrefixMismatch(existing.history, of: incoming) {
                let historyMessage = existing.history[mismatch]
                let incomingMessage = incoming[mismatch]
                traceLogger.trace(
                    "[MLX] prefixMismatch index=\(mismatch) role=\(incomingMessage.role.rawValue)" +
                    " historyTool=\(historyMessage.tool != nil) incomingTool=\(incomingMessage.tool != nil)" +
                    " history=\(existing.history.count) incoming=\(incoming.count)"
                )
            }
            let history = Array(incoming.dropLast())
            let session = ChatSession(
                container,
                history: history,
                generateParameters: params,
                additionalContext: additionalContext,
                tools: toolSpecs
            )
            managed = ManagedSession(
                session: session,
                history: history,
                historyJSON: Array(messages.dropLast())
            )
            reusedSession = false
            state.withLock { $0.sessions[executionKey.storageKey] = managed }
        }

        managed.session.generateParameters = params
        managed.session.tools = toolSpecs
        managed.session.additionalContext = additionalContext

        let delta: [Chat.Message]
        if reusedSession {
            delta = Array(incoming.dropFirst(managed.history.count))
        } else {
            delta = incoming.last.map { [$0] } ?? []
        }

        guard !delta.isEmpty else { return "" }

        let historyCount = managed.history.count
        let deltaCount = delta.count
        let streamStart = Date()
        var ttft: TimeInterval?
        let cacheTokensBefore = (try? await managed.session.cacheStatus())?
            .processedTokenCount

        var completedText = ""
        var toolCalls: [ToolCall] = []
        let filter = StreamTokenFilter(disableThinking: thinkingDisabled)
        var tokensPerSecond: Double?
        var promptTokens: Int?
        var promptSeconds: Double?
        var cachedPromptTokens: Int?
        var cacheEfficiency: Double?

        for try await generation in managed.session.streamDetails(to: delta) {
            switch generation {
            case .chunk(let text):
                ttft = ttft ?? Date().timeIntervalSince(streamStart)
                filter.feed(text) { chunk in
                    completedText.append(chunk)
                    onChunk(chunk)
                }
            case .toolCall(let call):
                ttft = ttft ?? Date().timeIntervalSince(streamStart)
                let normalizedCall = ToolCall(
                    function: call.function,
                    id: call.id ?? UUID().uuidString
                )
                toolCalls.append(normalizedCall)

                let arguments: [String: JSONValue]
                if let data = try? JSONEncoder().encode(normalizedCall.function.arguments),
                   let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data) {
                    arguments = decoded
                } else {
                    arguments = [:]
                }
                onToolCall(
                    ParsedToolCall(
                        id: normalizedCall.id ?? "",
                        name: normalizedCall.function.name,
                        arguments: arguments
                    )
                )
            case .rejectedToolCall(let rejection):
                traceLogger.trace(
                    "[MLX] rejectedToolCall reason=\(rejection.reason.rawValue) tool=\(rejection.toolName ?? "-")"
                )
            case .info(let info):
                tokensPerSecond = info.tokensPerSecond
                promptTokens = info.promptTokenCount
                promptSeconds = info.promptTime
                cachedPromptTokens = info.cachedPromptTokenCount
                cacheEfficiency = info.cacheEfficiency
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
        managed.historyJSON = messages + [
            Self.assistantToJSON(content: completedText, toolCalls: toolCalls)
        ]
        state.withLock {
            if let current = $0.sessions[executionKey.storageKey], current === managed {
                current.history = managed.history
                current.historyJSON = managed.historyJSON
            }
            $0.lastActivity = Date()
        }

        var log =
            "[MLX] session=\(executionKey.traceKey) messages=\(incoming.count)" +
            " history=\(historyCount) delta=\(deltaCount) reuse=\(reusedSession)"
        if let kvSettings {
            log += " kv=\(kvSettings.strategy ?? "fullPrecision")"
        }
        if let ttft {
            log += String(format: " ttft=%dms", Int(ttft * 1000))
        }
        if let cacheTokensBefore {
            log += " cacheTokens=\(cacheTokensBefore)"
        }
        if let cachedPromptTokens {
            log += " cacheHitTokens=\(cachedPromptTokens)"
        }
        if let cacheEfficiency {
            log += String(format: " cacheEff=%.2f", cacheEfficiency)
        }
        if let promptTokens {
            log += " promptTokens=\(promptTokens)"
        }
        if let promptSeconds {
            log += String(format: " promptTime=%.1fs", promptSeconds)
        }
        if let tokensPerSecond {
            log += String(format: " tps=%.1f", tokensPerSecond)
        }
        if !toolCalls.isEmpty {
            log += " toolCalls=\(toolCalls.count)"
        }
        traceLogger.trace(log)
        return completedText
    }

    public func cancelGeneration(requestId: String) {
        state.withLock { $0.activeRequestTasks[requestId] }?.cancel()
        traceLogger.trace("[CANCEL] r=\(requestId)")
    }

    // MARK: - Session KV Cache Persistence（官方 saveCache / loadPromptCacheSnapshot 透传）

    /// 把某逻辑分支当前会话的官方 KV cache 快照保存到磁盘，
    /// 并写入消息级 transcript sidecar（`<name>.meta.json`）。
    /// cache 文件格式由官方 saveCache 定义，SimiGo 不自定义。
    ///
    /// 与 gate 互斥：保存期间同 Key 的生成请求串行等待。
    /// 返回 cache 文件 URL；transcript sidecar 与其同目录同名（.meta.json）。
    @discardableResult
    public func saveSessionCache(
        agentId: String? = nil,
        sessionId: String,
        logicalBranchId: String = "main",
        to directory: URL
    ) async throws -> URL {
        let key = try AgentExecutionKey.resolve(
            agentId: agentId,
            sessionId: sessionId,
            logicalBranchId: logicalBranchId
        )
        guard let container = state.withLock({ $0.modelContainer }) else {
            throw RuntError.notLoaded
        }
        _ = container

        let gate = gateHolder.withLock { $0 }
        return try await gate.withExclusive(key) {
            guard let managed = state.withLock({ $0.sessions[key.storageKey] }) else {
                throw RuntError.generationFailed(
                    "no live session for \(key.storageKey); nothing to save"
                )
            }
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)

            let baseName = Self.cacheFileName(for: key.storageKey)
            let cacheURL = directory.appendingPathComponent(baseName + ".cachesnapshot")
            let metaURL = directory.appendingPathComponent(baseName + ".meta.json")

            // 未跑过任何生成的会话没有可保存的 cache（官方抛 noCacheAvailable）。
            try await managed.session.saveCache(to: cacheURL)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let metadata = SessionCacheMetadata(
                storageKey: key.storageKey,
                modelId: modelName(from: modelPath),
                savedAt: Date(),
                history: managed.historyJSON
            )
            try encoder.encode(metadata).write(to: metaURL, options: .atomic)

            traceLogger.trace(
                "[MLX] cacheSave session=\(key.traceKey) history=\(managed.historyJSON.count)"
            )
            return cacheURL
        }
    }

    /// 从磁盘恢复官方 KV cache 快照 + transcript sidecar，并注册为该逻辑分支的当前会话
    ///（覆盖同名现存会话）。恢复后的会话处于官方 fragment-continuation 语义：
    /// 客户端下一轮仍传全量对话，SimiGo 按 delta 契约只传新增消息，首 token 即 warm。
    ///
    /// 模型不匹配时拒绝加载（cache 与权重必须同源）。
    public func loadSessionCache(
        agentId: String? = nil,
        sessionId: String,
        logicalBranchId: String = "main",
        config: ModelConfig? = nil,
        from directory: URL
    ) async throws -> SessionCacheMetadata {
        let key = try AgentExecutionKey.resolve(
            agentId: agentId,
            sessionId: sessionId,
            logicalBranchId: logicalBranchId
        )
        guard let container = state.withLock({ $0.modelContainer }) else {
            throw RuntError.notLoaded
        }

        let baseName = Self.cacheFileName(for: key.storageKey)
        let cacheURL = directory.appendingPathComponent(baseName + ".cachesnapshot")
        let metaURL = directory.appendingPathComponent(baseName + ".meta.json")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(
            SessionCacheMetadata.self, from: try Data(contentsOf: metaURL))

        let currentModelId = modelName(from: modelPath)
        guard metadata.modelId == currentModelId else {
            throw RuntError.generationFailed(
                "session cache model mismatch: saved=\(metadata.modelId) current=\(currentModelId)"
            )
        }

        let effective = config ?? baseConfig
        let thinkingDisabled = effective.disableThinking || baseConfig.disableThinking
        let sessionParams: GenerateParameters = try {
            var params = GenerateParameters(
                maxTokens: effective.maxTokens > 0 ? effective.maxTokens : baseConfig.maxTokens,
                maxKVSize: nil,
                temperature: effective.temperature,
                topP: effective.topP,
                topK: effective.topK,
                minP: effective.minP,
                repetitionPenalty: effective.repeatPenalty,
                presencePenalty: effective.presencePenalty
            )
            params.kvCache = try Self.makeKVCacheConfiguration(effective.kvCache)
            return params
        }()

        let gate = gateHolder.withLock { $0 }
        let loadedMetadata = metadata
        try await gate.withExclusive(key) { [weak self] in
            guard let self else { throw RuntError.notLoaded }
            let snapshot = try loadPromptCacheSnapshot(url: cacheURL)
            let session = ChatSession(
                container,
                instructions: nil,
                cache: snapshot.cache,
                state: snapshot.state,
                generateParameters: sessionParams,
                additionalContext: thinkingDisabled ? ["enable_thinking": false] : nil
            )
            let restored = ManagedSession(
                session: session,
                history: Self.makeChatMessages(metadata.history),
                historyJSON: metadata.history
            )
            state.withLock {
                $0.sessions[key.storageKey] = restored
                $0.lastActivity = Date()
            }
            traceLogger.trace(
                "[MLX] cacheLoad session=\(key.traceKey) history=\(metadata.history.count)"
            )
        }
        return loadedMetadata
    }

    func integrationSnapshot() -> (activeRequests: Int, activeGenerations: Int, sessions: Int) {
        state.withLock {
            ($0.activeRequestTasks.count, $0.activeRequestTasks.count, $0.sessions.count)
        }
    }

    static nonisolated func makeChatMessages(_ messages: [JSONValue]) -> [Chat.Message] {
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

        // The OpenAI wire format stringifies `function.arguments`, while the
        // official ToolCall decodes it as an object. Normalize the string form
        // (the object form passes through untouched) before decoding, so
        // client-echoed assistant turns keep their tool calls.
        let normalized = items.map { item -> JSONValue in
            guard case .object(var object) = item,
                  case .object(var function)? = object["function"],
                  case .string(let rawArguments) = function["arguments"],
                  let data = rawArguments.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) else {
                return item
            }
            function["arguments"] = decoded
            object["function"] = .object(function)
            return .object(object)
        }

        guard let data = try? JSONEncoder().encode(normalized),
              let calls = try? JSONDecoder().decode([ToolCall].self, from: data) else {
            return []
        }
        return calls
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

    /// Chat.Message is not Equatable (Tool storage is fileprivate to mlx-swift-lm),
    /// so prefix identity is decided by serialized message signatures.
    private static nonisolated func isPrefix(
        _ prefix: [Chat.Message],
        of full: [Chat.Message]
    ) -> Bool {
        firstPrefixMismatch(prefix, of: full) == nil
    }

    /// Returns the first index where the histories diverge, or nil when
    /// `prefix` is a true prefix of `full`. An out-of-range index means
    /// `prefix` itself is longer than `full`.
    private static nonisolated func firstPrefixMismatch(
        _ prefix: [Chat.Message],
        of full: [Chat.Message]
    ) -> Int? {
        guard prefix.count <= full.count else { return prefix.count }
        for (index, pair) in zip(prefix, full).enumerated()
        where signature(pair.0) != signature(pair.1) {
            return index
        }
        return nil
    }

    /// Maps `KVCacheSettings` onto the official `KVCacheConfiguration`.
    ///
    /// Strategy names map 1:1 to official presets; capacity maps to
    /// `KVCacheConfiguration.Capacity`. Invalid values fail fast — a silently
    /// ignored KV setting would misrepresent what the session will actually do.
    /// Plan changes invalidate the official token ledger, so switching strategy
    /// or capacity costs one full prefill on the next request.
    static nonisolated func makeKVCacheConfiguration(
        _ settings: KVCacheSettings?
    ) throws -> KVCacheConfiguration? {
        guard let settings else { return nil }

        var capacity: KVCacheConfiguration.Capacity?
        if let maxTokens = settings.maxTokens {
            capacity = try KVCacheConfiguration.Capacity(
                maxTokens: maxTokens,
                preservedPrefixTokens: settings.preservedPrefixTokens ?? 4)
        } else if settings.preservedPrefixTokens != nil {
            throw RuntError.generationFailed(
                "kvCache.preservedPrefixTokens requires kvCache.maxTokens"
            )
        }

        let strategy: KVCacheConfiguration.Strategy
        switch settings.strategy ?? "fullPrecision" {
        case "fullPrecision":
            strategy = .fullPrecision
        case "affine4":
            strategy = .affine(.fourBit)
        case "affine8":
            strategy = .affine(.eightBit)
        case "turboQuality":
            strategy = .turboQuant(.qualityFirst)
        case "turboBalanced":
            strategy = .turboQuant(.balanced)
        case "turboMemory":
            strategy = .turboQuant(.memoryFirst)
        default:
            throw RuntError.generationFailed(
                "unknown kvCache.strategy: \(settings.strategy ?? "")" +
                " (supported: fullPrecision, affine4, affine8, turboQuality, turboBalanced, turboMemory)"
            )
        }

        return KVCacheConfiguration(
            capacity: capacity,
            strategy: strategy,
            // 混合注意力模型（如 qwen3_5_moe 的 Mamba 层）不支持量化策略，
            // allowPartial 让受支持的注意力层生效、其余层保持原样，模型仍可用。
            compatibility: .allowPartial)
    }

    /// 把 assistant 回复转成客户端回显形态的 JSON 消息（与 makeChatMessages 互逆），
    /// 用于 transcript sidecar 的持久化与恢复。
    static nonisolated func assistantToJSON(
        content: String,
        toolCalls: [ToolCall]
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "role": .string("assistant"),
            "content": .string(content)
        ]
        if !toolCalls.isEmpty {
            let encoder = JSONEncoder()
            let calls: [JSONValue] = toolCalls.map { call in
                let arguments: JSONValue = (try? encoder.encode(call.function.arguments))
                    .flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
                    ?? .object([:])
                var callObject: [String: JSONValue] = [
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(call.function.name),
                        "arguments": arguments
                    ])
                ]
                if let id = call.id {
                    callObject["id"] = .string(id)
                }
                return .object(callObject)
            }
            object["tool_calls"] = .array(calls)
        }
        return .object(object)
    }

    /// storageKey 含 `/`，作为文件名前先扁平化。
    static nonisolated func cacheFileName(for storageKey: String) -> String {
        storageKey.replacingOccurrences(of: "/", with: "_")
    }

    /// Semantic continuity signature: role + content + tool presence.
    ///
    /// Chat.Message.Tool keeps its payload fileprivate to mlx-swift-lm, so a
    /// deeper comparison is impossible from here — and unnecessary: the client
    /// echoes back what this runtime streamed, and the official token ledger
    /// inside the session reconciles rendered-vs-generated drift. This
    /// signature only decides which session a request continues; any real
    /// divergence surfaces at the first differing text content and is logged
    /// by the prefixMismatch diagnostic.
    private static nonisolated func signature(_ message: Chat.Message) -> String {
        let toolFlag = message.tool == nil ? "-" : "tool"
        return "\(message.role.rawValue)\u{1f}\(message.content)\u{1f}\(toolFlag)"
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

/// KV cache 快照的 transcript sidecar 元数据。
/// cache 文件本身由官方 `saveCache` 定义；本结构只记录 SimiGo 恢复 delta 契约
/// 所需的会话连续性元数据（消息级 transcript），不是 token ledger。
nonisolated public struct SessionCacheMetadata: Codable, Sendable {
    public var storageKey: String
    public var modelId: String
    public var savedAt: Date
    public var history: [JSONValue]

    public init(
        storageKey: String,
        modelId: String,
        savedAt: Date,
        history: [JSONValue]
    ) {
        self.storageKey = storageKey
        self.modelId = modelId
        self.savedAt = savedAt
        self.history = history
    }
}
