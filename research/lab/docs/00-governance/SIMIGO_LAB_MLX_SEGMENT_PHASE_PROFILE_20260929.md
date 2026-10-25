# SimiGo Lab MLX Segment Phase Attribution — 2026-09-29

## Result

```text
PHASE6F = PASS_WITH_BOUNDARY / SEGMENT_PHASE_ATTRIBUTION_PILOT / N1_PER_SIZE
```

登记：

```text
SEGMENT_PHASE_INSTRUMENTATION_OPERATIONAL
SEGMENT16_FORWARD_COST_REPLICATES_LATENCY_TREND
TRANSITION_COUNT_ALONE_INSUFFICIENT
```

这是 targeted phase-attribution pilot，不是 throughput benchmark、production
performance claim 或 segment-size recommendation。

## Question

PHASE6A/B 显示 segment size 16 的 transition数量更少，但 latency通常更高。
本轮把一次 warmed one-token profile拆分为：

```text
embed
per segment: materialize -> forward -> release
logits / argMax
```

从而检查 cost到底来自 transition次数、materialize、forward还是 release。

## Method

新增 `O6SegmentPhaseProfiler` 和 CLI：

```bash
simigo2-experimental/.build/debug/simigo2ctl mlx-segment-phase \
  <LOCAL_HOME>/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-Next-4bit/snapshots/7b9321eabb85ce79625cac3f61ea691e4ea984b5 \
  --prefix-length 64 --segment-size SIZE --samples 1
```

每个 size先执行一次 unprofiled warmup token，然后测量一次完整 token path。
使用 prefix length `64`，比较 segment size `8 / 16`。没有执行 Execution State
action，没有重试此前 GPU timeout的 `p8/t2/segment16` cell。

代码只新增 phase instrumentation；normal `greedy` path不变。同一提交的全仓
Swift verification为：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Raw checks

| Size | Status | Generated token | Segment transitions | Peak footprint | Max swap |
| ---: | --- | ---: | ---: | ---: | ---: |
| 8  | PASS | 26753 | 12 | 7,793 MiB | 0 MiB |
| 16 | PASS | 26753 | 6 | 8,883 MiB | 0 MiB |

每个 measured segment的 materialize transition delta均为 `1`。

## Phase totals

| Segment size / count | Embed | Materialize sum | Forward sum | Release sum | Logits | Total |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 8 / 6  | 9.706ms | 8,592.810ms | 1,953.801ms | 89.098ms | 27.509ms | 10,673.082ms |
| 16 / 3 | 18.241ms | 8,718.752ms | 4,008.853ms | 104.645ms | 46.024ms | 12,896.634ms |

Segment 16 相对 segment 8：

| Phase | Delta |
| --- | ---: |
| Total | +2,223.551ms |
| Materialize sum | +125.942ms |
| Forward sum | +2,055.053ms |
| Release sum | +15.548ms |
| Logits | +18.515ms |
| Embed | +8.536ms |

## Per-layer / per-transition view

| Metric | Segment 8 | Segment 16 |
| --- | ---: | ---: |
| Materialize per layer | 1,074.101ms | 544.922ms |
| Forward per layer | 244.225ms | 250.553ms |
| Release per layer | 11.137ms | 6.540ms |
| Release per transition | 14.850ms | 34.882ms |

因此 segment 16 的 transition数量减半，但每 segment覆盖 16 层；forward sum更高，
release per transition也更高。latency趋势不能归因于 transition count本身。

## Segment-level observation

Segment 8 的六个 segment分布均匀：

| Segment | Materialize | Forward | Release |
| ---: | ---: | ---: | ---: |
| 0-7   | 1,436.560ms | 343.650ms | 15.444ms |
| 8-15  | 1,422.913ms | 281.606ms | 14.472ms |
| 16-23 | 1,438.944ms | 316.233ms | 14.299ms |
| 24-31 | 1,429.104ms | 346.508ms | 15.607ms |
| 32-39 | 1,433.765ms | 293.229ms | 14.812ms |
| 40-47 | 1,431.524ms | 372.574ms | 14.465ms |

Segment 16 的三个 segment也相对均匀：

| Segment | Materialize | Forward | Release |
| ---: | ---: | ---: | ---: |
| 0-15  | 2,906.020ms | 1,367.795ms | 35.186ms |
| 16-31 | 2,912.188ms | 1,306.908ms | 42.128ms |
| 32-47 | 2,900.544ms | 1,334.150ms | 27.331ms |

## Resource observation

```text
max swap = 0 MiB
peak footprint = 7,793 / 8,883 MiB
```

均低于 30GiB gate；这是 run-level observation，不代表稳态内存曲线。

## Artifacts

```text
mlx-segment-phase-p64-s8.json
mlx-segment-phase-p64-s16.json
mlx-segment-phase-attribution-summary.json
```

所有文件位于：

```text
simigo2-experimental/results/backend-conformance/
```

## Finding

```text
SEGMENT16_FORWARD_SUM_INCREASE_OBSERVED /
MATERIALIZE_TOTAL_APPROXIMATELY_CONSTANT /
RELEASE_PER_TRANSITION_INCREASES /
TRANSITION_COUNT_ALONE_INSUFFICIENT
```

## Boundary

每个 size只有 `n=1` measured token；无重复、counterbalancing或 confidence
interval。不能建立最优 segment size，也不能解释 Metal timeout root cause。
结果限定 current model、prefix 64、one warmed token、本机 harness和 cacheless
greedy recompute。

## Non-claims

```text
❌ segment size 8 是最优配置
❌ segment size 16 是错误配置
❌ forward差异的底层原因已定位
❌ warm-KV retention 已验证
❌ production performance readiness 已建立
❌ cross-backend / cross-hardware comparison 已建立
```

## Next

1. 对 safe cells增加 replicates和 order counterbalancing。
2. 将 per-phase instrumentation接入 release/recovery profile。
3. 若要解释 forward差异，需要 capture Metal kernel/command-buffer级别证据。
4. `p8/t2/segment16` GPU timeout重试需用户明确确认。
