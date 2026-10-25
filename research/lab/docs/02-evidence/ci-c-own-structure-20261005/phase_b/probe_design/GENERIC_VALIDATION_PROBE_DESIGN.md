# Generic-Validation Rival Probe Design

Date: 2026-10-05
Status: `DESIGN_PROPOSED · NOT_FROZEN · RUN_NOT_AUTHORIZED`
Predecessor: `phase_b/run/results/EVIDENCE_BOUNDARY.md` (frozen at `0fd301d`)

---

## 1. Rival explanation under test

The primary rival explanation for `F-ABSENT → BLOCKED` is:

> The model applies a generic "required field is missing" rule. Any field named as required in the prompt, when absent, triggers the same block regardless of its semantic content.

This probe tests whether blocking is driven by:
- (a) the **semantic role** of the missing Information (decision-relevant vs decision-irrelevant), or
- (b) the **mechanical fact** that a named-required field is empty.

---

## 2. Design principle

One variable: **the semantic identity of the absent field.**

Everything else frozen: same Execution State transition, same candidate set, same models (C/N), same template structure, same output contract, same runtime.

---

## 3. Two information fields

| Field | Content | Semantic role |
|---|---|---|
| **F** | Baseline compatibility record for alpha/beta/gamma | **decision-relevant**: determines whether the release transition can execute |
| **G** | Deployment window annotation (e.g., "approved maintenance window: 2026-10-05 22:00–02:00 UTC") | **decision-irrelevant**: named as required metadata in the prompt, but does not determine executability |

Both fields are introduced in the "Available information" section with equal formality. The model is not told which one is decision-relevant.

---

## 4. Probe cells

| Cell | F | G | Question |
|---|---|---|---|
| P1 | present | present | baseline: both available |
| P2 | **absent** | present | replicates prior F-ABSENT condition |
| P3 | present | **absent** | does absence of decision-irrequired G also block? |
| P4 | absent | absent | does double absence produce the same block as F-absent alone? |

Cells P1 and P2 serve as replication anchors. **P3 is the critical new cell.** P4 tests additivity.

---

## 5. Expected signatures

| Outcome pattern | Interpretation |
|---|---|
| P3 → COMPLETED (same as P1) | Generic-validation rival **weakened**. Blocking depends on semantic role, not just field presence. |
| P3 → BLOCKED | Generic-validation rival **strengthened**. The model blocks whenever any named-required field is missing. H3 evidence from F-ABSENT is significantly undermined. |
| P4 → BLOCKED (same as P2) | Blocking is driven by F absence specifically, not by additive absence count. |
| P4 → different from P2 | Absence effects may interact. Interpretation depends on direction. |

---

## 6. Models

C and N only. Total: 4 cells × 2 models = 8 runs.

---

## 7. Template changes from Phase B main run

Only one change: the "Available information" section now contains two labeled fields (F and G) rather than one. Everything else (task, rules, output contract, JSON schema) is identical.

The G field introduction sentence:

```text
Deployment metadata (required):
  approved maintenance window: 2026-10-05 22:00–02:00 UTC
```

When absent:

```text
Deployment metadata: not available in this context.
```

---

## 8. Output contract

Same as Phase B main run, with one added field:

```json
"information_dependency": {
  "compatibility_info_available": true,
  "compatibility_info_current": true,
  "compatibility_info_consistent": true,
  "deployment_metadata_available": true,
  "dependency_declared": true,
  "reason": "..."
}
```

`deployment_metadata_available` tracks whether the model notices G's absence separately from F's.

---

## 9. Non-goals

No new Information types beyond F and G. No new models. No PALACE / MCP / Memory / RAG / remote API / Observer / InformationCore / 846 / mechanistic probe. No template paraphrase.

---

## 10. Proposed gate

1. Human Review of this design.
2. If approved: freeze design, implement prompts and runner.
3. If approved: run 8 cells (C + N).
4. Falsification review.
5. Update Evidence Boundary.
