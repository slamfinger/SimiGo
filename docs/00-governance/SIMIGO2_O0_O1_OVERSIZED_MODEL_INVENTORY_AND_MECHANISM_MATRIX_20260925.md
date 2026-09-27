# SimiGo-Lab — Oversized Model Execution Investigation — O0/O1 — 2026-09-25

Status: O0_PRIOR_ART_AND_O1_INVENTORY_COMPLETE / O2_MLX_BASELINE_NEXT
Phase: Oversized Model Execution Investigation (working title — final gate
naming deferred until O1–O5 evidence exists)
Core question: **when Model Representation > Physical Memory, can SimiGo
establish executable Model Residency and sustain real inference — and where
is the performance boundary?**
Boundary: this phase registers architecture-level findings only. E5v2 and
the frozen residency research line are untouched.

## O0 — Prior art and mechanism separation

Reference implementations (surveyed, not trusted as conclusions):

1. **llama.cpp / ggml** — documents an explicit chain: model file → mmap →
   tensor mapping → lazy read → backend buffer → execution, with separate
   load-mode (mmap) and lazy-mode controls, per-tensor buffer selection.
   Reference for MECHANISMS; not evidence that SimiGo + MLX can do the same.
2. **MLX / mlx-swift-lm** — the closest backend: registry-based model
   creation, safetensors weight loading, tokenizer. The O1 audit below
   establishes where ownership/allocation actually happens.
3. **Other offload/paging/expert-loading implementations** — second-tier
   references.

Mechanism separation discipline — these are NOT one concept:

| Mechanism | Problem it solves |
|---|---|
| mmap | file → virtual address mapping |
| lazy loading | defer physical read until touch |
| CPU/GPU offload | migration between compute devices |
| paging | resident working-set management |
| eviction | deliberate release of physical resources |
| expert loading | selective MoE sub-module residency |
| swap | OS virtual-memory mechanism |

## O1 — Mechanism matrix

| Capability | llama.cpp | MLX | mlx-swift-lm | SimiGo |
|---|---|---|---|---|
| mmap of model file | documented (load-mode mmap) | loadArrays is mmap-backed lazy at load (verified in IO.swift; empirical footprint check pending O2) | uses MLX loadArrays | not implemented (target) |
| lazy tensor read | documented (lazy mode) | lazy MLXArrays until eval | no — loadWeights updates ALL parameters | not implemented |
| partial residency | documented / needs experiment | not in the load path | no | group materializer VALIDATED (L4-A/B) |
| group materialization | reference | possible per-group (loadArrays + update) | no | VALIDATED (L4-B/C) |
| eviction | reference | release pattern validated | no | VALIDATED (L3/L4) |
| real execution consumption | yes | yes | yes | YES — E5v2 representation-consuming execution |
| model > physical memory | needs local verification | needs local verification (O2) | needs local verification (O2) | TARGET of this investigation |

The matrix prevents the "conceptually possible → code seems to support →
experiment PASS" jump: every cell above is either anchored to a registered
artifact or explicitly marked as pending empirical verification.

## O1 — Model Representation Inventory: Qwen3-Coder-Next-4bit

Measured facts (safetensors header scan + file audit; snapshot
`7b9321ea…`):

```text
files                    9 shards (≈4.78–4.90 GiB each) + config/index/tokenizer
on-disk size             42 GiB (du -L) ≈ 44.9 GB decimal
weight bytes (headers)   41.76 GiB across 1891 tensors
architecture             qwen3_next / Qwen3NextForCausalLM
layers                   48 = 12 full-attention + 36 GatedDeltaNet
                         linear-attention (full_attention_interval 4)
MoE                      512 experts / 10 active per token + shared expert
                         (moe_intermediate 512, hidden 2048)
quantization             4-bit group-64 affine (router gates 8-bit)
dtypes                   U32 (packed quantized) 37.12 GiB / 542 tensors
                         BF16 4.64 GiB / 1349 tensors
```

### File vs decoded vs resident representation

