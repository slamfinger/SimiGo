# SimiGo v2.1.6 — Text-First Model Loading (Nail Regression Fix)

Date: 2026-10-15  
Build: 16  
Tag: `v2.1.6`  
Platform: Apple Silicon macOS 26.4+  
Asset: `SimiGo-v2.1.6.dmg`

## The regression

v2.1.2's composite-VLM routing ("prefixed weight keys → VLM factory") broke
`peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX` — the user's daily driver: its
checkpoint is fully prefixed (`language_model.*`, 1930/1930 keys, vision
tower intact) but its `model_type` (`qwen3_5_moe`) is registered in **both**
factories, and the text stack had served it for weeks. Direct routing into
the VLM stack failed at startup ("The data couldn't be read because it is
missing."). Model cache verified intact (all 5 shards + index live).

## The fix

`loadModelContainer` now goes **text-first**: every model attempts the
text factory (the lineage-proven path); only when that fails **and** the
checkpoint is a composite VLM layout does it clear the MLX cache and fall
back to `VLMModelFactory`. If both paths fail, the error carries both
messages. Routing is self-maintaining — no registry allowlists.

Per-model outcome:

- **Nail-Qwen3.6 (qwen3_5_moe)** — text path first try: **fixed**.
- **Gemma4-26B-QAT-Q5 dense** — back to its pre-v2.1.2 text path (proven
  Oct 13-14); the VLM path also worked, text was always sufficient.
- **Gemma4-26B-MoE / VLM-only types** — text attempt fails at weight-name
  validation (~15s), then the VLM fallback engages.
- Plain text models — unchanged.

## Verification

- Release build: PASS (build 16).
- DMG `hdiutil verify` VALID; embedded app version 2.1.6 (16).
- Device check: switch to Nail — expect `NativeMLX ready` on first attempt
  (log line `[MLX] loadRoute text-first composite=true`), resident ~19.7GB,
  first generation `mode=cold` then warm extend on follow-ups.
