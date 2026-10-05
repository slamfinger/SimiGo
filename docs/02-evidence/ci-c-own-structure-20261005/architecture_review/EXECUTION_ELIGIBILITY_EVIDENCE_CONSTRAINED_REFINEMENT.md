# Execution Eligibility — Evidence-Constrained Conceptual Refinement

Date: 2026-10-05
Status: `CONCEPTUAL REFINEMENT · EVIDENCE-CONSTRAINED · NOT_THEORY · NO_NEW_CLAIM`
Predecessor: `EXECUTION_ELIGIBILITY_CONCEPTUAL_SPECIFICATION.md` v0.1 (`66a600c`)
Evidence incorporated: Phase A (`ea537cc`) + Phase B (`1f4fcd7`) + Joint Probe (`747c310`)
Experiment authorized: none
Version note: refinement of v0.1, not a version bump. The core definition `Eligible(T | C)` is unchanged. This document absorbs frozen behavioral evidence into the conceptual model without promoting candidate interpretations to established claims.

---

## 1. Purpose

This document refines the Conceptual Specification v0.1 by incorporating the behavioral evidence now available from Phase A, Phase B, and the Joint Eligibility Probe. It does not introduce new claims, authorize experiments, or resolve the shared-vs-parallel question.

The goal is to produce a conceptual model that is **constrained by evidence** — meaning every structural claim in the model has a corresponding observed behavior or is explicitly marked as open.

---

## 2. Refined conceptual model

```text
┌─────────────────────────────────────────────────────────┐
│                    Condition Domain C                    │
│                                                          │
│   Authorization conditions      Information conditions   │
│   (E±, X±)                      (F-present/absent/stale/ │
│                                  conflicting/irrelevant) │
└──────────┬──────────────────────────────┬────────────────┘
           │                              │
           ▼                              ▼
   ┌───────────────┐              ┌───────────────┐
   │   Observed    │              │   Observed    │
   │   behavior    │              │   behavior    │
   │  (Phase A)    │              │  (Phase B)    │
   └───────┬───────┘              └───────┬───────┘
           │                              │
           │         ? (open)             │
           └──────────────┬───────────────┘
                          ▼
              Eligibility(T | C)
                          │
                          ▼
              Transition admissibility
                          │
              ┌───────────┼───────────┐
              ▼           ▼           ▼
         COMPLETED    DEGRADED     BLOCKED
```

The `?` is **retained and explicitly marked open**. Current evidence supports **candidate convergence** but cannot distinguish shared function from parallel independent gates.

---

## 3. Evidence-constrained properties of Eligibility

Each property below is annotated with its evidence source and status.

### 3.1 Eligibility is transition-relative

**Definition (unchanged from v0.1):** `Eligible(T | C)` — a property of a candidate transition evaluated against a condition set, not a property of a state alone.

**Evidence constraint:** Both Phase A and Phase B manipulate conditions and observe transition outcomes. No experiment manipulates state in isolation. The transition-relative framing is the most conservative model consistent with all observations.

**Status: adopted.**

---

### 3.2 Conditions occupy distinct semantic roles relative to eligibility

Phase B empirically identified three roles:

| Role | Observed behavior | Evidence source |
|---|---|---|
| **Execution prerequisite** | Absence → BLOCKED (replicated, semantically specific) | Phase B main + probe |
| **Quality condition** | Staleness → DEGRADED/incorrect COMPLETED, no BLOCKED | Phase B main |
| **Non-condition** | Irrelevance → no effect on transition | Phase B probe (F-IRRELEVANT) |

Phase A identified two authorization sub-conditions:

| Sub-condition | Observed behavior | Evidence source |
|---|---|---|
| `A_epistemic` (E) | Controls premise adoption | Phase A main + partial-adoption probe |
| `A_execution` (X) | Controls execution-path emission | Phase A main + order reversal |

**Refinement:** The concept of "condition role" is now evidence-constrained rather than purely hypothetical. We can say:

> A condition's role (prerequisite / quality / non-condition) is determined by its **behavioral signature** (does its manipulation produce BLOCKED, DEGRADED, or no effect?), not by its semantic label.

**Status: adopted from Phase B evidence.**

---

### 3.3 The quality boundary and the execution boundary are distinct

**Observed:**

```text
F-STALE  → COMPLETED/DEGRADED (transition executable, output wrong)
F-ABSENT → BLOCKED (transition not executable)

Quality degradation ≠ Eligibility failure
```

**Refinement:** The conceptual model must maintain this distinction as a **hard boundary**. A condition that produces only quality degradation has not crossed the eligibility boundary, regardless of how severe the degradation is.

