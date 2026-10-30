import Foundation
import CryptoKit
import LOCALBCore
import Synchronization
import MLX
import MLXLMCommon
import MLXLLM
import MLXHuggingFace
import MLXVLM
import Tokenizers
import LOCALBCore
import SimiGo2Experimental
import SimiGoRuntimeContract

/// Native MLX runtime. Inference state is owned by the official ChatSession API.
/// SimiGo retains only service state around that API.
public final class NativeMLX: Runtime, @unchecked Sendable {
    /// Semantic KV-cache identity for THIS in-process runtime instance (owns one
    /// ModelContainer / KV set). Instance-scoped and meaningful, NOT a raw memory
    /// address, so cross-process cache non-sharing can be audited by comparing it.
    public let cacheIdentity: String = "cache-" + UUID().uuidString.lowercased()
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
        /// 由 checkpoint 快照恢复（performLoad）：vendor 侧无 conversation
        /// 账本（ChatSession "raw cache without transcript" 模式），走
        /// delta-only 前缀续接，info 归因块整体跳过。轮末遥测据此把
        /// cacheTokensBefore 补回 cacheHit 归因，消除 cacheEff=0.00 歧义。
        let isRestoredSnapshot: Bool
        /// The gate identity of the live execution. It is assigned when a
        /// generation uses the session; restored sessions acquire it lazily.
        var executionKey: AgentExecutionKey?
        /// A successful generation makes the live execution newer than its
        /// durable checkpoint until the automatic checkpoint completes.
        var checkpointDirty = false
        /// v2.1.1 官方内存 fork：forkSessionBranch 设置的分叉点溯源。
        /// 随 child 的每次 performSave 戳进 checkpoint meta——fork 溯源是
        /// 分支的永久血统属性，不只属于首次落盘。
        var pendingForkPoint: BranchForkPoint? = nil
        /// EXP-B 实验字段（B_HEDGE_SKIP_EXPERIMENT_DESIGN §1；运行时态，
        /// 不持久化）：上一轮 completion 的 vendor mode 与 cacheEff。
        /// 重启后为 nil → 对冲保守开启（未知状态不跳过 restore）。
        var lastCompletionMode: String?
        var lastCompletionCacheEff: Double?
        /// #90 A：本表示创建时的 thinking 配置。`nil` = 未记录 ⇒ 跨请求采纳
        /// 时必须拒绝（未知不等于相容）。同键复用沿用既有 kvFingerprint 门，
        /// 此字段只为「不同请求级 sessionId 采纳陌生分片」增加判据。
        let thinkingDisabled: Bool?
        /// #90 B：正在本分片上执行的请求 id。逐出器据此把淘汰对象与在途
        /// 请求隔离——非 nil 的分片永远不是逐出候选。
        var inFlightRequestId: String?

