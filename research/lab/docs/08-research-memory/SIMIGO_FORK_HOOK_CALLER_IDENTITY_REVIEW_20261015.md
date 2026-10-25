# Fork hook caller-identity residual — design review

- Review ID: `FORK-HOOK-CALLER-IDENTITY-01`
- Type: `RESIDUAL-RISK DESIGN REVIEW / NO FORK CHANGES / NO EXPERIMENTS`
- Baseline: `main = 861a2764` (post GUI-promotion ACCEPT); locked fork
  `mlx-swift-lm@6d01a13c`
- Status: `DESIGN PROPOSED / IMPLEMENTATION NOT AUTHORIZED BY THIS DOCUMENT`

## The registered residual (restated)

The global `ChatSession.crossSessionPrefixLookup` hook receives only
`promptTokenIds`. Host-side mitigations (generation-checked host sessions,
content-derived namespaces, token-chain admission, the fork's layer-count
guard) narrow but do not close the hole: a raw `ChatSession` created outside
the host (pre-switch, still alive) can reach the hook after the host switched
models; if token-chain and layer-count happen to line up, it could adopt the
new model's KV. GUI promotion ACCEPT records this as explicitly outside its
scope.

## Existing-interface evidence (locked fork, line-verified)

1. Hook declaration (`ChatSession.swift:371`):
   `nonisolated(unsafe) public static var crossSessionPrefixLookup:
   (@Sendable (_ promptTokenIds: [Int]) -> (cache: PromptCacheSnapshot,
   matchedTokenCount: Int)?)?` — no caller datum of any kind.
2. Consultation site (`ChatSession.evaluate`, ~1288): guards are
   `conversation?.cachedTokens.isEmpty`, `!carriesPreparedMedia`,
   `input.text.mask == nil`, `lmState == nil`, plus post-adoption
   `snapshot.cache.count == kvCache.cache.count` (layer count). None
   identifies the CALLING session's model.
3. `ModelConfiguration.id: Identifier` (`ModelConfiguration.swift`) is
   `.id(String, revision)` OR **`.directory(URL)`** — for locally loaded
   models the configuration RETAINS the local directory URL, and
   `ChatSession` holds its `ModelContainer` (constructor; reviewer-cited
   references). The consultation site can therefore read the caller's model
   directory without new bookkeeping.

## Answers to the four core questions

**Q1 — which fork layer provides the identity?**
`ChatSession.evaluate` at the consultation point — the only layer that knows
which session is asking. It already sits inside the fork's own adoption
decision; passing the caller's model origin there is the minimal, correct
seam. Nothing at the MLX/model-math layer is involved.

**Q2 — what is the identity bound to?**
The CALLER'S MODEL ORIGIN, not the host, not a generation: fork-side state
is the session's `ModelConfiguration.id`, exposed as
`modelDirectory: URL?` (nil for unresolved hub-id loads). Rationale: the
residual is cross-MODEL adoption; directory identity closes exactly that
(same directory = same model the cache was built for, from the fork's point
of view). Host generation stays a HOST-side concept (already enforced by
our admission guard) — pushing it into the fork would couple the fork to a
host abstraction it must not know about. Combination binding
(directory + the fork's existing layer-count check) is the complete pair.

**Q3 — fail-closed semantics?**
The hook variant receives `callerModelDirectory`. Our host cache refuses
(returning nil → normal cold path, and records an observed miss, matching
the existing refusal pattern) when: the datum is nil (hub-id caller — no
verifiable origin), the directory differs from the cache's activated model
directory, or the host generation guard already refuses. No throw, no
partial adoption — refusal is indistinguishable from a miss to the session,
which proceeds with full prefill.

**Q4 — compatibility and frozen semantics?**
Add a NEW opt-in hook variable, e.g.
`crossSessionPrefixLookupWithContext: (@Sendable (_ promptTokenIds: [Int],
_ caller: CallerContext) -> ...)?` where `CallerContext` carries
`modelDirectory: URL?`. `evaluate` prefers the context variant when
installed and falls back to the legacy variable otherwise. Zero behavior
change for every existing caller (the legacy path is untouched); the engine
path never consults either hook, so DCC-1 Tier-1 is untouched by
construction. `nonisolated(unsafe)` static state semantics unchanged.

## Minimal API sketch (fork side, ~15 lines)

```swift
public struct CrossSessionCallerContext: Sendable {
    public let modelDirectory: URL?   // nil when the model has no local origin
}

nonisolated(unsafe) public static var crossSessionPrefixLookupWithContext:
    (@Sendable (_ promptTokenIds: [Int], _ caller: CrossSessionCallerContext)
      -> (cache: PromptCacheSnapshot, matchedTokenCount: Int)?)?

// in evaluate's seed branch:
let hook = Self.crossSessionPrefixLookupWithContext
    ?? Self.crossSessionPrefixLookup.map { legacy in
        { tokens, _ in legacy(tokens) }   // legacy closure = unknown origin
    }
// caller context built from container.configuration.id
```

Host side: `install(admissionGuard:)` gains a caller-directory predicate;
refusal records a miss and returns nil.

## Rejection conditions (exhaustive, host-enforced)

| Condition | Outcome |
| --- | --- |
| caller `modelDirectory == nil` | refuse → cold |
| directory ≠ cache's activated model directory | refuse → cold |
| host generation stale (existing guard) | refuse → cold |
| directory matches, chain/layer checks pass | adopt (unchanged) |

## Residual AFTER this fix (accepted sliver, stated)

Same-directory-content-drift: a raw session loaded from directory D before
D's contents changed, consulting a cache built from D's new contents. The
raw session is itself stale relative to its own weights; the host's
content-derived namespace protects every HOST-issued session, and the fork
cannot see content identity. Recorded as accepted; NOT expanded by this
review.

## Acceptance criteria (for a future, separately authorized implementation)

1. Unit (fork-level): a context-hook installed; a mock caller with a
   different directory gets nil; same directory with matching chain gets
   the snapshot; legacy hook still functions when only it is installed.
2. Host integration: raw pre-switch ChatSession (foreign session) consulting
   during model-B activity returns nil IN THE CORRECT WINDOW (extends the
   existing probe leg, which currently measures only our host's namespace
   barrier).
3. Compatibility: full existing suite green with the context hook
   uninstalled (zero regression by default) and with it installed
   (behavior changes only for foreign callers).

## Non-goals

- No change to the legacy hook's signature or behavior.
- No fork-side concept of hosts, generations, or our content digests.
- No DCC-1 / engine-path involvement; no GUI feature expansion.
- No claim that this closes G-5/G-8/G-10 or any durability/concurrency
  question — those remain with independent governance.
