import Foundation

/// Form ② compactor producer — DECOUPLED from the rendering policy
/// (`HTTPServer.digestSubstitutedMessages`) and from the engine/KV handling.
/// Pure function: settled digests in, one bounded brief string out. Swap the
/// producer here for a model-synthesized judgment brief (quality upgrade)
/// without touching the rendering gate, the ledger, or KV handling.
/// ADR_TOKEN_PREFIX_REUSE_20261122 · model-agnostic · research arm.
enum DigestPrefixCompaction {
    /// TRIGGER policy (owner 2026-11-22): the brief is the cold-rebuild point,
    /// so compact at checkpoints — NOT every turn. Pure function of the raw
    /// turn sizes + thresholds => deterministic and cross-process reproducible
    /// (no mutable boundary state). Walks the eligible turns placing a
    /// checkpoint whenever accumulated raw chars reach `triggerChars` OR turns
    /// reach `triggerTurns` (first to hit); returns the LAST checkpoint index B
    /// (0 = none yet). Between checkpoints B is fixed and the raw tail appends
    /// => the engine message-prefix gate passes (append-only reuse); at a
    /// checkpoint B jumps and the bounded brief prefix cold-rebuilds once,
    /// amortized over the interval. The checkpoint size is the turn/token
    /// choice derived from the h100 minimum cold-fill rate (~1100 tok/s clean,
    /// turn1 2303tok/2.1s) so the inter-checkpoint prefix's predicted cold
    /// prefill stays under a deadline; failure/coverage gap stays fail-open.
    /// A threshold <= 0 disables that trigger; both <= 0 => never compact.
    static func boundary(
        rawTurnChars: [Int], triggerChars: Int, triggerTurns: Int
    ) -> Int {
        guard triggerChars > 0 || triggerTurns > 0 else { return 0 }
        var last = 0, chars = 0, turns = 0
        for (i, size) in rawTurnChars.enumerated() {
            chars += size
            turns += 1
            if (triggerChars > 0 && chars >= triggerChars)
                || (triggerTurns > 0 && turns >= triggerTurns) {
                last = i + 1
                chars = 0
                turns = 0
            }
        }
        return last
    }

    /// ponytail: deterministic extractive compactor — join old digests, hard-cap
    /// to a char budget. Bounds the prefix regardless of depth; lossy on old
    /// prose (precise facts ride IS retrieval blocks, not the digest chain —
    /// h100 normal 27/29, the 2 lost keys were a retrieval gap). A synthesized
    /// brief producer is the quality arm; this mechanical cap validates the
    /// bounded-cold-prefill mechanics first (owner alleviation bar).
    static func brief(
        _ digests: [(turnIndex: Int, digest: String)], budgetChars: Int
    ) -> String {
        let joined = digests
            .map { "t\($0.turnIndex): \($0.digest)" }
            .joined(separator: "\n")
        guard joined.count > budgetChars, budgetChars > 0 else { return joined }
        return String(joined.prefix(budgetChars)) + "…"
    }
}
