# SimiGo 2.0 Gemma4 Residency Compatibility Boundary

**Date**: 2026-09-24  
**Status**: TEXT_INFERENCE_PASS / WHOLE_GROUP_RESIDENCY_NOT_APPLICABLE / SIMIGO_GROUP_SUPPORT_INCOMPLETE  
**Device**: Apple M5, arm64, macOS 26.6.2 (25G83), 34,359,738,368 bytes physical memory  
**Model**: `mlx-community/gemma-4-12b-coder-fable5-composer2.5-4bit`  
**Snapshot**: `6b82053fa694ac4f1a0069f27ab71f1ab0cd7fff`  
**Architecture**: `Gemma4UnifiedForConditionalGeneration` / `gemma4_unified`  
**Local runtime**: `mlx-swift-lm @ 59e9abd`, branch `exp/execution-state-fork`

## 1. Inventory

Current Qwen3-Coder group catalog produced:

```text
CORE_NON_SWITCH     = 1,324 tensors / 6,698,991,200 bytes
SWITCH_MLP_L00_15   =     0 tensors / 0 bytes
SWITCH_MLP_L16_31   =     0 tensors / 0 bytes
SWITCH_MLP_L32_47   =     0 tensors / 0 bytes
total               = 1,324 tensors / 6,698,991,200 bytes
```

The checkpoint has dense `mlp.gate_proj`, `mlp.up_proj`, and `mlp.down_proj`
tensors, but no `switch_mlp` tensors. Therefore the current SimiGo residency
partition has no evictable whole group.

## 2. Gate 4 observation

The model did load and generate through the current MLX Swift LM text path:

```text
baselineOutput                 = ping
restoredOutput                 = ping
outputEquals                   = true
releasedTensorCount            = 0
rematerializedTensorCount      = 0
groupInferenceResidencyPass    = false
active memory after baseline   = 6,701,423,370 bytes
active memory after release    = 6,701,423,370 bytes
active memory after remat      = 6,701,423,370 bytes
```

This is the expected result for a checkpoint without switch-MLP groups: the model
is executable, but there is no group for the current residency gate to release.

## 3. Gate 5 app self-test observation

For `STATE_A → STATE_B → STATE_AB → STATE_A → STATE_ALL`:

```text
exit code                          = 0
all generation outputs             = ping
outputIdentityPass                 = true
residencyBenchmarkPass             = false
benchmarkPass                      = false
idleReductionObserved              = false
reloadReductionVsNaiveObserved     = false
cumulative reload / release bytes  = 0
```

After this boundary finding, the app self-test verdict was corrected to
`self-test: RESIDENCY_COMPATIBILITY_BOUNDARY; benchmarkPass=false`. It no longer
reports a generic PASS when the residency benchmark cannot establish benefit.

## 4. Conclusion

Two distinct facts must be kept separate:

1. `mlx-swift-lm` text inference for this `gemma4_unified` checkpoint works in the
   tested local runtime.
2. SimiGo 2.0's current execution-state residency design does **not** support this
   model. It requires switch-MLP tensors and a model-specific evictable group
   catalog; Gemma4 provides neither under the current Qwen3-Coder partition.

No group-residency success or performance claim is allowed for this checkpoint.

Raw Gate 5 evidence:
docs/02-evidence/SIMIGO2_GEMMA4_APP_REAL_DEVICE_BOUNDARY_20260924.json
