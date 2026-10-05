# Execution Admissibility — Conceptual Specification v0.3 (Mixed-State Propagation Semantics)

Date: 2026-10-05
Branch: `codex/execution-state-research-20260929`
Status: `CONCEPTUAL SPECIFICATION · SEMANTIC COMPLETION · SPEC DECISIONS REGISTERED · NO EMPIRICAL CLAIM · NO EXPERIMENT · PENDING HUMAN REVIEW`
Predecessors: `EXECUTION_ADMISSIBILITY_CONCEPTUAL_SPECIFICATION_V0.2.md` (`5f8bf23`) + `EXECUTION_ADMISSIBILITY_MODEL_AB_IDENTIFIABILITY.md` v0.1 (`f8840fd`)
Directive: Human ruling 2026-10-05 (after identifiability review) — **Step 1 of three**: complete the mixed-state propagation semantics. Concept closure only; no code, no experiments.
Evidence added: none. Experiment authorization: none.

---

## 0. What this document does

Spec v0.2 defined per-condition evaluation and whole-construct three-state output, but left the output **undefined for mixed configurations** — e.g., one condition determined `false` while another is `unevaluable`. Until this is fixed, the three-state model is not a complete function, and no discussion of combinations between `true` / `false` / `unevaluable` is well-formed (identifiability note §1, gap registration; §4.2, "requires spec completion first").

v0.3 closes that gap. It:

1. Introduces a **two-level evaluation vocabulary** (§2) — making explicit a structure v0.2 §4 already implied;
2. Defines a **total, order-independent propagation rule** (§3), with the one genuinely open design choice made as a **registered spec decision** (D-1), alternatives stated;
3. Verifies **back-compatibility** with every established finding (§3.4);
4. Registers the **new falsifiable commitments** this completion adds to Model B (§4) — under the governing discipline below.

### Governing discipline (binding, from Human ruling 2026-10-05)

> Conjunction is an **explanatory model**. What can be empirically tested are the **specific structural commitments** it makes — never the "conjunction" label itself. No result may ever be recorded as "supports Model B"; results test named commitments. A commitment failure means *"the current B formulation is refuted / needs revision"* — never *"Model A proven"*.

This document therefore adds commitments to B; it does not and cannot support B (identifiability verdict Case 2 remains in force; §6).

### What this document does NOT do

- Does not resolve Model A vs Model B (unresolvable per the identifiability analysis; unaffected here);
- Does not authorize any experiment — predictions stated in §4 are **stateable commitments, not probe designs**;
- Does not resolve Q1–Q8, the `?` between Condition-side and State-side, layered eligibility, or the C anomaly;
- Does not change any Phase A/B claim or any 846 finding;
- Does not formalize "admissibility information" (hard boundary) — the source taxonomy of per-condition unevaluability stays deliberately open (§2.3).

---

## 1. Why now, and why this is concept closure only

Step 2 of the Human ruling (Model-B Uniformity / Necessary-Condition Probe) compares any future condition D against X and F. Such comparison presupposes that the three-state semantics is well-defined for the configurations a probe might create — including configurations in which a condition's determination does not complete. Completing the semantics is therefore the precondition for Step 2 being stateable at all.

This is the same role the identifiability note assigned it (§4.2: "conceptual work, not an experiment"). Nothing here requires or authorizes data.

---

## 2. Two evaluation levels (vocabulary, not placement)

v0.2 §4 already contained the germ of a two-level structure: *"unevaluable occurs when one of the conditions required to **evaluate** the other conditions is itself absent."* v0.3 makes that structure explicit as vocabulary. This is **definitional bookkeeping, not an answer to Q3/Q4** — it supplies terms in which E and 846 could later be placed, without placing them.

### Level 0 — Evaluation-mechanism operability

Whether the evaluation mechanism itself can run at all.

- **Level 0 failure** ⇒ no condition is evaluated, no per-condition states exist, whole-construct output is `unevaluable`.
- **Grounded in**: 846 K3-DELETED → C4 absent (established, CI-C). This placement is v0.2 §4's own reading ("evaluation mechanism structurally absent") restated in the new vocabulary — **no reinterpretation of any 846 finding**.

### Level 1 — Per-condition determinations

Given Level 0 intact, each condition `c_i` receives a determination:

```text
c_i ∈ { true, false, U_c }

true   : determination completed, condition holds
false  : determination completed, condition fails
U_c    : determination of THIS condition does not complete
         while the evaluation process itself is operative
```

### 2.3 What `U_c` is and is not

- `U_c` is a **theoretical posit** required to state mixed configurations. It has **never been observed** as a condition-level determination; all established three-state observations are either Level-0 (846) or Level-1 `true`/`false` (Phase A/B, Joint Probe).
- Its **source taxonomy is deliberately open**: it may in principle include determination-blocking ambiguity or contradiction in the factor itself (F-CONFLICTING is a candidate instance class — **status unchanged, Q7 untouched, nothing interpreted**), or gaps in condition-specific evaluation preconditions (the region where Q3/Q4 live). Enumerating sources would require formalizing what conditions need in order to be evaluable — which the hard boundary on "admissibility information" forbids.
- `U_c` ≠ Level-0 unevaluability. If the mechanism is gone, there are no `U_c` states to compose — the output is `unevaluable` directly (§3).

