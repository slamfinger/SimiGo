import Foundation
import SimiGoRuntimeContract

/// Per-continuation KV bind authority.
///
/// A-2 makes the IS settlement the pre-condition for KV representation reuse:
/// the engine may only load a pooled prefix for a fresh Execution State when the
/// settlement that this continuation was admitted against recorded that exact
/// prefix boundary. This type is the transport for that decision — the protocol
/// layer (which runs the admission) registers it, the inference layer (which
/// owns the prefix pool) consumes it at the bind site.
///
/// Deliberately narrow:
/// * keyed by the child ES identity, which is the same string the generation
///   path uses as its `logicalBranchId` — no inference-side guessing;
/// * consumed exactly once, so a grant cannot leak into a later turn of a
///   different ES;
/// * bounded: live grants are capped at `capacity` (FIFO), and an evicted id is
///   remembered in a SEPARATE bounded tombstone ledger so a governed
///   continuation whose grant was dropped still fails closed at the bind site.
///   The ledger is itself capped (`tombstoneCapacity`); an id evicted from it
///   reverts to the ordinary ungoverned path — a request still in flight after
///   that many intervening registrations is treated as gone. Tombstones never
///   re-enter the live eviction queue, so neither structure grows without bound;
/// * it carries ONLY the recorded digests, never the prefix itself. For an
///   authorized grant the bind site additionally recomputes the pool entry's
///   content hash and compares it against the recorded digests, so a stale,
///   wrong, or absent entry still falls back to a cold prefill.
nonisolated final class ISKVBindAuthority: @unchecked Sendable {

    static let shared = ISKVBindAuthority()

    enum Verdict: Sendable, Equatable {
        /// The admission verified a settlement that recorded this prefix
        /// boundary. Carries the recorded `kv.*` digest rows for re-checking.
        case authorized([String: String])
        /// This ES runs under continuation semantics with no KV authority — the
        /// bind path must not load pooled state.
        case unauthorized(reason: String)
    }

    /// No entry means "not a governed continuation" (an ordinary turn), which is
    /// the pre-A-2 behaviour and must stay unchanged.
    enum Lookup: Sendable, Equatable {
        case notGoverned
        case verdict(Verdict)

        var isGoverned: Bool {
            if case .notGoverned = self { return false }
            return true
        }
    }

    private struct Entry: Sendable {
        let verdict: Verdict
        let sequence: Int
    }

    private static let capacity = 64
    /// Evicted-id ledger bound, kept equal to `capacity`: a small FIFO ring of
    /// recently evicted ids. An id pushed out of the ring is treated as an
    /// ordinary (ungoverned) turn again — a request still in flight after that
    /// many intervening registrations is treated as gone.
    private static let tombstoneCapacity = 64

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var sequence = 0
    private var insertionOrder: [String] = []
    private var tombstones: Set<String> = []
    private var tombstoneOrder: [String] = []

    private init() {}

    /// Register the authority for the child ES this request is executing under.
    /// Re-registering the same id replaces the verdict and moves it to the young
    /// end of the eviction order.
    func register(esStateID: String, verdict: Verdict) {
        lock.lock()
        defer { lock.unlock() }
        sequence += 1
        // Re-registration revives an id that was previously evicted.
        if tombstones.remove(esStateID) != nil {
            tombstoneOrder.removeAll { $0 == esStateID }
        }
        if entries[esStateID] == nil {
            insertionOrder.append(esStateID)
        } else {
            insertionOrder.removeAll { $0 == esStateID }
            insertionOrder.append(esStateID)
        }
        entries[esStateID] = Entry(verdict: verdict, sequence: sequence)
        // Evict the oldest LIVE grant into the tombstone ledger. The id leaves
        // the live queue for good (no re-append), so this loop shrinks the queue
        // and terminates; the grant stays fail-closed via the ledger.
        while insertionOrder.count > Self.capacity {
            let oldest = insertionOrder.removeFirst()
            entries[oldest] = nil
            tombstones.insert(oldest)
            tombstoneOrder.append(oldest)
        }
        while tombstoneOrder.count > Self.tombstoneCapacity {
            let dropped = tombstoneOrder.removeFirst()
            tombstones.remove(dropped)
        }
    }

    /// Read and retire the authority for one ES. The bind site calls this on
    /// every governed attempt, so a grant is spent whether it ends in a bind or
    /// a rejection.
    func consume(esStateID: String) -> Lookup {
        lock.lock()
        defer { lock.unlock() }
        if let entry = entries.removeValue(forKey: esStateID) {
            insertionOrder.removeAll { $0 == esStateID }
            return .verdict(entry.verdict)
        }
        if tombstones.remove(esStateID) != nil {
            tombstoneOrder.removeAll { $0 == esStateID }
            return .verdict(.unauthorized(reason: "kv_authority_evicted"))
        }
        return .notGoverned
    }

    func peek(esStateID: String) -> Lookup {
        lock.lock()
        defer { lock.unlock() }
        if let entry = entries[esStateID] { return .verdict(entry.verdict) }
        if tombstones.contains(esStateID) {
            return .verdict(.unauthorized(reason: "kv_authority_evicted"))
        }
        return .notGoverned
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        insertionOrder.removeAll()
        tombstones.removeAll()
        tombstoneOrder.removeAll()
    }
}
