# SimiGo-Lab — App Performance Tuning: Residency-Shape Sweep — 2026-09-26

Status: APP_TUNING_MATRIX_MEASURED / MEM22_UNIT24_SHIPPED_DEFAULT
Phase: SimiGo 2.0 Experimental (app performance tuning, user-directed)

User direction (evolved during the session): initial budget reading
(<16 GiB memory / <16 GiB cache / green pressure) was clarified as the
OBSERVED state, not a constraint; the actual request = raise memory usage
to ~22 GiB, keep cache low, and tune performance empirically.

## Engine change

`OversizedSegmentedEngine` gained a **persistent layer floor** policy
(derivation-only `floorBudgetMiB`) and a configurable **streaming unit
size** (`unitLayers`): the first L layers' switch_mlp weights load real
once and stay resident; the remaining layers stream in units of
`unitLayers` layers (materialize → forward → release per unit). Gauges now
include MLX cache MiB and the system memory-pressure level
(`kern.memorystatus_vm_pressure_level`; 1 = normal/green, 2 = warning,
4 = critical). PASS gate: determinism + footprint ≤ budget + cache ≤
budget + swap 0 + pressure == 1.

## Measured matrix (8-token runs on the 41.76 GiB model, 32 GiB machine)

```text
config (floor/unit)   mean ms/token   peak footprint*  pressure
floor 0 / unit 4              9,021          5,120 MiB      1 (green)
floor 8 / unit 10             9,115         11,699 MiB      1 (green)
floor 18 / unit 8            14,753         18,078 MiB      2 (warning)
floor 22 / unit 7            22,443         21,596 MiB      2 (warning)
floor 27 / unit 6            32,921         25,287 MiB      4 (CRITICAL)
floor 16 / unit 8            16,557         19,922 MiB      2 (warning)
floor 5  / unit 16           10,249         14,555 MiB      1 (green)
floor 0  / unit 16           10,734         14,155 MiB      1 (green)
floor 0  / unit 24  ★        13,158         11,668 MiB*     1 (green)
```

*peak gauges are token-boundary samples; the shipped unit-24 config's
true mid-token peak ≈ core + one 24-layer unit ≈ 21.5 GiB — the user's
22 GiB operating point. All configurations: cache ≈ 0 MiB (aggressive
clearCache — the cache budget is met with maximal margin), swap 0,
double-pass identical, and ALL shapes produce identical token sequences
(4-token cross-check; within-shape double-pass bit-identical).

## Findings

1. **Residency is NOT monotonic latency currency.** Raising the wired
   floor degrades latency monotonically (9.0 → 33 s at floor 27, pressure
   to critical): wired pages shrink the page cache and contend for unified
   memory bandwidth, so the streamed re-reads slow down more than the
   saved re-reads gain. The initial "increase memory → increase speed"
   hypothesis is falsified on this unified-memory machine.
2. **Unit size is the real lever at a given footprint.** At the ~22 GiB
   level, 2×24-layer units (13.2 s) beat 4×8-layer units (16.6 s) at the
   same residency — fewer materialize/release cycles and larger sequential
   reads.
3. **Shipped default** = the user's 22 GiB operating point: floor 0 /
   unit 24 (2 streaming units, mid-token peak ≈ 21.5 GiB, cache ≈ 0,
   swap 0, pressure green, 13.2 s/token). The measured low-footprint
   alternative (floor 0 / unit 4: 9.0 s/token at 5.1 GiB, green) remains
   available via `--unit-layers 4 --floor-budget-mib 4096` for
   battery/runtime-constrained contexts.
4. Measurement note: peak footprint is boundary-sampled and
   under-reports mid-token peaks (registered limitation).
5. Process notes: the zsh no-word-split behavior silently voided the
   first sweep's flag arguments (both runs silently ran the default
   config — caught by floor-count mismatch in the reports); fixed by
   explicit argument passing. All numbers above are from the corrected
   sweep.

Artifact: `simigo2-experimental/results/o5-sweep/app-selftest-*.json`,
`app-realdevice-selftest-mem22.json`; engine
`Sources/SimiGo2Experimental/OversizedSegmentedEngine.swift`.