### 2.4 Two explicit neutrality commitments

1. **Q3/Q4 agnosticism**: the two levels are vocabulary. E (epistemic) may ultimately be a Level-1 conjunct, a Level-0 evaluation precondition, or neither (its observed position — blocking adoption, upstream of the transition — is unmoved by this spec). 846's structural integrity is established at Level 0 as above; whether State-side integrity *additionally* has a Level-1 conjunct role in untested configurations remains Q4, open. Nothing here prejudges either.
2. **Q1 neutrality**: the propagation rule composes determination **outcomes** and presupposes neither a shared evaluation function nor parallel independent gates (Q1 stays open).

### 2.5 States are manipulation-defined, not inferred

In this line's method, per-condition states are set by experimental manipulation, not inferred from outcomes. This has two consequences:

- The `U_c` region of §3's table is **doubly unobserved**: no cell containing `U_c` has ever been instantiated, and **whether a manipulation exists that realizes `U_c` for X or F is itself an open operationalization question** — part of any future Step 2 design gate, not resolvable here.
- The established cells (§3.4) are safe: their states were manipulation-defined at run time.

---

## 3. Propagation semantics (the completion)

### 3.1 General rule (total, order-independent)

For a condition set {c₁, …, cₙ} (n ≥ 1; currently {X_eligible, F_available} plus the open `[other?]` slot):

```text
Evaluation mechanism intact (Level 0 OK):

  false          if any c_i is determined false
  unevaluable    if no c_i is determined false and at least one c_i = U_c
  true           if all c_i are determined true

Evaluation mechanism non-functional (Level 0 failure):

  unevaluable    regardless of any condition-level information
```

The rule is a symmetric reduction: `false` dominates, then `U_c`, then `true`. It is **order-independent by construction** (commitment C-PROP-3, §4).

### 3.2 Spec decision D-1: `false` dominates per-condition `U_c`

The one genuinely open design choice is the mixed cell: **one condition determined `false`, another `U_c`.** Two coherent semantics exist:

```text
D-1  false-dominant (adopted):   X=false, F=U_c  →  false
     (corresponds to strong-Kleene conjunction over partial values)

D-1′ U-dominant (registered alternative):
     X=false, F=U_c  →  unevaluable
     (aggregation-style: the conjunction determination "completes"
      only when ALL conjuncts are determined; corresponds to a
      weak/Bochvar-style reading)
```

**This is a spec decision, not a derivation.** v0.2 §5's necessity formulation ("Admissibility is false *or* unevaluable") is compatible with both, which is precisely why the choice had to be made explicit. Reasons for adopting D-1:

1. **Definitional boundary preservation (v0.2 §4).** `false` = "the determination completed with a negative result"; `unevaluable` = "the determination cannot be completed". A determined-false necessary condition *is* a completed negative determination — the determination of ¬Admissible is available and does not become unavailable because a different condition's determination failed. Reporting `unevaluable` there would conflate "no determination made" with "determination made: negative".
2. **Strong necessity reading.** The established law is single-failure-blocks (X- → BLOCKED, replicated). Under D-1′, unevaluability *elsewhere* could mask a known failure — a no-evidence consequence in tension with that law. D-1 preserves necessity in its strong form:

```text
Necessity (carried from v0.2 §5 + established findings):
    ¬c_i  ⇒  Admissibility ≠ true          (holds under both readings)

D-1 additionally fixes:
    mechanism intact ∧ ∃ determined-false c_i
        ⇒ output is false  (not unevaluable-from-that-configuration)
```

3. **No evidential support exists for either side.** No mixed configuration has ever been observed (§2.5). The decision is therefore made on definitional coherence and marked as **falsifiable** (§4, C-PROP-1) — exactly the kind of specific commitment Model B is allowed to make under the governing discipline.

### 3.3 The full function over the known conjuncts

Mechanism intact, conditions {X, F}:

| X \ F | true | false | U_c |
|---|---|---|---|
| **true** | true | false | unevaluable |
| **false** | false | false | **false** ← D-1 decision cell |
| **U_c** | unevaluable | false | unevaluable |

Mechanism non-functional: `unevaluable` in every cell (no per-condition states exist).

The `U_c` row/column is the **unobserved region**: predictions, not data (§2.5).

### 3.4 Back-compatibility check (no established mapping changes)

