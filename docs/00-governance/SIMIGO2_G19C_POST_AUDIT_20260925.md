# G1.9-C Post-Audit — Layer/Group Execution Line Closed — 2026-09-25

Status: GROUP_RESOLUTION_EXECUTION_LOCALITY_CLOSED / RESOLUTION_DEGENERATE_NO_PREDICTIVE_TARGET
Scope: the G1.9-C collection coverage (5 models × 4 workload shapes × 25 operations each, scenario prompts, ≤16-token generations)
Boundary: MEASURED_LAYER_ENTERED_ONLY / NOT_DEMAND / NOT_PREDICTION

This audit elevates the G1.9-C degenerate result from an experimental
finding to the formal terminal of the layer/group execution-locality line.
Three conclusions are locked.

## 1. The execution set at this resolution is the full set — everywhere observed

```text
∀ (m, w, t) in coverage:   M(m,w,t) = G_all(m)
therefore:                 |M_t| = |G_all|  and  ΔM_t = ∅
```

This holds at every observed step (125 operations × 5 models), not "mostly".
Within the covered boundary there is no execution-set differential at
Layer/Group resolution.

## 2. The Predictor question is semantically closed, not underperforming

Because `M_t = G_all` throughout the coverage:

```text
P(M_{t+1} = G_all | H_t) = 1   for every history H_t
```

but this is not a predictor worth building: there is no
`H_t → different execution set` mapping to learn. The correct statement is
NOT "predictor performance is insufficient" but:

```text
LAYER/GROUP EXECUTION DEMAND FORMS NO DIFFERENTIAL VARIABLE
REQUIRING PREDICTION WITHIN THE CURRENT EXPERIMENT BOUNDARY.
```

Accordingly the earlier `PREDICTOR_STOP_GATE_NO_GO` is upgraded to:

```text
RESOLUTION-DEGENERATE / NO PREDICTIVE TARGET   (layer/group resolution)
```

No predictive algorithm is to be pursued at this resolution. The historical
NO_GO entries remain in the ledger; this upgrade is the terminal semantics.

## 3. The residency research is not invalidated

The measured full execution set does not imply a full resident set:

```text
RequiredExecutionSet_t ≠ ResidentSet_t   (both remain distinct objects)
```

Therefore the registered real-runtime results stand unchanged: reload
savings of 16.7–55% versus naive on-demand across 20 (model, trace) pairs,
with output identity preserved. They answer the question:

> given that every complete execution needs all decoder groups, which
> parameters may keep residing between executions to reduce the next
> rematerialization?

and not the question:

> which layers will not execute next?

The Experimental route's two objects are now formally separated:

```text
Input / Context ──┬── Execution Set   → measured FULL SET at this resolution
                  └── Residency Set   → policy-controlled, may vary
                                        → reload economics (measured)
```

## Research-tree freeze point

```text
A2.0                                    FROZEN / TERMINAL
Experimental Engineering Route
  ├── ⑦ Declared workload locality      intervention value PASS (declared line)
  ├── G1.9-A Instrumentation Identity   PASS (pilot 4 gates, 5/5 models)
  ├── G1.9-C Measured Execution         Layer/Group = FULL SET; C1–C4 degenerate
  │     └── STOP                        Execution locality CLOSED
  │                                     Predictor CLOSED (resolution-degenerate)
  └── next: Residency Observability Audit
        └── sufficient → residency analysis
            insufficient → minimal residency observation first
```

Research discipline: the degenerate execution result must not be used to
justify opening Router/Expert observation "to keep the research going". If a
concrete phenomenon ever requires it — e.g. "executions are always ALL, yet
optimal resident sets differ by history" — that phenomenon would earn the
deeper resolution on evidence. Router/Expert observation remains an
unauthorized new decision.

Post-audit history: this document; collection results in
docs/00-governance/SIMIGO2_G19C_MEASURED_TRACE_COLLECTION_20260925.md.
