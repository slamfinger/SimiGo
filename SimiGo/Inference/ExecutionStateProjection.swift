import Foundation

/// Execution State 引擎只读投影（2026-10-16 收敛：窗口接真身）。
///
/// 纯数据快照：由 NativeMLX 在 state 锁内抄会话表 + lineage 快照得到。
/// 零行为、零 IO、零新执行语义——不参与 reuse/restore/驱逐任何决策，
/// 只作展示层事实源（与 S5 血统红线同一纪律：记录与查询，不做决策）。
/// 外部进程 / 云后端无进程内执行状态，投影为 nil。
nonisolated public struct EngineExecutionStateSnapshot: Sendable {
    nonisolated public struct SessionCard: Sendable {
        /// 紧凑展示键（traceKey 惯例 + client-split 分片后缀）。
        public let label: String
        /// 消息级账本条数（history）。
        public let historyCount: Int
        /// checkpoint 恢复态会话（raw-cache，vendor 侧无账本）。
        public let isRestoredSnapshot: Bool
        /// 活执行新于 durable checkpoint（挂起重试路径会补落盘）。
        public let checkpointDirty: Bool
        /// 请求级一次性会话（*-request:UUID，不参与跨请求 reuse）。
        public let requestScoped: Bool
        public let lastActivity: Date
    }

    public let isRunning: Bool
    public let pendingRequests: Int
    public let activeGenerations: Int
    public let sessions: [SessionCard]
    public let lineageRecords: [ExecutionRecord]
    public let forks: [BranchForkEvent]

    /// mapKey → 紧凑展示键：镜像 AgentExecutionKey.traceKey 语义
    /// （default agent 省略、session id 折叠到末段 ≤6 位）；storageKey
    /// 非标准三段时退化为末 12 字符。client-split 分片后缀（#指纹）
    /// 原样保留——双客户端分片在 UI 上必须可区分。
    nonisolated public static func compactLabel(mapKey: String) -> String {
        var base = mapKey
        var shard = ""
        if let hashIndex = mapKey.firstIndex(of: "#") {
            base = String(mapKey[mapKey.startIndex..<hashIndex])
            shard = String(mapKey[hashIndex...])
        }
        let parts = base.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return String(base.suffix(12)) + shard }
        let agent = parts[0] == "default" ? "" : parts[0] + "/"
        var block = parts[1].split(separator: "-").last.map(String.init) ?? parts[1]
        if block.count > 6 { block = String(block.suffix(6)) }
        return agent + block + "/" + parts[2] + shard
    }

    /// 会话卡片标签：executionKey 在场时用其 traceKey（权威口径），
    /// 并以 storageKey 前缀差还原 client-split 分片后缀（与
    /// sessionClientSplit trace 同法）；否则按 mapKey 推导。
    /// internal：签名含内部类型 AgentExecutionKey。
    nonisolated static func label(mapKey: String, executionKey: AgentExecutionKey?) -> String {
        guard let executionKey else { return compactLabel(mapKey: mapKey) }
        var label = executionKey.traceKey
        if mapKey.hasPrefix(executionKey.storageKey + "#") {
            label += String(mapKey.dropFirst(executionKey.storageKey.count))
        }
        return label
    }
}
