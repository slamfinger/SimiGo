# SimiGo 2.0 Multi-Model Locality Analysis & Predictor Stop Gate — 2026-09-25

Status: PHASE_LOCALITY_ANALYSIS_PASS / PREDICTOR_STOP_GATE_NO_GO
Scope: ANALYSIS_ONLY — no new runtime capability, no Predictor, no async I/O
Boundary: DECLARED_TRACE_STATE_MAPPING / DESCRIPTIVE_RECENCY_HINTS / NOT_PREDICTION / NOT_DEMAND_CLAIM / PER_MODEL_PER_TRACE_NO_POOLING

## Registered model set

All five checkpoints are local; simulator replay is header-only, real runs use
the existing planner-integrated Gate 5 harness.

| Model | Partition | Layers | Core GiB | Optional groups GiB | Real trace runs |
|---|---|---:|---:|---|---|
| `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit` | SWITCH_MLP | 48 | 0.81 | 5.06 / 5.06 / 5.06 | 4/4 PASS |
| `peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX` | SWITCH_MLP | 40 | 3.27 | 6.75 / 6.75 / 3.38 | 4/4 PASS |
| `peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-MLX-oQ4e` | SWITCH_MLP | 40 | 2.78 | 6.75 / 6.75 / 3.38 | 4/4 PASS |
| `mlx-community/gemma-4-12b-coder-fable5-composer2.5-4bit` | DENSE_MLP | 48 | 1.79 | 1.48 / 1.48 / 1.48 | 4/4 PASS |
| `RadixArk/Muse-Glimmer-q4-MLX` | DENSE_MLP | 52 | 3.73 | 3.76 / 3.76 / 3.34 | 4/4 PASS |

First registrations from this phase:

- Cyber-Tiel-Coder-35B-A3B-MLX-oQ4e (`qwen3_5_moe`) loads and passes Gate 5
  output identity on all four traces; first residency validation of this
  checkpoint.
- The local Muse-Glimmer checkpoint resolves to repo `RadixArk/Muse-Glimmer-q4-MLX`
  (`model_type muse_glimmer`, 52 layers). Semantic quality remains UNRESOLVED
  (raw-fallback repeated tokens, no bundled chat template); memory/IO
  measurements and cross-pass output identity remain valid.

All 20 real runs: `benchmarkPass = true`, `outputIdentityPass = true`.

## Transition structure (trace property, model-invariant)

The required-set transition structure is identical across models because the
declared state sequences are identical. Per trace, over optional-group parts
of consecutive required sets:

| Trace | overlap mean | next ⊆ prev ratio |
|---|---:|---:|
| T1 | 0.400 | 0.400 |
| T2 | 0.375 | 0.250 |
| T3 | 0.396 | 0.250 |
| T4 | 0.500 | 0.250 |

This quantifies the declared separation "just executed ≠ next required":
three quarters or more of transitions are not strict supersessions of the
previous optional set. Recency retention still hits because the three-step
window covers alternation; it fails when the required set broadens (T4 ALL).

## Simulator replay (per model × trace, required-hit ratio at 100% budget)

| Trace | Qwen3-Coder | Nail | Cyber-Tiel | Gemma4 | Muse-Glimmer |
|---|---:|---:|---:|---:|---:|
| T1 | 0.888 | 0.908 | 0.904 | 0.934 | 0.928 |
| T2 | 0.872 | 0.894 | 0.890 | 0.923 | 0.916 |
| T3 | 0.935 | 0.944 | 0.942 | 0.960 | 0.956 |
| T4 | 0.766 | 0.807 | 0.801 | 0.834 | 0.826 |

- The hit-ratio ordering T3 > T1 > T2 > T4 is invariant across all five
  models: it is a property of the declared trace mappings, not of model
  geometry.
- The byte economics are geometry-dependent: Nail/Cyber-Tiel need ≥90% budget
  before two-group steps fit (two switch groups = 83.8% of inventory);
  Gemma4's small dense groups fit single-group steps below 40%.
- T4 is the minimum in every column: registered as the working-set-breadth
  boundary workload. It stays a permanent counterexample in the trace catalog
  and is not pooled into "locality success".

