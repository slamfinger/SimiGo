# Research Log — Execution Admissibility

Date: 2026-10-05
Terminal commit: `5f8bf23`
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
