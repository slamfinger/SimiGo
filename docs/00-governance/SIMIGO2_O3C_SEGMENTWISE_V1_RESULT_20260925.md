# SimiGo-Lab — O3-C″ Segment-wise Probe v1 Result — 2026-09-25

Status: O3C_SEGMENTWISE_BLOCKED_AT_CORE_LOAD / LAZY_RANDOM_MATERIALIZATION_CLIFF_FOUND
Phase: Oversized Model Execution Investigation
Model: Qwen3-Coder-Next-4bit (41.76 GiB weights) on 32.0 GiB physical.
Probe: `simigo2ctl o3c-segmentwise` (G1.9-O3C.SEGMENTWISE.V1)

## Measured trace (5 observations before the system OOM-killed the probe, exit 137)

```text
AFTER_CORE_LOAD        active 44061 MiB (43.0 GiB!)  ← the finding
AFTER_EMBED_PASS1      active 44061 MiB
BEFORE_SEG0_FORWARD    active 44061 MiB
AFTER_SEG0_MATERIALIZE active 57885 MiB / footprint 73438 MiB
AFTER_SEG0_FORWARD     active 57887 MiB / peak 57934 MiB
[system OOM kill]      exit 137
```

The core load — which SHOULD materialize only ~1.26 GiB of non-switch_mlp
tensors — produced **43.0 GiB of active memory**. That is ≈ the FULL model.

## Root cause found: the lazy-random materialization cliff

The skeleton construction sequence (createModel → quantize) leaves the model
holding ~40 GiB of LAZY random quantized arrays (random init → quantize
schedules; nothing evaluated — hence the earlier "0.09 GiB skeleton" reading,
which was an illusion of laziness). The FIRST parameter-touching operation —
`model.update(coreArrays)` — forces the ENTIRE lazy parameter tree to
materialize (MLX evaluates the existing parameters to apply/verify the
update), including the skipped segments' random quantized weights.

This explains BOTH prior observations:

1. O3-A's "0.09 GiB skeleton" — real, but only because nothing had touched
   the parameters yet.
2. O3-B's 28.26 GiB selective residency — the measured number likely
   INCLUDES the forced materialization of the skipped group's random
   weights partially offset by array replacement (the group tensors were
   updated with real weights in the same update pass, masking the cliff).
3. O3-C's naive forward thrash — the forward touched the skipped group's
   lazy random arrays and materialized them mid-pass.

One mechanism, four symptoms: **the lazy random quantized arrays materialize
on first parameter touch, all at once.**

## Fix direction (registered, minimal)

**Placeholder-first full-parameter update**: immediately after
`quantize(model:)`, and BEFORE any eval of parameters, issue ONE
`model.update(parameters: unflattened(fullParameterMap), verify: [])` where:

```text
core tensors       = the real checkpoint arrays (1.26 GiB)
segment tensors    = MLXArray(0, [0]) zero-size placeholders (tiny)
```

This replaces every lazy random array with either real data or a
zero-size placeholder BEFORE anything is evaluated — the ~40 GiB of lazy
random quantized arrays are discarded without ever materializing. Subsequent
per-segment materialization then updates only that segment's parameters with
real checkpoint tensors (the validated L4 per-group pattern).

Open question for the fix's implementation: `quantize(model:)` itself may
force per-module evaluation during replacement (QuantizedLinear init takes
the module's lazy random weight). If so, the quantize step must ALSO be
replaced — construct QuantizedLinear modules directly from the checkpoint
scales/biases/weights (per-module), bypassing random-init quantization
entirely. This is still Backend-side work (the fork's model files), per the
E3 pattern.

## What this finding means for the chain

```text
O2   native full load: H-EAGER, fails            (measured)
O3-A skeleton construct: 0.09 GiB — ILLUSION of laziness (this probe)
O3-B selective residency: masked by the same cliff (reinterpret)
O3-C naive forward: same cliff, mid-pass          (measured)
O3-C″ segment-wise: same cliff, at FIRST core touch (this probe)
```

The single blocker for ALL oversized paths: **no existing MLX/Swift path
constructs a quantized model without materializing ~40 GiB of lazy random
weights.** The placeholder-first update is the candidate fix; if
`quantize(model:)` itself cannot run lazily, the fork's Qwen3Next model must
construct QuantizedLinear modules directly from checkpoint tensors (a
Backend-side change, E3 pattern).

## Boundary discipline

No frozen-line changes. E5v2 untouched. The machine OOM kill was the
system's; the probe has since been re-run-safed (placeholder-first is an
unimplemented direction, not attempted).
