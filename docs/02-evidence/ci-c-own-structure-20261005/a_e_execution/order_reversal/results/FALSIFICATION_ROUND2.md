# Second Falsification Review

Date: 2026-10-05
Scope: Order-Reversal Probe + baseline 8-cell experiment
Previous review: `a_e_execution/results/RIVAL_EXPLANATION_REVIEW.md`

## Q2 revisit: Single hidden mechanism vs two ordered layers

### What the order-reversal probe adds

The first review's most important gap was: "the ordered interpretation has not been tested by reversing the metadata order in the prompt." The order-reversal probe closes this gap.

**Result: the pattern did not reverse.** `E → adoption; X → C4` is stable across both metadata ordering conditions and both models.

This makes the single-mechanism explanation less plausible. A single mechanism that reads the metadata sequentially would be expected to produce a different behavioral sequence when the metadata order is reversed. The fact that it does not suggests the model is processing the two layers by their semantic content, not by their positional order.

### Updated confidence

Previous: moderate–high for "two distinct mechanisms"
Current: **high for "the behavioral pattern is not driven by metadata presentation order"**

Whether the model internally implements two genuinely distinct mechanisms is still not directly observable, but the behavioral evidence for ordered separability is now robust to at least one significant confound.

## Remaining untested rival explanations

1. **Partial-adoption route.** The model could adopt fragments of F without formally declaring adoption. Not directly probed.
2. **Template phrasing effects.** The exact wording of the E_REASONS and X_REASONS strings may contribute to the pattern. A paraphrase control would test this.
3. **Semantic content vs positional order.** The reversal controlled for positional order but not for the semantic content of the labels. If the model treats "PREMISE_ADOPTION_ALLOWED" and "EXECUTION_PATH_ELIGIBLE" as semantically distinct role assignments, that is consistent with ordered separation, not against it.
4. **Mechanistic probe.** No direct probe of internal representations. The claim remains behavioral.

## Summary

| Falsification test | Status | Impact on ORDERED_SEPARATION_SUPPORTED |
|---|---|---|
| Prompt metadata order reversal | **Passed** (pattern stable) | Strengthens |
| Cross-model replication (C, N) | **Passed** in both conditions | Strengthens |
| Factorial separation | **Passed** | Strengthens |
| E- non-bypass | **Passed** | Strengthens |
| Partial-adoption probe | Not run | No impact |
| Template paraphrase | Not run | No impact |
| Mechanistic probe | Not run | Limits claim to behavioral |

## Final assessment

`ORDERED_SEPARATION_SUPPORTED` is now robust to:

- cross-model replication (C, N);
- prompt metadata ordering (E→X and X→E);
- factorial separation across all 8 cells;
- non-bypass in E- cells.

The remaining limitation is that the claim is behavioral, not mechanistic. It describes how the model's output respects the declared two-layer order; it does not prove that the model's internal processing implements two distinct sequential gates.
