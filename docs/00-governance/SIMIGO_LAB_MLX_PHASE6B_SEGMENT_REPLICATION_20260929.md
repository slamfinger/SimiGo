# SimiGo Lab MLX Phase-6B Segment Replication — 2026-09-29

## Result

```text
PHASE6B = PASS_WITH_BOUNDARY / TARGETED_SEGMENT_REPLICATION_COMPLETE / FULL_FACTORIZATION_OPEN
```

登记：

```text
SEGMENT_SIZE_16_LATENCY_PENALTY_REPLICATED
SEGMENT_TRANSITIONS_SCALE_WITH_SEGMENT_COUNT_AND_TOKENS
PAIRED_ACTION_OUTPUTS_EXACT_AFTER_REPLICATION
```

这是 targeted replication，不是 throughput benchmark、production performance claim 或
segment-size recommendation。

## Question

PHASE6A 的 `n=1` pilot 观测到 segment size 16 虽然transition更少，但generation
latency高于 segment size 8。本轮对最有可能区分两者的两个 2-token cells做重复：

```text
prefix = 8 / 64
tokens = 2
segment sizes = 8 / 16
strategy = RETAIN / RELEASE_RESTORE
PHASE6A = 1 cycle per strategy
PHASE6B = 2 additional cycles per strategy
combined = 3 samples per strategy per cell
```

## Checks

十项 checks 全部 PASS：

| Check | Result |
| --- | --- |
| `ALL_REPLICATE_REPORTS_PASS` | PASS |
| `ALL_REPLICATE_PAIRED_OUTPUTS_EXACT` | PASS |
| `ALL_CELLS_PRESENT` | PASS |
| `COMBINED_SAMPLES_PER_STRATEGY` | PASS |
| `ALL_COMBINED_PAIRED_OUTPUTS_EXACT` | PASS |
| `RETAIN_NEVER_RELEASES_SEGMENTS` | PASS |
| `RELEASE_ALWAYS_RELEASES_SEGMENTS` | PASS |
| `GENERATION_TRANSITIONS_MATCH_STRUCTURE` | PASS |
| `OVERSIZED_PROFILE_UNDER_30GIB` | PASS |
| `ALL_RUNS_ZERO_SWAP` | PASS |

## Segment-size observation

combined `n=3` per strategy：

| Prefix | Segment size / count | RETAIN median | RELEASE_RESTORE median | RETAIN mean | RELEASE_RESTORE mean |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 8  | 8 / 6  | 18,665.924ms  | 18,673.739ms  | 18,689.133ms  | 18,698.781ms  |
| 8  | 16 / 3 | 27,638.236ms  | 31,111.494ms  | 31,884.130ms  | 32,872.436ms  |
| 64 | 8 / 6  | 26,230.057ms  | 29,864.848ms  | 28,353.233ms  | 29,994.914ms  |
| 64 | 16 / 3 | 47,111.706ms  | 45,780.322ms  | 47,973.184ms  | 45,990.251ms  |

segment size 16 的 transition数量更少：

```text
segment size 8  = 6 transitions per 2-token strategy run
segment size 16 = 3 transitions per 2-token strategy run
```

但 combined median/mean显示 segment size 16 在 prefix 8 两个 strategy和 prefix 64
RETAIN 中更慢；prefix 64 RELEASE_RESTORE median略低，但 mean仍高于 segment 8。
因此 PHASE6A 的“更少 transition但单次更大/更贵”的观测在 targeted replication后
仍然成立，不能根据 transition count单独选择 segment size。

## Action / output semantics

combined `n=3` per strategy：

```text
RETAIN action transition           = 0 in all cells
RELEASE_RESTORE action transition  = 1 in all cells
paired generated token IDs/text    = exact in all cells
```

RELEASE_RESTORE action mean：

| Prefix | Segment 8 | Segment 16 |
| ---: | ---: | ---: |
| 8  | 4.048125ms | 5.289764ms |
| 64 | 7.456139ms | 6.552847ms |

## Resource observation

PHASE6B replicate run：

| Prefix | Segment size | Peak footprint | Max swap | Segment transitions |
| ---: | ---: | ---: | ---: | ---: |
| 8  | 8  | 8,066 MiB | 0 MiB | 61 |
| 8  | 16 | 10,683 MiB | 0 MiB | 34 |
| 64 | 8  | 7,255 MiB | 0 MiB | 61 |
| 64 | 16 | 4,853 MiB | 0 MiB | 34 |

这些是 run-level peak observation；不能直接解释为每 token稳态内存。

## Verification

本轮只新增 replicated raw/summary artifacts，不改 Swift runtime。最近全仓 Swift
verification保持：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifacts

```text
mlx-release-recovery-replicate-p8-t2-s8.json
mlx-release-recovery-replicate-p8-t2-s16.json
mlx-release-recovery-replicate-p64-t2-s8.json
mlx-release-recovery-replicate-p64-t2-s16.json
mlx-phase6b-segment-size-replication-summary.json
```

所有文件位于：

```text
simigo2-experimental/results/backend-conformance/
```

## Boundary

combined n=3 仍是小样本。segment size同时改变 transition count、每次
materialize/forward/release的工作量和缓存行为；不能把 latency差异归因到单一
机制。`RETAIN` 不代表 warm-KV retention。结果限定 current model、本机 harness、
2-token workload、prefix 8/64 和 cacheless greedy recompute。

## Non-claims

```text
❌ segment size 8 是最优配置
❌ segment size 16 慢的机制已定位
❌ warm-KV retention 已验证
❌ production performance readiness 已建立
❌ cross-backend / cross-hardware comparison 已建立
```

## Next

1. 将 replication扩展到 token budgets `1/4`。
2. 增加更多 replicates并报告 distribution。
3. 若要优化 segment size，需要 instrument每次 materialize/forward/release，
   而不是只观测 transition count。
