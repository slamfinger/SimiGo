# 846 × Execution Eligibility Architecture Mapping

Date: 2026-10-05
Status: `CONCEPTUAL_MAPPING · NOT_EXPERIMENT · NOT_REINTERPRETATION · NO_NEW_CLAIM`
Scope: Where does 846 sit in the `Condition → Eligibility → Transition` framework?
Predecessor: `EXECUTION_ELIGIBILITY_EVIDENCE_CONSTRAINED_REFINEMENT.md` (`a19e3ba`)
Boundary: 846 is not reinterpreted. Phase A/B are not rewritten. No experiment is proposed or authorized.

---

## 1. What this document is

This document performs a **conceptual architecture mapping**: it asks where the 846 phenomenon sits relative to the `Condition → Eligibility → Transition` framework developed in Phase A, Phase B, and the Architecture Review.

It does **not**:
- map 846 atoms to specific Phase A/B variables;
- reinterpret 846's internal structure;
- claim that 846 and Phase A/B observe the same mechanism;
- propose experiments.

Its sole output is a **relationship judgment** with an evidence level.

---

## 2. What is documented about 846

From prior work (CI-C results, not reinterpreted here):

| Observation | Source | Status |
|---|---|---|
| K3 (relational admissibility operator) is load-bearing: K3_DELETED → C4 absent | CI-C first discrimination, replicated C/N | Established |
| K3 is substitutable: K3_PRECOMPUTED_F → C4 preserved | CI-C first discrimination, replicated C/N | Established |
| K2 (pair coexistence) is necessary in both runnable models | CI-C first discrimination | Established for C/N |
| K1 necessity is model-dependent | CI-C first discrimination | Not cross-model established |
| The candidate invariant is a **relational executable admissibility function** | CI-C interpretation | Candidate, not established as minimum |

Key structural property of 846:

> **846 concerns the internal relational structure of the execution function itself** — specifically, whether a relational admissibility operator is present and load-bearing.

---

## 3. Where 846 sits in the three-layer framework

```text
Condition → Eligibility → Transition
```

### 846's position

846 is not a condition external to the transition. It is a property of the **execution function** that the transition depends on.

```text
846: "Is the relational admissibility function intact and load-bearing?"
```

This is a question about the **State-side** or **Function-side** infrastructure, not about external conditions.

### Contrast with Phase A and Phase B

| | Phase A | Phase B | 846 |
|---|---|---|---|
| What is manipulated | Authorization metadata (external) | Information availability (external) | Internal relational structure |
| What is tested | Whether the model is permitted to execute | Whether the model has the information to execute | Whether the execution function itself is structurally intact |
| Layer | Condition | Condition | **State/Function side** |

Phase A and Phase B ask: "Given a working execution function, do external conditions permit/block the transition?"

846 asks: "Is the execution function itself structurally capable of producing an admissible outcome?"

---

## 4. Structural comparison

### 4.1 The parallel: "necessary condition removed → execution fails"

| Framework | Removing necessary condition | Result |
|---|---|---|
| Phase B | F-ABSENT (information unavailable) | BLOCKED |
| 846 / CI-C | K3-DELETED (relational operator absent) | C4 absent |

Both exhibit the pattern: **remove a necessary structural/informational element → execution outcome is lost**.

**This is a structural analogy at the same abstraction level.** Both are instances of "necessary dependency missing → execution fails."

**But**: the nature of the dependency differs:
- F-ABSENT: the transition **cannot be evaluated** because the required information for the eligibility decision is missing.
- K3-DELETED: the transition **cannot be computed** because the relational logic that produces the admissibility result is absent.

### 4.2 The difference: evaluation vs computation

```text
Phase B (F-ABSENT):
    "I have a transition, but I lack the information to determine if it's eligible"
    → Cannot evaluate eligibility → BLOCKED

846 (K3-DELETED):
    "I have a transition, but the function that would determine eligibility is structurally absent"
    → Cannot compute admissibility → C4 absent
```

These are at different points relative to the eligibility concept:
- F-ABSENT is an **input to** the eligibility evaluation.
- K3-DELETED is a **constituent of** the eligibility evaluation mechanism.

