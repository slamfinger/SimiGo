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
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var pendingDeletes: Set<String> = []
    private var deleting: Set<String> = []
    private let onDelete: (String) -> Void

    /// `onDelete(key)` performs the physical deletion for one artifact
    /// key. Called synchronously; must not re-enter the registry.
    public init(onDelete: @escaping (String) -> Void) {
        self.onDelete = onDelete
    }

    /// Admit one physical use of the artifact `key`. Admission fails while
    /// a delete for that key has been registered and its callback has not
    /// finished; the caller must not publish work against the old artifact.
    @discardableResult
    public func acquire(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !deleting.contains(key) else { return false }
        counts[key, default: 0] += 1
        return true
    }

    /// Release one physical use. When the count reaches zero, any
    /// deferred deletion fires.
    public func release(_ key: String) {
        lock.lock()
        let remaining = (counts[key] ?? 1) - 1
        if remaining <= 0 {
            counts[key] = nil
            let owed = pendingDeletes.remove(key) != nil
            if owed { deleting.insert(key) }
            lock.unlock()
            if owed { finishDelete(key) }
        } else {
            counts[key] = remaining
            lock.unlock()
        }
    }

    /// Eviction path (D-C2): request physical deletion. If uses are in
    /// flight the deletion is DEFERRED until the count reaches zero.
    public func requestDelete(_ key: String) {
        var deleteNow = false
        lock.lock()
        let inFlight = (counts[key] ?? 0) > 0
        if inFlight || deleting.contains(key) {
            pendingDeletes.insert(key)
        } else {
            deleting.insert(key)
            deleteNow = true
        }
        lock.unlock()
        if deleteNow { finishDelete(key) }
    }

    public func physicalUseCount(_ key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[key] ?? 0
    }

    /// `onDelete` must run outside the registry lock. `deleting` closes the
    /// decision/execution window against new admission; cleanup after the
    /// callback allows a later recreation of the same path.
    private func finishDelete(_ key: String) {
        onDelete(key)
        lock.lock()
        deleting.remove(key)
        // A request received while the callback ran addresses a later
        // incarnation of the reusable path; execute it before reopening
        // admission.
        let next = pendingDeletes.remove(key) != nil
        if next { deleting.insert(key) }
        lock.unlock()
        if next { finishDelete(key) }
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
            guard physicalUse.acquire(key) else {
                leaseRejectionObserver?(key)
                return (nil, nil)
            }
            let physicalUse = self.physicalUse
            let created = Task<Value, Error> {
                defer { physicalUse.release(key) }
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
