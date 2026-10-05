# Joint Eligibility Probe Design

Date: 2026-10-05
Status: `DESIGN_PROPOSED · NOT_FROZEN · RUN_NOT_AUTHORIZED`
Open question: Do Authorization and Information converge on a common `Eligibility(T | C)`?
Predecessor: `EXECUTION_ELIGIBILITY_CONCEPTUAL_SPECIFICATION.md` (frozen at `66a600c`)

---

## 1. Open question

Phase A manipulates Authorization conditions (E±, X±).
Phase B manipulates Information conditions (F-present/absent).

Both produce behavioral outcomes consistent with a transition eligibility boundary. Whether they feed into the **same** `Eligibility(T | C)` function is unknown.

---

## 2. Minimal joint design

Simultaneously vary one Authorization condition and one Information condition on the same transition.

| Dimension | Source | Levels |
|---|---|---|
| Authorization: X (A_execution) | Phase A | X+ (eligible) / X- (not eligible) |
| Information: F | Phase B | F-present / F-absent |

### 2 × 2 matrix

| Cell | X | F | Phase A alone predicts | Phase B alone predicts | Joint question |
|---|---|---|---|---|---|
| J1 | X+ | F-present | C4 emitted | COMPLETED | baseline |
| J2 | X+ | F-absent | C4 emitted (X satisfied) | **BLOCKED** | does info condition override? |
| J3 | X- | F-present | **C4 withheld** | COMPLETED | does auth condition block at info-present baseline? |
| J4 | X- | F-absent | C4 withheld | **BLOCKED** | do both conditions interact? |

Note: Phase A's E dimension is fixed at E+ (premise adoption allowed) to isolate the X × F interaction. E is not varied in this probe.

---

## 3. Predicted patterns under competing hypotheses

### H-SHARED: Authorization and Information feed into the same eligibility function

```text
Eligible(T | C) = f(..., X, F, ...)
```

If either X or F independently makes eligibility false, the transition is blocked.

| Cell | Prediction |
|---|---|
| J1 | executable |
| J2 | **BLOCKED** (F absent) |
| J3 | **BLOCKED or suppressed** (X denies execution) |
| J4 | **BLOCKED** (both deny; at least one is sufficient) |

Key signature: J2 and J3 both produce a **non-executable** outcome (BLOCKED or equivalent suppression). Either condition alone is sufficient to make the transition ineligible.

### H-INDEPENDENT: Authorization and Information are separate mechanisms

Authorization controls emission of an already-formed analysis.
Information controls whether the transition can initiate.

| Cell | Prediction |
|---|---|
| J1 | executable |
| J2 | **BLOCKED** (cannot initiate without F) |
| J3 | **DEGRADED** (transition executes, output suppressed by X-) |
| J4 | **BLOCKED** (cannot initiate) |

Key signature: J3 produces `DEGRADED` (transition still happens, output withheld), not `BLOCKED`. This would indicate the two conditions operate at different stages of the pipeline.

### H-AUTHORIZATION-DOMINANT: Authorization overrides Information

| Cell | Prediction |
|---|---|
| J1 | executable |
| J2 | executable (X+ overrides info absence) |
| J3 | suppressed (X- blocks) |
| J4 | suppressed |

Key signature: J2 does NOT block despite F being absent. This would mean Phase B's F-ABSENT blocking only occurs when X+ (i.e., authorization permits execution).

### H-INFORMATION-DOMINANT: Information overrides Authorization

| Cell | Prediction |
|---|---|
| J1 | executable |
| J2 | BLOCKED (F absent blocks) |
| J3 | executable (F present overrides X-) |
| J4 | BLOCKED |

Key signature: J3 does NOT suppress despite X-. This would mean Phase A's X- withholding only occurs when F is present.

---

## 4. Discriminating power

| Pattern in J2 + J3 | Supports |
|---|---|
| J2 = BLOCKED, J3 = BLOCKED/suppressed | **H-SHARED** (either condition independently makes ineligible) |
| J2 = BLOCKED, J3 = DEGRADED | **H-INDEPENDENT** (different pipeline stages) |
| J2 = executable, J3 = suppressed | **H-AUTHORIZATION-DOMINANT** |
| J2 = BLOCKED, J3 = executable | **H-INFORMATION-DOMINANT** |
| J2 = executable, J3 = executable | **No eligibility effect from either alone; interaction needed** |

