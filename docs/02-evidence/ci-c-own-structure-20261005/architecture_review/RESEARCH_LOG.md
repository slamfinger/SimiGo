# Research Log — Execution Admissibility

Date: 2026-10-05
Terminal commit: `5f8bf23` (handoff snapshot; post-review state in Addendum at end of file)
Branch: `codex/execution-state-research-20260929`
Worktree: clean

---

## Complete research chain

| # | Phase | Commit | Status | Key finding |
|---|---|---|---|---|
| 1 | Phase A: Authorization | `ea537cc` | CLOSED | `A_epistemic / A_execution` behaviorally separable and ordered; ORDERED_SEPARATION_SUPPORTED (STRENGTHENED) |
| 2 | Phase B: Information | `1f4fcd7` | FROZEN | F-ABSENT → BLOCKED (replicated, semantically specific); F-STALE → quality; F-IRRELEVANT → non-condition; F-CONFLICTING → unresolved |
| 3 | Eligibility Conceptual Spec v0.1 | `66a600c` | FROZEN | `Eligible(T | C)` transition-relative, condition-evaluated |
| 4 | Joint Eligibility Probe | `747c310` | COMPLETE | X- and F-absent independently produce BLOCKED; shared eligibility constraint = CANDIDATE EVIDENCE |
| 5 | Evidence Synthesis | `6962dd9` | FROZEN | Behavioral convergence established; mechanism unresolved |
| 6 | Evidence-Constrained Refinement | `a19e3ba` | FROZEN | Condition roles empirically grounded; quality ≠ eligibility boundary |
| 7 | 846 × Eligibility Mapping | `cb07a67` | FROZEN | SAME STRUCTURAL ABSTRACTION LEVEL; 846 = State-side determinant candidate |
| 8 | Admissibility Spec v0.1 | `5ef2ffb` | FROZEN | Admissibility as broader construct; three phenomena distinguished |
| 9 | **Admissibility Spec v0.2** | `5f8bf23` | **FROZEN** | **Admissibility = conjunction of necessary conditions; three-state {true, false, unevaluable}** |

---

## Core conceptual framework

```text
              Execution Admissibility
              (candidate general research object)
                        │
          ┌─────────────┴─────────────┐
          │                           │
    Condition-side              State-side /
    Authorization              Function (846)
    Information                internal structure
          │                           │
          └──────── ? ────────────────┘
                   │
                   ▼
          Eligible(T | C)
       (operationalized subset)
                   │
               Transition
```

---

## Key definitions

| Term | Definition |
|---|---|
| `Eligible(T | C)` | Transition-relative, condition-evaluated; observable subset of Admissibility |
| `Admissibility(T | context)` | Broader property; ∈ {true, false, unevaluable} |
| Admissibility condition | Factor whose absence/denial produces BLOCKED (semantically specific, replicated, not generic validation) |
| Quality condition | Factor whose manipulation produces DEGRADED but not BLOCKED |
| Non-condition | Factor with no effect on transition |
| `unevaluable` | Evaluation mechanism structurally absent (846 K3-DELETED); distinct from `false` |

---

## Established behavioral findings

| Finding | Models | Source |
|---|---|---|
| X- → BLOCKED | C, N | Joint Probe J3 |
| F-absent → BLOCKED | C, N | Phase B + Joint Probe J2 |
| F-absent blocking is semantically specific | C, N | Generic-Validation Probe P3 |
| F-STALE → DEGRADED (not BLOCKED) | C, N | Phase B main |
| F-IRRELEVANT → no blocking | C, N | Phase B + probe |
| X- + F-absent → BLOCKED, no extra interaction | C, N | Joint Probe J4 |
| Both X and F are necessary but not sufficient | C, N | Joint Probe pattern |
| E- blocks adoption (upstream of transition) | C, N | Phase A |
| K3-DELETED → C4 absent (unevaluable) | C, N | CI-C |

---

## Open questions

| # | Question | Status |
|---|---|---|
| 1 | Shared eligibility function vs parallel independent gates? | Open; candidate evidence for shared constraint |
| 2 | Does Admissibility have conjunction structure (Model B) or is it a result label (Model A)? | Open; Model B more productive |
| 3 | Is E (epistemic) a separate conjunct or a precondition for evaluating X and F? | Open |
| 4 | Is 846 State-side integrity a conjunct or a precondition for evaluation? | Open; candidate unevaluable source |
| 5 | Layered eligibility (epistemic/execution stages)? | Open; Phase A candidate structure |
| 6 | C emitted=true + BLOCKED anomaly? | Unresolved; recorded, not interpreted |
| 7 | F-CONFLICTING model-dependent divergence? | Unresolved |
| 8 | Are there additional unknown Admissibility conditions? | Unknown |

