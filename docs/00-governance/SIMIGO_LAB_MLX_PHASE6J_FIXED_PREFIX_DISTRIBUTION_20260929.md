# SimiGo Lab MLX Fixed-Prefix Distribution Analysis — 2026-09-29

## Result

```text
PHASE6J = PASS_WITH_BOUNDARY / FIXED_PREFIX_DISTRIBUTION_ANALYSIS_COMPLETE / NO_NEW_GPU_RUNS
```

登记：

```text
PREFIX64_TOTAL_HIGHER_IN_ALL_PAIRED_SAMPLES
PREFIX64_FORWARD_SUM_HIGHER_IN_ALL_PAIRED_SAMPLES
MATERIALIZE_DELTAS_ARE_SMALL_AND_MIXED
```

这是对 PHASE6I 已有 combined `n=3` samples的 post-hoc robust analysis；没有新增
GPU run，不建立 throughput benchmark 或 prefix-length recommendation。

## Method

分析 fixed-prefix study中 length `8/64` 的全部 combined samples：

```text
fixed leading token IDs = 1000–1063
prefix lengths          = 8 / 64
segment size / count    = 8 / 6
combined n              = 3 per length
metrics                 = generation total, embed, logits,
                          materialize/forward/release sums,
                          per-layer and release-per-transition
statistics              = mean, median, p05/p25/p75/p95,
                          min/max/range, stdev, IQR, Tukey fences
```

## Checks

八项 checks全部 PASS：

| Check | Result |
| --- | --- |
| `ALL_SOURCE_REPORTS_PASS` | PASS |
| `ALL_LENGTHS_PRESENT` | PASS |
| `COMBINED_N3_PER_LENGTH` | PASS |
| `SAME_LEADING_TOKEN_IDS` | PASS |
| `ALL_PAIRED_TOTAL_DELTAS_POSITIVE` | PASS |
| `ALL_PAIRED_FORWARD_DELTAS_POSITIVE` | PASS |
| `ROBUST_STATS_COMPUTED` | PASS |
| `NO_NEW_GPU_RUNS` | PASS |

## Generation total distribution

| Length | Mean | Median | p05 | p95 | Min | Max | Range | Stdev |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 8  | 10,033.498ms | 10,021.411ms | 9,995.723ms | 10,079.734ms | 9,992.869ms | 10,086.215ms | 93.346ms | 47.832ms |
| 64 | 10,953.392ms | 10,944.812ms | 10,859.565ms | 11,053.225ms | 10,850.094ms | 11,065.271ms | 215.177ms | 107.845ms |

三个配对 prefix64 − prefix8 total deltas：

```text
+828.683ms
+1,072.401ms
+858.597ms
mean +919.894ms
```

## Phase-sum distribution

| Length | Materialize mean | Forward mean | Release mean |
| ---: | ---: | ---: | ---: |
| 8  | 8,625.414ms | 1,283.792ms | 69.012ms |
| 64 | 8,653.658ms | 2,162.599ms | 89.277ms |

三个配对 deltas：

| Phase | Deltas | Mean delta |
| --- | ---: | ---: |
| Materialize | +59.645 / +22.100 / +2.985ms | +28.243ms |
| Forward | +758.827 / +1,017.653 / +859.941ms | +878.807ms |
| Release | +19.092 / +40.134 / +1.569ms | +20.265ms |

IQR analysis没有在这些 `n=3` arms中标出 outlier；这不证明无变异，只说明当前
样本未超过 1.5×IQR fences。

## Artifact

```text
simigo2-experimental/results/backend-conformance/mlx-fixed-prefix-phase-distribution-analysis.json
```

Source：

```text
simigo2-experimental/results/backend-conformance/mlx-fixed-prefix-phase-attribution-summary.json
```

## Finding

```text
PREFIX64_TOTAL_HIGHER_IN_ALL_PAIRED_SAMPLES /
PREFIX64_FORWARD_SUM_HIGHER_IN_ALL_PAIRED_SAMPLES /
MATERIALIZE_DELTAS_ARE_SMALL_AND_MIXED /
N3_IS_TOO_SMALL_FOR_CAUSAL_MODEL
```

## Boundary

combined `n=3`仍是小样本。fixed token IDs消除了 text/tokenizer confound，但不能
解释 Metal kernel、command-buffer scheduling或 allocator差异。不建立定量
prefix-length曲线。

## Non-claims

```text
❌ throughput benchmark
❌ production performance readiness
❌ prefix-length recommendation
❌ warm-KV retention
❌ cross-backend / cross-hardware comparison
❌ causal model
```

## Next

1. 增加 replicates并报告 IQR / p95。
2. 测试更多 prefix lengths。
3. 若继续归因，需要 Metal kernel/command-buffer级别证据。
