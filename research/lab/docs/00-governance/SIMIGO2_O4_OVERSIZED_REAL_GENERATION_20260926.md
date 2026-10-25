# SimiGo-Lab — O4 Oversized Real Generation — Measured — 2026-09-26

Status: O4_OVERSIZED_REAL_GENERATION_PASS / CORE_PLUS_ONE_SEGMENT_ZERO_SWAP
Phase: Oversized Model Execution Investigation
Protocol: G1.9-O4.OVERSIZEGEN.V1 (`simigo2ctl o4-oversized-gen`)
Model: Qwen3-Coder-Next-4bit (qwen3_next, 48 layers, SparseMoE 512 experts ×
10 active + shared, 41.76 GiB weights, 9 shards, snapshot 7b9321ea — user
re-pulled) on 32.0 GiB physical.
Execution: segmented only (3×16-layer segments, the registered partition);
full path does not exist at this scale (O2/O3 measured). Harness-level
physical layer only — no Execution State machinery (that composition is O6).

## The O4 question, answered by measurement

"When Model Representation > Physical Memory, can SimiGo establish
executable Model Residency and sustain real inference?" — **YES**:

```text
core resident (active)          1,294 MiB   (matches the O1 registered
                                             core ≈ 1.26 GiB)
peak footprint                  13,883 MiB  — 41.76 GiB model executing in
                                             < 14 GiB of physical memory
max swap at any boundary        0 MiB
tokens generated                16 (8 × 2 passes), greedy, chat template
mean token latency              10,961 ms (pass 1) / 11,038 ms (pass 2)
  decomposition                 re-materialization read ≈ 8.6 s/token
                                (40.5 GiB/token ≈ 4.7 GB/s effective)
                                forward ≈ 2.2 s/token
double-pass determinism         PASS — [8420, 594, 264, 13027, 729, 429,
                                80953, 1378] identical across passes
```

The 20.15 GiB A/B extrapolation (6–14 s/token) is confirmed by direct
measurement (~11 s/token). The cost decomposition matches the A/B finding:
the differential vs full residency (which does not exist here) is almost
entirely per-token re-materialization I/O; segment execution itself
(2.2 s) is on the same order as whole-graph forward at fitting scale.

## Reading

1. Oversized execution is REAL and STABLE: 41.76 GiB > 32 GiB physical,
   resident set = core + one 13.5 GiB segment, zero swap across 16 token
   boundaries, bit-identical double pass. Capacity, stability, and
   determinism all hold at forward granularity.
2. The price is latency, exactly as the O4 differential predicted:
   ~40.5 GiB of re-materialization I/O per token dominates (8.6 s of the
   11 s token). Throughput-bound, not compute-bound.
3. Same no-free-improvement economics as the frozen frontier result, now
   measured at forward granularity on the true oversized case: residency
   capacity is bought with per-token reload latency.

## Caveats

- 8 tokens × 2 passes, one prompt; stability at length (long generations,
  larger contexts) is O5 territory. No performance/production claims.
- Pass 1 and pass 2 read times are near-identical (8,639 vs 8,665 ms) —
  the ~41.76 GiB checkpoint can never be fully page-cache resident on this
  machine, so cold-vs-warm is structurally irrelevant at this scale (the
  steady state is disk/memory-bandwidth-bound by construction).
- Harness-level probe; the ResidencyController contract, transfer log, and
  Execution State machinery are intentionally absent (physical-layer gate;
  composition = O6).

Artifact: `simigo2-experimental/results/o4-generation/qwen3-coder-next-4bit-oversized-gen.json`;
probe `O4OversizedGenerationProbe.swift`.
