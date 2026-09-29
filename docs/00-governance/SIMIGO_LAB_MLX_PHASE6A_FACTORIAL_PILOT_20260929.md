# SimiGo Lab MLX Phase-6A Factorial Pilot — 2026-09-29

## Result

```text
PHASE6A = PASS_WITH_BOUNDARY / FULL_FACTORIAL_PILOT_COMPLETE / STATISTICAL_FACTORIZATION_OPEN
```

登记：

```text
PHASE6A_PREFIX_TOKEN_SEGMENT_ACTION_PILOT_PASS
LARGER_SEGMENTS_HAVE_FEWER_BUT_COSTLIER_TRANSITIONS
PAIRED_ACTION_OUTPUTS_EXACT_IN_ALL_CELLS
```

这是 phase-6 的 one-cycle factorial pilot，不是完整 statistical factorization、
throughput benchmark 或 production performance claim。

## Design

新增 8-cell pilot，复用 `mlx-release-recovery`：

```text
prefix token lengths = 8 / 64
generated tokens     = 1 / 2
segment sizes        = 8 / 16
strategy             = RETAIN, RELEASE_RESTORE
cycles per strategy  = 1
model                = local Qwen3-Coder-Next-4bit
```

每个 cell 都运行两个 strategy 并比较 generated token IDs/text。`RETAIN` 表示
capture 后没有额外 explicit release/restore；`RELEASE_RESTORE` 表示 release
current representation 后 restore checkpoint。

## Checks

八项 summary checks 全部 PASS：

| Check | Result |
| --- | --- |
| `ALL_CELLS_PRESENT` | PASS |
| `ALL_CELLS_PASS` | PASS |
| `ALL_PAIRED_OUTPUTS_EXACT` | PASS |
| `RETAIN_NEVER_RELEASES_SEGMENTS` | PASS |
| `RELEASE_ALWAYS_RELEASES_SEGMENTS` | PASS |
| `GENERATION_TRANSITIONS_MATCH_SEGMENTS_TIMES_TOKENS` | PASS |
| `OVERSIZED_PROFILE_UNDER_30GIB` | PASS |
| `ALL_RUNS_ZERO_SWAP` | PASS |

所有 cell 中：

```text
RETAIN action transition         = 0
RELEASE_RESTORE action transition = 1
paired outputs                   = exact
max swap                         = 0 MiB
```

## Cell observations

`n=1` per strategy per cell；strategy generation mean 是 RETAIN 和
RELEASE_RESTORE 的平均：

| Prefix | Tokens | Segment size / count | Strategy generation mean | Strategy-averaged mean | Peak footprint |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 8  | 1 | 8 / 6  | 9,317.761 / 9,347.462ms   | 9,332.611ms  | 8,005 MiB |
| 8  | 1 | 16 / 3 | 11,763.418 / 11,706.750ms | 11,735.084ms | 12,046 MiB |
| 8  | 2 | 8 / 6  | 18,520.064 / 18,519.438ms | 18,519.751ms | 7,959 MiB |
| 8  | 2 | 16 / 3 | 26,270.584 / 28,594.859ms | 27,432.722ms | 11,818 MiB |
| 64 | 1 | 8 / 6  | 11,973.962 / 12,204.661ms | 12,089.311ms | 7,527 MiB |
| 64 | 1 | 16 / 3 | 18,638.322 / 18,043.686ms | 18,341.004ms | 7,638 MiB |
| 64 | 2 | 8 / 6  | 24,673.300 / 24,697.140ms | 24,685.220ms | 7,256 MiB |
| 64 | 2 | 16 / 3 | 36,916.892 / 37,051.433ms | 36,984.162ms | 6,853 MiB |

## Pilot observations

### 1. Segment size 16 has fewer transitions but higher observed latency

Generation transition delta符合结构：

```text
segment size 8  / 6 segments -> 6 * tokens
segment size 16 / 3 segments -> 3 * tokens
```

但在所有四个可比 pair中，segment size 16 的 strategy-averaged generation mean
都高于 segment size 8：

```text
p8/t1:  +2,402.473ms
p8/t2:  +8,912.971ms
p64/t1: +6,251.693ms
p64/t2: +12,298.942ms
```

这说明“transition 更少”不等于“总成本更低”；更大 segment 的单次
materialize/forward/release成本更高。样本为 `n=1`，不建立定量曲线。

### 2. Prefix length 64 观测上慢于 8

同 token/segment 下，prefix 64 相对 prefix 8 的 strategy-averaged delta：

```text
segment 8,  1 token: +2,756.700ms
segment 8,  2 tokens: +6,165.469ms
segment 16, 1 token: +6,605.920ms
segment 16, 2 tokens: +9,551.440ms
```

### 3. Release action is small but observable

RELEASE_RESTORE action mean range：

```text
3.967–7.108ms
```

RETAIN action mean range：

```text
0.001–0.011ms
```

所有 cell 的 paired outputs exact，因此 action差异没有改变 greedy continuation
输出。

## Resource observation

```text
peak footprint range = 6,853–12,046 MiB
max swap             = 0 MiB
```

segment size 16 的两个 p8 cells footprint较高；所有 cell仍低于 30GiB gate。

## Verification

本轮只新增 pilot artifact和汇总，不改 Swift runtime。当前提交前全仓 Swift
verification保持：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifacts

```text
mlx-release-recovery-factorial-p8-t1-s8.json
mlx-release-recovery-factorial-p8-t1-s16.json
mlx-release-recovery-factorial-p8-t2-s8.json
mlx-release-recovery-factorial-p8-t2-s16.json
mlx-release-recovery-factorial-p64-t1-s8.json
mlx-release-recovery-factorial-p64-t1-s16.json
mlx-release-recovery-factorial-p64-t2-s8.json
mlx-release-recovery-factorial-p64-t2-s16.json
mlx-phase6a-factorial-pilot-summary.json
```

所有文件位于：

```text
simigo2-experimental/results/backend-conformance/
```

## Boundary

每个 cell 每 strategy 只有 `n=1`，没有重复、confidence interval或多硬件/多模型
泛化。segment size 16 的 latency差异是 observational，不建立最优 segment size
结论。`RETAIN` 仍不代表 warm-KV retention；当前 executor是 cacheless greedy
prefix recompute。

## Non-claims

```text
❌ segment size 16 是最优配置
❌ release/restore 可忽略
❌ warm-KV retention 已验证
❌ statistical factorial closure 已完成
❌ production performance readiness 已建立
❌ cross-backend / cross-hardware comparison 已建立
```

## Next

1. 对有意义 cells增加重复和 order counterbalancing。
2. 报告 median / IQR / p95，不只使用 single-cell mean。
3. 若要评估真实 retention，需要单独实现 segment-residency policy。
