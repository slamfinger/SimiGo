# Group-Resolution Experimental Line Closure — 2026-09-25

Status: G19E0_STOP / GROUP_RESOLUTION_POLICY_TRADEOFF_CLOSED
Authority: user ruling 2026-09-25 — option (b) STOP; terminal, stronger than a pause
Scope: the entire group-resolution Experimental research line of SimiGo 2.0

## Ruling (registered)

The E0 audit compressed the group-resolution policy space into one exact
trade-off frontier; continuing candidate analysis without a new value
function or real constraint evidence would produce no new mechanistic
knowledge. The line therefore closes here.

Locked boundaries (all permanent until reopened by new problems/evidence):

```text
- no Candidate Analysis
- no cost weighting definition
- no optimizer definition
- no optimal policy definition
- no Router/Expert observation
- no additional runtime instrumentation
- no production MLX modifications
```

## Terminal results (the two objects, separately concluded)

### Execution object

```text
MeasuredExecution = FULL          (G1.9-C, 125 operations × 5 models)
⇒ Layer/Group locality degenerate
⇒ No predictive target
⇒ PREDICTOR CLOSED (RESOLUTION-DEGENERATE / NO PREDICTIVE TARGET)
```

### Residency object

```text
PolicyResidency                   (byte-validated, observability audit)
⇒ Retention structure characterized   (G1.9-D, D1–D4)
⇒ Exact reload identity:
    ReloadTotal = n·OptionalTotal − Σ_{t=0..n−2} RetainedBytes_t
    (verified 20/20 pairs, exact; C_model offsets sealed as accounting items)
⇒ Trade-off frontier (E0):
    peak-budget reading  — improvers exist, paying with mean residency
    integral reading     — improvement provably impossible
    domination           — none; current policy on the frontier
⇒ No free improvement
```

The precise final formulation, replacing any vague "remaining optimization
space":

> **A residency/reload trade-off exists; a free improvement does not.
> Reload reduction ⟺ additional retention integral, exactly, under the
> current model/trace/harness conditions.**

The user's Δ-form: between candidates, ΔReload = −ΔRetentionIntegral; with
no external constraint weights (λ_reload, λ_residency) there is no legal
basis to prefer one candidate over another, and further enumeration yields
no mechanistic knowledge.

## The pairing this line leaves behind

What began as "can execution-state predict layer demand to optimize model
residency?" ends as a clean negative-plus-positive result pair:

```text
NEGATIVE: at layer/group resolution there is no execution locality a
          Predictor could exploit — execution is the full set everywhere
          observed, so no differential variable exists to predict.

POSITIVE: even without execution locality, policy-level residency retention
          is strictly measurable, byte-validated against independent MLX
          observations, its retention structure is characterized, and its
          reload economics decompose exactly into a linear trade-off
          frontier with no free improvement.
```

This is a complete stage closure, not an incomplete investigation.

## Reopening conditions

Reopening requires a NEW problem or NEW evidence — never "remaining
optimization space". Examples of the kind of trigger that would legitimately
open a new engineering question:

```text
- a real deployment constraint pair, e.g. peak memory ≤ X GiB AND
  reload latency ≤ Y ms (a bounded, weighted optimization problem);
- measured workload-specific SLA or long-session memory-pressure evidence;
- a measured materialization/compute overlap cost structure;
- evidence that execution is NOT the full set at some resolution or model
  class (would require new observation, itself a new authorization).
```

None of these exist today; all would be new authorizations.

## Research tree — final form for this line

```text
SimiGo 2.0 Experimental
  ├── EXECUTION OBJECT
  │     measured = ALL → locality degenerate → predictor closed
  │
  └── RESIDENCY OBJECT
        policy-derived → byte-validated → D1–D4 characterized
        → E0 feasibility → trade-off exists / no free gain
        → CURRENT RESOLUTION CLOSED
```

History chain (all registered):

```text
⑦ declared locality + intervention value → PREDICTOR_STOP_GATE_NO_GO
G1.9-A authorization → identity pilot (4 gates, 5/5 models) → PASS
G1.9-C measured collection → degenerate → post-audit closure of execution line
Residency observability audit → byte-level validation → split verdict
G1.9-D retention analysis → characterized (exact economics identity)
G1.9-E0 feasibility audit → trade-off frontier only → STOP (this ruling)
```

A2.0 remains FROZEN/TERMINAL and untouched by this line. No optimizer,
predictor, probability, speculative retention, new instrumentation, MLX
modification, or architecture declaration follows from this closure.
