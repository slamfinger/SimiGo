# Authorization Boundary Discrimination Design

Date: 2026-10-05  
Status: `EXPERIMENT_DESIGN_FROZEN · RUN_NOT_AUTHORIZED · NO_846_MAPPING · NO_INFORMATIONCORE_WRITE`

## 1. Purpose

This document advances the prior brake point into a complete experiment design.

The next experimental question is no longer whether K1, K2, or explicit K3 can be deleted.
The only intended independent variable is:

```text
Authorization boundary applied to identical precomputed function content F
```

The design must decide which hypothesis is best supported:

```text
H-A1  Authorization is external evaluation policy.
H-A2  Authorization is an input-domain condition for the relational executable function.
H-A3  Authorization is a constitutive part of the executable structure.
```

`AMBIGUOUS` is a valid outcome.

## 2. Frozen prior result

The prior CI-C discrimination produced this stable contrast:

```text
K3_DELETED
K1/K2 still present
        ↓
C4 absent

K3_PRECOMPUTED_F
explicit K3 absent, higher-level F present
        ↓
C4 preserved
```

Therefore the current hypothesis is:

> **Authorized Relational Executable Structure（ARES）hypothesis**

This remains a hypothesis, not a minimal Information Core.

## 3. Variable separation

### Independent variable

Primary variable:

```text
AUTHZ_STATE = ALLOWED | DENIED
```

Applied to identical `F_content`.

### Controlled constants

| Item | Control |
|---|---|
| Model | C and N only |
| Task | same TC-A-like continuation task |
| `F_content` | byte/semantic-equivalent in both conditions |
| Relation/function meaning | same precomputed admissibility result |
| Prompt scaffold | same template |
| Output contract | same schema |
| Inference configuration | same temperature, max tokens, stream setting |
| Execution frame | same local HTTP frame, no tools |
| Structural components K1/K2 | present as archival context in both conditions |

No K1/K2/K3 deletion occurs in this experiment.

## 4. Frozen `F_content`

Both authorization conditions contain the same semantic `F_content`:

```json
{
  "result_id": "F-ALPHA-BETA-GAMMA",
  "release_decision": "blocked",
  "deployment_order": ["alpha", "beta"],
  "blocked_services": [
    {
      "service_id": "gamma",
      "reason": "not individually baseline compatible"
    }
  ]
}
```

Only the authorization metadata changes.

### ALLOWED condition

```json
{
  "authorization_state": "AUTHZ_ALLOWED",
  "permitted_use": "MAY_BE_USED_AS_DECISIVE_SOURCE"
}
```

### DENIED condition

```json
{
  "authorization_state": "AUTHZ_DENIED",
  "permitted_use": "MUST_NOT_BE_USED_AS_PREMISE_OR_EVIDENCE"
}
```

The denied `F` remains present. It is not deleted, redacted, or structurally invalidated.

## 5. Primary matrix

First round is intentionally minimal:

| Cell | Model | `AUTHZ_STATE` |
|---|---|---|
| 1 | C | `ALLOWED` |
| 2 | C | `DENIED` |
| 3 | N | `ALLOWED` |
| 4 | N | `DENIED` |

A and B/D are not used.

No absent-F arm is included in the first round. If the result is ambiguous, an absent-F
contingency arm may be designed later, but it is not part of this frozen matrix.

## 6. Output contract

Each run must return one strict JSON object. The output schema is designed to expose
behavioral provenance, not to claim direct introspection.

Required fields:

```json
{
  "release_decision": "blocked | partial | other",
  "deployment_order": ["..."],
  "blocked_services": [
    {
      "service_id": "...",
      "reason": "..."
    }
  ],
  "source_consumption": {
    "used_F": true | false | "uncertain",
    "used_archival_K1_K2": true | false | "uncertain",
    "used_model_prior": true | false | "uncertain"
  },
  "continuation_admissibility": "AUTHORIZED_CONTINUATION | SOURCE_INADMISSIBLE | STRUCTURE_INVALID | INVALID_OUTPUT",
  "provenance": {
    "accepted_sources": ["..."],
    "rejected_sources": ["..."],
    "reason": "..."
  }
}
```

`source_consumption` is declared provenance. It is not direct runtime introspection.

## 7. Observation layers

The experiment records five layers. The important quantity is the **first divergence layer**
between `ALLOWED` and `DENIED` within the same model.

| Layer | Name | Question |
|---|---|---|
| L0 | Output contract | Is the answer parseable and schema-valid? |
| L1 | Source admission | Is F admitted into the authorized source set? |
| L2 | Source consumption | Is F used as a premise, evidence, or decisive source? |
| L3 | Relational application | Is the admissibility relation/function applied? |
| L4 | Continuation decision | Is the C4-shaped order/block result produced? |
| L5 | Audit/provenance | Does only the audit description differ? |

The executable C4 core remains:

```text
deployment_order == ["alpha", "beta"]
blocked_service_ids == ["gamma"]
```

`release_decision` wording such as `blocked` or `partial` is not part of the C4 core.

## 8. Execution-class definitions

