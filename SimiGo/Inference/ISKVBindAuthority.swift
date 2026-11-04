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
/// * bounded, so an abandoned request cannot grow the map;
/// * it carries ONLY the recorded digests, never the prefix itself. The final
///   safety boundary is not this map: the bind site recomputes the pool entry's
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

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var sequence = 0
    private var insertionOrder: [String] = []

    private init() {}

    /// Register the authority for the child ES this request is executing under.
    /// Re-registering the same id replaces the verdict and moves it to the young
    /// end of the eviction order.
    func register(esStateID: String, verdict: Verdict) {
        lock.lock()
        defer { lock.unlock() }
        sequence += 1
        if entries[esStateID] == nil {
            insertionOrder.append(esStateID)
        } else {
            insertionOrder.removeAll { $0 == esStateID }
            insertionOrder.append(esStateID)
        }
        entries[esStateID] = Entry(verdict: verdict, sequence: sequence)
        while insertionOrder.count > Self.capacity {
            let oldest = insertionOrder.removeFirst()
            entries[oldest] = nil
        }
    }

    /// Read and retire the authority for one ES. The bind site calls this on
    /// every governed attempt, so a grant is spent whether it ends in a bind or
    /// a rejection.
    func consume(esStateID: String) -> Lookup {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries.removeValue(forKey: esStateID) else {
            return .notGoverned
        }
        insertionOrder.removeAll { $0 == esStateID }
        return .verdict(entry.verdict)
    }

    func peek(esStateID: String) -> Lookup {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[esStateID] else { return .notGoverned }
        return .verdict(entry.verdict)
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
    }
}
