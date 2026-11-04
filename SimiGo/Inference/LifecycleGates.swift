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

    func withExclusive<T: Sendable>(
        _ key: AgentExecutionKey,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        try await withExclusive([key], operation: operation)
    }

    /// Acquires a deterministic ordered set of execution keys for a multi-branch
    /// transaction. Fork needs source + target (and, when enabled, the same global
    /// generation key used by generate) so neither side can advance while the
    /// checkpoint pair is being copied and restored.
    func withExclusive<T: Sendable>(
        _ keys: [AgentExecutionKey],
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        let ordered = Array(Set(keys)).sorted { $0.storageKey < $1.storageKey }
        try Task.checkCancellation()

        var acquired: [AgentExecutionKey] = []
        acquired.reserveCapacity(ordered.count)

        do {
            for key in ordered {
                guard await acquire(key) else {
                    throw CancellationError()
                }
                acquired.append(key)
            }

            try Task.checkCancellation()
            let result = try await operation()
            for held in acquired.reversed() { release(held) }
            return result
        } catch {
            for held in acquired.reversed() { release(held) }
            throw error
        }
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

// MARK: - Route 04: bounded request admission

/// Bounds how many requests may sit inside the generation window at once.
///
/// This is deliberately a REQUEST-level limit. It does not grant concurrent
/// access to the mutable MLX session/KV state: generation itself is still
/// ordered by `SessionGenerationGate` (global single-flight under
/// `RuntimeTuning.serializeGeneration`). Level 1/2/4 answers "how many turns
/// may be in flight"; the engine safety boundary answers "how many may
/// execute". Keeping them separate means raising the level cannot silently
/// turn into concurrent model mutation.
///
/// The queue is bounded. A saturated queue is refused (HTTP 503) instead of
/// growing without limit, so a disconnect storm or a misbehaving agent cannot
/// park an unbounded number of prefill-intent requests on the runtime.
///
/// Ownership is explicit: `release` only accepts the exact ticket issued to
/// that request, so a late or duplicated release can never free a slot that
/// belongs to another turn.
public final class RequestAdmissionScheduler: @unchecked Sendable {
    struct Ticket: Hashable, Sendable {
        let requestId: String
        let sequence: UInt64
    }

    enum AcquireResult: Sendable {
        case admitted(Ticket)
        case queueFull
        case cancelled
        case shuttingDown
    }

    struct Snapshot: Sendable, Equatable {
        let capacity: Int
        let queueCapacity: Int
        let active: Int
        let waiting: Int
        let shuttingDown: Bool
    }

    private final class Waiter: @unchecked Sendable {
        enum State {
            case waiting
            case granted
            case cancelled
        }

        let requestId: String
        let sequence: UInt64
        var state: State = .waiting
        var continuation: CheckedContinuation<AcquireResult, Never>?

        init(requestId: String, sequence: UInt64) {
            self.requestId = requestId
            self.sequence = sequence
        }
    }

    let capacity: Int
    let queueCapacity: Int

    private let lock = NSLock()
    private var activeTickets: Set<Ticket> = []
    private var waiters: [Waiter] = []
    private var nextSequence: UInt64 = 0
    private var isShuttingDown = false

    init(limit: Int, queueCapacity: Int? = nil) {
        precondition(limit > 0, "request admission limit must be positive")
        self.capacity = limit
        // Local single-user deployment: the queue exists to absorb a small
        // burst, not to buffer arbitrary load. Scale with the level so the
        // larger level really admits a larger working set.
        self.queueCapacity = queueCapacity ?? max(4, limit * 4)
    }

    func acquire(requestId: String) async -> AcquireResult {
        if Task.isCancelled {
            return .cancelled
        }

        let waiter = Waiter(requestId: requestId, sequence: allocateSequence())

        let result = await withTaskCancellationHandler(
            operation: {
                await withCheckedContinuation { continuation in
                    admitOrEnqueue(waiter, continuation: continuation)
                }
            },
            onCancel: {
                self.cancel(waiter)
            }
        )

        // A task cancelled after being granted must not hold a slot it will
        // never use: return it before surfacing the cancellation.
        if Task.isCancelled, case .admitted(let ticket) = result {
            release(ticket)
            return .cancelled
        }

        return result
    }

    func release(_ ticket: Ticket) {
        var granted: (waiter: Waiter, continuation: CheckedContinuation<AcquireResult, Never>)?

        lock.lock()
        guard activeTickets.remove(ticket) != nil else {
            lock.unlock()
            return
        }

        while !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            guard waiter.state == .waiting, let continuation = waiter.continuation else {
                continue
            }

            waiter.state = .granted
            waiter.continuation = nil
            let next = Ticket(requestId: waiter.requestId, sequence: waiter.sequence)
            activeTickets.insert(next)
            granted = (waiter, continuation)
            break
        }
        lock.unlock()

        if let granted {
            granted.continuation.resume(
                returning: .admitted(
                    Ticket(
                        requestId: granted.waiter.requestId,
                        sequence: granted.waiter.sequence)))
        }
    }

    func beginShutdown() {
        var toResume: [CheckedContinuation<AcquireResult, Never>] = []

        lock.lock()
        isShuttingDown = true
        for waiter in waiters {
            guard waiter.state == .waiting, let continuation = waiter.continuation else {
                continue
            }
            waiter.state = .cancelled
            waiter.continuation = nil
            toResume.append(continuation)
        }
        waiters.removeAll()
        lock.unlock()

        for continuation in toResume {
            continuation.resume(returning: .shuttingDown)
        }
    }

    func debugSnapshot() -> Snapshot {
        lock.withLock {
            Snapshot(
                capacity: capacity,
                queueCapacity: queueCapacity,
                active: activeTickets.count,
                waiting: waiters.count,
                shuttingDown: isShuttingDown)
        }
    }

    private func allocateSequence() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let sequence = nextSequence
        nextSequence += 1
        return sequence
    }

    private func admitOrEnqueue(
        _ waiter: Waiter,
        continuation: CheckedContinuation<AcquireResult, Never>
    ) {
        lock.lock()

        if isShuttingDown {
            lock.unlock()
            continuation.resume(returning: .shuttingDown)
            return
        }

        // The cancellation handler may have run before this continuation was
        // installed. In that case the waiter is already cancelled and must not
        // enter the queue.
        if waiter.state == .cancelled || Task.isCancelled {
            waiter.state = .cancelled
            lock.unlock()
            continuation.resume(returning: .cancelled)
            return
        }

        if activeTickets.count < capacity, waiters.isEmpty {
            let ticket = Ticket(requestId: waiter.requestId, sequence: waiter.sequence)
            waiter.state = .granted
            activeTickets.insert(ticket)
            lock.unlock()
            continuation.resume(returning: .admitted(ticket))
            return
        }

        guard waiters.count < queueCapacity else {
            waiter.state = .cancelled
            lock.unlock()
            continuation.resume(returning: .queueFull)
            return
        }

        waiter.continuation = continuation
        waiters.append(waiter)
        lock.unlock()
    }

    private func cancel(_ waiter: Waiter) {
        var continuation: CheckedContinuation<AcquireResult, Never>?

        lock.lock()
        if waiter.state == .cancelled {
            lock.unlock()
            return
        }
        if waiter.state == .granted {
            // Grant won the race; the acquire caller observes cancellation and
            // releases the ticket itself.
            lock.unlock()
            return
        }

        if let index = waiters.firstIndex(where: { $0 === waiter }) {
            waiters.remove(at: index)
            waiter.state = .cancelled
            continuation = waiter.continuation
            waiter.continuation = nil
        } else {
            // Not enqueued yet: mark it so `admitOrEnqueue` refuses it.
            waiter.state = .cancelled
        }
        lock.unlock()

        continuation?.resume(returning: .cancelled)
    }
}