| Established finding | Configuration | Output under v0.3 | Change vs v0.2 |
|---|---|---|---|
| J1 baseline | X=true, F=true | true (COMPLETED / DEGRADED) | none |
| J2 F-absent | X=true, F=false | false (BLOCKED) | none |
| J3 X- | X=false, F=true | false (BLOCKED) | none |
| J4 both fail | X=false, F=false | false (BLOCKED) | none |
| K3-DELETED (846) | mechanism absent | unevaluable (C4 absent) | none |
| F-STALE → DEGRADED | quality, not admissibility | out of scope (unchanged) | none |
| F-IRRELEVANT → no blocking | non-condition | out of scope (unchanged) | none |

All previously defined cells are unchanged; v0.3 only fills the region v0.2 left undefined.

---

## 4. New commitment inventory (what Model B now asserts that can fail)

These are added to the commitment inventory of the identifiability note (§4). Each is tagged: **[established]** grounded in existing sealed findings · **[decision]** spec choice registered here · **[posit]** theoretical posit. Per the governing discipline, failures of any of these revise B — they never prove Model A (Model A absorbs any propagation behavior whatsoever; identifiability verdict unaffected, §6).

**C-PROP-1 [decision]** — *false-dominance signature.* If a configuration with one condition determined `false` and another `U_c` is ever realized, the output is `false` (transition-level: BLOCKED). The registered alternative D-1′ predicts the opposite (`unevaluable`; transition-level: absence/error signature, not BLOCKED). **Testability precondition**: realizing this configuration requires first operationalizing a manipulation that produces `U_c` for a known condition (§2.5) — a design-gate matter, not authorized here.

**C-PROP-2 [established instance / decision as generalization]** — *Level-0 preemption.* When the evaluation mechanism is non-functional, no partial per-condition determinations are observable — the 846 instance (C4 absent, no partial output) is established; its **generalization** ("no mixed report can ever coexist with mechanism-level absence") is a v0.3 commitment.

**C-PROP-3 [decision]** — *Order-independence.* The propagation reduction is symmetric: the output does not depend on the order in which conditions are determined or presented. (Registered as a commitment; note this is a claim about the *evaluation-output composition*, not about how conditions come to hold — those formations are outside this spec.)

**C-PROP-4 [decision]** — *Reporting purity of `unevaluable`.* `U_c` and Level-0 `unevaluable` never mean "a negative determination was made". Any observation in which an `unevaluable`-class output carries a completed negative determination would violate the v0.2 §4 boundary as extended here.

---

## 5. Interface to open questions (statuses unchanged)

| Question | Interface | Status |
|---|---|---|
| Q3 (E: conjunct or evaluation precondition?) | The two-level vocabulary (§2) makes both placements stateable; E's observed position (adoption-upstream) is unmoved | **Open, untouched** |
| Q4 (846: conjunct or precondition?) | K3 established at Level 0 (= v0.2 §4's own reading, restated); a Level-1 conjunct role in untested configurations remains possible | **Open, untouched** |
| Q7 (F-CONFLICTING) | Candidate instance class for `U_c` (determination-blocking contradiction) — **noted only; nothing interpreted** | **Unresolved, untouched** |
| Q6 (C emitted=true + BLOCKED) | Belongs to the identifiability note's evaluation-signature class (its Step 3), not to propagation | **Unresolved, untouched** |
| Q8 (unknown conditions) | The rule applies over whatever the condition set is; the set stays open | **Open, re-framed as B-uniformity (Step 2)** |
| Q1 (shared vs parallel) | Propagation presupposes neither (§2.4) | **Open** |
| Q5 (layered eligibility) | Not addressed | **Closed to reopening** |

---

## 6. Relation to the identifiability verdict

v0.3 operates entirely on **Model B's side** of the asymmetry established in the identifiability analysis: it makes B a complete function so that B's commitments are stateable and failable. Model A — which entails no outcome constraints — absorbs every row of §3.3's table as easily as every behavior observed to date. **Case 2 stands; nothing here reopens, revisits, or weakens it.** The completion removes the one *internal* obstacle the identifiability note registered (its §1 spec gap), and nothing else.

---

## 7. Summary

```text
COMPLETION:  Mixed-state propagation semantics — Model B is now a total function
VOCABULARY:  Level 0 = evaluation-mechanism operability (846-grounded)
             Level 1 = per-condition determination {true, false, U_c}
             U_c = posit, source taxonomy deliberately open (boundary-honoring)
DECISION:    D-1 = false dominates per-condition unevaluable
             (alternative D-1′ registered; decision marked falsifiable, not derived)
RULE:        false if any determined-false; else unevaluable if any U_c; else true
             Level-0 failure ⇒ unevaluable regardless; order-independent
BACK-COMPAT: every established finding maps to an unchanged cell
NEW:         commitments C-PROP-1..4 (all failure-revises-B, never proves A)
UNTOUCHED:   Q3/Q4/Q6/Q7/Q5 statuses; Phase A/B claims; 846 findings;
             identifiability verdict (Case 2); ND-1; all hard boundaries
NEXT:        Human Review of this spec → Step 2 (Model-B Uniformity /
             Necessary-Condition Probe) requires separate design gate + authorization
```
