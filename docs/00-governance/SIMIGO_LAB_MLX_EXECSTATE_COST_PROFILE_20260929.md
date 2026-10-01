# SimiGo Lab MLX Execution State Cost Profile — 2026-09-29

## Result

```text
COST1 = PASS / OVERSIZED_MLX_COST_OBSERVATION_WITH_BOUNDARY
```

登记：

```text
MLX_EXECSTATE_PAIRED_COST_OBSERVED
MLX_EXECSTATE_LIFECYCLE_LOCAL_COST_OBSERVED
NOT_A_PERFORMANCE_BENCHMARK
```

这是 oversized MLX harness cost observation，不是 throughput benchmark、生产
performance claim 或跨模型/跨硬件比较。

## Experiment

新增 `MLXExecutionStateCostProfile` 和 CLI：

```bash
simigo2-experimental/.build/debug/simigo2ctl mlx-execstate-cost \
  <LOCAL_HOME>/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-Next-4bit/snapshots/7b9321eabb85ce79625cac3f61ea691e4ea984b5 \
  --tokens 2 --paired-cycles 3 --lifecycle-cycles 2 --segment-size 8
```

两个部分：

### 1. Paired ordinary generation

每个 cycle 交替 order，运行：

```text
direct: seed + root input，无 Execution State binding
state:  bind seed -> capture -> consume representation -> advance/bind -> release stale
```

### 2. Lifecycle operations

每个 cycle：

```text
capture parent checkpoint
fork child
divergent child generation
bind divergent representation
capture divergent state
release divergent state
restore child fork point
replay reference
verify parent / child non-interference
```

## Semantic checks

五项 checks 全部 PASS：

| Check | Result |
| --- | --- |
| `PAIRED_SEMANTICS_STABLE` | PASS |
| `LIFECYCLE_REPLAY_EXACT` | PASS |
| `LIFECYCLE_BRANCH_DIVERGED` | PASS |
| `PARENT_NON_INTERFERENCE` | PASS |
| `OVERSIZED_PROFILE_UNDER_30GIB` | PASS |

## Paired observation

`direct` 与 `state` 均为 `3` samples，greedy token IDs 全部一致：

| Path | Mean | Median | Min | Max |
| --- | ---: | ---: | ---: | ---: |
| Direct generation | 19,203.369ms | 19,459.989ms | 18,105.400ms | 20,044.718ms |
| State generation | 19,243.577ms | 18,652.069ms | 18,046.111ms | 21,032.552ms |
| State − Direct | +40.208ms | -59.290ms | -807.920ms | +987.835ms |

State local bookkeeping（bind + capture + advance/bind + release stale）：

```text
mean   0.022111ms
median 0.021874ms
max    0.027876ms
```

## Lifecycle local observation

| Operation | Mean | Median | Min | Max |
| --- | ---: | ---: | ---: | ---: |
| capture | 0.001063ms | 0.001063ms | 0.001000ms | 0.001125ms |
| fork / derive | 0.016896ms | 0.016896ms | 0.010041ms | 0.023750ms |
| release | 7.651396ms | 7.651396ms | 7.049125ms | 8.253667ms |
| restore | 0.007729ms | 0.007729ms | 0.006250ms | 0.009208ms |

上述 capture/fork/release/restore 的合计 local operation：

```text
mean 7.695876ms
median 7.695876ms
max   8.287791ms
```

注意：release 不是纯字典删除；它会触发 oversized segment-weight release。因此
本 run 中 release 是 lifecycle local cost 的主要部分，不能与 LLAMA token-prefix
dictionary release 直接比较。

## Resource observation

```text
peak footprint      = 7,714 MiB
max swap            = 0 MiB
segment transitions = 146
```

同一 commit 全仓 Swift verification：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifact

```text
simigo2-experimental/results/backend-conformance/mlx-execstate-cost-profile.json
```

## Finding

```text
MLX_EXECSTATE_LOCAL_COST_OBSERVED /
SEMANTICS_PASS /
PAIR_DIFFERENCE_WITHIN_SMALL_SAMPLE_NOISE /
OVERSIZED_RELEASE_IS_MATERIAL_LOCAL_OPERATION
```

本 run 中 no-fork state local bookkeeping 约为 tens-of-microseconds；lifecycle
local operation 约为 7.7ms，其中 oversized segment release 约 7.7ms。paired
generation difference 的 mean 为 +40ms，但样本只有 3、中位数为负且范围约
-808ms 到 +988ms，因此不能解释为稳定 state overhead。

## Boundary

结果限定 current Qwen3-Coder-Next-4bit snapshot、segment size 8、6 segments、
cacheless greedy recompute、short 2-token generation、3 paired cycles、2
lifecycle cycles 和本机 harness。耗时受首触状态、Metal/cache 行为、segment
materialization、系统调度和极小样本影响；不建立 throughput、production
readiness、upstream MLX、跨 backend 或跨硬件 performance claim。

## Non-claims

```text
❌ state overhead 稳定为 +40ms
❌ lifecycle local cost 普适
❌ oversized release 可忽略
❌ production performance readiness 已建立
❌ 与 LLAMA cost 可直接对比
```

## Next

1. 若要建立 performance characterization，需要更多 samples、warmup discipline、
   order counterbalancing 和 token-length sweep。
2. 应把 oversized release 单独建模，而不是把所有 lifecycle local operation 合并
   为一个“微不足道”的数字。
3. 性能结论必须与 RQ3 Metal instability mitigation 边界分开报告。
