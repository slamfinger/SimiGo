# SimiGo v2.1.5 — Swift-1.5 Garbled-Output Discrimination Build

Date: 2026-10-15  
Build: 15  
Tag: `v2.1.5`  
Platform: Apple Silicon macOS 26.4+  
Asset: `SimiGo-v2.1.5.dmg`

## What this build is

v2.1.4 loaded `ukisai/Swift-1.5-4bit-MLX` successfully, but the first
generation produced multilingual token soup (uniform-random sampling across
the vocabulary — broken logits) and the 26.7k-token cold prefill ran ~146
tok/s (≈3 min). This build is a **controlled discrimination step**: it
reverts upstream #662 ("compiled decode for Qwen3.5 VLM models") — 551
lines transplanted into this lineage's VLM-only `Qwen35Language` stack,
i.e. exactly the code Swift-1.5 executes — falling back to the lineage's
eager decode path. Vendor pin `c3057c58` → `bc64ee69` (single revert
commit).

Already ruled out by direct checkpoint inspection (no code changes needed):

- Norm-shift convention — the checkpoint's `conv1d.weight` shape
  `[10240, 4, 1]` proves the converted convention; the mlx-format early
  return's assumption holds.
- `lm_head` tying — config declares `tie_word_embeddings: false` and the
  checkpoint carries quantized `language_model.lm_head.*`; the filter is a
  pass-through.

## How to read the retry

- **Output sane** → #662's compiled paths are numerically incompatible with
  this lineage's Qwen35Language; it stays reverted until properly re-ported
  against our implementation (decode will run eager — slower but correct).
- **Still garbled** → suspicion moves to #633 (GDN q/k norm eps, also
  touched Qwen35.swift) or a lineage/checkpoint mismatch inside
  Qwen35Language itself; next step is reverting #633 in the same manner.

Prefill throughput (~146 tok/s for this 30B-class dense hybrid through the
VLM stack) is unchanged by this revert — #662 targeted decode. Prefill
optimization for the VLM text stack is tracked separately.

## Verification

- Release build: PASS (build 15).
- Vendor delta `c3057c58..bc64ee69` = the single revert commit.
- DMG `hdiutil verify` VALID; embedded app version 2.1.5 (15).
