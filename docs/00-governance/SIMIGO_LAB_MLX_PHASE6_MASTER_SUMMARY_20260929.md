# SimiGo Lab MLX Phase-6 Master Summary — 2026-09-29

## Result

```text
PHASE6 = CONSOLIDATED_PASS_WITH_BOUNDARY / OBSERVATION_INDEX_COMPLETE / FULL_MATRIX_OPEN
```

新的 master index把 BASE COST1–COST5与 PHASE6A–PHASE6J纳入同一 evidence index。
它是 observation index，不是 throughput benchmark、production performance claim或
segment-size recommendation。

## Scope

```text
model        = local Qwen3-Coder-Next-4bit / qwen3_next
executor     = cacheless greedy prefix recompute
representation = token-prefix Execution State payload
boundary     = harness-level observation, current model/build/workload only
```

## Indexed entries

| ID | Scope | Status | Artifact |
| --- | --- | --- | --- |
| BASE COST1–COST5 | paired cost, prefix scale, release isolation, retain/release, token-budget scaling | PASS_WITH_BOUNDARY | `mlx-phase6-cost-summary.json` |
| PHASE6A | factorial pilot, prefix/token/segment/action, n=1 per cell | PASS_WITH_BOUNDARY | `mlx-phase6a-factorial-pilot-summary.json` |
| PHASE6B | targeted segment replication, 2-token cells, n=3 per strategy | PASS_WITH_BOUNDARY | `mlx-phase6b-segment-size-replication-summary.json` |
| PHASE6C | token-budget replication, budgets 1/2/4, n=3 per strategy | PASS_WITH_BOUNDARY | `mlx-phase6c-token-budget-replication-summary.json` |
| PHASE6D | distribution expansion partial; p8/s16 GPU timeout remains n=3 | PARTIAL_PASS_WITH_BOUNDARY | `mlx-phase6d-distribution-partial-summary.json` |
| PHASE6E | post-hoc robust distribution analysis | PASS_WITH_BOUNDARY | `mlx-phase6e-distribution-analysis.json` |
| PHASE6F | warmed one-token segment phase attribution, n=1 per size | PASS_WITH_BOUNDARY | `mlx-segment-phase-attribution-summary.json` |
| PHASE6G | segment phase replication, n=3 per size | PASS_WITH_BOUNDARY | `mlx-phase6g-segment-phase-replication-summary.json` |
| PHASE6H | prefix 8/64 phase attribution, n=3 per prefix | PASS_WITH_BOUNDARY | `mlx-phase6h-prefix-phase-attribution-summary.json` |
| PHASE6I | fixed-token prefix attribution, length 8/64, n=3 per length | PASS_WITH_BOUNDARY | `mlx-fixed-prefix-phase-attribution-summary.json` |
| PHASE6J | fixed-prefix distribution analysis, no new GPU runs | PASS_WITH_BOUNDARY | `mlx-fixed-prefix-phase-distribution-analysis.json` |

## Master checks

| Check | Result |
| --- | --- |
| `ALL_EXPECTED_INDEX_ENTRIES_PRESENT` | PASS |
| `ALL_INDEXED_SUMMARIES_PASS` | PASS |
| `PHASE6D_PARTIAL_STATUS_EXPLICIT` | PASS |
| `GPU_TIMEOUT_CELL_REMAINS_N3` | PASS |
| `GPU_TIMEOUT_ROOT_CAUSE_NOT_CLAIMED` | PASS |
| `FULL_FACTORIZATION_REMAINS_OPEN` | PASS |

## Consolidated findings

1. Execution State local bookkeeping远小于 generation cost。
2. Controlled fixed-token probes中，prefix 64的 forward sum高于 prefix 8。
3. Segment 16 的 transition更少，但 PHASE6F/G显示 forward sum更高；transition
   count alone不足以解释 cost。
4. PHASE6D completed n=5 cells呈现 long tail；`p8/t2/segment16`因 repeated Metal
   GPU timeout保持 n=3。
5. 当前 evidence不建立最优 segment size、prefix length或 release policy。

## Master artifact

```text
simigo2-experimental/results/backend-conformance/mlx-phase6-master-summary.json
```

## Open items

```text
FULL_N5_MATRIX_INCLUDING_P8_T2_S16_AFTER_SAFE_RETRY
STATISTICAL_FACTORIZATION_WITH_MORE_REPLICATES
KERNEL_AND_COMMAND_BUFFER_LEVEL_ATTRIBUTION
WARM_KV_OR_SEGMENT_RESIDENCY_POLICY
CROSS_BACKEND_COST_NORMALIZATION
```

## Non-claims

```text
❌ throughput benchmark
❌ production performance readiness
❌ warm-KV retention
❌ release-policy recommendation
❌ cross-backend / cross-hardware comparison
❌ GPU timeout root cause
❌ prefix-length 或 token-budget 定量曲线
```
