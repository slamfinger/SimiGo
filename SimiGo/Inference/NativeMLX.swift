import Foundation
import CryptoKit
import Network
import Synchronization
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers
import Darwin

// (The rest of the file is unchanged)

private nonisolated struct RuntimeMemorySnapshot: Sendable {
    let residentBytes: UInt64
    let virtualBytes: UInt64
    let swapUsedBytes: UInt64?
    let swapTotalBytes: UInt64?
    let swapFreeBytes: UInt64?

    var residentGB: Double { Double(residentBytes) / 1024.0 / 1024.0 / 1024.0 }
    var virtualGB: Double { Double(virtualBytes) / 1024.0 / 1024.0 / 1024.0 }

    var swapUsedGB: Double? {
        guard let value = swapUsedBytes else { return nil }
        return Double(value) / 1024.0 / 1024.0 / 1024.0
    }

    var swapTotalGB: Double? {
        guard let value = swapTotalBytes else { return nil }
        return Double(value) / 1024.0 / 1024.0 / 1024.0
    }

    var swapFreeGB: Double? {
        guard let value = swapFreeBytes else { return nil }
        return Double(value) / 1024.0 / 1024.0 / 1024.0
    }
}

private nonisolated enum RuntimeMemoryProbe {
    static func snapshot() -> RuntimeMemorySnapshot {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { buffer in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), buffer, &count)
            }
        }

        let residentBytes: UInt64
        let virtualBytes: UInt64

        if result == KERN_SUCCESS {
            residentBytes = UInt64(info.resident_size)
            virtualBytes = UInt64(info.virtual_size)
        } else {
            residentBytes = 0
            virtualBytes = 0
        }

        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size

        let swapResult = sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0)
        if swapResult == 0 {
            return RuntimeMemorySnapshot(
                residentBytes: residentBytes,
                virtualBytes: virtualBytes,
                swapUsedBytes: UInt64(swapUsage.xsu_used),
                swapTotalBytes: UInt64(swapUsage.xsu_total),
                swapFreeBytes: UInt64(swapUsage.xsu_avail)
            )
        }

        return RuntimeMemorySnapshot(
            residentBytes: residentBytes,
            virtualBytes: virtualBytes,
            swapUsedBytes: nil,
            swapTotalBytes: nil,
            swapFreeBytes: nil
        )
    }
}

public final class NativeMLX: Runtime, @unchecked Sendable {
    private static let gibibyte = RuntimeTuning.gibibyte
    /// 调优常量集中定义于 RuntimeTuning（白皮书出处见该文件注释）。
    private static let inferenceMemoryLimit = RuntimeTuning.admissionMemoryLimitBytes
    private static let inferenceCacheLimit = RuntimeTuning.mlxCacheLimitBytes
    /// 权重感知预算下的 OS + App 基线预留（白皮书 §30，铁律 63 校准项）。
    private static let osReserveBytes = RuntimeTuning.osReserveBytes
    private static let maxPhysicalKVRevisions = RuntimeTuning.maxPhysicalKVRevisions
    private static let longContextThreshold = RuntimeTuning.longContextThreshold
    private static let sessionMaxIdleTime = RuntimeTuning.sessionMaxIdleSeconds
    private static let prefillStepSize = RuntimeTuning.prefillChunkSize

