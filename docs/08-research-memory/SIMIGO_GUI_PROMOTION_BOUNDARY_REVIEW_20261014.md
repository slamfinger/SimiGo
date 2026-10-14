# GUI promotion boundary review — 2026-10-14

- Review ID: `REVIEW-GUI-PROMOTION-BOUNDARY-20261014`
- Type: `BOUNDARY DECISION REVIEW / NO IMPLEMENTATION`
- Baseline: `main = 6cb995ff`
- Question: can the MLX cross-session prefix cache be adopted by the GUI
  (`SimiGo2App` / `OversizedSegmentedEngine`) without modifying the frozen
  DCC-1 Tier-1 recovery semantics?

## Verdict

`REQUIRES-INDEPENDENT-PROMOTION-DECISION / DO-NOT-IMPLEMENT`.

Adoption through the engine's existing interfaces is not possible: the reuse
layer is architecturally mismatched, and the only in-boundary alternative
(token-level seeding) delivers none of the value. There IS a second option
that touches no frozen semantics — adding a ChatSession-based host path to
the app as a NEW parallel path — but that changes the product shape of the
GUI and is therefore a promotion decision, not an engineering task. This
review supplies the decision material for both options.

## Q1 — Is the reuse layer correct? No (two mismatches)

1. **Representation strategy.** The hook sells KV rows: the fork's
   consultation site (`ChatSession.evaluate`, mlx-swift-lm) adopts a
   `PromptCacheSnapshot` via `kvCache.replace(with:processedTokenCount:)`.
   The engine path has no KV cache object anywhere: `executeTurn` recomputes
   `bound.prefix + nextInput` from embeddings with `forwardLayerRange(...,
   cache: nil)` every turn, and its representation IS the token prefix
   (`OversizedPrefixPayload`), length-cross-checked by the token ledger
   (I-L3). Installing the hook today is a no-op for the GUI: the hook is
   consulted only inside `ChatSession.evaluate`. The engine path has zero
   references to `PrefixSnapshotStore` / `PromptCacheSnapshot` / KV caches
   (verified by grep over `OversizedSegmentedEngine.swift`,
   `O6ExecutionStateOversized.swift`, `EngineSessionBaseline.swift`).
   `savePrefixSnapshot` is a fork-side `ChatSession` method; the engine has
   neither the write side nor the read side of the artifact contract.
2. **Model identity.** The engine's durable records carry
   `EngineModelIdentity.compute` (weights + tokenizer content identity,
   re-validated at recovery by `loadCurrentValidated`). The cross-session
   cache namespace keys on `modelDirectory.lastPathComponent` plus a fixed
   fingerprint, and the fork's only model-side adoption guard is layer-count
   equality. The two identity schemes are not at the same strength.

Additionally: full-prefix recompute per turn — including within one session —
is the load-bearing O5/O6 design of the oversized engine (KV residency for
streamed 30B-class models does not fit; that is why segment streaming
exists). KV reuse is not merely unwired on this path; it is contraindicated
by the path's reason for existing.

## Q2 — Is there a legal integration point? No

- The frozen DCC-1 Tier-1 contract recovers from the baseline record's
  `prefixTokens` (tokens, never KV) at the baseline position, retires the
  baseline before teardown, and always `resetSemanticState`s at bootstrap.
  Any KV-at-recovery behavior changes the documented Tier-1 data-loss
  semantics — exactly what the runtime handoff forbids reopening.
- The engine's lifecycle interfaces (`ensureSession`, `bootstrapSession`,
  `commitDurableBaseline`, `restoreSession`, `newSession`,
  `recoverDurableSession`) expose no artifact-read or KV-adoption port.
- The only adoption that does not cross the frozen boundary is token-level
  cross-session seeding (bootstrap a new session from a previous session's
  final prefix). The engine already bootstraps from tokens; the next turn
  would still recompute the full prefix, so nothing is saved. Implementing
  it would be ceremony, not capability.

## Q3 — Regression evidence if promotion is approved

Minimal acceptance matrix (for a ChatSession-based host path; the ownership
discipline from `2cf87cb9` and the real-model acceptance PASS are the
prerequisites already in place):

1. Same-model cross-session hit: warm session output bit-equal to cold
   full-prefill output; `hookCalls = 1`, `hookHits = 1`, matched tokens =
   artifact boundary.
2. Model-switch isolation: different model directory → namespace miss →
   cold start; no cross-model artifact adoption.
3. Invalidation: token-chain mismatch or corrupted artifact → load fails
   closed → cold recompute, never partial adoption.
4. Concurrent switching: `forceTakeover` preserves the single-owner
   invariant; no "hook alive without owner" intermediate state (already
   covered by ownership tests; re-run under the host's real concurrency).
5. Recovery consistency (engine-type hosts only, if ever approved):
   adoption must never advance Execution State beyond the verified artifact
   boundary; cancellation/failure during adoption marks `bindingUncertain`;
   I-L3 / INV-1 / INV-3 invariants hold post-adoption.

## The actual decision

The GUI promotion question is not "wire the cache into the engine". It is:
**should the GUI gain a ChatSession-based small-scale host path alongside
the oversized engine?**

- Option A (new ChatSession host path): engine and DCC-1 semantics untouched;
  the accepted cross-session cache plugs in via the existing ownership
  layer; minimal unit = app-side host path + ownership mount + the Q3
  matrix (items 1–4). Serves the daily small-scale priority directly.
- Option B (stay oversized-only): the line closes at the ownership layer;
  the cache keeps serving CLI/other hosts; no GUI work.

Either way, wiring the cache into `OversizedSegmentedEngine` itself is
rejected by this review.

## Scope of this review

Code-level reading of both paths, the fork's consultation contract, and
zero-touch verification (grep) — no implementation, no frozen-semantics
changes, no governance registrations. G-5 / G-8 / G-10 remain with
independent governance review.
