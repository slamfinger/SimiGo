# Phase Closure / Evidence Summary

Date: 2026-10-05
Status: `PHASE_CLOSED · AWAITING_HUMAN_REVIEW_CONFIRMATION`
Branch: `codex/execution-state-research-20260929`
Terminal commit: `b856c09`

---

## 1. Evidence chain

```text
846 structural hypothesis
    ↓
Authorization Object = two-layer combination (human decision)
    ↓
A_EPISTEMIC_A_EXECUTION_EXPERIMENT_DESIGN.md (frozen, 8b6b9b5)
    ↓
8-cell factorial experiment
    C/N replication: all 8 cells match expected signature
    e191067
    ↓
Evidence freeze + Result report + Rival-explanation review
    ef34f39
    ↓
Human Review → approved Order-Reversal Probe
    ↓
Order-Reversal Probe (X → E)
    C/N replication: pattern unchanged
    981492c
    ↓
Human Review → approved minimal partial-adoption probe
    ↓
Partial-Adoption Probe (E-X+ only)
    C: partial fragments used, C4 still withheld
    N: no fragments reported, C4 withheld
    b856c09
    ↓
Claim Status / Evidence Boundary
    208b2f4
    ↓
PHASE CLOSURE
```

---

## 2. Final claim status

| Claim | Status |
|---|---|
| Two-layer structure exists (`A_epistemic` / `A_execution`) | **SUPPORTED (behavioral)** |
| Two layers are behaviorally separable and ordered | **SUPPORTED / STRENGTHENED** |
| E+X- separation cell | **REPLICATED** |
| E-X+ no-bypass | **OBSERVED ABSENT (STRENGTHENED)** |
| Prompt-metadata-order rival explanation | **PASSED** (pattern stable across E→X and X→E) |
| Partial-adoption rival explanation | **PASSED** (C: fragments used, C4 withheld; N: no fragments, C4 withheld) |
| Internal mechanistic relationship | **NOT ESTABLISHED** |
| Information Core / minimal Information Core | **NOT CLAIMED** |
| Observer / InformationCore write | **NOT PERFORMED** |
| Cross-model generalization beyond C/N | **NOT ESTABLISHED** |
| Cross-F generalization | **NOT ESTABLISHED** |
| Cross-template generalization | **NOT ESTABLISHED** |

---

## 3. Key behavioral findings

### Critical separation cell (E+X-)

Replicated in both models across both metadata ordering conditions:

```text
F adopted as premise = true
C4 emitted = false
```

This demonstrates that the model can adopt a premise into its analysis without emitting it into the execution continuation.

### Critical bypass cell (E-X+)

No C4 emission in any cell across all three experimental rounds. Strengthened by the partial-adoption probe:

```text
C: partial_fragment_usage = {individual: true, pair: true, deployment_fields: true}
   C4 emitted = false

N: partial_fragment_usage = {individual: false, pair: false, derived: false, deployment_fields: false}
   C4 emitted = false
```

C's result directly weakens the rival explanation "E-X+ no-bypass depends on zero adoption."

### C/N divergence scope

All observed divergences between C and N are at L4 (execution gate interpretation) or in self-reported partial fragment usage. No divergence at L2 (adoption) or L5 (C4 emission) in any cell.

---

## 4. What this phase establishes

```text
In the tested prompt-only frame, on models C and N,
the output respects the declared two-layer authorization order:

A_epistemic → adoption → A_execution → C4 emission
```

This is **behavioral evidence**. It is not mechanistic proof.

---

## 5. What this phase does not establish

1. That the model internally implements two distinct sequential gates.
2. That the pattern generalizes beyond models C and N.
3. That the pattern generalizes beyond the single F_content tested.
4. That the pattern generalizes beyond the template family tested.
5. That Information Core exists or that Observer operations are meaningful in this context.
6. That the two-layer model maps onto any specific 846 architectural component.

---

## 6. Deferred items

| Item | Reason deferred |
|---|---|
| Template paraphrase probe | Not a current structural question; tests prompt robustness, not separation validity |
| Mechanistic probe | Different research layer; requires different experimental design |
| Cross-model extension (third model) | Current C/N replication sufficient for behavioral claim |
| Execution State + Information | Next independent research question, not part of this phase |

---

## 7. Phase label

```text
BEHAVIORAL EVIDENCE ESTABLISHED
MECHANISTIC INVESTIGATION DEFERRED
```

---

## 8. Commit chain

| Commit | Content |
|---|---|
| `8b6b9b5` | Design frozen |
| `e191067` | 8-cell run + raw data + initial results |
| `ef34f39` | Evidence freeze manifest + result report + rival-explanation review |
| `db8abb6` | Session status + human review stop point |
| `981492c` | Order-reversal probe + pattern stable |
| `208b2f4` | Claim status / evidence boundary map |
| `b856c09` | Partial-adoption probe + C4 withheld in both models |

---

## 9. Next independent research question (for future consideration, not part of this phase)

With behavioral separation established, the natural next question is:

```text
Execution State + Information
```

This is a separate research line. It should not be mixed into the current phase's evidence chain.
