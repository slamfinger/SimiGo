import Foundation

/// S1（白皮书第六/七章）：Execution Plane 的批化调度骨架。
///
/// 职责边界（白皮书钉死）：
/// - 拥有：等待队列、Capability 过滤、固定批组装、成员相位（active/cancelled/finished）
/// - 不拥有：Session、Tool Protocol、Agent 生命周期、PhysicalKVRevision 语义
/// - Logical Safety Filter / KV Admission / Latency Budget 属于 S1 后续阶段的
///   注入式钩子（本骨架预留 formation 管线位，不做实现）
///
/// 第一版固定 batch（2/4，白皮书第七章）：same model、standard-KV、greedy、
/// 固定 decode quantum；禁止 continuous/ragged/hybrid/跨模型批。
actor BatchedDecodeScheduler {
    let capabilities: InferenceModelCapabilities
    let fixedBatchSize: Int

    private var waiting: [BatchSequence] = []
    private var active: [BatchSequence] = []
    private var finished: [BatchSequence] = []
    private var nextSlot = 0

    init(capabilities: InferenceModelCapabilities, fixedBatchSize: Int = 4) {
        precondition(fixedBatchSize == 2 || fixedBatchSize == 4, "S1 第一版仅支持固定 batch 2/4")
        self.capabilities = capabilities
        self.fixedBatchSize = fixedBatchSize
    }

    var waitingCount: Int { waiting.count }
    var activeCount: Int { active.count }

    /// 提交请求进入等待队列。
    /// Capability Filter（白皮书 formation 管线第一级）：
    /// 模型不支持 Batch Decode 或成员超出容量时拒绝——拒绝即抛错，
    /// 调用方（未来的 Execution Gate）负责映射为请求级失败。
    func submit(_ request: (requestId: String, executionKey: String)) throws -> BatchSequence {
        guard capabilities.supportsBatchDecode else {
            throw BatchSchedulerError.capabilityUnsupported
        }
        guard waiting.count + active.count < fixedBatchSize else {
            throw BatchSchedulerError.batchFull
        }

        let sequence = BatchSequence(
            requestId: request.requestId,
            executionKey: request.executionKey,
            slotId: waiting.count + active.count
        )
        waiting.append(sequence)
        return sequence
    }

    /// Batch Formation（白皮书 formation 管线末级）：
    /// 等待队列 FIFO 组装为一批；返回组成成员并转入 active。
    /// 返回空数组 = 可组成成员不足。
    func formBatch() -> [BatchSequence] {
        guard !waiting.isEmpty else { return [] }

        var formed: [BatchSequence] = []
        while formed.count < fixedBatchSize, !waiting.isEmpty {
            var member = waiting.removeFirst()
            member.phase = .active
            formed.append(member)
        }

        active.append(contentsOf: formed)
        return formed
    }

    /// 批内成员取消（白皮书第九章）：该成员立即离开后续 decode step，
    /// 其余成员继续；取消成员永不提交部分 KV（由调用方的 commit 语义保证）。
    func cancel(requestId: String) {
        if let index = waiting.firstIndex(where: { $0.requestId == requestId }) {
            var member = waiting.remove(at: index)
            member.phase = .cancelled
            finished.append(member)
        }

        if let index = active.firstIndex(where: { $0.requestId == requestId }) {
            var member = active.remove(at: index)
            member.phase = .cancelled
            finished.append(member)
        }
    }

    /// decode step 完成后推进成员计数；某成员达到输出上限时转为 finished。
    func stepCompleted(requestId: String) {
        if let index = active.firstIndex(where: { $0.requestId == requestId }) {
            active[index].generatedTokens += 1
        }
    }

    func finish(requestId: String) {
        if let index = active.firstIndex(where: { $0.requestId == requestId }) {
            var member = active.remove(at: index)
            member.phase = .finished
            finished.append(member)
        }
    }

    /// 当前批内活跃成员（decode quantum 的输入顺序 = slotId 顺序）。
    func activeMembers() -> [BatchSequence] {
        active.sorted { $0.slotId < $1.slotId }
    }

    func finishedMembers() -> [BatchSequence] {
        finished
    }
}

enum BatchSchedulerError: Error, Equatable {
    case capabilityUnsupported
    case batchFull
}
