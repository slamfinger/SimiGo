# SimiGo 2.0 Nail-Qwen3.6 Real-Device Validation

**Date**: 2026-09-24  
**Status**: SINGLE_GROUP_INFERENCE_PASS / MULTI_STATE_APP_PROOF_PASS / LATENCY_ADVANTAGE_NOT_ESTABLISHED  
**Device**: Apple M5, arm64, macOS 26.6.2 (25G83), 34,359,738,368 bytes physical memory  
**Model**: `peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX`  
**Snapshot**: `31a0106483c94e9fbb0a6d3360ff122d47377058`

## 1. Inventory

```text
CORE_NON_SWITCH     = 1,570 tensors / 3,515,345,632 bytes
SWITCH_MLP_L00_15   =   144 tensors / 7,247,757,312 bytes
SWITCH_MLP_L16_31   =   144 tensors / 7,247,757,312 bytes
SWITCH_MLP_L32_47   =    72 tensors / 3,623,878,656 bytes
total               = 1,930 tensors / 21,634,738,912 bytes
```

## 2. Gate 4 single-group inference

For `STATE_A → SWITCH_MLP_L00_15`:

```text
released / rematerialized tensors = 144 / 144
baseline output                   = restored output
outputEquals                      = true
groupInferenceResidencyPass       = true
active after baseline             = 20,742,340,808 bytes
active after release              = 13,494,583,880 bytes
active after rematerialization    = 20,742,340,808 bytes
release time                      = 19.98 ms
rematerialization time            = 977.63 ms
```

## 3. Gate 5 app self-test

Ran the installed local SwiftUI app bundle in self-test mode across:

```text
STATE_A → STATE_B → STATE_AB → STATE_A → STATE_ALL
```

```text
exit code                       = 0
self-test                       = PASS
benchmarkPass                   = true
outputIdentityPass              = true
idleReductionObserved           = true
maximum idle reduction          = 10,871,635,392 bytes
reload reduction vs naive       = 18,119,393,280 bytes
all generation outputs          = identical
```

Policy totals:

| Metric | ALL_RESIDENT | NAIVE_ON_DEMAND | EXECUTION_STATE |
| --- | ---: | ---: | ---: |
| generation total | 11,111.07 ms | 10,849.25 ms | 12,193.26 ms |
| reload bytes | 0 | 72,477,573,120 | 54,358,179,840 |
| release bytes | 0 | 90,596,966,400 | 36,238,786,560 |
| reload time | 0 ms | 11,675.80 ms | 10,394.22 ms |
| release time | 0 ms | 223.76 ms | 101.10 ms |

## 4. Boundary

This validates the model on the existing whole-switch-MLP group boundary. It does
not claim expert-level residency, latency optimization, or production readiness.
Complete inference still traverses all required groups; execution-state controls
idle retention only.

Raw Gate 5 evidence:
docs/02-evidence/SIMIGO2_NAIL_QWEN36_APP_REAL_DEVICE_PROOF_20260924.json
