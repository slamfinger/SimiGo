import Foundation
import MLXLMCommon
import SimiGo2Experimental

/// Route B 前缀池协调器（SIMIGO17_PREFIX_POOL 门 B-4）——跨会话内容寻址
/// KV 共享在产品日常路径的接缝。
///
/// 语义（与 E 线 Execution State 原则一致）：逻辑会话按内容消费物理
/// KV 表示，不按会话身份独占。三步链全程对账（P-I1）：
///   admission   存储边界哈希 == 对来方消息流重算的链哈希（池内核）
///   load        快照 sidecar 声明 == 条目声明（适配器，不符即删条目
///               + 响亮 throw——绝不静默续算）
///   export      轮末把已处理消息流 + 新鲜 KV 快照注册为新边界
///
/// 先级：同会话活复用（cacheEff=1.00 那条健康路径）永远第一优先；
/// 池只接住「换会话 key / 重启后」的冷重建。
final class NativeMLXPrefixPool: @unchecked Sendable {
    static let shared = NativeMLXPrefixPool()

    private let lock = NSLock()
    private var store: PrefixSnapshotStore?
    private var rescanned = false
    /// 已导出的 token 边界登记（避免同轮重复落盘同一边界）。
    private var exportedTokenBoundaries = Set<String>()

    static func namespace(modelID: String, kvFingerprint: String?, thinkingDisabled: Bool)
        -> PrefixPoolNamespace
    {
        PrefixPoolNamespace(
            modelID: modelID,
            kvFingerprint: (kvFingerprint ?? "none") + "|think:" + (thinkingDisabled ? "0" : "1"))
    }

    func makeStore() -> PrefixSnapshotStore {
        lock.lock()
        defer { lock.unlock() }
        if let store { return store }
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".simigo/prefix-pool")
        let store = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: RuntimeTuning.prefixPoolTokenBudget))
        self.store = store
        // 重启 warm：磁盘边界重新注册进池。声明式注册——P-I1 在 admission
        // 对来方消息流重算，坏声明只会 miss。
        if let count = try? store.rescan() {
            RuntimeTraceLogger.shared.trace("[MLX] poolRescan entries=\(count)")
        }
        return store
    }

    /// 冷重建前的池查询。返回已对账的命中（覆盖消息数 = tokenCount/2）。
    func admit(
        modelID: String, kvFingerprint: String?, thinkingDisabled: Bool,
        incoming: [(role: String, content: String)]
    ) -> PrefixAdmission? {
        guard RuntimeTuning.prefixPoolEnabled else { return nil }
        let namespace = Self.namespace(
            modelID: modelID, kvFingerprint: kvFingerprint, thinkingDisabled: thinkingDisabled)
        let store = makeStore()
        let result = store.pool.admit(
            namespace: namespace, promptTokens: PrefixMessageChain.stream(incoming))
        if result != nil {
            RuntimeTraceLogger.shared.trace(
                "[MLX] poolHit messages=\(result!.entry.tokenCount / 2)")
        }
        return result
    }

    /// 命中装载（适配器内完成 sidecar 对账；失败即抛+条目自愈）。
    func load(_ admission: PrefixAdmission) async throws -> PromptCacheSnapshot {
        try await makeStore().load(admission)
    }

    /// B-6：安装 fork 级跨会话 token 前缀查询钩子（模型加载时一次）。
    /// 同步闭包：池对账（token 链）→ sidecar 对账 → 快照装载，任一失败
    /// 自愈 + nil（会话回退全量 prefill）。命名空间绑定**基配置**指纹；
    /// 非基 kvSettings 的会话不导出 token 边界（登记的 beta 边界：仅基
    /// 配置会话进 token 池，跨 plan 类的静默误装不可能发生）。
    func installHook(modelID: String, kvFingerprint: String?, thinkingDisabled: Bool) {
        guard RuntimeTuning.prefixPoolEnabled else { return }
        let namespace = Self.namespace(
            modelID: modelID, kvFingerprint: kvFingerprint, thinkingDisabled: thinkingDisabled)
        ChatSession.crossSessionPrefixLookup = { [weak self] promptTokenIds in
            guard let self,
                let admission = self.makeStore().pool.admit(
                    namespace: namespace, promptTokens: promptTokenIds)
            else { return nil }
            do {
                let snapshot = try self.makeStore().loadSync(admission)
                RuntimeTraceLogger.shared.trace(
                    "[MLX] poolTokenHit tokens=\(admission.entry.tokenCount)")
                return (snapshot, admission.entry.tokenCount)
            } catch {
                RuntimeTraceLogger.shared.trace(
                    "[MLX] poolTokenHitRejected err=\(String(describing: error))")
                return nil
            }
        }
    }

    /// B-6：轮末 token 边界导出——全量 + 2048 网格（best-effort，已导出
    /// 的边界不重写）。
    func exportTokenBoundaries(
        modelID: String, kvFingerprint: String?, thinkingDisabled: Bool,
        tokenIds: [Int], session: ChatSession
    ) async {
        guard RuntimeTuning.prefixPoolEnabled, tokenIds.count > 2048 else { return }
        let namespace = Self.namespace(
            modelID: modelID, kvFingerprint: kvFingerprint, thinkingDisabled: thinkingDisabled)
        let store = makeStore()
        var boundaries: [Int] = [tokenIds.count]
        var grid = 2048
        while grid < tokenIds.count {
            boundaries.append(grid)
            grid += 2048
        }
        for count in boundaries {
            let slice = Array(tokenIds[..<count])
            let hash = PrefixChain.hash(slice)
            let key = "\(namespace.modelID)|\(namespace.kvFingerprint)|\(count)|\(hash)"
            lock.lock()
            let known = exportedTokenBoundaries.contains(key)
            lock.unlock()
            guard !known else { continue }
            do {
                _ = try await store.export(
                    namespace: namespace, tokens: slice
                ) { url in
                    try await session.savePrefixSnapshot(to: url, upTo: count)
                }
                lock.lock()
                exportedTokenBoundaries.insert(key)
                lock.unlock()
                RuntimeTraceLogger.shared.trace(
                    "[MLX] poolTokenExport tokens=\(count)")
            } catch {
                RuntimeTraceLogger.shared.trace(
                    "[MLX] poolTokenExportFailed tokens=\(count) err=\(String(describing: error))")
            }
        }
    }
    func export(
        modelID: String, kvFingerprint: String?, thinkingDisabled: Bool,
        history: [(role: String, content: String)],
        save: @escaping (URL) async throws -> Void
    ) async {
        guard RuntimeTuning.prefixPoolEnabled else { return }
        let namespace = Self.namespace(
            modelID: modelID, kvFingerprint: kvFingerprint, thinkingDisabled: thinkingDisabled)
        let store = makeStore()
        do {
            let entry = try await store.export(
                namespace: namespace, tokens: PrefixMessageChain.stream(history),
                write: save)
            RuntimeTraceLogger.shared.trace(
                "[MLX] poolExport messages=\(entry.tokenCount / 2)")
        } catch {
            RuntimeTraceLogger.shared.trace(
                "[MLX] poolExportFailed err=\(String(describing: error))")
        }
    }
}
