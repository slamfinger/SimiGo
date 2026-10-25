# Small-scale host acceptance — 2026-10-15 / e138936b

## Verdict

`NOT PASS` overall, with precise per-item state (GUI promotion Option A,
first vertical unit):

| Acceptance item | State |
| --- | --- |
| 1. Same-model cross-session hit | mechanism PASS ×3 runs; **bit-equality FAIL (open finding F1)** |
| 2. Model identity isolation | PASS (unit level: same-name/different-content separated by content digest) |
| 3. Invalidation / corruption | PASS (unit level: fail-closed, no partial adoption) |
| 4. Concurrent switching & lifecycle | PASS (unit churn invariant; real 30B→35B→30B round trip re-adopts at full boundary after fix F2) |
| 5. Actual benefit | **INSUFFICIENT EVIDENCE** — single-run wall time is variance-dominated on this host (F3) |

Mechanism evidence is real and reproduced: every run hit the snapshot at
exactly the 900-token artifact boundary; outputs otherwise matched.

## Findings

- **F1 (open, blocking item 1's bit-equality bar):** adopted-KV greedy decode
  diverges from cold full-prefill decode at one deterministic position
  (generation token ~7 of 24, one compound-token flip, identical in all three
  runs). Hypothesis: GEMM reassociation between 968-token and 68-token prefill
  batch shapes. Needs either an acceptance-bar adjudication (semantic
  equivalence over N tokens) or a fork-side investigation into deterministic
  prefill batching.
- **F2 (found and fixed this unit):** snapshot pools start empty over durable
  roots; activation must rescan. Without it, a switched-back model missed
  every lookup (run 2). Host activation now rescans, fail-closed; pinned by
  `testFreshCacheOnDurableRootReAdoptsAfterRescan`.
- **F3 (open, protocol):** single-run wall time cannot separate adoption
  savings from machine noise for a 16 GB model on this shared 34 GB host.
  Next protocol: min-of-N warm sampling, prefill-rate metric, or a smaller
  timing model.

## What shipped in this unit

`MLXSmallScaleChatHost` (parallel small-scale path; no engine reference, no
shared execution state, explicit single-resident switch discipline),
content-derived model identity for cache namespaces (same-name
different-content models can never share a snapshot pool), the
`mlx-small-scale-host-probe` CLI measuring hit/boundary/equality/timing/switch
re-adoption, and 8 new tests (full suite `364 executed / 3 skipped / 0
failures`).

## Boundary

Single-machine, process-level evidence. No GUI (SimiGo2App) wiring has been
performed; no power-loss/media durability, universal-concurrency, or
governance-closure claims of any kind.

## Files

- `manifest.json` — per-item verdicts, findings, hashes
- `probe-run1-probefix-pending.json` — first run (probe comparison bug era)
- `probe-run2-rescan-missing.json` — run 2, evidencing F2 before the fix
- `probe-run3-final.json` — final run: re-adoption PASS, F1 reproduced,
  timing variance documented
- `full-suite.log` — 364/3/0
