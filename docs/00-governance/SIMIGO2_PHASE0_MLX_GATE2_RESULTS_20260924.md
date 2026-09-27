# SimiGo 2.0 Phase 0 — MLX Group Gate 2 Results

**Date**: 2026-09-24  
**Status**: GATE_2_PASS_AT_FINGERPRINT_LEVEL / MODEL_PARAMETER_SWAP_PENDING  
**Group**: `SWITCH_MLP_L00_15`  
**Model**: `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`

## 1. Gate

Verify independent MLX array-group lifecycle:

```text
initial materialization
→ release references and clear MLX cache
→ rematerialize from checkpoint
→ compare semantic fingerprints
```

## 2. Result

```text
groupID                     = SWITCH_MLP_L00_15
tensorCount                 = 144
byteCount                   = 5,435,817,984
initial load                = 177.78 ms
release                     = active/cache dropped to 0 bytes
rematerialization           = 166.49 ms
rematerialized tensors      = 144
rematerialized bytes        = 5,435,817,984
lifecyclePass               = true
```

Memory:

| Phase | Active | Cache | Peak |
| --- | ---: | ---: | ---: |
| after initial load | 5,435,817,984 | 0 | 5,435,817,984 |
| after release | 0 | 0 | unchanged historical peak |
| after rematerialize | 5,435,817,984 | 0 | unchanged historical peak |

## 3. Semantic fingerprint check

The probe compared dtype/shape/sum/min/max fingerprints for all 144 tensors:

```text
semanticEqualCount    = 144
semanticMismatchCount = 0
```

This is fingerprint-level consistency for rematerialized storage. It is stronger
than byte-count-only evidence, but not yet full end-to-end inference-output
consistency.

## 4. Conclusion

Gate 2 passes at group-array lifecycle level: a selected group can be released and
rematerialized without retaining the earlier MLX arrays. This does not yet prove
that an MLX model object can externally replace or release those modules during
inference.

Gate 3, real model parameter swap and inference semantic consistency, remains
pending.
