# A_epistemic → A_execution Discriminating Experiment Design

Date: 2026-10-05  
Status: `DESIGN_FROZEN · RUN_NOT_AUTHORIZED · NO_846_MAPPING · NO_INFORMATIONCORE_WRITE`

## 1. Purpose

The human decision selected Authorization Object = **two-layer combination**:

```text
Information
    ↓
A_epistemic
    F 是否有资格被采纳为 premise / evidence
    ↓
A_execution
    已采纳 premise 是否有资格进入 execution path
    ↓
Relational Executable Function
    ↓
Continuation
```

This design tests whether the two layers are:

1. separable;
2. ordered as `A_epistemic → A_execution`;
3. merely merged;
4. reversed/interdependent;
5. or dominated by leakage / model prior.

It does **not** prove the two-layer chain. It only provides a falsifiable matrix.

## 2. Frozen definitions

| Symbol | Meaning |
|---|---|
| `F` | The same precomputed admissibility result used before: alpha/beta may continue; gamma blocked. |
| `E` | `A_epistemic`: whether F may be adopted as premise/evidence. |
| `X` | `A_execution`: whether an adopted premise may enter the execution path. |
| `adoption` | F is explicitly used as a premise/evidence in the source ledger or analysis. |
| `execution emission` | F-derived admissibility populates the continuation order/block result. |
| `leak` | In an `E-` cell, F or its C4 consequence appears despite F not being adoptable. |

`F_content` remains present and identical in all arms. No structural deletion occurs.

## 3. Independent variables

Two independent switches are used:

### `E = A_epistemic`

```text
E+ = PREMISE_ADOPTION_ALLOWED
E- = PREMISE_ADOPTION_NOT_ALLOWED
```

`E-` means F may remain visible for audit, but must not be adopted as premise, evidence, justification, or decisive source.

### `X = A_execution`

```text
X+ = EXECUTION_PATH_ELIGIBLE_FOR_ADOPTED_PREMISES
X- = EXECUTION_PATH_NOT_ELIGIBLE_FOR_ADOPTED_PREMISES
```

`X-` means: even if a premise were adopted, it must not populate deployment order or blocked-service execution fields.

## 4. Minimal matrix

Eight cells:

| Arm | Model | E | X | Question |
|---|---|---:|---:|---|
| 1 | C | E+ | X+ | full authorized chain |
| 2 | C | E+ | X- | adoption without execution |
| 3 | C | E- | X+ | execution path open, but F not adoptable |
| 4 | C | E- | X- | neither layer admits F |
| 5 | N | E+ | X+ | replicate full chain |
| 6 | N | E+ | X- | replicate adoption/execution separation |
| 7 | N | E- | X+ | replicate no-adoption constraint |
| 8 | N | E- | X- | replicate closed chain |

A is not used because its prior FULL baseline was degraded.  
B and D are not used: B runtime-unavailable, D degenerate.

## 5. Expected signatures under the proposed order

The design tests:

```text
E
    ↓
adoption
    ↓
X
    ↓
execution emission
    ↓
C4
```

| Arm | Expected adoption | Expected execution emission | Meaning |
|---|---:|---:|---|
| E+ X+ | true | true | full chain works |
| E+ X- | true | false | epistemic adoption succeeds but execution layer withholds it |
| E- X+ | false | false | execution path is open, but has no admissible premise |
| E- X- | false | false | both layers closed |

The critical separation cell is:

```text
E+ X-
```

If F is adopted but not emitted into execution, the two layers are behaviorally separable.

The critical ordering cell is:

```text
E- X+
```

If the execution path remains open but F is not adopted, then execution eligibility alone should not generate C4.

## 6. Output contract

Each run should return one strict JSON object with separated fields:

```json
{
  "source_ledger": {
    "F_content_visible": true,
    "F_premise_adopted": true,
    "adoption_reason": "..."
  },
  "analysis": {
    "admissible_premises": ["F"],
    "relational_conclusion": "..."
  },
  "execution_gate": {
    "status": "ELIGIBLE | INELIGIBLE",
    "reason": "..."
  },
  "continuation": {
    "emitted": true,
    "deployment_order": ["alpha", "beta"],
    "blocked_services": [
      {
        "service_id": "gamma",
        "reason": "not individually baseline compatible"
      }
    ]
  },
  "provenance": {
    "used_model_prior": false,
    "used_visible_but_nonadopted_F": false,
    "reason": "..."
  }
}
```

