# B-6 — Token-Level Automatic Prefix Caching in ChatSession (fork) — Definition Draft

**Date**: 2026-09-27
**Status**: DEFINITION_DRAFT / AWAITING_REVIEW (fork core-path surgery —
implementation only on approval)
**Trigger**: real-device log 03:52–03:55 (session 081f70): new session,
same large system document, different first question → still cold 43s.
Message-boundary granularity (B-4) cannot serve this: the chain diverges
at message 2 while the SHARED TOKEN PREFIX (the document) is identical.

## 0. Second-layer finding (registered with the user's "not fully implemented")

```text
process started 02:18 (pre-pool binary) — the 03:52 session ran on it:
zero pool activity is expected there; beta.2 requires install + restart.
EVEN on beta.2: turn-commit boundaries are message-aligned; "same
document, different first question" diverges at message 2 → miss.
The user's dominant workload lives exactly in this gap.
```

## 1. Discovery

`ChatSession`'s internal `KVCacheStorage` already tracks
`Conversation.cachedTokens` — the rendered token stream per conversation.
The data substrate for token-level caching EXISTS in the fork; what is
missing is the consult/export seam.

## 2. Design (draft)

```text
match surface  FINAL RENDERED TOKEN IDS (not messages). Sound by
               construction: KV is causal, so KV[0..<T] depends only on
               tokens[0..<T]; if two requests share the first T rendered
               tokens, the stored KV is a valid prefix regardless of
               message boundaries or template wrapper positions.
export (fork)  KVCacheStorage retains cachedTokens (done) + gains a
               boundary-snapshot API: slice each cache layer to a token
               count and serialize with the token chain (only layer
               classes that slice safely — KVCacheSimple first; others
               degrade to full-length boundaries).
consult (fork) at prefill time, before computing: ask an injected hook
               (the product's prefix pool) for the longest matching
               token-prefix boundary; on hit, seed the cache storage from
               the snapshot and prefill only the remainder. Empty new
               sessions and continuing sessions both benefit.
product        feeds the hook with the existing pool; boundary cadence
               e.g. every 2048 tokens + turn end. Same kill switch.
```

## 3. Invariants (carried)

- P-I1 unchanged: match = recomputed token-chain equality on the live
  rendered stream; any mismatch = miss (never a wrong bind). Sidecar
  reconciliation at load stays.
- P-I4: hook nil / disabled → bit-exact today's path.
- Memory: boundary cadence bounds snapshot count; pool LRU budget stands.

## 4. Honest scope

- Fork (mlx-swift-lm) core serving path is touched — this is why it is a
  gated definition, not a patch. Regression battery: fork unit tests +
  product suite + the B-5 battery re-run with a NEW-conversation case.
- Quantized/rotating cache classes may not slice safely in v1: they
  degrade to full-length boundaries (still serves continuation/resume).

## 5. Decision requested

Approve B-6 fork surgery per this design, or defer and run interim
mitigations (stable session_id client-side; document-as-tool-result
instead of prompt) while GA-scale work continues.
