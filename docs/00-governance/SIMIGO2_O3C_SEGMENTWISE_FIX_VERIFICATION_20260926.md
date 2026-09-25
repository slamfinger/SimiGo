# SimiGo-Lab — O3-C″ Segment-wise Fix Verification + Capacity Attribution Correction — 2026-09-26

Status: O3C_SEGMENTWISE_PLACEHOLDER_FIRST_PASS / CAPACITY_ATTRIBUTION_CORRECTED
Phase: Oversized Model Execution Investigation
Model: Nail-Qwen3.6-35B-A3B-MLX-6bit (35B total / 3.39B active, 256 experts × 8
active + shared, 30.28 GiB weights = 32.51 GB, model_type `qwen3_5_moe`,
7 shards, dtypes: U32 27.38 GiB / BF16 2.9 GiB) on 32.0 GiB physical.
Probe: `simigo2ctl o3c-segmentwise --passes 2` (G1.9-O3C.SEGMENTWISE.V1)

## Reopening note

The 2026-09-25 Qwen35MoE boundary experiment was sealed with "will not be
re-run". Reopened on explicit user instruction + new evidence: the sealed
run's capacity attribution is traceable to probe defects (below), which
invalidates the measurement, not the mechanism.

## Defect ledger (six, all fixed and verified this round)

```text
D-P1  probe: loadContainer performed the FULL native load (30.28 GiB) and
      kept it resident for the whole run, solely to obtain a model-type
      string. This alone explains the sealed run's "core load = 32.7 GiB —
      already at physical capacity": 30.28 (container) + ~2.4 (true core)
      ≈ 32.7. Fix: container removed; type read from the skeleton model.
D-P2  probe: no placeholder-first update — the lazy-random quantized tree
      (registered cliff) materialized at eval(model.parameters()) in the
      release path (+22 GiB → peak 78,373 MiB footprint). Fix: ONE
      placeholder-first full-parameter update (core = real tensors,
      switch_mlp = zero-size placeholders) before any eval; update(verify: [])
      is pure assignment. Verified: core load = 3,356 MiB active.
D-P3  probe: the per-segment arrays dictionary pinned the segment's real
      weights until the NEXT loop iteration — the release boundary freed
      nothing at the boundary (active stayed 10,365 MiB), buffers moved to
      MLX cache, and footprint ratcheted 22 → 29 GiB per segment. Fix:
      dictionary scoped inside the materialize block; release = placeholder
      swap then clearCache.
D-R1  reader: makeArray element-mapped every tensor into an intermediate
      Swift Array before MLXArray construction — a second full copy of
      every tensor (~7 GiB extra churn per segment on this model); footprint
      ratcheted 22 → 28.6 GiB with system swap > 10-12 GiB. Fix: single-copy
      MLXArray(data, shape, dtype:) construction straight from the file
      bytes (little-endian file on little-endian host; the raw copy IS the
      decode).
D-R2  reader (correctness, found during D-R1): the BF16 branch NUMERICALLY
      converted uint16 values via asType(.bfloat16) instead of reinterpreting
      their bits — every BF16 tensor read through this reader (norms, scales,
      biases; 2.9 GiB on this model) was garbage. No prior output-identity
      claim depended on this path (O3-C never produced a valid reference
      output; the fork's 3/3 math-equivalence test loads through loadWeights).
      Fix: bit-exact raw construction.
D-G1  gate: the capacity check compared raw phys_footprint BYTES against
      capacityMiB — capacityHeldThroughout was false in every run regardless
      of memory behavior (any footprint > 30 KB tripped it). Fix: compare in
      MiB.
```

## Measured verification (after all six fixes)

Double-pass, 4×10-layer segments (40 layers from text_config), 32 GiB
physical, system swap baseline ~1 GiB (other applications):

```text
AFTER_CORE_LOAD         active  3,356 MiB / footprint  4,022 MiB / swap 0
per-segment materialize active 10,237 MiB / footprint ~11,150 MiB
per-segment forward     peak    10,663 MiB / footprint ~11,550 MiB
every release           active  3,357 MiB (core baseline) / footprint flat
                        ~11,350 MiB — ZERO ratchet across 4 segments × 2 passes
max footprint (39 boundaries)    11,768 MiB   (gate 30,720 MiB)
max swap at any boundary          0 MiB
determinism (pass1 vs pass2)      [71093] == [71093] — now meaningful:
                                  reader is bit-exact after D-R2
residentSetBoundaryObserved       true
capacityHeldThroughout            true
overall                           PASS
```

Runtime note: with the checkpoint resident in the OS page cache (immediately
after the previous run) the full double pass completes in ~15 s; cold-cache
reads take ~4-5 min. Memory profile identical either way.

## Corrections to the registered 2026-09-25 boundary evidence

```text
Finding 1  "segment-wise execution produces a stable, observable residency
           release boundary"      — STANDS, now with stronger evidence: each
           release returns active memory exactly to the core baseline
           (3,357 MiB) with no footprint ratchet.
Finding 2  "capacity is exceeded by core load alone, independent of segment
           policy"                — RETRACTED as a probe-defect artifact
           (D-P1). True core residency is 3.3 GiB; the sealed run never
           measured core load at all — it measured container + core.
```

Boundary discipline: not a performance claim (no latency/throughput
assertions); no frozen research-line changes; E5v2 untouched; fork segment
API remains as registered (uncommitted in the local fork, pending E2E).

Artifact: `simigo2-experimental/results/o3c-streaming/nail-qwen36-35b-6bit-placeholder-first.json`;
probe `O3CSegmentWiseProbe.swift`; reader `PerTensorSafetensorsReader.swift`.
