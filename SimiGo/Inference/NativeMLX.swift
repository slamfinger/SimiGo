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
        var lastActivity = Date()
        /// P0-5：创建时会话的 KV 配置指纹。配置变更 → 禁止复用旧缓存。
        let kvFingerprint: String?

        init(
            session: ChatSession,
            history: [Chat.Message],
            historyJSON: [JSONValue] = [],
            kvFingerprint: String? = nil
        ) {
            self.session = session
            self.history = history
            self.historyJSON = historyJSON
            self.kvFingerprint = kvFingerprint
        }
    }

    private struct State {
        var modelContainer: ModelContainer?
        var httpServer: HTTPServer?
        var isRunning = false
        var lifecycle: Lifecycle = .stopped
        var lastActivity = Date()
        var sessions: [String: ManagedSession] = [:]
        var modelCapabilityContract: ModelCapabilityContract?
        var activeRequestTasks: [String: Task<GenerationResult, Error>] = [:]
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
    private let toolGovernance = ToolGovernance { line in
        RuntimeTraceLogger.shared.trace(line)
    }

    public var isInProcess: Bool { true }
    public var isGenerating: Bool { state.withLock { !$0.activeRequestTasks.isEmpty } }
    public var isRunning: Bool { state.withLock { $0.isRunning } }

    public init(info: ModelInfo, config: ModelConfig) {
        self.modelPath = info.path
        self.baseConfig = config
        state.withLock {
            $0.modelCapabilityContract = Self.buildCapabilityContract(
                modelPath: info.path
            )
        }
        Memory.memoryLimit = RuntimeTuning.mlxMemoryLimitBytes
        Memory.cacheLimit = RuntimeTuning.mlxCacheLimitBytes
    }

    /// P1-1：从模型仓库 config.json 读声明层（model_type / 上下文长度）。
    private nonisolated static func readDeclaredCapabilities(
        modelPath: String
    ) -> (modelType: String?, contextLength: Int?) {
        guard
            let data = try? Data(
                contentsOf: URL(fileURLWithPath: modelPath)
                    .appendingPathComponent("config.json")
            ),
            let obj = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else { return (nil, nil) }
        let modelType = obj["model_type"] as? String
        let contextLength = (obj["max_position_embeddings"] as? Int)
            ?? (obj["ctxSize"] as? Int)
        return (modelType, contextLength)
    }

    /// P1-1：来源分离解析器——声明 + 实测 + 配置汇成三态契约；
    /// 未实测架构保持 unverified，不反向驱动 Runtime 行为。
    private nonisolated static func buildCapabilityContract(
        modelPath: String
    ) -> ModelCapabilityContract {
        let declared = readDeclaredCapabilities(modelPath: modelPath)
        return ModelCapabilityContract.resolve(
            backend: "NativeMLX",
            modelType: declared.modelType,
            contextLength: declared.contextLength,
            serializeGeneration: RuntimeTuning.serializeGeneration,
            maxKVSize: RuntimeTuning.maxKVSize
        )
    }

    /// P0-3/4/5 后的对外查询入口（HTTPServer capabilitiesProvider 消费）。
    public func capabilityContract() -> ModelCapabilityContract? {
        state.withLock { $0.modelCapabilityContract }
    }

    public func start(_ info: ModelInfo, port: Int) async throws {
        try await lifecycleGate.withLock { [weak self] in
            guard let self else { throw RuntError.notLoaded }
            guard !self.state.withLock({ $0.isRunning }) else { return }

            logMemory("beforeLoad")
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
                    },
                    capabilitiesProvider: { [weak self] in
                        self?.capabilityContract()
                    },
                    baseConfigProvider: { [weak self] in
                        self?.baseConfig ?? ModelConfig()
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
            logMemory("afterLoad")
        }
    }

    public func stop() async {
        await lifecycleGate.withLockVoid { [weak self] in
            guard let self else { return }

            logMemory("beforeUnload")

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

            // P1 memory settle：等待 footprint/MLX 计数回稳（观测，不强制）。
            let settleDeadline = Date().addingTimeInterval(RuntimeTuning.memorySettleTimeoutSeconds)
            var lastFootprint = RuntimeTuning.footprintBytes()
            var stableRounds = 0
            while Date() < settleDeadline, stableRounds < 4 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let fp = RuntimeTuning.footprintBytes()
                stableRounds = fp == lastFootprint ? stableRounds + 1 : 0
                lastFootprint = fp
            }
            logMemory("settled")

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
            traceLogger.trace("[LIFECYCLE] resume_started")
            let resumeBegan = Date()
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
                let elapsedMs = Int(Date().timeIntervalSince(resumeBegan) * 1000)
                traceLogger.trace("[LIFECYCLE] resume_done ms=\(elapsedMs)")
            } catch {
                self.state.withLock {
                    $0.lifecycle = .suspended
                    $0.modelContainer = nil
                }
                traceLogger.trace("[LIFECYCLE] resume_failed err=\(error.localizedDescription)")
                throw RuntError.loadFailed(error.localizedDescription)
            }
        }
    }

    /// 自适应闲置超时（2026-09-13，替代固定 600s）：max(600s 基线, 最贵会话
    /// 重建时长估算 + 60s 容错)。重建时长按 512 档实测吞吐取保守 150 tok/s
    /// 估算（121k 会话闲置 ~14.5 分钟才允许卸载）；小会话维持 600s 基线。
    /// 避免大会话刚闲置满固定阈值即被卸载、下轮再缴全额冷启动税。
    private func adaptiveIdleTimeout() async -> TimeInterval {
        let sessions = state.withLock { Array($0.sessions.values) }
        var maxTokens = 0
        for managed in sessions {
            let tokens = (try? await managed.session.cacheStatus())?.processedTokenCount ?? 0
            maxTokens = max(maxTokens, tokens)
        }
        return max(600, Double(maxTokens) / RuntimeTuning.prefillThroughputFloor + 60)
    }

    public func suspendIfIdle() async -> Bool {
        let idleTimeout = await adaptiveIdleTimeout()
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
                let timeout = await self.adaptiveIdleTimeout()
                let stillEligible = self.state.withLock { state in
                    state.isRunning &&
                    state.modelContainer != nil &&
                    state.activeRequestTasks.isEmpty &&
                    Date().timeIntervalSince(state.lastActivity) >= timeout
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
        requestId: String = "internal-\(UUID().uuidString.prefix(8).lowercased())",
        agentId: String? = nil,
        sessionId: String = "default",
        logicalBranchId: String = "main",
        messages: [JSONValue],
        tools: [JSONValue]?,
        config: ModelConfig,
        onChunk: @escaping @Sendable (String) -> Void,
        onToolCall: @escaping @Sendable (ParsedToolCall) -> Void = { _ in }
    ) async throws -> GenerationResult {
        state.withLock { $0.lastActivity = Date() }
        try await ensureLoaded()

        let executionKey = try AgentExecutionKey.resolve(
            agentId: agentId,
            sessionId: sessionId,
            logicalBranchId: logicalBranchId
        )

        // P0-3 强化：全局生成串行化。gate key 常量化使所有生成跨 session 单飞，
        // 规避 qwen3_5_moe 动态编译架构在并发首次编译时的 mlx 锁互堵
        // （sessions 存储仍用真实 executionKey，仅互斥令牌常量化）。
        let gateExecutionKey = try RuntimeTuning.serializeGeneration
            ? AgentExecutionKey(
                agentId: executionKey.agentId,
                sessionId: "__global_generation__",
                logicalBranchId: executionKey.logicalBranchId
            )
            : executionKey

        let gate = gateHolder.withLock { $0 }
        let task = Task<GenerationResult, Error> { [weak self] in
            guard let self else { throw RuntError.notLoaded }
            return try await gate.withExclusive(gateExecutionKey) {
                // P0-3：QUEUED→RUNNING 由推理层在真正拿到 generation gate 后置位，
                // LC 状态与实际执行一致——排队中的请求保持 QUEUED。
                do {
                    try await RuntimeLifecycleCoordinator.shared.transition(
                        requestID: requestId,
                        to: .running
                    )
                } catch {
                    // 排队期间已被取消：转换非法，按取消处理。
                    throw CancellationError()
                }
                return try await self.generateUsingChatSession(
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
    ) async throws -> GenerationResult {
        guard let container = state.withLock({ $0.modelContainer }) else {
            throw RuntError.notLoaded
        }

        let incoming = Self.makeChatMessages(messages)
        guard !incoming.isEmpty else {
            return GenerationResult(text: "", usage: nil)
        }

        let thinkingDisabled = config.disableThinking || baseConfig.disableThinking
        let kvSettings = config.kvCache ?? baseConfig.kvCache
        let kvConfiguration = try Self.makeKVCacheConfiguration(kvSettings)
        var params = GenerateParameters(
            maxTokens: config.maxTokens > 0 ? config.maxTokens : baseConfig.maxTokens,
            maxKVSize: RuntimeTuning.maxKVSize,
            temperature: config.temperature,
            topP: config.topP,
            topK: config.topK,
            minP: config.minP,
            repetitionPenalty: config.repeatPenalty,
            presencePenalty: config.presencePenalty
        )
        params.kvCache = kvConfiguration
        // 预填进度可见化：每 ≥16k token 一行 trace（引擎按 asyncEval 流水，
        // 数值略超前于 GPU 完成）。
        let prefillLogged = Locked(0)
        params.prefill.progress = { processed, total in
            if processed == total || processed - prefillLogged.value >= 16384 {
                prefillLogged.set(processed)
                RuntimeTraceLogger.shared.trace("[MLX] prefill \(processed)/\(total)")
            }
        }
        let toolSpecs = Self.makeToolSpecs(tools)
        let additionalContext: [String: any Sendable]? = thinkingDisabled ? ["enable_thinking": false] : nil

        let existing = state.withLock { $0.sessions[executionKey.storageKey] }
        let managed: ManagedSession
        let reusedSession: Bool

        let kvFingerprint = kvSettings.map { String(describing: $0) }

        if let existing,
           incoming.count > existing.history.count,
           existing.kvFingerprint == kvFingerprint,
           Self.isPrefix(existing.history, of: incoming) {
            managed = existing
            managed.lastActivity = Date()
            reusedSession = true
        } else {
            // 复用失败判据（2026-09-13 排查「重试全量冷预填死循环」加）：
            // prefix=false 时上方 prefixMismatch 有细节；count/fp 失败此前完全静默，
            // 而重试冷预填 ~600s 恰好卡死在客户端重连阈值上方，必须可见。
            if let existing {
                let countOk = incoming.count > existing.history.count
                let fpOk = existing.kvFingerprint == kvFingerprint
                let prefixOk = Self.isPrefix(existing.history, of: incoming)
                if !countOk || !fpOk || !prefixOk {
                    traceLogger.trace(
                        "[MLX] reuseMiss count=\(countOk) fp=\(fpOk) prefix=\(prefixOk)" +
                        " history=\(existing.history.count) incoming=\(incoming.count)" +
                        " fpHistory=\(existing.kvFingerprint ?? "-") fpIncoming=\(kvFingerprint ?? "-")"
                    )
                }
            }
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
                historyJSON: Array(messages.dropLast()),
                kvFingerprint: kvFingerprint
            )
            reusedSession = false
            state.withLock { $0.sessions[executionKey.storageKey] = managed }
        }

        // P1 会话 LRU：上限外最久未用会话先经官方 clear() 释放 KV（锁外执行）。
        await evictSessionsIfNeeded(keeping: executionKey.storageKey)

        let delta: [Chat.Message]
        if reusedSession {
            delta = Array(incoming.dropFirst(managed.history.count))
        } else {
            delta = incoming.last.map { [$0] } ?? []
        }

        guard !delta.isEmpty else { return GenerationResult(text: "", usage: nil) }

        // P1-3 ③：function_call_output ingestion——只观测本轮新增的 tool 消息。
        // 历史结果在各自轮次首次到达时已观测过，全量重放只会刷 unknown_tc 噪音
        // （2026-09-13 实测 110k 会话每轮 52-60 条，淹没 trace）。新增 tool 消息
        // 命中已派发 invocation → TOOL_RESULT（observed result，外部执行回传）；
        // 未命中/重复/非法状态 → anomaly（不伪造成功）。
        let newMessageStart = reusedSession
            ? managed.historyJSON.count
            : max(messages.count - 1, 0)

        let cacheTokensBefore = (try? await managed.session.cacheStatus())?
            .processedTokenCount

        // 预填步长按本轮最终上下文规模选档（阶梯实测见 RuntimeTuning）。
        // 顺序关键：GenerateParameters 是值类型，stepSize 必须在赋给
        // managed.session 之前选定，否则选档永远不生效（9d2c521 回归）。
        // 复用会话规模 = 既有缓存 + delta 字节/4；全新会话 = 全量字节/4
        // （只按 delta 估会让全新 121k 会话误选 2048 档，正是换页抖动配置）。
        var deltaBytes = 0
        for value in messages.dropFirst(newMessageStart) {
            guard case .object(let obj) = value else { continue }
            deltaBytes += obj["content"]?.string?.utf8.count ?? 0
        }
        let contextEstimate: Int
        if reusedSession {
            contextEstimate = (cacheTokensBefore ?? 0) + deltaBytes / 4
        } else {
            var incomingBytes = 0
            for value in messages {
                guard case .object(let obj) = value else { continue }
                incomingBytes += obj["content"]?.string?.utf8.count ?? 0
            }
            contextEstimate = incomingBytes / 4
        }
        params.prefill.stepSize = RuntimeTuning.prefillStepSize(
            contextTokens: contextEstimate
        )

        managed.session.generateParameters = params
        managed.session.tools = toolSpecs
        managed.session.additionalContext = additionalContext

        for value in messages.dropFirst(newMessageStart) {
            guard case .object(let obj) = value,
                  (obj["role"]?.string ?? "").lowercased() == "tool",
                  let toolCallId = obj["tool_call_id"]?.string else { continue }
            let size = obj["content"]?.string?.utf8.count
            toolGovernance.resultObserved(
                requestId: requestId,
                generationId: requestId,
                toolCallId: toolCallId,
                sizeBytes: size
            )
        }

        let historyCount = managed.history.count
        let deltaCount = delta.count
        let streamStart = Date()
        var ttft: TimeInterval?

        var completedText = ""
        var toolCalls: [ToolCall] = []
        let filter = StreamTokenFilter(disableThinking: thinkingDisabled)
        var tokensPerSecond: Double?
        var promptTokens: Int?
        var generationTokens: Int?
        var promptSeconds: Double?
        var cachedPromptTokens: Int?
        var cacheEfficiency: Double?
        // 解码可见性诊断（2026-09-13）：流实际产出 vs filter 放行。
        // rawB 大而 emitB=0 ⇒ 模型在长思考、输出被整段吞掉——客户端看到
        // 的就是数百秒零事件静默（e155f1 实测 601s）。
        var rawEventCount = 0
        var rawChunkBytes = 0
        var emittedChunkBytes = 0

        for try await generation in managed.session.streamDetails(to: delta) {
            switch generation {
            case .chunk(let text):
                rawEventCount += 1
                rawChunkBytes += text.utf8.count
                ttft = ttft ?? Date().timeIntervalSince(streamStart)
                filter.feed(text) { chunk in
                    emittedChunkBytes += chunk.utf8.count
                    completedText.append(chunk)
                    onChunk(chunk)
                }
            case .toolCall(let call):
                rawEventCount += 1
                ttft = ttft ?? Date().timeIntervalSince(streamStart)
                let normalizedCall = ToolCall(
                    function: call.function,
                    id: call.id ?? UUID().uuidString
                )
                toolCalls.append(normalizedCall)

                let callId = normalizedCall.id ?? ""
                let argumentsRaw = (try? JSONEncoder().encode(normalizedCall.function.arguments))
                    .flatMap { String(data: $0, encoding: .utf8) }
                let arguments: [String: JSONValue]
                if let data = try? JSONEncoder().encode(normalizedCall.function.arguments),
                   let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data) {
                    arguments = decoded
                } else {
                    arguments = [:]
                }

                // P1-3 ①：REQUESTED → VALIDATED；invalid → REJECTED(invalid_arguments)。
                // 失败分支不进入 onToolCall。
                toolGovernance.requested(
                    requestId: requestId,
                    generationId: requestId,
                    toolCallId: callId,
                    tool: normalizedCall.function.name,
                    argumentsRaw: argumentsRaw
                )
                let argumentsValid = !arguments.isEmpty
                if argumentsValid {
                    toolGovernance.validated(
                        requestId: requestId,
                        generationId: requestId,
                        toolCallId: callId
                    )
                } else {
                    toolGovernance.rejected(
                        requestId: requestId,
                        generationId: requestId,
                        toolCallId: callId,
                        code: .invalidArguments,
                        message: "arguments is not a JSON object"
                    )
                }

                if argumentsValid {
                    onToolCall(
                        ParsedToolCall(
                            id: normalizedCall.id ?? "",
                            name: normalizedCall.function.name,
                            arguments: arguments
                        )
                    )
                }
            case .rejectedToolCall(let rejection):
                rawEventCount += 1
                // P1-3 ②：backend observation（undeclared_tool）→ Runtime 映射
                // → REJECTED(unknown_tool)。官方拒绝无 tool_call identity，
                // tool_call_id 由 Runtime 生成（契约允许）。
                let rejectedCallId = "rtc-rejected-\(UUID().uuidString.lowercased())"
                let rejectedTool = rejection.toolName ?? "-"
                toolGovernance.requested(
                    requestId: requestId,
                    generationId: requestId,
                    toolCallId: rejectedCallId,
                    tool: rejectedTool,
                    argumentsRaw: nil
                )
                toolGovernance.validated(
                    requestId: requestId,
                    generationId: requestId,
                    toolCallId: rejectedCallId
                )
                toolGovernance.rejected(
                    requestId: requestId,
                    generationId: requestId,
                    toolCallId: rejectedCallId,
                    code: .unknownTool,
                    message: "upstream rejectedToolCall reason=\(rejection.reason.rawValue)"
                )
                traceLogger.trace(
                    "[MLX] rejectedToolCall reason=\(rejection.reason.rawValue) tool=\(rejection.toolName ?? "-")"
                )
            case .info(let info):
                tokensPerSecond = info.tokensPerSecond
                promptTokens = info.promptTokenCount
                promptSeconds = info.promptTime
                generationTokens = info.generationTokenCount
                cachedPromptTokens = info.cachedPromptTokenCount
                cacheEfficiency = info.cacheEfficiency
            }
        }

        filter.flush { chunk in
            completedText.append(chunk)
            onChunk(chunk)
        }

        // 铁律 10：取消不得产生有效提交。mlx-swift-lm 的流在所属 task 被取消时
        // 正常结束而非抛 CancellationError（2026-09-13 01:18 实测）：若照常提交，
        // incoming + 空 assistant 会写入 managed.history，此后同一会话的每个重试
        // 请求 count=false → 复用失败 → 每次多付 ~625s 全量冷预填。
        // 残余竞态窗口：流在 cancel 落地前瞬间自然结束——无法在会话层根除，已收窄。
        if Task.isCancelled {
            traceLogger.trace(
                "[MLX] cancelCommitSkip session=\(executionKey.traceKey)" +
                " history=\(managed.history.count)" +
                " rawEv=\(rawEventCount) rawB=\(rawChunkBytes) emitB=\(emittedChunkBytes)"
            )
            throw CancellationError()
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
                current.lastActivity = Date()
            }
            $0.lastActivity = Date()
        }

        // P1 会话 LRU 扫描：生成收尾后驱动驱逐。
        await evictSessionsIfNeeded(keeping: executionKey.storageKey)

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
        log += " rawEv=\(rawEventCount) rawB=\(rawChunkBytes) emitB=\(emittedChunkBytes)"
        traceLogger.trace(log)
        let usage: GenerationUsageReport? = (promptTokens != nil && generationTokens != nil)
            ? GenerationUsageReport(
                promptTokens: promptTokens!,
                generationTokens: generationTokens!,
                cachedPromptTokens: cachedPromptTokens,
                cacheEfficiency: cacheEfficiency,
                ttftSeconds: ttft,
                tokensPerSecond: tokensPerSecond
            )
            : nil
        return GenerationResult(text: completedText, usage: usage)
    }

    /// P1 会话 LRU：上限外最久未用会话先经官方 clear() 释放 KV（锁外执行），再回收缓冲。
    private func evictSessionsIfNeeded(keeping currentKey: String) async {
        let victims: [(key: String, session: ChatSession)] = state.withLock { state in
            guard state.sessions.count > RuntimeTuning.sessionLimit else { return [] }
            let removeCount = state.sessions.count - RuntimeTuning.sessionLimit
            guard removeCount > 0 else { return [] }
            let sorted = state.sessions
                .filter { $0.key != currentKey }
                .sorted { $0.value.lastActivity < $1.value.lastActivity }
            let victims = sorted.prefix(removeCount).map { (key: $0.key, session: $0.value.session) }
            for (key, _) in victims { state.sessions.removeValue(forKey: key) }
            return victims
        }
        guard !victims.isEmpty else { return }

        for (_, session) in victims { await session.clear() }
        Memory.clearCache()
        traceLogger.trace(
            "[MEM] session LRU evicted=\(victims.count)" +
            " keys=" + victims.map { String($0.key.suffix(6)) }.joined(separator: ",") +
            " limit=\(RuntimeTuning.sessionLimit)"
        )
        logMemory("afterEvict")
    }

    /// P1 Unified Memory 遥测：MLX 计数器 + footprint + swap。
    private nonisolated func logMemory(_ phase: String) {
        let active = max(0, Memory.activeMemory)
        let cache = max(0, Memory.cacheMemory)
        let peak = max(0, Memory.peakMemory)
        let line = RuntimeTuning.memorySnapshotLine(
            activeBytes: active,
            cacheBytes: cache,
            peakBytes: peak
        )
        traceLogger.trace("[MEM] \(phase) " + line)
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
                maxKVSize: RuntimeTuning.maxKVSize,
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