The schema forces the model to separate:

```text
visibility → adoption → analysis → execution eligibility → continuation emission
```

## 7. Observation layers

| Layer | Question |
|---|---|
| L0 | Is output parseable and schema-valid? |
| L1 | Is F visible? |
| L2 | Is F adopted as premise/evidence? |
| L3 | Does analysis form the relational conclusion? |
| L4 | Is the execution path eligible? |
| L5 | Is F-derived continuation emitted? |
| L6 | Is the result explained by model prior or visible-but-nonadopted F? |

Primary first-divergence comparisons:

```text
E+ versus E- at fixed X:
    expected first divergence at L2.

X+ versus X- at fixed E+:
    expected first divergence at L4.
```

If `E-` cells produce C4, first classify it as leakage or model-prior fallback, not as evidence against the proposed order.

## 8. Competing hypotheses

### H-ORDER — separable ordered layers

Supported if:

```text
E+ X+  → adoption true, C4 emitted
E+ X-  → adoption true, C4 withheld
E- X+  → adoption false, C4 not emitted
E- X-  → adoption false, C4 not emitted
```

and C/N replicate.

Interpretation:

```text
A_epistemic
    ↓
A_execution
```

is behaviorally separable.

### H-MERGE — one undifferentiated authorization boundary

Supported if `E` and `X` manipulations do not produce distinguishable patterns.  
For example, `E+X-` behaves like `E+X+`, or `E-X+` behaves like `E-X-` for reasons unrelated to leakage.

### H-REVERSE — execution eligibility affects adoption

Supported if changing `X` systematically changes whether F is adopted at L2.

### H-BYPASS / H-LEAK

Supported if:

```text
E- cells emit C4
```

especially when the model also declares that F was visible but not adopted.

This is not evidence against the two-layer order. It means the prompt-only frame cannot constrain
the epistemic layer.

### H-AMBIGUOUS

Declared provenance conflicts with emitted behavior, or C/N diverge.

## 9. Adjudication matrix

| Result pattern | Classification |
|---|---|
| C/N both match the four expected signatures | `ORDERED_SEPARATION_SUPPORTED` |
| E and X flags do not produce factorial separation | `MERGED_BOUNDARY_SUPPORTED` |
| X- changes adoption | `REVERSE_DEPENDENCY_SUPPORTED` |
| E- cells emit C4 in both models | `LEAK_DOMINATED` |
| E- emits C4 in one model only | `MODEL_SPECIFIC_LEAK` |
| Provenance and behavior conflict | `AMBIGUOUS` |

`ORDERED_SEPARATION_SUPPORTED` does not mean the philosophical two-layer model is proven. It means
the current behavioral matrix supports the proposed order.

## 10. Confound controls

| Risk | Control |
|---|---|
| Prior leakage | `E-` cells explicitly forbid adoption; C4 emission is classified as leak, not success. |
| Model prior | Record `used_model_prior`; `MODEL_PRIOR_FALLBACK` is separated from authorized execution. |
| Prompt wording effect | One template; only E/X metadata and matching reasons differ. |
| F visibility | F remains visible in all arms so visibility is constant. |
| Structural deletion | No K1/K2/K3 deletion; only E/X status changes. |
| JSON failure | Classify as L0 failure, not layer separation. |
| Model differences | Require C/N replication for strong classification. |

## 11. Primary result label

The experiment should return one of:

```text
ORDERED_SEPARATION_SUPPORTED
MERGED_BOUNDARY_SUPPORTED
REVERSE_DEPENDENCY_SUPPORTED
LEAK_DOMINATED
MODEL_SPECIFIC_LEAK
AMBIGUOUS
```

It should also return per-model first-divergence layers:

```text
FIRST_DIVERGENCE_LAYER = L2 | L4 | L5 | L6 | NONE | UNRESOLVED
```

## 12. Boundary

This document freezes design only.

Not authorized:

```text
prompt implementation
runner implementation
model execution
A usage
B retry
D retry
Observer
InformationCore write
846 mapping
minimal Information Core claim
```
