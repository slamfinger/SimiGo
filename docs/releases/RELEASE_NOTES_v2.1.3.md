# SimiGo v2.1.3 — Vendor Performance Batch

Date: 2026-10-15  
Build: 13  
Tag: `v2.1.3`  
Platform: Apple Silicon macOS 26.4+  
Asset: `SimiGo-v2.1.3.dmg`

## Highlights

Ten upstream mlx-swift-lm commits (performance + correctness) cherry-picked
onto the pinned vendor with per-commit zero-smuggle audit. Vendor pin moves
`e520e605` → `252f440b` (only the audited commits; vendor `Package.swift` and
the mlx-swift pin untouched).

### Performance

- **#662 — Compiled decode for Qwen3.5 VLM models.** The single largest win
  for `ukisai/Swift-1.5-4bit-MLX`: hybrid linear-attention decode goes
  through compiled fast paths instead of eager evaluation.
- **#614 — Reduce unused vocabulary projections during Qwen prefill.**
- **#672 — Hidden states split from logit projection** (`HiddenStateLanguageModel`):
  callers can select positions before the vocabulary projection.
- **#675 — Gemma4 softcap fusion reused for text inference.**

### Correctness

- **#633 — GDN q/k L2-norm epsilon fix** (gated-delta-net family, incl.
  qwen3_5_moe — SimiGo's daily driver).
- **#650 — Cross-SIMD WHT read synchronization** (GDN recurrence).
- **#626 — Gemma tool calls keep nested object/array arguments** instead of
  collapsing them to raw strings — removes a known driver of client agent
  retry loops on Gemma models.
- **#642 — MTP weights dropped from converted Qwen3.5 VLM checkpoints**
  (memory no longer held for unused MTP layers).

### Dropped from the batch (incompatible with this vendor lineage)

- #670 (tokenizer flush) and #625 (tool-parser chunk scan) target files this
  lineage restructured away — porting is a separate task.
- #627 (Qwen3VL input splitting) requires porting media-slicing machinery
  (#603's Qwen3VL) that text-only SimiGo cannot exercise; reverted.
- #667's pick turned out test-only for this lineage.

## Verification

- Release build (vendor-changed, same fresh root as v2.1.2's pin audit):
  PASS (build 13).
- Vendor delta `e520e605..252f440b` = the audited picks plus the documented
  revert/extraction commits only.
- DMG `hdiutil verify` VALID; embedded app version 2.1.3 (13).
- Device expectations: qwen3_5_moe prefill (#614) and decode (eps/WHT fixes)
  rates; Gemma4 decode (softcap fusion) and tool-call argument fidelity;
  Swift-1.5 decode throughput (compiled decode) against v2.1.2's eager path.
