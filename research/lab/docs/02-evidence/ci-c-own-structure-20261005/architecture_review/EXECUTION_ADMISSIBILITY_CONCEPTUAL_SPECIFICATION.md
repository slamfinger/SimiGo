# Execution Admissibility — Conceptual Specification v0.1

Date: 2026-10-05
Status: `CONCEPTUAL SPECIFICATION · NO_NEW_CLAIM · NO_EXPERIMENT`
Predecessor: `EXECUTION_ELIGIBILITY_EVIDENCE_CONSTRAINED_REFINEMENT.md` (`a19e3ba`) + `846_ELIGIBILITY_ARCHITECTURE_MAPPING.md` (`cb07a67`)
Evidence added: none
Claim status change: none
Experiment authorization: none

---

## 0. Purpose

This specification introduces **Execution Admissibility** as a candidate research object that is broader than the currently operationalized `Eligibility(T | C)`. It does not replace Eligibility; it clarifies their relationship and identifies what Admissibility would need to encompass.

This document does not:
- claim that Admissibility is established;
- resolve the `?` between State-side and Condition-side;
- authorize experiments;
- change Phase A/B claims.

---

## Governing principle

```text
Conditions / State-side factors
            │
            ? (open)
            │
            ▼
    Execution Admissibility
            │
            ▼
       Transition
```

`Eligibility(T | C)` is the **currently operationalized** subset of this broader question. Admissibility is the **candidate general research object**.

---

## 1. Relationship between Admissibility and Eligibility

### Three possible relationships

| Relationship | Meaning | Current status |
|---|---|---|
| Synonymous | Admissibility = Eligibility; two names for the same concept | Possible but uninformative |
| **Eligibility is the observable/operationalized form of Admissibility** | Admissibility is the general property; Eligibility is what we can currently measure under tested conditions | **Working hypothesis** |
| Different levels | Admissibility and Eligibility operate at different architectural layers | Not currently supported |

### Working hypothesis adopted here

> **Eligibility(T | C) is the observable, condition-side operationalization of the broader property Execution Admissibility.**

This means:
- Eligibility captures what we can currently test: external conditions on a transition.
- Admissibility encompasses both external conditions **and** State-side/Function-side determinants that we have not yet experimentally manipulated.
- The relationship between them is analogous to the relationship between "temperature" (what a thermometer reads) and "thermal energy" (the broader physical property).

### What this hypothesis does NOT claim

- It does not claim Admissibility exists as a real phenomenon.
- It does not claim State-side factors are part of Admissibility.
- It does not change `Eligible(T | C)` to `Admissible(T | S, C)`.

### Operational distinction

```text
Eligibility:   what we can currently observe and manipulate
               → operationalized via Phase A/B/Joint Probe conditions

Admissibility: the broader property we are trying to characterize
               → encompasses Eligibility + candidate State-side determinants
               → not yet fully operationalized
```

---

## 2. Condition-side and State-side relationship

### Current architecture

```text
         Execution State / Function
                  │
        ┌─────────┴─────────┐
        │                   │
    State-side          Condition-side
        │                   │
       846          Authorization / Information
        │           (Phase A / Phase B)
        │                   │
        └────────┬──────────┘
                 ?
                 │
         Admissibility
                 │
            Transition
```

### What Condition-side contributes

Phase A and Phase B establish that external conditions (Authorization metadata, Information availability) independently produce blocking at the transition level. This is the **operationally accessible** portion of Admissibility.

### What State-side contributes (candidate, not established)

846's CI-C results establish that the internal relational structure of the execution function is load-bearing (K3-DELETED → C4 absent). This suggests that **the internal structure of the execution mechanism** is also a determinant of whether a transition can proceed.

**However**: 846 has not been experimentally connected to the Eligibility framework. The structural parallel (K3-DELETED → C4 absent ≈ F-ABSENT → BLOCKED) is observed at the same abstraction level but through different mechanisms.

### The `?`

The `?` represents the open question:

> Do State-side and Condition-side factors feed into the **same** admissibility determination, or are they **separate** constraints that independently block transitions?

This is the same question as "shared vs parallel gates" from the Joint Eligibility Probe, now extended to include State-side factors.

### What would be needed to resolve

1. A transition where both State-side integrity and external conditions can be independently manipulated.
2. Evidence that manipulating one changes the effect of the other (interaction).
3. Or evidence that they are fully independent (additive).

None of these have been attempted.

---

## 3. Where does 846 fit?

### Three candidate positions

| Position | Meaning | Evidence |
|---|---|---|
| **Condition** | 846's structural integrity is one more external condition (like F-presence) | Not supported: 846 is internal, not externally manipulable in the current setup |
| **State-side determinant** | 846's structural integrity is a determinant of Admissibility that is not a Condition but a property of the execution mechanism | **Candidate**: structurally motivated by K3-DELETED → C4 absent |
| **Internal structure evidence for Admissibility itself** | 846 provides evidence that Admissibility has an internal structure (relational admissibility function), not just external conditions | **Candidate**: the relational function is the mechanism that computes admissibility, not a condition that gates it |

