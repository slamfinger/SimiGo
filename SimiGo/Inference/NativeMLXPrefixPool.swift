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

    /// 轮末导出：把已处理消息流注册为新边界（best-effort——导出失败
    /// 只记 trace 不影响本轮成功）。await 内联执行：不与下一轮对该
    /// session 的使用竞态（生成全局串行已由 serializeGeneration 保证）。
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
