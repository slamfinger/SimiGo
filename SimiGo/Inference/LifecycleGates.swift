import Foundation

enum NativeMLXValidationError: Error, LocalizedError, Sendable {
    case invalidExecutionKey(String)
    case invalidMessageHistory(String)
    case contextDemandExceeded(Int, Int)

    var errorDescription: String? {
        switch self {
        case .invalidExecutionKey(let message), .invalidMessageHistory(let message):
            return message

        case .contextDemandExceeded(let demand, let budget):
            return "Effective context demand (\(demand)) exceeds safety budget (\(budget)). L1 Agent Compaction required."
        }
    }
}

enum GateWaiterState {
    case waiting
    case granted
    case cancelled
}

// MARK: - Tier 1: Runtime Lifecycle Gate

actor RuntimeLifecycleGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
        var state: GateWaiterState = .waiting
    }

    private var busy = false
    private var waiters: [Waiter] = []

    func withLock<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()

        guard await acquire() else {
            throw CancellationError()
        }

        defer {
            release()
        }

        try Task.checkCancellation()
        return try await operation()
    }

    func withLockVoid(_ operation: @Sendable () async -> Void) async {
        guard !Task.isCancelled else { return }
        guard await acquire() else { return }

        defer {
            release()
        }

        guard !Task.isCancelled else { return }
        await operation()
    }

    private func acquire() async -> Bool {
        if Task.isCancelled {
            return false
        }

        if !busy {
            busy = true
            return true
        }

        let waiterId = UUID()

        return await withTaskCancellationHandler(
            operation: {
                await withCheckedContinuation { continuation in
                    enqueue(id: waiterId, continuation: continuation)
                }
            },
            onCancel: {
                Task {
                    await self.cancel(id: waiterId)
                }
            }
        )
    }

    private func enqueue(id: UUID, continuation: CheckedContinuation<Bool, Never>) {
        if Task.isCancelled {
            continuation.resume(returning: false)
            return
        }

        waiters.append(Waiter(id: id, continuation: continuation))
    }

    private func cancel(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }

        var waiter = waiters.remove(at: index)
        guard case .waiting = waiter.state else { return }

        waiter.state = .cancelled
        waiter.continuation.resume(returning: false)
    }

    private func release() {
        while !waiters.isEmpty {
            var waiter = waiters.removeFirst()
            guard case .waiting = waiter.state else { continue }

            waiter.state = .granted
            waiter.continuation.resume(returning: true)
            return
        }

        busy = false
    }
}

// MARK: - Tier 2: Session / Branch Generation Gate

actor SessionGenerationGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
        var state: GateWaiterState = .waiting
    }

    private var activeKeys: Set<AgentExecutionKey> = []
    private var waiters: [AgentExecutionKey: [Waiter]] = [:]
    private var isShuttingDown = false
    private var drainContinuations: [CheckedContinuation<Void, Never>] = []

    func withExclusive<T: Sendable>(_ key: AgentExecutionKey, operation: @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()

        guard await acquire(key) else {
            throw CancellationError()
        }

        defer {
            release(key)
        }

        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire(_ key: AgentExecutionKey) async -> Bool {
        if isShuttingDown || Task.isCancelled {
            return false
        }

        if activeKeys.insert(key).inserted {
            return true
        }

        let waiterId = UUID()

        return await withTaskCancellationHandler(
            operation: {
                await withCheckedContinuation { continuation in
                    enqueue(id: waiterId, key: key, continuation: continuation)
                }
            },
            onCancel: {
                Task {
                    await self.cancel(id: waiterId, key: key)
                }
            }
        )
    }

    private func enqueue(id: UUID, key: AgentExecutionKey, continuation: CheckedContinuation<Bool, Never>) {
        if isShuttingDown || Task.isCancelled {
            continuation.resume(returning: false)
            return
        }

        waiters[key, default: []].append(
            Waiter(id: id, continuation: continuation)
        )
    }

    private func cancel(id: UUID, key: AgentExecutionKey) {
        guard var queue = waiters[key],
              let index = queue.firstIndex(where: { $0.id == id }) else {
            return
        }

        var waiter = queue.remove(at: index)

        if queue.isEmpty {
            waiters.removeValue(forKey: key)
        } else {
            waiters[key] = queue
        }

        guard case .waiting = waiter.state else { return }

        waiter.state = .cancelled
        waiter.continuation.resume(returning: false)
    }

    private func release(_ key: AgentExecutionKey) {
        if isShuttingDown {
            activeKeys.remove(key)
            notifyDrainIfNeeded()
            return
        }

        guard var queue = waiters[key], !queue.isEmpty else {
            activeKeys.remove(key)
            notifyDrainIfNeeded()
            return
        }

        while !queue.isEmpty {
            var waiter = queue.removeFirst()

            if queue.isEmpty {
                waiters.removeValue(forKey: key)
            } else {
                waiters[key] = queue
            }

            guard case .waiting = waiter.state else { continue }

            waiter.state = .granted
            activeKeys.insert(key)
            waiter.continuation.resume(returning: true)
            return
        }

        activeKeys.remove(key)
        notifyDrainIfNeeded()
    }

    func beginShutdown() {
        isShuttingDown = true

        for key in waiters.keys {
            guard let queue = waiters[key] else { continue }

            for var waiter in queue {
                guard case .waiting = waiter.state else { continue }

                waiter.state = .cancelled
                waiter.continuation.resume(returning: false)
            }
        }

        waiters.removeAll()
        notifyDrainIfNeeded()
    }

    func awaitDrain() async {
        if activeKeys.isEmpty {
            return
        }

        await withCheckedContinuation { continuation in
            if activeKeys.isEmpty {
                continuation.resume()
            } else {
                drainContinuations.append(continuation)
            }
        }
    }

    private func notifyDrainIfNeeded() {
        guard activeKeys.isEmpty, !drainContinuations.isEmpty else { return }

        let continuations = drainContinuations
        drainContinuations.removeAll()

        for continuation in continuations {
            continuation.resume()
        }
    }
}
