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
    private let onDelete: (String) -> Void

    /// `onDelete(key)` performs the physical deletion for one artifact
    /// key. Called synchronously; must not re-enter the registry.
    public init(onDelete: @escaping (String) -> Void) {
        self.onDelete = onDelete
    }

    /// Acquire one physical use of the artifact `key`.
    public func acquire(_ key: String) {
        lock.lock()
        counts[key, default: 0] += 1
        lock.unlock()
    }

    /// Release one physical use. When the count reaches zero, any
    /// deferred deletion fires.
    public func release(_ key: String) {
        lock.lock()
        let remaining = (counts[key] ?? 1) - 1
        if remaining <= 0 {
            counts[key] = nil
            let owed = pendingDeletes.remove(key) != nil
            lock.unlock()
            if owed { onDelete(key) }
        } else {
            counts[key] = remaining
            lock.unlock()
        }
    }

    /// Eviction path (D-C2): request physical deletion. If uses are in
    /// flight the deletion is DEFERRED until the count reaches zero.
    public func requestDelete(_ key: String) {
        lock.lock()
        let inFlight = (counts[key] ?? 0) > 0
        if inFlight { pendingDeletes.insert(key) }
        lock.unlock()
        if !inFlight { onDelete(key) }
    }

    public func physicalUseCount(_ key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[key] ?? 0
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

    public init(physicalUse: PhysicalUseRegistry) {
        self.physicalUse = physicalUse
    }

    /// Single-flight materialization for `key`. Concurrent calls for the
    /// same key share one work task (one underlying load). The work runs
    /// under a transient physical-use protection acquired and released
    /// by the coordinator — NOT by callers.
    public func materialize(
        key: String, work: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let start = lock.withLock { () -> (existing: Task<Value, Error>?, created: Task<Value, Error>?) in
            if let existing = inFlight[key] { return (existing, nil) }
            let physicalUse = self.physicalUse
            let created = Task<Value, Error> {
                physicalUse.acquire(key)
                defer { physicalUse.release(key) }
                return try await work()
            }
            inFlight[key] = created
            return (nil, created)
        }
        if let task = start.existing {
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
}
