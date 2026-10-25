# Order-Reversal Probe Results

Date: 2026-10-05
Status: `ORDER_REVERSAL_COMPLETE`
Run root: `a_e_execution/order_reversal/runs/20261005-101500-order-reversal`
Baseline: `a_e_execution/runs/20261005-093200-a-e-execution` (commit `e191067`)

## Controlled variable

Only one change from baseline: Authorization layer declarations table lists `A_execution` before `A_epistemic` (X → E order). The baseline lists `A_epistemic` before `A_execution` (E → X order).

Everything else frozen: same 8 arms, same models (C, N), same template text, same F_content, same metrics, same runtime, same temperature (0), same max_tokens (1024).

## Observed matrix — Order-Reversal (X → E)

### Model C

| Arm | F visible | adoption | execution_gate.status | C4 emitted | Matches expected |
|---|---|---|---|---|---|
| E+ X+ | true | true | ELIGIBLE | true | ✅ |
| E+ X- | true | true | INELIGIBLE | false | ✅ |
| E- X+ | true | false | ELIGIBLE | false | ✅ |
| E- X- | true | false | ELIGIBLE | false | ✅ |

### Model N

| Arm | F visible | adoption | execution_gate.status | C4 emitted | Matches expected |
|---|---|---|---|---|---|
| E+ X+ | true | true | ELIGIBLE | true | ✅ |
| E+ X- | true | true | INELIGIBLE | false | ✅ |
| E- X+ | true | false | INELIGIBLE | false | ✅ |
| E- X- | true | false | INELIGIBLE | false | ✅ |

## Cross-condition comparison (baseline vs order-reversal)

| Arm | Baseline C adoption/C4 | Reversal C adoption/C4 | Baseline N adoption/C4 | Reversal N adoption/C4 | Pattern stable? |
|---|---|---|---|---|---|
| E+ X+ | true / true | true / true | true / true | true / true | ✅ |
| E+ X- | true / false | true / false | true / false | true / false | ✅ |
| E- X+ | false / false | false / false | false / false | false / false | ✅ |
| E- X- | false / false | false / false | false / false | false / false | ✅ |

**All 8 cells produce the same behavioral pattern in both metadata ordering conditions, on both models.**

## Primary conclusion

The ordered-separation behavioral pattern is **not a prompt-metadata ordering artifact**. Reversing the presentation order from E → X to X → E does not change the observed adoption and C4 outcomes.

This directly attacks and weakens the strongest rival explanation identified in `RIVAL_EXPLANATION_REVIEW.md` (Q2: "ordered interpretation has not been tested by reversing the metadata order in the prompt").

## Result label

```text
ORDERED_SEPARATION_SUPPORTED (STRENGTHENED)
```

The label is strengthened from the first round because the ordering confound has been experimentally controlled and the pattern survived.

## Interpretation

The behavioral contrast `E → adoption; X → C4` survives independent of the order in which the two authorization layers are declared in the prompt. This is consistent with the two layers being functionally distinct in the model's processing, not merely sequentially ordered by presentation.
