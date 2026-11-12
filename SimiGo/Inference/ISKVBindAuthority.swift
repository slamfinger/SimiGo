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
/// * alive for exactly as long as the request that registered it. The protocol
///   layer releases the grant in `ConnectionContext.finishLifecycle` — the same
///   funnel every endpoint already runs at completion, failure and cancellation
///   — so the table's size is the number of in-flight governed requests, not a
///   policy choice. An earlier revision capped live grants at 64 and remembered
///   evicted ids in a bounded tombstone ring; that ring could be walked past by
///   unrelated registrations while a long request was still streaming, which
///   downgraded a governed continuation to an ordinary turn. Lifetime ownership
///   removes the window instead of widening it, so nothing here is evicted;
///   `release` is the only way an unspent grant leaves the table;
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

    private let lock = NSLock()
    private var entries: [String: Verdict] = [:]

    private init() {}

    /// Register the authority for the child ES this request is executing under.
    /// Re-registering the same id replaces the verdict.
    func register(esStateID: String, verdict: Verdict) {
        lock.lock()
        defer { lock.unlock() }
        entries[esStateID] = verdict
    }

    /// Read and retire the authority for one ES. The bind site calls this on
    /// every governed attempt, so a grant is spent whether it ends in a bind or
    /// a rejection.
    func consume(esStateID: String) -> Lookup {
        lock.lock()
        defer { lock.unlock() }
        if let verdict = entries.removeValue(forKey: esStateID) { return .verdict(verdict) }
        return .notGoverned
    }

    func peek(esStateID: String) -> Lookup {
        lock.lock()
        defer { lock.unlock() }
        if let verdict = entries[esStateID] { return .verdict(verdict) }
        return .notGoverned
    }

    /// The request that registered this grant has ended (completed, failed or
    /// was cancelled). Anything the bind site did not consume is dropped here:
    /// a finished request cannot be governed again, so "no entry" is the true
    /// answer, not a downgrade.
    func release(esStateID: String) {
        lock.lock()
        defer { lock.unlock() }
        entries[esStateID] = nil
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
    }
}
