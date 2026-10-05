# Rival-Explanation / Falsification Review

Date: 2026-10-05
Status: `FALSIFICATION_REVIEW_COMPLETE · AWAITING_HUMAN_REVIEW`
Scope: `RESULT_REPORT.md` + frozen run data (commit `e191067`)

This document does not add new experiments. It interrogates the existing 8-cell result against the three rival-explanation questions the human specified, and against any additional confounds that were not addressed in the design document.

---

## Q1. Does C4 truly represent execution-layer behavior?

### What C4 is

In this experiment, C4 emission is defined by the `continuation.emitted` field and the presence of non-empty `deployment_order` / `blocked_services` in the JSON output. The model is instructed to populate these fields only if the execution gate permits it.

### Is C4 sufficient evidence?

C4 is a **declared behavioral output**, not a mechanistic probe. The model writes `"emitted": true` or `"emitted": false`. This is self-report.

### What strengthens the claim

1. The behavior is **structurally consistent**: in every `E+X-` cell (C and N), the model reports adoption = true, execution gate = INELIGIBLE, and leaves `deployment_order` and `blocked_services` empty. The declared gate status and the emitted fields agree.
2. The behavior is **cross-model replicated**: C and N show the same pattern.
3. The behavior is **factorially separated**: only changing `X` at fixed `E+` suppresses C4; changing `E` alone does not.
4. The behavior matches the expected ordered signature exactly, not approximately.

### What weakens the claim

1. The model could be pattern-matching the prompt metadata (`EXECUTION_PATH_NOT_ELIGIBLE`) to produce `"emitted": false` without a genuine internal "execution layer." The behavioral separation is real; the mechanistic separation is inferred.
2. There is no independent probe (e.g., a secondary task that asks the model to explain *why* it withheld C4) that would distinguish "genuinely applying two sequential gates" from "reading the X- label and suppressing output."

### Verdict

C4 is **valid as a behavioral marker** of execution-layer suppression, replicated across C/N with factorial separation. It is **not sufficient as a mechanistic proof** that the model internally implements two distinct sequential gates. The claim is bounded to: *the model's output behavior respects the declared two-layer order.*

---

## Q2. Could adoption and C4 be controlled by the same hidden mechanism?

### The concern

If a single undifferentiated mechanism reads the prompt metadata and produces both adoption status and C4 status from the same internal computation, then the "two-layer" pattern would be an artifact of the prompt structure (which lists E before X) rather than evidence of two genuinely ordered gates.

### Evidence from the data

1. **`E+X-` shows adoption = true but C4 = false.** If a single mechanism controlled both, then suppressing C4 should also suppress adoption (or vice versa). The fact that they can be independently manipulated (E changes adoption without changing C4's dependence on X; X changes C4 without changing adoption) is strong evidence against a single undifferentiated switch.
2. **`E-X+` shows adoption = false but execution_gate.status can still be reported.** In C's output, the gate reports `ELIGIBLE` even though no premises exist. This suggests the model can represent the execution layer's state independently of whether any premises exist to populate it — consistent with two separable layers.
3. **N reports `INELIGIBLE` at `E-X+`.** N interprets the gate differently, but the behavioral outcome (no C4) is identical. The fact that two models reach the same L2/L5 output through different L4 framings weakly suggests that the L2/L5 pattern is not fragile to L4 interpretation.

### What would falsify ordered separability

If a new experiment varied the order of E/X metadata in the prompt (e.g., X listed before E) and the behavioral pattern reversed, that would suggest the "order" is a prompt-structure artifact, not a behavioral property.

### Verdict

The factorial separation (especially `E+X-`: adoption true / C4 false) is **strong behavioral evidence against a single undifferentiated mechanism**. However, the ordered interpretation (E → X, not X → E) has not been tested by reversing the metadata order in the prompt. This is the most important untested rival explanation.

---

## Q3. Is E-X+ non-bypass sufficient to rule out other paths?

### What was tested

In `E-X+`, the execution path is declared eligible but F is not adoptable. Neither model emits C4. This is consistent with ordered separation: no premise enters the execution path, so no C4.

### What was NOT tested

1. **Alternative adoption sources.** The design only tests whether F itself is adopted. It does not test whether the model could adopt a *partial* or *derived* version of F from the visible context without formally "adopting F." The E- prompt says F must not be adopted, but the model could form a relational conclusion from partial fragments without declaring adoption. No cell shows evidence of this, but it has not been directly probed.
2. **Indirect prompting.** A model could follow a different reasoning chain that reaches the same C4 output without traversing the E→X path. The JSON schema constrains the output format but does not constrain the internal reasoning path.
3. **Context-window leakage through related fields.** The `adoption_reason` field in E- cells contains the E- instruction text, which re-states "gamma is not individually baseline-compatible." If the model retains this string in context during the continuation step, it could in principle use it. However, in both models' E- cells, `blocked_services` is empty, so this leakage did not materialize in this run.

### Verdict

E-X+ non-bypass is **consistent with ordered separation** and provides good evidence that the execution path does not independently generate C4 without adopted premises. It is **not sufficient to exhaustively rule out all alternative paths**, because:
- the model's internal reasoning chain is unobservable;
- partial-adoption routes have not been directly probed;
- context-window residual effects have not been tested with a clean-context continuation.

---

## Summary of falsification status

| Question | Answered? | Confidence | Remaining gap |
|---|---|---|---|
| Q1: Does C4 represent execution-layer behavior? | Yes, behaviorally | High for behavioral claim | No mechanistic probe; self-report only |
| Q2: Single hidden mechanism? | Unlikely given factorial separation | Moderate–High | Order-reversal control not run |
| Q3: Other paths ruled out? | Partially | Moderate | Partial-adoption probe and order-reversal not run |

---

## Recommended next minimal experiment (for Human Review decision, not authorized)

The single most informative minimal perturbation would be:

**Prompt-metadata order reversal.** Run the same 8 cells but list X before E in the Authorization layer declarations table.

- If the pattern is preserved, the ordered interpretation is strengthened against the prompt-structure artifact.
- If the pattern reverses, the "order" is a prompt artifact and the claim must be narrowed to "the prompt-listing order controls the behavioral sequence."

This is one variable, uses the same 8 cells, and does not add models or new infrastructure.
