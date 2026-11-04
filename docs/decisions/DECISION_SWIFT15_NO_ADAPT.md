# Decision: Stop adapting ukisai/Swift-1.5-4bit-MLX

Date: 2026-10-15  
Status: Accepted (user decision)  
Releases affected: none further; v2.1.5 remains the current release

## Context

- v2.1.2 added composite-VLM-checkpoint routing (weight-key layout based);
  v2.1.4 fixed the `visual.*` → `vision_tower.*` prefix so Swift-1.5
  **loads**.
- First real generation produced uniform-random multilingual token soup
  (broken logits) and a ~146 tok/s cold prefill (26.7k tokens ≈ 3 min).
- Discrimination build v2.1.5 reverted upstream #662 (compiled decode for
  the VLM stack): **garbage persisted** → #662 exonerated.
- Static audit cleared: norm-shift convention (conv1d `[10240,4,1]` =
  converted), lm_head tying (untied + quantized head present), rope chain
  (`rope_parameters` fully declared and decoded; rotaryDim = headDim × 0.25
  honored), mrope sections (irrelevant for text-only). Upstream #633 (GDN
  eps) has mathematical proof + tests (0.984 → 2.4e-6 error) — not reverted.
- Investigation endpoint: the shared `gatedDeltaUpdate` kernel call
  arguments are identical between this lineage and upstream; the divergence
  sits in the VLM-only `Qwen35Language` GDN wrapper (fused-projection
  split / gating semantics) — an unproven Lab-era implementation that had
  never served a real VLM checkpoint before v2.1.2.

## Decision

Stop adapting. Reasons:

1. **Serving economics are against it.** Swift-1.5 is a dense Qwen3.8-27B
   derivative (51.25 GFLOP/token) vs the user's daily driver
   Nail-Qwen3.6-35B-A3B (MoE, ~3.4B active, 6.79 GFLOP/token) — 7.5× the
   per-token compute for the same serving profile.
2. **Its headline advantage does not apply.** The model's value proposition
   is thinking-token economy (−58.5%, 9.18× vs its own base); SimiGo serves
   with `thinkOff=true`.
3. **The checkpoint is exotic by its author's own documentation**: requires
   a supplied architecture patch + pinned Python runtime even for
   mlx-lm; unpatched loaders reject 501 vision entries; "GUI compatibility
   remains unverified." Debugging the wrapper divergence for a
   worse-economics model is not worth further cycles.

The user deleted the local HF cache (`models--ukisai--Swift-1.5-4bit-MLX`).

## What stands

- Composite-VLM routing stays (correct, zero-cost infrastructure).
- v2.1.5 stays as released (eager decode on the VLM stack is the safer
  default for this lineage).
- If a future mainstream Qwen3.5/3.8-family VLM matters for SimiGo, the
  right path is porting upstream's proven Qwen35 VLM implementation (with
  its component infra), not patching this lineage's wrapper against an
  author-patched checkpoint.
