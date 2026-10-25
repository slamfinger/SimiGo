# SimiGo-Lab — O4 Full-vs-Segmented Generation Performance Differential — 2026-09-26

Status: O4_PERFORMANCE_DIFFERENTIAL_MEASURED / SEGMENTED_2X_FULL_AT_20GIB_SCALE
Phase: Oversized Model Execution Investigation
Protocol: G1.9-O4.GEN.V1 (`simigo2ctl o4-gen-compare`)
Model: Nail-Qwen3.6-35B-A3B-MLX-4bit (qwen3_5_moe, 40 layers, 256 experts × 8
active + shared, 20.15 GiB, 360 fused switch_mlp tensors) on 32.0 GiB
physical — a model where BOTH residency strategies fit, so the same greedy
cacheless function (full-sequence re-forward per token, no KV authority) is
executable through both. The only difference is the residency/execution
strategy.

User-directed analysis (2026-09-26): "全量计算和分片两者之间的性能差异分析".
The oversized model itself (Qwen3-Coder-Next-4bit, 41.76 GiB) admits NO full
path (measured, O2/O3): native full load never completes and whole-graph
execution requires all segments resident (> physical). The differential is
therefore measured at 20.15 GiB and combined with the O2/O3 capacity facts
for the oversized axis.

## Measured differential (8 tokens × 2 passes, 4×10-layer segments,
prompt 203 tokens, greedy)

```text
                              segmented            full
resident (active)             3,353 MiB            20,633 MiB
peak footprint                6,649 MiB            22,451 MiB
mean token latency pass 1     4,771 ms             2,355 ms
mean token latency pass 2     4,640 ms             2,295 ms
per-token segment breakdown   read 2,528 ms        —
  (pass 2)                    forward 2,037 ms
                              update 4 / release 34 ms
tokens                        [1919, 18091, 264,   identical (all 8 tokens,
                               709, 1510, 698,      both passes)
                               63, 421]
swap at any sampled boundary  0 MiB                0 MiB
```

Headline: **segmented ≈ 2.0× full per-token latency at 20.15 GiB scale,
for 3.4× less peak memory.** Cross-path token sequences are bit-identical
(descriptive observation only; no numeric-equivalence claim per the frozen
C″ protocol boundary).

## Decomposition — where the differential lives

```text
full forward (whole graph)        ≈ 2.30 s/token
segmented forward (4 segments)    ≈ 2.04 s/token   → decomposition penalty
                                                     ≈ 0 (slightly faster)
segmented re-materialization I/O  ≈ +2.53 s/token  → THE differential
```

The segment-wise execution itself costs the same as whole-graph forward
(the fork's forwardLayerRange decomposition adds no measurable overhead);
the entire performance gap is **per-token re-materialization I/O**:
~17 GiB of fused switch_mlp weights re-read per token at ~6.9 GB/s
effective throughput. Any capacity gain from segmentation is bought at
exactly this I/O price per token.

## Oversized axis (structural, from O2/O3 measured facts)

```text
41.76 GiB model, 32 GiB physical:
  full path     — DOES NOT EXIST (O2: native load never completes; O3-C:
                  whole-graph forward forces full residency → over-physical)
  segmented     — the only executable path; cost model = per-token I/O of
                  the re-materialized span. At the measured ~6.9 GB/s warm
                  and ~3-5 GB/s cold, ~41.76 GiB/token ≈ 6-14 s/token —
                  slow but REAL execution; the direct O4 measurement on the
                  re-downloaded checkpoint will replace this extrapolation.
```

## Trade-off framing (connection to the frozen line)

The frozen group-resolution result established: between generations,
reload reduction ⟺ retention integral, a linear trade-off frontier with no
free improvement. This measurement is the same economics at FORWARD
granularity: capacity (core + one segment = 3.4 GiB peak vs 20.6 GiB) is
bought at per-token re-materialization latency (≈ +2.5 s/token at 20 GiB
scale, scaling linearly with the re-materialized span and inversely with
I/O throughput). No free improvement appears here either: segmented is
strictly slower per token and exists only to make the oversized case
executable at all.

## Registered caveats

1. Concurrent 42 GiB model download during the run (user-initiated re-pull
   of Qwen3-Coder-Next-4bit) continuously churned the page cache: pass 1 vs
   pass 2 segmented read times are nearly identical (2,668 vs 2,528 ms) —
   the intended cold/warm contrast is neutralized. Absolute read throughput
   (~6.9 GB/s) is a floor estimate under this contention.
2. Small sample (8 tokens × 2 passes per path); unoptimized probe code;
   absolute numbers are baselines, not production performance claims
   (O5 owns the boundary sweep).
3. In-token peak active memory is under-sampled (gauges taken at token
   boundaries); segmented capacity evidence at in-loop boundaries comes
   from the O3-C″ probe gauges (core 3.3 GiB ↔ core+segment 10.4 GiB
   oscillation, swap 0).
4. Probe defect fixed in-flight before accepting numbers: the shared
   `msSince` helper dropped the whole-seconds component of durations ≥ 1 s
   (a ~6 s token reported as its sub-second remainder). The first run's
   token totals were invalid; all numbers above are from the corrected
   timer run.

Artifact: `simigo2-experimental/results/o4-generation/nail-qwen36-35b-4bit-full-vs-segmented.json`;
probe `O4GenerationProbe.swift`.
