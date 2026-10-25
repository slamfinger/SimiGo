# G1.9-D PolicyResidency Retention Analysis — 2026-09-25

Status: G19D_RETENTION_STRUCTURE_CHARACTERIZED / NEXT_GATE_USER_DECISION
Protocol: G1.9-D.RETENTION.V1
Authorization: user ruling 2026-09-25 — option (a) exclusively; narrow authorization over existing artifacts only
Boundary: POLICYRESIDENCY_RETENTION_STRUCTURE / BYTE_VALIDATED_BOOKKEEPING / NOT_DEMAND / NOT_PREDICTION / NOT_RESIDENCY_LOCALITY / PER_MODEL_PER_WORKLOAD_NO_POOLING

Naming note: this phase is deliberately NOT called "Residency Locality". Its
object is the retention structure of the policy, never natural residency
demand. The C_model offsets (Nail/Cyber-Tiel −851.1/−851.5 MiB) remain
sealed as inventory-vs-loaded-model accounting corrections; they do not
enter any quantity below — D1–D4 use policy bookkeeping bytes and the
executed transfer log, not memory snapshots.

## Research question (as authorized)

> With execution set fixed at ALL, does the existing residency policy's
> retention structure exhibit stable cross-operation structure, and does
> that structure explain the previously measured reload-traffic reduction?

## Method

`R_t^policy` (policy resident set after transition t) is reconstructed from
the state sequences of the 20 real trace artifacts via the validated
bookkeeping (core + retention optionals per state). All quantities are
computed per (model, workload); no pooling. The naive and all-resident
policies serve as retention floor/ceiling references. T4/STATE_ALL steps are
retained as the full-retention boundary.

## D1 — Retention recurrence (byte-weighted, optional part)

Mean optional-byte keep ratio |Q_t ∩ R_{t+1}| / |R_{t+1}| per workload —
identical across models with equal state-sequence geometry, shifted only
where group bytes differ (Nail/Cyber-Tiel's half-size third group):

| Workload | Qwen3-Coder | Nail | Cyber-Tiel | Gemma4 | Muse-Glimmer |
|---|---:|---:|---:|---:|---:|
| T1 | 0.600 | 0.600 | 0.600 | 0.600 | 0.600 |
| T2 | 0.500 | 0.500 | 0.500 | 0.500 | 0.500 |
| T3 | 0.521 | 0.537 | 0.537 | 0.521 | 0.524 |
| T4 | 0.667 | 0.742 | 0.742 | 0.667 | 0.680 |

Retention is deterministic given (policy, state sequence): the keep ratios
are structural constants of the workload shape, not random quantities.

## D2 — Transition retention

Per-transition kept/added/removed sets are recorded in the artifact for all
20 pairs. The measured reload at each generation equals exactly the
complement of the previous retention set (the harness loads all missing
optional groups before each generation), so the transition structure fully
determines the measured transfer stream.

## D3 — Retention stability (lag-1 byte overlap of R_t)

| Workload | Qwen3-Coder | Nail | Cyber-Tiel | Gemma4 | Muse-Glimmer |
|---|---:|---:|---:|---:|---:|
| T1 | 0.643 | 0.704 | 0.692 | 0.785 | 0.766 |
| T2 | 0.553 | 0.630 | 0.616 | 0.731 | 0.707 |
| T3 | 0.572 | 0.660 | 0.646 | 0.740 | 0.721 |
| T4 | 0.689 | 0.795 | 0.788 | 0.785 | 0.782 |

Interpretation is restricted to "temporal stability of the policy retention
structure"; it is not execution locality.

## D4 — Retention structure ↔ reload economics

Exact accounting identity, verified against measurements on all 20 pairs:

```text
savings(naive − policy) = Σ_t retainedOptionalBytes(t) − oneColdStartLoad
identity holds:      20 / 20   (tolerance < 0.1%)
```

This decomposes the previously measured 16.7–55% savings precisely: the
savings are the retained-optional-bytes integral of the workload minus the
single cold-start load. Workloads with broader retention breadth realize
proportionally more savings:

| Workload | savings fraction of naive (5-model range) | full-retention steps |
|---|---|---|
| T1 | 0.267 – 0.360 | 0/6 |
| T2 | 0.167 – 0.250 | 0/5 |
| T3 | 0.333 – 0.425 | 1/9 (FINAL_ANSWER) |
| T4 | 0.500 – 0.550 | 2/5 (CONTEXT_LOAD, CONTEXT_SUMMARY) |

T4-ALL boundary contrast (as registered): on the execution side M_t = ALL
everywhere with no structure; on the residency side T4 contains the
full-retention boundary steps AND realizes the largest savings fraction —
the two sides are cleanly separated objects.

## Verdict (pre-registered rule applied)

```text
D4 identity:            20/20 pairs  (< 0.1% tolerance)
D1–D3 patterns:         deterministic given (policy, state sequence)
result:                 POLICY_RETENTION_STRUCTURE_EMPIRICALLY_CHARACTERIZED
```

The retention structure is stable and its correspondence with reload
economics is exact. Per the authorization, the claim stops here:

```text
PolicyResidency retention structure is empirically characterized.
```

No optimization, prediction, or probability layer follows automatically.
Whether studying retention optimization is worthwhile is a new decision on
new evidence. The frozen vocabulary (ResidencyDemand, ResidencyProbability,
RetentionPredictor, OptimalResidentSet, predictedResidentSet) appears
nowhere in this analysis or its artifacts.

## Artifacts

```text
simigo2-experimental/scripts/analyze_policy_retention.py
simigo2-experimental/results/residency-audit/policy-retention-analysis.json
```
