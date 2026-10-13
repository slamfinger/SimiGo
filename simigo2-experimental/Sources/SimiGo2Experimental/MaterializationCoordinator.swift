import Foundation

/// PhysicalUseRegistry (F3 Coordinator Skeleton, IMPLEMENTATION_PLANNING
/// Q1) — transient in-flight physical-operation protection.
///
/// D-I4: this counts PHYSICAL OPERATIONS in flight, never Execution
/// Bindings (BindingCount ≠ PhysicalUseCount). D-C2: a deletion request
/// while count > 0 is DEFERRED, not dropped — eviction delayed ≠
/// artifact pinned. P2 continuity: the onDelete sink is the store's
/// artifact deletion (the same deletion the eviction path always
/// performed, now gated).
public final class PhysicalUseRegistry: @unchecked Sendable {
    public struct Lease: Equatable, Sendable {
        public let key: String
        public let generation: UUID?
    }

    private struct LeaseKey: Hashable {
        let key: String
        let generation: UUID?
    }

    /// Internal generation representation avoids Optional<Optional<UUID>>;
    /// `.legacy` is the public nil generation used by old sidecars.
    private enum Generation: Hashable {
        case legacy
        case identified(UUID)

        init(_ value: UUID?) {
            self = value.map(Self.identified) ?? .legacy
        }

        var publicValue: UUID? {
            switch self {
            case .legacy: return nil
            case .identified(let value): return value
            }
        }
    }

    private let lock = NSLock()
    private var counts: [LeaseKey: Int] = [:]
    private var generations: [String: Generation] = [:]
    private var pendingDeletes: [String: [Generation]] = [:]
    private var deleting: [String: Generation] = [:]
    private var preparing: Set<String> = []
    private let onDelete: (String, UUID?) -> Void

    /// `onDelete(key, generation)` performs physical deletion for one
    /// artifact generation. Called synchronously; must not re-enter the
    /// registry.
    public init(onDelete: @escaping (String, UUID?) -> Void) {
        self.onDelete = onDelete
    }

    /// Publish a replacement generation while leases remain rejected until
    /// `publish` commits. `publish` must serialize against the delete sink's
    /// file I/O and validate the on-disk generation before unlinking.
    public func beginGeneration(
        _ key: String, generation: UUID?, publish: () throws -> Void
    ) rethrows {
        let generation = Generation(generation)
        let previous = currentGenerationInternal(key)
        lock.lock()
        generations[key] = generation
        preparing.insert(key)
        lock.unlock()
        defer {
            lock.lock()
            preparing.remove(key)
            lock.unlock()
            startNextDeleteIfIdle(key)
        }
        do {
            try publish()
        } catch {
            lock.lock()
            generations[key] = previous
            lock.unlock()
            throw error
        }
    }

    /// Admit one physical use of the current generation. A nil result means
    /// no work may be published: a delete is registered/executing or a
    /// replacement is being published.
    @discardableResult
    public func acquire(_ key: String) -> Lease? {
        lock.lock()
        defer { lock.unlock() }
        guard !preparing.contains(key), activeDeleteLocked(key) == nil else { return nil }
        let generation = (generations[key] ?? .legacy).publicValue
        counts[LeaseKey(key: key, generation: generation), default: 0] += 1
        return Lease(key: key, generation: generation)
    }

    /// Release one generation-bound physical use. When no generation for the
    /// path remains in flight, the next valid deferred delete may execute.
    public func release(_ lease: Lease) {
        lock.lock()
        let leaseKey = LeaseKey(key: lease.key, generation: lease.generation)
        let remaining = (counts[leaseKey] ?? 1) - 1
        if remaining <= 0 {
            counts[leaseKey] = nil
            lock.unlock()
            startNextDeleteIfIdle(lease.key)
        } else {
            counts[leaseKey] = remaining
            lock.unlock()
        }
    }

    /// Request deletion of the current generation. A stale-generation request
    /// is dropped; live-generation requests dedupe and execute only after all
    /// leases and any prior delete have finished.
    public func requestDelete(_ key: String, generation: UUID?) {
        let generation = Generation(generation)
        lock.lock()
        guard generation == (generations[key] ?? .legacy) else {
            lock.unlock()
            return
        }
        var queue = pendingDeletes[key] ?? []
        if activeDeleteLocked(key) != generation, !queue.contains(generation) {
            queue.append(generation)
        }
        pendingDeletes[key] = queue
        let started = startNextDeleteIfIdleLocked(key)
        lock.unlock()
        if let generation = started { finishDelete(key, generation) }
    }

    public func physicalUseCount(_ key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts.reduce(0) { $1.key.key == key ? $0 + $1.value : $0 }
    }

    private func currentGeneration(_ key: String) -> UUID? {
        currentGenerationInternal(key).publicValue
    }

    private func currentGenerationInternal(_ key: String) -> Generation {
        lock.lock()
        defer { lock.unlock() }
        return generations[key] ?? .legacy
    }

    private func hasInFlightLocked(_ key: String) -> Bool {
        counts.contains { $0.key.key == key && $0.value > 0 }
    }

    private func activeDeleteLocked(_ key: String) -> Generation? {
        deleting[key]
    }

    /// Caller holds `lock`. Pops stale entries and marks the first live
    /// generation as deleting without ever reopening admission in between.
    private func startNextDeleteIfIdleLocked(_ key: String) -> Generation? {
        guard !preparing.contains(key), activeDeleteLocked(key) == nil, !hasInFlightLocked(key) else {
            return nil
        }
        while var queue = pendingDeletes[key], !queue.isEmpty {
            let generation = queue.removeFirst()
            if queue.isEmpty {
                pendingDeletes[key] = nil
            } else {
                pendingDeletes[key] = queue
            }
            if generation == (generations[key] ?? .legacy) {
                deleting[key] = .some(generation)
                return generation
            }
        }
        return nil
    }

