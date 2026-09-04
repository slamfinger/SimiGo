import Foundation

/// SimiGo 推理节点全局 Prefill 计算调度器
///
/// 设计原则（遵循 v4.5 白皮书准则 21 & 30）：
/// - Prefill 是 Apple Silicon 统一内存带宽消耗最高的计算阶段，在全节点范围内实行全局公平排队。
/// - Decode 阶段不占 Prefill 锁，保证解码多任务的并发重叠。
actor PrefillScheduler {
    private struct Waiter {
        let id: UUID
        let requestId: String
        let enqueuedAt: Date
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var activeRequestId: String?
    private var waiters: [Waiter] = []

    func acquire(requestId: String) async -> (granted: Bool, waited: TimeInterval) {
        if Task.isCancelled {
            return (false, 0)
        }

        if activeRequestId == nil {
            activeRequestId = requestId
            return (true, 0)
        }

        let waiterId = UUID()
        let enqueuedAt = Date()

        let granted = await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                    return
                }

                waiters.append(
                    Waiter(
                        id: waiterId,
                        requestId: requestId,
                        enqueuedAt: enqueuedAt,
                        continuation: continuation
                    )
                )

                // 注册后即时检查，关闭取消注册竞争窗口
                if Task.isCancelled, let index = waiters.firstIndex(where: { $0.id == waiterId }) {
                    let waiter = waiters.remove(at: index)
                    waiter.continuation.resume(returning: false)
                }
            }
        }, onCancel: {
            Task {
                await self.cancelWaiter(waiterId)
            }
        })

        let waited = max(Date().timeIntervalSince(enqueuedAt), 0)
        return (granted, waited)
    }

    func release(requestId: String) {
        guard activeRequestId == requestId else {
            return
        }

        if waiters.isEmpty {
            activeRequestId = nil
            return
        }

        let next = waiters.removeFirst()
        activeRequestId = next.requestId
        next.continuation.resume(returning: true)
    }

    func cancelWaiter(_ waiterId: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == waiterId }) else {
            return
        }

        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }

    func cancelAll() {
        let pending = waiters
        waiters.removeAll()

        for waiter in pending {
            waiter.continuation.resume(returning: false)
        }

        activeRequestId = nil
    }

    func snapshot() -> (activeRequestId: String?, queued: Int) {
        (activeRequestId, waiters.count)
    }
}
