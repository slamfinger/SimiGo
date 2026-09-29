# SimiGo Lab MLX Phase-6C Token Budget Replication — 2026-09-29

## Result

```text
PHASE6C = PASS_WITH_BOUNDARY / TOKEN_BUDGET_REPLICATION_COMPLETE / SMALL_SAMPLE
```

登记：

```text
TOKEN_BUDGET_COMBINED_N3_OBSERVED
PAIRED_STRATEGY_OUTPUTS_EXACT_AT_ALL_BUDGETS
T4_RELEASE_RUN_VARIATION_OBSERVED
```

这是 targeted token-budget replication，不是 throughput benchmark、production
performance claim 或 release-policy recommendation。

## Question

COST5 在 prefix 64 / segment 8 上对 `1/2/4` token budgets各只有 2 samples。
本轮将 combined样本提升到每 strategy `n=3`，并检查更大 budget是否仍保持
paired exact semantics，以及小样本 mean是否被长尾运行扭曲。

## Method

核心 prefix-64 / segment-8 数据源：

| Budget | COST5 | Added run | Combined n |
| ---: | ---: | ---: | ---: |
| 1 | 2 cycles per strategy | PHASE6C 1 cycle | 3 |
| 2 | 2 cycles per strategy | PHASE6A 1 cycle | 3 |
| 4 | 2 cycles per strategy | PHASE6C 1 cycle | 3 |

Strategy为 `RETAIN` 与 `RELEASE_RESTORE`。所有 run均使用 cacheless greedy
prefix recompute；action semantics分离为：

```text
RETAIN action transition           = 0
RELEASE_RESTORE action transition  = 1
```

另保留两个 prefix-8 supplementary runs（budgets `1/4`，每 strategy `n=1`），
不进入核心 prefix-64 combined n=3结论。

## Checks

九项 checks全部 PASS：

| Check | Result |
| --- | --- |
| `ALL_SOURCE_REPORTS_PASS` | PASS |
| `ALL_BUDGETS_PRESENT` | PASS |
| `COMBINED_N3_PER_STRATEGY` | PASS |
| `ALL_COMBINED_PAIRED_OUTPUTS_EXACT` | PASS |
| `RETAIN_ACTION_NEVER_RELEASES_SEGMENTS` | PASS |
| `RELEASE_ACTION_ALWAYS_RELEASES_SEGMENTS` | PASS |
| `GENERATION_TRANSITIONS_MATCH_STRUCTURE` | PASS |
| `ALL_RUNS_ZERO_SWAP` | PASS |
| `OVERSIZED_PROFILE_UNDER_30GIB` | PASS |

所有 budget的 generated token IDs/text 两两配对 exact：

```text
1 token: [81917]
2 tokens: [81917, 279]
4 tokens: [81917, 279, 6559, 1847]
```

## Core prefix-64 distribution

combined `n=3` per strategy：

| Budget | Strategy | Generation mean | Median | Min | Max | Range |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | RETAIN | 15,923.831ms | 10,448.105ms | 10,428.564ms | 26,894.823ms | 16,466.259ms |
| 1 | RELEASE_RESTORE | 15,467.756ms | 10,436.751ms | 10,426.835ms | 25,539.684ms | 15,112.849ms |
| 2 | RETAIN | 22,799.211ms | 22,858.117ms | 20,866.217ms | 24,673.300ms | 3,807.083ms |
| 2 | RELEASE_RESTORE | 22,620.266ms | 22,061.736ms | 21,101.924ms | 24,697.140ms | 3,595.217ms |
| 4 | RETAIN | 62,628.598ms | 50,508.985ms | 49,972.016ms | 87,404.793ms | 37,432.777ms |
| 4 | RELEASE_RESTORE | 83,907.846ms | 52,059.338ms | 50,122.700ms | 149,541.501ms | 99,418.801ms |

Median随 budget增长：

```text
RETAIN:           10,448.105 -> 22,858.117 -> 50,508.985ms
RELEASE_RESTORE:  10,436.751 -> 22,061.736 -> 52,059.338ms
```

但 mean在 budget 1和 4被长尾显著拉高。尤其 budget 4的
RELEASE_RESTORE max run为 `149,541.501ms`，range达 `99,418.801ms`。因此不能使用
mean声称 release/restore造成固定倍率惩罚或收益。

## Action observation

combined `n=3`：

| Budget | RETAIN action mean/median | RELEASE_RESTORE action mean/median |
| ---: | ---: | ---: |
| 1 | 0.005764 / 0.003083ms | 6.632417 / 4.558916ms |
| 2 | 0.003028 / 0.002667ms | 5.482931 / 4.865125ms |
| 4 | 0.005542 / 0.003500ms | 9.933681 / 7.260584ms |

RELEASE action cost仍远小于 generation cost，但其自身在小样本中也有波动。

## Prefix-8 supplementary observation

每 strategy `n=1`，不进入 core结论：

| Budget | RETAIN generation | RELEASE_RESTORE generation | Peak footprint |
| ---: | ---: | ---: | ---: |
| 1 | 11,707.532ms | 12,007.561ms | 6,886 MiB |
| 4 | 48,387.495ms | 98,497.580ms | 6,647 MiB |

prefix-8 budget-4 也观测到 release arm长尾，进一步说明不能把单次运行当性能结论。

## Resource observation

所有 core/supplementary runs：

```text
max swap = 0 MiB
peak footprint <= 30 GiB gate
```

同一代码基线最近全仓 Swift verification保持：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifact

```text
simigo2-experimental/results/backend-conformance/mlx-phase6c-token-budget-replication-summary.json
```

Raw artifacts：

```text
mlx-release-recovery-token-replicate-p8-t1-s8.json
mlx-release-recovery-token-replicate-p8-t4-s8.json
mlx-release-recovery-token-replicate-p64-t1-s8.json
mlx-release-recovery-token-replicate-p64-t4-s8.json
```

所有文件位于：

```text
simigo2-experimental/results/backend-conformance/
```

## Finding

```text
TOKEN_BUDGET_MEDIAN_SCALING_OBSERVED /
PAIRED_OUTPUTS_EXACT_AT_N3 /
MEANS_ARE_LONG_TAIL_SENSITIVE /
T4_RELEASE_VARIATION_OBSERVED
```

## Boundary

combined `n=3`仍为小样本。budget 2的 third sample来自 PHASE6A，budget 1/4的
third sample来自 PHASE6C；不同 commit-time run有模型加载和系统状态差异，但均遵循
相同 harness semantics。结果限定 current Qwen3-Coder-Next-4bit snapshot、segment
size 8、prefix 64 core matrix、cacheless greedy recompute和本机 harness。

## Non-claims

```text
❌ 定量 token-cost 曲线已建立
❌ release/restore 导致 4-token变慢的因果结论
❌ warm-KV retention 已验证
❌ release-policy recommendation 已建立
❌ production performance readiness 已建立
❌ cross-backend / cross-hardware comparison 已建立
```

## Next

1. 增加更多 replicates并报告 IQR / p95，而不是依赖 mean。
2. 使用同一 process内重复和跨 process重复区分 load/thermal/order效应。
3. 将 prefix length、token budget、segment size和 release action组成完整 factorial。