        init(
            session: ChatSession,
            history: [Chat.Message],
            historyJSON: [JSONValue] = [],
            kvFingerprint: String? = nil,
            isRestoredSnapshot: Bool = false,
            thinkingDisabled: Bool? = nil
        ) {
            self.session = session
            self.history = history
            self.historyJSON = historyJSON
            self.kvFingerprint = kvFingerprint
            self.isRestoredSnapshot = isRestoredSnapshot
            self.thinkingDisabled = thinkingDisabled
            self.checkpointDirty = false
        }
    }

    /// evictSessionsIfNeeded 的驱逐报告：admission 观测行消费。
    private struct SessionEvictionReport {
        var evicted = 0
        var evictedTokens = 0
        var warmSessions = 0
        var warmTokens = 0
        /// #90 B：驻留字节维度的读数（residency 未知时全为 0，维度不触发）。
        var warmBytes = 0
        var evictedBytes = 0
        var byteBudget = 0
    }

    private struct State {
        var modelContainer: ModelContainer?
        /// v2.0 beta: oversized models are served by the segmented runtime
        /// instead of the container path; nil for fitting models.
        var oversized: OversizedRuntime?
        var httpServer: HTTPServer?
        var isRunning = false
        var lifecycle: Lifecycle = .stopped
        var lastActivity = Date()
        var sessions: [String: ManagedSession] = [:]
        var modelCapabilityContract: ModelCapabilityContract?
        var activeRequestTasks: [String: Task<GenerationResult, Error>] = [:]
        /// Request intent survives the async ensureLoaded → task-registration
        /// gap. Suspend must not unload the runtime while this is non-empty.
        var pendingRequestIds: Set<String> = []
        /// W4/#138：加载后的第一笔完成预填含 kernel 首次编译/权重驻留代价，
        /// 只能消费一次，不能充当吞吐证据（加载/恢复完成时复位）。
        var postLoadWarmup = PostLoadWarmupTracker()
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
    /// #90 B：活会话驻留字节的口径（模型 config.json 几何推出）。
    /// `nil` = 读不到几何 ⇒ 字节维度不启用：宁可不逐出，也不用猜的常数
    /// 打掉暖会话。
    private let residency: LiveSessionResidency?
    private let lifecycleGate = RuntimeLifecycleGate()
    private let gateHolder = Mutex(SessionGenerationGate())
    /// V1.6 S5：执行血统日志（有界 128 条；只记录查询，不参与决策）。
    let lineage = ExecutionLineage()
    /// G1/G3 §5 read-only observability recorder. It NEVER participates in
    /// cache-hit decisions or the inference lifecycle — each hook is a single
    /// increment beside an existing trace/engine value. See NativeMLXObservation.
    public let observation = NativeMLXObservation()
    private let traceLogger = RuntimeTraceLogger.shared
    private let toolGovernance = ToolGovernance { line in
        RuntimeTraceLogger.shared.trace(line)
    }
    /// W4/A：预算身份（model + tokenizer 内容指纹 + 模板口径）按模型路径
    /// 缓存一次。tokenizer 指纹要对 tokenizer 文件做内容哈希，逐请求重算
    /// 会把门本身变成新的开销来源。
    private let budgetIdentityCache =
        Locked<(path: String, model: String, tokenizer: String)?>(nil)

    public var isInProcess: Bool { true }
    public var isGenerating: Bool {
        state.withLock { !$0.activeRequestTasks.isEmpty || !$0.pendingRequestIds.isEmpty }
    }
    public var isRunning: Bool { state.withLock { $0.isRunning } }

    public init(info: ModelInfo, config: ModelConfig) {
        self.modelPath = info.path
        self.baseConfig = config
        self.residency = LiveSessionResidency.resolve(modelPath: info.path)
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

    // MARK: - Context Safety Gate（2026-10-15 复线）

    /// 有效上下文预算：请求/基底 ctx 配置与模型声明长度取严；
    /// 均无效则门关闭（nil）。
    private nonisolated static func contextSafetyBudget(
        config: ModelConfig,
        base: ModelConfig,
        contract: ModelCapabilityContract?
    ) -> Int? {
        let configured = config.ctxSize > 0 ? config.ctxSize : base.ctxSize
        guard configured > 0 else { return nil }

        if let declared = contract?.contextLength, declared > 0, declared < configured {
            return declared
        }
        return configured
    }

    /// 内容 token 精确计数（tokenizer 复核）。只统计字符串内容、不渲染
    /// 模板——内容 token 是渲染后 prompt token 的严格下界，下界超限即
    /// 必超限，判定无假阳性；tools 文本一并计入。
    private nonisolated static func contentTokenDemand(
        messages: [JSONValue],
        tools: [JSONValue]?,
        container: ModelContainer
    ) async -> Int {
        var leaves: [String] = []
        collectStringLeaves(messages, into: &leaves)
        if let tools {
            collectStringLeaves(tools, into: &leaves)
        }
        guard !leaves.isEmpty else { return 0 }

        let text = leaves.joined(separator: "\n")
        let tokenizer = await container.tokenizer
        return tokenizer.encode(text: text, addSpecialTokens: false).count
    }

    /// 内容字节量。token 数 ≤ 字节数，字节不超预算即可免 tokenize 放行
    /// ——常规请求零 tokenize 成本，只有巨型 payload 才付一次精确复核。
    private nonisolated static func contentByteDemand(
        messages: [JSONValue],
        tools: [JSONValue]?
    ) -> Int {
        var leaves: [String] = []
        collectStringLeaves(messages, into: &leaves)
        if let tools {
            collectStringLeaves(tools, into: &leaves)
        }
        return leaves.reduce(0) { $0 + $1.utf8.count }
    }

    private nonisolated static func collectStringLeaves(
        _ values: [JSONValue],
        into sink: inout [String]
    ) {
        for value in values {
            switch value {
            case .string(let string):
                sink.append(string)
            case .array(let items):
                collectStringLeaves(items, into: &sink)
            case .object(let object):
                // 键名（role/tool 名等）是模板结构的极小常量，不计数。
                collectStringLeaves(Array(object.values), into: &sink)
            default:
                break
            }
        }
    }

    // MARK: - Session Client Split（2026-10-15 双客户端互踩修复）

    /// 内存会话表键：storageKey 本体不变；首消息为 system 的请求追加其
    /// 内容指纹后缀。同一 session id 下的不同客户端（Codex / 记忆写入
    /// agent 等，系统提示互异）各自持暖缓存，交替不再互相顶替触发全量
    /// 冷重建（prefixDiff commonPrefix=0 实证，2026-10-15 12:07）。
    /// checkpoint、prefix 池、fork 血统、磁盘命名仍用原 storageKey；
    /// 无 system 首消息时键不变，完全向后兼容。
    /// 判定取 makeChatMessages 展平后的首条 Chat.Message——raw content
    /// 的字符串/数组两种形态在此统一（14:28 实证数组形态曾漏判）。
    nonisolated static func sessionMapKey(
        storageKey: String, firstMessage: (role: String, content: String)?
    ) -> String {
        guard let firstMessage,
              firstMessage.role == "system",
              !firstMessage.content.isEmpty else {
            return storageKey
        }
        return storageKey + "#" + ExecutionPolicy.fingerprint(firstMessage.content)
    }

    /// key-external 操作（save/load/fork）解析会话表键：精确命中优先，
    /// miss 后按 `storageKey#` 前缀扫描取最近活跃的客户端分片会话。
    /// nonisolated：从 withExclusive 的 @Sendable 闭包内调用，state 锁
    /// 本身线程安全。
    private nonisolated func resolveSessionMapKey(for storageKey: String) -> String {
        state.withLock { state in
            guard state.sessions[storageKey] == nil else { return storageKey }
            let prefix = storageKey + "#"
            return state.sessions
                .filter { $0.key.hasPrefix(prefix) }
                .sorted { $0.value.lastActivity > $1.value.lastActivity }
                .first?.key ?? storageKey
        }
    }

    // MARK: - Composite VLM checkpoint routing（v2.1.2）

    /// 复合 VLM 检查点判定（ukisai/Swift-1.5-4bit-MLX、mavis Gemma4-26B-MoE
    /// 一类）：同一 model_type（qwen3_5 / gemma4）在文本工厂与 VLM 工厂都
    /// 有注册，但文本模型无法消费 `language_model.*` / `visual.*` 前缀的
    /// 权重布局（2026-10-13/14 实测："Unhandled keys [visual]" 与
    /// "Key language_model... not found"）。判据取**权重键布局**而非
    /// architectures——mavis 稠密 QAT Q5 同为 Gemma4ForConditionalGeneration
    /// 但权重无前缀、今天走文本工厂正常，不得被误路由。
    nonisolated static func isCompositeVLMCheckpoint(path: String) -> Bool {
        let prefixes = [
            "language_model.", "visual.", "vision_tower.", "multi_modal_projector.",
        ]
        func hasCompositeKey(_ keys: some Sequence<String>) -> Bool {
            keys.contains { key in
                prefixes.contains { key.hasPrefix($0) }
            }
        }
        let fm = FileManager.default
        let indexURL = URL(fileURLWithPath: path + "/model.safetensors.index.json")
        if let data = fm.contents(atPath: indexURL.path),
           let index = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let weightMap = index["weight_map"] as? [String: Any]
        {
            return hasCompositeKey(weightMap.keys)
        }
        // 单文件布局：safetensors header = 8 字节 LE 头长 + JSON 元数据。
        let singleURL = URL(fileURLWithPath: path + "/model.safetensors")
        guard
            let handle = try? FileHandle(forReadingFrom: singleURL),
            let lenData = try? handle.read(upToCount: 8),
            lenData.count == 8,
            let headerData = try? handle.read(
                upToCount: Int(lenData.withUnsafeBytes { $0.load(as: UInt64.self) })),
            let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any]
        else { return false }
        defer { try? handle.close() }
        return hasCompositeKey(header.keys.filter { $0 != "__metadata__" })
    }

    /// 统一模型装载入口（v2.1.6 起：文本优先 + 复合布局回落）。
    ///
    /// 文本工厂认识 model_type 的（qwen3_5_moe、gemma4 稠密等）一律先走
    /// 文本路径——那是本血统验证数周的栈；仅当装载失败且检查点为复合
    /// VLM 布局（语言/视觉权重带前缀，文本栈无法消费其命名——如
    /// Gemma4-MoE 的专家键、纯 VLM-only 类型）时回落 VLMModelFactory。
    /// 取代 v2.1.2 的「复合即 VLM」直路由——它把 Nail-Qwen3.6
    /// （qwen3_5_moe 复合布局，文本路径长期正常）误送进 VLM 路径导致
    /// 启动失败（2026-10-15 "The data couldn't be read..."）。
    nonisolated static func loadModelContainer(path: String) async throws -> ModelContainer {
        do {
            return try await LLMModelFactory.shared.loadContainer(
                from: URL(fileURLWithPath: path),
                using: #huggingFaceTokenizerLoader())
        } catch let textError {
            guard isCompositeVLMCheckpoint(path: path) else { throw textError }
            // 释放文本尝试的瞬态权重再重试，避免 20G 级双重驻留。
            Memory.clearCache()
            do {
                return try await VLMModelFactory.shared.loadContainer(
                    from: URL(fileURLWithPath: path),
                    using: #huggingFaceTokenizerLoader())
            } catch {
                // 两条路径的失败原因都留档，避免下次排查丢前一半线索。
                throw RuntError.loadFailed(
                    "text path: \(textError.localizedDescription)"
                        + "; vlm fallback: \(error.localizedDescription)")
            }
        }
    }

    /// Protocol witness (Runtime). Defaults to the shared transport-policy
    /// decision with no caller-supplied LOCALB configuration.
    public func start(_ info: ModelInfo, port: Int) async throws {
        try await startWithLOCALB(
            info, port: port,
            localbTransportIdentity: nil,
            localbRequestAuthorization: nil
        )
    }

    /// Start with an EXPLICIT caller-supplied LOCALB configuration
    /// (test/management-plane injection). Never a fallback and never a
    /// default open rule: when both arguments are nil this is exactly the
    /// default-resolution path, which opens the operational LOCALB host
    /// (transport identity + request authorization from one verified
    /// context) or stays transport-only fail-closed before activation.
    public func startWithLOCALB(
        _ info: ModelInfo,
        port: Int,
        localbTransportIdentity: LOCALBTransportIdentityHandle?,
        localbRequestAuthorization: (coordinator: LOCALBPairingCoordinator,
                                     trustedCheckpoint: () throws -> LOCALBRegistryCheckpoint)?,
        localbHostDirectory: URL? = nil,
        keychainStore: LOCALBKeychainSignerStore = LOCALBKeychainSignerStore(),
        transportIdentityStore: LOCALBTransportIdentityStore =
            LOCALBTransportIdentityStore()
    ) async throws {
        try await lifecycleGate.withLock { [weak self] in
            guard let self else { throw RuntError.notLoaded }
            guard !self.state.withLock({ $0.isRunning }) else { return }

            logMemory("beforeLoad")
            self.state.withLock { $0.lifecycle = .loading }
            // v2.0 beta: oversized models route to the segmented engine
            // (controller-driven segment residency + strict Execution State
            // sessions); every other model loads through the unchanged
            // container path below.
            var container: ModelContainer?
            if OversizedRuntime.supports(path: info.path) {
                let oversized = OversizedRuntime(info: info)
                try await oversized.startWithLOCALB(
                    info,
                    port: port,
                    localbTransportIdentity: localbTransportIdentity,
                    localbRequestAuthorization: localbRequestAuthorization,
                    localbHostDirectory: localbHostDirectory,
                    keychainStore: keychainStore,
                    transportIdentityStore: transportIdentityStore
                )
                self.state.withLock { $0.oversized = oversized }
            } else {
                container = try await Self.loadModelContainer(path: info.path)
                traceLogger.trace(
                    "[MLX] loadRoute text-first composite=\(Self.isCompositeVLMCheckpoint(path: info.path)) model=\(modelName(from: info.path))")
            }
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
            Self.enforceDefaultBranchCheckpointRetention(
                retaining: self.state.withLock { Set($0.sessions.keys) })

            // Resolved once at load time (not per request): the IS producer
            // identity is a pure re-derivation from the snapshot on disk.
            let informationProducer = InformationTurnProducer(
                modelIdentity: SimiGoProducerIdentity.canonicalModelIdentity(
                    fromPath: info.path),
                identity: SimiGoProducerIdentity.identity(fromPath: info.path))

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
                    forkBranchHandler: { [weak self] agentId, sessionId, sourceBranch, targetBranch in
                        guard let self else { throw RuntError.notLoaded }
                        return try await self.forkSessionBranch(
                            agentId: agentId,
                            sessionId: sessionId,
                            sourceBranch: sourceBranch,
                            targetBranch: targetBranch
                        )
                    },
                    deleteBranchHandler: { [weak self] agentId, sessionId, branchId in
                        guard let self else { throw RuntError.notLoaded }
                        try await self.deleteSessionBranch(
                            agentId: agentId,
                            sessionId: sessionId,
                            logicalBranchId: branchId
                        )
                    },
                    listBranchesHandler: { [weak self] agentId, sessionId in
                        guard let self else { return (live: [], checkpoints: []) }
                        let branches = self.listSessionBranches(
                            agentId: agentId,
                            sessionId: sessionId
                        )
                        return (live: branches.liveBranches, checkpoints: branches.checkpointFiles)
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
                    },
                    continuationAdmission: { [weak self] esStateID in
                        guard let self else { throw ContinuationAdmissionFailure.unavailable }
                        let modelPath = self.modelPath
                        // The admission's verified bindings are carried forward:
                        // the settlement gate binds THIS request's result against
                        // exactly what this admission verified.
                        let admitted = try await MainActor.run {
                            try SimiGoProducerIdentity.recoverForContinuation(
                                stateID: esStateID, modelPath: modelPath)
                        }
                        return ContinuationAdmissionOutcome(
                            esStateID: esStateID,
                            recoveredValue: admitted.recoveredValue,
                            verifiedBindings: admitted.verifiedBindings,
                            kvBindings: admitted.kvBindings)
                    },
                    continuationSettlement: makeNativeMLXContinuationSettlementHandler(
                        modelPath: self.modelPath
                    ),
                    settlementConsumption: makeNativeMLXSettlementConsumptionHandler(
                        modelPath: self.modelPath
                    ),
                    managedContinuation: makeNativeMLXManagedContinuationHandler(
                        modelPath: self.modelPath,
                        generate: { [weak self] request, messages in
                            guard let self else { throw RuntError.notLoaded }
                            return try await self.generate(
                                requestId: request.requestId,
                                agentId: request.agentId,
                                sessionId: request.sessionId,
                                logicalBranchId: request.logicalBranchId,
                                messages: messages,
                                tools: request.tools,
                                config: request.config,
                                onChunk: { _ in },
                                onToolCall: { _ in }
                            )
                        }
                    ),
                    informationTurnProducer: { informationProducer },
                    requestBudget: { [weak self] requestId, agentId, sessionId,
                        branchId, messages, tools, config, budgetHeaderMs in
                        guard let self else {
                            return RequestBudgetVerdict.unavailable()
                        }
                        return await self.requestBudgetVerdict(
                            requestId: requestId,
                            agentId: agentId,
                            sessionId: sessionId,
                            logicalBranchId: branchId,
                            messages: messages,
                            tools: tools,
                            config: config,
                            budgetHeaderMs: budgetHeaderMs)
                    }
                )
            }

            // LOCALB B1: one shared transport-policy decision for every
            // listener site. Secure by default; LAN binds can never fall
            // back to plaintext; legacy plaintext only via explicit loopback
            // opt-in (SIMIGO_TRANSPORT=legacy-http). Fail-closed decisions
            // surface as typed start() errors.
            if let localbTransportIdentity {
                // Explicit caller-supplied configuration (test/management-
                // plane injection): a fully verified transport identity
                // plus, optionally, the LOCALB request-authorization host.
                // Explicit configuration — never a fallback and never a
                // default open rule; the policy path stays the default.
                server.configureLOCALBTransport(
                    identity: localbTransportIdentity
                )
                if let localbRequestAuthorization {
                    server.configureLOCALBRequestAuthorization(
                        coordinator: localbRequestAuthorization.coordinator,
                        trustedCheckpoint: localbRequestAuthorization
                            .trustedCheckpoint
                    )
                }
            } else {
                // Default resolution: an activated LOCALB host supplies
                // BOTH the transport identity and request authorization
                // from one verified context; before activation this stays
                // transport-only and protected routes remain fail-closed.
                // Verification failures propagate as typed start() errors.
                try LOCALBHostRuntime.applyDefault(
                    to: server,
                    bindHost: nodeConfiguration.bindHost,
                    hostDirectory: localbHostDirectory,
                    keychainStore: keychainStore,
                    transportIdentityStore: transportIdentityStore
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
                $0.postLoadWarmup.modelLoaded()
            }

            // B-6：跨会话 token 前缀池钩子（基配置命名空间）。
            NativeMLXPrefixPool.shared.installHook(
                modelID: modelName(from: info.path),
                kvFingerprint: baseConfig.kvCache.map { String(describing: $0) },
                thinkingDisabled: baseConfig.disableThinking
            )

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
                state.pendingRequestIds.removeAll()
                return (server, tasks, gate)
            }

            // #136：整池随停机归零——内存表示活不过它所属的模型驻留期。
            _ = PrefixMemoryPool.shared.purge(reason: "shutdown")

            if let server {
                await MainActor.run { server.stop() }
            }

            await gate.beginShutdown()
            for task in tasks { task.cancel() }
            for task in tasks { _ = try? await task.value }
            await gate.awaitDrain()

            Memory.clearCache()
            // P1 memory settle（强制版 2026-10-23）：clearCache 只回收 MLX 缓存，
            // 进程 malloc 已释放页仍滞留 → macOS 内存压力长时间黄色。主动请求分配器
            // 归还空闲页（malloc_zone_pressure_relief）后再观测 footprint 回稳，缩短窗口。
            malloc_zone_pressure_relief(nil, 0)
            let settleDeadline = Date().addingTimeInterval(RuntimeTuning.memorySettleTimeoutSeconds)
            var lastFootprint = RuntimeTuning.footprintBytes()
            var stableRounds = 0
            while Date() < settleDeadline, stableRounds < 4 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                let fp = RuntimeTuning.footprintBytes()
                if fp != lastFootprint {
                    stableRounds = 0
                    lastFootprint = fp
                } else {
                    stableRounds += 1
                    // 每轮再请求一次，推动 allocator 持续归还，加快压力回落。
                    malloc_zone_pressure_relief(nil, 0)
                }
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
            if state.withLock({ $0.oversized }) != nil { return }

        let needsResume = state.withLock { $0.isRunning && $0.modelContainer == nil }
        guard needsResume else { return }

        try await lifecycleGate.withLock { [weak self] in
            guard let self else { throw RuntError.notLoaded }
            guard self.state.withLock({ $0.isRunning && $0.modelContainer == nil }) else { return }

            self.state.withLock { $0.lifecycle = .resuming }
            traceLogger.trace("[LIFECYCLE] resume_started")
            let resumeBegan = Date()
            do {
                let container = try await Self.loadModelContainer(path: self.modelPath)
                self.state.withLock {
                    $0.modelContainer = container
                    $0.lifecycle = .running
                    $0.lastActivity = Date()
                    $0.postLoadWarmup.modelLoaded()
                }
                let elapsedMs = Int(Date().timeIntervalSince(resumeBegan) * 1000)
                traceLogger.trace("[LIFECYCLE] resume_done ms=\(elapsedMs)")
                observation.noteResume()
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

    /// 自适应闲置超时：min(cap=360s, max(floor=240s, 最贵会话重建时长估算 + 60s 容错))。
    /// 重建时长按 512 档保守吞吐估算。上限封顶（idleResidencyCapSeconds=360）是为缓解
    /// "推理结束后内存压力长时间黄色"——大会话不再滞留 ~14.5 分钟才卸载，最长 6 分钟；
    /// 下限兜底（idleResidencyFloorSeconds=240）保证小会话工具/思考间隙不反复缴冷启动税。
    /// （2026-10-23 由 max(600s…) 收紧为带 cap 的收敛窗口。）
    private func adaptiveIdleTimeout() async -> TimeInterval {
        #if DEBUG
        if let override = RuntimeTuning.suspendIdleTimeoutOverrideSeconds {
            return override
        }
        #endif
        let sessions = state.withLock { Array($0.sessions.values) }
        var maxTokens = 0
        for managed in sessions {
            let tokens = (try? await managed.session.cacheStatus())?.processedTokenCount ?? 0
            maxTokens = max(maxTokens, tokens)
        }
        let estimate = Double(maxTokens) / RuntimeTuning.prefillThroughputFloor + 60
        // 收敛驻留窗口：floor 兜底小会话、cap 封顶大会话（内存黄色缓解，见 RuntimeTuning）。
        return min(RuntimeTuning.idleResidencyCapSeconds,
                   max(RuntimeTuning.idleResidencyFloorSeconds, estimate))
    }

    public func suspendIfIdle() async -> Bool {
        let idleTimeout = await adaptiveIdleTimeout()
        let eligible = state.withLock { state in
            state.isRunning &&
            state.modelContainer != nil &&
            state.activeRequestTasks.isEmpty &&
            state.pendingRequestIds.isEmpty &&
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
                    state.pendingRequestIds.isEmpty &&
                    Date().timeIntervalSince(state.lastActivity) >= timeout
                }
                guard stillEligible else { return false }

                // Retry the checkpoint path once, but a failed write must not
                // keep ~20 GB resident (owner ruling U3, 2026-10-27): unsettled
                // in-flight output is not a valid result, so it is discarded and
                // the release proceeds.  ES/IS settled anchors remain the only
                // continuity authority; this path never claims a recovery.
                // kv_persist states what THIS suspend actually did, never more:
                // disabled (U2 default) / not_attempted (nothing dirty, or the
                // restore-policy gate skipped it) / attempted (write loop ran;
                // per-key failures carry their own lines).
                var kvPersist = RuntimeTuning.branchCheckpointsEnabled ? "not_attempted" : "disabled"
                if RuntimeTuning.rollforwardEnabled || RuntimeTuning.conditionalRestoreEnabled {
                    let dirty = self.state.withLock { state in
                        state.sessions.compactMap { _, managed -> (AgentExecutionKey, ManagedSession)? in
                            guard managed.checkpointDirty,
                                  let executionKey = managed.executionKey else {
                                return nil
                            }
                            return (executionKey, managed)
                        }
                    }
                    // 持久化关闭时不重试落盘：脏会话直接随 suspend 释放。
                    // 连续性由 ES/IS 的已结算锚点承担，未结算的在途生成本来
                    // 就不是有效结果，恢复时从合格锚点重跑。
                    if RuntimeTuning.branchCheckpointsEnabled, !dirty.isEmpty {
                        var unreleased: [String] = []
                        if let container = self.state.withLock({ $0.modelContainer }) {
                            kvPersist = "attempted"
                            let gate = self.gateHolder.withLock { $0 }
                            for (executionKey, managed) in dirty {
                                do {
                                    let retryGateKey = try self.generationGateKey(for: executionKey)
                                    _ = try await gate.withExclusive(retryGateKey) { [weak self] in
                                        guard let self else { throw RuntError.notLoaded }
                                        return try await self.performSave(
                                            key: executionKey.storageKey,
                                            traceKey: executionKey.traceKey,
                                            container: container,
                                            managed: managed,
                                            directory: Self.defaultBranchCheckpointStore(),
                                            modelPath: self.modelPath
                                        )
                                    }
                                    managed.checkpointDirty = false
                                } catch {
                                    unreleased.append(executionKey.traceKey)
                                    self.traceLogger.trace(
                                        "[LIFECYCLE] checkpoint_write_failed key=\(executionKey.traceKey)"
                                            + " err=\(error.localizedDescription)"
                                    )
                                }
                            }
                        } else {
                            kvPersist = "skipped_container_unavailable"
                            unreleased = dirty.map { executionKey, _ in executionKey.traceKey }
                            self.traceLogger.trace(
                                "[LIFECYCLE] checkpoint_write_skipped reason=container_unavailable"
                                    + " count=\(dirty.count)"
                            )
                        }
                        if !unreleased.isEmpty {
                            self.traceLogger.trace(
                                "[LIFECYCLE] suspend_releases_unsettled count=\(unreleased.count)"
                                    + " settled=false authority=es_is_anchor"
                            )
                        }
                    }
                }

                // §8 G3 tier 1: observe the runtime state BEFORE and AFTER the
                // suspend mutation, so the release below is measured, not asserted.
                var sessionsBefore = 0
                var containerPresentBefore = false
                var sessionsAfter = -1
                var containerAbsentAfter = false
                let releasedCount = self.state.withLock { state -> Int in
                    sessionsBefore = state.sessions.count
                    containerPresentBefore = state.modelContainer != nil
                    state.lifecycle = .suspended
                    state.modelContainer = nil
                    state.sessions.removeAll()
                    state.lastActivity = Date()
                    sessionsAfter = state.sessions.count
                    containerAbsentAfter = state.modelContainer == nil
                    return sessionsBefore
                }
                // Logical REFERENCE release (NOT proof of physical memory return).
                self.observation.noteReferenceRelease(
                    sessionsReleased: releasedCount,
                    sessionsAfter: sessionsAfter,
                    containerPresentBefore: containerPresentBefore,
                    containerAbsentAfter: containerAbsentAfter)
                // #136：内存前缀池随模型卸载归零。表示只在权重驻留期间
                // 有意义，容器一放手就必须作废——连续性由 ES/IS 的已结算
                // 锚点承担，不靠这些字节。memPoolPurge 行是 §IV.4 的取证点。
                _ = PrefixMemoryPool.shared.purge(reason: "suspend")
                Memory.clearCache()
                // §8 G3 tier 2: explicit resource-reclaim OPERATION invoked (MLX cache).
                self.observation.noteResourceReclaim()
                // 强制分配器归还空闲页，避免挂起后内存压力长时间黄色（2026-10-23）。
                malloc_zone_pressure_relief(nil, 0)
                self.traceLogger.trace(
                    "[LIFECYCLE] suspend_done released_sessions=\(releasedCount)"
                        + " kv_persist=\(kvPersist)")
                self.observation.noteSuspend()
                return true
            }
        } catch {
            // 外审 P1 错误传播链（2026-09-19）：suspend 失败静默 false 会让
            // "空闲未挂起"在 trace 上不可见；其余生命周期路径均有日志。
            traceLogger.trace(
                "[LIFECYCLE] suspend_failed err=\(error.localizedDescription)")
            return false
        }
    }

    private nonisolated func generationGateKey(
        for executionKey: AgentExecutionKey
    ) throws -> AgentExecutionKey {
        guard RuntimeTuning.serializeGeneration else { return executionKey }
        return try AgentExecutionKey(
            agentId: executionKey.agentId,
            sessionId: "__global_generation__",
            logicalBranchId: executionKey.logicalBranchId
        )
    }

    // MARK: - W4/A request budget (P2)

    /// 渲染后计数：与引擎 `ChatSession` 同一条 `processor.prepare` 与同一组
    /// tools/additionalContext，得到的就是本轮会被预填的 token 序列。
    private static func budgetRenderedTokens(
        chat: [Chat.Message],
        tools: [ToolSpec]?,
        additionalContext: [String: any Sendable]?,
        container: ModelContainer
    ) async -> [Int]? {
        do {
            let input = try await container.prepare(
                input: UserInput(
                    chat: chat,
                    tools: tools,
                    additionalContext: additionalContext))
            return input.text.tokens.asArray(Int.self)
        } catch {
            return nil
        }
    }

    private func budgetIdentity(thinkingDisabled: Bool) -> RequestBudgetIdentity? {
        let path = modelPath
        var cached = budgetIdentityCache.value
        if cached?.path != path {
            let identity = SimiGoProducerIdentity.identity(fromPath: path)
            let entry = (
                path: path,
                model: identity.model,
                tokenizer: identity.tokenizer
            )
            budgetIdentityCache.set(entry)
            cached = entry
        }
        guard let cached else { return nil }
        // 模板身份：tokenizer 内容指纹已覆盖 tokenizer_config.json（含
        // chat_template 原文）与 vocab 文件；逐请求唯一会改写模板行为的
        // 开关是 thinking，单独进身份——禁用模板的样本不得喂给启用请求。
        return RequestBudgetIdentity(
            model: cached.model,
            tokenizer: cached.tokenizer,
            template: "thinking=\(thinkingDisabled ? "disabled" : "enabled")")
    }

    private static func budgetInactiveVerdict(
        _ kind: RequestBudgetVerdictKind,
        bucket: String,
        budgetMs: Int,
        maxTokens: Int,
        tokens: Int = 0,
        digest: String = ""
    ) -> RequestBudgetVerdict {
        RequestBudgetVerdict(
            kind: kind,
            promptTokens: tokens,
            estimatedPrefillMs: 0,
            budgetMs: budgetMs,
            prefillBudgetMs: RequestBudgetController.prefillBudgetMs(
                budgetMs: budgetMs, maxTokens: maxTokens),
            samples: 0,
            bucket: bucket,
            promptDigest: digest,
            rateTokPerSecond: nil,
            priorProcessed: nil,
            priorTotal: nil,
            priorElapsedMs: nil,
            priorRequestID: nil,
            cached: false,
            memoryMatchedTokens: 0)
    }

    /// W4/A：协议层在 IS 注入准备完成后、任何 SSE 流头与生成启动之前调用。
    ///
    /// 判定输入必须是渲染后的 prompt token（模板 + tools + thinking 上下文
    /// 全部生效），不是字节数估算或内容下界。冷轮按全量渲染计数，已有同键
    /// 会话且前缀匹配时只计 delta（热桶）。门不参与 KV 复用决策，只在
    /// 估算/观测表明预算内做不完时拒绝，避免把同一份输入反复预填。
    public func requestBudgetVerdict(
        requestId: String,
        agentId: String?,
        sessionId: String,
        logicalBranchId: String,
        messages: [JSONValue],
        tools: [JSONValue]?,
        config: ModelConfig,
        budgetHeaderMs: Int? = nil
    ) async -> RequestBudgetVerdict {
        let budgetMs =
            budgetHeaderMs.flatMap { $0 > 0 ? $0 : nil } ?? RuntimeTuning.requestBudgetMs
        let maxTokens = config.maxTokens > 0 ? config.maxTokens : baseConfig.maxTokens
        RequestBudgetController.shared.prepare()

        // 研究态：前缀池命中会提供门无法建模的暖表示（池内 token 边界命中
        // 时本轮根本不做全量预填）。产品默认关闭，开启即实验模式：门如实
        // 声明未生效，不得把放行报作拦截。
        let restorePolicy = ExecutionPolicy.ConditionalRestoreConfiguration.current()
        if RuntimeTuning.prefixPoolEnabled {
            let verdict = Self.budgetInactiveVerdict(
                .poolActive, bucket: "unknown", budgetMs: budgetMs, maxTokens: maxTokens)
            traceLogger.trace(
                "[BUDGET] r=\(requestId) verdict=pool_active gate=inactive reason=prefix_pool_enabled")
            return verdict
        }
        guard budgetMs > 0 else {
            let verdict = Self.budgetInactiveVerdict(
                .disabled, bucket: "unknown", budgetMs: budgetMs, maxTokens: maxTokens)
            traceLogger.trace("[BUDGET] r=\(requestId) verdict=disabled gate=inactive")
            return verdict
        }
        guard let container = state.withLock({ $0.modelContainer }) else {
            let verdict = Self.budgetInactiveVerdict(
                .estimateUnavailable, bucket: "unknown",
                budgetMs: budgetMs, maxTokens: maxTokens)
            traceLogger.trace(
                "[BUDGET] r=\(requestId) verdict=estimate_unavailable gate=inactive reason=model_not_loaded")
            return verdict
        }
        guard
            let executionKey = try? AgentExecutionKey.resolve(
                agentId: agentId,
                sessionId: sessionId,
                logicalBranchId: logicalBranchId)
        else {
            let verdict = Self.budgetInactiveVerdict(
                .estimateUnavailable, bucket: "unknown",
                budgetMs: budgetMs, maxTokens: maxTokens)
            traceLogger.trace(
                "[BUDGET] r=\(requestId) verdict=estimate_unavailable gate=inactive reason=identity_unresolved")
            return verdict
        }

        let thinkingDisabled = config.disableThinking || baseConfig.disableThinking
        let kvSettings = config.kvCache ?? baseConfig.kvCache
        let kvFingerprint = kvSettings.map { String(describing: $0) }
        let toolSpecs = Self.makeToolSpecs(tools)
        let additionalContext: [String: any Sendable]? =
            thinkingDisabled ? ["enable_thinking": false] : nil

        var incoming = Self.makeChatMessages(messages)
        if incoming.isEmpty {
            let verdict = Self.budgetInactiveVerdict(
                .emptyTranscript, bucket: "unknown",
                budgetMs: budgetMs, maxTokens: maxTokens)
            traceLogger.trace(
                "[BUDGET] r=\(requestId) verdict=empty_transcript gate=inactive")
            return verdict
        }

        guard let identity = budgetIdentity(thinkingDisabled: thinkingDisabled)
        else {
            let verdict = Self.budgetInactiveVerdict(
                .estimateUnavailable, bucket: "unknown",
                budgetMs: budgetMs, maxTokens: maxTokens)
            traceLogger.trace(
                "[BUDGET] r=\(requestId) verdict=estimate_unavailable gate=inactive reason=identity_unavailable")
            return verdict
        }

        // 热/冷判定与生成路径同一判据（mapKey + KV 指纹 + 消息前缀），
        // 差异只在用途：这里不做任何会话移动，只决定计数口径。
        let mapKey = Self.sessionMapKey(
            storageKey: executionKey.storageKey,
            firstMessage: incoming.first.map { (role: $0.role.rawValue, content: $0.content) }
        )
        let existing = state.withLock { $0.sessions[mapKey] }
        var bucket = "cold"
        var cachedPrefixTokens = 0
        var gateMessages = messages
        if let existing,
            incoming.count > existing.history.count,
            existing.kvFingerprint == kvFingerprint {
            let echoNormalization = Self.normalizeToolEcho(
                messages, against: existing.historyJSON)
            let candidate = echoNormalization.changed
                ? Self.makeChatMessages(echoNormalization.messages) : incoming
            if Self.isPrefix(existing.history, of: candidate) {
                bucket = "hot"
                incoming = candidate
                if echoNormalization.changed {
                    gateMessages = echoNormalization.messages
                }
                if let historyTokens = await Self.budgetRenderedTokens(
                    chat: existing.history,
                    tools: toolSpecs,
                    additionalContext: additionalContext,
                    container: container
                ) {
                    cachedPrefixTokens = historyTokens.count
                }
            }
        }

        // Conditional Restore 只有真会接管本轮时才跳过全量预填，才轮到门
        // 让位。它需要全部条件同时成立：checkpoint 落盘开启（U2 默认关）、
        // 命中活会话、账本尾 assistant 带 tool_calls、delta 规模门放行。
        // conditionalRestoreEnabled 默认是 true——只看这个 flag 会把默认
        // 产品态的门永远判成不活跃，等于 W4 没有接通。
        if bucket == "hot", let existing,
            RuntimeTuning.branchCheckpointsEnabled,
            ExecutionPolicy.rollforwardRisk(lastJSON: existing.historyJSON.last),
            ExecutionPolicy.conditionalRestoreGate(
                configuration: restorePolicy,
                incoming: gateMessages,
                ledgerCount: existing.historyJSON.count) == .allowed {
            let verdict = Self.budgetInactiveVerdict(
                .restoreActive, bucket: bucket,
                budgetMs: budgetMs, maxTokens: maxTokens)
            traceLogger.trace(
                "[BUDGET] r=\(requestId) verdict=restore_active gate=inactive reason=conditional_restore_would_take_over")
            return verdict
        }

        guard
            let fullTokens = await Self.budgetRenderedTokens(
                chat: incoming,
                tools: toolSpecs,
                additionalContext: additionalContext,
                container: container)
        else {
            let verdict = Self.budgetInactiveVerdict(
                .estimateUnavailable, bucket: bucket,
                budgetMs: budgetMs, maxTokens: maxTokens)
            traceLogger.trace(
                "[BUDGET] r=\(requestId) verdict=estimate_unavailable gate=inactive reason=render_failed bucket=\(bucket)")
            return verdict
        }

        // #136/W4：冷重建轮先问内存池——只有走完采纳那道门（同命名空间、ES
        // 身份逐字相等、链哈希对账、bind 权威）的边界才算数。命中多少就少
        // 预填多少；探不到就是 0，按完整冷 prefill 估算。热桶不叠加：那段
        // 前缀已由活会话付过，再扣一次等于双重抵扣。
        let memoryMatched = bucket == "hot" ? 0 : memoryPoolCreditTokens(
            promptTokens: fullTokens,
            kvFingerprint: kvFingerprint,
            thinkingDisabled: thinkingDisabled,
            logicalBranchId: executionKey.logicalBranchId)
        // 计数口径：冷＝全量渲染 token，热＝活会话没覆盖的 delta。内存池抵扣
        // 由判定自己减（`decide` 里唯一的减法），这里只报基数，否则一处估算
        // 用扣后的、另一处用扣前的。
        let tokens = bucket == "hot"
            ? max(1, fullTokens.count - cachedPrefixTokens)
            : fullTokens.count
        let digest = RequestBudgetDigest.of(
            tokens: fullTokens.map { Int32(truncatingIfNeeded: $0) },
            model: identity.model)
        let controller = RequestBudgetController.shared
        controller.rememberPromptDigest(requestID: requestId, digest: digest)
        let verdict = controller.decide(
            identity: identity,
            bucket: bucket,
            promptDigest: digest,
            tokens: tokens,
            budgetMs: budgetMs,
            maxTokens: maxTokens,
            memoryMatchedTokens: memoryMatched)
        traceLogger.trace(budgetLogLine(
            requestId: requestId, verdict: verdict, fullTokens: fullTokens.count,
            deltaTokens: tokens))
        if verdict.isReject, RequestBudgetController.admissionEnforcementEnabled {
            // 独立一行、每笔拒绝都留痕：RejectBurstTracker 只服务 CONTEXT
            // SAFETY 的 L1 压缩风暴（10s 窗口内成员笔被抑制），预算拒绝不入
            // 该聚合——否则「请求被拒」会被读成「请求消失」。
            // ADR 2026-10-30：准入拒绝已下线，本行只在（当前恒为假的）
            // 强制开关打开时才写，避免把「本应被拒但已准入」记成 503。
            traceLogger.trace(budgetRejectLogLine(
                requestId: requestId, verdict: verdict))
        }
        return verdict
    }

    /// #136/W4：内存前缀池的**只读**预探测。走的是采纳那一道门的同一个实现
    /// （`PrefixMemoryPool.provenMatchTokenCount`）：命名空间、ES 身份逐字
    /// 相等、链哈希对账、`bindVerdict` 权威全过才算数。不克隆、不刷新
    /// `lastUsedAt`、不注销授权——权威用 `peekBindAuthority` 只读取，bind
    /// 站点的 consume 时机与改动前逐字节一致。探不到返回 0，门按完整冷
    /// prefill 估算，绝不因为「池里有个像的条目」就把注定超时的尝试放行。
    private func memoryPoolCreditTokens(
        promptTokens: [Int],
        kvFingerprint: String?,
        thinkingDisabled: Bool,
        logicalBranchId: String?
    ) -> Int {
        guard RuntimeTuning.prefixMemoryPoolEnabled, promptTokens.count > 1 else { return 0 }
        let namespace = NativeMLXPrefixPool.namespace(
            modelID: modelName(from: modelPath),
            kvFingerprint: kvFingerprint,
            thinkingDisabled: thinkingDisabled)
        let authority: ISKVBindAuthority.Lookup
        if let logicalBranchId {
            authority = NativeMLXPrefixPool.shared.peekBindAuthority(esStateID: logicalBranchId)
        } else {
            authority = .notGoverned
        }
        return PrefixMemoryPool.shared.provenMatchTokenCount(
            promptTokenIds: promptTokens,
            namespace: namespace,
            esStateID: logicalBranchId,
            authority: authority
        ) ?? 0
    }

    private func budgetLogLine(
        requestId: String,
        verdict: RequestBudgetVerdict,
        fullTokens: Int,
        deltaTokens: Int
    ) -> String {
        var line =
            "[BUDGET] r=\(requestId) verdict=\(verdict.kind.wireName)" +
            " gate=\(verdict.gateWasActive ? "active" : "inactive")" +
            " bucket=\(verdict.bucket)" +
            " promptTokens=\(verdict.promptTokens)" +
            " renderedTokens=\(fullTokens) deltaTokens=\(deltaTokens)" +
            " budget=\(verdict.budgetMs)" +
            " prefillBudget=\(verdict.prefillBudgetMs)" +
            " estMs=\(verdict.estimatedPrefillMs)" +
            " samples=\(verdict.samples)"
        if let rate = verdict.rateTokPerSecond {
            line += String(format: " rate=%.1f", rate)
        }
        if !verdict.promptDigest.isEmpty {
            line += " digest=\(verdict.promptDigest.prefix(12))"
        }
        if verdict.cached {
            line += " cached=1"
        }
        if verdict.memoryMatchedTokens > 0 {
            line += " memMatched=\(verdict.memoryMatchedTokens)"
        }
        if let processed = verdict.priorProcessed, let total = verdict.priorTotal,
            let elapsed = verdict.priorElapsedMs {
            line += " priorAttempt=\(processed)/\(total)@\(elapsed)ms"
        }
        if verdict.isReject, !RequestBudgetController.admissionEnforcementEnabled {
            line += " enforced=0"
        }
        return line
    }

    private func budgetRejectLogLine(
        requestId: String,
        verdict: RequestBudgetVerdict
    ) -> String {
        var line =
            "[BUDGET_REJECT] r=\(requestId) verdict=\(verdict.kind.wireName)" +
            " bucket=\(verdict.bucket) tokens=\(verdict.promptTokens)" +
            " estMs=\(verdict.estimatedPrefillMs)" +
            " prefillBudget=\(verdict.prefillBudgetMs)" +
            " samples=\(verdict.samples)"
        if verdict.cached {
            line += " cached=1"
        }
        if let processed = verdict.priorProcessed, let total = verdict.priorTotal,
            let elapsed = verdict.priorElapsedMs, let prior = verdict.priorRequestID {
            line += " priorAttempt=\(processed)/\(total)@\(elapsed)ms prior=\(prior.prefix(8))"
        }
        line += " action=prefill_budget_exceeded status=503"
        return line
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
        var reservationError: RuntError?
        state.withLock { state in
            guard state.isRunning else {
                reservationError = .notLoaded
                return
            }
            guard state.activeRequestTasks[requestId] == nil,
                  !state.pendingRequestIds.contains(requestId) else {
                reservationError = .generationFailed("Duplicate request ID: \(requestId)")
                return
            }
            state.pendingRequestIds.insert(requestId)
        }
        if let reservationError {
            // Preserve the existing lineage contract: admission-time
            // notLoaded/duplicate failures are still failed executions.
            _ = try AgentExecutionKey.resolve(
                agentId: agentId,
                sessionId: sessionId,
                logicalBranchId: logicalBranchId
            )
            let executionId = UUID().uuidString.lowercased()
            lineage.begin(ExecutionRecord(
                executionId: String(executionId), requestId: requestId,
                agentId: agentId, sessionId: sessionId,
                logicalBranchId: logicalBranchId, status: .running,
                startedAt: Date()))
            lineage.end(executionId: String(executionId), status: .failed)
            throw reservationError
        }
        defer {
            state.withLock {
                $0.pendingRequestIds.remove(requestId)
                $0.activeRequestTasks.removeValue(forKey: requestId)
                $0.lastActivity = Date()
            }
        }

        if let oversized = state.withLock({ $0.oversized }) {
            return try await oversized.handleGenerate(
                messages: messages, maxTokens: config.maxTokens, onChunk: onChunk
            )
        }
        try await ensureLoaded()

        let executionKey = try AgentExecutionKey.resolve(
            agentId: agentId,
            sessionId: sessionId,
            logicalBranchId: logicalBranchId
        )
        // executionId 仍供 Lineage / 生命周期终态使用，但不再输出
        // [EXEC] begin 埋点。
        let executionId = UUID().uuidString.lowercased()
        lineage.begin(ExecutionRecord(
            executionId: String(executionId), requestId: requestId,
            agentId: agentId, sessionId: sessionId,
            logicalBranchId: logicalBranchId, status: .running,
            startedAt: Date()))

        do {
        // P0-3 强化：全局生成串行化。gate key 常量化使所有生成跨 session 单飞，
        // 规避 qwen3_5_moe 动态编译架构在并发首次编译时的 mlx 锁互堵
        // （sessions 存储仍用真实 executionKey，仅互斥令牌常量化）。
        let gateExecutionKey = try self.generationGateKey(for: executionKey)

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
                    executionId: executionId,
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
            guard state.activeRequestTasks[requestId] == nil,
                  state.pendingRequestIds.contains(requestId) else {
                registrationError = .generationFailed("Duplicate request ID: \(requestId)")
                return
            }
            state.activeRequestTasks[requestId] = task
            state.pendingRequestIds.remove(requestId)
        }

        if let registrationError {
            task.cancel()
            throw registrationError
        }

        let result = try await withTaskCancellationHandler(
            operation: { try await task.value },
            onCancel: { task.cancel() }
        )
        lineage.end(executionId: String(executionId), status: .completed)
        return result
        } catch {
            let status: ExecutionStatus = error is CancellationError
                ? .cancelled : .failed
            lineage.end(executionId: String(executionId), status: status)
            throw error
        }
    }

    private func generateUsingChatSession(
        requestId: String,
        executionKey: AgentExecutionKey,
        executionId: String,
        messages: [JSONValue],
        tools: [JSONValue]?,
        config: ModelConfig,
        onChunk: @escaping @Sendable (String) -> Void,
        onToolCall: @escaping @Sendable (ParsedToolCall) -> Void
    ) async throws -> GenerationResult {
        guard let container = state.withLock({ $0.modelContainer }) else {
            throw RuntError.notLoaded
        }
        // S3：配置面一次性快照（外审七轮 P1 关注点——单请求单快照，
        // 门判定与 checkpoint save 门全程只消费快照，防跨时刻拼凑）。
        let restorePolicy = ExecutionPolicy.ConditionalRestoreConfiguration.current()
        // §II.3：本轮 ES 权威在函数作用域一次性只读取值。磁盘准入在 bind
        // 站点注销它，内存采纳（引擎 prefill 期间发生）必须消费同一份快照，
        // 否则第二次查询只会拿到 `.notGoverned`＝自己给自己放行。日常轮次
        // 无登记＝`.notGoverned`，两池行为与本改动之前逐字节一致。
        let bindLookup = NativeMLXPrefixPool.shared.peekBindAuthority(
            esStateID: executionKey.logicalBranchId)

        // 入站转录归一化（2026-10-15）可能改写回传形态，自此后以 var 流转。
        var messages = messages
        var incoming = Self.makeChatMessages(messages)
        guard !incoming.isEmpty else {
            // Nothing was generated, so nothing can be attested as finished.
            return GenerationResult(text: "", usage: nil, completion: .unconfirmed)
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
        // W4/A：取消轮的实际预填进度——同 payload 重试据此判断「这份输入
        // 在本机已经跑不完一次」，而不是每次当全新请求再付一遍。
        // startedAt 记录第一次进度回调的时刻：预填耗时不能把排队/加载时间
        // 算进来，否则未完成轮的投影会把等队列的秒数当成预填速度。
        let prefillProgress =
            Locked((processed: 0, total: 0, startedAt: Date?.none))
            params.prefill.progress = { processed, total in
                let startedAt = prefillProgress.value.startedAt ?? Date()
                prefillProgress.set((processed, total, startedAt))
                // 4096（原 16384）：roll-forward delta ~12k 时中途零心跳被
                // 误读为挂起（2026-09-18 真机），阈值须低于单轮 delta 量级。
                if processed == total || processed - prefillLogged.value >= 4096 {
                prefillLogged.set(processed)
                RuntimeTraceLogger.shared.trace("[MLX] prefill \(processed)/\(total)")
                if processed == total { self.observation.notePrefillTotal(total) }
            }
        }
        let toolSpecs = Self.makeToolSpecs(tools)
        let additionalContext: [String: any Sendable]? = thinkingDisabled ? ["enable_thinking": false] : nil

        // CONTEXT SAFETY 门（2026-10-15 复线）：404f9d4 ChatSession 重构曾
        // 把超限拒绝整段删除——超 ctx 的巨型 prompt（实测 235K vs 131072）
        // 会进入注定失败的预填并随 KV 增长单调劣化至 45 tok/s。字节快门
        // 放行常规请求；巨型 payload 才 tokenizer 精确复核，下界超限即拒。
        if let budget = Self.contextSafetyBudget(
            config: config,
            base: baseConfig,
            contract: state.withLock({ $0.modelCapabilityContract })
        ) {
            let contentBytes = Self.contentByteDemand(messages: messages, tools: tools)
            if contentBytes > budget {
                let demand = await Self.contentTokenDemand(
                    messages: messages,
                    tools: tools,
                    container: container
                )
                if demand > budget {
                    // 首尾记录（2026-10-16）：风暴头笔保留完整 REJECT 行，
                    // 成员笔抑制、由 burstSuppressed 聚合尾行收口。
                    let burstMember = RejectBurstTracker.shared.noteReject(
                        key: executionKey.storageKey,
                        requestID: requestId,
                        demand: demand
                    )
                    if !burstMember {
                        traceLogger.trace(
                            "[CONTEXT SAFETY REJECT] demand=\(demand) budget=\(budget)" +
                            " contentBytes=\(contentBytes) action=require_L1_compaction"
                        )
                    }
                    throw NativeMLXValidationError.contextDemandExceeded(demand, budget)
                }
            }
        }

        // 过门即冲刷同键拒绝风暴的聚合尾行（若有）。
        RejectBurstTracker.shared.noteAdmitted(
            key: executionKey.storageKey
        )

        // #90 A：所有权转移在 adoptLiveSession 的临界区内完成，本键不随后改写。
        let mapKey = Self.sessionMapKey(
            storageKey: executionKey.storageKey,
            firstMessage: incoming.first.map { (role: $0.role.rawValue, content: $0.content) }
        )
        let existing = state.withLock { $0.sessions[mapKey] }
        var managed: ManagedSession
        var reusedSession = false
        // Route B 前缀池命中轮：本会话的表示来自共享池快照（已对账），
        // roll-forward 无需再对其做 conditional restore。
        var poolRestoredTurn = false
        /// #90 A：本轮从另一个请求级身份键上接手了活分片（所有权转移，
        /// 不是共享别名）。取消时按「本轮分片 + 同源别名」整体逐出。
        var adoptedForeignShard = false

        let kvFingerprint = kvSettings.map { String(describing: $0) }

        if let existing,
           incoming.count > existing.history.count,
           existing.kvFingerprint == kvFingerprint,
           Self.isPrefix(existing.history, of: incoming) {
            managed = existing
            managed.lastActivity = Date()
            reusedSession = true
            // 入站转录工具回声归一化（2026-10-15 批准）：客户端回传的
            // 工具轮形态（split 文本位+调用位 / 参数再序列化）对齐到
            // 账本权威形态，delta 回到纯新增消息——引擎不再对已生成区
            // 重渲染对账（16:55/16:58 两轮 12.3KB/4.9KB 参数触发
            // fork-no-rewind 132s/218s 全量重渲的根因收口）。
            let echoNormalization = Self.normalizeToolEcho(
                messages, against: managed.historyJSON)
            if echoNormalization.changed {
                traceLogger.trace(
                    "[MLX] toolEchoNormalize key=\(executionKey.traceKey)" +
                    " merged=\(echoNormalization.mergedPairs)" +
                    " replaced=\(echoNormalization.replacedCalls)")
                messages = echoNormalization.messages
                incoming = Self.makeChatMessages(messages)
            }
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
                    observation.noteReuseMiss()
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
                traceLogger.trace(
                    Self.prefixDiffLine(
                        index: mismatch,
                        stored: historyMessage,
                        incoming: incomingMessage
                    )
                )
                observation.notePrefixMismatch()
            }
            // Route B 前缀池（SIMIGO17）：冷重建前先查跨会话共享池。
            // 命中即 cacheLoad 恢复同款形态（快照 KV + delta 契约），
            // 只付自己的尾巴——47.6s 冷税变快照加载 + delta prefill。
            var poolRestored: ManagedSession?
            var poolAdmission = NativeMLXPrefixPool.shared.admit(
                modelID: modelName(from: modelPath),
                kvFingerprint: kvFingerprint,
                thinkingDisabled: thinkingDisabled,
                incoming: incoming.map { (role: $0.role.rawValue, content: $0.content) }
            )
            // A-2 前置权威：这条边只在续跑准入发生时受门禁约束。
            // 未受管（日常路径）逐字节保持 A-2 之前行为；被拒 = IS 没有为这个
            // ES 结算过这条前缀边界，于是回退冷 prefill —— 盘上确实存在该
            // 表示并不构成复用许可。
            if let candidate = poolAdmission {
                let bindGate = NativeMLXPrefixPool.shared.checkBindAuthority(
                    esStateID: executionKey.logicalBranchId,
                    modelID: modelName(from: modelPath),
                    kvFingerprint: kvFingerprint,
                    thinkingDisabled: thinkingDisabled,
                    entry: candidate.entry
                )
                if !bindGate.permitsBind {
                    traceLogger.trace(
                        "[MLX] isKvBindRejected reason=\(bindGate.rejectionReason ?? "kv_binding_blocked")"
                            + " messages=\(candidate.entry.tokenCount / 2)"
                            + " key=\(executionKey.traceKey)"
                    )
                    observation.noteISKVBindRejected()
                    poolAdmission = nil
                }
            }
            if let poolAdmission {
                do {
                    let snapshot = try await NativeMLXPrefixPool.shared.load(poolAdmission)
                    let coveredMessages = poolAdmission.entry.tokenCount / 2
                    let session = ChatSession(
                        container,
                        cache: snapshot.cache,
                        state: snapshot.state,
                        generateParameters: params,
                        additionalContext: additionalContext
                    )
                    let restored = ManagedSession(
                        session: session,
                        history: Array(incoming.prefix(coveredMessages)),
                        historyJSON: Array(messages.prefix(coveredMessages)),
                        kvFingerprint: kvFingerprint,
                        isRestoredSnapshot: true,
                        thinkingDisabled: thinkingDisabled
                    )
                    state.withLock { $0.sessions[mapKey] = restored }
                    poolRestored = restored
                    // FORK-3 step-9: the child binds the SAME RepresentationRef
                    // the exporting parent bound — zero re-materialization is
                    // structural (the registry has no store parameter).
                    let boundRef = NativeMLXPrefixPool.representationRef(
                        namespace: NativeMLXPrefixPool.namespace(
                            modelID: modelName(from: modelPath),
                            kvFingerprint: kvFingerprint,
                            thinkingDisabled: thinkingDisabled),
                        boundaryHash: poolAdmission.entry.boundaryHash,
                        boundLength: poolAdmission.entry.tokenCount)
                    let childBinding = NativeMLXPrefixPool.shared.bindings.bind(
                        executionID: executionKey.storageKey,
                        runtimeAddress: "live:\(executionKey.storageKey)",
                        ref: boundRef)
                    traceLogger.trace(
                        "[MLX] poolBind messages=\(coveredMessages) delta=\(incoming.count - coveredMessages)"
                            + " bindingGen=\(childBinding.generation)"
                            + " refHash=\(String(poolAdmission.entry.boundaryHash, radix: 16))"
                    )
                    observation.notePoolBindHit()
                } catch {
                    // P-I1 响亮失败已在适配器内自愈（条目已删）；
                    // 本轮回退冷路径，绝不静默续算在未对账表示上。
                    traceLogger.trace(
                        "[MLX] poolBindFailed err=\(error.localizedDescription)")
                    observation.notePoolBindFailed()
                }
            }
            if let restored = poolRestored {
                managed = restored
                reusedSession = true
                poolRestoredTurn = true
            } else if existing == nil,
                      AgentExecutionKey.isRequestScopedSession(executionKey.storageKey),
                      let adopted = adoptLiveSession(
                        incoming: incoming,
                        kvFingerprint: kvFingerprint,
                        thinkingDisabled: thinkingDisabled,
                        owner: executionKey,
                        ownerKey: mapKey,
                        requestId: requestId) {
                // #90 A 跨请求活会话续接：客户端每轮携带新的请求级
                // sessionId、转录逐条追加时，命中同进程内另一请求留下的
                // 兼容分片——本轮只付 delta，不再逐轮冷 prefill。兼容判据
                // 全部在 SessionAdoption（同 agent 作用域 + 严格前缀 + kv 指纹
                // + thinking 配置 + 不在途 + 仅请求级分片），任一不成立即落到
                // 下面的冷路径。放在池查询之后：默认关闭的池不参与产品结论，
                // 开启态（研究对照）保持既有池优先语义不被本次改动遮蔽。
                //
                // 认领即所有权转移（adoptLiveSession 锁内完成）：分片已从
                // 原请求键摘下、登记到本轮 mapKey 下，执行身份同时重绑到
                // 本轮请求。此后成功写回、在途标记与取消逐出都只命中本键。
                // 原请求若重放自己的旧转录（比手中历史更短），长度判据
                // `historyCount < incomingCount` 不成立 ⇒ 不采纳、走冷路径，
                // 于是本轮推进的分支不会反向写进原请求的映射。
                managed = adopted.session
                reusedSession = true
                adoptedForeignShard = true
                let fromTail = adopted.fromKey.split(separator: "#").first?
                    .split(separator: "-").last.map { String($0.suffix(6)) }
                    ?? String(adopted.fromKey.suffix(6))
                traceLogger.trace(
                    "[MLX] sessionAdopt key=\(executionKey.traceKey)" +
                    " from=\(fromTail) own=transfer" +
                    " history=\(adopted.session.history.count)" +
                    " incoming=\(incoming.count)" +
                    " delta=\(incoming.count - adopted.session.history.count)"
                )
                observation.noteSessionAdopt()
            } else {
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
                    kvFingerprint: kvFingerprint,
                    thinkingDisabled: thinkingDisabled
                )
                reusedSession = false
                observation.noteColdRebuild()
                state.withLock { $0.sessions[mapKey] = managed }
                if mapKey != executionKey.storageKey {
                    // 展示走 traceKey 紧凑形态（6 位），全量 UUID 不进 trace。
                    traceLogger.trace(
                        "[MLX] sessionClientSplit key=\(executionKey.traceKey)" +
                        "\(String(mapKey.dropFirst(executionKey.storageKey.count)))" +
                        " note=system-prompt client shard"
                    )
                }
            }
        }

        // Phase B roll-forward（2026-09-18，探索文档 §5/§6）：账本尾部 assistant
        // 含多键 tool_calls ⇒ 下一轮全模板重渲染可能键序分叉（TodoWrite 家族）
        // → 同 key 恢复 checkpoint 进入 fragment-continuation（raw-cache 无账本
        // → 无比较 → 无分歧）。误报代价 = loadSessionCache 0.01s（Phase A 实测），
        // 漏报代价 = 分歧税 300-490s。恢复失败/不兼容 → 回退活会话继续。
        // Conditional Restore（V1.5 主轨道）：触发前再过 delta 规模门——只吃
        // 小 delta 轮（162 fork 样本实测：分歧全在尾段、rebuild 170-248 vs
        // 恢复态 94-139 tok/s ⇒ delta<0.8×full 恒赢；大 delta 交回 extend）。
        var rolledForward = false
        // EXP-B：hedge-skip 判定（B_HEDGE_SKIP_EXPERIMENT_DESIGN §1）。
        // 仅在 restore 本会触发的轮次（复用会话 + 工具尾）评估；env 关闭时
        // 恒 false = 实验 A 行为，逐字节不变。
        let restoreRiskFires = RuntimeTuning.branchCheckpointsEnabled
            && reusedSession && !poolRestoredTurn
            && ExecutionPolicy.rollforwardRisk(lastJSON: managed.historyJSON.last)
        let hedgeSkip = restoreRiskFires
            && RuntimeTuning.expHedgeSkipEnabled
            && managed.lastCompletionMode == "extend"
            && (managed.lastCompletionCacheEff ?? 0) >= RuntimeTuning.expHedgeSkipThreshold
        if hedgeSkip {
            traceLogger.trace(
                "[MLX] action=hedgeSkip key=\(executionKey.traceKey)"
                + " lastMode=\(managed.lastCompletionMode ?? "-")"
                + " lastEff=\(managed.lastCompletionCacheEff.map { String(format: "%.2f", $0) } ?? "-")"
                + " threshold=\(RuntimeTuning.expHedgeSkipThreshold)")
        }
        if restoreRiskFires, !hedgeSkip {
            switch ExecutionPolicy.conditionalRestoreGate(
                configuration: restorePolicy,
                incoming: messages,
                ledgerCount: managed.historyJSON.count) {
            case .skipDisabled:
                break
            case .skipDeltaTooLarge(let estimate):
                traceLogger.trace(
                    "[MLX] action=rollforwardSkip key=\(executionKey.traceKey)"
                    + " reason=deltaTooLarge deltaTokensEst=\(estimate)")
            case .allowed:
                rollforward: do {
                let (restored, meta) = try await performLoad(
                    key: executionKey.storageKey, traceKey: executionKey.traceKey,
                    container: container, config: config, baseConfig: baseConfig,
                    directory: Self.defaultBranchCheckpointStore(), modelPath: modelPath)
                // KV 配置指纹对账：checkpoint 的 KV 状态属于保存时的配置；
                // 指纹不一致 → 恢复态对当前配置是陈旧物，放弃滚前。
                guard restored.kvFingerprint == kvFingerprint else {
                    traceLogger.trace(
                        "[MLX] action=rollforwardSkip key=\(executionKey.traceKey)"
                        + " reason=kvFingerprintMismatch")
                    break rollforward
                }
                guard ExecutionPolicy.rollforwardCompatible(incoming: messages,
                                                 restoredHistory: meta.history) else {
                    // 生产遥测只带首分歧摘要（字段归因）；全量 diff 行
                    // （rollforwardDiffLine）留在研究 harness，不再逐轮进 trace。
                    traceLogger.trace(
                        "[MLX] action=rollforwardSkip key=\(executionKey.traceKey)"
                            + " reason=checkpointStale "
                            + ExecutionPolicy.rollforwardFirstDiffSummary(
                                incoming: messages, restoredHistory: meta.history))
                    break rollforward
                }
                // 原子替换 + 身份守卫：只有恢复态真正进入 sessions 池才允许
                // 继续使用；守卫失败（池中已换成其他对象）必须放弃恢复态——
                // 否则本轮生成运行在 detached session 上，收尾回写与 checkpoint
                // 都会落到池外对象（外审 P1，2026-09-18）。
                var replaced = false
                state.withLock {
                    if let live = $0.sessions[mapKey], live === managed {
                        $0.sessions[mapKey] = restored
                        replaced = true
                    }
                }
                guard replaced else {
                    traceLogger.trace(
                        "[MLX] action=rollforwardSkip key=\(executionKey.traceKey)"
                        + " reason=sessionReplaced")
                    break rollforward
                }
                managed = restored
                rolledForward = true
                // 双估算入 trace(log-only,门校准数据):chars÷4 对 CJK
                // 低估 ~4×(2026-09-18 生产 12k 级回填全过 8192 门),CJK
                // 感知口径并行记录,攒够真实样本后一并重校准门与阈值。
                let estAscii = ExecutionPolicy.estimateDeltaTokens(
                    incoming: messages, ledgerCount: managed.historyJSON.count)
                let estCJK = ExecutionPolicy.estimateDeltaTokensCJK(
                    incoming: messages, ledgerCount: managed.historyJSON.count)
                traceLogger.trace(
                    "[MLX] action=rollforward key=\(executionKey.traceKey)"
                    + " history=\(meta.history.count)"
                    + " deltaTokensEst=\(estAscii) deltaTokensCJK=\(estCJK)")
            } catch {
                traceLogger.trace(
                    "[MLX] action=rollforwardFailed key=\(executionKey.traceKey)"
                    + " err=\(error.localizedDescription)")
            }
            }
        }

        // P1 会话 LRU + P2 Admission：数量/内存双维度驱逐，随后记录暖会话态势
        // （warmTokenBudget 的校准观测行）。生产降噪（2026-09-29）：无驱逐
        // 且未 rollforward 的轮次不发 admission 行——rf= 是 prefill_stats.py
        // noMode 判别的载荷，rollforward/驱逐轮仍整行保留（格式不变）。
        let admission = await evictSessionsIfNeeded(keeping: mapKey)
        if admission.evicted > 0 || rolledForward {
            traceLogger.trace(
                "[MLX] admission warmSessions=\(admission.warmSessions)" +
                " warmTokens=\(admission.warmTokens)" +
                " swap=" + (RuntimeTuning.swapUsedBytes()
                    .map { String(format: "%.1fGB", Double($0) / Double(RuntimeTuning.gibibyte)) } ?? "n/a") +
                " evicted=\(admission.evicted) freedTokens=\(admission.evictedTokens)"
                + " rf=\(rolledForward ? 1 : 0)"
            )
        }

        let delta: [Chat.Message]
        if reusedSession {
            delta = Array(incoming.dropFirst(managed.history.count))
        } else {
            delta = incoming.last.map { [$0] } ?? []
        }

        guard !delta.isEmpty else {
            return GenerationResult(text: "", usage: nil, completion: .unconfirmed)
        }

        // #90 A：采纳轮的身份已在 adoptLiveSession 的转移临界区内重绑；
        // 这里补上新建/池恢复轮的绑定。lineage 与 durable 落盘按每个 HTTP
        // 请求各自的 executionId 记账——分片归属不合并请求身份。
        managed.executionKey = executionKey
        // #90 B：在途标记。字节上限逐出只允许选中没有请求在跑的分片；
        // 本轮无论成功、抛错还是取消都必须清除（defer 覆盖全部退出路径）。
        state.withLock {
            if let current = $0.sessions[mapKey], current === managed {
                current.inFlightRequestId = requestId
            }
        }
        defer {
            state.withLock {
                if let current = $0.sessions[mapKey],
                   current.inFlightRequestId == requestId {
                    current.inFlightRequestId = nil
                }
            }
        }

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
            deltaBytes += obj["content"]?.messageText.utf8.count ?? 0
        }
        let contextEstimate: Int
        if reusedSession {
            contextEstimate = (cacheTokensBefore ?? 0) + deltaBytes / 4
        } else {
            var incomingBytes = 0
            for value in messages {
                guard case .object(let obj) = value else { continue }
                incomingBytes += obj["content"]?.messageText.utf8.count ?? 0
            }
            contextEstimate = incomingBytes / 4
        }
        params.prefill.stepSize = RuntimeTuning.prefillStepSize(
            contextTokens: contextEstimate
        )
        // rebuild 可见性（外部审核 P0-2）：选档即宣告本轮预期——
        // 配合轮末 cacheEff=0.00 即「渲染分叉 rebuild」完整证据链。
        traceLogger.trace(
            "[MLX] prefillStep=\(params.prefill.stepSize.map(String.init) ?? "512") est=\(contextEstimate) reuse=\(reusedSession)"
        )

        managed.session.generateParameters = params
        managed.session.tools = toolSpecs
        managed.session.additionalContext = additionalContext

        for value in messages.dropFirst(newMessageStart) {
            guard case .object(let obj) = value,
                  (obj["role"]?.string ?? "").lowercased() == "tool",
                  let toolCallId = obj["tool_call_id"]?.string else { continue }
            let size = obj["content"]?.messageText.utf8.count
            toolGovernance.resultObserved(
                requestId: requestId,
                generationId: requestId,
                toolCallId: toolCallId,
                sizeBytes: size
            )
        }

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
        // 引擎本轮实际走的物理复用路径（extend / extend-main / exact-n1 /
        // rewind / fork-no-rewind / rebuild / cold），连续命中率语义由
        // cacheHitTokens/promptTokens 分子分母 + mode 共同表达。
        var cacheReuseMode: String?
        // fork-no-rewind 时的分叉点：渲染 prompt 与账本的最长公共前缀 /
        // 账本长度（引擎 token 空间），用于把 GDN 重建定位到具体位置。
        var cacheForkCommon: Int?
        var cacheForkLedger: Int?
        // 解码可见性诊断（2026-09-13）：流实际产出 vs filter 放行。
        // rawB 大而 emitB=0 ⇒ 模型在长思考、输出被整段吞掉——客户端看到
        // 的就是数百秒零事件静默（e155f1 实测 601s）。
        var rawEventCount = 0
        var rawChunkBytes = 0
        var emittedChunkBytes = 0
        // T-1：引擎唯一的终止见证。vendor 只在信息事件里给出，缺事件即缺证据，
        // 不得当作自然结束（否则预算触顶的半句答案会被宣称为完整回答）。
        var stopReason: GenerateStopReason?

        // #136 ES 续接授权上下文：本轮采纳内存前缀表示时的身份。钩子在
        // 引擎的 `.prefillAll` 策略边界内读取它，条目只有 ES 身份逐字相等
        // 才可采纳——不借内存池绕过权限检查。`bindLookup` 是本轮在函数入口
        // 只读取到的同一份 IS 权威（磁盘 bind 站点会注销它，这里不能再查）：
        // 受管续接下内存采纳与磁盘准入过同一个 digest 比较（§II.3）。
        PrefixMemoryPool.shared.setAdoptionContext(
            executionKey.logicalBranchId, authority: bindLookup)

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
                // encode-once：同一 arguments 只做一次 JSONEncoder（此前连续
                // 两次）。字符串形态进治理账本，Data 形态解码出结构化形态；
                // 编码确定性使两条派生路径与旧双编码行为逐字节一致。
                let argumentsData = try? JSONEncoder().encode(normalizedCall.function.arguments)
                let argumentsRaw = argumentsData.flatMap { String(data: $0, encoding: .utf8) }
                let arguments = argumentsData.flatMap {
                    try? JSONDecoder().decode([String: JSONValue].self, from: $0)
                } ?? [:]

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
                cacheReuseMode = info.cacheReuseMode
                cacheForkCommon = info.cacheForkCommonTokens
                cacheForkLedger = info.cacheForkLedgerTokens
                stopReason = info.stopReason
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
            // W4/A：取消轮的预算观测——记下真实的预填进度与耗时，供同一
            // payload 的下一次重试判定（本轮没有完成预填，不产出速度样本）。
            // #138：加载后的第一笔预填同样不是稳态证据；预填完成过则消费
            // 预热标记，未完成则保持待消费，让下一轮仍按预热豁免。
            let prefill = prefillProgress.value
            let postLoadWarmupTurn = state.withLock { state -> Bool in
                if prefill.total > 0, prefill.processed >= prefill.total {
                    return state.postLoadWarmup.consumeCompletedPrefill()
                }
                return state.postLoadWarmup.isWarmupTurn
            }
            if prefill.total > 0, prefill.processed > 0,
                let startedAt = prefill.startedAt,
                !postLoadWarmupTurn,
                let digest = RequestBudgetController.shared.promptDigest(requestID: requestId),
                let identity = budgetIdentity(thinkingDisabled: thinkingDisabled)
            {
                RequestBudgetController.shared.recordObservedAttempt(
                    identity: identity,
                    bucket: reusedSession ? "hot" : "cold",
                    promptDigest: digest,
                    processed: prefill.processed,
                    total: prefill.total,
                    elapsed: Date().timeIntervalSince(startedAt),
                    requestID: requestId,
                    completed: prefill.processed >= prefill.total)
            } else if postLoadWarmupTurn, prefill.processed > 0 {
                traceLogger.trace(
                    "[BUDGET] skip_record reason=model_warmup cancelled=1" +
                    " processed=\(prefill.processed)/\(prefill.total)")
            }
            // 取消清理第二不变量（2026-09-17 毒 session 事故，lessons 同名文档）：
            // 被打断的分片留在表里，后续 prefix 命中它的请求将零输出挂死
            // （真机实证连续 10 次无自愈）。逐出后下一请求新建 session 走健康
            // 路径。判据本身在 `CancelEviction`（纯函数，测试层可证伪）：
            // 新建分片看「零事件 + 非复用」，#90 C 采纳来的分片不看事件数。
            // #134：零事件这一支先取上游的保留证据（账本 vs 物理 cache），
            // 只有证明一致的可用前缀才免逐出。显式 readiness 状态留待
            // session 生命周期协议。
            // #136：取消轮的内存前缀捕获——必须在驱逐（session.clear()）之前
            // 做，且只接受引擎自己的证明（`interruptedPrefixBoundary()`：
            // 边界取自各注意力层 offset 的一致值，逐项核验行数、token 前缀
            // 与 GDN 递推状态）。证明不了就只留一行拒绝原因。
            // 快照是与本会话独立的表示，因此下面的 `poisonedSessionEvict`
            // 语义不变：毒分片照样逐出，可证明的前缀照样留在池里，重试
            // 不再重复支付同一段 prefill。
            let capturedPrefixTokens = await NativeMLXPrefixPool.shared.captureInterruptedPrefix(
                managed.session,
                modelID: modelName(from: modelPath),
                kvFingerprint: kvFingerprint,
                thinkingDisabled: thinkingDisabled,
                esStateID: executionKey.logicalBranchId,
                traceKey: executionKey.traceKey
            )
            let retention = await cancelledPrefixRetention(managed.session)
            switch CancelEviction.decide(
                rawEventCount: rawEventCount,
                reusedSameSession: reusedSession,
                adoptedForeignShard: adoptedForeignShard,
                retainedLedgerTokens: retention.ledgerTokens,
                cacheProcessedTokens: retention.processedTokens
            ) {
            case .keepResident:
                break
            case .retainProvenPrefix:
                // 观测独立成行：保留不是驱逐，不复用驱逐那两个标记。
                traceLogger.trace(
                    "[MLX] cancelPrefixRetain session=\(executionKey.traceKey)" +
                    " retainedTokens=\(retention.ledgerTokens)" +
                    " captured=\(capturedPrefixTokens)" +
                    " rawEv=\(rawEventCount)"
                )
            case .evictFreshShard:
                // 拒绝理由单独成行：真机取证要能区分「账本为空」与「账本
                // 非空但和物理 cache 不一致」，二者都是逐出但证据不同。
                // `captured>`0` 时逐出仍然发生（毒分片不留存），但引擎证明
                // 过的那段前缀已作为独立表示进内存池，重试不必重付。
                traceLogger.trace(
                    "[MLX] cancelPrefixUnproven session=\(executionKey.traceKey)" +
                    " ledgerTokens=\(retention.ledgerTokens)" +
                    " processedTokens=\(retention.processedTokens)" +
                    " captured=\(capturedPrefixTokens)" +
                    " rawEv=\(rawEventCount)"
                )
                await evictInterruptedExecution(
                    managed: managed,
                    marker: CancelEviction.freshShardMarker,
                    sessionLabel: executionKey.traceKey
                )
            case .evictAdoptedShard:
                await evictInterruptedExecution(
                    managed: managed,
                    marker: CancelEviction.adoptedShardMarker,
                    sessionLabel: executionKey.traceKey
                )
            }
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
            if let current = $0.sessions[mapKey], current === managed {
                current.history = managed.history
                current.historyJSON = managed.historyJSON
                current.lastActivity = Date()
            }
            $0.lastActivity = Date()
        }

        // Route B 前缀池轮末导出：把本轮已处理消息流 + 新鲜 KV 注册为共享
        // 边界（best-effort，await 内联——不与下一轮对该 session 的使用竞态；
        // 序列化量级与上方 performSave 相当，0.15s@58k 实测口径）。
        if RuntimeTuning.prefixPoolEnabled {
            let poolHistory = managed.history.map {
                (role: $0.role.rawValue, content: $0.content)
            }
            let poolSession = managed.session
            _ = await NativeMLXPrefixPool.shared.export(
                modelID: modelName(from: modelPath),
                kvFingerprint: kvFingerprint,
                thinkingDisabled: thinkingDisabled,
                executionID: executionKey.storageKey,
                branchID: executionKey.logicalBranchId,
                history: poolHistory
            ) { url in
                _ = try await poolSession.saveCache(to: url)
            }
            // B-6 token 边界：仅基 kvSettings 会话导出（跨 plan 类误装
            // 不可能进池——登记的 beta 边界）。
            if kvFingerprint == baseConfig.kvCache.map({ String(describing: $0) }) {
                let tokenIds = await poolSession.cachedTokenIds()
                if !tokenIds.isEmpty {
                    await NativeMLXPrefixPool.shared.exportTokenBoundaries(
                        modelID: modelName(from: modelPath),
                        kvFingerprint: kvFingerprint,
                        thinkingDisabled: thinkingDisabled,
                        tokenIds: tokenIds, session: poolSession
                    )
                }
            }
        }

        // Phase B：每成功轮落 checkpoint（roll-forward 的 last known good；
        // Phase A 实测 0.15s@58k，计入轮延迟可忽略）。Conditional Restore
        // 依赖 ledger-end 新鲜 checkpoint——陈旧 checkpoint 曾致 +10k 重渲
        // （a210155 对照：checkpoint 覆盖 31k vs 活 41k），是旧 rf 负收益
        // 的第一来源，故两 flag 任一开启都落盘。
        // v2.1.1 留存作用域：请求级一次性会话（*-request:UUID）不参与
        // 跨请求 KV reuse，durable receipt 永无复访者——跳过落盘。
        if RuntimeTuning.branchCheckpointsEnabled,
            (restorePolicy.legacyRollforwardEnabled || restorePolicy.conditionalRestoreEnabled),
            !AgentExecutionKey.isRequestScopedSession(executionKey.storageKey) {
            managed.checkpointDirty = true
            do {
                _ = try await performSave(
                    key: executionKey.storageKey, traceKey: executionKey.traceKey,
                    container: container, managed: managed,
                    directory: Self.defaultBranchCheckpointStore(), modelPath: modelPath)
                managed.checkpointDirty = false
                observation.noteCacheSave()
                Self.enforceDefaultBranchCheckpointRetention(
                    retaining: state.withLock { Set($0.sessions.keys) })
                lineage.attachCheckpoint(
                    executionId: String(executionId),
                    checkpointKey: executionKey.storageKey)
            } catch {
                // Do not discard the live execution on checkpoint failure.
                // suspendIfIdle will retry; until then the session remains the
                // authoritative newer state and is explicitly marked dirty.
                traceLogger.trace(
                    "[MLX] action=checkpointFailed key=\(executionKey.traceKey)"
                    + " err=\(error.localizedDescription)")
                observation.noteCheckpointFailed()
            }
        }

        // P1 会话 LRU 扫描：生成收尾后驱动驱逐。
        await evictSessionsIfNeeded(keeping: mapKey)

        // Restore 路径归因补全（2026-09-20）：checkpoint 恢复的会话在 vendor
        // 侧无 conversation 账本，归因块整体跳过，info 恒为 cacheHit=0/无
        // mode——而物理上是「N=cacheTokens 前缀全复用 + 仅预填 d=promptTokens」
        // 的最优路径，0.00 与冷启/重建同形，歧义极大。N、d 均为实测计数
        // （官方 cacheStatus + info 透传），cacheEff=N/(N+d) 是可证明值，
        // 不写死 1（delta 确实预填了）。vendor 给出 mode 时以 vendor 为准。
        var reportedCacheHit = cachedPromptTokens
        var reportedCacheEff = cacheEfficiency
        var reportedMode = cacheReuseMode
        observation.noteEngineTokens(prompt: promptTokens, cacheHit: reportedCacheHit,
                                     generation: generationTokens, mode: reportedMode,
                                     reused: reusedSession)
        if cacheReuseMode == nil, managed.isRestoredSnapshot,
           let n = cacheTokensBefore, n > 0, let d = promptTokens {
            reportedCacheHit = n
            reportedCacheEff = Double(n) / Double(n + d)
            reportedMode = "restore"
        }
        // EXP-B：记录上一轮 completion 形态（hedge-skip 判定输入）。
        managed.lastCompletionMode = reportedMode
        managed.lastCompletionCacheEff = reportedCacheEff

        // T-1：终止原因只由 vendor 的信息事件给出。没有信息事件就没有证据，
        // 本轮按 `unconfirmed` 处理——协议层与结算门共用这一个判定，缺失信号
        // 永远不等于自然结束。
        let completion: GenerationCompletion
        switch stopReason {
        case .some(.stop): completion = .complete
        case .some(.length): completion = .capped
        case .some(.cancelled): completion = .cancelled
        case .none: completion = .unconfirmed
        }

        // 轮末完成行（build 4 恢复，211aa59 trim 曾删）：V1.7-0 矩阵
        // 位置法捕获的唯一认证级来源——mode/reuse/cacheEff/ttft 逐轮
        // 真值。纯遥测，零行为变更；逐轮一行，量级与 v1.5/v1.6 相同。
        var log =
            "[MLX] session=\(executionKey.traceKey) messages=\(incoming.count)" +
            " exec=\(executionId.prefix(6))" +
            " history=\(managed.history.count) delta=\(delta.count) reuse=\(reusedSession)"
        if let kvSettings {
            log += " kv=\(kvSettings.strategy ?? "fullPrecision")"
        }
        if let ttft {
            log += String(format: " ttft=%dms", Int(ttft * 1000))
        }
        if let cacheTokensBefore {
            log += " cacheTokens=\(cacheTokensBefore)"
        }
        if let reportedCacheHit {
            log += " cacheHitTokens=\(reportedCacheHit)"
        }
        if let reportedCacheEff {
            log += String(format: " cacheEff=%.2f", reportedCacheEff)
        }
        if let reportedMode {
            log += " mode=\(reportedMode)"
        }
        if let c = cacheForkCommon, let l = cacheForkLedger {
            log += " fork@common=\(c)/\(l)"
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
        if adoptedForeignShard {
            // #90 A：采纳即所有权转移。session= 始终是本轮自己的请求级
            // 身份；adopt=1 声明本轮从另一请求键接手了这份活分片
            // （own=transfer），不是与对方共享别名。
            log += " adopt=1"
        }
        log += " rawEv=\(rawEventCount) rawB=\(rawChunkBytes) emitB=\(emittedChunkBytes)"
        // 行尾追加，不动既有位置法捕获（mode/reuse/cacheEff/ttft 在其之前）。
        // genTokens/maxTokens 让「触顶」在读日志时可直接判定，不必反推 tps。
        log += " stop=\(completion.wireName)" +
            " genTokens=\(generationTokens.map(String.init) ?? "nil")" +
            " maxTokens=\(params.maxTokens)"

        // W4/A：真实预填样本（冷/热分桶）+ 同 payload 完成观测。
        // 计数口径：info.promptTokenCount 是本轮实际预填的 delta（restore
        // 归因里 N=cacheHitTokens 另计），promptTime 是引擎预填耗时；恢复
        // 快照轮的账本由 restore 语义决定，不属于本轮渲染口径，不采样本。
        //
        // #138：加载后的第一笔完成轮承担 kernel 首次编译/权重驻留代价，其
        // 计时不是稳态吞吐。它只消费预热标记：既不入 P10 速率窗口（否则
        // 冷启动下限会长期压住所有估算），也不给同 payload 留「已完成」
        // 观测（否则重试会被这笔被低估的速率直接拒绝）。
        // 只有真正跑过预填的可记录轮才消费预热标记：restore/池恢复轮没付
        // 编译与驻留代价，若让它消费，下一笔真正的冷预填仍会被当成稳态采样。
        let prefillRecordable = !managed.isRestoredSnapshot && !poolRestoredTurn
            && (promptTokens ?? 0) > 0 && (promptSeconds ?? 0) > 0
        let postLoadWarmupTurn = prefillRecordable
            ? state.withLock { $0.postLoadWarmup.consumeCompletedPrefill() }
            : false
        if prefillRecordable,
            let prefillTokens = promptTokens,
            let prefillSeconds = promptSeconds,
            let identity = budgetIdentity(thinkingDisabled: thinkingDisabled)
        {
            let bucket = reusedSession ? "hot" : "cold"
            if postLoadWarmupTurn {
                traceLogger.trace(
                    "[BUDGET] skip_record reason=model_warmup bucket=\(bucket)" +
                    " tokens=\(prefillTokens)" +
                    String(format: " seconds=%.1f", prefillSeconds))
            } else {
                RequestBudgetController.shared.recordPrefillSample(
                    identity: identity, bucket: bucket,
                    tokens: prefillTokens, seconds: prefillSeconds, source: "engine")
                if let digest = RequestBudgetController.shared.promptDigest(requestID: requestId) {
                    RequestBudgetController.shared.recordObservedAttempt(
                        identity: identity, bucket: bucket, promptDigest: digest,
                        processed: prefillTokens, total: prefillTokens,
                        elapsed: prefillSeconds, requestID: requestId, completed: true)
                }
            }
        }
        traceLogger.trace(log)

        // usage 保持 vendor 原值透传（含 restore 路径的归因缺口）：P1-2 契约
        // 是官方计数不做估算；restore 归因补全只属于上方 Runtime 遥测行。
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
        return GenerationResult(
            text: completedText, usage: usage, completion: completion)
    }

    /// #90 A：跨请求采纳活会话分片。判据本身是纯函数（`SessionAdoption`，
    /// 测试层可证伪）；本函数只做表快照、锁外前缀对账与锁内原子转移。
    ///
    /// 采纳即**所有权转移**，不是共享别名：认领的同一临界区内把分片从原
    /// 请求键摘下、登记到 `ownerKey` 下并重绑执行身份。因此任一时刻只有
    /// 本轮请求持有这份可变会话，后续推进只写本轮映射；原请求键不再指向
    /// 它，其重放（历史更短）不满足长度判据，只会走冷路径。
    ///
    /// 采纳域：同一 agent 作用域内的请求级（`*-request:`）身份之间。两类边界
    /// 都不许越：①不同 agent 的请求不得互相借用（隔离裁定优先于复用收益）；
    /// ②有稳定 sessionId 的真实会话不得互相借用——那属于 #92/W2′ 的跨会话
    /// 共享语义，本窗口未获开启（owner 裁定 D）。
    private func adoptLiveSession(
        incoming: [Chat.Message],
        kvFingerprint: String?,
        thinkingDisabled: Bool,
        owner: AgentExecutionKey,
        ownerKey: String,
        requestId: String
    ) -> (session: ManagedSession, fromKey: String)? {
        let table: [(key: String, entry: ManagedSession)] = state.withLock { state in
            state.sessions.compactMap { key, entry in
                guard key != ownerKey else { return nil }
                guard AgentExecutionKey.isRequestScopedSession(
                    entry.executionKey?.storageKey ?? key
                ) else { return nil }
                return (key, entry)
            }
        }
        guard !table.isEmpty else { return nil }
        // 前缀对账在锁外执行（与 evictSessionsIfNeeded 同一口径：锁内不跑
        // O(历史) 比较）；认领时在锁内做对象身份 + 在途 + 长度复核。
        // serializeGeneration = true 时本轮不存在并发写者，复核是防御性收口。
        let candidates = table.map { item in
            SessionAdoption.Candidate(
                key: item.key,
                historyCount: item.entry.history.count,
                historyIsStrictPrefixOfIncoming:
                    Self.isPrefix(item.entry.history, of: incoming),
                kvFingerprint: item.entry.kvFingerprint,
                thinkingDisabled: item.entry.thinkingDisabled,
                inFlightRequestId: item.entry.inFlightRequestId,
                agentId: item.entry.executionKey?.agentId,
                lastActivity: item.entry.lastActivity
            )
        }
        let request = SessionAdoption.Request(
            incomingCount: incoming.count,
            kvFingerprint: kvFingerprint,
            thinkingDisabled: thinkingDisabled,
            agentId: owner.agentId
        )
        // 诊断用短名：候选拒绝理由要能对上 trace 里的 session= 标签。
        let candidateLabels = Dictionary(
            uniqueKeysWithValues: table.map {
                ($0.key,
                 $0.entry.executionKey?.traceKey ?? "shard-" + String($0.key.suffix(6)))
            })
        guard let chosen = SessionAdoption.choose(candidates, for: request),
              let record = table.first(where: { $0.key == chosen.key })
        else {
            // 验收要能区分「没看」与「看了但没有合格候选」：候选数与逐条
            // 拒绝理由都写出来（只写短标签与理由码，不写内容）。
            let eligible = SessionAdoption.eligibleCandidates(candidates, for: request).count
            let reasons = candidates.map { candidate in
                "\(candidateLabels[candidate.key] ?? "?"):"
                    + (SessionAdoption.eligibility(candidate, for: request).reason ?? "eligible")
            }.joined(separator: ",")
            traceLogger.trace(
                "[MLX] sessionAdoptMiss key=\(owner.traceKey)"
                    + " candidates=\(candidates.count) eligible=\(eligible)"
                    + " reasons=\(reasons)"
            )
            return nil
        }
        let claimed: ManagedSession? = state.withLock { state in
            guard let entry = state.sessions[chosen.key],
                  entry === record.entry,
                  entry.inFlightRequestId == nil,
                  entry.history.count < incoming.count,
                  // 属主键必须空闲：本轮走的是「该键无活会话」分支，
                  // 这里是锁内复核（表快照之后可能有别的写者先占了同键）。
                  state.sessions[ownerKey] == nil else { return nil }
            // #90 A 所有权转移：摘下原键 → 重绑执行身份 → 登记本键，
            // 三步同一临界区。之后本轮是这份可变会话唯一的属主与写者，
            // 且它在本轮的键下接受在途标记与取消逐出。
            state.sessions.removeValue(forKey: chosen.key)
            entry.inFlightRequestId = requestId
            entry.executionKey = owner
            entry.lastActivity = Date()
            state.sessions[ownerKey] = entry
            return entry
        }
        guard let claimed else {
            traceLogger.trace(
                "[MLX] sessionAdoptClaimLost key=\(owner.traceKey)"
                    + " from=\(candidateLabels[chosen.key] ?? "?") note=state-changed"
            )
            return nil
        }
        return (claimed, chosen.key)
    }

    /// #134 取消轮的前缀保留证据探针——只读取，不做任何推断。
    ///
    /// `cachedTokenIds()` 是会话账本：上游 `ChatSession.record()` 只有在
    /// 「取消 + 物理 cache 进度可证 + 该 cache 逐层可 trim + trim 后计数恰为
    /// retainedTokenCount」全部成立时，才把它重基为这一段前缀；任一条件不满足
    /// 它就为空。`cacheStatus().processedTokenCount` 是物理 cache 的真实进度。
    /// 两者非空且相等 ⇒ 这份表示是上游已经证明过的，本层无权再用 `clear()`
    /// 把它抹掉。读失败记 -1（不可能与账本相等）⇒ 无证据，走既有驱逐。
    /// 生产模型（30× GDN 递归层）上 `isTrimmable` 为 false，账本已被上游清空
    /// ⇒ 这里返回 0，行为与本次改动前逐字相同。
    private func cancelledPrefixRetention(
        _ session: ChatSession
    ) async -> (ledgerTokens: Int, processedTokens: Int) {
        let ledgerTokens = await session.cachedTokenIds().count
        let processedTokens = (try? await session.cacheStatus())?.processedTokenCount ?? -1
        return (ledgerTokens, processedTokens)
    }

    /// #90 B/C：逐出一个被打断的活执行——移除池中指向同一 ManagedSession
    /// 或同一 ChatSession 的全部条目（别名），再用官方 `clear()` 释放 KV。
    /// 移除在锁内做身份确认，只有真正摘掉的才进入 clear 阶段。
    private func evictInterruptedExecution(
        managed: ManagedSession,
        marker: String,
        sessionLabel: String
    ) async {
        let removedKeys: [String] = state.withLock { state in
            let matches = state.sessions.filter { _, entry in
                entry === managed || entry.session === managed.session
            }.map { $0.key }
            for key in matches { state.sessions.removeValue(forKey: key) }
            return matches
        }
        guard !removedKeys.isEmpty else { return }
        await managed.session.clear()
        traceLogger.trace(
            "[MLX] \(marker) session=\(sessionLabel)" +
            " history=\(managed.history.count)" +
            " aliases=\(removedKeys.count)" +
            " keys=" + removedKeys.map { String($0.suffix(6)) }.joined(separator: ",")
        )
    }

    /// P1 会话 LRU（数量维度）+ P2 Admission（内存维度，2026-09-18）：
    /// 数量超限或 swap 压力下，最久未用会话先经官方 clear() 释放 KV
    /// （锁外执行），再回收缓冲。内存维度把暖会话 KV token 总和压回
    /// warmTokenBudget——并行多会话把预填顶进 swap 爬速区是「重建×超时」
    /// 循环的直接乘数（09-17 深夜实证，lessons 同名文档深夜段）。
    /// swap 读不到（nil=未知）不触发内存维度：未知不冒充压力。
    @discardableResult
    private func evictSessionsIfNeeded(keeping currentKey: String) async -> SessionEvictionReport {
        // 锁内只做快照；token 统计锁外执行。快照与移除之间字典可能被
        // deleteSessionBranch（不走 gate）/loadSessionCache 变更，故最终
        // 移除在锁内做身份确认（见下方原子移除段）。
        let snapshot: [(key: String, session: ChatSession, inFlight: Bool)] = state.withLock { state in
            state.sessions
                .filter { $0.key != currentKey }
                .sorted { $0.value.lastActivity < $1.value.lastActivity }
                .map {
                    (key: $0.key, session: $0.value.session,
                     inFlight: $0.value.inFlightRequestId != nil)
                }
        }
        let totalCount = state.withLock { $0.sessions.count }
        let currentSession = state.withLock { $0.sessions[currentKey]?.session }
        let swap = RuntimeTuning.swapUsedBytes()
        let swapPressure = (swap ?? 0) > RuntimeTuning.swapPressureThresholdBytes

        let currentTokens = await sessionTokens(currentSession)
        var lru: [(key: String, session: ChatSession, tokens: Int, inFlight: Bool)] = []
        lru.reserveCapacity(snapshot.count)
        for candidate in snapshot {
            lru.append((
                candidate.key, candidate.session,
                await sessionTokens(candidate.session), candidate.inFlight
            ))
        }
        var warmTokens = currentTokens + lru.reduce(0) { $0 + $1.tokens }

        var victims: [(key: String, session: ChatSession, tokens: Int)] = []
        // 数量维度（P1 原语义）：总数超 sessionLimit 的溢出部分。
        var overflow = max(0, totalCount - RuntimeTuning.sessionLimit)
        while overflow > 0, let candidate = lru.first {
            lru.removeFirst()
            overflow -= 1
            warmTokens -= candidate.tokens
            victims.append((candidate.key, candidate.session, candidate.tokens))
        }
        // 内存维度（P2 新增）：swap 压力下把暖 token 总和压回预算。
        if swapPressure {
            while warmTokens > RuntimeTuning.warmTokenBudget, let candidate = lru.first {
                lru.removeFirst()
                warmTokens -= candidate.tokens
                victims.append((candidate.key, candidate.session, candidate.tokens))
            }
        }
        // #90 B 驻留字节维度（不受 swap 门控）：跨请求采纳把活会话复用变成
        // 常态后，暖会话必须有物理上界。上限 = 模型几何 × 既有两条预算
        // （sessionLimit 份固定状态 + warmTokenBudget token），不引入新常数。
        // 选择在途隔离 + LRU 由 ResidencyGovernor 判定（测试层已证伪）；
        // 本轮分片由 keeping 保护，不在 residents 输入里。
        // residency 为 nil（读不到几何）时整个维度不启用：未知不冒充压力。
        var warmBytes = 0
        var ceilingBytes = 0
        var residencyFired = false
        if let residency {
            ceilingBytes = LiveSessionResidency.byteBudget(residency: residency)
            let residents = lru.map {
                ResidencyGovernor.Resident(
                    key: $0.key,
                    bytes: residency.estimatedBytes(processedTokens: $0.tokens),
                    isInFlight: $0.inFlight
                )
            }
            let plan = ResidencyGovernor.evictionPlan(
                residents,
                protectedBytes: residency.estimatedBytes(processedTokens: currentTokens),
                ceiling: ceilingBytes
            )
            warmBytes = plan.warmBytesAfter
            residencyFired = plan.fired
            if plan.fired {
                let victimKeys = Set(plan.victims)
                var kept: [(key: String, session: ChatSession, tokens: Int, inFlight: Bool)] = []
                kept.reserveCapacity(lru.count)
                for candidate in lru {
                    if victimKeys.contains(candidate.key) {
                        warmTokens -= candidate.tokens
                        victims.append((candidate.key, candidate.session, candidate.tokens))
                    } else {
                        kept.append(candidate)
                    }
                }
                lru = kept
            }
        }

        var report = SessionEvictionReport()
        report.warmSessions = 1 + lru.count
        report.warmTokens = warmTokens
        report.warmBytes = warmBytes
        report.byteBudget = ceilingBytes
        // #90 B 驻留曲线：逐轮一行纯遥测（零行为）。账本口径 = 几何估算字节，
        // 物理足迹不在这里（[MEM] 行与测试侧 footprint 采样）——预算估算精确
        // 不等于 RSS/MLX 实际内存被同等字节数硬限。几何不可解析时记 -1
        // （NOT_INSTRUMENTED），不拿 0 冒充计量。
        traceLogger.trace(
            "[MLX] residencyLedger sessions=\(report.warmSessions)"
                + " warmTokens=\(report.warmTokens)"
                + " ledgerBytes=\(residency == nil ? -1 : report.warmBytes)"
                + " ceilingBytes=\(residency == nil ? -1 : report.byteBudget)"
                + " plannedEvictions=\(victims.count)"
        )
        guard !victims.isEmpty else { return report }

        // 原子移除：锁内逐个身份确认（?.session === victim.session）后从池中
        // 移除，只有成功移除的才允许进入 clear() 阶段。快照到移除之间字典可能
        // 被 deleteSessionBranch/loadSessionCache 变更——只 clear 不移除会让
        // 已清空 KV 的 session 留池被复用，且数量维度每请求重复选中同一批
        // victim 形成清除抖动（21f04de 回归，2026-09-18 修正）。
        var removed: [(key: String, session: ChatSession, tokens: Int)] = []
        state.withLock { state in
            for victim in victims {
                if state.sessions[victim.key]?.session === victim.session {
                    state.sessions.removeValue(forKey: victim.key)
                    removed.append(victim)
                }
            }
        }
        if removed.count < victims.count {
            traceLogger.trace(
                "[MLX] evictSkipReplaced n=\(victims.count - removed.count)" +
                " (session replaced concurrently)"
            )
        }
        guard !removed.isEmpty else {
            report.warmSessions = state.withLock { $0.sessions.count }
            return report
        }

        let freedTokens = removed.reduce(0) { $0 + $1.tokens }
        for (_, session, _) in removed { await session.clear() }
        Memory.clearCache()
        // 强制分配器归还空闲页，缩短 LRU 换出后的内存压力黄色窗口（2026-10-23）。
        malloc_zone_pressure_relief(nil, 0)
        report.evicted = removed.count
        report.evictedTokens = freedTokens
        report.warmSessions = state.withLock { $0.sessions.count }
        // token 总和为治理估算：身份确认失败（已被替换）的会话不再计入，
        // 其替身的 token 未进快照，严格上限语义不成立（审核边界 三.2）。
        report.warmTokens = warmTokens - freedTokens
        if let residency {
            // 身份确认失败的 victim 仍在池中，其字节要加回驻留总和。
            let removedKeys = Set(removed.map { $0.key })
            let stillResident = victims
                .filter { !removedKeys.contains($0.key) }
                .reduce(0) { $0 + residency.estimatedBytes(processedTokens: $1.tokens) }
            report.warmBytes = warmBytes + stillResident
            report.evictedBytes = removed.reduce(0) {
                $0 + residency.estimatedBytes(processedTokens: $1.tokens)
            }
        }
        if residencyFired, let residency {
            traceLogger.trace(
                "[MLX] residencyCeiling evicted=\(removed.count)" +
                " freedBytes=\(report.evictedBytes)" +
                " warmBytesNow=\(report.warmBytes)" +
                " ceilingBytes=\(report.byteBudget)" +
                " overCeiling=\(max(0, report.warmBytes - report.byteBudget))" +
                " bytesPerToken=\(residency.bytesPerToken)" +
                " fixedPerSession=\(residency.fixedBytesPerSession)"
            )
            observation.noteResidencyEviction(removed.count)
        }
        traceLogger.trace(
            "[MEM] session LRU evicted=\(removed.count)" +
            " keys=" + removed.map { String($0.key.suffix(6)) }.joined(separator: ",") +
            " limit=\(RuntimeTuning.sessionLimit) budget=\(RuntimeTuning.warmTokenBudget)" +
            " freedTokens=\(freedTokens) warmTokensNow=\(report.warmTokens)" +
            " overBudget=\(max(0, report.warmTokens - RuntimeTuning.warmTokenBudget))" +
            " warmBytesNow=\(report.warmBytes) ceilingBytes=\(report.byteBudget)" +
            " freedBytes=\(report.evictedBytes)" +
            " swap=" + (swap.map { String(format: "%.1fGB", Double($0) / Double(RuntimeTuning.gibibyte)) } ?? "n/a")
        )
        logMemory("afterEvict")
        return report
    }

    /// 会话官方账本 token 数；无会话或读取失败记 0——预算是治理估算，
    /// 不因单次读失败放弃整轮驱逐。
    private func sessionTokens(_ session: ChatSession?) async -> Int {
        guard let session else { return 0 }
        return (try? await session.cacheStatus())?.processedTokenCount ?? 0
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

        let generationKey = try generationGateKey(for: key)
        let gate = gateHolder.withLock { $0 }
        return try await gate.withExclusive(generationKey) {
            let mapKey = resolveSessionMapKey(for: key.storageKey)
            guard let managed = state.withLock({ $0.sessions[mapKey] }) else {
                throw RuntError.generationFailed(
                    "no live session for \(key.storageKey); nothing to save"
                )
            }
            let url = try await performSave(
                key: key.storageKey, traceKey: key.traceKey, container: container,
                managed: managed, directory: directory, modelPath: modelPath)
            managed.checkpointDirty = false
            return url
        }
    }

    /// checkpoint 落盘内核（无 gate）——公开 saveSessionCache 包 gate 使用；
    /// roll-forward 路径在 generate 持 gate 期间直接调用，避免 gate 重入死锁。
    /// Streamed SHA-256 over a file (O(chunk) memory). Checkpoint content
    /// identity must never pull a multi-GiB representation into RAM for
    /// hashing (STEP-10 review, 2026-09-28): lifecycle-boundary operation,
    /// never in the generation hot path.
    nonisolated static func sha256HexOfFile(at url: URL, chunkBytes: Int = 4 << 20) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: chunkBytes)
            guard let chunk, !chunk.isEmpty else { break }
            let data = chunk
            autoreleasepool {
                hasher.update(data: data)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    private func performSave(
        key: String, traceKey: String, container: ModelContainer,
        managed: ManagedSession, directory: URL, modelPath: String
    ) async throws -> URL {
        guard RuntimeTuning.branchCheckpointsEnabled else {
            throw RuntError.generationFailed(
                "branch checkpoints are disabled (SIMIGO_BRANCH_CHECKPOINTS=0)")
        }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        let baseName = Self.cacheFileName(for: key)
        // 后缀必须是 .safetensors：官方 mlx IO 按 pathExtension 分派
        // （2026-09-17 实验实测，.cachesnapshot 抛 unknownExtension）。
        let cacheURL = directory.appendingPathComponent(baseName + ".safetensors")
        let metaURL = directory.appendingPathComponent(baseName + ".meta.json")

        // 未跑过任何生成的会话没有可保存的 cache（官方抛 noCacheAvailable）。
        let saveReceipt = try await managed.session.saveCache(to: cacheURL)

        // The vendor cache is written separately from the sidecar. Bind the
        // pair with a generation id + content hash so any crash/failure between
        // the two writes becomes an invalid checkpoint instead of a mixed pair.
        let cacheSHA256 = saveReceipt.sha256
        let checkpointGeneration = UUID().uuidString.lowercased()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let metadata = SessionCacheMetadata(
            storageKey: key,
            modelId: modelName(from: modelPath),
            savedAt: Date(),
            history: managed.historyJSON,
            kvFingerprint: managed.kvFingerprint,
            checkpointGeneration: checkpointGeneration,
            cacheSHA256: cacheSHA256,
            forkPoint: managed.pendingForkPoint
        )
        try encoder.encode(metadata).write(to: metaURL, options: .atomic)

        traceLogger.trace(
            "[MLX] cacheSave session=\(traceKey) history=\(managed.historyJSON.count)"
        )
        return cacheURL
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
        let existing: ManagedSession?
        let mapKey = resolveSessionMapKey(for: key.storageKey)
        existing = state.withLock { $0.sessions[mapKey] }

        let generationKey = try generationGateKey(for: key)
        let gate = gateHolder.withLock { $0 }
        let output = try await gate.withExclusive(generationKey) {
            let loaded = try await performLoad(
                key: key.storageKey, traceKey: key.traceKey, container: container,
                config: config, baseConfig: baseConfig, directory: directory,
                modelPath: modelPath)
            try state.withLock {
                if let existing, $0.sessions[mapKey] !== existing {
                    throw RuntError.generationFailed(
                        "session replaced during checkpoint load: \(key.storageKey)"
                    )
                }
                $0.sessions[mapKey] = loaded.managed
                $0.lastActivity = Date()
            }
            return loaded
        }
        return output.metadata
    }

    /// checkpoint 恢复内核（无 gate）——公开 loadSessionCache 包 gate 使用；
    /// roll-forward 路径在 generate 持 gate 期间直接调用。不写 sessions 池，
    /// 由调用方决定是否替换（roll-forward 带身份守卫的原子替换见
    /// generateUsingChatSession）。
    private func performLoad(
        key: String, traceKey: String, container: ModelContainer,
        config: ModelConfig?, baseConfig: ModelConfig, directory: URL,
        modelPath: String
    ) async throws -> (managed: ManagedSession, metadata: SessionCacheMetadata) {
        guard RuntimeTuning.branchCheckpointsEnabled else {
            throw RuntError.generationFailed(
                "branch checkpoints are disabled (SIMIGO_BRANCH_CHECKPOINTS=0); "
                + "restore from persisted KV is unavailable by design")
        }
        let expLoadStart = Date() // cacheLoadMs：恢复/对冲加载耗时的常设诊断字段（346ms 归因，2026-09-29 转正）
        let baseName = Self.cacheFileName(for: key)
        let cacheURL = directory.appendingPathComponent(baseName + ".safetensors")
        let metaURL = directory.appendingPathComponent(baseName + ".meta.json")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(
            SessionCacheMetadata.self, from: try Data(contentsOf: metaURL))

        // Fail closed for pre-generation or mixed checkpoints. The generation
        // id is the sidecar commit identity; the cache hash proves that the
        // sidecar describes the exact .safetensors bytes on disk.
        guard let checkpointGeneration = metadata.checkpointGeneration,
              !checkpointGeneration.isEmpty,
              let expectedCacheSHA256 = metadata.cacheSHA256,
              !expectedCacheSHA256.isEmpty else {
            throw RuntError.generationFailed(
                "session checkpoint has no generation/hash commit proof"
            )
        }
        let actualCacheSHA256 = try Self.sha256HexOfFile(at: cacheURL)
        guard actualCacheSHA256 == expectedCacheSHA256 else {
            throw RuntError.generationFailed(
                "session checkpoint generation mismatch: generation=\(checkpointGeneration)"
            )
        }

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

        let snapshot = try loadPromptCacheSnapshot(url: cacheURL, materializeArrays: true)
        let restoredHistory = Self.makeChatMessages(metadata.history)
        let session = ChatSession(
            container,
            instructions: nil,
            cache: snapshot.cache,
            state: snapshot.state,
            history: restoredHistory,
            generateParameters: sessionParams,
            additionalContext: thinkingDisabled ? ["enable_thinking": false] : nil
        )
        // Phase B 补齐（外审 P0-1）：恢复会话必须携带 checkpoint 的 KV 指纹，
        // 否则下一轮复用检查 nil ≠ 当前指纹 → reuseMiss → 全量重建清零收益。
        let restored = ManagedSession(
            session: session,
            history: restoredHistory,
            historyJSON: metadata.history,
            kvFingerprint: metadata.kvFingerprint,
            isRestoredSnapshot: true,
            thinkingDisabled: thinkingDisabled
        )
        traceLogger.trace(
            "[MLX] cacheLoad session=\(traceKey) history=\(metadata.history.count)"
            + " cacheLoadMs=\(Int(Date().timeIntervalSince(expLoadStart) * 1000))"
        )
        return (restored, metadata)
    }

    func integrationSnapshot() -> (activeRequests: Int, activeGenerations: Int, sessions: Int) {
        state.withLock {
            ($0.activeRequestTasks.count, $0.activeRequestTasks.count, $0.sessions.count)
        }
    }

    /// Regression witness only. Return a strong reference so ObjectIdentifier
    /// reuse cannot make a removed session look like its replacement.
    func integrationActiveSessionWitness(
        agentId: String? = nil,
        sessionId: String,
        logicalBranchId: String
    ) -> AnyObject? {
        guard let key = try? AgentExecutionKey.resolve(
            agentId: agentId,
            sessionId: sessionId,
            logicalBranchId: logicalBranchId
        ) else { return nil }
        return state.withLock {
            $0.sessions[key.storageKey].map { $0 as AnyObject }
        }
    }

    // MARK: - Execution State 投影（2026-10-16 收敛；只读）

    /// 引擎真身只读投影：Execution State 窗口的展示层事实源。
    /// 弱一致契约（展示专用，2026-10-16 外审 F3）：会话表在 state 锁内
    /// 复制；血统在取锁前经 ExecutionLineage 自有锁快照——两个状态源
    /// 无共同原子边界，并发窗口内会话计数与血统尾可相差一拍。只读、
    /// 零 IO、零行为，不参与任何执行决策；若将来需要请求↔会话↔血统
    /// 同刻绑定，须另设一致性机制，不得把两个读取塞进同一闭包冒充原子。
    func executionStateSnapshot() -> EngineExecutionStateSnapshot {
        let lineageSnapshot = lineage.snapshot
        return state.withLock { state in
            EngineExecutionStateSnapshot(
                isRunning: state.isRunning,
                pendingRequests: state.pendingRequestIds.count,
                activeGenerations: state.activeRequestTasks.count,
                sessions: state.sessions
                    .sorted { $0.value.lastActivity > $1.value.lastActivity }
                    .map { (mapKey, session) in
                        .init(
                            mapKey: mapKey,
                            label: EngineExecutionStateSnapshot.label(
                                mapKey: mapKey, executionKey: session.executionKey),
                            historyCount: session.history.count,
                            isRestoredSnapshot: session.isRestoredSnapshot,
                            checkpointDirty: session.checkpointDirty,
                            requestScoped: AgentExecutionKey.isRequestScopedSession(mapKey),
                            lastActivity: session.lastActivity)
                    },
                lineageRecords: lineageSnapshot.records,
                forks: lineageSnapshot.forks)
        }
    }

    // MARK: - Branch Fork（生产分支协议 v1；证据链与设计见 docs/decisions/BRANCH_FORK_PROTOCOL_DRAFT.md）

    /// 分支 checkpoint 默认存储：~/.simigo/branch-checkpoints/。
    /// 关闭持久化（`SIMIGO_BRANCH_CHECKPOINTS=0`）时不得创建该目录——目录
    /// 本身就不该出现，而不是建了再不用。
    nonisolated public static func defaultBranchCheckpointStore() -> URL {
        let directory = SimiGoRuntimeCachePaths.branchCheckpointsRoot
        if RuntimeTuning.branchCheckpointsEnabled {
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    nonisolated private static func enforceDefaultBranchCheckpointRetention(
        retaining activeKeys: Set<String>
    ) {
        guard RuntimeTuning.branchCheckpointsEnabled else { return }
        do {
            let result = try BranchCheckpointRetention.enforce(
                directory: defaultBranchCheckpointStore(),
                retainedKeys: activeKeys,
                byteBudget: RuntimeTuning.branchCheckpointByteBudget)
            // 生产降噪（2026-09-29）：无 orphan/预算驱逐的例行 sweep 静默，
            // retention 行只在发生实际回收时出现（retainedGiB 每轮漂移曾致
            // 每轮一行纯噪音）；失败路径照常响。
            if result.removedOrphans > 0 || result.removedForBudget > 0 {
                RuntimeTraceLogger.shared.trace(
                    "[STORAGE] branchRetention retained=\(result.retainedReceipts)"
                        + " retainedGiB=\(String(format: "%.2f", Double(result.retainedBytes) / 1_073_741_824))"
                        + " orphans=\(result.removedOrphans)"
                        + " budgetRemoved=\(result.removedForBudget)"
                        + " freedGiB=\(String(format: "%.2f", Double(result.freedBytes) / 1_073_741_824))")
            }
        } catch {
            RuntimeTraceLogger.shared.trace(
                "[STORAGE] branchRetentionFailed err=\(error.localizedDescription)")
        }
    }

    /// 把 source 逻辑分支的当前执行状态分叉为 target 逻辑分支。
    ///
    /// v2.1.1：活会话分叉改走官方 ChatSession.fork()（上游 #641——KV/draft
    /// cache 数组共享 + 首写拷贝的进程内 COW），退出 v1 磁盘 round-trip
    /// （saveCache → GB 级文件拷贝 → 独立反序列化实例）。隔离性由
    /// testInMemoryForkCopyOwnership 预先封口，官方 fork 携带 conversation
    /// 与 token ledger——child 是一等活会话，非 v1 的 raw-cache 恢复态。
    ///
    /// 持久化契约：fork 即时产物只在内存；child 的 durable checkpoint 由其
    /// 首个成功轮的 per-turn 落盘补上（checkpointDirty 进入挂起重试路径，
    /// 跨挂起存活语义不变），forkPoint 溯源随该落盘戳进 meta。
    ///
    /// 覆盖语义：target 已存在时被覆盖（与 loadSessionCache 一致）——这正是
    /// 「选边提升」流程（客户端选定胜者 → fork 回 main → 其余分支 DELETE）。
    @discardableResult
    public func forkSessionBranch(
        agentId: String? = nil,
        sessionId: String,
        sourceBranch: String,
        targetBranch: String,
        in storeDirectory: URL? = nil
    ) async throws -> SessionCacheMetadata {
        guard sourceBranch != targetBranch else {
            throw RuntError.generationFailed(
                "fork source and target branch are identical: \(sourceBranch)")
        }
        let store = storeDirectory ?? Self.defaultBranchCheckpointStore()
        guard state.withLock({ $0.modelContainer != nil }) else {
            throw RuntError.notLoaded
        }
        let sourceKey = try AgentExecutionKey(
            agentId: agentId, sessionId: sessionId, logicalBranchId: sourceBranch)
        let targetKey = try AgentExecutionKey(
            agentId: agentId, sessionId: sessionId, logicalBranchId: targetBranch)

        // One transaction covers every key that can mutate either checkpoint.
        // When generation serialization is enabled, include the exact global
        // generation key used by generate; otherwise source + target keys are
        // sufficient. Deterministic ordering prevents cross-key deadlock.
        let generationKey = try generationGateKey(for: sourceKey)
        let transactionKeys = RuntimeTuning.serializeGeneration
            ? [generationKey, sourceKey, targetKey]
            : [sourceKey, targetKey]
        let gate = gateHolder.withLock { $0 }

        return try await gate.withExclusive(transactionKeys) {
            // 会话表键对齐：fork 不感知 system 提示，按前缀扫描定位源；
            // child 继承源的客户端分片后缀（同一会话血统、同一系统提示）。
            let sourceMapKey = resolveSessionMapKey(for: sourceKey.storageKey)
            guard let sourceManaged = state.withLock({
                $0.sessions[sourceMapKey]
            }) else {
                throw RuntError.generationFailed(
                    "no live source session for \(sourceKey.storageKey); cannot fork"
                )
            }

            // 官方进程内 fork：数组共享 + 首写拷贝，零磁盘 IO、零序列化
            // （对照 v1：GB 级文件拷贝 + 0.15s@58k 双向序列化税）。
            let forkStartedAt = Date()
            let childSession = await sourceManaged.session.fork()
            let forkTokenCount = await childSession.cachedTokenIds().count
            let forkMs = Int(Date().timeIntervalSince(forkStartedAt) * 1000)

            // 覆盖语义（选边提升）：旧 target 会话显式 clear 释放 KV；
            // 陈旧 checkpoint 文件即刻清除，维持「target checkpoint ⟺
            // target 当前血统」——否则 fork→首生成之间挂起会载入分叉前
            // 的旧状态。child 的 durable pair 由其首个成功轮重写。
            let clientSuffix = sourceMapKey.hasPrefix(sourceKey.storageKey + "#")
                ? String(sourceMapKey.dropFirst(sourceKey.storageKey.count))
                : ""
            let targetMapKey = targetKey.storageKey + clientSuffix
            if let oldTarget = state.withLock({
                $0.sessions.removeValue(forKey: targetMapKey)
            }) {
                await oldTarget.session.clear()
            }
            let targetBaseName = Self.cacheFileName(for: targetKey.storageKey)
            if RuntimeTuning.branchCheckpointsEnabled {
                for suffix in [".safetensors", ".meta.json"] {
                    try? FileManager.default.removeItem(
                        at: store.appendingPathComponent(targetBaseName + suffix))
                }
            }

            let child = ManagedSession(
                session: childSession,
                history: sourceManaged.history,
                historyJSON: sourceManaged.historyJSON,
                kvFingerprint: sourceManaged.kvFingerprint,
                isRestoredSnapshot: false,
                thinkingDisabled: sourceManaged.thinkingDisabled)
            child.pendingForkPoint = BranchForkPoint(
                sourceStorageKey: sourceKey.storageKey,
                atMessage: sourceManaged.history.count,
                atToken: forkTokenCount)
            child.checkpointDirty = RuntimeTuning.branchCheckpointsEnabled
            state.withLock {
                $0.sessions[targetMapKey] = child
                $0.lastActivity = Date()
            }

            // FORK-2 + STEP-10 R3 语义保持：child 绑定分叉点的 .residentKV
            // 表示（boundLength = fork 点 token 数）；parent 不绑——其池
            // 边界绑定不被 supersede（B-R2 单活行）。contentHash 标识本次
            // fork 事件（source+target+边界），非去重声明。
            var forkHasher = SHA256()
            for piece in [
                sourceKey.storageKey, targetKey.storageKey, String(forkTokenCount),
            ] {
                forkHasher.update(data: Data(piece.utf8))
            }
            let ref = RepresentationRef(
                kind: .residentKV,
                modelIdentity: modelName(from: modelPath),
                kvLayoutIdentity: sourceManaged.kvFingerprint ?? "none",
                renderIdentity: "chat-daily",
                contentHash: forkHasher.finalize().withUnsafeBytes {
                    $0.load(as: UInt64.self)
                },
                boundLength: forkTokenCount)

            // 事务边界（STEP-10）：物理 fork 成功后才登记 child 绑定——
            // 失败的 fork 不留任何关系；对已存在 target 的 re-fork 不会
            // supersede 一次从未发生的恢复。
            let childBinding = NativeMLXPrefixPool.shared.bindings.bind(
                executionID: targetKey.storageKey,
                runtimeAddress: "session-fork:\(targetKey.storageKey)",
                ref: ref)
            traceLogger.trace(
                "[MLX] branchFork session=\(sourceKey.traceKey) -> \(targetBranch)"
                + " history=\(sourceManaged.history.count) forkToken=\(forkTokenCount)"
                + " forkMs=\(forkMs)"
                + " bindingGen=\(childBinding.generation)"
                + " refHash=\(String(ref.contentHash, radix: 16))")
            lineage.recordFork(parent: sourceKey.storageKey, child: targetKey.storageKey)
            traceLogger.trace(
                "[EXEC] fork parent=\(sourceKey.storageKey)"
                + " child=\(targetKey.storageKey)")

            // 返回值是本次 fork 事件的描述符，不是 durable receipt：
            // checkpointGeneration/cacheSHA256 留空（child 此刻无盘上
            // pair）；盘上 meta 由其首个成功轮落盘并携带 forkPoint。
            return SessionCacheMetadata(
                storageKey: targetKey.storageKey,
                modelId: modelName(from: modelPath),
                savedAt: Date(),
                history: sourceManaged.historyJSON,
                kvFingerprint: sourceManaged.kvFingerprint,
                forkPoint: child.pendingForkPoint)
        }
    }

    /// 删除分支：释放 KV（官方 clear()）+ 移除会话 + 清理 checkpoint 文件。
    /// 分支不可 merge：客户端选边胜者后，其余分支走本方法回收。
    public func deleteSessionBranch(
        agentId: String? = nil,
        sessionId: String,
        logicalBranchId: String,
        in storeDirectory: URL? = nil
    ) async throws {
        let key = try AgentExecutionKey.resolve(
            agentId: agentId,
            sessionId: sessionId,
            logicalBranchId: logicalBranchId
        )
        let store = storeDirectory ?? Self.defaultBranchCheckpointStore()
        let generationKey = try generationGateKey(for: key)
        let gate = gateHolder.withLock { $0 }
        try await gate.withExclusive(generationKey) {
            let session: ChatSession? = state.withLock { state in
                state.sessions.removeValue(forKey: key.storageKey)?.session
            }
            if let session {
                await session.clear()
            }
            // STEP-10 lifecycle: deleting the branch ENDS the execution - its
            // binding is explicitly detached (Gate C: detach is an OPERATION).
            // The row is retained (append-only history); only the active state
            // clears, so currentBinding/activeBindings stop resolving it.
            _ = NativeMLXPrefixPool.shared.bindings.detach(executionID: key.storageKey)
            // #136: branch deletion is a TRUE logical session end, so the memory
            // pool must release every representation this branch authorized.
            let memPoolReleased = PrefixMemoryPool.shared.purge(esStateID: logicalBranchId)
            let baseName = Self.cacheFileName(for: key.storageKey)
            if RuntimeTuning.branchCheckpointsEnabled {
                for suffix in [".safetensors", ".meta.json"] {
                    try? FileManager.default.removeItem(
                        at: store.appendingPathComponent(baseName + suffix))
                }
            }
            traceLogger.trace(
                "[MLX] branchDelete session=\(key.traceKey) memPoolReleased=\(memPoolReleased)")
        }
    }

    /// 列出某会话的存活分支：live = 内存中的会话分支；checkpoints = 落盘 checkpoint 文件。
    public func listSessionBranches(
        agentId: String? = nil,
        sessionId: String,
        in storeDirectory: URL? = nil
    ) -> (liveBranches: [String], checkpointFiles: [String]) {
        let key = (try? AgentExecutionKey(
            agentId: agentId, sessionId: sessionId, logicalBranchId: "list"))?
            .storageKey ?? ""
        let prefix = key.isEmpty ? "" : String(key.dropLast("list".count))
        let live = state.withLock { state in
            state.sessions.keys.filter { $0.hasPrefix(prefix) }
                .map { String($0.dropFirst(prefix.count)) }
                .sorted()
        }
        let store = storeDirectory ?? Self.defaultBranchCheckpointStore()
        let filePrefix = Self.cacheFileName(for: prefix)
        let checkpoints: [String] = RuntimeTuning.branchCheckpointsEnabled
            ? ((try? FileManager.default.contentsOfDirectory(atPath: store.path)) ?? [])
                .filter { $0.hasPrefix(filePrefix) && $0.hasSuffix(".safetensors") }
                .map { String($0.dropFirst(filePrefix.count).dropLast(".safetensors".count)) }
                .sorted()
            : []
        return (live, checkpoints)
    }

    static nonisolated func makeChatMessages(_ messages: [JSONValue]) -> [Chat.Message] {
        messages.compactMap { value in
            guard case .object(let object) = value else { return nil }
            let role = (object["role"]?.string ?? "user").lowercased()
            let content = object["content"]?.messageText ?? ""

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

    // MARK: - 入站转录工具回声归一化（2026-10-15）

    /// 入站转录工具回声归一化结果：只计数，内容不进 trace。
    struct ToolEchoNormalization: Sendable {
        /// 输出转录（未变化时与原数组同引用）。
        let messages: [JSONValue]
        /// split 形态（文本位 + 连续调用位）被账本权威形态吸收的对数。
        let mergedPairs: Int
        /// 同位 tool_calls 被账本权威形态替换的条数
        /// （参数再序列化 / 字符串↔对象差异）。
        let replacedCalls: Int

        var changed: Bool {
            mergedPairs > 0 || replacedCalls > 0
        }
    }

    /// 把入站转录的 assistant 工具轮回传对齐到账本权威形态。
    ///
    /// 实证根因（2026-10-15 16:44/16:55/16:58 三轮 fork-no-rewind 全量
    /// 重渲）：上一轮生成的工具调用以 merged 形态（文本+调用同消息）入
    /// 账本，客户端回传是 split 形态（文本位+调用位）或参数再序列化
    /// 形态——形态差使 dropFirst 的 delta 边界错位，客户端形态的调用
    /// 消息混入 delta，引擎被迫对整个 arguments 区重渲染对账（实测
    /// 12.3KB→3132 tok / 4.9KB→1312 tok 分叉，132s/218s 全量重渲，
    /// cacheHitTokens=0）。归一化把回传位改写为账本消息，delta 回到
    /// 纯新增消息，已生成区零重渲染。
    ///
    /// 守门：角色/内容/id 集合任一不一致即停，保留已归一化前缀、
    /// 其余原样返回（内容不同是真分叉，照旧走全量渲染语义）；文本
    /// 内容零变化，只对齐 tool_calls 形态。账本是会话实际喂入/生成
    /// 内容的镜像（commit 不变式），改写不引入外来内容。
    static nonisolated func normalizeToolEcho(
        _ messages: [JSONValue],
        against ledger: [JSONValue]
    ) -> ToolEchoNormalization {
        var output = messages
        var mergedPairs = 0
        var replacedCalls = 0
        var ledgerIndex = 0
        var index = 0

        while ledgerIndex < ledger.count, index < output.count {
            guard
                case .object(let ledgerMessage) = ledger[ledgerIndex],
                case .object(let incomingMessage) = output[index]
            else { break }

            guard
                (ledgerMessage["role"]?.string ?? "").lowercased()
                    == (incomingMessage["role"]?.string ?? "").lowercased()
            else { break }

            let ledgerContent = ledgerMessage["content"]?.messageText ?? ""
            let incomingContent = incomingMessage["content"]?.messageText ?? ""
            let ledgerCalls = toolCallItems(ledgerMessage["tool_calls"])
            let incomingCalls = toolCallItems(incomingMessage["tool_calls"])

            if ledgerCalls.isEmpty {
                guard
                    ledgerContent == incomingContent,
                    incomingCalls.isEmpty
                else { break }
                // tool 位还须 call id 一致：并行工具可产生同内容不同 id
                // 的结果，只比内容会让游标错位到错误对应关系上。
                if ledgerMessage["role"]?.string?.lowercased() == "tool" {
                    guard
                        ledgerMessage["tool_call_id"]?.string
                            == incomingMessage["tool_call_id"]?.string
                    else { break }
                }
                ledgerIndex += 1
                index += 1
                continue
            }

            let ledgerIDs = toolCallIDs(ledgerCalls)

            // 同位形态：同文本、同 id 集 → 整消息替换为账本权威形态
            // （覆盖参数再序列化、转义、字符串↔对象表示差）。
            if !incomingCalls.isEmpty {
                guard
                    ledgerContent == incomingContent,
                    toolCallIDs(incomingCalls) == ledgerIDs
                else { break }
                if incomingMessage["tool_calls"] != ledgerMessage["tool_calls"] {
                    output[index] = ledger[ledgerIndex]
                    replacedCalls += 1
                }
                ledgerIndex += 1
                index += 1
                continue
            }

            // split 形态：本位为文本（可为空），其后跟随连续调用位。
            // 吸收位的 id 并集须与账本精确一致；缺失/多余/未知 id 都停。
            guard ledgerContent == incomingContent else { break }
            var absorbed = 0
            var absorbedIDs: [String] = []
            while index + 1 + absorbed < output.count {
                guard
                    case .object(let next) = output[index + 1 + absorbed],
                    (next["role"]?.string ?? "").lowercased() == "assistant",
                    (next["content"]?.messageText ?? "").isEmpty,
                    !toolCallItems(next["tool_calls"]).isEmpty
                else { break }
                absorbedIDs.append(
                    contentsOf: toolCallIDs(toolCallItems(next["tool_calls"])))
                absorbed += 1
            }
            guard absorbed > 0, absorbedIDs.sorted() == ledgerIDs.sorted() else { break }
            output[index] = ledger[ledgerIndex]
            output.removeSubrange((index + 1)...(index + absorbed))
            mergedPairs += 1
            ledgerIndex += 1
            index += 1
        }

        return ToolEchoNormalization(
            messages: output,
            mergedPairs: mergedPairs,
            replacedCalls: replacedCalls
        )
    }

    private static nonisolated func toolCallItems(_ value: JSONValue?) -> [JSONValue] {
        guard case .array(let items) = value else { return [] }
        return items
    }

    private static nonisolated func toolCallIDs(_ calls: [JSONValue]) -> [String] {
        calls.compactMap { call in
            guard case .object(let object) = call else { return nil }
            return object["id"]?.string
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

    /// Chat.Message is not Equatable (Tool storage is fileprivate to mlx-swift-lm),
    /// so prefix identity is decided by serialized message signatures.
    private static nonisolated func isPrefix(
        _ prefix: [Chat.Message],
        of full: [Chat.Message]
    ) -> Bool {
        guard prefix.count <= full.count else { return false }
        for (index, pair) in zip(prefix, full).enumerated() {
            if signature(pair.0) != signature(pair.1) {
                if isAssistantToolEchoLoss(pair.0, pair.1) {
                    RuntimeTraceLogger.shared.trace(
                        "[MLX] assistantToolEchoLoss index=\(index)" +
                        " storedTool=1 echoedTool=0 tolerated"
                    )
                    continue
                }
                return false
            }
        }
        return true
    }

    /// 助手消息的工具字段回传缺失：runtime 存储侧带工具调用，客户端回传
    /// 同文本但剥离了 tool_calls（2026-09-14 实测某 LC 客户端每工具轮必现，
    /// 旧逻辑因此每轮全量冷预填）。被复用 session 的内部会话保存着权威的
    /// 工具调用记录——客户端对历史消息的回传从不进入渲染——续接该会话
    /// 才是正确语义。内容不同仍是真分叉，不容错。
    private static nonisolated func isAssistantToolEchoLoss(
        _ stored: Chat.Message,
        _ incoming: Chat.Message
    ) -> Bool {
        stored.role == .assistant
            && incoming.role == .assistant
            && stored.tool != nil
            && incoming.tool == nil
            && stored.content == incoming.content
    }

    /// Returns the first index where the histories diverge, or nil when
    /// `prefix` is a true prefix of `full`. An out-of-range index means
    /// `prefix` itself is longer than `full`.
    ///
    /// This is diagnostics only, so it must apply exactly the tolerance the gate
    /// applies: a tool-echo loss is skipped here too. Reporting it as the
    /// mismatch made `prefixDiff` blame a shape that never caused a miss
    /// (measured 2026-10-26: 15 tolerated echo losses alongside real misses).
    private static nonisolated func firstPrefixMismatch(
        _ prefix: [Chat.Message],
        of full: [Chat.Message]
    ) -> Int? {
        guard prefix.count <= full.count else { return prefix.count }
        for (index, pair) in zip(prefix, full).enumerated()
        where signature(pair.0) != signature(pair.1)
            && !isAssistantToolEchoLoss(pair.0, pair.1) {
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
        // 实验 A（null-equivalence，BETA4-PROD-FINDINGS-1）：空 content 写
        // .null 而非 .string("")——客户端回显形态是 content:null，渲染对账
        // 两侧必须同形，否则条件恢复在每个工具轮必然 checkpointStale
        // （beta.4 生产日志实证，历史固有自 757082c）。渲染路径零变化：
        // makeChatMessages 的 messageText 对 .null 读出 ""。
        var object: [String: JSONValue] = [
            "role": .string("assistant"),
            "content": content.isEmpty ? .null : .string(content)
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

    /// prefixMismatch 的内容级 diff（纯诊断，2026-09-17 index=13/46 家族）：
    /// 回答「同一语义不同表示 vs 真历史分叉」——两侧 role/toolFlag、内容长度、
    /// 字符级公共前缀长度、首个分叉点两侧摘录、内容指纹。只写 trace，
    /// 不参与任何行为判定；token 级 LCP 待接入 tokenizer 后作为后续档位。
    private static nonisolated func prefixDiffLine(
        index: Int,
        stored: Chat.Message,
        incoming: Chat.Message
    ) -> String {
        let a = stored.content
        let b = incoming.content
        var common = 0
        for (x, y) in zip(a, b) {
            if x != y { break }
            common += 1
        }
        return "[MLX] prefixDiff index=\(index)" +
            " stored(role=\(stored.role.rawValue),tool=\(stored.tool != nil ? 1 : 0),len=\(a.count),fp=\(ExecutionPolicy.fingerprint(a)))" +
            " incoming(role=\(incoming.role.rawValue),tool=\(incoming.tool != nil ? 1 : 0),len=\(b.count),fp=\(ExecutionPolicy.fingerprint(b)))" +
            " commonPrefix=\(common)" +
            " stored='\(ExecutionPolicy.excerpt(a, at: common))'" +
            " incoming='\(ExecutionPolicy.excerpt(b, at: common))'"
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
    /// 保存时会话的 KV 配置指纹（2026-09-18 Phase B 补齐）：恢复会话必须
    /// 携带指纹，否则下一轮复用检查 nil ≠ 当前指纹 → reuseMiss → 全量重建，
    /// roll-forward 连续收益被清零。可选 + decodeIfPresent：旧格式文件
    /// （无此键）解码为 nil，向后兼容。
    public var kvFingerprint: String?
    /// Checkpoint generation identity. It is generated for each successful
    /// save and copied with the checkpoint during fork.
    public var checkpointGeneration: String?
    /// SHA-256 of the official .safetensors bytes for this generation.
    /// Restore is fail-closed when the sidecar and cache do not match.
    public var cacheSHA256: String?
    /// FORK-2 (STEP-10): the branch point this copy was created from, when
    /// the copy was registered by forkSessionBranch. Optional + decodeIfPresent:
    /// files saved outside a fork (and pre-STEP-10 files) decode without it.
    public var forkPoint: BranchForkPoint?

    public init(
        storageKey: String,
        modelId: String,
        savedAt: Date,
        history: [JSONValue],
        kvFingerprint: String? = nil,
        checkpointGeneration: String? = nil,
        cacheSHA256: String? = nil,
        forkPoint: BranchForkPoint? = nil
    ) {
        self.storageKey = storageKey
        self.modelId = modelId
        self.savedAt = savedAt
        self.history = history
        self.kvFingerprint = kvFingerprint
        self.checkpointGeneration = checkpointGeneration
        self.cacheSHA256 = cacheSHA256
        self.forkPoint = forkPoint
    }
}

/// FORK-2: the persisted fork point of a branch checkpoint — WHERE the copy
/// branched from, in both message and token units of the SOURCE at fork time.
nonisolated public struct BranchForkPoint: Codable, Sendable, Equatable {
    public var sourceStorageKey: String
    public var atMessage: Int
    public var atToken: Int

    public init(sourceStorageKey: String, atMessage: Int, atToken: Int) {
        self.sourceStorageKey = sourceStorageKey
        self.atMessage = atMessage
        self.atToken = atToken
    }
}
