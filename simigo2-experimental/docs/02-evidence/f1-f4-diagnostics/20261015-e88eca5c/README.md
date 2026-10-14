# F1 / F4 diagnostics — 2026-10-15 / e88eca5c

F1 authorized on locked fork `mlx-swift-lm@6d01a13c` (diagnostics only — no
inference-behavior changes, no acceptance-bar changes). F4 is the
reviewer-found host lifecycle/caller-identity gap. Model:
Qwen3-Coder-30B-A3B-Instruct-4bit @ `6e302ea6`; prompt 968 tokens; boundary
900; greedy.

## F1 — numerical path findings (four-path diagnostics + fidelity isolation)

1. **Chunk-shape sensitivity is real and cold-only.** The pure-cold
   remainder-chunked path (`coldSegmented`) flips the same compound token as
   the warm path — NO snapshots involved. `coldFullBalanced` and
   `coldFullUnchunked` agree with each other and differ from `coldSegmented`
   at text position 35.
2. **The flip site is numerically marginal.** Top-1 ("head", 23.75) vs top-2
   (" Ahead", 23.50): a 0.25-logit margin decides it. Any prefill-shape
   perturbation can cross it.
3. **Save→load fidelity is EXACT.** The artifact-sourced-from-an-unchunked
   session equals a direct single-forward KV computation bit-exactly across
   all 48 layers (`keysMaxAbsDiff = 0`, `valuesMaxAbsDiff = 0`). The
   serialization path is ACQUITTED.
4. **The earlier diff=26 was a confounder, itself a finding.** The
   balanced-session's INTERNAL KV differs from both single-forward and
   [900|68]-forward computations by max-abs ~26 — the fork's ChatSession
   prefill internals (logits-position reservation, internal chunk shapes)
   produce materially different KV from any externally reproducible shape.
   `unchunkedPrefix_vs_segmentedPrefix` (both direct calls) is exactly 0:
   a clean 900|68 split does NOT change KV; the shape effect lives in the
   fork's session-internal prefill management.
5. **Warm ≠ segmented-cold.** They diverge from each other (position 35/36),
   so adoption does not reduce to "boundary-aligned cold chunking": the
   fork's public chunking API cannot reproduce the adoption shape exactly
   (the remainder mode's logits reservation reshapes the split).

Per the approved decision logic this lands in branch 2 (warm ≠ segmented
cold → inspect serialization/adoption/suffix), and the inspection acquits
serialization while locating the residual in session-internal prefill shape
composition. Diagnostics only; the bit-equality bar stands unchanged pending
the human adjudication this evidence feeds: the data show bit-equality
across prefill shapes is not a stable property of this stack even between
two cold paths.

## F4 — host-side closure with registered residual

- `switchModel` now: bump generation → release hook → DROP old container →
  load new. Rollback RELOADS the previous model; double failure reports the
  host deactivated with the original error.
- Host-issued sessions carry their generation (`HostSession`): post-switch
  generate attempts throw `sessionStale` instead of evaluating against the
  new model's snapshots.
- The global hook installs with a generation-bound `admissionGuard`; refused
  lookups return nil (cold) and record an observed miss — closing the
  wrapper-check→hook TOCTOU window.
- Self-review caught and fixed an ordering bug before any run: `activate`
  originally bumped the generation AFTER loading, which would have
  permanently cold-refused the first activation's cache.
- **Residual (deliberately not claimed closed):** a raw pre-switch
  `ChatSession` created outside the host can still reach the global hook;
  the fork's hook signature carries no caller identity, so full closure
  needs a fork-side session-identity API. Mitigations: namespace separation,
  the fork's layer-count guard, token-chain admission. The probe records a
  `foreignHookCold` observation leg; a full-closure fork API change is
  REGISTERED as follow-up, out of this unit's scope.

Unit evidence: guard refusal/re-allow test; full suite
`365 executed / 3 skipped / 0 failures`. Real-model F4 legs in the probe run:
`staleSessionRejected = true`, `reAdoptedHitObserved = true` at the full 900
boundary.

Measurement defect, recorded honestly: the `foreignHookCold` leg invoked the
hook AFTER the switch-back, i.e. model-A tokens against model-A's own cache
— a legitimate hit, so `foreignHookCold = false` is the expected same-model
result, NOT evidence about the residual. The correct placement (raw A tokens
while B is active) was not measured; the residual stays REGISTERED-OPEN
pending the fork-side session-identity API.

## Files

- `f1-four-path-diagnostics.json` — four decode paths, pairwise divergences,
  direct-KV diffs, divergence margin
- `f1-artifact-fidelity.json` — save→load exactness isolation
- `f4-probe-run1.json` — real-model switch round trip with F4 legs
- `full-suite.log` — 365/3/0
