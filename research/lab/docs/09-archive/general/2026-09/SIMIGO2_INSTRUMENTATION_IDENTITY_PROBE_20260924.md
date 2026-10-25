# SimiGo 2.0 Instrumentation Identity Probe — G1.9-B — 2026-09-24

> **ARCHIVED** 2026-10-20 · line: 通用治理 / 其他 · original: docs/00-governance/SIMIGO2_INSTRUMENTATION_IDENTITY_PROBE_20260924.md
> Evidence status: unchanged (content frozen; moved only)


Status: G1.9-B FIRST PROXY PASS / H_I_X NOT DEFINED  
Model: `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`  
Snapshot: `6e302ea604ad9ab206367e2c501d1571023e7b6d`  
Boundary: ISOLATED_IDENTITY_PROBE / SINGLE_PROXY_MODULE_POINT / NO DEMAND CLAIM

## Command

```bash
simigo2ctl instrument-audit MODEL_SNAPSHOT \
  --layers 0 \
  --prompt 'Return exactly one word: ping'
```

## Identity result

```text
status                         = PASS
modelType                      = Qwen3MoEModel
forwardExecuted                = true
observationPath                = model.layers.0.mlp.switch_mlp.down_proj
observationGranularity         = MLP_SWITCH_DOWN_PROJ_OUTPUT
output shape / dtype           = [1, 14, 151936] / bfloat16
baseline output checksum       = 640VhGBLIvdOdvjjCnztVxq1b7XbdO37kVs7FiPhwto=
instrumented output checksum   = 640VhGBLIvdOdvjjCnztVxq1b7XbdO37kVs7FiPhwto=
max absolute output difference = 0
```

The prompt token IDs were frozen by the checkpoint chat template:

```text
151644, 872, 198, 5598, 6896, 825, 3409, 25, 29998,
151645, 198, 151644, 77091, 198
```

Captured observation:

```text
shape       = [112, 1, 2048]
dtype       = bfloat16
checksum    = Y4WqUFGASYIQD86+4TXTybwmWxZ4xXY5CH4vtqnaJNY=
```

The shape is consistent with the fused MoE switch output before the public
model-level weighted reduction: 14 prompt tokens × top-8 experts, hidden size
2048. This records observed module granularity only. It does **not** decide that
Token × Expert is SimiGo's demand unit.

## Cost recording

```text
baseline forward             = 153.2795 ms
instrumented forward         = 342.6185 ms
capture/checksum time        = 13.7305 ms
peak memory overhead         = 4.5 MiB
capture overhead percentage  = NOT_ESTABLISHED
overheadEstablished          = false
```

The timing boundary is:

```text
RAW_TIMES_ONLY / SINGLE_CONTAINER_WARMUP_ASYMMETRY / OVERHEAD_NOT_ESTABLISHED
```

The first instrumented run is not comparable to the first baseline run because
graph/kernel warmup is asymmetric. A later probe must warm both paths before
timing comparison.

## Instrumentation boundary

The implementation replaces one selected leaf module with a subclass that calls
the original public module forward, records its output, and returns the same
tensor. For the quantized fused-MoE probe it preserves packed weight, bias,
scales, biases, group size, bit width, and quantization mode. It does not modify
MLX internals or the residency harness.

This observation point is a **proxy module output**, not decoder-layer boundary
`H_i(x)`. Therefore G1.9-C remains open. The successful identity check means
this instrumentation route is legal enough to continue; it does not define the
representation object, does not assert semantic importance, and does not
authorize ablation, unload, prediction, or demand analysis.

Raw report:

`simigo2-experimental/results/instrumentation-audits/qwen3-coder-layer0.json`