### 4.3 K3_PRECOMPUTED_F: a bridge observation

846 has one result that is directly relevant to the Eligibility framework:

> **K3_PRECOMPUTED_F → C4 preserved**

When the relational operator is deleted but a precomputed result is supplied, the execution function survives. This means:

> **The eligibility boundary can be maintained by either the internal relational structure OR by an externally supplied precomputed result.**

This is directly parallel to Phase B's finding:

> **F-ABSENT blocks; but if a precomputed F is supplied, the transition can proceed.**

In both cases: **the transition requires some form of "admissibility information" — either computed internally or supplied externally.**

---

## 5. Relationship judgment

Based on the structural comparison, the relationship between 846 and the Execution Eligibility framework is:

```text
SAME ABSTRACTION LEVEL
```

**Evidence level: structural analogy (strong), mechanistic identity (not established).**

### Reasoning

1. **Same abstraction**: Both 846 and Phase A/B are instances of "conditions for execution continuation." 846 identifies the internal structural condition (relational operator); Phase A/B identify external authorization and information conditions. All three address the same question: **under what conditions does execution continue?**

2. **Not the same phenomenon**: 846's K3 is a structural component of the execution function. Phase B's F is an external information input. They operate through different mechanisms and are not interchangeable.

3. **Not upstream-determinant (in the tested frame)**: The Phase A/B experiments did not manipulate 846's internal structure. The Joint Probe's transition used an externally supplied F, not an internally computed one. Therefore 846's internal state was held constant (implicitly intact) during Phase A/B.

4. **Not merely surface similarity**: The K3_PRECOMPUTED_F result directly parallels Phase B's F-present/F-absent distinction. In both cases, the presence of admissibility information (whether computed or supplied) is the load-bearing factor for execution continuation. This is more than surface resemblance.

### What would upgrade the relationship

If a future experiment showed that:
- 846's K3-DELETED state makes the transition ineligible **regardless of** external conditions (Authorization and Information both satisfied);
- or that K3-PRECOMPUTED_F is functionally equivalent to F-present in the Eligibility framework;

then the relationship would upgrade from SAME ABSTRACTION to **UPSTREAM-DETERMINANT** (846 defines whether the eligibility function itself is operational).

This has not been tested.

---

## 6. Should Eligible(T | C) become Eligible(T | S, C)?

### Current answer: **not yet**

If 846 represents State-side factors, the natural extension would be:

```text
Eligible(T | C)  →  Eligible(T | S, C)
                    where S = State-side/Function-side factors
                    and C = external Conditions
```

However, this extension requires:
1. Evidence that State-side factors independently affect eligibility in the same transition (not yet tested).
2. A clear definition of what S contains (K3? other structural properties? the entire execution function?).
3. Evidence that S and C interact or are independent.

None of these have been established. Adding S at this stage would be premature formalization.

### What the mapping does suggest

846 provides **theoretical motivation** for eventually extending to `Eligible(T | S, C)`:

> If the relational admissibility function is load-bearing (K3_DELETED → C4 absent), then the internal state of the execution function is a **candidate condition** for eligibility, alongside external Authorization and Information.

But this remains a **hypothesis for future work**, not a claim.

---

## 7. Evidence-constrained classification of 846

| Property | Value |
|---|---|
| Relationship to Eligibility framework | **SAME ABSTRACTION LEVEL** |
| Evidence for this relationship | **Structural analogy (strong); mechanistic identity not established** |
| 846 as State-side condition | **Theoretically motivated, not experimentally tested** |
| `Eligible(T | S, C)` extension | **Hypothesis, not adopted** |
| K3_PRECOMPUTED_F ↔ F-present parallel | **Observed structural parallel, not experimentally confirmed as equivalent** |

---

## 8. Summary

```text
846 occupies the State-side / Function-side of the execution architecture.
Phase A occupies the Authorization condition domain.
Phase B occupies the Information condition domain.

All three address the same abstraction level:
"Under what conditions does execution continue?"

Current relationship: SAME ABSTRACTION LEVEL (structural analogy)
Not established: mechanistic identity, upstream determination, S extension

Next gate: Human Review on whether to pursue 846 integration or maintain current boundary.
```
