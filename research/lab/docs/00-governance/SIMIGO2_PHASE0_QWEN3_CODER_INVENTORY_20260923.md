# SimiGo 2.0 Phase 0 Inventory — Qwen3-Coder

**Date**: 2026-09-23  
**Status**: PHASE_0_PARTIAL_REPORT / RUNTIME_PARTIAL_LOAD_TEST_PENDING  
**Model**: `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`

## 1. Scope

Read-only Safetensors index/header inventory for SimiGo 2.0 Experimental Phase 0.
No model weights were modified and no inference was executed.

## 2. Top-level inventory

```text
safetensor files       = 4
indexed tensors        = 1351
checkpoint size        = 16385 MiB / 16.00 GiB
```

## 3. Candidate MVP partition

Because Qwen3-Coder stores fused MoE weights as `mlp.switch_mlp` tensors, the first
legal MVP partition is by decoder-layer range, not by individual expert index.

| Group | Layer range | Contents | Tensors | Size |
| --- | ---: | --- | ---: | ---: |
| `CORE_NON_SWITCH` | all | embeddings, attention, norms, router, non-switch tensors, `lm_head` | 919 | 833 MiB |
| `SWITCH_MLP_L00_15` | 0–15 | fused MoE expert MLP tensors | 144 | 5184 MiB |
| `SWITCH_MLP_L16_31` | 16–31 | fused MoE expert MLP tensors | 144 | 5184 MiB |
| `SWITCH_MLP_L32_47` | 32–47 | fused MoE expert MLP tensors | 144 | 5184 MiB |
| **Total** | — | — | **1351** | **16385 MiB** |

## 4. Constraints

1. The checkpoint fuses each layer's 128 experts into stacked `switch_mlp` tensors.
   Therefore expert-index granularity would require repacking and is not a Phase 0
   implementation assumption.
2. A normal Transformer forward still traverses all decoder layers. Group residency
   means tensors are available when the forward needs them; it does not mean unused
   decoder layers can be skipped without changing model semantics.
3. The runtime adapter must either ensure all required groups are resident before a
   forward, or support legal lazy tensor loading during execution. This capability is
   still pending.

## 5. Candidate MVP policy

```text
CORE_NON_SWITCH       = always resident
SWITCH_MLP_L00_15     = policy-selected
SWITCH_MLP_L16_31     = policy-selected
SWITCH_MLP_L32_47     = policy-selected
```

Initial deterministic labels may map:

```text
STATE_A  → CORE + L00_15
STATE_B  → CORE + L16_31
STATE_C  → CORE + L32_47
STATE_AB → CORE + L00_31
STATE_ALL→ CORE + all switch groups
```

These labels are experimental workload labels, not model-semantic claims.

## 6. Next gate

Before Phase 1 implementation, answer:

```text
Can the selected runtime construct a model whose switch-MLP tensors are
loaded, released, or lazily materialized by group without invasive
model-internal changes?
```

If no, Phase 1 must use a residency simulator rather than real inference.
