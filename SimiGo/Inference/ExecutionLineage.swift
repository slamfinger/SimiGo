import Foundation
import Synchronization

/// V1.6 S5：执行血统（外审十轮红线在先——Session / Execution / Branch /
/// Checkpoint / Trace 五身份保持分离；本文件只描述**单次 execution 的
/// 生命周期与关联**，不吞并其他身份对象，不做任何执行决策）。

public enum ExecutionStatus: String, Sendable {
    case running
    case completed
    case failed
    case cancelled
}

public struct ExecutionRecord: Sendable {
    public let executionId: String
    public let requestId: String
    public let agentId: String?
    public let sessionId: String
    public let logicalBranchId: String
    public var status: ExecutionStatus
    public let startedAt: Date
    public var completedAt: Date?
    /// 成功落盘 checkpoint 的存储键（performSave 成功后关联）
    public var checkpointKey: String?
}

/// 分支派生事件（BranchFork v1 provenance）——parent/child 均为
/// **storageKey 级**分支寻址，语义是"checkpoint 从哪个分支复制而来"，
/// **不是** execution→execution lineage（当前 fork 不产生执行级父子）。
/// （外审十一轮 P2-2：语义钉死，防误读为执行血统。）
public struct BranchForkEvent: Sendable {
    public let parent: String
    public let child: String
    public let at: Date
}

/// 有界血统日志（每 Runtime 实例一份；FIFO 淘汰）。只记录与查询。
public final class ExecutionLineage: @unchecked Sendable {
    private struct Storage {
        var records: [ExecutionRecord] = []
        var forks: [BranchForkEvent] = []
    }

    private let capacity: Int
    private let lock: Mutex<Storage>

    public init(capacity: Int = 128) {
        self.capacity = capacity
        self.lock = Mutex(Storage())
    }

    public func begin(_ record: ExecutionRecord) {
        lock.withLock { storage in
            storage.records.append(record)
            if storage.records.count > capacity {
                storage.records.removeFirst(storage.records.count - capacity)
            }
        }
    }

    public func end(executionId: String, status: ExecutionStatus) {
        lock.withLock { storage in
            guard let idx = storage.records.firstIndex(where: { $0.executionId == executionId }) else { return }
            storage.records[idx].status = status
            storage.records[idx].completedAt = Date()
        }
    }

    public func attachCheckpoint(executionId: String, checkpointKey: String) {
        lock.withLock { storage in
            if let idx = storage.records.firstIndex(where: { $0.executionId == executionId }) {
                storage.records[idx].checkpointKey = checkpointKey
            }
        }
    }

    /// 分支派生事件：仅在整个 fork（save→copy→load）成功后记录——
    /// 失败的 fork 不留 parent→child 假 provenance。
    public func recordFork(parent: String, child: String) {
        lock.withLock { storage in
            storage.forks.append(
                BranchForkEvent(parent: parent, child: child, at: Date()))
            if storage.forks.count > capacity {
                storage.forks.removeFirst(storage.forks.count - capacity)
            }
        }
    }

    public var snapshot: (records: [ExecutionRecord], forks: [BranchForkEvent]) {
        lock.withLock { storage in
            (records: storage.records, forks: storage.forks)
        }
    }
}
