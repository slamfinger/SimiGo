# SimiGo 1.7 Execution State Prefix Pool — Problem Definition & Design Draft

**Date**: 2026-09-27
**Status**: DEFINITION_DRAFT / AWAITING_REVIEW (implementation starts only
after review approval — gate discipline)
**Trigger**: user ruling 2026-09-27 — the oversized line is THEORY
VALIDATION only; the daily small-scale path is the foundation. Bring
Execution State to the daily v1.7 NativeMLX path.

---

## 0. Evidence (real-device, native_mlx_trace.log 2026-09-27 02:18–02:25)

```text
new session (first turn)      mode=cold, cacheEff=0.00, TTFT 47.6s
                              (~6.2K context full cold prefill)
same-session continuation     reuse=true, cacheEff=1.00, TTFT 0.478s
                              (healthy — reuse machinery works)
per-turn ~18K injection       cacheEff 0.57/0.70, TTFT 76.3s / 225s
                              (delta is real compute; locality-free)
app restart                   warmTokens=0 — every session cold again
```

Historical confirmation: 2026-09-13 already registered the "retry full
cold-prefill death loop" investigation (reuseMiss visibility added);
the structural gap itself was never registered as a product gap.

## 1. Problem

KV reuse in the v1.7 NativeMLX path is gated on SESSION IDENTITY:
`sessions[executionKey.storageKey]` (NativeMLX.swift:566) — the logical
session key co-owns the physical KV representation. Any new session key
must re-materialize (cold-prefill) its full context even when its token
prefix is bit-identical to an existing representation. Session identity
is too coarse a logical boundary: physical representations cannot be
shared across logically distinct but content-identical states.

## 2. Thesis — Execution State applied at token granularity

The Execution State principle (this lab's registered research line):
logical execution states must consume physical representations by
CONTENT, not by identity; representations are derived, bound, and
released independently of who created them. Applied to the daily path:

```text
newSession(prompt)
  = longestPrefixHit(prefixPool, tokens(prompt))   ← bind, zero compute
  + prefill(delta only)                            ← the true remainder
```

This is the frozen research conclusion made actionable: the only legal
saving is NOT recomputing an already-computed prefix (representation
reuse); never computation skipping (G1.9-C: no execution locality).

## 3. Mechanism (draft)

```text
PrefixPool
  entry      = KV checkpoint at a block boundary of one prompt's token
               sequence
  key        = rolling hash chain over token ids
               namespaced by (modelID, kvFingerprint)
  boundary   = every 512 prompt tokens (aligned; final partial block
               stored at turn commit)

admission (bind)
  tokenize incoming prompt → longest boundary match in namespace →
  load checkpoint via the EXISTING performLoad/cacheLoad machinery
  (kvFingerprint reconciliation already registered for rollforward) →
  prefill delta only

extend (derive)
  turn commit exports NEW tail boundary checkpoints into the pool
  (pool entries are immutable prefix views; no refcounting)

eviction
  prefix-tree LRU under the existing warmTokenBudget/KVTRIM budget;
  admission evicts before importing under pressure (same policy family
  as today's evictSessionsIfNeeded)

precedence
  existing same-session reuse stays FIRST (it is exact and cheapest);
  pool lookup second; cold path unchanged when both miss
```

## 4. Invariants (draft)

```text
P-I1 bind correctness   a pool hit must reproduce a bit-identical
                        continuation; per admission the loaded
                        checkpoint's token count AND rolling hash are
                        cross-checked against the incoming prompt
                        prefix (the I-L3 lesson: verify the claim
                        against the representation, never trust the key)
P-I2 fidelity           entries namespaced by (modelID, kvFingerprint);
                        cross-namespace hits impossible by construction
P-I3 bounded memory     pool token total ≤ warmTokenBudget; eviction
                        precedes admission under pressure; pool must
                        not grow swap (verified against [MEM] records)
P-I4 preservation       pool miss = exactly today's path; oversized
                        segmented path UNTOUCHED; no client API change
```

## 5. Verification battery (draft)

```text
unit          hash-chain keying; longest-match admission; delta
              accounting; eviction order; fingerprint isolation;
              corruption of a checkpoint → loud miss (P-I1), not a
              wrong continuation
product E2E   two distinct sessions sharing system+document prefix →
              second session TTFT ≈ delta prefill only; restart + same
              prompt → pool persistence via disk checkpoints;
              oversized E2E regression unchanged
real device   registered BEFORE work: cold TTFT 47.6s @6.2K shared
              context → target = delta × measured prefill rate;
              [MEM] swap flat vs 02:18 baseline
```

## 6. Non-goals

```text
no cross-node sharing            single machine only
no speculation                   exact-prefix reuse only — NOT a
                                 predictor (G1.9-C stands)
no oversized-path change         segment KV stays a separate GA item
no KV mixing across fingerprints no quantization strategy blending
no client-visible API change     transparent to OpenAI-compatible surface
```

## 7. Honest scope statement

The pool removes the SHARED-PREFIX cold tax (47.6s class). It does NOT
remove genuinely new tokens: the ~18K-per-turn injection class (76–225s)
is real compute — G1.9-C proved no locality exists to exploit. That tax
is addressable only client-side (context curation) or by prefill
throughput work, both out of scope here.

## 8. Open review questions

1. Block size 512: prefill-rate-weighted optimum vs hash granularity?
2. Export points: turn-commit only (proposed) vs also mid-prefill?
3. Disk persistence lifetime: session-scoped today (cacheSave) —
   pool-scoped LRU with what cap?
4. Interaction with rollforward conditional-restore gate — precedence
   and accounting when both fire?
5. Does ChatSession delta-extend from an imported checkpoint without
   full re-render (mlx-swift-lm API audit — first implementation step)?
