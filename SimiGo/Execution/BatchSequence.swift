import Foundation

/// S1（白皮书第六章 §6.3）：Batch 内一个执行成员。
///
/// 不变量（白皮书钉死）：`executionKey ≠ slotId`——
/// executionKey 是 Logical 身份（Agent/Session/Branch），slotId 是 Execution
/// Plane 槽位；两者可以在批内重复映射，但永远不能互相冒充。
///
/// tokenState/cacheState 的完整形态（per-sequence KV、position 等）在 S1.2
/// 接入真实 Batched Forward 时填充；本骨架只携带计数与相位。
struct BatchSequence: Sendable, Equatable {
    enum Phase: Sendable, Equatable {
        case waiting
        case active
        case cancelled
        case finished
    }

    let requestId: String
    let executionKey: String
    /// Execution Plane 槽位（0 ..< batchSize）——与 executionKey 语义无关
    let slotId: Int
    var phase: Phase
    /// 已生成的 token 数（每 decode step +1）
    var generatedTokens: Int

    init(requestId: String, executionKey: String, slotId: Int) {
        self.requestId = requestId
        self.executionKey = executionKey
        self.slotId = slotId
        self.phase = .waiting
        self.generatedTokens = 0
    }

    var isActive: Bool { phase == .active }
    var isCancelled: Bool { phase == .cancelled }
}
