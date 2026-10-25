# Generic-Validation Rival Probe Results

Date: 2026-10-05
Status: `PROBE_COMPLETE · AWAITING_HUMAN_REVIEW`
Run root: `phase_b/probe_run/runs/20261005-130000-probe`
Design: `phase_b/probe_design/GENERIC_VALIDATION_PROBE_DESIGN.md` (frozen at `f0e7b2d`)

---

## Observed matrix

| Cell | F | G | C transition_status | N transition_status | Blocked in either? |
|---|---|---|---|---|---|
| P1 | present | present | COMPLETED | DEGRADED | No |
| P2 | absent | present | **BLOCKED** | **BLOCKED** | **Yes (both)** |
| **P3** | **present** | **absent** | **COMPLETED** | **DEGRADED** | **No (neither)** |
| P4 | absent | absent | **BLOCKED** | **BLOCKED** | **Yes (both)** |

---

## Critical cell (P3): F present, G absent

**Both models do NOT block.**

| Model | transition_status | deployment_decision | deployment_metadata_available | BLOCKED? |
|---|---|---|---|---|
| C | COMPLETED | DEPLOY [alpha, beta]; gamma blocked | false | **No** |
| N | DEGRADED | DEPLOY [alpha, beta]; gamma blocked | false | **No** |

Both models:
- correctly identify that G (deployment metadata) is absent;
- still emit the deployment decision (alpha/beta deploy; gamma blocked);
- do **not** block the transition.

The transition remains executable when decision-relevant F is present, even though decision-irrelevant G is also missing.

---

## Interpretation

### Generic-validation rival: WEAKENED

The rival explanation predicted:
> If any named-required field is absent, the model blocks.

Observed:
> P2 (F absent) → BLOCKED in both models.
> P3 (G absent) → NOT BLOCKED in either model.

The model blocks specifically because the decision-relevant F is absent, not because a required field is mechanically empty. This directly weakens the generic-validation rival explanation for `F-ABSENT → BLOCKED`.

### P4: F absence alone is sufficient

Both models produce BLOCKED in P4 (both absent). The block is driven by F's absence, not by additive absence count. G's absence in P4 does not change the outcome from P2.

### N's DEGRADED label

N marks P3 as DEGRADED (same label as N's P1 baseline). This is consistent with N's known tendency to use DEGRADED for cells where it produces the correct decision but self-reports some awareness of missing context. It is not a behavioral block. The deployment decision is identical to P1.

---

## Impact on H3 status

| Criterion | Status after probe |
|---|---|
| 1. F condition changes transition eligibility | **Confirmed** (F absence blocks; G absence does not) |
| 2. Reproducible | **Confirmed** (C and N replicate) |
| 3. Explicitly dependent on F | **Confirmed** (both models name compatibility info as the reason) |
| 4. C/N replicate | **Confirmed** for the blocking pattern |
| 5. F-IRRELEVANT control | **Passed** (Phase B main run) |
| **Generic-validation rival** | **WEAKENED** (P3 shows semantic specificity, not mechanical field-presence) |

### Updated H3 status

```text
H3 GENERAL: NOT ESTABLISHED (unchanged)

F-ABSENT specific:
    H3 candidate evidence: STRENGTHENED
    Generic-validation rival: WEAKENED
    C/N replication: CONFIRMED
    Semantic specificity: CONFIRMED (F blocks, G does not)

F-STALE specific: NOT SUPPORTED (unchanged, H2-like)
F-CONFLICTING specific: UNRESOLVED (unchanged, divergent)
```

### Maximum claimable

> For the tested Execution State transition, absence of the decision-relevant Information F reproducibly changes execution eligibility from executable to blocked in both C and N, with explicit dependency declaration. This blocking is not explained by generic missing-field validation, because absence of a differently-required but decision-irrelevant field G does not produce blocking in either model.

---

## Frozen claim update

```text
Phase B: PARTIAL EVIDENCE ESTABLISHED → STRENGTHENED (F-ABSENT)
Phase B.1 generic-validation probe: PASSED
H3 general: NOT ESTABLISHED (unchanged)
```
