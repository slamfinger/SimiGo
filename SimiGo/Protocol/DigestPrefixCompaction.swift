import Foundation

/// Form ② compactor producer — DECOUPLED from the rendering policy
/// (`HTTPServer.digestSubstitutedMessages`) and from the engine/KV handling.
/// Pure function: settled digests in, one bounded brief string out. Swap the
/// producer here for a model-synthesized judgment brief (quality upgrade)
/// without touching the rendering gate, the ledger, or KV handling.
/// ADR_TOKEN_PREFIX_REUSE_20261122 · model-agnostic · research arm.
enum DigestPrefixCompaction {
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
