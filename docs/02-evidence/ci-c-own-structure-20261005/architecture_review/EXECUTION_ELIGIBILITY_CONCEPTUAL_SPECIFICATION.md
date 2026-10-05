# Execution Eligibility Conceptual Specification v0.1

Date: 2026-10-05
Status: `CONCEPTUAL SPECIFICATION`
Evidence added: none
Claim status change: none
Phase A: CLOSED (`ea537cc`)
Phase B: FROZEN (`1f4fcd7`)
General H3: NOT ESTABLISHED
Experiment authorization: NONE

---

## 0. Purpose and scope

This document establishes a **conceptual skeleton** for the term "Execution Eligibility" as a candidate intermediate abstraction between observed conditions and observed transition outcomes.

It does **not**:
- claim that Execution Eligibility exists as a unified variable;
- redefine Phase A or Phase B results;
- authorize any experiment;
- introduce a formal theory.

Its sole function is to make the concept precise enough that future work can evaluate whether the concept is useful, without presupposing the answer.

---

## Governing principle

```text
Condition → Eligibility → Transition
```

`Eligibility` is a **candidate intermediate abstraction**. Whether Phase A and Phase B converge on the same eligibility variable is an open question, not an assumption.

---

## 1. What does "eligible" mean?

### Working definition

A transition `T` is **eligible** under a set of conditions `C` if and only if `T` is **admissible for execution** under `C` — that is, there is no condition in `C` that prevents `T` from being initiated or completed as a legitimate state change.

This is a **transition-relative** definition:

```text
Eligible(T | C)
```

Eligibility is not a property of a state in isolation. It is a property of a **candidate transition** evaluated against a set of conditions.

### What "eligible" does NOT mean

- It does not mean the transition will succeed.
- It does not mean the output will be correct.
- It does not mean the model has made a decision.

It means: the transition is **not ruled out** by the current condition set.

### Minimal formal sketch

```text
Given:
  T  = a candidate state transition
  C  = a set of conditions {c₁, c₂, …, cₙ}

Define:
  Eligible(T | C) = true   if no cᵢ in C prevents T
  Eligible(T | C) = false  if at least one cᵢ in C prevents T
```

The conditions that prevent `T` are called **execution-prerequisite conditions**. The conditions that affect output but not eligibility are called **quality conditions**. The conditions that have no effect are called **non-conditions**.

This trichotomy is derived from Phase B's empirical observation (not assumed a priori).

---

## 2. Relationship between Eligibility and COMPLETED / DEGRADED / BLOCKED

The three transition outcomes observed in Phase B map to eligibility as follows:

| Transition status | Eligibility implication |
|---|---|
| `COMPLETED` | Eligibility = true; output meets baseline expectations |
| `DEGRADED` | **Eligibility = true**; transition executed but output quality/validity is reduced |
| `BLOCKED` | **Candidate eligibility = false**; transition not executed |

### Critical boundary

```text
DEGRADED ≠ eligibility failure
BLOCKED  = eligibility failure (candidate, not proven)
```

`DEGRADED` means the transition was **executable** but the output was suboptimal. The state transition still occurred. Eligibility was not the binding constraint.

`BLOCKED` means the transition was **not executed**. This is the candidate signal for eligibility = false, but it requires further evidence (see §6) to distinguish from generic error handling.

### Phase A mapping

Phase A did not use the three-state vocabulary. Its observable was binary: C4 emitted or withheld.

Mapping to eligibility:

| Phase A outcome | Eligibility implication |
|---|---|
| C4 emitted (E+X+) | Eligibility = true; all conditions satisfied |
| C4 withheld (E+X−) | Eligibility = **partially false**: adoption succeeded (epistemic eligibility) but execution emission was denied. This suggests eligibility may be **layered**. |
| C4 withheld (E−X±) | Adoption denied; downstream steps not reached. Epistemic eligibility = false. |

### Open question from Phase A

Phase A's E+X− cell raises the possibility that eligibility is not binary but **layered**:

```text
epistemic eligibility  (may this premise be used?)
execution eligibility  (may the resulting action be emitted?)
```

