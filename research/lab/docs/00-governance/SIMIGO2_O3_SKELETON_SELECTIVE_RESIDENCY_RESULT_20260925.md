# SimiGo-Lab — O3 Skeleton Load + Selective Residency Result — 2026-09-25

Status: O3A_SKELETON_LOAD_PASS / O3B_SELECTIVE_RESIDENCY_PASS / O3C_STREAMING_FORWARD_REQUIRED
Phase: Oversized Model Execution Investigation
Model: Qwen3-Coder-Next-4bit (41.76 GiB weights) on 32.0 GiB physical.
Probe: `simigo2ctl o3-skeleton` (G1.9-O3.SKELETON.V1), per-layer
quantization resolution mirroring `loadWeights`.

## Measured results

### O3-A Skeleton Load: PASS (decisive)

```text
A1 construct   Qwen3NextModel via typeRegistry.createModel — NO weights
               loaded; MLX lazy random init
A1 footprint   0.08 GiB   (vs 41.76 GiB full — skeleton construction is
               essentially free)
A2 quantize    in-place quantize from the checkpoint's interleaved
               quantization dict (base + per-module overrides via
               perLayerQuantization); footprint 0.09 GiB, 542 modules
```

The native path's hidden cost is now located precisely: `loadWeights`
materializes LAZY RANDOM full-size weights per module during quantize, then
overwrites them with checkpoint arrays — pay random-init twice and read all
shards up front. The skeleton path pays neither.

### O3-B Selective Residency: PASS (spectacular)

```text
materialized   1747 tensors / 28.26 GiB (core + switch groups 0–15, 32–47)
skipped        13.50 GiB (switch group 16–31 — the evicted group)
time           0.3–0.4 s (shard-range selective reads only)
footprint      28.33 GiB, swap 0.00 GiB — UNDER the 32 GiB physical limit
per-layer      quantization (base 64/4 + 8-bit gate overrides) verified by
               A2 + B passing without quantized_matmul shape mismatches
               (an intermediate run with a uniform 64/4 predicate failed
               exactly there, confirming the O1 finding that the
               checkpoint mixes 4-bit and 8-bit modules)
```

### O3-C Real Forward: BLOCKED — with the mechanism identified

The naive skeleton forward (model called over the full 48-layer graph) hung
at 0% CPU and was killed at ~29 min. Post-mortem mechanism: the evicted
group's parameters were LAZY RANDOM arrays; the forward touches every
layer, so MLX lazily materialized the 13.50 GiB random group during the
pass → footprint ≈ 41.8 GiB → over-physical thrash (swap 24.5 GiB at kill).

**This is the structural finding of O3**: a complete forward pass through
48 sequential layers necessarily touches EVERY layer's weights. Residency
management between generations (the L4 pattern) cannot help DURING a
forward. For a model whose groups do not all fit, the forward itself must
stream:

```text
for each 16-layer range (in order):
    materialize that group's switch_mlp from shards
    run those layers
    release the group
```

Layer streaming (Route D at forward granularity) is REQUIRED for oversized
execution on this machine. It is feasible — layers are strictly sequential,
and the selective materializer already loads arbitrary shard ranges in
0.3–0.4 s — but it is a distinct execution mode (per-range forward between
materializations), not a flag on the existing path.

## Consequences

```text
O3-A skeleton load      SOLVED (0.09 GiB; quantize-in-place from checkpoint
                        metadata)
O3-B selective residency SOLVED (28.26 GiB resident, swap 0, <1 s)
O3-C real forward       REQUIRES STREAMING FORWARD (next gate, O3-C′):
                        materialize-run-release per layer range during the
                        forward; also requires lazy-random suppression
                        (zero-placeholder release) so untouched groups
                        never materialize random weights
```

Registered boundary: with 13.5 GiB group granularity, streaming means one
13.5 GiB materialization per forward pass (disk-read bound) unless finer
granularity (per-layer or per-expert-tensor materialization) is used — the
safetensors format stores per-tensor offsets, so finer granularity IS
available to the materializer; only the 3-group PARTITION was coarse.

No frozen-line changes. E5v2 untouched. The watchdog kill and swap spike
were contained (system recovered; swap drained after kill).

O3 history: `O3SkeletonProbe.swift` probe; stage traces in
`/tmp/o3-qwen-next.err` (session artifact); this document.
