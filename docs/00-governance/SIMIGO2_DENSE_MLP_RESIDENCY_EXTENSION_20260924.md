# SimiGo 2.0 Dense MLP Residency Extension

**Date**: 2026-09-24  
**Status**: EXTENSION_STARTED / DENSE_GATE4_PASS / MULTI_STATE_IDLE_MEMORY_UNRESOLVED  
**Models probed**:  
- `mlx-community/gemma-4-12b-coder-fable5-composer2.5-4bit`  
- `OpensourceWTF/Muse-Glimmer-30B-MLX-q4` (runtime support prerequisite completed separately)

## 1. Extension

Extend execution-state residency beyond fused `switch_mlp` by adding a dense-MLP
group catalog:

```text
CORE_NON_SWITCH      = embeddings, attention, norms, non-MLP tensors
DENSE_MLP_L00_15     = dense mlp.* tensors in layer range
DENSE_MLP_L16_31     = dense mlp.* tensors in layer range
DENSE_MLP_L32_47     = dense mlp.* tensors in layer range
```

The catalog derives layer ranges from `model_type` and `num_hidden_layers`. It now
recognizes `gemma4_unified` and `muse_glimmer_text` as dense candidates. A
`ContiguousLayerStatePolicy` maps the six execution-state labels onto available
contiguous groups.

## 2. Gemma4 inventory

```text
CORE_NON_SWITCH     = 892 tensors / 1,921,416,800 bytes
DENSE_MLP_L00_15    = 144 tensors / 1,592,524,800 bytes
DENSE_MLP_L16_31    = 144 tensors / 1,592,524,800 bytes
DENSE_MLP_L32_47    = 144 tensors / 1,592,524,800 bytes
total               = 1,324 tensors / 6,698,991,200 bytes
```

## 3. Gemma4 Gate 4

`STATE_A → DENSE_MLP_L00_15`:

```text
released / rematerialized tensors = 144 / 144
baseline output                   = ping
restored output                   = ping
outputEquals                      = true
groupInferenceResidencyPass       = true
active memory after baseline      = 6,701,423,370 bytes
active memory after release       = 5,108,112,522 bytes
active memory after rematerialize = 6,701,423,370 bytes
release time                      = 11.84 ms
rematerialization time            = 74.34 ms
```

This is the first successful dense-model Gate 4. It proves dense MLP tensors can
be externally detached and rematerialized around real MLX inference.

## 4. Multi-state benchmark observation

The dense Gate 5 run produced identical outputs across all policies and showed a
reload-byte reduction for execution-state retention versus naive on-demand:

```text
outputIdentityPass              = true
reloadReductionVsNaiveObserved  = true
reloadReductionVsNaiveBytes     = 3,185,049,600
idleReductionObserved           = false
benchmarkPass                   = false
```

The first Gate 4 proves physical group detachment, but the benchmark's idle-memory
measurement did not yet show the expected drop after release. This is now the
blocking issue for declaring dense multi-state success. It should not be
reinterpretated as a performance win.

## 5. Next hard gate

Fix or explain the idle-memory measurement discrepancy, then rerun the full dense
Gate 5. Only then register dense-model residency as benchmark-pass.
