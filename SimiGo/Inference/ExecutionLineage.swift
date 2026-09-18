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

public struct ForkEvent: Sendable {
    public let parent: String
    public let child: String
    public let at: Date
}

/// 有界血统日志（每 Runtime 实例一份；FIFO 淘汰）。只记录与查询。
public final class ExecutionLineage: @unchecked Sendable {
    private struct Storage {
        var records: [ExecutionRecord] = []
        var forks: [ForkEvent] = []
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

    /// fork 事件：分支级派生真值记录（parent/child 均为 storageKey）。
    public func recordFork(parent: String, child: String) {
        lock.withLock { storage in
            storage.forks.append(
                ForkEvent(parent: parent, child: child, at: Date()))
            if storage.forks.count > capacity {
                storage.forks.removeFirst(storage.forks.count - capacity)
            }
        }
    }

    public var snapshot: (records: [ExecutionRecord], forks: [ForkEvent]) {
        lock.withLock { storage in
            (records: storage.records, forks: storage.forks)
        }
    }
}
