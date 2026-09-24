# SimiGo 2.0 Dense MLP Residency Extension

**Date**: 2026-09-24
**Status**: EXTENSION_IMPLEMENTED / GEMMA4_GATE4_PASS / GEMMA4_GATE5_PASS / MUSE_GLIMMER_GATE4_PASS / SEMANTIC_QUALITY_UNRESOLVED
**Device**: Apple M5, arm64, macOS 26.6.2 (25G83), 34,359,738,368 bytes physical memory

## 1. Extension

Extend execution-state residency beyond fused `switch_mlp` with a dense-MLP group
catalog:

```text
CORE_NON_SWITCH      = embeddings, attention, norms, non-MLP tensors
DENSE_MLP_L00_15     = dense mlp.* tensors in contiguous layer range
DENSE_MLP_L16_31     = dense mlp.* tensors in contiguous layer range
DENSE_MLP_L32_47     = dense mlp.* tensors in contiguous layer range
```

The inventory now recognizes `gemma4_unified` and `muse_glimmer_text`, reads the
text layer count, and dynamically creates three contiguous dense-MLP groups. A
`ContiguousLayerStatePolicy` maps execution states to the ordered groups.

The idle-memory discrepancy was traced to the dense Gate 5 using hard-coded
switch-MLP group matching. The benchmark matched zero dense tensors, so release
was metadata-only. The fix adds dense-range matching and uses a direct model
generation path so ChatSession prompt-cache lifetime cannot be confused with
model-parameter residency.

## 2. Gemma4 dense validation

Inventory:

```text
CORE_NON_SWITCH     = 892 tensors / 1,921,416,800 bytes
DENSE_MLP_L00_15    = 144 tensors / 1,592,524,800 bytes
DENSE_MLP_L16_31    = 144 tensors / 1,592,524,800 bytes
DENSE_MLP_L32_47    = 144 tensors / 1,592,524,800 bytes
```

Gate 4:

```text
released / rematerialized tensors = 144 / 144
outputEquals                      = true
active memory after baseline      = 6,701,423,370 bytes
active memory after release       = 5,108,112,522 bytes
active memory after rematerialize = 6,701,423,370 bytes
groupInferenceResidencyPass       = true
```

Gate 5:

```text
benchmarkPass                    = true
outputIdentityPass               = true
idleReductionObserved            = true
maximum idle reduction           = 3,186,621,696 bytes
reloadReductionVsNaiveObserved   = true
reload reduction vs naive        = 3,185,049,600 bytes
```

This establishes dense-model residency feasibility.

## 3. Muse-Glimmer dense validation

After adding text runtime support, inventory partitions into:

```text
CORE_NON_SWITCH     = 995 tensors / 4,644,676,608 bytes
DENSE_MLP_L00_17    = 162 tensors / 4,485,611,520 bytes
DENSE_MLP_L18_35    = 162 tensors / 4,485,611,520 bytes
DENSE_MLP_L36_51    = 144 tensors / 3,987,210,240 bytes
```

Gate 4:

```text
released / rematerialized tensors = 162 / 162
outputEquals                      = true
active memory after baseline      = 17,604,890,160 bytes
active memory after release       = 13,119,279,072 bytes
active memory after rematerialize = 17,604,890,160 bytes
groupInferenceResidencyPass       = true
```

Gate 5:

```text
benchmarkPass                    = true
outputIdentityPass               = true
idleReductionObserved            = true
maximum idle reduction           = 8,472,820,944 bytes
reloadReductionVsNaiveObserved   = true
reload reduction vs naive        = 9,469,624,320 bytes
```

## 4. Boundary

The model outputs under the no-chat-template deterministic probe are repeated
token sequences, so this is not a semantic-quality or product-readiness claim.
The extension proves physical dense-group residency mechanics and multi-state
execution-state feasibility only.

Raw evidence:
- docs/02-evidence/SIMIGO2_DENSE_MLP_GEMMA4_GATE5_20260924.json
- docs/02-evidence/SIMIGO2_DENSE_MLP_MUSE_GATE5_20260924.json
