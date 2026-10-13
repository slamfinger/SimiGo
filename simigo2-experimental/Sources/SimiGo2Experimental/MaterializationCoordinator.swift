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
        let id = UUID()
    }

    private struct LeaseKey: Hashable {
        let key: String
        let generation: UUID?
        let id: UUID

        init(_ lease: Lease) {
            key = lease.key
            generation = lease.generation
            id = lease.id
        }
    }

    /// Internal generation representation avoids Optional<Optional<UUID>>;
    /// `.legacy` is the public nil generation used by old sidecars.
    private enum Generation: Hashable {
        case legacy
        case identified(UUID)
        case invalidated

        init(_ value: UUID?) {
            self = value.map(Self.identified) ?? .legacy
        }

        var publicValue: UUID? {
            switch self {
            case .legacy: return nil
            case .identified(let value): return value
            case .invalidated: return nil
            }
        }
    }

    private enum ExpectedGeneration {
        case any
        case exact(Generation)
    }

    private let lock = NSCondition()
    private var counts: [LeaseKey: Int] = [:]
    private var generations: [String: Generation] = [:]
    private var pendingDeletes: [String: [Generation]] = [:]
    private var deleting: [String: Generation] = [:]
    private var preparing: Set<String> = []
    private var deleteFailures: [String: [Error]] = [:]
    private var publicationFailures: [String: [Error]] = [:]
    private let publicationLock = NSLock()
    private let onDelete: (String, UUID?) throws -> Void

    /// A publication was left intentionally unusable because rollback failed.
    public struct PublicationQuarantinedError: Error {
        public let key: String
        public let generation: UUID?
        public let underlyingError: Error
    }

    /// `onDelete(key, generation)` performs physical deletion for one
    /// artifact generation. Called synchronously; must not re-enter the
    /// registry. Failures are retained by `takeDeleteFailures(_:)`.
    public init(onDelete: @escaping (String, UUID?) throws -> Void) {
        self.onDelete = onDelete
    }

    /// Publish a replacement generation while leases remain rejected until
    /// `publish` commits. `publish` must serialize against the delete sink's
    /// file I/O and validate the on-disk generation before unlinking.
    public func beginGeneration(
        _ key: String, generation: UUID?, publish: () throws -> Void
    ) rethrows {
        _ = try beginGenerationTransaction(
            key, generation: generation, expected: .any, publish: publish)
    }

    /// Rescan competes with live exports after reading a sidecar. Accept the
    /// publication only when the scanned generation is still current, or when
    /// the path is first registered. A stale scan must not roll back a newer
    /// publication.
    func beginGenerationIfCurrentOrUnregistered(
        _ key: String, generation: UUID?, publish: () throws -> Void
    ) rethrows -> Bool {
        try beginGenerationTransaction(
            key,
            generation: generation,
            expected: .exact(Generation(generation)),
            publish: publish)
    }

    private func beginGenerationTransaction(
        _ key: String,
        generation: UUID?,
        expected: ExpectedGeneration,
        publish: () throws -> Void
    ) rethrows -> Bool {
        // ponytail: one global publication lock; split per-path only after a
        // measured same-path export bottleneck.
        publicationLock.lock()
        defer { publicationLock.unlock() }
        let generation = Generation(generation)
        let previous = currentGenerationInternal(key)
        lock.lock()
        let current = generations[key] ?? .legacy
        switch expected {
        case .any:
            break
        case .exact(let scanned):
            // An unregistered path has the implicit legacy current. This also
            // lets the first rescan of a newly generated sidecar succeed.
            guard activeDeleteLocked(key) == nil,
                !hasPendingDeleteLocked(key, generation: current),
                current == scanned || (current == .legacy && scanned != .legacy)
            else {
                lock.unlock()
                return false
            }
        }
        generations[key] = generation
        preparing.insert(key)
        // Drain all existing leases for this path before publishing the new
        // physical pair. New admission is already closed by `preparing`.
        while hasInFlightLocked(key) { lock.wait() }
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
            if generations[key] == .invalidated || error is PublicationQuarantinedError {
                generations[key] = .invalidated
                publicationFailures[key, default: []].append(error)
            } else {
                generations[key] = previous
            }
            lock.unlock()
            throw error
        }
        return true
    }

    /// Admit one physical use of the current generation. A nil result means
    /// no work may be published: a delete is registered/executing or a
    /// replacement is being published.
    @discardableResult
    public func acquire(_ key: String) -> Lease? {
        lock.lock()
        defer { lock.unlock() }
        let generation = (generations[key] ?? .legacy)
        guard !preparing.contains(key), activeDeleteLocked(key) == nil,
            !hasPendingDeleteLocked(key, generation: generation),
            generation != .invalidated
        else {
            return nil
        }
        let publicGeneration = generation.publicValue
        let lease = Lease(key: key, generation: publicGeneration)
        counts[LeaseKey(lease), default: 0] += 1
        return lease
    }

    /// Release one generation-bound physical use. When no generation for the
    /// path remains in flight, the next valid deferred delete may execute.
    public func release(_ lease: Lease) {
        lock.lock()
        let leaseKey = LeaseKey(lease)
        guard let remaining = counts[leaseKey].map({ $0 - 1 }) else {
            lock.unlock()
            return
        }
        if remaining <= 0 {
            counts[leaseKey] = nil
            lock.signal()
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
    /// Immediate failures are retained for `takeDeleteFailures(_:)` and also
    /// returned to callers that can surface them directly.
    @discardableResult
    public func requestDelete(_ key: String, generation: UUID?) -> Error? {
        let generation = Generation(generation)
        lock.lock()
        let current = generations[key] ?? .legacy
        // While publication is preparing, the previous generation is still a
        // valid rollback target. Queue the request; it becomes stale only if
        // publication succeeds.
        guard generation == current || preparing.contains(key) else {
            lock.unlock()
            return nil
        }
        var queue = pendingDeletes[key] ?? []
        if activeDeleteLocked(key) != generation, !queue.contains(generation) {
            queue.append(generation)
        }
        pendingDeletes[key] = queue
        let started = startNextDeleteIfIdleLocked(key)
        lock.unlock()
        guard let generation = started else { return nil }
        do {
            try onDelete(key, generation.publicValue)
        } catch {
            lock.lock()
            deleteFailures[key, default: []].append(error)
            if deleting[key] == generation { deleting[key] = nil }
            lock.unlock()
            startNextDeleteIfIdle(key)
            return error
        }
        lock.lock()
        if deleting[key] == generation { deleting[key] = nil }
        lock.unlock()
        startNextDeleteIfIdle(key)
        return nil
    }

    public func physicalUseCount(_ key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts.reduce(0) { $1.key.key == key ? $0 + $1.value : $0 }
    }

    func isPreparingGeneration(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return preparing.contains(key)
    }

    func inFlightLeaseCount(_ key: String) -> Int {
        physicalUseCount(key)
    }

    /// Consume at-most-once deletion failures for `key`. Admission is already
    /// restored when these are returned; the caller decides whether to retry.
    public func takeDeleteFailures(_ key: String) -> [Error] {
        lock.lock()
        defer { lock.unlock() }
        return deleteFailures.removeValue(forKey: key) ?? []
    }

    /// True when rollback failed and the path was deliberately quarantined.
    public func isGenerationInvalidated(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generations[key] == .invalidated
    }

    /// Consume quarantined-publication failures for `key`.
    public func takePublicationFailures(_ key: String) -> [Error] {
        lock.lock()
        defer { lock.unlock() }
        return publicationFailures.removeValue(forKey: key) ?? []
    }

    /// Mark a generation unusable after failed publication rollback. The
    /// caller throws a `PublicationQuarantinedError`; `beginGeneration`
    /// records that canonical failure exactly once.
    func markGenerationQuarantined(_ key: String, generation: UUID?) {
        lock.lock()
        generations[key] = .invalidated
        lock.unlock()
    }

    private func currentGenerationInternal(_ key: String) -> Generation {
        lock.lock()
        defer { lock.unlock() }
        return generations[key] ?? .legacy
    }

    private func hasInFlightLocked(_ key: String) -> Bool {
        counts.contains { $0.key.key == key && $0.value > 0 }
    }

    private func hasPendingDeleteLocked(
        _ key: String, generation: Generation
    ) -> Bool {
        pendingDeletes[key]?.contains(generation) == true
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
        do {
            try onDelete(key, generation.publicValue)
        } catch {
            lock.lock()
            deleteFailures[key, default: []].append(error)
            if deleting[key] == generation { deleting[key] = nil }
            lock.unlock()
            startNextDeleteIfIdle(key)
            return
        }
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