---

## 5. Implementation notes

### Template

Based on Phase B's `TEMPLATE_B.prompt.txt` with the following additions:

1. Add the Authorization layer declarations (same as Phase A's template).
2. Fix E = PREMISE_ADOPTION_ALLOWED.
3. Vary X between EXECUTION_PATH_ELIGIBLE / NOT_ELIGIBLE.
4. Vary F between the Phase B F-present and F-absent information sections.

### Output contract

Merge Phase A and Phase B JSON schemas:

```json
{
  "source_ledger": {"F_content_visible": true, "F_premise_adopted": true, "adoption_reason": "..."},
  "analysis": {"admissible_premises": ["F"], "relational_conclusion": "..."},
  "execution_gate": {"status": "ELIGIBLE | INELIGIBLE", "reason": "..."},
  "continuation": {"emitted": true, "deployment_order": ["..."], "blocked_services": [...]},
  "transition_status": "COMPLETED | DEGRADED | BLOCKED",
  "information_dependency": {"compatibility_info_available": true, "dependency_declared": true, "reason": "..."},
  "provenance": {"used_model_prior": false, "used_visible_but_nonadopted_F": false, "reason": "..."}
}
```

### Models

C and N. Total: 4 cells × 2 models = 8 runs.

---

## 6. Non-goals

No new Information types. No E-dimension variation (E fixed at E+). No PALACE / MCP / Memory / RAG / remote API / Observer / InformationCore / 846 / mechanistic probe. No new models.

---

## 7. Proposed gate

1. Human Review of this design.
2. If approved: freeze, implement, run 8 cells.
3. Falsification review.
4. Update Architecture Review with results.

---

## Amendment 1 (Human Review, 2026-10-05)

### 1. BLOCKED and suppressed are distinct phenomena

`BLOCKED` = candidate eligibility boundary. `Suppressed` = behavior withheld; mechanism not yet proven to be the same as eligibility.

These are **not interchangeable** in hypothesis interpretation. Any observed `suppressed` outcome must be classified separately from `BLOCKED` until further evidence links them.

### 2. Hypothesis labels are candidate interpretations, not conclusions

The four competing hypotheses (H-SHARED / H-INDEPENDENT / H-AUTHORIZATION-DOMINANT / H-INFORMATION-DOMINANT) are **discriminating patterns**, not established conclusions. Observing a matching pattern produces **candidate evidence** for that interpretation, not proof.

Revised interpretation table:

| J2 + J3 pattern (relative to J1) | Candidate interpretation |
|---|---|
| J2 = BLOCKED, J3 = BLOCKED | candidate evidence for shared eligibility constraint |
| J2 = BLOCKED, J3 = DEGRADED | candidate evidence for independent pipeline stages |
| J2 = executable, J3 = suppressed | candidate evidence for authorization-dominant |
| J2 = BLOCKED, J3 = executable | candidate evidence for information-dominant |
| J2 = executable, J3 = executable | no single-condition eligibility effect; interaction question only |

None of these are proofs. Each requires C/N replication and Human Review before upgrade.

### 3. J1 is the baseline anchor

All comparisons are **relative to J1**, not absolute:

```text
Δ(J2, J1)  = effect of F-absent at X+
Δ(J3, J1)  = effect of X- at F-present
Δ(J4, J1)  = combined effect
```

If C and N have different J1 baselines (e.g., C COMPLETED vs N DEGRADED), the Δ comparison must be made within each model, not across models.

### 4. J4 is a combined-condition / interaction probe

J4 does not carry standalone interpretation. Its role is:

- if `J4` matches the prediction from `J2` and `J3` independently → no additional interaction observed
- if `J4` deviates from the prediction → interaction question is opened, not resolved

J4 alone cannot establish or refute any hypothesis.

### 5. Unchanged constraints

- E fixed at E+.
- C/N replication required for all candidate interpretations.
- No expansion to 3D probe.
- No PALACE / MCP / Memory / RAG / Observer / InformationCore / 846 / mechanistic probe.

---

## Revised status

```text
DESIGN STATUS: APPROVED WITH REVISION
RUN STATUS: NOT YET AUTHORIZED
NEXT: Human Review of this amendment → Run Authorization
```
