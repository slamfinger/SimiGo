# SimiGo 2.0 Muse-Glimmer Runtime Support Note

**Date**: 2026-09-24
**Status**: TEXT_RUNTIME_SUPPORT_ADDED / WHOLE_GROUP_RESIDENCY_NOT_APPLICABLE / OUTPUT_QUALITY_UNRESOLVED
**Device**: Apple M5, arm64, macOS 26.6.2 (25G83), 34,359,738,368 bytes physical memory
**Model**: `OpensourceWTF/Muse-Glimmer-30B-MLX-q4`
**Snapshot**: `e1c987b60874388e68621c71b680643b1cb0ce03`
**Model type**: `muse_glimmer_text`

## 1. Checkpoint and inventory

```text
checkpoint bytes         = 17,603,109,888
parameters               = 27,854,780,928
tensors                  = 1,463
switch_mlp tensors       = 0
vision tensors           = 0
```

Current Qwen3-Coder-style partition produced:

```text
CORE_NON_SWITCH     = 1,463 tensors / 17,603,109,888 bytes
SWITCH_MLP_L00_15   = 0 tensors
SWITCH_MLP_L16_31   = 0 tensors
SWITCH_MLP_L32_47   = 0 tensors
```

The checkpoint has no evictable switch-MLP group for the current SimiGo
whole-group residency design.

## 2. Borrowed support

The upstream Python `mlx-lm` repository implements the Muse-Glimmer language tower
directly and strips/renames vision keys in `sanitize`. The local Swift fork now
borrows that approach:

- add `MuseGlimmerTextLLMConfiguration`;
- add a standalone dense text model with gated attention, QK norm, NoPE/full
  layers, sliding-window cache, centered RMS norms, output multiplier, and logit
  softcapping;
- register `muse_glimmer_text` with `LLMModelFactory`.

The local Swift fork commit is `4ff8c19`.

## 3. Runtime result

Gate 4 now loads the checkpoint and completes two generations:

```text
load / forward              = PASS
baselineOutput              = "uk...uk" (24 tokens)
restoredOutput              = same repeated token sequence
outputEquals                = true
active memory after load    = 17,604,890,160 bytes
peak memory                 = 17,634,220,738 bytes
switch group tensors        = 0
groupInferenceResidencyPass = false
```

The test prompt has no chat template. The repeated-token output shows that runtime
execution is not yet sufficient evidence for semantic quality. Upstream Python
`mlx-lm` produced newline-dominated output for the same prompt, so further
numerical / decoding comparison is required.

## 4. Conclusion

```text
runtimeLoadAndForward        = PASS
semanticQuality              = UNRESOLVED
simigoWholeGroupResidency    = NOT_APPLICABLE
reason                       = no switch_mlp groups
performance claim            = NONE
```

Raw evidence:
docs/02-evidence/SIMIGO2_MUSE_GLIMMER_RUNTIME_BOUNDARY_20260924.json
