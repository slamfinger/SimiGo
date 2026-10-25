# SimiGo-Lab — O3-C′ Streaming Forward v1 Result — 2026-09-25

Status: O3C_V1_TWO_HARD_BLOCKERS_IDENTIFIED / O3C_V2_REQUIREMENTS_REGISTERED
Phase: Oversized Model Execution Investigation
Model: Qwen3-Coder-Next-4bit on 32.0 GiB physical.

## What v1 measured

The streaming probe skeleton + quantize + tensor-location index all worked
(1891 tensors located across 9 shards). The first streaming pass then
aborted with a hard error at the first materialized tensor: **[dequantize]
scales.dtype() == uint32** — the naive per-tensor extraction returned a
packed-U32 metadata array instead of the target weight.

## The two hard blockers (registered as O3-C″ requirements)

### Blocker 1 — no per-tensor safetensors reader in the toolchain

`MLX.loadArraysAndMetadata` is SHARD-granular: it reads a whole 4.9 GiB
shard. Segment streaming needs per-tensor reads (header → seek to
data_offsets → read only that tensor → construct MLXArray with dtype/shape,
handling packed U32 4-bit weights). The naive first-array selection loads
the wrong dtype. **Required component: `PerTensorSafetensorsReader`**
(header parse + seek + dtype construction + packed-quantized handling).

### Blocker 2 — whole-graph lazy eval defeats capacity discipline

Even with per-tensor reads, `model(running)` builds the FULL 48-layer lazy
graph; at `eval(logits)` every layer's weights are touched → all segments
must be resident simultaneously → peak = full model (41.76 GiB) regardless
of materialize/release ordering around the call. True streaming requires
SEGMENT-WISE graph decomposition: run embed → layers[0..16] → eval →
layers[16..32] → eval → …. The fork's `Qwen3NextModelInner.layers` is
`fileprivate` — segment decomposition needs a Backend API surface (an E3-
pattern extension to the local fork's `Qwen3Next` model: a public segment
forward, which is Backend-side and does not move identity/continuation into
the Backend).

## Failure-mode evidence retained

```text
O3C +0s   skeleton + quantize done
O3C +0s   tensor location index: 1891 tensors
O3C +0s   streaming pass 1 started
fatal     [dequantize] scales.dtype() == uint32 … (first naive tensor read)
watchdog  process exited before any step completed (json 0 bytes)
```

## O3-C″ requirements (next gate, registered)

1. `PerTensorSafetensorsReader` — per-tensor seek+read with dtype/shape
   construction and packed-U32 4-bit/8-bit handling; also the O2-B
   selective-touch experiment's missing tool.
2. Backend segment-execution surface — extend the local fork's
   `Qwen3Next` model with a public layer-range forward (Backend-side
   feature; Runtime keeps identity/lineage/continuation). No Apple mlx-swift
   modifications.
3. Re-run the two-pass determinism + capacity-discipline protocol on the
   working streaming path.

The chain so far remains: O2 native = H-EAGER/load-incomplete → O3-A
skeleton PASS (0.09 GiB) → O3-B selective residency PASS (28.26 GiB,
swap 0) → O3-C naive forward blocked (lazy-random materialization) →
O3-C′ v1 blockers identified → **O3-C″ designed, not started**.

No frozen-line changes. E5v2 untouched.
