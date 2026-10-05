# Execution Admissibility — Conceptual Specification v0.2

Date: 2026-10-05
Status: `CONCEPTUAL SPECIFICATION · STRUCTURAL QUESTION · NO_NEW_CLAIM · NO_EXPERIMENT`
Predecessor: `EXECUTION_ADMISSIBILITY_CONCEPTUAL_SPECIFICATION.md` v0.1 (`5ef2ffb`)
Core question: **Is Admissibility a result label, or a structure composed of multiple necessary conditions?**
Experiment authorization: none

---

## 0. What changed from v0.1

v0.1 introduced Admissibility as a candidate general research object, broader than Eligibility.

v0.2 asks a **structural question about Admissibility itself**: is it a binary label applied to a transition, or does it have decomposable internal structure?

This document does not:
- resolve the `?` between Condition-side and State-side;
- authorize experiments;
- change Phase A/B claims;
- generalize beyond tested transitions.

---

## 1. The structural question

### Two models of Admissibility

**Model A — Result label:**

```text
Admissibility(T) = true | false
```

Admissibility is a **property assignment** to a transition. Conditions are inputs to whatever process computes this property, but the property itself is atomic — it does not have parts.

Under this model:
- `X-` and `F-absent` both happen to make Admissibility false.
- They do so through whatever mechanism computes the label.
- The fact that both produce the same label is not structurally meaningful.

**Model B — Necessary condition structure:**

```text
Admissible(T) ⟺ C₁ ∧ C₂ ∧ … ∧ Cₙ
```

Admissibility is a **conjunction of necessary conditions**. Each condition must hold for the transition to be admissible. The structure is the conjunction itself.

Under this model:
- `X` is one necessary condition.
- `F` is another necessary condition.
- Their joint observation (both independently producing BLOCKED) is **structurally meaningful**: it suggests they are separate conjuncts, not redundant triggers of the same label.

### What current evidence supports

The Joint Eligibility Probe showed:
- `X-` alone → BLOCKED
- `F-absent` alone → BLOCKED
- Both → BLOCKED (no additional effect)

This pattern is **consistent with Model B** (two independent necessary conditions, either alone sufficient to make the conjunction false). It is also **consistent with Model A** (two triggers of the same label).

**The pattern alone cannot distinguish Model A from Model B.** Conceptual clarification is needed before further experiments can be informative.

---

## 2. What is Admissibility?

### Definition (refined from v0.1)

> Execution Admissibility is the property that determines whether a candidate state transition `T` is **legitimate to execute** under a given context.

### Object of Admissibility

Admissibility is not a free-floating property. It is always:

```text
Admissibility(T | context)
```

Where:
- `T` = a candidate state transition (not a state, not an action, but a **transition** from source to target)
- `context` = the set of all factors relevant to whether `T` may proceed

### Why `T | context` and not `T`

Phase A and Phase B demonstrated that the **same transition** (candidate set → release decision) can be COMPLETED or BLOCKED depending on external conditions. 846 further suggests that the internal structure of the execution function also matters.

Therefore, Admissibility cannot be a property of `T` alone. It must be **indexed to context**.

```text
Admissibility(T | context) — not Admissibility(T)
```

This is already implicit in `Eligible(T | C)` from v0.1. This specification makes it explicit for Admissibility.

---

## 3. What is an Admissibility condition?

### Minimal definition

A factor `c` is an **Admissibility condition** for transition `T` if and only if:

1. `c` has a **semantic role** specific to `T` (not merely any input to the system)
2. The absence, denial, or corruption of `c` produces a **transition status change to BLOCKED** (not merely DEGRADED)
3. This blocking is **semantically specific** (not generic validation)
4. This blocking is **replicable** across models
5. Blocking is not produced by **non-conditions** (irrelevant factors)

These criteria are directly derived from Phase B and the Generic-Validation Probe.

### Current known Admissibility conditions

| Condition | Domain | Evidence |
|---|---|---|
| `X` (A_execution) | Authorization | Joint Probe: X- → BLOCKED, replicated |
| `F` (decision-relevant Information) | Information | Phase B + probe: F-absent → BLOCKED, semantically specific |

### Current known non-conditions

| Factor | Domain | Evidence |
|---|---|---|
| `G` (decision-irrelevant metadata) | Information | Generic-Validation Probe: G-absent → not BLOCKED |
| F-IRRELEVANT | Information | Phase B: no blocking |

### Current unresolved

| Factor | Status |
|---|---|
| F-CONFLICTING | Model-dependent (C completes, N blocks) |
| E (A_epistemic) | Operates upstream of transition eligibility (blocks adoption, not transition per se) |
| 846 internal structure | Candidate State-side determinant; not experimentally connected |

---

## 4. `false` vs `unevaluable`

### The distinction

A critical conceptual boundary that must be maintained:

```text
Admissibility evaluated to FALSE:
    The evaluation mechanism is intact.
    It determined that T is not executable under current conditions.
    Result: BLOCKED

Admissibility UNEVALUABLE:
    The evaluation mechanism itself is absent, corrupted, or non-functional.
    No determination can be made.
    Result: C4 absent / error / function unavailable
```

