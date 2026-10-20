# SimiGo Lab MLX Phase-6I Fixed-Prefix Phase Attribution — 2026-09-29

> **ARCHIVED** 2026-10-20 · line: Small-scale runtime / GUI · original: docs/00-governance/SIMIGO_LAB_MLX_PHASE6I_FIXED_PREFIX_PHASE_ATTRIBUTION_20260929.md
> Evidence status: unchanged (content frozen; moved only)


## Result

```text
PHASE6I = PASS_WITH_BOUNDARY / FIXED_TOKEN_PREFIX_ATTRIBUTION_COMPLETE / N3_PER_LENGTH
```

登记：

```text
SAME_LEADING_TOKEN_IDS_CONTROLLED
PREFIX64_TOTAL_SLOWER_IN_ALL_PAIRED_SAMPLES
PREFIX64_FORWARD_SUM_SLOWER_IN_ALL_PAIRED_SAMPLES
```

这是 controlled fixed-token prefix attribution，不是 throughput benchmark、
production performance claim 或 prefix-length recommendation。

## Question

PHASE6H 观测到 prefix 64 的 forward sum高于 prefix 8，但两者 text/tokenizer不同。
本轮使用同一 leading token ID sequence，仅改变 context长度，消除 content/tokenizer
confound。

## Method

新增 `O6FixedPrefixPhaseStudy` 和 CLI：

```bash
simigo2-experimental/.build/debug/simigo2ctl mlx-fixed-prefix-phase \
  <LOCAL_HOME>/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-Next-4bit/snapshots/7b9321eabb85ce79625cac3f61ea691e4ea984b5 \
  --prefix-token-ids 1000,1001,...,1063 \
  --prefix-lengths 8,64 --segment-size 8 --samples-per-size 3
```

两个长度都从同一 64-ID sequence取 leading IDs：

```text
length 8  = token IDs 1000–1007
length 64 = token IDs 1000–1063
```

每个 length先执行一次 unprofiled warmup token，然后测量 3个完整 token path。
phase拆分为 embed、每 segment materialize/forward/release、logits/argMax。

## Checks

八项 checks全部 PASS：

| Check | Result |
| --- | --- |
| `ALL_SOURCE_REPORTS_PASS` | PASS |
| `ALL_LENGTHS_PRESENT` | PASS |
| `COMBINED_N3_PER_LENGTH` | PASS |
| `SAME_LEADING_TOKEN_IDS` | PASS |
| `PREFIX64_TOTAL_SLOWER_IN_ALL_PAIRED_SAMPLES` | PASS |
| `PREFIX64_FORWARD_SUM_SLOWER_IN_ALL_PAIRED_SAMPLES` | PASS |
| `ALL_REPORTS_ZERO_SWAP` | PASS |
| `ALL_REPORTS_UNDER_30GIB` | PASS |

## Cost observation

combined `n=3` per length：

| Length | Generation total mean/median | Materialize sum mean | Forward sum mean | Release sum mean |
| ---: | ---: | ---: | ---: | ---: |
| 8  | 10,033.498 / 10,086.215ms | 8,625.414ms | 1,283.792ms | 69.012ms |
| 64 | 10,953.392 / 10,944.812ms | 8,653.658ms | 2,162.599ms | 89.277ms |

三个 sample-index配对的 prefix64 − prefix8 deltas：

| Sample | Total delta | Materialize delta | Forward delta | Release delta |
| ---: | ---: | ---: | ---: | ---: |
| 0 | +828.683ms | +59.645ms | +758.827ms | +19.092ms |
| 1 | +1,072.401ms | +22.100ms | +1,017.653ms | +40.134ms |
| 2 | +858.597ms | +2.985ms | +859.941ms | +1.569ms |
| Mean | +919.894ms | +28.243ms | +878.807ms | +20.265ms |

forward sum delta是主要项；materialize sum delta很小。这 replicated PHASE6H 的
方向，并在消除 text/tokenizer confound后仍然成立。

per-layer mean：

| Phase | Length 8 | Length 64 |
| --- | ---: | ---: |
| Materialize | 179.696ms | 180.285ms |
| Forward | 26.746ms | 45.054ms |
| Release | 1.438ms | 1.860ms |

## Generated tokens

因为 context长度不同，两个长度产生的 greedy tokens不同：

```text
length 8:  [279, 4910, 11]
length 64: [268, 198, 262]
```

本实验比较 cost attribution，不要求输出 semantic equivalence。

## Resource observation

```text
peak footprint = 7,980 / 7,955 MiB
max swap       = 0 MiB
```

同一代码基线最近全仓 Swift verification保持：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifacts

```text
mlx-fixed-prefix-phase-p8-s8.json
mlx-fixed-prefix-phase-p64-s8.json
mlx-fixed-prefix-phase-study.json
mlx-fixed-prefix-phase-attribution-summary.json
```

所有文件位于：

```text
simigo2-experimental/results/backend-conformance/
```

## Finding

```text
PREFIX64_FORWARD_SUM_HIGHER_IN_ALL_PAIRED_SAMPLES /
PREFIX64_TOTAL_HIGHER_IN_ALL_PAIRED_SAMPLES /
MATERIALIZE_SUM_APPROXIMATELY_SIMILAR /
CONTENT_TOKENIZER_CONFOUND_CONTROLLED
```

## Boundary

combined `n=3` per length仍是小样本；没有 confidence interval、counterbalancing
或跨硬件泛化。固定 token IDs消除了 text/tokenizer confound，但不能解释 Metal
kernel或 command-buffer调度差异。

## Non-claims

```text
❌ prefix length是唯一 causal factor
❌ 定量 prefix-length 曲线已建立
❌ segment size 8 是最优配置
❌ warm-KV retention 已验证
❌ production performance readiness 已建立
❌ cross-backend / cross-hardware comparison 已建立
```

## Next

1. 增加 replicates并报告 IQR / p95。
2. 测试更多 prefix lengths和 generated-token budgets。
3. 若继续归因，需要 Metal kernel/command-buffer级别证据。
