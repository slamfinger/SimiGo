# SimiGo Lab MLX Release/Recovery Cost Profile — 2026-09-29

## Result

```text
COST4 = PASS / RETAIN_VS_RELEASE_RESTORE_OBSERVATION_WITH_BOUNDARY
```

登记：

```text
MLX_RETAIN_VS_RELEASE_RECOVERY_ACTION_COST_OBSERVED
PAIRED_STRATEGY_OUTPUTS_EXACT
CACHELESS_RELEASE_DID_NOT_CHANGE_PAIRED_GENERATION_OUTPUT
```

这是 phase-6 paired recovery observation，不是 throughput benchmark、生产
performance claim 或 release-policy recommendation。

## Question

在 oversized MLX prefix-recompute 路径上，比较两个 action strategy：

```text
RETAIN
  capture checkpoint
  -> 不做 explicit release/restore
  -> generation

RELEASE_RESTORE
  capture checkpoint
  -> release current oversized representation
  -> restore checkpoint
  -> generation
```

问题不是“release 是否免费”，而是：

1. release action 本身的 local cost 是多少？
2. release/restore 后 generation 是否仍产生 exact paired output？
3. 当前 cacheless greedy path 中，explicit release 是否会造成可归因的稳定
   generation penalty？

## Experiment

新增 `runReleaseRecoveryProfile` 和 CLI：

```bash
simigo2-experimental/.build/debug/simigo2ctl mlx-release-recovery \
  /Users/mr.simi/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-Next-4bit/snapshots/7b9321eabb85ce79625cac3f61ea691e4ea984b5 \
  --prefix-length 64 --tokens 2 --cycles 4 --segment-size 8
```

每个 cycle 交替 order 运行两个 strategy。每个 strategy 前先 normalize 为
released segment state；`RETAIN` 表示不额外做 release/restore，只保留
checkpoint capture，不代表 warm-KV retention。generation 使用 cacheless greedy
recompute，2 tokens；每个 strategy 记录：

```text
actionMs
action segment-transition delta
generationMs
generation segment-transition delta
advanced binding exactness
generated token IDs / text
```

## Semantic checks

七项 checks 全部 PASS：

| Check | Result |
| --- | --- |
| `BOTH_STRATEGIES_COMPLETE` | PASS |
| `GENERATION_TOKEN_BUDGET_COMPLETE` | PASS |
| `OVERSIZED_PROFILE_UNDER_30GIB` | PASS |
| `PAIRED_STRATEGY_OUTPUTS_EXACT` | PASS |
| `RECOVERY_BINDINGS_EXACT` | PASS |
| `RETAIN_ACTION_DOES_NOT_RELEASE_SEGMENTS` | PASS |
| `RELEASE_ACTION_RELEASES_SEGMENTS` | PASS |

四个 cycle 中，RETAIN action segment transition delta 全部为 `0`；
RELEASE_RESTORE action delta 全部为 `1`。两两配对的 generated token IDs 和
text 完全一致。

## Cost observation

`n=4` per strategy：

| Strategy | Action mean | Action transition | Generation mean | Generation transition | Total mean |
| --- | ---: | ---: | ---: | ---: | ---: |
| RETAIN | 0.008479ms | 0 | 21,294.930ms | 12 | 21,294.938ms |
| RELEASE_RESTORE | 4.519990ms | 1 | 21,084.897ms | 12 | 21,089.417ms |

Aggregate one-token-budget recovery throughput observation：

```text
RETAIN          = 0.3757 tokens/s
RELEASE_RESTORE = 0.3794 tokens/s
```

## Finding

```text
RELEASE_ACTION_LOCAL_COST_APPROXIMATELY_4_5MS /
PAIRED_GENERATION_OUTPUT_EXACT /
NO_STABLE_GENERATION_PENALTY_CLAIMED
```

本 run 中 RELEASE_RESTORE 的额外 action cost 约为 `4.51ms`。其后 generation
mean 反而比 RETAIN 低约 `210ms`，但每个 strategy 只有 4 samples，且当前
cacheless greedy executor 本身会按 segment materialize/release；因此不能解释为
release 提升性能，也不能将 RETAIN−RELEASE generation difference 当作稳定
penalty。可归因的稳定差异只有 action transition 与 action local cost。

## Resource observation

```text
peak footprint      = 7,732 MiB
max swap            = 0 MiB
segment transitions = 115
```

同一 commit 全仓 Swift verification：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifact

```text
simigo2-experimental/results/backend-conformance/mlx-release-recovery-profile.json
```

## Boundary

结果限定 current Qwen3-Coder-Next-4bit snapshot、segment size 8、6 segments、
64-token prefix、cacheless greedy recompute、2-token generation、4 cycles 和本机
harness。`RETAIN` 不代表 warm-KV retention；当前 executor 每个 token 内也会
materialize/release segment。结果不建立 release 策略、production performance、
跨 backend 或跨硬件 claim。

## Non-claims

```text
❌ release 后 generation 更快
❌ release action 无成本
❌ warm-KV retention 已验证
❌ release 策略已优化
❌ production performance readiness 已建立
```

## Next

1. 若要评估真实 retention，需要修改/注入 segment-residency policy，分别测量
   resident、partial、released 后的首 token 与后续 token。
2. 增加 cycles、prefix/generated-token lengths，并报告分布。
3. 将 action cost、generation cost、memory footprint 和 segment transitions
   放入统一 factorial report。