## Real-runtime intervention effect (reload saved vs naive on-demand)

| Trace | Qwen3-Coder | Nail | Cyber-Tiel | Gemma4 | Muse-Glimmer |
|---|---:|---:|---:|---:|---:|
| T1 | 20.25 GiB (27%) | 30.38 GiB (36%) | 30.38 GiB (36%) | 5.93 GiB (27%) | 15.46 GiB (29%) |
| T2 | 10.12 GiB (17%) | 16.88 GiB (25%) | 16.88 GiB (25%) | 2.97 GiB (17%) | 7.94 GiB (18%) |
| T3 | 40.50 GiB (33%) | 57.38 GiB (43%) | 57.38 GiB (43%) | 11.87 GiB (33%) | 30.50 GiB (35%) |
| T4 | 30.38 GiB (50%) | 37.12 GiB (55%) | 37.12 GiB (55%) | 8.90 GiB (50%) | 22.14 GiB (51%) |

- State-driven retention reduced cumulative reload bytes on all 20 (model,
  trace) pairs; per-trace reduction ratios are stable across models.
- Note the inverse ordering vs declarative locality: T4 has the lowest
  required-hit ratio but the highest real reload-reduction ratio. The
  reduction measures naive waste avoided (naive reloads every optional group
  at every transition), not trace locality. These are different quantities
  and must not be conflated.
- Latency advantage remains NOT ESTABLISHED. Generation totals are comparable
  between policies; on Nail and Cyber-Tiel T3/T4 the state-driven pass is
  slightly slower in generation time than naive (e.g. Cyber-Tiel T3 35.65 s
  vs 29.67 s). No latency claim is made.

## Stop gate assessment

Gate criteria (registered before reading the verdict):

```text
G1 recurrence            optional groups recur within a trace with short gaps
G2 transition locality   consecutive required sets overlap substantially
G3 intervention value    retention materially reduces real reload bytes
G4 source legitimacy     the phenomenon is measured from real execution,
                         not built into the workload definition
```

Results:

```text
G1 = OBSERVED (declared level only; reuse gaps 1–2 steps by construction)
G2 = MODERATE (overlap 0.375–0.5; next ⊆ prev 0.25–0.4)
G3 = PASS (20/20 real runs; 16.7–55% reload reduction)
G4 = NOT SATISFIABLE AT CURRENT EVIDENCE
```

G4 fails by absence, not by contradiction: every locality number in this
phase is a property of the declared operation→state mappings and of the
recency hints reacting to them. The traces prove the planning machinery
responds correctly to a declared working set; they do not measure whether
real execution exhibits exploitable locality. No real-workload execution
trace exists in the repository yet.

## Verdict

```text
PREDICTOR_STOP_GATE = NO_GO
```

STOP is the registered research conclusion of this phase, a complete result:
the execution-centric residency machinery (required set → bounded planner →
load/keep/evict) is validated end-to-end on five models, and the observed
reload reductions are an engineering response to declared workloads — not
evidence of predictable demand.

The locality question can only be reopened by measured execution traces.
The already-registered route for that measurement is ISOLATED_INSTRUMENTATION
(G1.9-A infrastructure COMPLETE, direct public-API capture REJECTED,
instrumentation identity probe PASS on Qwen3-Coder). Opening that route is a
separate gate decision, NOT STARTED, and requires explicit authorization.

Unchanged boundaries: Predictor / Expert demand / Token × Expert demand /
real async I/O / production residency policy remain unauthorized. A2.0
remains FROZEN; no A2.0 object is restored or extended by this analysis.

## Artifacts

```text
simigo2-experimental/scripts/analyze_trace_locality.py
simigo2-experimental/results/workload-trace/{qwen3-coder-default,gemma4-12b-coder-sim,
  nail-qwen36-35b-sim,cyber-tiel-35b-sim,muse-glimmer-30b-sim}.json
simigo2-experimental/results/workload-trace/{qwen3-coder-real-*,gemma4-12b-coder-real-*,
  nail-qwen36-35b-real-*,cyber-tiel-35b-real-*,muse-glimmer-30b-real-*}-{T1..T4}.json
simigo2-experimental/results/workload-trace/analysis/locality-analysis.json
```