- The 4-bit weights are stored PACKED (U32) and MLX executes quantized
  matmul directly on packed weights: **decoded expansion does not occur at
  load** (to be confirmed empirically in O2 by comparing process footprint
  with header bytes). Runtime resident ≈ file bytes for weights.
- Therefore `44.9 GB file ≈ 41.76 GiB packed weights ≈ the resident weight
  footprint when fully materialized`.

### The decisive structural fact

**The 512 experts are FUSED into `switch_mlp` tensors** — the same
fused-MoE pattern as Qwen3-Coder-30B. Mapped onto the existing SimiGo
3-group partition:

```text
switch_mlp layers 00–15 : 13.50 GiB
switch_mlp layers 16–31 : 13.50 GiB
switch_mlp layers 32–47 : 13.50 GiB
non-switch (attention, linear-attn, shared expert, norms, embed, lm_head)
                        : ≈ 1.26 GiB
```

Physical memory of this machine: **32.0 GiB**.

### Oversize arithmetic

```text
core + 1 switch group   ≈ 14.8 GiB   fits
core + 2 switch groups  ≈ 28.3 GiB   fits (< 32 GiB)
core + 3 switch groups  ≈ 41.8 GiB   EXCEEDS 32 GiB physical
```

The model is oversized ONLY when all three switch groups are resident
simultaneously. With a residency strategy that keeps at most two groups
resident, execution fits comfortably — at the cost of reloading the third
group per layer-range traversal (the trade-off frontier machinery from the
frozen research line applies directly).

## O1 — Load-chain audit (the four questions)

1. **What is the 44.9 GB made of?** 41.76 GiB of weights (37.12 GiB packed
   4-bit + 4.64 GiB BF16), dominated by the fused 512-expert switch_mlp
   (40.50 GiB); 9 shards; plus config/tokenizer. Answered above.

2. **How does the current ModelContainer load path handle these weights?**
   `LLMModelFactory.loadContainer` → model-type registry → `Qwen3NextModel`
   init → `loadWeights` (MLXLMCommon/Load.swift) reads ALL 9 shards and
   calls `model.update(parameters:, verify: [.all])` — a SINGLE-SHOT
   FULL-MODEL load. No partial, per-group, or deferred weight loading exists
   in the current path.

3. **Does MLX have mmap / lazy / page-backed behavior?** `loadArrays`
   creates mmap-backed lazy MLXArrays at read time; the open question is
   what `model.update(verify: .all)` does at first forward: (H-mmap) weights
   stay page-backed until touched, or (H-eager) all weights materialize into
   unified-memory device buffers at load. **O2 distinguishes these
   empirically** by measuring process footprint after load (≈ small vs
   ≈ 42 GiB) — no assumptions.

4. **Can the SimiGo residency layer intervene in real weight execution?**
   YES with one missing piece. The L4-A/B per-group materializer
   (MLX.loadArrays + model.update for ONE group) is validated on four
   models; the missing piece for oversized models is a **skeleton-load
   path**: construct the model WITHOUT loading all weights, then
   group-materialize on demand. The existing per-group materializer is
   reusable as-is for everything after that point. This is the O3 design
   target.

## Support-status discipline

```text
fork supports the architecture (qwen3_next registered)   = verified
the fork can LOAD this model                             = O2, not yet run
SimiGo can manage its residency                          = O3/O4, not yet run
the combined path sustains real inference                = O4/O5, not yet run
```

No claim beyond the first line is made.

## O2 preview (next gate, unchanged scope)

Native MLX baseline on this model, no SimiGo involvement: load (start/
complete), process footprint, swap/pressure, single forward, 1/5/10
generations with TTFT and steady-state tok/s. Distinguishes H-mmap vs
H-eager. No SimiGo code changes in O2.

## Registration

Phase registered in RESEARCH_STATE as
`OVERSIZED_MODEL_INVESTIGATION_O0_O1_COMPLETE / O2_MLX_BASELINE_NEXT`.
E5v2 and the frozen residency research line are NOT modified. All three
possible O-phase outcomes remain open: (A) stable direct execution, (B)
execution requiring SimiGo residency, (C) current MLX path cannot complete
oversized execution — each is a valid result.
