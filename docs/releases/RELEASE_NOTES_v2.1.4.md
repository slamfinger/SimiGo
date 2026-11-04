# SimiGo v2.1.4 — Swift-1.5 Vision-Tower Prefix Fix

Date: 2026-10-15  
Build: 14  
Tag: `v2.1.4`  
Platform: Apple Silicon macOS 26.4+  
Asset: `SimiGo-v2.1.4.dmg`

## Highlights

### Fixes `ukisai/Swift-1.5-4bit-MLX` load failure introduced by v2.1.2's routing

v2.1.2 correctly routed the checkpoint into the VLM factory, but the load
then failed with `Key vision_tower...linear_fc2.bias not found`: this
conversion keeps HF-style **`visual.*`** paths for the vision tower, while
the model mounts it at **`vision_tower.*`** — and the MLX-format early
return in `Qwen35.sanitize` skipped prefix mapping entirely (the general
path only knew `model.visual.*`).

The vendor patch (`c3057c58`) normalizes the bare `visual.` prefix in both
sanitize branches. Module-level key shapes were verified against the
checkpoint before patching: `blocks.N.mlp.linear_fc1/fc2` (with bias),
`merger`, `patch_embed.proj`, `pos_embed` all match; the rotary embedding
carries no weights and the checkpoint's `deepstack_visual_indexes` is empty.

Vendor pin `252f440b` → `c3057c58` (single fix commit; everything else
identical to v2.1.3).

## Verification

- Release build: PASS (build 14).
- Structural dry-run against the local checkpoint index: post-mapping key
  set matches the model's vision mounts; text side already aligned
  (`language_model.*`).
- DMG `hdiutil verify` VALID; embedded app version 2.1.4 (14).
- Device check: switch to Swift-1.5 and expect `[MLX] loadRoute vlm=true`
  → `NativeMLX ready` (first load pulls ~16-18 GB; give it a minute).
