# SimiGo Lab MLX Execution State Scale Profile — 2026-09-29

## Result

```text
COST2 = PASS / OVERSIZED_MLX_TOKEN_LENGTH_OBSERVATION_WITH_BOUNDARY
```

登记：

```text
MLX_EXECSTATE_TOKEN_LENGTH_SCALE_OBSERVED
MLX_EXECSTATE_STATE_LOCAL_COST_SEPARATED
SMALL_SAMPLE_NOT_A_PERFORMANCE_BENCHMARK
```

这是 phase-6 token-length scale observation，不是 throughput benchmark、生产
performance claim 或跨模型/跨硬件比较。

## Experiment

新增 `runScaleSweep` 和 CLI：

```bash
simigo2-experimental/.build/debug/simigo2ctl mlx-execstate-scale \
  /Users/mr.simi/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-Next-4bit/snapshots/7b9321eabb85ce79625cac3f61ea691e4ea984b5 \
  --lengths 8,64,256 --pairs-per-length 2 --tokens 1 --segment-size 8
```

先执行一次未计时的 warmup，然后对每个 prefix length 运行 2 组交替
direct-vs-state observation：

```text
direct: seed + filler prefix + root input，无 Execution State binding
state:  bind prefix -> capture -> consume representation -> advance/bind -> release stale
```

`stateLocalMs` 只包含 capture + advance/bind + release stale，不包含 generation。

## Semantic checks

三项 checks 全部 PASS：

| Check | Result |
| --- | --- |
| `ALL_SCALE_SEMANTICS_STABLE` | PASS |
| `ALL_LENGTHS_OBSERVED` | PASS |
| `OVERSIZED_PROFILE_UNDER_30GIB` | PASS |

## Token-length observation

每个 bucket `n=2`：

| Prefix tokens | Direct mean | State mean | State−Direct mean | State local mean |
| ---: | ---: | ---: | ---: | ---: |
| 8  | 9,947.386ms  | 9,931.575ms  | -15.811ms | 0.010584ms |
| 64 | 11,943.900ms | 11,971.644ms | +27.744ms | 0.011729ms |
| 256| 17,177.501ms | 17,565.942ms | +388.442ms | 0.014855ms |

Aggregate one-token throughput observation：

| Prefix tokens | Direct | State |
| ---: | ---: | ---: |
| 8   | 0.2011 tokens/s | 0.2014 tokens/s |
| 64  | 0.1674 tokens/s | 0.1671 tokens/s |
| 256 | 0.1164 tokens/s | 0.1139 tokens/s |

观测到 generation latency 随 prefix length 增长；但这只是当前 cacheless greedy
harness 的小样本趋势，不建立曲线、模型或生产吞吐结论。

paired state−direct difference 在三个 bucket 分别为 `-15.811ms`、`+27.744ms`
和 `+388.442ms`；每个 bucket 只有 2 samples，因此不能归因为稳定 Execution
State overhead。state local bookkeeping 仍保持在约 `0.0106–0.0149ms`。

## Resource observation

```text
peak footprint      = 7,954 MiB
max swap            = 0 MiB
segment transitions = 85
```

每个 bucket 的 post-operation footprint snapshot 分别为 `7,954 / 7,266 /
5,880 MiB`；该差异受 segment release/cache 清理影响，不代表模型随 prefix
length 缩小。

同一 commit 全仓 Swift verification：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifact

```text
simigo2-experimental/results/backend-conformance/mlx-execstate-scale-profile.json
```

## Finding

```text
TOKEN_LENGTH_LATENCY_TREND_OBSERVED /
STATE_LOCAL_COST_REMAINS_MICROSECOND_SCALE /
PAIRED_DELTA_TOO_SMALL_AND_NOISY_FOR_OVERHEAD_CLAIM
```

## Boundary

结果限定 current Qwen3-Coder-Next-4bit snapshot、segment size 8、6 segments、
cacheless greedy recompute、one-token generation、prefix lengths 8/64/256、每
bucket 2 pairs 和本机 harness。首触效应已用 warmup 降低，但没有建立足够样本、
置信区间或多硬件/多模型泛化。

## Non-claims

```text
❌ latency 随长度增长的定量曲线已建立
❌ state overhead 为 +388ms 或任何固定值
❌ production throughput 已建立
❌ oversized release cost 已被 scale sweep 分离
❌ 与 LLAMA 成本可直接对比
```

## Next

1. 增加每 bucket samples、warmup 和 order counterbalancing。
2. 将 prefix length、generated tokens、segment size 和 release action 分离成
   factorial sweep。
3. 报告置信区间/分布，而不是只用 mean。
