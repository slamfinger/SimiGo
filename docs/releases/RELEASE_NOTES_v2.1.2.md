# SimiGo v2.1.2 — Composite VLM Checkpoint Support

Date: 2026-10-15  
Build: 12  
Tag: `v2.1.2`  
Platform: Apple Silicon macOS 26.4+  
Asset: `SimiGo-v2.1.2.dmg`

## Highlights

### New model support: composite VLM checkpoints load through the VLM factory

MLX conversions that carry a vision tower (`ForConditionalGeneration` layout
with `language_model.*` / `visual.*` weight prefixes) previously failed at
startup through the text-only loader:

- `ukisai/Swift-1.5-4bit-MLX` (Qwen3.5 VLM family, model_type `qwen3_5`) —
  failed with `Unhandled keys ["visual"]`.
- `mavis-ai/Gemma4-26B-MoE-Q5T` (model_type `gemma4`, MoE text config with
  `switch_glu` experts) — failed with
  `Key language_model...experts.switch_glu... not found`.

Both now route through the vendor's `VLMModelFactory`, whose registry already
implements `qwen3_5` and `gemma4` (vision tower loaded alongside; `Qwen3VL`
and `Gemma4` processors registered). SimiGo remains text-only at the protocol
level — the capability contract still reports `vision: unsupported`.

Routing is decided by **weight-key layout**, not by `architectures`:
`mavis-ai/Gemma4-26B-QAT-Q5` shares the same `Gemma4ForConditionalGeneration`
architecture and `gemma4` model_type but ships unprefixed text weights and
keeps its existing (working) text-factory path untouched. The check reads
`model.safetensors.index.json` (or the single-file safetensors header) before
loading; a `[MLX] loadRoute vlm=` trace line records the decision.

### Known boundaries (unchanged in this release)

- Vision inputs are not wired through the OpenAI-compatible protocol; these
  models serve text-only.
- The Gemma tool-call argument fix (upstream #626) and Qwen3.5 VLM compiled
  decode (upstream #662) remain in the vendor-refresh backlog — this release
  is load/serve support on the pinned vendor.

## Verification

- Fresh Release build: PASS (build 12).
- Binary contains the routing symbols (`VLMModelFactory` load path +
  `isCompositeVLMCheckpoint`); `loadRoute` trace string present.
- Load-path structural checks against the local checkpoints: Swift-1.5 index
  = 2379/2379 prefixed keys (routes VLM); dense QAT Q5 keys unprefixed
  (routes text, unchanged).
- First device load of both models happens on real hardware per standing
  hosted-test policy — watch for `[MLX] loadRoute vlm=true` followed by
  `NativeMLX ready` in `~/.simigo/logs/native_mlx_trace.log`.
- DMG `hdiutil verify` VALID; embedded app version 2.1.2 (12).
