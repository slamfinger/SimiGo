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
import SimiGoRuntimeContract
import SimiGo2Experimental

/// Session KV-cache persistence, the read-only Execution State projection and
/// the Branch Fork protocol, moved verbatim from NativeMLX.swift to keep the
/// generation file navigable. Pure file move; no logic changes.
extension NativeMLX {
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
        // Snapshot the current gate before checking runtime resources. If Stop
        // races this call, it either closes this captured gate and drains us,
        // or has already replaced it after clearing the container (so preflight fails).
        let gate = gateHolder.withLock { $0 }
        guard let container = state.withLock({ $0.modelContainer }) else {
            throw RuntError.notLoaded
        }
        _ = container

        let generationKey = try generationGateKey(for: key)
        let operationID = "save-\(UUID().uuidString.lowercased())"
        return try await gate.withExclusive(generationKey) {
            let mapKey = resolveSessionMapKey(for: key.storageKey)
            guard let managed = state.withLock({ $0.sessions[mapKey] }) else {
                throw RuntError.generationFailed(
                    "no live session for \(key.storageKey); nothing to save"
                )
            }
            try claimSessionOperation(managed, mapKey: mapKey, operationID: operationID)
            defer {
                releaseSessionOperation(managed, mapKey: mapKey, operationID: operationID)
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
    func performSave(
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
        try await managed.session.saveCache(to: cacheURL)

        // The vendor cache is written separately from the sidecar. Bind the
        // pair with a generation id + content hash so any crash/failure between
        // the two writes becomes an invalid checkpoint instead of a mixed pair.
        //
        // 上游 `saveCache(to:)` 只写文件、不返回摘要（3.32.3 起；旧轮的
        // SaveReceipt 是 mlx-swift 侧补丁产物）。摘要因此在本层按落盘字节
        // 重算：同一份文件字节 → 同一 sha256，checkpoint 语义不变。
        let cacheSHA256 = try Self.sha256HexOfFile(at: cacheURL)
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
        // Keep gate and resource preflight in lifecycle order: an operation
        // must not pair a pre-Stop container snapshot with the post-Stop gate.
        let gate = gateHolder.withLock { $0 }
        guard let container = state.withLock({ $0.modelContainer }) else {
            throw RuntError.notLoaded
        }

        let generationKey = try generationGateKey(for: key)
        let output = try await gate.withExclusive(generationKey) {
            // Resolve both the client shard and its identity snapshot only
            // AFTER owning the same gate that excludes generation/fork/delete.
            let mapKey = resolveSessionMapKey(for: key.storageKey)
            let existing = state.withLock { $0.sessions[mapKey] }

            let loaded = try await performLoad(
                key: key.storageKey, traceKey: key.traceKey, container: container,
                config: config, baseConfig: baseConfig, directory: directory,
                modelPath: modelPath)
            try state.withLock {
                let current = $0.sessions[mapKey]
                if let existing {
                    guard current === existing else {
                        throw RuntError.generationFailed(
                            "session replaced during checkpoint load: \(key.storageKey)")
                    }
                } else {
                    guard current == nil else {
                        throw RuntError.generationFailed(
                            "session appeared during checkpoint load: \(key.storageKey)")
                    }
                }
                loaded.managed.executionKey = key
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
    func performLoad(
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
        let mapKey = resolveSessionMapKey(for: key.storageKey)
        return state.withLock {
            $0.sessions[mapKey].map { $0 as AnyObject }
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
                        let displayMapKey: String
                        if let executionKey = session.executionKey {
                            let base = Self.baseSessionMapKey(
                                storageKey: executionKey.storageKey)
                            let shardSuffix = mapKey.hasPrefix(base + "#sp-")
                                ? String(mapKey.dropFirst(base.count)) : ""
                            displayMapKey = executionKey.storageKey + shardSuffix
                        } else {
                            displayMapKey = mapKey
                        }
                        return .init(
                            mapKey: mapKey,
                            label: EngineExecutionStateSnapshot.label(
                                mapKey: displayMapKey, executionKey: session.executionKey),
                            historyCount: session.history.count,
                            isRestoredSnapshot: session.isRestoredSnapshot,
                            checkpointDirty: session.checkpointDirty,
                            requestScoped: AgentExecutionKey.isRequestScopedSession(
                                session.executionKey?.storageKey ?? mapKey),
                            lastActivity: session.lastActivity)
                    },
                lineageRecords: lineageSnapshot.records,
                forks: lineageSnapshot.forks)
        }
    }

    private struct QuarantinedCheckpointFile: Sendable {
        let originalURL: URL
        let quarantineURL: URL
    }

    /// Atomically remove checkpoint files from their canonical restore names.
    /// Same-directory moves avoid copying multi-GiB safetensors files. If a
    /// later move fails, already-moved files are restored before the caller
    /// observes failure and before any in-memory branch state is changed.
    private func quarantineCheckpointFiles(
        storageKey: String, in store: URL
    ) throws -> [QuarantinedCheckpointFile] {
        guard RuntimeTuning.branchCheckpointsEnabled else { return [] }
        let fileManager = FileManager.default
        let baseName = Self.cacheFileName(for: storageKey)
        var moved: [QuarantinedCheckpointFile] = []
        for suffix in [".safetensors", ".meta.json"] {
            let original = store.appendingPathComponent(baseName + suffix)
            guard fileManager.fileExists(atPath: original.path) else { continue }
            let quarantine = store.appendingPathComponent(
                ".simigo-quarantine-\(UUID().uuidString.lowercased())-\(baseName)\(suffix).quarantine")
            do {
                try fileManager.moveItem(at: original, to: quarantine)
                moved.append(QuarantinedCheckpointFile(
                    originalURL: original, quarantineURL: quarantine))
            } catch {
                var rollbackFailures: [String] = []
                for item in moved.reversed() {
                    do {
                        try fileManager.moveItem(
                            at: item.quarantineURL, to: item.originalURL)
                    } catch {
                        rollbackFailures.append(
                            "\(item.originalURL.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                let rollback = rollbackFailures.isEmpty
                    ? "staged files restored"
                    : "rollback incomplete: \(rollbackFailures.joined(separator: "; "))"
                throw RuntError.generationFailed(
                    "checkpoint quarantine failed for \(storageKey): "
                        + "\(error.localizedDescription); \(rollback)")
            }
        }
        return moved
    }

    /// Quarantined names are never considered by branch listing or restore.
    /// Cleanup failures are explicitly traced rather than silently swallowed;
    /// they cannot resurrect a stale checkpoint because canonical names are
    /// already absent.
    private func discardQuarantinedCheckpointFiles(
        _ files: [QuarantinedCheckpointFile], operation: String
    ) -> Int {
        var failures = 0
        for item in files {
            do {
                try FileManager.default.removeItem(at: item.quarantineURL)
            } catch {
                failures += 1
                traceLogger.trace(
                    "[MLX] checkpointQuarantineCleanupFailed operation=\(operation)"
                        + " file=\(item.quarantineURL.lastPathComponent)"
                        + " err=\(error.localizedDescription)")
            }
        }
        return failures
    }

    // MARK: - Branch Fork（生产分支协议 v1；证据链与设计见 docs/decisions/BRANCH_FORK_PROTOCOL_DRAFT.md）

    /// [实验臂 / EXPERIMENTAL] 分支 checkpoint 默认存储：~/.simigo/branch-checkpoints/。
    /// 正常运行不启用（owner 裁定 U2）；目录已于 2026-11-09 手动删除。
    /// 关闭持久化（`SIMIGO_BRANCH_CHECKPOINTS=0`）时不得创建该目录——目录
    /// 本身就不该出现，而不是建了再不用。
    nonisolated public static func defaultBranchCheckpointStore() -> URL {
        let directory = RuntimeCachePaths.branchCheckpointsRoot
        if RuntimeTuning.branchCheckpointsEnabled {
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    nonisolated static func enforceDefaultBranchCheckpointRetention(
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
        let sourceKey = try AgentExecutionKey(
            agentId: agentId, sessionId: sessionId, logicalBranchId: sourceBranch)
        let targetKey = try AgentExecutionKey(
            agentId: agentId, sessionId: sessionId, logicalBranchId: targetBranch)

        // One transaction covers every key that can mutate either checkpoint.
        // When generation serialization is enabled, include the exact global
        // generation key used by generate; otherwise source + target keys are
        // sufficient. Deterministic ordering prevents cross-key deadlock.
        let sourceGenerationKey = try generationGateKey(for: sourceKey)
        let targetGenerationKey = try generationGateKey(for: targetKey)
        let transactionKeys = RuntimeTuning.serializeGeneration
            ? [sourceGenerationKey, targetGenerationKey, sourceKey, targetKey]
            : [sourceKey, targetKey]
        let operationID = "fork-\(UUID().uuidString.lowercased())"
        // Capture the gate before checking model residency so Stop cannot
        // replace the gate between a successful preflight and transaction admission.
        let gate = gateHolder.withLock { $0 }
        guard state.withLock({ $0.modelContainer != nil }) else {
            throw RuntError.notLoaded
        }

        return try await gate.withExclusive(transactionKeys) {
            // The source and published child remain protected for the full
            // lifecycle operation. Local defer scopes release claims on every exit.
            var childLease: ManagedSession?
            var childLeaseMapKey: String?
            defer {
                if let childLease, let childLeaseMapKey {
                    releaseSessionOperation(
                        childLease, mapKey: childLeaseMapKey, operationID: operationID)
                }
            }

            // 会话表键对齐：fork 不感知 system 提示；
            // child 继承源的客户端分片后缀（同一会话血统、同一系统提示）。
            let sourceMapKey = resolveSessionMapKey(for: sourceKey.storageKey)
            guard let sourceManaged = state.withLock({
                $0.sessions[sourceMapKey]
            }) else {
                throw RuntError.generationFailed(
                    "no live source session for \(sourceKey.storageKey); cannot fork"
                )
            }
            try claimSessionOperation(
                sourceManaged, mapKey: sourceMapKey, operationID: operationID)
            defer {
                releaseSessionOperation(
                    sourceManaged, mapKey: sourceMapKey, operationID: operationID)
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
            let sourceBaseMapKey = Self.baseSessionMapKey(storageKey: sourceKey.storageKey)
            let clientSuffix = sourceMapKey.hasPrefix(sourceBaseMapKey + "#sp-")
                ? String(sourceMapKey.dropFirst(sourceBaseMapKey.count))
                : ""
            let targetBaseMapKey = Self.baseSessionMapKey(storageKey: targetKey.storageKey)
            let targetMapKey = targetBaseMapKey + clientSuffix

            // Move the old durable pair out of its canonical restore names
            // before touching the live target. If staging fails, restore any
            // file already moved and leave the live branch untouched.
            let quarantinedCheckpointFiles: [QuarantinedCheckpointFile]
            do {
                quarantinedCheckpointFiles = try quarantineCheckpointFiles(
                    storageKey: targetKey.storageKey, in: store)
            } catch {
                await childSession.clear()
                throw error
            }

            // A logical branch can own several system-prompt shards. Re-fork
            // replaces the whole logical target, not only the shard inherited
            // from this particular source request. Encoded base keys make this
            // prefix exact even when a user branch contains '#sp-' itself.
            let oldTargets = state.withLock { state in
                let prefix = targetBaseMapKey + "#sp-"
                let keys = state.sessions.keys.filter {
                    $0 == targetBaseMapKey || $0.hasPrefix(prefix)
                }
                return keys.compactMap { state.sessions.removeValue(forKey: $0) }
            }
            for oldTarget in oldTargets {
                await oldTarget.session.clear()
            }
            _ = PrefixMemoryPool.shared.purge(esStateID: targetKey.storageKey)

            let child = ManagedSession(
                session: childSession,
                history: sourceManaged.history,
                historyJSON: sourceManaged.historyJSON,
                kvFingerprint: sourceManaged.kvFingerprint,
                isRestoredSnapshot: false,
                thinkingDisabled: sourceManaged.thinkingDisabled)
            child.executionKey = targetKey
            child.inFlightRequestId = operationID
            childLease = child
            childLeaseMapKey = targetMapKey
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
                boundLength: forkTokenCount,
                contentDigest: "")

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
            let checkpointCleanupFailures = discardQuarantinedCheckpointFiles(
                quarantinedCheckpointFiles, operation: "fork:\(targetKey.traceKey)")
            traceLogger.trace(
                "[MLX] branchForkCheckpointCleanup pending=\(checkpointCleanupFailures)")
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

    /// 删除一个逻辑分支及其全部 system-prompt 会话分片。
    ///
    /// 存在性检查、分片摘除、KV 清理与 checkpoint 清理都在同一生命周期
    /// gate 内完成。并发 DELETE 因而只有第一个请求能观察到并删除目标；
    /// 后续请求会得到 typed 404，而不是把 no-op 当成成功。
    @discardableResult
    public func deleteSessionBranch(
        agentId: String? = nil,
        sessionId: String,
        logicalBranchId: String,
        in storeDirectory: URL? = nil
    ) async throws -> BranchDeletionOutcome {
        let key = try AgentExecutionKey.resolve(
            agentId: agentId,
            sessionId: sessionId,
            logicalBranchId: logicalBranchId
        )
        let store = storeDirectory ?? Self.defaultBranchCheckpointStore()
        let generationKey = try generationGateKey(for: key)
        let gate = gateHolder.withLock { $0 }
        return try await gate.withExclusive(generationKey) {
            let baseName = Self.cacheFileName(for: key.storageKey)
            let checkpointURLs = [".safetensors", ".meta.json"].map {
                store.appendingPathComponent(baseName + $0)
            }
            let hadCheckpoint = RuntimeTuning.branchCheckpointsEnabled
                && checkpointURLs.contains {
                    FileManager.default.fileExists(atPath: $0.path)
                }

            // Encoded base keys make the shard prefix an exact ownership
            // boundary. A different user branch can no longer be mistaken for
            // a child shard merely because its name contains '#sp-'.
            let baseMapKey = Self.baseSessionMapKey(storageKey: key.storageKey)
            let shardPrefix = baseMapKey + "#sp-"
            let liveMapKeys = state.withLock { state in
                state.sessions.keys.filter {
                    $0 == baseMapKey || $0.hasPrefix(shardPrefix)
                }
            }
            let hadLive = !liveMapKeys.isEmpty
            guard hadLive || hadCheckpoint else {
                throw BranchLifecycleError.branchUnknown(
                    sessionId: sessionId, branchId: logicalBranchId)
            }

            // Stage the durable pair BEFORE removing live ownership. A file
            // move failure is observable and leaves the branch/session table
            // intact; a partially staged pair is rolled back by the helper.
            let quarantinedCheckpointFiles = try quarantineCheckpointFiles(
                storageKey: key.storageKey, in: store)

            let removedSessions = state.withLock { state in
                liveMapKeys.compactMap { state.sessions.removeValue(forKey: $0) }
            }
            // The generation gate excludes all in-flight use of these sessions.
            for managed in removedSessions {
                await managed.session.clear()
            }

            _ = NativeMLXPrefixPool.shared.bindings.detach(executionID: key.storageKey)
            // Memory-prefix ownership is the complete execution storage key,
            // not a branch label such as "main" shared by many sessions.
            let memPoolReleased = PrefixMemoryPool.shared.purge(esStateID: key.storageKey)
            let checkpointCleanupFailures = discardQuarantinedCheckpointFiles(
                quarantinedCheckpointFiles, operation: "delete:\(key.traceKey)")
            traceLogger.trace(
                "[MLX] branchDelete session=\(key.traceKey)"
                + " shards=\(removedSessions.count)"
                + " memPoolReleased=\(memPoolReleased)"
                + " checkpointCleanupPending=\(checkpointCleanupFailures)")

            let after = listSessionBranches(
                agentId: agentId, sessionId: sessionId, in: store)
            return BranchDeletionOutcome(
                deletedBranch: logicalBranchId,
                hadLiveSession: hadLive,
                hadCheckpointFile: hadCheckpoint,
                remainingLiveBranches: after.liveBranches,
                remainingCheckpointBranches: after.checkpointFiles)
        }
    }

    /// Convert the runtime-only client shard suffix back to the logical
    /// branch identity exposed by the branch lifecycle API. The shard suffix
    /// is ExecutionPolicy's eight-hex FNV-1a fingerprint; it is not a branch.
    nonisolated static func logicalBranchID(fromSessionMapSuffix suffix: String) -> String {
        guard let marker = suffix.range(of: "#sp-", options: .backwards) else {
            return suffix
        }
        let fingerprint = suffix[marker.upperBound...]
        guard fingerprint.count == 8,
              UInt32(String(fingerprint), radix: 16) != nil else {
            return suffix
        }
        return String(suffix[..<marker.lowerBound])
    }

    /// 列出某会话的存活分支：live = 内存中的会话分支；checkpoints = 落盘 checkpoint 文件。
    public func listSessionBranches(
        agentId: String? = nil,
        sessionId: String,
        in storeDirectory: URL? = nil
    ) -> (liveBranches: [String], checkpointFiles: [String]) {
        let identity = try? AgentExecutionKey(
            agentId: agentId, sessionId: sessionId, logicalBranchId: "list")
        let prefix = identity.map { String($0.storageKey.dropLast("list".count)) } ?? ""
        let live = state.withLock { state in
            let logicalIDs = state.sessions.values.compactMap { managed -> String? in
                guard let owner = managed.executionKey,
                      let identity,
                      owner.agentId == identity.agentId,
                      owner.sessionId == identity.sessionId else {
                    return nil
                }
                return owner.logicalBranchId
            }
            return Array(Set(logicalIDs)).sorted()
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

    static nonisolated func decodeToolArguments(
        _ data: Data?
    ) -> [String: JSONValue]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([String: JSONValue].self, from: data)
    }

    /// Decode echoed calls independently. A malformed sibling must not make
    /// JSONDecoder reject the entire array and erase otherwise valid calls.
    static nonisolated func parseToolCalls(_ value: JSONValue?) -> [ToolCall] {
        guard case .array(let items) = value else { return [] }
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        return items.compactMap { item in
            var candidate = item
            if case .object(var object) = item,
               case .object(var function)? = object["function"],
               case .string(let rawArguments)? = function["arguments"] {
                guard let data = rawArguments.data(using: .utf8),
                      let decoded = try? decoder.decode(JSONValue.self, from: data),
                      case .object = decoded else {
                    return nil
                }
                function["arguments"] = decoded
                object["function"] = .object(function)
                candidate = .object(object)
            }

            guard let data = try? encoder.encode(candidate),
                  let call = try? decoder.decode(ToolCall.self, from: data) else {
                return nil
            }
            return call
        }
    }
}