**Formal sketch:**

```text
Quality boundary:     output differs from baseline; T still executes
Execution boundary:   T does not execute; no valid output produced
```

**Status: adopted. Evidence: Phase B main run (F-STALE vs F-ABSENT), replicated C/N.**

---

### 3.4 Authorization and Information conditions independently produce blocking

**Observed (Joint Probe):**

```text
X-  → BLOCKED (C and N)
F-absent → BLOCKED (C and N)
X- + F-absent → BLOCKED (no additional interaction)
```

**Refinement:** The conceptual model now includes **two condition domains** (Authorization and Information) that both independently produce blocking at the transition-eligibility level. This is **candidate evidence for shared constraint**, not proof of shared mechanism.

**Status: adopted as candidate, explicitly not resolved.**

---

### 3.5 The shared-vs-parallel question

**Open.** Two structures remain consistent with all data:

```text
Structure A (shared):   X ─┐
                           ├──→ Eligibility(T|C) → BLOCKED
                        F ─┘

Structure B (parallel): X → eligibility_X → BLOCKED
                        F → eligibility_F → BLOCKED
```

**Status: explicitly open. Not resolved by current evidence. No future direction committed.**

---

### 3.6 Layered eligibility (from Phase A)

Phase A's E+X− cell showed:

```text
adoption = true (epistemic condition satisfied)
C4 withheld (execution condition not satisfied)
```

This suggests eligibility may be **layered**: epistemic admissibility is a necessary but not sufficient condition for execution emission.

**Refinement:** The conceptual model should allow for:

```text
Eligibility(T | C) as a composite:
    epistemic_eligibility  (may the premise be used?)
    execution_eligibility  (may the action be emitted?)
```

Whether these are two sequential checks on one function or two independent checks is **open**.

**Status: candidate structure. Evidence from Phase A only. Not integrated with Phase B's condition roles.**

---

## 4. Evidence-constrained classification of conditions

Based on all completed experiments, the current classification is:

| Condition | Domain | Role | Evidence status |
|---|---|---|---|
| F-ABSENT | Information | **Execution prerequisite** | Established (replicated, semantically specific, generic-validation control passed) |
| F-STALE | Information | **Quality condition** | Established (replicated, no blocking) |
| F-IRRELEVANT | Information | **Non-condition** | Established (control passed) |
| F-CONFLICTING | Information | **Unresolved** | Model-dependent (C completes, N blocks) |
| X- (A_execution) | Authorization | **Execution prerequisite** | Established (Joint Probe, replicated) |
| E- (A_epistemic) | Authorization | **Premise admissibility** | Established (Phase A, replicated; blocks adoption but not transition per se) |

**Note:** `E-` blocks at the epistemic level (no adoption), which is upstream of the transition-eligibility level tested in the Joint Probe. The relationship between epistemic ineligibility and transition ineligibility is not directly tested in the Joint Probe (E was fixed at E+).

---

## 5. What this refinement does NOT claim

1. Does not claim Execution Eligibility is a proven unified construct.
2. Does not resolve shared vs parallel gates.
3. Does not integrate Phase A's layered eligibility with Phase B's condition roles into a single model.
4. Does not generalize to other transitions, models, or condition types.
5. Does not propose or authorize any experiment.
6. Does not change any Phase A/B claims.
7. Does not resolve the C emitted=true + BLOCKED anomaly.

---

## 6. What changed from v0.1

| Aspect | v0.1 | This refinement |
|---|---|---|
| Condition roles | Hypothetical trichotomy | **Evidence-constrained** (Phase B + Joint Probe) |
| Quality/execution boundary | Conceptual distinction | **Empirically grounded** (F-STALE vs F-ABSENT) |
| Authorization + Information convergence | Purely structural `?` | **Candidate convergence** (Joint Probe BLOCKED pattern) |
| Layered eligibility | Mentioned as Phase A observation | **Retained as candidate structure**, not merged with Phase B |
| Overall status | Conceptual skeleton | **Evidence-constrained conceptual model** |

The core definition `Eligible(T | C)` is **unchanged**.

---

## 7. Summary

```text
DOCUMENT: Execution Eligibility — Evidence-Constrained Conceptual Refinement
STATUS:   REFINEMENT COMPLETE · NOT THEORY · NO NEW CLAIM
DEFINITION: Eligible(T | C) — unchanged from v0.1
STRUCTURE:  Condition → Eligibility → Transition (unchanged)
EVIDENCE:   Absorbed from Phase A + Phase B + Joint Probe
OPEN:       Shared vs parallel gates; layered eligibility integration; C anomaly
NEXT:       Human Review → then likely research pause or new thread
```