---

## Hard boundaries

```text
No 846 atom mapping / reinterpretation
No Observer
No InformationCore write
No minimal Information Core claim
No A / B / D retry
No experiment without Human Review
No formalizing "admissibility information" as concept yet
No Eligible(T | S, C) extension without S definition + manipulation + interaction evidence
```

---

## Next session: how to continue

1. Read this file + `EXECUTION_ADMISSIBILITY_CONCEPTUAL_SPECIFICATION_V0.2.md`
2. The most productive next direction depends on Human Review:
   - Model A vs B discriminating experiment (requires new conceptual groundwork)
   - Multiple Necessary Conditions Probe (extend beyond X and F)
   - Or pause and begin a new research thread
3. Do NOT re-run existing experiments or re-open frozen phases.
4. All claims and their evidence levels are documented in the referenced commits.

---

## Addendum — 2026-10-05: Human direction after log review (Identifiability Analysis v0.1)

Human reviewed this log and Spec v0.2 and directed: settle **Model A/B identifiability before any discriminating experiment** (no code, no experiments).

Delivered: `EXECUTION_ADMISSIBILITY_MODEL_AB_IDENTIFIABILITY.md` (v0.1, committed with this addendum).

Verdict (PROPOSED — pending Human Review seal): **Case 2.** Model A (result label, as stated in v0.2) entails no outcome constraints, so A/B strict identifiability fails **by construction**, not by an evidence gap; A and B are observationally equivalent over the current observable space. Key registrations:

- **ND-1**: any newly established condition (D-absent → BLOCKED) is A/B-neutral evidence — it counts toward Q8 only, never as conjunction-structure evidence, and never as evidence for Model A.
- Model B retained as **productive hypothesis / explanatory model**; its empirical content relocates to its own falsifiable commitments: no-rescue necessity, mixed-state propagation semantics, uniform three-state behavior across conditions (Q8 re-scoped as B-testing, not A/B discrimination).
- Spec gap registered: v0.2 does not define mixed-state propagation (e.g., X `false` + F `unevaluable` → output class undefined). This is the precondition gap for any future mixed-configuration test.

Human priority order registered: Q2 (settled by this note, pending seal) > Q8 (re-scoped) > Q3/Q4. Q6 stays unresolved; Q7 stays uninterpreted; Q5 stays closed.

Next-step candidates (Human Review required; nothing auto-opens): ① Spec v0.3 — complete B's mixed-state propagation semantics (conceptual only); ② re-scoped Multiple Necessary Conditions Probe (design-gated, B-uniformity framing under ND-1); ③ evaluation-signature observable question (new, open — would re-pose identifiability on a wider observable space).

This addendum supersedes the "Next session" section above.

---

## Addendum 2 — 2026-10-05: Human ruling on next steps; Spec v0.3 delivered (Step 1)

Human accepted the Case 2 framing and registered, in order:

**Binding discipline**: no experiment may ever be recorded as "supports Model B". Experiments test **specific commitments** of B; a commitment failure means "current B formulation refuted / needs revision" — never "Model A proven". "D- → BLOCKED" licenses only "D is a candidate necessary condition", never "therefore Admissibility is conjunction".

**Three-step order**:

- **Step 1 (immediate)** — Spec v0.3: complete mixed-state propagation semantics. Concept closure only. → **DELIVERED**: `EXECUTION_ADMISSIBILITY_CONCEPTUAL_SPECIFICATION_V0.3.md` (committed with this addendum; PENDING HUMAN REVIEW).
- **Step 2 (after Step 1; separate design gate + Human Review)** — Multiple Necessary Conditions Probe, renamed **Model-B Uniformity / Necessary-Condition Probe**: tests whether new conditions exhibit the same necessary-condition structure as X and F. Never an A/B discriminator (ND-1 in force).
- **Step 3 (kept at distance)** — Evaluation-Signature question: whether a new observable dimension (evaluation-side signature separable from transition-side result) can shrink Model A's hypothesis space and re-pose identifiability. NOT started.

v0.3 summary: two-level evaluation vocabulary (Level 0 = mechanism operability, 846-grounded; Level 1 = per-condition determination {true, false, U_c}, U_c = registered posit with source taxonomy deliberately open) + total order-independent propagation rule; **spec decision D-1 = false-dominant over per-condition unevaluable** (alternative D-1′ U-dominant registered; decision marked falsifiable, not derived); new commitments C-PROP-1..4; back-compatibility with all established findings verified (no cell changed); Q3/Q4/Q6/Q7/Q5 untouched; identifiability verdict (Case 2) and ND-1 unaffected; no experiment authorized.

State after this commit: Step 1 delivered pending Human Review; Step 2 / Step 3 NOT started; nothing auto-opens.
