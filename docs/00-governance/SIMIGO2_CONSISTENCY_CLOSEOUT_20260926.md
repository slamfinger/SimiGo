# SimiGo-Lab — Consistency Close-out: Controller-Driven Segments + Swap-Fix — 2026-09-26

Status: CONSISTENCY_CLOSEOUT_PASS / OVERSIZED_MATCHES_FITTING_CONTRACT
Phase: SimiGo 2.0 Experimental

## What "consistent with the fitting-model path" required

Of the registered follow-ups, exactly one was a semantic consistency gap:
the oversized path performed segment materialization/release ad hoc (no
admission semantics, no transfer log, no INV-1, silent release failures),
while the fitting-model path routes every group residency transition
through the ResidencyController contract (admission/budget, transfer log,
INV-1 log-replay equivalence, DIRTY/recovery). This close-out wires the
oversized path through the same contract.

## Implementation

- `OversizedSegmentMaterializer: RuntimeResidencyBackend` — maps
  controller groupIDs ("layers-L-R") onto the engine's per-unit
  materialize/release; memoryObservation/purgeTransientCaches implemented
  from the engine gauge. Backend decoupled from O6SegmentedCore via a
  release closure (shared with the app engine).
- `OversizedSegmentedEngine`: builds the segment `LayerInventory` (core =
  alwaysResident; streaming units = controller-managed groups); the token
  loop's unit residency goes through `residency.admit(requiredGroupIDs:
  [unit], budget:)` — the controller plans and logs every load/evict.
  Placeholder-first load now leaves ALL switch units as placeholders and
  admits the persistent floor through the controller, so bookkeeping,
  transfer log, and physical state agree from the first transition.
- **Swap-thrash root cause found and fixed** (user-observed "swap 2-20G
  剧烈换页" at the 24-layer-unit profile, persisting 2-12 GiB at the
  16-layer profile): the controller's admission loads the new unit BEFORE
  evicting the previous one — transient double occupancy (2 units + core
  ≈ 28 GiB wired) thrashed the system. Fix: explicit
  `respondToMemoryPressure(targetBytes: floorResidentBytes)` immediately
  after each unit's forward — a contract-clean, logged eviction that
  frees the unit BEFORE the next admission's load. Measured: swap
  oscillation eliminated (flat at the ~1.4 GiB system baseline), latency
  38.5 → 10.5 s/token (3.7×).
- Self-test extended: INV-1 audited after every admission and pressure
  release (checks/failures counted); overallPass now requires
  INV-1 + transfers > 0 in addition to determinism (restore-replay),
  footprint/cache ≤ budget, swap 0, pressure green.

## Final real-device verification (Apple M5, release bundle, unit 16 × 3)

```text
overallPass            TRUE
determinism (restore-replay)  PASS (canonical tokens)
strictExecutionState   TRUE / lifecycle records tracked
INV-1 over segments    TRUE (audited per transition, 96 logged transfers)
peak footprint         13,729 MiB / MLX cache 0 MiB / swap flat at system
                       baseline (~1.4 GiB, no oscillation)
pressure               level 1 (green) throughout
mean token             10,489 ms
```

## Measurement-hygiene lessons registered

1. Engine boundary gauges under-report system swap (samples align with
   release points); dense external sampling (3 s) is required for swap
   claims — the boundary-sampled "swap 0" coexisted with 2-12 GiB
   thrash.
2. zsh does not word-split unquoted variables: a sweep's flag arguments
   silently collapsed into one argument and both runs executed the
   default config (caught by floor-count mismatch in the reports).
3. Controller admission order (load-before-evict within a plan) interacts
   with unified-memory thrash at large unit sizes; per-unit explicit
   pressure release restores the safe ordering within the contract.

Artifacts: `results/o5-sweep/app-realdevice-selftest-{inv1,final}.json`,
`app-selftest-*.json`; code: `OversizedSegmentMaterializer.swift`,
`OversizedSegmentedEngine.swift`, `SimiGo2App.swift`.

## Addendum — Fitting-Model Swap Behavior (descriptive probe) — 2026-09-26

Question: do the oversized techniques matter for fitting (fully-resident)
models? Native full-resident path probe (o2-baseline, zero SimiGo
involvement) on Qwen3-Coder-30B-A3B-Instruct-4bit (16 GiB weights, 32 GiB
machine), dense external swap sampling across load + 3 generations:

```text
swap: flat at 1.61 GiB — the pre-existing system baseline; ZERO
paging activity during load or generation
```

Conclusion: a fitting model that fully resides is naturally swap-free —
there is no streaming, hence no wired-oscillation source for the kernel
to page against. The oversized techniques divide accordingly:
- No use for fitting models: floor/streaming-unit policy and
  post-forward eviction (no streaming = no oscillation source).
- Universal (already model-agnostic): Controller/INV-1 accounting and
  placeholder-first load (the native quantize transient exists at small
  scale too, but at 16 GiB it stays far below the paging threshold —
  headroom, not necessity).
- The one fitting-model class that benefits: borderline models (e.g.
  Nail-6bit, 30.28 GiB — nominally fitting but squeezed under
  co-residency) — for those, the segmented streaming policy applies
  directly.

Artifact: `results/o5-sweep/qwen30b-native-swap-probe.json`.

## Addendum 2 — Nail-4bit (20.15 GiB) Real-Use Swap Probe — 2026-09-26

Question: does the 20 GiB-class fitting model swap in real use? Native
full-resident path (o2-baseline) on Nail-Qwen3.6-35B-A3B-MLX-4bit
(20.15 GiB weights, qwen3_5_moe), dense external swap sampling (3 s) plus
in-probe snapshots:

```text
load                 510 ms (page-cache warm; cold ~1-2 min)
load transient       swap briefly +1.5 GiB (1.56 -> 3.16 -> 1.99 G),
                     settled within one sample
generation           3 x 48 tokens, TTFT ~0.5 s, ~7-14 ms/token;
                     swap FLAT at 1.99 GiB — zero oscillation
full residency       mlxActive 20.74 GiB / phys footprint 22.57 GiB
max system swap      3.16 GiB (load transient only)
```

Conclusion: at current co-residency the 20 GiB-class model is safely
full-resident — no meaningful swap, generation is ~100x faster than the
segmented path. The segmented machinery is NOT recommended for this class
today; it becomes the right tool exactly when co-residency squeezes
available memory below the full-residency point (the borderline regime).
Probe cosmetic: gen-1 tokensPerSecond metric mis-scaled (timing
division); ttft/total fields are the meaningful ones.

Artifact: `results/o5-sweep/nail4b-native-swap-probe.json`.
