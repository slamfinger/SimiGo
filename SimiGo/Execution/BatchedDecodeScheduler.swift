import Foundation

/// S1（白皮书第六/九章，审计第五轮 slot/cancel 语义修正）：
/// Execution Plane 的批化调度骨架。
///
/// 职责边界（白皮书钉死）：
/// - 拥有：等待队列、Capability 过滤、固定批组装、成员相位（waiting/active/cancelled/finished）
/// - 不拥有：Session、Tool Protocol、Agent 生命周期、PhysicalKVRevision 语义
/// - Logical Safety Filter / KV Admission / Latency Budget 属于 S1 后续阶段的
///   注入式钩子（本骨架预留 formation 管线位，不做实现）
///
/// 取消语义（审计第五轮修正 + 第六轮 executionFrame 补强：fixed-slot / non-compaction）：
/// - cancel → 标记 phase = .cancelled 并**保留 execution slot**（成员留在 roster）
/// - decode quantum 边界调用 `reclaimCancelledSlots()` 后才回收槽位
/// - 白皮书第九章语义：A ✓ / B ✗ / C ✓ / D ✓ —— batch 宽度不变，
///   非 active 行由 forward 侧跳过（future seq-id / fixed slot 兼容）
/// - 注意：这是 **non-compaction** 语义；「发送 [B=3] 的 compaction」是另一种可选
///   演进，两者不得混用（审计判定当前代码 compaction 与白皮书 non-compaction 冲突）
///
/// Forward 接线契约（审计第六轮 P1-2）：
/// **Scheduler 便利投影 ≠ Forward 执行布局**。未来接 MLX 时必须使用
/// `executionFrame()`（fixed slot + active mask），不得依赖
/// `activeMembers()`（业务层便利视图，天然是 compacted 投影）。
///
/// fallback 语义（审计第六轮 P2 措辞修正）：本调度器只做 **拒绝**；
/// 「Batch reject → Execution Gate 选择 Single / interleaved fallback」——
/// fallback 由调用方（Execution Gate）选择，本组件内不存在 fallback 实现。
///
/// 第一版固定 batch（2/4，白皮书第七章）：same model、standard-KV、greedy、
/// 固定 decode quantum；禁止 continuous/ragged/hybrid/跨模型批。
actor BatchedDecodeScheduler {
    let capabilities: InferenceModelCapabilities
    let fixedBatchSize: Int

    private var waiting: [BatchSequence] = []
    private var roster: [BatchSequence] = [] // slot 持有者（active + cancelled，直到 reclaim）
    private var finished: [BatchSequence] = []
    private var nextSlot = 0

    init(capabilities: InferenceModelCapabilities, fixedBatchSize: Int = 4) {
        precondition(fixedBatchSize == 2 || fixedBatchSize == 4, "S1 第一版仅支持固定 batch 2/4")
        self.capabilities = capabilities
        self.fixedBatchSize = fixedBatchSize
    }

    var waitingCount: Int { waiting.count }

    /// 批内持有 slot 的成员（含已取消未回收的——slot 保留到 quantum 边界）
    var rosterCount: Int { roster.count }

    /// decode quantum 的活跃成员数（phase == .active）
    var activeCount: Int { roster.filter { $0.phase == .active }.count }

    /// Effective gate（两层三态，evaluate 时按资格键判定固化）。
    /// 当前锁定依赖 = rejected → false → 拒绝组批，
    /// Execution Gate 选择 Single / interleaved fallback。
    private var batchDecodeAllowed: Bool {
        capabilities.effectiveSupportsBatchDecode
            && capabilities.executionProfile.batchDecodeT1 == .verified
    }

    /// 提交请求进入等待队列。
    /// Capability Filter（白皮书 formation 管线第一级，两层三态）：
    /// Static 必要条件 + 资格键匹配 + Validated 状态同时满足才接受；
    /// 拒绝 = Batch reject → Execution Gate 选择 Single / interleaved fallback
    /// （fallback 由调用方实现，本组件内不存在 fallback 路径）。
    func submit(_ request: (requestId: String, executionKey: String)) throws -> BatchSequence {
        guard batchDecodeAllowed else {
            throw BatchSchedulerError.capabilityUnsupported
        }
        guard waiting.count + roster.count < fixedBatchSize else {
            throw BatchSchedulerError.batchFull
        }

        let sequence = BatchSequence(
            requestId: request.requestId,
            executionKey: request.executionKey,
            slotId: nextSlot
        )
        nextSlot += 1
        waiting.append(sequence)
        return sequence
    }

    /// Batch Formation（白皮书 formation 管线末级）：
    /// 等待队列 FIFO 组装为一批；返回组成成员并转入 active。
    /// 返回空数组 = 可组成成员不足。
    func formBatch() -> [BatchSequence] {
        guard batchDecodeAllowed, !waiting.isEmpty else { return [] }

        var formed: [BatchSequence] = []
        while formed.count < fixedBatchSize, !waiting.isEmpty {
            var member = waiting.removeFirst()
            member.phase = .active
            formed.append(member)
            roster.append(member)
        }

        return formed
    }

    /// Forward 执行布局（fixed slot + active mask）。
    ///
    /// 契约：**Scheduler 便利投影 ≠ Forward 执行布局**——
    /// 未来接 MLX 时 forward 的 batch 输入必须按本 frame 的 slot 顺序与
    /// activeMask 构造（inactive 行占位跳过），不得使用 `activeMembers()`
    /// （compact 便利投影会把 [A, B✗, C, D] 变成 [A, C, D]，
    /// 再次引入 compaction 语义）。
    func executionFrame() -> BatchExecutionFrame {
        let slots = roster
            .sorted { $0.slotId < $1.slotId }
            .map {
                BatchExecutionFrame.Slot(
                    slotId: $0.slotId,
                    requestId: $0.requestId,
                    isActive: $0.phase == .active
                )
            }
        return BatchExecutionFrame(slots: slots)
    }

    /// 批内成员取消（fixed-slot / non-compaction）：
    /// 标记 phase = .cancelled 并保留 execution slot 至 quantum 边界；
    /// 非 active 行由 forward 侧跳过。不影响其余成员。
    func cancel(requestId: String) {
        if let index = waiting.firstIndex(where: { $0.requestId == requestId }) {
            var member = waiting.remove(at: index)
            member.phase = .cancelled
            finished.append(member)
        }

        if let index = roster.firstIndex(where: { $0.requestId == requestId }) {
            roster[index].phase = .cancelled
        }
    }

    /// decode quantum 边界：回收已取消成员的槽位。
    /// 返回回收数量。回收后空出的 slot 由 nextSlot 计数器继续单调分配
    /// （同阶段内不复用已回收的 slotId，避免身份混淆）。
    func reclaimCancelledSlots() -> Int {
        let before = roster.count
        roster.removeAll { $0.phase == .cancelled }
        return before - roster.count
    }

    /// decode step 完成后推进成员计数。
    /// 仅 active 成员计数；cancelled 成员不再 decode（forward 侧跳过）。
    func stepCompleted(requestId: String) {
        if let index = roster.firstIndex(where: { $0.requestId == requestId && $0.phase == .active }) {
            roster[index].generatedTokens += 1
        }
    }

    /// 成员完成：离开 active 名册，进入 finished（phase = .finished）。
    func finish(requestId: String) {
        if let index = roster.firstIndex(where: { $0.requestId == requestId }) {
            var member = roster.remove(at: index)
            member.phase = .finished
            finished.append(member)
        }
    }

    /// 业务层便利视图（phase == .active，slotId 顺序）。
    /// 注意：这是 **compact 投影**——不得用于 forward 输入构造；
    /// forward 布局必须使用 `executionFrame()`。
    func activeMembers() -> [BatchSequence] {
        roster.filter { $0.phase == .active }.sorted { $0.slotId < $1.slotId }
    }

    /// slot 名册（含 cancelled 未回收成员——fixed-slot 语义的可观测投影）。
    func rosterMembers() -> [BatchSequence] {
        roster.sorted { $0.slotId < $1.slotId }
    }

    func finishedMembers() -> [BatchSequence] {
        finished
    }
}

/// Forward 执行布局（fixed slot + active mask）。
/// 顺序 = slot 顺序 = 未来 batched forward 的行顺序；
/// inactive 行占位、由 forward 侧跳过（S1 交错路径下整批禁用，见 Capability gate）。
struct BatchExecutionFrame: Sendable, Equatable {
    struct Slot: Sendable, Equatable {
        let slotId: Int
        let requestId: String
        let isActive: Bool
    }

    let slots: [Slot]

    var activeMask: [Bool] { slots.map(\.isActive) }
    var activeRequestIds: [String] {
        slots.filter(\.isActive).map(\.requestId)
    }
}

enum BatchSchedulerError: Error, Equatable {
    case capabilityUnsupported
    case batchFull
}