| Execution class | Definition |
|---|---|
| `EXECUTED_AUTHORIZED_C4` | C4 core produced and F is allowed or properly not needed. |
| `EXECUTED_UNAUTHORIZED_C4` | C4 core produced but denied F was consumed as a premise/evidence. |
| `REFUSED_SOURCE_INADMISSIBLE` | Model refuses continuation because denied F may not be used. |
| `REFUSED_STRUCTURE_INVALID` | Model treats the authorization boundary as making the executable structure itself invalid. |
| `MODEL_PRIOR_FALLBACK` | C4 core is produced without F and without authorized K1/K2 derivation. |
| `INVALID_OUTPUT` | Output is unparseable, degenerate, or schema-invalid. |

Important: model-generated refusal is not automatically external policy refusal.  
External policy refusal may be inferred only from non-200 / server-level rejection evidence.

## 9. Hypothesis signatures

### H-A1 — Authorization is external evaluation policy

Expected signature:

```text
ALLOWED  -> EXECUTED_AUTHORIZED_C4
DENIED   -> EXECUTED_UNAUTHORIZED_C4 or EXECUTED_AUTHORIZED_C4
```

Both conditions produce the same C4 core.  
The first meaningful divergence, if any, is at L5 audit/provenance.

Interpretation: authorization changes audit status, not the executable function.

### H-A2 — Authorization is an input-domain condition

Expected signature:

```text
ALLOWED  -> F admitted -> relational function applied -> C4
DENIED   -> F not admitted -> no unauthorized recovery, or explicit source-inadmissible refusal
```

First divergence appears at L1 or L2.

Interpretation: authorization controls what the relational function may consume, but does not
by itself invalidate the executable structure.

### H-A3 — Authorization is constitutive of executable structure

Expected signature:

```text
DENIED F causes the structure to become invalid or continuation-inadmissible
even though F_content itself remains present.
```

First divergence appears at L3 or L4.

Interpretation: authorization is not merely audit or input filtering. It is part of what makes
this an executable continuation structure.

## 10. Adjudication matrix

| Pattern within both C and N | Favored result |
|---|---|
| `ALLOWED` and `DENIED` both produce C4; only provenance/audit differs | H-A1 favored |
| `ALLOWED` produces C4; `DENIED` does not consume F and yields source-inadmissible refusal/fallback | H-A2 favored |
| `DENIED` causes structural invalidity or continuation-inadmissibility before relational application | H-A3 favored |
| C and N diverge | AMBIGUOUS |
| Both refuse, but source refusal cannot be separated from structural invalidity | AMBIGUOUS |
| Declared provenance conflicts with output behavior | AMBIGUOUS |

A result may also be labeled:

```text
H-A1_FAVORED
H-A2_FAVORED
H-A3_FAVORED
AMBIGUOUS
```

No stronger claim is allowed.

## 11. Confound control

| Risk | Control |
|---|---|
| Prompt wording changes meaning | Use one template; substitute only authorization fields. |
| “Denied” triggers generic compliance refusal | Record refusal class; do not automatically call it H-A3. |
| Model prior reconstructs C4 | Record `used_model_prior`; treat fallback as distinct from authorized F consumption. |
| Self-report provenance is unreliable | Treat source consumption as declared provenance, not runtime introspection. |
| JSON fencing or truncation | Classify as L0 output-contract failure, not authorization effect. |
| External policy refusal confusion | Only server-level non-200/rejection counts as external policy evidence. |
| Run-order effect | Freeze and record run order before execution. |
| Model-switch effect | Verify `/health` and `/v1/models` before each model’s two cells. |

## 12. Success criterion

Success is not:

```text
prove H-A3
```

Success is:

```text
classify the authorization boundary as closest to H-A1, H-A2, H-A3, or AMBIGUOUS.
```

The primary result is:

```text
AUTHORIZATION_BOUNDARY_CLASS = H-A1_FAVORED | H-A2_FAVORED | H-A3_FAVORED | AMBIGUOUS
```

A secondary result is the first divergence layer for each model:

```text
FIRST_DIVERGENCE_LAYER = L1 | L2 | L3 | L4 | L5 | NONE | UNRESOLVED
```

## 13. Post-result update rules

### If H-A1 favored

```text
ARES candidate is demoted.
New candidate:
Relational Executable Structure.
Authorization becomes audit/evaluation policy.
```

### If H-A2 favored

```text
ARES is retained but redefined.
Authorization is the executable function’s input-domain condition.
```

### If H-A3 favored

```text
ARES is strengthened.
Authorization is constitutive of the executable structure.
```

### If AMBIGUOUS

```text
Do not force classification.
Design a follow-up that separates:
source-admission refusal,
structural invalidity,
external policy refusal.
```

## 14. Run boundary

This document freezes design only.

Not authorized:

```text
prompt implementation
runner implementation
model execution
new model selection
B retry
D retry
Observer
InformationCore write
846 mapping
minimal Information Core claim
```

The next separate authorization step, after human review, would be prompt/runner implementation
followed by the four-cell run.
