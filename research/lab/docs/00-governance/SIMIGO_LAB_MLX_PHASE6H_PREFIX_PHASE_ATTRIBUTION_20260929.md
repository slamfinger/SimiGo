# SimiGo Lab MLX Phase-6H Prefix Phase Attribution — 2026-09-29

## Result

```text
PHASE6H = PASS_WITH_BOUNDARY / PREFIX_PHASE_ATTRIBUTION_COMPLETE / N3_PER_PREFIX
```

登记：

```text
PREFIX64_TOTAL_SLOWER_IN_ALL_PAIRED_SAMPLES
PREFIX64_FORWARD_SUM_SLOWER_IN_ALL_PAIRED_SAMPLES
PREFIX_LENGTH_EFFECT_IS_OBSERVATIONAL
```

这是 targeted prefix-length phase attribution，不是 throughput benchmark、
production performance claim 或 prefix-length recommendation。

## Question

PHASE6G 已在 prefix 64 / segment 8建立 combined `n=3` phase profile。本轮在
prefix 8 / segment 8增加 3个独立 warmed one-token profiles，比较 prefix length对
materialize / forward / release的影响。

## Method

```bash
simigo2-experimental/.build/debug/simigo2ctl mlx-segment-phase \
  <LOCAL_HOME>/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-Next-4bit/snapshots/7b9321eabb85ce79625cac3f61ea691e4ea984b5 \
  --prefix-length 8 --segment-size 8 --samples 1
```

```text
segment size / count = 8 / 6
prefix token lengths = 8 / 64
sources              = PHASE6H_B1/B2/B3 for prefix8;
                       PHASE6F + PHASE6G_B1/B2 for prefix64
combined n           = 3 per prefix
phases               = embed; per segment materialize/forward/release; logits
```

每个 run都先执行 unprofiled warmup token。prefix 8和 prefix 64使用不同 text和
tokenizer output，因此这不是同一 token sequence的 paired comparison。

## Checks

九项 checks全部 PASS：

| Check | Result |
| --- | --- |
| `ALL_SOURCE_REPORTS_PASS` | PASS |
| `ALL_PREFIXES_PRESENT` | PASS |
| `COMBINED_N3_PER_PREFIX` | PASS |
| `SEGMENT_SIZE_FIXED_AT_8` | PASS |
| `ALL_REPORTS_ZERO_SWAP` | PASS |
| `ALL_REPORTS_UNDER_30GIB` | PASS |
| `PREFIX64_TOTAL_SLOWER_IN_ALL_PAIRED_SAMPLES` | PASS |
| `PREFIX64_FORWARD_SLOWER_IN_ALL_PAIRED_SAMPLES` | PASS |

所有 reports的 generated token ID均已记录；max swap `0 MiB`；peak footprint低于
30GiB gate。

## Phase distribution

combined `n=3` per prefix：

| Prefix | Generation total mean/median | Materialize sum mean | Forward sum mean | Release sum mean |
| ---: | ---: | ---: | ---: | ---: |
| 8  | 9,741.621 / 9,723.216ms | 8,608.747ms | 1,023.550ms | 66.784ms |
| 64 | 10,605.054 / 10,631.051ms | 8,618.143ms | 1,869.628ms | 89.624ms |

三个 sample-index配对的 prefix64 − prefix8 deltas：

| Sample | Total delta | Materialize delta | Forward delta | Release delta | Logits delta |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | +968.394ms | -2.989ms | +958.769ms | +21.833ms | -1.338ms |
| 1 | +714.069ms | -25.989ms | +731.115ms | +21.905ms | -6.781ms |
| 2 | +907.835ms | +57.166ms | +848.349ms | +24.782ms | -24.028ms |
| Mean | +863.433ms | +9.396ms | +846.078ms | +22.840ms | -10.716ms |

prefix 64 的 total delta在三个配对中均为正；forward sum delta也全为正。
materialize sum delta方向混合且幅度小。release sum delta全为正。

## Per-layer view

| Phase | Prefix 8 per layer | Prefix 64 per layer |
| --- | ---: | ---: |
| Materialize | 179.349ms | 179.545ms |
| Forward | 21.324ms | 38.951ms |
| Release | 1.391ms | 1.867ms |

forward per-layer差异是主要增量；materialize per-layer几乎一致。由于 prefix
内容和 tokenization不同，不能把 delta唯一归因于“长度”本身。

## Resource observation

```text
max swap = 0 MiB
peak footprint reports <= 30 GiB gate
```

同一代码基线最近全仓 Swift verification保持：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifacts

```text
mlx-segment-phase-replicate-p8-s8-b1.json
mlx-segment-phase-replicate-p8-s8-b2.json
mlx-segment-phase-replicate-p8-s8-b3.json
mlx-phase6h-prefix-phase-attribution-summary.json
```

所有文件位于：

```text
simigo2-experimental/results/backend-conformance/
```

## Finding

```text
PREFIX64_FORWARD_SUM_HIGHER_IN_ALL_PAIRED_SAMPLES /
PREFIX64_TOTAL_HIGHER_IN_ALL_PAIRED_SAMPLES /
MATERIALIZE_PER_LAYER_APPROXIMATELY_SIMILAR /
SMALL_N_NO_CAUSAL_LENGTH_MODEL
```

## Boundary

combined `n=3` per prefix仍是小样本。prefix 8和 prefix 64的 token sequence、
text content和 tokenizer行为不同；不能将差异唯一归因于长度。结果限定 current
model、segment size 8、cacheless greedy recompute和本机 harness。

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

1. 使用固定 token IDs或受控文本设计消除 tokenizer/content confound。
2. 增加 replicates并报告 IQR / p95。
3. 若继续性能研究，可结合 segment size和 prefix length做 full factorial。
