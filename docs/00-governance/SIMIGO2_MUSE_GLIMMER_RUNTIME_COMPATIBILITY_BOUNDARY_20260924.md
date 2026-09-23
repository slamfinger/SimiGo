# SimiGo 2.0 Muse-Glimmer Runtime Compatibility Boundary

**Date**: 2026-09-24  
**Status**: RUNTIME_LOAD_UNSUPPORTED / WHOLE_GROUP_RESIDENCY_NOT_APPLICABLE  
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

Current Qwen3-Coder-style partition therefore produced:

```text
CORE_NON_SWITCH     = 1,463 tensors / 17,603,109,888 bytes
SWITCH_MLP_L00_15   = 0 tensors
SWITCH_MLP_L16_31   = 0 tensors
SWITCH_MLP_L32_47   = 0 tensors
```

Even before runtime loading, this checkpoint has no evictable switch-MLP group for
the current SimiGo whole-group residency design.

## 2. Runtime probe

The Gate 4 command reached MLX Swift LM model loading and failed before inference:

```text
error: Unsupported model type: muse_glimmer_text
```

Therefore Gate 4 and Gate 5 were not run after the load failure.

## 3. Local mlx-swift-lm observation

The local `mlx-swift-lm` checkout is at `59e9abd`, branch
`exp/execution-state-fork`.

- `LLMModelFactory` has no `muse_glimmer_text` registration.
- `VLMModelFactory` registers `muse_glimmer` only, i.e. the full VLM implementation.
- The checkpoint is a text-only export with `model_type=muse_glimmer_text`, no
  vision tensors, and no top-level `architectures` field.
- The text language model inside the VLM implementation is private and is not
  exposed as a standalone factory-compatible text model.

Thus the user-visible boundary is: current SimiGo / MLX Swift LM text path does not
support this text-only checkpoint.

## 4. Conclusion

```text
runtimeTextInference         = UNSUPPORTED
simigoWholeGroupResidency    = NOT_APPLICABLE
reason                       = unsupported model type + no switch_mlp groups
performance claim            = NONE
```

Raw evidence:
docs/02-evidence/SIMIGO2_MUSE_GLIMMER_RUNTIME_BOUNDARY_20260924.json