Whether these are two separate eligibility checks or two stages of one check is **unknown**. This specification does not resolve it.

---

## 3. Is Eligibility a property of a transition or of a state?

### This specification adopts: **transition-relative**

Eligibility is defined as `Eligible(T | C)`. It is a property of a **candidate transition evaluated against conditions**, not a property of a state alone.

### Rationale

1. A state without a candidate transition has no eligibility question to answer. The concept only becomes meaningful when there is a transition to evaluate.
2. Phase A and Phase B both manipulated **conditions** and observed **transition outcomes**. Neither phase manipulated state in isolation.
3. Defining eligibility as a state property would require specifying which state (source, target, or intermediate), which adds complexity without clear benefit at this stage.

### What this choice does not rule out

It remains possible that certain conditions are constitutive of a **state** rather than a **transition** (e.g., "this state cannot exist without information X"). The transition-relative definition does not deny this possibility; it simply does not address it. If future work shows that some conditions are state-constitutive, the specification can be extended.

---

## 4. Are conditions inputs to eligibility or components of the state?

### This specification adopts: **conditions are external to the state**

Conditions `C` are treated as an **external condition domain** that is evaluated against a candidate transition. They are not, at this stage, treated as components of the state itself.

### Rationale

1. Phase A manipulated authorization metadata (external to the model's internal state).
2. Phase B manipulated prompt-context information (external to the transition logic).
3. In both cases, the manipulation was external to the transition's core logic. Treating conditions as external preserves this observation.

### The alternative (not adopted here)

An alternative view treats certain conditions as **state-constitutive**: the state does not properly exist without them. For example, F-ABSENT might mean "the execution state is incompletely specified and therefore not a valid execution state."

This view is **attractive** (it would explain why F-ABSENT blocks while F-STALE does not), but it goes beyond what current evidence supports. The external-conditions view is more conservative and does not require redefining "state."

### Boundary note

The external-conditions view does **not** mean conditions are irrelevant to the state. It means: at this level of specification, we model them as **inputs to the eligibility function**, not as components of the state definition.

---

## 5. Are Authorization and Information different condition domains?

### Working answer: **yes, they are distinct condition domains, but whether they feed into the same eligibility function is untested**

Phase A and Phase B manipulate different types of conditions:

| Domain | What is manipulated | Source of evidence |
|---|---|---|
| Authorization | Permission metadata (E±, X±) | Phase A |
| Information | Availability / validity of F (present / absent / stale / conflicting) | Phase B |

These domains differ in:
- what is manipulated (permission vs availability);
- the mechanism of action (authorization tells the model what it may do; information determines what the model can do);
- the observable they most directly affect (adoption vs transition status).

### What is NOT established

- Whether these domains feed into the **same** eligibility function.
- Whether their effects are additive, interactive, or independent.
- Whether a unified "eligibility" construct is necessary to explain both, or whether two separate mechanisms suffice.

### Minimal representation

```text
                  Condition set C
                 /                \
        Authorization           Information
        {E, X}                  {F-present, F-absent, …}
             │                        │
             ▼                        ▼
        observed                  observed
        behavior                  behavior
             │                        │
             └────────?───────────────┘
                      │
              Eligibility(T | C)
                      │
                      ▼
                  Transition
```

The `?` is **retained**. It represents the open question of whether a common eligibility variable exists.

---

## 6. What evidence is sufficient to show that a condition changes eligibility?

This is the most critical criterion for future work. A condition `cᵢ` is said to **change eligibility** (rather than merely affect quality) if **all** of the following are observed:

### Sufficient conditions for "cᵢ changes eligibility"

1. **Transition status changes.** The condition's presence/absence/value changes the transition outcome from `COMPLETED` to `BLOCKED` (not merely to `DEGRADED`).

2. **Semantic specificity.** The blocking is specific to this condition's semantic role, not to the mechanical fact that a field is empty or a value is unusual. (Operationalized in Phase B as: a structurally similar but decision-irrelevant field's absence does not produce blocking.)