### Working position adopted here

> **846 is placed as a State-side determinant candidate.** It provides evidence that the execution mechanism has internal structural requirements for producing admissible outcomes. It is not a Condition in the same sense as Authorization or Information.

**But**: the relationship between 846's internal structure and external Conditions is unresolved. The `?` is retained.

### What 846 contributes to the Admissibility concept

846 suggests that Admissibility is not purely a function of external conditions. There is an **internal structural dimension** — the execution function must be structurally intact (have its relational admissibility operator) for admissibility to be computable at all.

This is a qualitatively different type of determinant than "the model has the information" or "the model is authorized." It is: "the mechanism that would evaluate admissibility is itself structurally capable of doing so."

---

## 4. What counts as Admissibility evidence

### Three distinct phenomena that must not be conflated

| Phenomenon | Definition | How it differs from Admissibility failure |
|---|---|---|
| **Quality degradation** | Transition executes; output is incorrect, stale, or suboptimal | Transition is still admissible; the execution succeeded but the result is wrong |
| **Execution inadmissibility** | Transition is BLOCKED; no valid output produced | The transition was evaluated and found to be non-executable under current conditions |
| **Internal representation failure** | The mechanism that would evaluate or execute the transition is structurally absent or corrupted | The question of admissibility cannot even be properly evaluated because the evaluating function is broken |

### Criteria for each

**Quality degradation** (Phase B F-STALE):
- Transition status = COMPLETED or DEGRADED
- Output differs from baseline
- No BLOCKED

**Execution inadmissibility** (Phase B F-ABSENT, Joint Probe X-, Joint Probe F-absent):
- Transition status = BLOCKED
- No valid output
- Semantic specificity demonstrated
- Replicated across models
- Not explained by generic validation

**Internal representation failure** (846 K3-DELETED):
- C4 absent
- Error indicates relational admissibility unavailable
- Not the same as "information missing" or "not authorized"
- The function that would produce the admissibility result is itself non-functional

### Critical boundary

```text
Quality degradation:    T executes → wrong output
Inadmissibility:        T blocked → no output
Representation failure: evaluator broken → cannot determine admissibility
```

These are **three different phenomena**. Current Phase A/B evidence covers the first two. 846 provides evidence for the third. Whether they are three levels of the same Admissibility construct or three independent phenomena is **open**.

---

## 5. Refined architecture with Admissibility

```text
┌────────────────────────────────────────────────────────────┐
│                   Execution Admissibility                   │
│                                                             │
│   ┌─────────────────┐   ┌──────────────────────────────┐   │
│   │ Condition-side  │   │     State-side / Function    │   │
│   │                 │   │                              │   │
│   │ Authorization   │   │  Internal relational         │   │
│   │ Information     │   │  admissibility function      │   │
│   │ [other?]        │   │  (846 candidate)             │   │
│   └────────┬────────┘   └──────────────┬───────────────┘   │
│            │                           │                    │
│            │        ? (open)           │                    │
│            └───────────┬───────────────┘                    │
│                        │                                    │
│                        ▼                                    │
│              Eligible(T | C) — operationalized subset       │
│                        │                                    │
│                        ▼                                    │
│                   Transition                                │
└────────────────────────────────────────────────────────────┘
```

**Note**: `Eligible(T | C)` sits **inside** the broader Admissibility construct as its currently operationalized portion. The State-side dimension is inside the Admissibility boundary but outside the current Eligibility operationalization.

---

## 6. What this specification does NOT do

1. Does not claim Admissibility is established as a phenomenon.
2. Does not resolve the `?` between State-side and Condition-side.
3. Does not redefine `Eligible(T | C)`.
4. Does not change Phase A/B claims.
5. Does not authorize experiments.
6. Does not formalize "admissibility information" as a concept.
7. Does not extend to `Eligible(T | S, C)` or `Admissible(T | S, C)`.
8. Does not resolve layered eligibility.
9. Does not resolve the C anomaly.

---

## 7. Relationship to prior documents

| Document | Contribution | This spec |
|---|---|---|
| Conceptual Spec v0.1 (`66a600c`) | Defined `Eligible(T | C)` | Retained unchanged as operationalized subset |
| Evidence-Constrained Refinement (`a19e3ba`) | Grounded condition roles in evidence | Absorbed; roles are properties of the Condition-side |
| 846 Mapping (`cb07a67`) | Identified State-side as candidate determinant | Extended: 846 is placed inside Admissibility as internal-structure candidate |
| Joint Probe (`747c310`) | Demonstrated cross-domain blocking | Absorbed as evidence for Condition-side contribution to Admissibility |

---

## 8. Summary

```text
CONCEPT:   Execution Admissibility
STATUS:    Candidate general research object (broader than Eligibility)
DEFINITION: The property that determines whether a state transition
            is legitimate/executable, encompassing both external
            conditions and internal structural requirements
RELATIONSHIP TO ELIGIBILITY: Eligibility = operationalized subset
OPEN:      State-side / Condition-side convergence (?)
           Internal representation failure as third admissibility barrier
NEXT:      Human Review of this specification
```
