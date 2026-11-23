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
    /// to a char budget. Bounds the prefix regardless of depth.
    ///
    /// KEY-ANCHORED (owner 2026-11-23): the old prefix-only truncation kept the
    /// first ~budget chars (≈t1–t5) and DROPPED every later digest entirely, so
    /// late-turn precise keys vanished from the rendered prefix (perf-full normal
    /// needle 7/29 ≪ 27/29 bar; the IS block channel is a line-granularity lexical
    /// echo carrying only 4/29 keys, and the model filled gaps with standard
    /// defaults). The digest chain itself carries 24/29 keys verbatim. Fix: when
    /// truncation would drop digests, first preserve the verbatim fact tokens
    /// (codes / grades / numbers+unit) from ALL digests as a key anchor, then fill
    /// the remaining budget with the narrative prefix. Precise facts ride the
    /// anchor (never truncated); only narrative prose is lossy. This restores the
    /// digest chain's own key-retention floor instead of the prefix-drop floor.
    /// A model-synthesized judgment brief remains the quality upgrade arm.
    static func brief(
        _ digests: [(turnIndex: Int, digest: String)], budgetChars: Int
    ) -> String {
        let joined = digests
            .map { "t\($0.turnIndex): \($0.digest)" }
            .joined(separator: "\n")
        guard joined.count > budgetChars, budgetChars > 0 else { return joined }
        let anchor = factAnchor(digests.map { $0.digest })
        let anchorLine = anchor.isEmpty ? "" : "事实锚点（逐字保留）：\(anchor)\n"
        // Facts ride the anchor first (never dropped for narrative), but the
        // anchor itself stays within budget so the prefix bound holds even in
        // the degenerate many-facts case. Normal corpus: ~24 keys ≈ 500 chars
        // fits the 1500 default with room for narrative context.
        let boundedAnchor = anchorLine.count > budgetChars
            ? String(anchorLine.prefix(budgetChars)) : anchorLine
        let narrativeBudget = max(0, budgetChars - boundedAnchor.count)
        let narrative = narrativeBudget == 0
            ? "" : String(joined.prefix(narrativeBudget)) + "…"
        return boundedAnchor + narrative
    }

    /// Verbatim fact tokens from all digests, deduped, first-occurrence order.
    /// Captures the precise-fact shapes the digest chain carries: dashed codes
    /// (X-9942 / SDJZ-2026-018 / JL-3105 / QC-2027-103), letter grades (C45),
    /// numbers with units (155℃ / 98% / 0.5mm / 5.5% / 850天) and bare numbers
    /// (3880 / 850). Validated on the perf-full 100-digest corpus: preserves
    /// 24/29 needle keys (the 5 misses are digest-production losses, absent from
    /// the digests themselves — a separate D-plane issue, not compaction).
    /// ponytail: NSRegularExpression (stdlib), no new dependency; narrative prose
    /// (Chinese) carries no digit/uppercase-code run so it is not captured.
    private static let factPattern = try! NSRegularExpression(
        pattern: "[A-Za-z]+-[A-Za-z0-9][A-Za-z0-9-]*"
            + "|[A-Za-z]+\\d+[A-Za-z0-9-]*"
            + "|\\d+(?:\\.\\d+)?(?:%|℃|mm|万元|天|米|吨|公里|项|卷)?")

    private static func factAnchor(_ texts: [String]) -> String {
        var seen = Set<String>()
        var facts: [String] = []
        for text in texts {
            let range = NSRange(text.startIndex..., in: text)
            for match in factPattern.matches(in: text, range: range) {
                guard let r = Range(match.range, in: text) else { continue }
                let token = String(text[r])
                if seen.insert(token).inserted { facts.append(token) }
            }
        }
        return facts.joined(separator: "、")
    }
}