3. **Replication.** The pattern is reproduced across at least two models (C and N in the current setup).

4. **Dependency declaration.** The model explicitly names this condition (or its absence) as the reason for blocking.

5. **No equivalent blocking from non-conditions.** Conditions known to be irrelevant to the transition do not produce blocking when similarly absent or anomalous.

### What is NOT sufficient

- A single `BLOCKED` observation without replication.
- `DEGRADED` status alone (this indicates quality degradation, not eligibility change).
- Blocking that also occurs when irrelevant information is missing (generic validation, not eligibility).
- Model self-report of dependency without behavioral blocking.

---

## 7. What evidence shows only quality degradation?

A condition `cⱼ` affects **quality but not eligibility** if:

1. The transition status remains `COMPLETED` (or is labeled `DEGRADED` with the transition still executing), even when the condition is absent, stale, or anomalous.
2. The output is observably different from baseline (wrong values, missing information, stale references).
3. Blocking does not occur for this condition under any tested value.
4. The pattern replicates across models.

### Phase B example

`F-STALE` meets all four criteria: both models completed the transition (deploying gamma incorrectly) without blocking. The output was degraded but the transition was still executable.

### Boundary with §6

The critical distinction is:

```text
If changing cⱼ ever produces BLOCKED (with semantic specificity and replication), 
    then cⱼ is an execution-prerequisite condition.

If changing cⱼ only produces DEGRADED / incorrect COMPLETED, 
    then cⱼ is a quality condition.
```

A condition's role (prerequisite vs quality) is **determined empirically**, not assumed from its semantic label.

---

## 8. Where do Phase A and Phase B fit into this framework?

### Phase A

Phase A manipulates Authorization conditions and observes their effect on behavior.

| Phase A element | Framework position |
|---|---|
| `A_epistemic` (E±) | Authorization condition affecting **premise admissibility** (a candidate eligibility sub-layer) |
| `A_execution` (X±) | Authorization condition affecting **execution permission** (a candidate eligibility sub-layer) |
| adoption (true/false) | Observable downstream of epistemic eligibility |
| C4 emitted/withheld | Observable downstream of execution eligibility |

Phase A provides evidence that authorization conditions can **selectively suppress different stages** of the transition pipeline without eliminating the entire transition.

### Phase B

Phase B manipulates Information conditions and observes their effect on transition status.

| Phase B element | Framework position |
|---|---|
| F-ABSENT | Information condition that meets all §6 criteria → execution-prerequisite condition |
| F-STALE | Information condition that meets §7 criteria → quality condition |
| F-IRRELEVANT | Information condition with no effect → non-condition |
| F-CONFLICTING | Unresolved; model-dependent |
| transition_status | Observable downstream of information-conditioned eligibility |

Phase B provides evidence that information conditions can be classified into at least three roles relative to transition eligibility.

### What remains open

```text
Authorization conditions (Phase A)    Information conditions (Phase B)
         │                                      │
         ?──────────────────────────────────────?
         │                                      │
         └────────── Eligibility(T | C) ────────┘
                              │
                        Transition outcome
```

Whether the `?` resolves into a shared eligibility function is the **central open question** for the next phase of research.

---

## 9. What this specification does NOT do

1. Does not claim Execution Eligibility exists as a unified construct.
2. Does not merge Phase A and Phase B into a single theory.
3. Does not authorize any experiment.
4. Does not redefine any Phase A/B claims.
5. Does not resolve the layered-eligibility question from Phase A's E+X− cell.
6. Does not specify the functional form of `Eligible(T | C)`.
7. Does not generalize beyond the tested transition, models, or condition types.

---

## 10. Summary

```text
CONCEPT:  Execution Eligibility
STATUS:   Candidate intermediate abstraction
DEFINITION: Eligible(T | C) — transition-relative, condition-evaluated
STRUCTURE:  Condition → Eligibility → Transition
EVIDENCE:   None added by this document
OPEN:       Whether Authorization and Information feed into the same eligibility function
NEXT:       Human Review of this specification
```