### Why this matters

Phase A/B/Joint Probe produce `false` outcomes (the model evaluates and blocks).
846 produces `unevaluable` outcomes (K3-DELETED → C4 absent; the relational function is gone).

These are **not the same phenomenon**:
- `false` = the admissibility determination completed with a negative result.
- `unevaluable` = the admissibility determination cannot be completed.

### Mapping to observed behaviors

| Observed behavior | Admissibility status |
|---|---|
| BLOCKED (Phase A X-, Phase B F-absent, Joint Probe) | `false` — evaluated and denied |
| COMPLETED / DEGRADED | `true` — evaluated and permitted |
| C4 absent / K3-DELETED (846) | **unevaluable** — evaluation mechanism structurally absent |
| C4 preserved / K3-PRECOMPUTED_F (846) | `true` — externally supplied result substitutes for internal computation |

### Implication

If Admissibility has a necessary-condition structure (Model B), then `unevaluable` is a **third state** beyond `true` and `false`:

```text
Admissibility(T | context) ∈ { true, false, unevaluable }
```

`unevaluable` occurs when one of the conditions required to **evaluate** the other conditions is itself absent.

This is formally distinct from `false` (all conditions evaluated, at least one fails) and `true` (all conditions evaluated, all pass).

---

## 5. Necessary vs sufficient

### Necessary condition

A condition `c` is **necessary** for Admissibility if:

```text
¬c → ¬Admissible(T)
```

If `c` is absent/denied, Admissibility is false (or unevaluable).

### Sufficient condition

A condition `c` is **sufficient** for Admissibility if:

```text
c → Admissible(T)
```

If `c` alone guarantees Admissibility regardless of other conditions.

### Current evidence

From the Joint Probe:

```text
X+  alone (with F-present)     → executable    (from J1)
F-present alone (with X+)      → executable    (from J1)
X-  alone (with F-present)     → BLOCKED      (from J3)
F-absent alone (with X+)       → BLOCKED      (from J2)
```

This pattern suggests:
- `X+` is **necessary** (X- → BLOCKED) but not **sufficient** (X+ with F-absent → still BLOCKED)
- `F-present` is **necessary** (F-absent → BLOCKED) but not **sufficient** (F-present with X- → still BLOCKED)

Both are necessary. Neither is sufficient alone. This is consistent with a **conjunction model**:

```text
Admissible(T) ⟺ X-eligible ∧ F-available ∧ ...
```

### What is NOT established

- Whether the conjunction has exactly two conjuncts or more.
- Whether `E` (epistemic) is a separate conjunct or a precondition for evaluating the others.
- Whether State-side structural integrity (846) is a conjunct or a precondition for evaluation.
- Whether additional unknown conditions exist.

---

## 6. Candidate structure

Based on current evidence, the minimal candidate structure is:

```text
Admissible(T | context) = X_eligible ∧ F_available ∧ [other conditions?]
```

Where:
- `X_eligible` = Authorization execution path is eligible
- `F_available` = Decision-relevant Information is present and current
- `[other conditions?]` = unknown; may include E (epistemic), State-side integrity, or others

This structure is a **candidate**, not an established theory.

### Three-state extension

If 846 is included, the structure becomes:

```text
Admissibility(T | context) ∈ { true, false, unevaluable }

where:
  unevaluable if evaluation mechanism is structurally absent (846 K3-DELETED)
  false if evaluated and at least one necessary condition fails
  true if evaluated and all known necessary conditions pass
```

---

## 7. What this specification does NOT do

1. Does not resolve Model A vs Model B empirically.
2. Does not claim the conjunction structure is proven.
3. Does not include State-side factors as formal conjuncts.
4. Does not resolve `?`.
5. Does not authorize experiments.
6. Does not change Phase A/B claims.
7. Does not resolve layered eligibility.
8. Does not resolve the C anomaly.

---

## 8. What would distinguish Model A from Model B

If a future experiment found a condition `D` such that:
- `D-absent` → BLOCKED
- `D-present` + `X-` + `F-absent` → still BLOCKED (no change from X-/F-absent alone)

This would be **consistent with Model B** (D is a third conjunct; removing it doesn't matter if X or F already fails).

If instead:
- `D-present` + `X-` → some different outcome than X- alone

This would suggest an **interaction** between conditions, which is more complex than a simple conjunction.

The design of such experiments is **deferred** until this conceptual specification is reviewed.

---

## 9. Summary

```text
QUESTION:  Is Admissibility a result label or a structure of necessary conditions?
ANSWER:    Candidate structure: conjunction of necessary conditions
           (Model B is more productive but not yet empirically distinguished from Model A)

DEFINITION: Admissibility(T | context) ∈ { true, false, unevaluable }
KNOWN CONJUNCTS: X (Authorization), F (Information)
UNKNOWN CONJUNCTS: E?, State-side integrity?, others?

NECESSARY vs SUFFICIENT:
  X: necessary, not sufficient
  F: necessary, not sufficient
  Both: consistent with conjunction model

NEXT: Human Review → decide whether to design Model A vs B discriminating experiment
```