    /// 量取模型权重文件体积，用于权重感知的 KV 预算（铁律 63：参数须有实测依据）。
    /// HF hub 的 snapshot 内是指向 blobs 的符号链接：必须 resolve 后量取，
    /// 否则量到的是链接本身（~几十字节），实测 weights=0.0GB（日志 2026-09-05 02:04）。
    private static func measureWeightsBytes(atPath path: String) -> UInt64 {
        let fileManager = FileManager.default
        var totalBytes: UInt64 = 0

        guard let enumerator = fileManager.enumerator(atPath: path) else {
            return 0
        }

        for case let file as String in enumerator {
            let isWeightFile =
                file.hasSuffix(".safetensors") ||
                file.hasSuffix(".npz") ||
                file.hasSuffix(".gguf")

            guard isWeightFile else { continue }

            let resolvedPath = URL(fileURLWithPath: path)
                .appendingPathComponent(file)
                .resolvingSymlinksInPath()
                .path

            let attributes = try? fileManager.attributesOfItem(atPath: resolvedPath)

            totalBytes += (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        }

        return totalBytes
    }

    private struct State {
        var modelContainer: ModelContainer?
        var isRunning = false
        var isGenerating = false
        var generatingSessions: Set<String> = []
        var httpServer: HTTPServer?
        var sessionCaches: [String: SessionLogicalState] = [:]
        var physicalRevisions: [PhysicalKVRevision] = []
        var activeRequestTasks: [String: Task<String, Error>] = [:]
        var activeGenerationTasks: [String: Task<Void, Never>] = [:]
        var peakActiveRequests = 0
        var peakActiveGenerationTasks = 0
        var peakResidentBytes: UInt64 = 0
        var peakSwapUsedBytes: UInt64 = 0
    }

    private let state = Mutex(State())
    private let modelPath: String
    private let modelWeightsBytes: UInt64
    private let baseConfig: ModelConfig
    private let lifecycleGate = RuntimeLifecycleGate()
    private let gateHolder = Mutex(SessionGenerationGate())
    private let prefillScheduler = PrefillScheduler()
    private let traceLogger = RuntimeTraceLogger.shared

    // MARK: - Observability

    private nonisolated func emitRuntimeObservation(
        _ label: String,
        requestId: String? = nil,
        executionKey: AgentExecutionKey? = nil
    ) {
        let memory = RuntimeMemoryProbe.snapshot()

        let runtime = state.withLock { state in
            let revisionTokens = state.physicalRevisions.map { $0.physicalTokens.count }

            return (
                activeRequests: state.activeRequestTasks.count,
                activeGenerations: state.activeGenerationTasks.count,
                generatingSessions: state.generatingSessions.count,
                revisions: state.physicalRevisions.count,
                revisionTokens: revisionTokens,
                sessions: state.sessionCaches.count
            )
        }

        state.withLock { state in
            state.peakActiveRequests = max(state.peakActiveRequests, runtime.activeRequests)
            state.peakActiveGenerationTasks = max(state.peakActiveGenerationTasks, runtime.activeGenerations)
            state.peakResidentBytes = max(state.peakResidentBytes, memory.residentBytes)

            if let swap = memory.swapUsedBytes {
                state.peakSwapUsedBytes = max(state.peakSwapUsedBytes, swap)
            }
        }

        let visible: Set<String> = [
            "runtime-start-preload",
            "request-admitted",
            "generation-start",
            "cancel-request-issued",
            "cancelled",
            "request-complete",
            "shutdown-begin",
            "shutdown-after-drain",
            "shutdown-after-kv-release",
            "shutdown-after-memory-clear"
        ]

        guard visible.contains(label) else { return }

        let labelMap: [String: String] = [
            "runtime-start-preload": "start",
            "request-admitted": "admit",
            "generation-start": "gen",
            "cancel-request-issued": "cancel",
            "cancelled": "cancelled",
            "request-complete": "done",
            "shutdown-begin": "stop",
            "shutdown-after-drain": "drain",
            "shutdown-after-kv-release": "kvfree",
            "shutdown-after-memory-clear": "memfree"
        ]

        let phase = labelMap[label] ?? label
        let rid = requestId.map { String($0.replacingOccurrences(of: "req-", with: "").prefix(6)) }
        let req = rid.map { "r=\($0)" } ?? ""

        let revSummary = runtime.revisionTokens.isEmpty
            ? "-"
            : runtime.revisionTokens.map(compactTokenCount).joined(separator: ",")

        let swap: String

        if let used = memory.swapUsedGB, let total = memory.swapTotalGB {
            swap = String(format: "sw=%.2f/%.2fG", used, total)
        } else {
            swap = "sw=?"
        }

        let sessionPart: String

        if let executionKey {
            let raw = executionKey.sessionId
            let short = raw.contains("anon_")
                ? String(raw.split(separator: "_").last.map(String.init)?.prefix(6) ?? raw.suffix(6))
                : String(raw.suffix(6))

            sessionPart = "s=\(short) br=\(executionKey.logicalBranchId)"
        } else {
            sessionPart = ""
        }

        let memoryLine = "[MEM] p=\(phase)" +
            (req.isEmpty ? "" : " \(req)") +
            (sessionPart.isEmpty ? "" : " \(sessionPart)") +
            String(format: " rss=%.2fG vm=%.2fG", memory.residentGB, memory.virtualGB) +
            " \(swap)" +
            " q=\(runtime.activeRequests)/\(runtime.activeGenerations)" +
            " sess=\(runtime.sessions)" +
            " rev=\(runtime.revisions)" +
            " ktok=\(revSummary)"

        traceLogger.trace(memoryLine, session: executionKey?.traceKey)
    }

    private nonisolated func emitObservationSummary() {
        let memory = RuntimeMemoryProbe.snapshot()

        let stats = state.withLock { state in
            let revisionTokens = state.physicalRevisions.map { $0.physicalTokens.count }

            return (
                activeRequests: state.activeRequestTasks.count,
                activeGenerations: state.activeGenerationTasks.count,
                revisions: state.physicalRevisions.count,
                revisionTokens: revisionTokens,
                peakActiveRequests: state.peakActiveRequests,
                peakActiveGenerations: state.peakActiveGenerationTasks,
                peakResidentBytes: state.peakResidentBytes,
                peakSwapUsedBytes: state.peakSwapUsedBytes
            )
        }

        let peakResidentGB = Double(stats.peakResidentBytes) / 1024.0 / 1024.0 / 1024.0
        let peakSwapGB = Double(stats.peakSwapUsedBytes) / 1024.0 / 1024.0 / 1024.0

        let revisionSummary = stats.revisionTokens.isEmpty
            ? "-"
            : stats.revisionTokens.map(compactTokenCount).joined(separator: ",")

        let currentSwap = memory.swapUsedGB.map { String(format: "%.2fG", $0) } ?? "?"

        traceLogger.trace(
            String(
                format: "[SUM] q=%d/%d rev=%d ktok=%@ peakRSS=%.2fG peakSW=%.2fG rss=%.2fG sw=%@",
                stats.activeRequests,
                stats.activeGenerations,
                stats.revisions,
                revisionSummary,
                peakResidentGB,
                peakSwapGB,
                memory.residentGB,
                currentSwap
            )
        )
    }

    // MARK: Runtime Conformance

    public var isInProcess: Bool { true }
    public var isGenerating: Bool { state.withLock { $0.isGenerating || !$0.generatingSessions.isEmpty } }
    public var isRunning: Bool { state.withLock { $0.isRunning } }

    public init(info: ModelInfo, config: ModelConfig) {
        self.modelPath = info.path
        self.modelWeightsBytes = Self.measureWeightsBytes(atPath: info.path)
        self.baseConfig = config

        Memory.memoryLimit = Self.inferenceMemoryLimit
        Memory.cacheLimit = Self.inferenceCacheLimit

        let weightsGB = Double(modelWeightsBytes) / Double(Self.gibibyte)
        traceLogger.trace(
            "Init NativeMLX Runtime: memoryLimit=22GB, cacheLimit=4GB, weights=\(String(format: "%.1f", weightsGB))GB, prefillStepSize=\(Self.prefillStepSize), " +
            "maxPhysicalKVRevisions=\(Self.maxPhysicalKVRevisions), logicalSessionEviction=TTL(\(Int(Self.sessionMaxIdleTime))s), modelPath=\(info.path)"
        )
    }

    // MARK: Lifecycle

    public func start(_ info: ModelInfo, port: Int) async throws {
        try await lifecycleGate.withLock { [weak self] in
            guard let self else {
                throw RuntError.notLoaded
            }

            guard !self.state.withLock({ $0.isRunning }) else {
                return
            }

            let oldRevisions = self.state.withLock { state -> [PhysicalKVRevision] in
                let revisions = state.physicalRevisions

                state.physicalRevisions.removeAll()
                state.sessionCaches.removeAll()
                state.generatingSessions.removeAll()

                return revisions
            }

            if !oldRevisions.isEmpty {
                await MainActor.run {
                    for var revision in oldRevisions {
                        revision.releasePhysicalMemory()
                    }
                }
            }

            Memory.clearCache()
            self.emitRuntimeObservation("runtime-start-preload")
            self.gateHolder.withLock { $0 = SessionGenerationGate() }
            self.traceLogger.reset()

            Service.log("🚀 [NativeMLX] 正在加载本地模型: \(info.path)")
            self.traceLogger.trace("Loading model container from \(info.path)")

            do {
                let modelURL = URL(fileURLWithPath: info.path)

                let container = try await LLMModelFactory.shared.loadContainer(
                    from: modelURL,
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

                        return InferenceNodeConfiguration.shared.snapshot()
                    }

                    return current
                }

                let server = await MainActor.run {
                    HTTPServer(
                        port: nodeConfiguration.port,
                        modelId: modelId,
                        bindHost: nodeConfiguration.bindHost,
                        bonjourEnabled: nodeConfiguration.bonjourEnabled,
                        generateHandler: { [weak self] rid, agent, sess, branch, msgs, tools, cfg, onChunk, onToolCall in
                            guard let self else { return "" }

                            return try await self.generate(
                                requestId: rid,
                                agentId: agent,
                                sessionId: sess,
                                logicalBranchId: branch,
                                messages: msgs,
                                tools: tools,
                                config: cfg,
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

                try await MainActor.run {
                    try server.start()
                }

                self.state.withLock {
                    $0.modelContainer = container
                    $0.isRunning = true
                    $0.isGenerating = false
                    $0.httpServer = server
                    $0.sessionCaches.removeAll()
                    $0.physicalRevisions.removeAll()
                    $0.generatingSessions.removeAll()
                }

                self.traceLogger.trace(
                    "Model ready on port \(nodeConfiguration.port), bindHost=\(nodeConfiguration.bindHost), modelId=\(modelId)"
                )

                Service.log(
                    "✅ [NativeMLX] 原生模型已就绪 (Model ID: \(modelId), Port: \(nodeConfiguration.port), Bind: \(nodeConfiguration.bindHost))"
                )
            } catch {
                self.traceLogger.trace("Model load failed: \(error.localizedDescription)")
                throw RuntError.loadFailed(error.localizedDescription)
            }
        }
    }

    public func stop() async {
        await lifecycleGate.withLockVoid { [weak self] in
            guard let self else { return }

            self.emitRuntimeObservation("shutdown-begin")

            let (server, requestTasks, generationTasks, gate) = self.state.withLock { state in
                let server = state.httpServer
                let requestTasks = Array(state.activeRequestTasks.values)
                let generationTasks = Array(state.activeGenerationTasks.values)
                let gate = self.gateHolder.withLock { $0 }

                state.httpServer = nil
                state.isRunning = false
                state.isGenerating = false
                state.generatingSessions.removeAll()

                return (server, requestTasks, generationTasks, gate)
            }

            if let server {
                await MainActor.run {
                    server.stop()
                }
            }

            await self.prefillScheduler.cancelAll()
            await gate.beginShutdown()

            for task in requestTasks {
                task.cancel()
            }

            for task in generationTasks {
                task.cancel()
            }

            for task in requestTasks {
                _ = try? await task.value
            }

            for task in generationTasks {
                await task.value
            }

            await gate.awaitDrain()
            self.emitRuntimeObservation("shutdown-after-drain")

            let revisions = self.state.withLock { state -> [PhysicalKVRevision] in
                let revisions = state.physicalRevisions

                state.physicalRevisions.removeAll()
                state.sessionCaches.removeAll()
                state.generatingSessions.removeAll()
                state.modelContainer = nil

                return revisions
            }

            if !revisions.isEmpty {
                await MainActor.run {
                    for var revision in revisions {
                        revision.releasePhysicalMemory()
                    }
                }
            }

            self.emitRuntimeObservation("shutdown-after-kv-release")

            Memory.clearCache()
            self.emitRuntimeObservation("shutdown-after-memory-clear")
            self.emitObservationSummary()

            Service.log("🛑 [NativeMLX] 模型已物理卸载，Task + Scheduler + Gate + Global KV 已完成最终一致性清扫")
            self.traceLogger.trace("NativeMLX runtime stopped and memory cleared (Two-Phase Teardown complete).")
            self.traceLogger.flush()
        }
    }

    public func checkHealth() async -> Bool {
        state.withLock { $0.isRunning && $0.modelContainer != nil }
    }

    // MARK: Inference Entry

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
        let executionKey = try AgentExecutionKey.resolve(
            agentId: agentId,
            sessionId: sessionId,
            logicalBranchId: logicalBranchId
        )

        let gate = gateHolder.withLock { $0 }

        traceLogger.trace(
            "[REQ] request=\(requestId) a=\(executionKey.agentId) s=\(executionKey.sessionId) br=\(executionKey.logicalBranchId)",
            session: executionKey.traceKey
        )

        emitRuntimeObservation(
            "request-admitted",
            requestId: requestId,
            executionKey: executionKey
        )

        let gateWaitStart = Date()

        let task: Task<String, Error> = Task { [weak self] in
            guard let self else {
                throw RuntError.notLoaded
            }

            return try await gate.withExclusive(executionKey) {
                let gateWait = max(Date().timeIntervalSince(gateWaitStart), 0)

                self.traceLogger.trace(
                    "[GATE] request=\(requestId) wait=\(String(format: "%.1f", gateWait * 1000))ms",
                    session: executionKey.traceKey
                )

                await MainActor.run {
                    self.emitRuntimeObservation(
                        "generation-gate-granted",
                        requestId: requestId,
                        executionKey: executionKey
                    )
                }

                return try await self.generateAfterGate(
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

        state.withLock { state in
            state.activeRequestTasks[requestId] = task
            state.peakActiveRequests = max(state.peakActiveRequests, state.activeRequestTasks.count)
        }

        defer {
            _ = state.withLock {
                $0.activeRequestTasks.removeValue(forKey: requestId)
            }

            emitRuntimeObservation(
                "request-task-removed",
                requestId: requestId,
                executionKey: executionKey
            )

            // Invariant 1 观测：真实任务收尾回报给生命周期账本
            Task {
                await RuntimeLifecycleCoordinator.shared.noteRequestTaskEnded(
                    requestID: requestId
                )
            }
        }

        return try await withTaskCancellationHandler(
            operation: {
                try await task.value
            },
            onCancel: {
                task.cancel()
            }
        )
    }

    // MARK: Generation Core

    private func generateAfterGate(
        requestId: String,
        executionKey: AgentExecutionKey,
        messages: [JSONValue],
        tools: [JSONValue]?,
        config: ModelConfig,
        onChunk: @escaping @Sendable (String) -> Void,
        onToolCall: @escaping @Sendable (ParsedToolCall) -> Void
    ) async throws -> String {
        let t0 = Date()
        let sessionKey = executionKey.storageKey
        let targetLogicalBranchId = executionKey.logicalBranchId
        let traceSession = executionKey.traceKey

        guard !Task.isCancelled else {
            throw CancellationError()
        }

        let proceed = state.withLock { state -> Bool in
            guard state.isRunning, state.modelContainer != nil else {
                return false
            }

            state.generatingSessions.insert(sessionKey)
            purgeStaleSessionCachesLocked(&state)

            return true
        }

        guard proceed else {
            throw RuntError.notLoaded
        }

        defer {
            _ = state.withLock {
                $0.generatingSessions.remove(sessionKey)
            }
        }

        guard let container = state.withLock({ $0.modelContainer }) else {
            throw RuntError.notLoaded
        }

        // MARK: Message Normalization

        var messagesAny: [[String: Any]] = []
        var systemMerged = false
        var sawNonSystemPrefix = false

        for value in messages {
            guard case .object(let dict) = value else { continue }

            var message = dict.mapValues {
                $0.toAny()
            }

            if let rawCalls = message["tool_calls"] {
                let normalizedCalls = try normalizedHistoricalToolCalls(rawCalls)

                if normalizedCalls.isEmpty {
                    message.removeValue(forKey: "tool_calls")
                } else {
                    message["tool_calls"] = normalizedCalls
                }
            }

            let hasToolCalls = (message["tool_calls"] as? [[String: Any]])?.isEmpty == false
            let role = (message["role"] as? String) ?? "user"

            if let content = message["content"] {
                let normalizedContent = coerceContentToString(content)

                if hasToolCalls && normalizedContent.isEmpty {
                    message.removeValue(forKey: "content")
                } else {
                    message["content"] = normalizedContent
                }
            } else if !hasToolCalls && role != "assistant" {
                message["content"] = ""
            }

            let isSystemLike = role == "system" || role == "developer"

            if isSystemLike && !sawNonSystemPrefix {
                let body = (message["content"] as? String) ?? ""

                if !systemMerged {
                    message["role"] = "system"
                    messagesAny.append(message)
                    systemMerged = true
                } else if !body.isEmpty, let base = messagesAny.first?["content"] as? String {
                    messagesAny[0]["content"] = base + "\n\n" + body
                }

                continue
            }

            sawNonSystemPrefix = true

            if isSystemLike || !["user", "assistant", "tool"].contains(role) {
                message["role"] = "user"
            }

            messagesAny.append(message)
        }

        // MARK: Parameters

        let thinkingDisabled = config.disableThinking || baseConfig.disableThinking
        let requestedMaxTokens = config.maxTokens > 0 ? config.maxTokens : (baseConfig.maxTokens > 0 ? baseConfig.maxTokens : 4096)
        let maxTokens = min(requestedMaxTokens, 4096)
        let temperature = config.temperature != 0.0 ? config.temperature : baseConfig.temperature
        let topP = config.topP != 0.0 ? config.topP : (baseConfig.topP != 0.0 ? baseConfig.topP : 1.0)
        let topK = config.topK != 0 ? config.topK : baseConfig.topK
        let minP = config.minP != 0.0 ? config.minP : baseConfig.minP
        let repeatPenalty = config.repeatPenalty != 0.0 ? config.repeatPenalty : baseConfig.repeatPenalty
        let presencePenalty = config.presencePenalty != 0.0 ? config.presencePenalty : baseConfig.presencePenalty

        let params = GenerateParameters(
            maxTokens: maxTokens,
            maxKVSize: nil,
            temperature: Float(temperature),
            topP: topK > 0 ? 1.0 : Float(topP),
            topK: topK,
            minP: minP,
            repetitionPenalty: repeatPenalty,
            presencePenalty: presencePenalty,
            prefillStepSize: Self.prefillStepSize
        )

        let toolsAny = makeToolSpecs(tools)
        let additionalContext: [String: Any]? = thinkingDisabled ? ["enable_thinking": false] : nil
        let userInput = UserInput(
            messages: messagesAny,
            tools: toolsAny,
            additionalContext: additionalContext
        )

        traceLogger.trace(
            "[INF] m=\(messagesAny.count) tools=\(toolsAny?.count ?? 0) thinkOff=\(thinkingDisabled) max=\(maxTokens)",
            session: traceSession
        )

        // MARK: Official Prompt Preparation

        let lmInput = try await container.prepare(input: userInput)
        let allPromptTokens = lmInput.text.tokens.asArray(Int.self)

        guard !allPromptTokens.isEmpty else {
            traceLogger.trace("⚠️ Tokenization produced 0 tokens, aborting.", session: traceSession)
            return ""
        }

        let effectiveContextDemand = allPromptTokens.count + maxTokens
        let runtimeSafetyContextBudget = max(1024, config.ctxSize)

        guard effectiveContextDemand <= runtimeSafetyContextBudget else {
            traceLogger.trace(
                "[CONTEXT SAFETY REJECT] demand=\(effectiveContextDemand), budget=\(runtimeSafetyContextBudget), action=require_L1_compaction",
                session: traceSession
            )

            throw NativeMLXValidationError.contextDemandExceeded(
                effectiveContextDemand,
                runtimeSafetyContextBudget
            )
        }

        guard !Task.isCancelled else {
            throw CancellationError()
        }

        // MARK: Tool Fingerprint + Semantic Progress

        let toolFingerprint = makeToolFingerprint(toolsAny)
        let semanticProgressHash = computeSemanticProgressHash(messagesAny)

        let logicalStateReleases = state.withLock { state -> [PhysicalKVRevision] in
            var session = state.sessionCaches[sessionKey] ?? SessionLogicalState()

            if session.logicalBranches[targetLogicalBranchId] == nil {
                session.logicalBranches[targetLogicalBranchId] = LogicalBranchState(
                    logicalBranchId: targetLogicalBranchId,
                    toolFingerprint: toolFingerprint
                )
            }

            if var logical = session.logicalBranches[targetLogicalBranchId] {
                logical.toolFingerprint = toolFingerprint
                logical.lastActive = Date()
                session.logicalBranches[targetLogicalBranchId] = logical
            }

            session.lastActive = Date()
            state.sessionCaches[sessionKey] = session

            return []
        }

        _ = logicalStateReleases

        var selectedBranch: PhysicalKVRevision?
        var selectedIndex = -1
        var selectedCommonLen = 0
        var selectedRawCommonLen = 0
        var sawUsableBranch = false
        var sawToolFingerprintMismatch = false
        var activeKVCacheFromPrefix: [any KVCache]?
        // LAN 深度优化：同分支源 revision 深拷贝后立即无损释放（锁内标记、锁外执行）
        var kvTrimReleases: [(caches: [any KVCache], tokens: Int, id: String)] = []

        state.withLock { state in
            for (index, revision) in state.physicalRevisions.enumerated() {
                guard !revision.physicalTokens.isEmpty else { continue }

                sawUsableBranch = true

                guard revision.toolFingerprint == toolFingerprint else {
                    sawToolFingerprintMismatch = true
                    continue
                }

                let rawCommon = computeCommonPrefix(
                    revision.physicalTokens,
                    allPromptTokens
                )

                let boundedCommon = min(
                    rawCommon,
                    revision.physicalTokens.count,
                    allPromptTokens.count
                )

                if boundedCommon > selectedCommonLen ||
                    (boundedCommon == selectedCommonLen &&
                     boundedCommon > 0 &&
                     revision.lastActive > (selectedBranch?.lastActive ?? .distantPast)) {
                    selectedCommonLen = boundedCommon
                    selectedRawCommonLen = rawCommon
                    selectedBranch = revision
                    selectedIndex = index
                }
            }

            if let revision = selectedBranch, selectedCommonLen > 0 {
                if !revision.resident {
                    selectedCommonLen = 0
                    activeKVCacheFromPrefix = nil

                    traceLogger.trace(
                        "[KVD] br=\(targetLogicalBranchId) why=evicted rev=\(revision.id)",
                        session: traceSession
                    )
                } else {
                    activeKVCacheFromPrefix = revision.kvCache.map {
                        $0.copy()
                    }

                    var touched = revision
                    touched.lastActive = Date()

                    if selectedIndex >= 0,
                       selectedIndex < state.physicalRevisions.count {
                        state.physicalRevisions[selectedIndex].lastActive = touched.lastActive
                    }

                    // 白皮书 §35 lossless：同分支源 revision 被本轮深拷贝取代，
                    // 串行链路下一轮只复用最新 revision —— 立即释放物理层（账本保留，
                    // 再命中走 why=evicted Cold）。跨会话全局复用源不释放（对端链路仍需要它）。
                    // 常驻从"父+子"减半为"仅子"，8.3G 预算可容 2 路 30K 会话。
                    if revision.logicalBranchId == targetLogicalBranchId,
                       selectedIndex >= 0,
                       selectedIndex < state.physicalRevisions.count {
                        kvTrimReleases.append(
                            (revision.kvCache, revision.physicalTokens.count, revision.id)
                        )
                        state.physicalRevisions[selectedIndex].kvCache = []
                    }
                }
            }
        }

        if !kvTrimReleases.isEmpty {
            await MainActor.run {
                for release in kvTrimReleases {
                    for cache in release.caches {
                        _ = cache.trim(release.tokens)
                    }
                }

                Memory.clearCache()
            }

            for release in kvTrimReleases {
                traceLogger.trace(
                    "[KVTRIM] rev=\(release.id) est_freed=\(release.tokens * 128 / 1024)M why=superseded",
                    session: traceSession
                )
            }
        }

        if sawToolFingerprintMismatch {
            traceLogger.trace(
                "[KVD] br=\(targetLogicalBranchId) why=toolFP reuse=0",
                session: traceSession
            )
        }

        if selectedBranch != nil {
            traceLogger.trace(
                "[KVS] br=\(targetLogicalBranchId) i=\(selectedIndex) rawcp=\(selectedRawCommonLen) cp=\(selectedCommonLen)",
                session: traceSession
            )
        }

        // MARK: Prefill Scheduler

        let prefillPermit = await prefillScheduler.acquire(requestId: requestId)

        guard prefillPermit.granted else {
            traceLogger.trace(
                "🛑 Prefill Scheduler acquisition cancelled.",
                session: traceSession
            )

            throw CancellationError()
        }

        if prefillPermit.waited > 0.005 {
            traceLogger.trace(
                "[PWAIT] request=\(requestId) wait=\(String(format: "%.1f", prefillPermit.waited * 1000))ms",
                session: traceSession
            )
        }

        var prefillSlotReleased = false

        defer {
            if !prefillSlotReleased {
                Task {
                    await prefillScheduler.release(requestId: requestId)
                }
            }
        }

        // MARK: Build Active KV Cache

        var activeKVCache: [any KVCache]
        var finalInput: LMInput = lmInput
        var deltaTokenCount = allPromptTokens.count
        var hasReusableCache = false

        if let branch = selectedBranch,
           selectedCommonLen > 0,
           let copiedKV = activeKVCacheFromPrefix {
            activeKVCache = copiedKV

            traceLogger.trace(
                "[KCP] src=G rev=\(branch.id) cache=\(branch.physicalTokens.count) kv=\(activeKVCache.count) p=\(allPromptTokens.count) cp=\(selectedCommonLen)",
                session: traceSession
            )

            selectedCommonLen = min(
                selectedCommonLen,
                branch.physicalTokens.count,
                allPromptTokens.count
            )

            let stalePhysicalCount = max(
                branch.physicalTokens.count - selectedCommonLen,
                0
            )

            if stalePhysicalCount > 0 {
                for index in activeKVCache.indices {
                    _ = activeKVCache[index].trim(stalePhysicalCount)
                }
            }

            let deltaCount = max(
                allPromptTokens.count - selectedCommonLen,
                0
            )

            if deltaCount > 0 {
                let deltaTokens = Array(
                    allPromptTokens.dropFirst(selectedCommonLen)
                )

                finalInput = LMInput(
                    tokens: MLXArray(deltaTokens)
                )

                deltaTokenCount = deltaTokens.count
                hasReusableCache = true

                let skippedPercent = String(
                    format: "%.1f",
                    Double(selectedCommonLen) /
                        Double(max(allPromptTokens.count, 1)) * 100.0
                )

                Service.log(
                    "⚡️ [Global KV Reuse] branch=\(branch.id), reused=\(selectedCommonLen), delta=\(deltaCount), skipped=\(skippedPercent)%"
                )

                traceLogger.trace(
                    "[KVR] src=G i=\(selectedIndex) rev=\(branch.id) cache=\(branch.physicalTokens.count) cp=\(selectedCommonLen) d=\(deltaCount) hit=\(skippedPercent)%",
                    session: traceSession
                )
            } else if selectedCommonLen > 1 {
                for index in activeKVCache.indices {
                    _ = activeKVCache[index].trim(1)
                }

                let reprimeToken = allPromptTokens[selectedCommonLen - 1]
                finalInput = LMInput(
                    tokens: MLXArray([reprimeToken])
                )

                deltaTokenCount = 1
                hasReusableCache = true
                selectedCommonLen -= 1

                let skippedPercent = String(
                    format: "%.1f",
                    Double(selectedCommonLen) /
                        Double(max(allPromptTokens.count, 1)) * 100.0
                )

                Service.log(
                    "⚡️ [Global KV Reuse] exact prompt match: branch=\(branch.id), reused=\(selectedCommonLen), delta=1, skipped=\(skippedPercent)%"
                )

                traceLogger.trace(
                    "[EXACT MATCH REPRIME] source=global, index=\(selectedIndex), branch=\(branch.id), reused=\(selectedCommonLen), delta=1, reuse=\(skippedPercent)%",
                    session: traceSession
                )
            } else {
                hasReusableCache = false

                let newCacheBox = await container.perform { (context: ModelContext) -> SendableBox<[any KVCache]> in
                    SendableBox(
                        context.model.newCache(parameters: params)
                    )
                }

                activeKVCache = newCacheBox.value
                finalInput = lmInput
                deltaTokenCount = allPromptTokens.count
            }
        } else {
            let newCacheBox = await container.perform { (context: ModelContext) -> SendableBox<[any KVCache]> in
                SendableBox(
                    context.model.newCache(parameters: params)
                )
            }

            activeKVCache = newCacheBox.value
            finalInput = lmInput
            deltaTokenCount = allPromptTokens.count

            let revisionCount = state.withLock {
                $0.physicalRevisions.count
            }

            let missReason: String

            if revisionCount == 0 {
                missReason = "noGlobalRevision"
            } else if sawToolFingerprintMismatch {
                missReason = "toolFingerprintMismatch"
            } else if selectedBranch != nil && !(selectedBranch!.resident) {
                missReason = "evictedPhysicalKV"
            } else if sawUsableBranch {
                missReason = "noCommonPrefix"
            } else {
                missReason = "noUsableLineage"
            }

            Service.log(
                "⚡️ [Global Physical KV Cold] prompt=\(allPromptTokens.count)"
            )

            traceLogger.trace(
                "[KVM] why=\(missReason) p=\(allPromptTokens.count) tf=\(toolFingerprint) revs=\(revisionCount)",
                session: traceSession
            )

            traceLogger.trace(
                "[COLD] p=\(allPromptTokens.count) tf=\(toolFingerprint) revs=\(revisionCount)",
                session: traceSession
            )
        }

        // MARK: Long Context Policy & Admission Control

        let estimatedBytesPerToken: UInt64 = RuntimeTuning.estimatedKVBytesPerToken
        let projectedKVBytes = UInt64(deltaTokenCount) * estimatedBytesPerToken
        let executionWorkingSetBytes: UInt64 = RuntimeTuning.executionWorkingSetBytes
        let safetyMarginBytes: UInt64 = RuntimeTuning.safetyMarginBytes

        // 白皮书 §30 + 铁律 63：Admission 预算必须与物理内存对账。
        // 权重不计入预算的旧口径在 20G 权重模型 + 32G 机器上超订 ~9G，
        // macOS 被迫页出权重，实测 decode 33→12.7 tok/s（日志 2026-09-05）。
        // limit = min(22G, RAM − weights − OS 基线)，下限防御见 RuntimeTuning。
        let physicalRAMBytes = ProcessInfo.processInfo.physicalMemory
        let reservedBytes = modelWeightsBytes &+ UInt64(Self.osReserveBytes)
        let weightAwareLimit: UInt64 = physicalRAMBytes > reservedBytes
            ? physicalRAMBytes &- reservedBytes
            : RuntimeTuning.admissionFloorBytes
        let admissionLimit = min(
            UInt64(Self.inferenceMemoryLimit),
            weightAwareLimit
        )

        let currentResidentKVBytes: UInt64 = state.withLock { state in
            state.physicalRevisions
                .map(\.estimatedResidentBytes)
                .reduce(0, +)
        }

        let admissionMemorySnapshot = RuntimeMemoryProbe.snapshot()
        let internalKVGB = Double(currentResidentKVBytes) / Double(Self.gibibyte)
        let rssGB = admissionMemorySnapshot.residentGB
        let weightsGB = Double(modelWeightsBytes) / Double(Self.gibibyte)
        let budgetGB = Double(admissionLimit) / Double(Self.gibibyte)

        traceLogger.trace(
            "[ADMISSION OBS] r=\(requestId) kv=\(String(format: "%.2f", internalKVGB))G rss=\(String(format: "%.2f", rssGB))G sw=\(admissionMemorySnapshot.swapUsedGB.map { String(format: "%.2f", $0) } ?? "?")G weights=\(String(format: "%.1f", weightsGB))G budget=\(String(format: "%.1f", budgetGB))G",
            session: traceSession
        )

        var projectedMemory =
            currentResidentKVBytes +
            projectedKVBytes +
            executionWorkingSetBytes +
            safetyMarginBytes

        if projectedMemory > admissionLimit {
            let isLongContext = allPromptTokens.count >= Self.longContextThreshold
            let targetEvictionBytes = projectedMemory - admissionLimit

            var freedBytes: UInt64 = 0
            var evictedCount = 0

            state.withLock { state in
                var evictCandidates = state.physicalRevisions.indices.filter {
                    state.physicalRevisions[$0].resident
                }

                evictCandidates.sort {
                    state.physicalRevisions[$0].lastActive < state.physicalRevisions[$1].lastActive
                }

                for index in evictCandidates {
                    if freedBytes >= targetEvictionBytes && !isLongContext {
                        break
                    }

                    let bytes = state.physicalRevisions[index].estimatedResidentBytes

                    state.physicalRevisions[index].releasePhysicalMemory()
                    freedBytes += bytes
                    evictedCount += 1

                    if isLongContext &&
                        freedBytes >= targetEvictionBytes + 2 * 1024 * 1024 * 1024 {
                        break
                    }
                }
            }

            if evictedCount > 0 {
                Memory.clearCache()

                traceLogger.trace(
                    "[ADMISSION] r=\(requestId) projected=\(projectedMemory / 1024 / 1024)M limit=\(admissionLimit / 1024 / 1024)M evicted=\(evictedCount) est_freed=\(freedBytes / 1024 / 1024)M",
                    session: traceSession
                )

                projectedMemory =
                    (currentResidentKVBytes - freedBytes) +
                    projectedKVBytes +
                    executionWorkingSetBytes +
                    safetyMarginBytes
            }

            if projectedMemory > admissionLimit {
                Memory.clearCache()

                traceLogger.trace(
                    "[ADMISSION WARN] Still exceeding limit after eviction. Projected: \(projectedMemory / 1024 / 1024)M",
                    session: traceSession
                )
            }
        }

        // MARK: Physical Ledger

        let ledgerRecorder = PhysicalTokenRecorder()
        let cacheBox = SendableBox(activeKVCache)
        let inputBox = SendableBox(finalInput)
        let toolsBox = SendableBox(toolsAny)
        let generationUsesReusableCache = hasReusableCache

        let generationBox: SendableBox<
            (
                AsyncStream<Generation>,
                Task<Void, Never>,
                [any KVCache],
                TimeInterval
            )
        > = try await container.perform {
            (context: ModelContext) -> SendableBox<
                (
                    AsyncStream<Generation>,
                    Task<Void, Never>,
                    [any KVCache],
                    TimeInterval
                )
            > in
            let iterator = try TokenIterator(
                input: inputBox.value,
                model: context.model,
                cache: cacheBox.value,
                parameters: params
            )

            if generationUsesReusableCache {
                let promptKVState = cacheBox.value.flatMap {
                    $0.state
                }

                if !promptKVState.isEmpty {
                    eval(promptKVState)
                }
            }

            let promptPrefillTime = iterator.promptPrefillTime

            let recordingIterator = PhysicalLedgerTokenIterator(
                base: iterator,
                recorder: ledgerRecorder
            )

            let (stream, task) = MLXLMCommon.generateTask(
                promptTokenCount: inputBox.value.text.tokens.size,
                modelConfiguration: context.configuration,
                tokenizer: context.tokenizer,
                iterator: recordingIterator,
                tools: toolsBox.value
            )

            return SendableBox(
                (
                    stream,
                    task,
                    cacheBox.value,
                    promptPrefillTime
                )
            )
        }

        prefillSlotReleased = true
        await prefillScheduler.release(requestId: requestId)

        let (stream, generationTask, generationKVCache, promptPrefillTime) = generationBox.value

        state.withLock { state in
            state.activeGenerationTasks[requestId] = generationTask
            state.peakActiveGenerationTasks = max(
                state.peakActiveGenerationTasks,
                state.activeGenerationTasks.count
            )
        }

        traceLogger.trace(
            "[GENERATION START] request=\(requestId), agent=\(executionKey.agentId), session=\(executionKey.sessionId), prefillQueueWait=\(String(format: "%.1f", prefillPermit.waited * 1000))ms",
            session: traceSession
        )

        emitRuntimeObservation(
            "generation-start",
            requestId: requestId,
            executionKey: executionKey
        )

        defer {
            _ = state.withLock {
                $0.activeGenerationTasks.removeValue(forKey: requestId)
            }

            emitRuntimeObservation(
                "generation-task-removed",
                requestId: requestId,
                executionKey: executionKey
            )
        }

        // MARK: Stream Consume

        let filter = StreamTokenFilter(
            disableThinking: thinkingDisabled
        )

        let rawToolCallParser = RawToolCallStreamParser()
        var completedText = ""
        var isInterrupted = false
        var toolCallDetected = false
        var rawToolCallDetected = false
        var turnToolCalls: [ParsedToolCall] = []
        var attemptedToolSignatures = Set<String>()

        func appendToolCallCandidate(_ call: ParsedToolCall) {
            let normalizedName = call.name.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !normalizedName.isEmpty else {
                traceLogger.trace(
                    "[TDROP] request=\(requestId) why=noName",
                    session: traceSession
                )

                return
            }

            let canonicalArguments = canonicalValue(
                call.arguments.mapValues(toolValueToSendable)
            )

            let signature = "\(normalizedName)\u{001F}\(canonicalArguments)"

            guard attemptedToolSignatures.insert(signature).inserted else {
                traceLogger.trace(
                    "[TDUP] request=\(requestId) name=\(normalizedName) act=dup",
                    session: traceSession
                )

                return
            }

            toolCallDetected = true

            turnToolCalls.append(
                ParsedToolCall(
                    id: call.id,
                    name: normalizedName,
                    arguments: call.arguments
                )
            )
        }

        emitRuntimeObservation(
            "decode-start",
            requestId: requestId,
            executionKey: executionKey
        )

        let decodeStartTime = Date()

        for await generation in stream {
            if Task.isCancelled || !state.withLock({ $0.isRunning }) {
                isInterrupted = true
                generationTask.cancel()
                break
            }

            switch generation {
            case .chunk(let text):
                if text.contains("<tool_call>") || text.contains("</tool_call>") {
                    traceLogger.trace(
                        "[RAWTOOL] request=\(requestId) chunkLen=\(text.count)",
                        session: traceSession
                    )
                }

                rawToolCallParser.feed(
                    text,
                    onText: { plainText in
                        filter.feed(plainText) { chunk in
                            completedText.append(chunk)
                            onChunk(chunk)
                        }
                    },
                    onToolCall: { call in
                        rawToolCallDetected = true
                        appendToolCallCandidate(call)
                    }
                )

            case .toolCall(let toolCall):
                let argumentObject = toolCall.function.arguments.reduce(
                    into: [String: JSONValue]()
                ) { result, item in
                    result[item.key] = mlxJSONToSimiGo(item.value)
                }

                appendToolCallCandidate(
                    ParsedToolCall(
                        id: toolCall.id ?? UUID().uuidString,
                        name: toolCall.function.name,
                        arguments: argumentObject
                    )
                )

            case .info:
                break
            }
        }

        if isInterrupted {
            generationTask.cancel()
        }

        await generationTask.value

        emitRuntimeObservation(
            "generation-task-completed",
            requestId: requestId,
            executionKey: executionKey
        )

        let decodeWallTime = max(
            Date().timeIntervalSince(decodeStartTime),
            0.001
        )

        // First flush Raw Tool Call Parser

        rawToolCallParser.flush { plainText in
            filter.feed(plainText) { chunk in
                completedText.append(chunk)
                onChunk(chunk)
            }
        }

        filter.flush { chunk in
            completedText.append(chunk)
            onChunk(chunk)
        }

        rawToolCallDetected =
            rawToolCallDetected ||
            rawToolCallParser.rawToolCallDetected

        if let failure = rawToolCallParser.failure {
            traceLogger.trace(
                "[TPFAIL] request=\(requestId) raw=1 error=\(failure.localizedDescription) kv=0",
                session: traceSession
            )

            throw failure
        }

        let actualGeneratedTokenIDs = ledgerRecorder.snapshot()

        if toolCallDetected {
            traceLogger.trace(
                "[TOOL] request=\(requestId) tok=\(actualGeneratedTokenIDs.count) raw=\(rawToolCallDetected ? 1 : 0) calls=\(turnToolCalls.count)",
                session: traceSession
            )
        }

        if rawToolCallDetected {
            traceLogger.trace(
                "[RAWTOOL] request=\(requestId) raw=\(rawToolCallDetected ? 1 : 0) structured=\(turnToolCalls.count)",
                session: traceSession
            )
        }

        // MARK: Cross-Turn Degeneration State Machine

        var forwardedToolCount = 0
        var stateAdvanced = false
        var kvCommittedSuccessfully = false

        let candidateSignatures = turnToolCalls.map {
            "\($0.name)\u{001F}" +
            canonicalValue($0.arguments.mapValues(toolValueToSendable))
        }.sorted()

        var actualForwardedSignatures: [String] = []
        var degenerationBlocked = false

        var currentDegenerationState = state.withLock {
            $0.sessionCaches[sessionKey]?
                .logicalBranches[targetLogicalBranchId]?
                .degenerationState
                ?? BranchDegenerationState()
        }

        if !isInterrupted && !Task.isCancelled {
            if turnToolCalls.isEmpty {
                if !rawToolCallDetected {
                    currentDegenerationState.resetOnPlain()
                    stateAdvanced = true
                }
            } else {
                let probe = currentDegenerationState.preview(
                    signatures: candidateSignatures,
                    progress: semanticProgressHash
                )

                if probe.blocked {
                    currentDegenerationState.recordBlocked(probe)
                    stateAdvanced = true
                    degenerationBlocked = true

                    traceLogger.trace(
                        "[BRANCH DEGENERATION BLOCKED] request=\(requestId), branch=\(targetLogicalBranchId), projectedRounds=\(probe.projected), action=circuit_break, forwarded=0, kvCommitted=false, stateAdvanced=true",
                        session: traceSession
                    )
                } else {
                    for tool in turnToolCalls {
                        if Task.isCancelled {
                            isInterrupted = true
                            break
                        }

                        onToolCall(tool)
                        forwardedToolCount += 1

                        actualForwardedSignatures.append(
                            "\(tool.name)\u{001F}" +
                            canonicalValue(tool.arguments.mapValues(toolValueToSendable))
                        )
                    }

                    actualForwardedSignatures.sort()

                    if forwardedToolCount > 0 {
                        currentDegenerationState.commitForwarded(
                            BranchDegenerationState.Probe(
                                signatures: candidateSignatures,
                                progress: semanticProgressHash,
                                projected: probe.projected,
                                blocked: false
                            )
                        )

                        stateAdvanced = true
                    }
                }
            }

            state.withLock { state in
                var session = state.sessionCaches[sessionKey] ?? SessionLogicalState()

                var logical = session.logicalBranches[targetLogicalBranchId] ?? LogicalBranchState(
                    logicalBranchId: targetLogicalBranchId,
                    toolFingerprint: toolFingerprint
                )

                logical.degenerationState = currentDegenerationState
                logical.toolFingerprint = toolFingerprint
                logical.lastActive = Date()

                session.logicalBranches[targetLogicalBranchId] = logical
                session.lastActive = Date()

                state.sessionCaches[sessionKey] = session
            }
        }

        // MARK: Physical KV Commit

        if !degenerationBlocked &&
            !isInterrupted &&
            !Task.isCancelled &&
            forwardedToolCount == turnToolCalls.count &&
            !allPromptTokens.isEmpty &&
            !generationKVCache.isEmpty {

            var physicalTokens: [Int] = []

            physicalTokens.reserveCapacity(
                allPromptTokens.count +
                actualGeneratedTokenIDs.count
            )

            physicalTokens.append(contentsOf: allPromptTokens)
            physicalTokens.append(contentsOf: actualGeneratedTokenIDs)

            let branchId = makeBranchID(
                logicalBranchId: targetLogicalBranchId,
                toolFingerprint: toolFingerprint,
                promptTokens: allPromptTokens
            )

            let revision = PhysicalKVRevision(
                id: branchId,
                logicalBranchId: targetLogicalBranchId,
                toolFingerprint: toolFingerprint,
                physicalTokens: physicalTokens,
                kvCache: generationKVCache,
                lastActive: Date()
            )

            let revisionsToRelease = state.withLock { state -> [PhysicalKVRevision] in
                var retained: [PhysicalKVRevision] = []
                var toRelease: [PhysicalKVRevision] = []

                retained.reserveCapacity(
                    state.physicalRevisions.count + 1
                )

                for existing in state.physicalRevisions {
                    if existing.id == revision.id ||
                        (existing.logicalBranchId == revision.logicalBranchId &&
                         existing.toolFingerprint == revision.toolFingerprint &&
                         existing.physicalTokens == revision.physicalTokens) {
                        toRelease.append(existing)
                    } else {
                        retained.append(existing)
                    }
                }

                retained.append(revision)
                retained.sort {
                    $0.lastActive > $1.lastActive
                }

                let maxPhysicalRevisions = Self.maxPhysicalKVRevisions

                if retained.count > maxPhysicalRevisions {
                    let discarded = Array(
                        retained.suffix(from: maxPhysicalRevisions)
                    )

                    toRelease.append(contentsOf: discarded)
                    retained.removeLast(
                        retained.count - maxPhysicalRevisions
                    )
                }

                state.physicalRevisions = retained

                if var session = state.sessionCaches[sessionKey],
                   var logical = session.logicalBranches[targetLogicalBranchId] {
                    logical.lastActive = Date()
                    logical.toolFingerprint = toolFingerprint

                    session.logicalBranches[targetLogicalBranchId] = logical
                    session.lastActive = Date()

                    state.sessionCaches[sessionKey] = session
                }

                return toRelease
            }

            if !revisionsToRelease.isEmpty {
                await MainActor.run {
                    for var oldRevision in revisionsToRelease {
                        oldRevision.releasePhysicalMemory()
                    }
                }

                Memory.clearCache()
            }

            kvCommittedSuccessfully = true

            traceLogger.trace(
                "[KVC] src=G rev=\(branchId) br=\(targetLogicalBranchId) p=\(allPromptTokens.count) g=\(actualGeneratedTokenIDs.count) ktok=\(physicalTokens.count) revs=\(state.withLock { $0.physicalRevisions.count }) ok",
                session: traceSession
            )

            emitRuntimeObservation(
                "kv-commit",
                requestId: requestId,
                executionKey: executionKey
            )
        } else if isInterrupted || Task.isCancelled {
            Service.log(
                "🛑 [NativeMLX] 本轮生成已中断/取消，安全跳过 KV Cache Commit"
            )

            traceLogger.trace(
                "[CXL] request=\(requestId) kv=0",
                session: traceSession
            )

            emitRuntimeObservation(
                "cancelled",
                requestId: requestId,
                executionKey: executionKey
            )
        }

        traceLogger.trace(
            "[DEG] br=\(targetLogicalBranchId) round=\(currentDegenerationState.round) rep=\(currentDegenerationState.consecutive) cand=\(candidateSignatures.count) fwd=\(actualForwardedSignatures.count) kv=\(kvCommittedSuccessfully ? 1 : 0) adv=\(stateAdvanced ? 1 : 0) ph=\(semanticProgressHash)",
            session: traceSession
        )

        // MARK: Performance Telemetry

        let totalDuration = Date().timeIntervalSince(t0)

        let decodeTPS = actualGeneratedTokenIDs.count > 0
            ? Double(actualGeneratedTokenIDs.count) / decodeWallTime
            : 0

        let prefillTPS = promptPrefillTime > 0.001
            ? Double(deltaTokenCount) / promptPrefillTime
            : 0

        let branchCount = state.withLock {
            $0.physicalRevisions.count
        }

        let perfSummary = "[PERF] r=\(requestId)" +
            " ttft=\(String(format: "%.3f", promptPrefillTime))s" +
            " pre=\(String(format: "%.1f", prefillTPS))/s" +
            " d=\(String(format: "%.1f", decodeTPS))/s" +
            " p=\(allPromptTokens.count)" +
            " cp=\(selectedCommonLen)" +
            " cache=\(selectedBranch?.physicalTokens.count ?? 0)" +
            " tok=\(actualGeneratedTokenIDs.count)" +
            " tool=\(toolCallDetected ? 1 : 0)" +
            " fwd=\(forwardedToolCount)" +
            " rev=\(branchCount)" +
            " dur=\(String(format: "%.2f", totalDuration))s"

        Service.log(
            "📈 [MLX] r=\(requestId) p=\(allPromptTokens.count) cp=\(selectedCommonLen) tok=\(actualGeneratedTokenIDs.count) tool=\(toolCallDetected ? 1 : 0) rev=\(branchCount) dur=\(String(format: "%.2f", totalDuration))s"
        )

        traceLogger.trace(
            perfSummary,
            session: traceSession
        )

        emitRuntimeObservation(
            "request-complete",
            requestId: requestId,
            executionKey: executionKey
        )

        return completedText
    }

    // MARK: - Session / Logical Cache Maintenance

    private func purgeStaleSessionCachesLocked(_ state: inout State) {
        let now = Date()

        for sessionID in Array(state.sessionCaches.keys) {
            guard var session = state.sessionCaches[sessionID] else {
                continue
            }

            let activeBranches = session.logicalBranches.filter {
                _, branch in
                now.timeIntervalSince(branch.lastActive) < Self.sessionMaxIdleTime
            }

            if activeBranches.isEmpty {
                state.sessionCaches.removeValue(
                    forKey: sessionID
                )
            } else {
                session.logicalBranches = Dictionary(
                    uniqueKeysWithValues: activeBranches.map {
                        ($0.key, $0.value)
                    }
                )

                session.lastActive =
                    session.logicalBranches.values
                    .map(\.lastActive)
                    .max() ?? now

                state.sessionCaches[sessionID] = session
            }
        }
    }

    // MARK: - Tool Fingerprint

    private nonisolated func makeToolFingerprint(
        _ tools: [[String: any Sendable]]?
    ) -> String {
        guard let tools, !tools.isEmpty else {
            return "none"
        }

        let canonical = tools
            .map { canonicalValue($0) }
            .joined(separator: "\n")

        let digest = SHA256.hash(
            data: Data(canonical.utf8)
        )

        return digest
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(16)
            .description
    }

    // MARK: - Branch ID

    private nonisolated func makeBranchID(
        logicalBranchId: String,
        toolFingerprint: String,
        promptTokens: [Int]
    ) -> String {
        var hasher = SHA256()

        hasher.update(data: Data(logicalBranchId.utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: Data(toolFingerprint.utf8))
        hasher.update(data: Data([0]))

        for token in promptTokens {
            var value = UInt64(
                bitPattern: Int64(token)
            ).bigEndian

            withUnsafeBytes(of: &value) {
                hasher.update(data: $0)
            }
        }

        let digest = hasher.finalize()

        return digest
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(16)
            .description
    }

    // MARK: - Common Prefix

    private nonisolated func computeCommonPrefix(
        _ a: [Int],
        _ b: [Int]
    ) -> Int {
        let limit = min(a.count, b.count)
        var count = 0

        while count < limit, a[count] == b[count] {
            count += 1
        }

        return count
    }

    // MARK: - Cancellation

    public func cancelGeneration(requestId: String) {
        let handles = state.withLock { state in
            (
                request: state.activeRequestTasks[requestId],
                generation: state.activeGenerationTasks[requestId]
            )
        }

        traceLogger.trace(
            "[CANCEL REQUEST] request=\(requestId), hasRequestTask=\(handles.request != nil), hasGenerationTask=\(handles.generation != nil)"
        )

        // 统一终止入口（收敛文档 §5）：账本进入取消释放序列；真实 task 取消仍在下方执行。
        Task {
            await RuntimeLifecycleCoordinator.shared.finish(
                requestID: requestId,
                success: false,
                reason: "cancel_generation"
            )
        }
        handles.request?.cancel()
        handles.generation?.cancel()

        emitRuntimeObservation(
            "cancel-request-issued",
            requestId: requestId
        )
    }
}
