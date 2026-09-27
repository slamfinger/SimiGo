# SimiGo 2.0 Planner Runtime Integration — Phase R0 — 2026-09-24

Status: PHASE_R0_PLANNER_RUNTIME_INTEGRATION_PASS  
Model: `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`  
Boundary: ENGINEERING_INTEGRATION_ONLY / NO DEMAND OR PREDICTION CLAIM

## Scope

Phase R0 connects the pure `ExecutionResidencyPlanner` to the existing
simulator and real MLX residency runtime. It does not introduce a Predictor,
async streaming, Router/Expert research, or a new formal theory layer.

The old policy baseline remains available and is not deleted.

## 1. Unit and equivalence gate

Fixed the planner build regression caused by malformed Swift key paths.

Result:

```text
swift test = PASS / 23 tests
```

Added `ExecutionPlannerPolicy` and `ResidencyPolicyKind.executionPlanner`.
For every `ExecutionStateLabel`, the planner-driven policy produces the same
load, keep, evict, resident-set, byte, and event ordering as the legacy
reactive policy.

Simulator comparison for `STATE_A → STATE_B → STATE_A`:

```text
legacy reactive loaded bytes    = 17,180,913,664
legacy reactive evicted bytes   = 10,871,635,968
legacy reactive peak bytes      = 6,309,277,696

execution planner loaded bytes  = 17,180,913,664
execution planner evicted bytes = 10,871,635,968
execution planner peak bytes    = 6,309,277,696
```

Raw artifact:

`simigo2-experimental/results/planner-integration/simulator-benchmark-ab-a.json`

## 2. Planner/runtime split

The real MLX path now uses two explicit planner calls:

1. **Execution load plan**
   - required execution set = `CORE_NON_SWITCH ∪ all optional groups`;
   - every group is required for a complete Transformer forward;
   - missing groups are materialized before generation.

2. **Retention plan**
   - required retention set = the state's desired policy set;
   - optional groups not retained are released after generation.

This preserves the old runtime invariant that generation never semantically
skips a layer group. The planner controls materialization and idle retention;
it does not change the model graph.

## 3. Real MLX Gate R0 result

States:

```text
STATE_A → STATE_B → STATE_AB → STATE_A → STATE_ALL
```

All fifteen generations returned `pong`.

```text
outputIdentityPass                 = true
idleReductionObserved              = true
maximum idle reduction             = 10,871,635,200 bytes
reload reduction vs naive          = 10,871,635,968 bytes
reloadReductionVsNaiveObserved     = true
benchmarkPass                      = true
```

Policy totals:

| Policy | Generation ms | Reload ms | Reload bytes | Release bytes |
|---|---:|---:|---:|---:|
| `ALL_RESIDENT` | 5,663.75 | 0.00 | 0 | 0 |
| `NAIVE_ON_DEMAND` | 7,500.71 | 7,722.27 | 65,229,815,808 | 81,537,269,760 |
| `EXECUTION_STATE_PLANNER` | 7,800.11 | 7,209.34 | 54,358,179,840 | 38,050,725,888 |

Latency advantage remains **NOT ESTABLISHED**: planner-driven generation was
slower than all-resident in this short workload.

Raw artifact:

`simigo2-experimental/results/planner-integration/mlx-gate5-planner-standard.json`

An additional `STATE_A → STATE_B → STATE_A` run is retained to show a
non-local sequence where the planner is correct but reload reduction is not
observed:

`simigo2-experimental/results/planner-integration/mlx-gate5-planner-ab-a.json`

## Decision

Phase R0 passes. The Required Execution Set → Bounded Planner →
Load/Keep/Evict path now operates over the existing real MLX runtime without
breaking output identity.

Next work must be workload traces, locality measurement, and budget sweeps.
Predictor, Expert demand, Token × Expert demand, preload, and async I/O remain
outside the authorized Phase R0 boundary.
