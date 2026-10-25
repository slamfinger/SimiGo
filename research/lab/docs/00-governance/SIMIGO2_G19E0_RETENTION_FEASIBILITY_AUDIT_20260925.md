# G1.9-E0 Retention Optimization Feasibility Audit — 2026-09-25

Status: G19E0_FEASIBILITY_TRADEOFF_ONLY / NEXT_GATE_USER_DECISION
Protocol: G1.9-E0.FEASIBILITY.V1
Authorization: user ruling 2026-09-25 — E0 only; purely offline over existing artifacts; candidate enumeration/replay authorized; optimizer implementation NOT opened
Boundary: OFFLINE_FEASIBILITY_AUDIT / CANDIDATE_POLICIES_NOT_OPTIMA / NOT_DEMAND / NOT_PREDICTION / NO_NEW_RUNTIME_OBSERVATION / PER_MODEL_PER_WORKLOAD_NO_POOLING

Frozen vocabulary check: no "optimal"-family term (OptimalResidentSet,
OptimalRetentionPolicy, RetentionPredictor, ResidencyDemand,
RetentionProbability) appears in the analysis or its artifact — candidates
are candidates, not optima.

## Question (as authorized)

Does a candidate retention policy P' ≠ P exist with lower reload bytes,
without increasing the resident budget, while execution correctness is
preserved — i.e., is there measurable policy-improvement space at all?

## Method

Purely offline. State sequences come from the 20 real trace artifacts; group
bytes from the per-model inventories. Candidate family:

```text
POLICY_STATE_RETENTION    current policy (retention = declared state groups)
CANDIDATE_FILL_PEAK       state-independent: retain the largest optional
                          groups filling the current policy's peak budget
CANDIDATE_ALL_RESIDENT    ceiling reference
CANDIDATE_CORE_ONLY       floor reference (hypothetical; not the measured
                          naive policy, which starts with optionals resident)
```

Metrics per candidate: total reload bytes, peak resident bytes, mean
resident bytes, retained-byte integral, load/evict transition counts.
80 candidate-replays total (4 candidates × 20 pairs).

## Structural facts used (previously measured/validated)

1. Execution set = ALL at every generation (G1.9-C, measured): every
   generation must find all optional groups resident, so
   `reload(t) = optionalTotal − retainedOptionalBytes(t−1)`.
2. Therefore `reloadTotal = n·optionalTotal − Σ_{t=0..n−2} retainedBytes(t)`
   — **total reload is exactly determined by the retention time-integral
   over the first n−1 steps.** Verified numerically for every candidate on
   every pair.
3. Correctness (E4): because the harness loads all missing groups before
   each generation, any post-generation retention policy preserves outputs.
   This is a structural offline argument; it is empirically verified only
   for the three measured policies (output identity PASS on all 20 runs).

## Results (20 pairs; condensed)

| Workload | current reload → fill@peak reload (GiB) | current mean → fill@peak mean (GiB) | peak (both) |
|---|---|---|---|
| T1 (Qwen3-Coder) | 55.69 → 40.50 | 7.56 → 10.94 | 10.94 |
| T2 (Qwen3-Coder) | 50.62 → 35.44 | 7.90 → 10.94 | 10.94 |
| T3 (Qwen3-Coder) | 81.00 → 15.19 | 8.69 → 16.00 | 16.00 |
| T4 (Qwen3-Coder) | 30.38 → 15.19 | 12.96 → 16.00 | 16.00 |

The same pattern holds on all five models (see artifact for full tables).

## Three feasibility verdicts

```text
V1  equal PEAK budget     improvers EXIST on 20/20 pairs: CANDIDATE_FILL_PEAK
                          reaches the current policy's own peak every step
                          and reload drops (e.g. T3 81.0 → 15.19 GiB) —
                          but mean residency rises to the peak
                          (e.g. 8.69 → 16.00 GiB)
V2  equal TIME-INTEGRAL   frontier EXACT on 20/20 pairs and for every
                          candidate: reloadTotal = n·optTotal − leading
                          integral. At equal resident-byte integral no
                          policy can have lower total reload — provably,
                          not empirically.
V3  domination            NO candidate dominates the current policy on
                          (reload, mean residency, peak) — 20/20. The
                          current policy lies on the trade-off frontier.
```

## Verdict

```text
FEASIBLE_TRADEOFF_SPACE_ONLY_NO_FREE_IMPROVEMENT
```

The answer to `∃ P' ≠ P : Cost(P') < Cost(P)` depends on which axis the
"budget" constraint E3 binds:

- budget = peak resident bytes → YES, candidates exist (V1);
- budget = resident-byte time-integral → NO, provably impossible (V2);
- and under no interpretation does a candidate dominate the current policy
  (V3): every reload gain pays with higher mean residency.

There is no free improvement and no dominated-policy gain. The entire
policy space at this resolution is the linear trade-off frontier between
retention integral and reload bytes; the current policy and the fill-to-peak
candidate are two points on it. E1 (reload) can only improve by spending E2
(resident integral), E3 fixes which point is admissible, and E4 holds
structurally for all of them.

T4-ALL boundary note: the workload with full-retention steps is also where
the fill-to-peak candidate coincides with all-resident retention — the
execution-side/residency-side object separation is preserved under
candidate replay.

## Consequence (per authorization — decision returns to the user)

Feasible candidates exist only as trade-offs. A "Retention Optimization
Candidate Analysis" gate could only re-describe this frontier unless it
introduces a new cost weighting or new evidence (e.g., measured residency
preferences of real workloads) — both new decisions. The alternative
reading is that E0 already supplies the engineering answer: the current
policy is on the frontier, and the frontier itself is exactly characterized.

Options (not entered):

a. Candidate analysis gate under a declared cost weighting;
b. STOP here: frontier characterized + no free improvement is itself a
   complete engineering conclusion.

No optimizer, predictor, probability, speculative retention, new runtime
observation, MLX modification, or architecture declaration follows from
this audit. A2.0 remains FROZEN/TERMINAL.

## Artifacts

```text
simigo2-experimental/scripts/audit_retention_feasibility.py
simigo2-experimental/results/residency-audit/retention-feasibility.json
```
