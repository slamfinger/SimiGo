# SimiGo Lab MLX Phase-6G Segment Phase Replication — 2026-09-29

## Result

```text
PHASE6G = PASS_WITH_BOUNDARY / SEGMENT_PHASE_REPLICATION_COMPLETE / N3_PER_SIZE
```

登记：

```text
SEGMENT16_TOTAL_SLOWER_IN_ALL_PAIRED_SAMPLES
SEGMENT16_FORWARD_SUM_SLOWER_IN_ALL_PAIRED_SAMPLES
TRANSITION_COUNT_ALONE_INSUFFICIENT
```

这是 targeted phase-attribution replication，不是 throughput benchmark、production
performance claim 或 segment-size recommendation。

## Question

PHASE6F 每个 size只有 `n=1`，观测到 segment 16 的 total和 forward sum高于
segment 8。本轮在 safe prefix-64 path上增加两个 replicates，使 combined每 size
达到 `n=3`，检查该趋势是否稳定。

## Method

复用 `mlx-segment-phase`：

```bash
simigo2-experimental/.build/debug/simigo2ctl mlx-segment-phase \
  <LOCAL_HOME>/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-Next-4bit/snapshots/7b9321eabb85ce79625cac3f61ea691e4ea984b5 \
  --prefix-length 64 --segment-size SIZE --samples 1
```

```text
prefix        = 64
segment sizes = 8 / 16
sources       = PHASE6F + PHASE6G_B1 + PHASE6G_B2
combined n    = 3 per size
phases        = embed; per segment materialize/forward/release; logits/argMax
```

没有 Execution State action，没有重试 GPU timeout cell。

## Checks

八项 checks全部 PASS：

| Check | Result |
| --- | --- |
| `ALL_SOURCE_REPORTS_PASS` | PASS |
| `ALL_SIZES_PRESENT` | PASS |
| `COMBINED_N3_PER_SIZE` | PASS |
| `SAME_GENERATED_TOKEN` | PASS |
| `ALL_REPORTS_ZERO_SWAP` | PASS |
| `ALL_REPORTS_UNDER_30GIB` | PASS |
| `SEGMENT16_TOTAL_SLOWER_IN_ALL_PAIRED_SAMPLES` | PASS |
| `SEGMENT16_FORWARD_SLOWER_IN_ALL_PAIRED_SAMPLES` | PASS |

三个 paired samples中 generated token均为 `26753`；max swap `0 MiB`；peak
footprint低于 30GiB。

## Combined generation distribution

`n=3` per size：

| Segment size / count | Total mean | Total median | Total min | Total max | Total stdev |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 8 / 6  | 10,605.054ms | 10,631.051ms | 10,511.029ms | 10,673.082ms | 84.097ms |
| 16 / 3 | 12,870.913ms | 12,896.634ms | 12,776.190ms | 12,939.915ms | 84.839ms |

三个 paired `segment16 - segment8` total deltas全部为正：

```text
+2,223.551ms
+2,428.887ms
+2,145.139ms
```

## Phase-sum attribution

`n=3` means：

| Phase | Segment 8 | Segment 16 | Segment 16 − Segment 8 |
| --- | ---: | ---: | ---: |
| Materialize sum | 8,618.143ms | 8,733.775ms | +115.632ms |
| Forward sum | 1,869.628ms | 3,977.427ms | +2,107.799ms |
| Release sum | 89.624ms | 102.594ms | +12.969ms |

per-layer均值：

| Phase | Segment 8 per layer | Segment 16 per layer |
| --- | ---: | ---: |
| Materialize | 179.513ms | 181.511ms |
| Forward | 38.951ms | 82.363ms |
| Release | 1.867ms | 2.137ms |

release per transition均值：

```text
segment 8  = 14.937ms
segment 16 = 34.198ms
```

这 replicated PHASE6F：materialize total接近，但 segment 16 的 forward sum显著
更高，release per transition也更高。latency差异不能归因于 transition count减少。

## Resource observation

```text
max swap = 0 MiB
peak footprint reports = 7,793 / 8,883 MiB baseline and <= 30 GiB in replicates
```

run-level footprint受 segment size和 release timing影响，不代表稳态内存曲线。

## Verification

本轮只新增 replicated raw/summary artifacts，不改 Swift runtime。当前代码基线最近
全仓 Swift verification保持：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifacts

```text
mlx-segment-phase-replicate-p64-s8-b1.json
mlx-segment-phase-replicate-p64-s8-b2.json
mlx-segment-phase-replicate-p64-s16-b1.json
mlx-segment-phase-replicate-p64-s16-b2.json
mlx-segment-phase-attribution-summary.json
mlx-phase6g-segment-phase-replication-summary.json
```

所有文件位于：

```text
simigo2-experimental/results/backend-conformance/
```

## Finding

```text
SEGMENT16_TOTAL_SLOWER_IN_ALL_PAIRED_SAMPLES /
SEGMENT16_FORWARD_SUM_SLOWER_IN_ALL_PAIRED_SAMPLES /
MATERIALIZE_TOTAL_APPROXIMATELY_SIMILAR /
TRANSITION_COUNT_ALONE_INSUFFICIENT
```

## Boundary

combined `n=3`仍是小样本；没有 confidence interval、counterbalancing 或跨硬件
泛化。segment size同时改变每 segment层数、materialize workload、forward graph和
release count，不能将差异归因到单一机制。`p8/t2/segment16` GPU timeout cell仍未
重试。

## Non-claims

```text
❌ segment size 8 是最优配置
❌ segment size 16 慢的底层机制已定位
❌ warm-KV retention 已验证
❌ production performance readiness 已建立
❌ cross-backend / cross-hardware comparison 已建立
❌ GPU timeout root cause 已定位
```

## Next

1. 增加更多 replicates和 counterbalancing。
2. 将 per-phase instrumentation接入 release/recovery profile。
3. 若要解释 forward差异，需要 Metal kernel/command-buffer级别证据。
4. GPU timeout cell重试需用户明确确认。
