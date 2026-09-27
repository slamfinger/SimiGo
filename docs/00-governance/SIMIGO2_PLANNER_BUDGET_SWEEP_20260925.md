# SimiGo 2.0 Planner Budget Sweep — 2026-09-25

Status: PHASE_BUDGET_SWEEP_SIMULATOR_PASS / WORKLOAD_TRACE_PENDING  
Model inventory: `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`  
Boundary: SIMULATOR_ONLY / DESCRIPTIVE_RECENCY_HINTS / NOT_PREDICTION / NOT_DEMAND_CLAIM

## Command

```bash
simigo2ctl budget-sweep MODEL_SNAPSHOT
```

Default budgets are percentages of full inventory bytes:

```text
25, 40, 50, 60, 70, 80, 90, 100, 110, 120, 150
```

The sweep covers all registered state sequences. Demand hints are descriptive
recency labels derived only from prior states in the same sequence. They do not
predict future state and do not establish execution demand.

## Inventory

```text
recommended bytes = 17,180,913,664
core bytes        = 873,459,712
entries           = 66
```

## First no-overflow budget

| Sequence | First fitting percent | Overflow below it |
|---|---:|---|
| `LOCALITY_A` | 40% | 25%: 5 transitions |
| `ALTERNATE_AB` | 40% | 25%: 5 transitions |
| `CYCLE_ABC` | 40% | 25%: 6 transitions |
| `ALTERNATE_A_AB` | 70% | 40%: 2; 50%: 2 |
| `BASELINE_ABA` | 100% | 40–60%: 2; 70–90%: 1 |
| `FULL_PARTIAL` | 100% | 40–90%: 3 |

At 40%, `LOCALITY_A`, `ALTERNATE_AB`, and `CYCLE_ABC` fit because each active
state requires only one optional switch group. Sequences containing
`STATE_AB` require more than one optional group and overflow at 40%.

## Key planning trade-off

| Sequence | Percent | Loaded bytes | Evicted bytes | Peak resident bytes | Fits |
|---|---:|---:|---:|---:|---|
| `ALTERNATE_AB` | 40% | 27,179,089,920 | 21,743,271,936 | 6,309,277,696 | true |
| `ALTERNATE_AB` | 70% | 10,871,635,968 | 0 | 11,745,095,680 | true |
| `BASELINE_ABA` | 40% | 27,179,089,920 | 10,871,635,968 | 17,180,913,664 | false |
| `BASELINE_ABA` | 100% | 16,307,453,952 | 0 | 17,180,913,664 | true |
| `FULL_PARTIAL` | 70% | 27,179,089,920 | 10,871,635,968 | 17,180,913,664 | false |
| `FULL_PARTIAL` | 100% | 16,307,453,952 | 0 | 17,180,913,664 | true |

The result is expected: lower budgets reduce idle residency but increase
materialization traffic unless the sequence has sufficient locality. This is a
planning trade-off measurement, not evidence that real workload demand exists.

## Boundary

This phase does not authorize Predictor, Expert demand, Token × Expert demand,
real async I/O, or production residency policy. The next gate must replace the
synthetic state sequences with replayable workload traces and measure reload
cost / temporal locality on the real runtime.

Raw artifact:

`simigo2-experimental/results/planner-budget-sweep/qwen3-coder-default.json`