    private func startNextDeleteIfIdle(_ key: String) {
        lock.lock()
        let generation = startNextDeleteIfIdleLocked(key)
        lock.unlock()
        if let generation { finishDelete(key, generation) }
    }

    /// `onDelete` runs outside the registry lock. `deleting` closes the
    /// execution window, and the next live generation can be selected only
    /// atomically after callback cleanup.
    private func finishDelete(_ key: String, _ generation: Generation) {
        onDelete(key, generation.publicValue)
        lock.lock()
        if deleting[key] == generation { deleting[key] = nil }
        lock.unlock()
        startNextDeleteIfIdle(key)
    }
}

/// MaterializationCoordinator (F3 Coordinator Skeleton, IMPLEMENTATION_
/// PLANNING Q2) — Ref-scoped single-flight materialization.
///
/// D-C4/D-C5: one in-flight `MaterializationWork` per canonical
/// RepresentationRef key — joiners await the SAME task; the WORK owns
/// the PhysicalUseHandle for its whole lifetime (acquire before the
/// first byte of work, release after the last — joiners and async
/// lifecycles can never escape protection, D-C6 race). Success does NOT
/// imply any Execution attachment: callers run their own commit
/// boundaries (D-C5). Failure changes Representation Availability only —
/// Bindings are untouched (D-C7).
public final class MaterializationCoordinator<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight: [String: Task<Value, Error>] = [:]
    private let physicalUse: PhysicalUseRegistry
    private var joinObserver: (@Sendable (String) async -> Void)?
    /// Test/observability seam (D-I4 startup-window regression): invoked
    /// synchronously under the coordinator lock immediately AFTER the
    /// single-flight task is published and its physical-use lease is
    /// acquired — exactly the window whose race this class closes. Must not
    /// re-enter the coordinator.
    private var startupObserver: (@Sendable (String) -> Void)?
    private var leaseRejectionObserver: (@Sendable (String) -> Void)?

    public init(physicalUse: PhysicalUseRegistry) {
        self.physicalUse = physicalUse
    }

    /// Single-flight materialization for `key`. Concurrent calls for the
    /// same key share one work task (one underlying load). The work runs
    /// under a transient physical-use protection acquired and released
    /// by the coordinator — NOT by callers.
    ///
    /// D-I4 startup-window fix: the lease is acquired SYNCHRONOUSLY under
    /// the same lock that publishes the single-flight task. Once
    /// `inFlight[key]` is visible to any caller, the physical-use count is
    /// already ≥ 1 — an eviction-side `requestDelete(key)` in the former
    /// window (registered but not yet protected) now DEFERS instead of
    /// racing the work's startup. Lock order is always
    /// coordinator.lock → registry.lock; the registry never calls back into
    /// the coordinator (its `onDelete` sink runs after its own unlock), so
    /// no lock cycle exists.
    public func materialize(
        key: String, work: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let start = lock.withLock { () -> (existing: Task<Value, Error>?, created: Task<Value, Error>?) in
            if let existing = inFlight[key] { return (existing, nil) }
            // Startup-window fix (D-I4): acquire BEFORE publication.
            guard let lease = physicalUse.acquire(key) else {
                leaseRejectionObserver?(key)
                return (nil, nil)
            }
            let physicalUse = self.physicalUse
            let created = Task<Value, Error> {
                defer { physicalUse.release(lease) }
                return try await work()
            }
            inFlight[key] = created
            startupObserver?(key)
            return (nil, created)
        }
        if start.existing == nil && start.created == nil {
            throw MaterializationCoordinatorError.physicalUseUnavailable(key)
        }
        if let task = start.existing {
            await notifyJoin(key: key)
            return try await task.value
        }
        guard let task = start.created else { fatalError("unreachable materialization state") }
        defer {
            lock.withLock { inFlight[key] = nil }
        }
        return try await task.value
    }

    /// Test/observability surface: is a work for `key` currently in
    /// flight?
    public func isInFlight(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return inFlight[key] != nil
    }

    /// Test observation boundary for an actual single-flight join. The event
    /// is emitted after the lock is released and never inside critical state.
    func setJoinObserver(_ observer: (@Sendable (String) async -> Void)?) {
        lock.withLock { joinObserver = observer }
    }

    /// Test observation boundary for the D-I4 startup window: invoked
    /// synchronously under the coordinator lock right after the lease is
    /// acquired and the task published. Observers see the protected window
    /// deterministically (use count ≥ 1, work not yet started) and may call
    /// `PhysicalUseRegistry.requestDelete` to pin the deferred-delete
    /// interleaving. Must not re-enter the coordinator.
    func setStartupObserver(_ observer: (@Sendable (String) -> Void)?) {
        lock.withLock { startupObserver = observer }
    }

    /// Test observation boundary for a rejected startup lease. Invoked under
    /// the coordinator lock after registry admission returns false; observers
    /// must not re-enter either lock.
    func setLeaseRejectionObserver(_ observer: (@Sendable (String) -> Void)?) {
        lock.withLock { leaseRejectionObserver = observer }
    }

    private func notifyJoin(key: String) async {
        let observer = lock.withLock { joinObserver }
        await observer?(key)
    }
}

public enum MaterializationCoordinatorError: Error, Equatable {
    /// The physical-use lease was rejected because a delete for `key` was
    /// registered and had not completed. No single-flight task was published.
    case physicalUseUnavailable(String)
}
