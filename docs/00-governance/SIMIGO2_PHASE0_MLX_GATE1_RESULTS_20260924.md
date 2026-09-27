# SimiGo 2.0 Phase 0 — MLX Group Gate 1 Results

**Date**: 2026-09-24  
**Status**: GATE_1_PASS / GROUP_LIFECYCLE_AND_INFERENCE_STILL_PENDING  
**Model**: `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`

## 1. Gate

Verify that selected Safetensors tensors in a layer group can be materialized as
real MLX arrays without loading unrelated groups.

MLX's Safetensors loader is lazy. The probe filters tensor names before
evaluation, so only selected tensor ranges should be materialized.

## 2. Results

| Group | Files | Tensors | Bytes | Elapsed ms | Throughput MiB/s |
| --- | ---: | ---: | ---: | ---: | ---: |
| `CORE_NON_SWITCH` | 4 | 919 | 873,459,712 | 167.01 | 4,987.84 |
| `SWITCH_MLP_L00_15` | 2 | 144 | 5,435,817,984 | 782.72 | 6,623.10 |

Both groups decoded into real MLX arrays with expected dtypes and shapes. The
probe cleared MLX cache afterward and did not retain the 5+ GiB groups.

## 3. Conclusion

```text
Gate 1 selective tensor materialization = PASS
Group lifecycle                         = PENDING
Semantic consistency                    = PENDING
```

This validates the first hard gate. It does not yet prove that a model object can
independently release or restore these groups during inference.
