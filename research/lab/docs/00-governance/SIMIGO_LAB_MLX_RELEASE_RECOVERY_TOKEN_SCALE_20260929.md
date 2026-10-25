# SimiGo Lab MLX Release/Recovery Token Scale — 2026-09-29

## Result

```text
COST5 = PASS / RETAIN_VS_RELEASE_RESTORE_TOKEN_SCALE_WITH_BOUNDARY
```

登记：

```text
MLX_RELEASE_RECOVERY_TOKEN_SCALE_OBSERVED
GENERATION_TRANSITIONS_SCALE_WITH_TOKEN_COUNT
PAIRED_STRATEGY_OUTPUTS_REMAIN_EXACT
```

这是 phase-6 token-budget scale observation，不是 throughput benchmark、生产
performance claim 或 release-policy recommendation。

## Experiment

复用 `runReleaseRecoveryProfile`，对同一 oversized MLX prefix-recompute 路径运行
三个 token budget：

```bash
simigo2-experimental/.build/debug/simigo2ctl mlx-release-recovery \
  <LOCAL_HOME>/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-Next-4bit/snapshots/7b9321eabb85ce79625cac3f61ea691e4ea984b5 \
  --prefix-length 64 --tokens TOKENS --cycles 2 --segment-size 8
```

```text
prefix length = 64
maxTokens     = 1 / 2 / 4
cycles        = 2 per strategy per budget
strategy      = RETAIN, RELEASE_RESTORE
segment size  = 8
```

每个 run 交替 order，每个 strategy 前先 normalize 为 released segment state。
`RETAIN` 不是 warm-KV retention；仅表示 capture 后没有额外 explicit
release/restore。

## Raw run checks

三个 raw runs 均为 `PASS / overallPass=true`，7 项 checks 全部 PASS。所有
RETAIN-vs-RELEASE_RESTORE paired generated token IDs/text exact。

## Token-budget observation

`n=2` per strategy per budget：

| maxTokens | RETAIN generation mean | RELEASE_RESTORE generation mean | Strategy-averaged mean |
| ---: | ---: | ---: | ---: |
| 1 | 10,438.335ms | 10,431.793ms | 10,435.064ms |
| 2 | 21,862.167ms | 21,581.830ms | 21,721.998ms |
| 4 | 50,240.501ms | 51,091.019ms | 50,665.760ms |

相对前一个 budget 的 strategy-averaged marginal generation mean：

```text
1 -> 2 tokens: +11,286.935ms
2 -> 4 tokens: +28,943.762ms (+14,471.881ms per additional token)
```

action mean：

| maxTokens | RETAIN action | RELEASE_RESTORE action |
| ---: | ---: | ---: |
| 1 | 0.002062ms | 4.447208ms |
| 2 | 0.002188ms | 4.670188ms |
| 4 | 0.002688ms | 7.196896ms |

generation segment-transition delta 分别为 `6 / 12 / 24`，与 6 个 oversized
segments 和 generated token count 成比例。

Aggregate one-run recovery throughput observation：

| maxTokens | RETAIN | RELEASE_RESTORE |
| ---: | ---: | ---: |
| 1 | 0.1916 tokens/s | 0.1917 tokens/s |
| 2 | 0.1830 tokens/s | 0.1853 tokens/s |
| 4 | 0.1592 tokens/s | 0.1566 tokens/s |

## Combined checks

五项 summary checks 全部 PASS：

| Check | Result |
| --- | --- |
| `ALL_RUNS_PASS` | PASS |
| `ALL_PAIRED_OUTPUTS_EXACT` | PASS |
| `ALL_TOKEN_BUDGETS_OBSERVED` | PASS |
| `TRANSITIONS_SCALE_WITH_GENERATED_TOKENS` | PASS |
| `OVERSIZED_PROFILE_UNDER_30GIB` | PASS |

## Resource observation

```text
peak footprint by run = 7,765 / 7,848 / 7,541 MiB
max swap              = 0 MiB
segment transitions   = 37 / 61 / 109
```

同一 commit 全仓 Swift verification：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifacts

```text
simigo2-experimental/results/backend-conformance/mlx-release-recovery-tokens1.json
simigo2-experimental/results/backend-conformance/mlx-release-recovery-tokens2.json
simigo2-experimental/results/backend-conformance/mlx-release-recovery-tokens4.json
simigo2-experimental/results/backend-conformance/mlx-release-recovery-token-scale-summary.json
```

## Finding

```text
GENERATION_COST_INCREASES_WITH_TOKEN_BUDGET /
SEGMENT_TRANSITIONS_SCALE_WITH_TOKEN_COUNT /
RELEASE_RESTORE_ACTION_REMAINS_SMALL_VS_GENERATION /
PAIRED_OUTPUTS_EXACT_AT_ALL_BUDGETS
```

在当前 cacheless greedy implementation 下，generation cost 随 token budget 明显
增长；segment transitions 也按 token budget 缩放。RELEASE_RESTORE 的 local action
cost 只有几毫秒，远小于 generation 成本。paired outputs 在 1/2/4 token budget
均 exact。

## Boundary

结果限定 current Qwen3-Coder-Next-4bit snapshot、segment size 8、6 segments、
64-token prefix、cacheless greedy recompute、1/2/4-token budgets、每 strategy 每
budget 2 cycles 和本机 harness。`RETAIN` 不代表 warm-KV retention。小样本
mean 不能建立 throughput 曲线；`4-token` 的 RELEASE action 增大到 `7.2ms` 也不足
以建立统计结论。

## Non-claims

```text
❌ generation scaling 曲线已建立
❌ marginal token cost 已精确建模
❌ release action 与 generation penalty 的因果关系已建立
❌ warm-KV retention 已验证
❌ production performance readiness 已建立
```

## Next

1. 将 prefix length、generated tokens、segment size 和 normalize/release action
   组成统一 factorial design。
2. 每 cell 增加样本并报告 median / IQR / p95，不只使用 mean。
3. 将 cost profiles 与 RQ3 Metal instability mitigation 边界分开报告。
