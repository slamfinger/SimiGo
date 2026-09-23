# SimiGo 2.0 Phase 0 — MLX Whole-Group Inference Residency Gate 4 Results

**Date**: 2026-09-24  
**Status**: GATE_4_WHOLE_GROUP_INFERENCE_RESIDENCY_PASS / MULTI_STATE_BENCHMARK_PENDING  
**Model**: `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`  
**Execution state**: `STATE_A`  
**Group**: `SWITCH_MLP_L00_15`

## 1. Gate

The state policy selected one optional group. A real MLX model then ran the
following cycle:

```text
all-resident baseline inference
→ release all 144 group tensors from the model object
→ observe MLX active memory
→ rematerialize the group from Safetensors into the model object
→ observe MLX active memory
→ run inference again
→ compare deterministic output
```

The group was released only between generations. It was fully rematerialized
before the restored inference; no semantic layer skipping occurred.

## 2. Result

```text
released tensors                  = 144 / 144
rematerialized tensors            = 144 / 144
group byte count                  = 5,435,817,984
baseline output                   = pong
restored output                   = pong
outputEquals                      = true
release time                      = 16.85 ms
rematerialization time            = 606.10 ms
baseline generation time          = 1,060.46 ms
restored generation time          = 368.58 ms
```

MLX memory samples:

| Phase | Active bytes | Cache bytes |
| --- | ---: | ---: |
| after baseline | 17,180,952,624 | 0 |
| after release | 11,745,135,024 | 0 |
| after rematerialization | 17,180,952,624 | 0 |
| after restored generation | 17,180,952,624 | 0 |

Active memory dropped by exactly 5,435,817,600 bytes after release and returned
to the baseline level after rematerialization.

## 3. Interpretation

This is the first end-to-end runtime evidence that a selected fused MoE group can
be detached from a real model object, rematerialized from checkpoint storage, and
used again with identical deterministic output. It therefore crosses the prior
boundary left open by Gate 2 and Gate 3.

The generation-time difference is not treated as a policy benefit claim: the
baseline includes cold-start effects and the restored run is warm. Peak memory in
this one-cycle probe remains the all-resident baseline peak.

## 4. Boundary

This single-state gate proves feasibility for one optional group. It does not yet
establish that a full `STATE_A → STATE_B → ...` execution-state workload reduces
peak residency or total reload cost while preserving output identity. That
requires the multi-state real-runtime benchmark and comparison against
all-resident and reactive policies.
