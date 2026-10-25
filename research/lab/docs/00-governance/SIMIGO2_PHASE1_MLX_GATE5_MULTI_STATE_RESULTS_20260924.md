# SimiGo 2.0 Phase 1 — MLX Multi-State Runtime Residency Gate 5 Results

**Date**: 2026-09-24
**Status**: GATE_5_MULTI_STATE_RUNTIME_RESIDENCY_PASS / LATENCY_ADVANTAGE_NOT_ESTABLISHED
**Model**: `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`
**States**: `STATE_A → STATE_B → STATE_AB → STATE_A → STATE_ALL`

## 1. Gate

Run the same deterministic prompt on a real MLX model under three policies:

1. `ALL_RESIDENT`: keep all three optional groups resident.
2. `NAIVE_ON_DEMAND`: after each complete generation, release all optional groups;
   before the next complete generation, rematerialize all of them.
3. `EXECUTION_STATE`: after each complete generation, release optional groups not
   desired by the next state; before the next complete generation, rematerialize
   every missing group.

Every complete Transformer generation still traverses all decoder-layer groups.
The policies therefore control idle retention, not semantic layer skipping.

## 2. Result

```text
outputIdentityPass                  = true
idleReductionObserved               = true
maximum idle reduction vs resident  = 10,871,635,200 bytes
reload reduction vs naive           = 10,871,635,968 bytes
benchmarkPass                       = true
```

All fifteen generations returned `pong`.

## 3. Policy totals

| Metric | ALL_RESIDENT | NAIVE_ON_DEMAND | EXECUTION_STATE |
| --- | ---: | ---: | ---: |
| generation total | 1,513.55 ms | 3,469.65 ms | 3,918.20 ms |
| reload bytes | 0 | 65,229,815,808 | 54,358,179,840 |
| release bytes | 0 | 81,537,269,760 | 38,050,725,888 |
| reload time | 0 ms | 9,031.85 ms | 7,734.08 ms |
| release time | 0 ms | 213.24 ms | 98.67 ms |

Idle active bytes by policy:

| Policy | Idle bytes |
| --- | ---: |
| ALL_RESIDENT | 17,180,952,624 every state |
| NAIVE_ON_DEMAND | 873,499,824 every state |
| EXECUTION_STATE | 6,309,317,424 / 6,309,317,424 / 11,745,135,024 / 6,309,317,424 / 17,180,952,624 |

## 4. Conclusion

Gate 5 passes the multi-state feasibility and correctness gate. Execution-state
residency changes whole-group retention between real generations, preserves
output identity, and reduces checkpoint reload traffic versus naive on-demand by
10.87 GiB.

It does not establish a latency advantage: state-driven generation was about
2.40 seconds slower than all-resident and about 0.45 seconds slower than naive
on-demand in this short workload. It also has higher idle memory than naive
on-demand. A practical cost win requires longer state locality or predictive
residency; this result alone does not justify a production residency claim.
