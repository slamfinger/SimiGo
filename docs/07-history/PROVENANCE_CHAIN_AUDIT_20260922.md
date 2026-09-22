# Provenance Chain Audit — 2026-09-22

> Purpose: connect the existing Track B / Track E closure chains to the new archive taxonomy without creating new research claims or changing gate state.
> Scope: SimiGo-Lab only. This document is an audit/index record, not a new experiment, finding, or decision.

## 1. Track B — execution-state closure chain

```text
F1–F4 lifecycle evidence
  → F5-1/F5-2 representation and migration evidence
  → F5-3 Step 1 policy simulation
  → F5-3 Step 2/3 live four-strategy + estimator results
  → Track B Closure v4
  → CLOSED / FROZEN
```

### Archive interpretation

| Stage | Existing source | Archive role | Status handling |
|---|---|---|---|
| F1–F4 | `trackB-execution-state/EXECUTION_FORK_F*_...md` | evidence | historical evidence; preserve original paths |
| F5-3 Step 1 | `EXECUTION_FORK_F5_3_STEP1_POLICY_SIM_RESULTS_20260921.md` | evidence | simulation evidence; do not treat modeled latency as runtime measurement |
| F5-3 Step 2/3 | `EXECUTION_FORK_F5_3_STEP23_LIVE_RESULTS_20260921.md` | evidence | real-device evidence within explicitly stated 12-trial / single-configuration scope |
| Closure | `TRACK_B_CLOSURE_RESULTS_20260921.md` | closure | authoritative Track B endpoint; CLOSED / FROZEN |

### Boundary preserved

The closure document explicitly separates lifecycle semantic correctness from performance generalization, estimator robustness, and residency behavior. Therefore the archive must not collapse the evidence chain into a generic 'performance result'.

## 2. Track E — nodes-out closure chain

```text
Correctness evidence
  → Effect Interpretation Contract
  → Tier-1 mechanism accounting
  → Mechanism Synthesis Review
  → Effect Verdict Design Revision v0.2
  → Path / Endpoint Decision
  → Research Question Coverage Audit + E3 supplement
  → Research Endpoint Decision
  → Track E CLOSED
```

### Archive interpretation

| Stage | Existing source | Archive role | Status handling |
|---|---|---|---|
| correctness | `trackE-residency/` correctness record | evidence | historical evidence |
| contract | `trackE-residency/` Effect Interpretation Contract record | evidence / governance constraint | frozen provenance anchor |
| accounting | Tier-1 mechanism accounting records | evidence | modeled/accounting evidence; not runtime effect evidence |
| synthesis | `NODES_OUT_EFFECT_MECHANISM_SYNTHESIS_REVIEW_v0.1.md` | finding/synthesis | historical interpretation record |
| design revision | `NODES_OUT_EFFECT_VERDICT_DESIGN_REVISION_v0.2.md` | decision/design | historical accepted design revision |
| path decision | `NODES_OUT_PATH_ENDPOINT_DECISION_v0.1.md` | decision | historical path analysis; its conditional language must remain conditional |
| endpoint | `NODES_OUT_RESEARCH_ENDPOINT_DECISION_v0.1.md` | closure | endpoint record; later superseded as an active gate snapshot by the final closure record |
| final closure | `TRACK_E_CLOSED_RECORD_20260922.md` | closure | current Track E closure fact |

### Boundary preserved

Track E's `LOCKED` effect verdict is not an effect measurement result. The endpoint record explicitly distinguishes established accounting facts from a registered future runtime prediction. The archive therefore keeps those as separate evidence/decision layers.

## 3. Definition / Opening chain

```text
STEP ① research object boundary
  → STEP ② minimal research object C1
  → STEP ③ independence argument
  → STEP ④ estimand: not started
```

| Stage | Source | Archive role | Current state |
|---|---|---|---|
| STEP ① | `SOURCE_RUNTIME_RESEARCH_DEFINITION_OPENING_v0.1.md` | question/definition source | PASS / registered |
| STEP ② | `SOURCE_RUNTIME_RESEARCH_QUESTION_DEFINITION_v0.1.md` | question-definition source | Q2.1 C1 selected; remaining STEP ② work is governed by current state |
| STEP ③ | `SOURCE_RUNTIME_INDEPENDENCE_ARGUMENT_v0.1.md` | independence argument | external review PASS; registration is governed by state record |
| STEP ④ | not yet produced | question/estimand | NOT STARTED |

**Important:** this archive audit does not register STEP ④, allocate an RQ ID, define an estimand, or authorize measurement.

## 4. Architecture relationship

`docs/architecture/ARCHITECTURE_2.0_PRERESEARCH_20260920.md` remains the directional 2.0 source document. Its Track B / Track A / Track D descriptions are treated as historical strategic framing, while current research state is governed separately by `RESEARCH_STATE.md` and later track-specific closure records.

Architecture statements must therefore be cited with their source and date; they are not silently promoted to current implementation requirements.

## 5. Provenance rules established by this audit

1. **Closure beats directory name.** A directory can contain multiple historical strata; the explicit closure/endpoint record controls the closure meaning.
2. **Evidence beats synthesis for factual claims.** Findings and decisions may interpret evidence but must retain evidence anchors.
3. **Prediction is not evidence.** Registered future predictions remain predictions until a separately authorized research chain tests them.
4. **Historical drafts remain history.** A superseded draft is not deleted merely because a later revision exists.
5. **Current state remains external to this archive taxonomy.** `RESEARCH_STATE.md` remains the state authority.
6. **No gate advancement by documentation work.** Creating this audit does not advance Definition / Opening, unlock implementation, or authorize measurement.

## 6. Review outcome

Track B and Track E now have explicit archive-level provenance chains, while the Definition / Opening chain remains visibly incomplete at STEP ④. No historical result was promoted, no frozen asset was modified, and no new research line was opened.