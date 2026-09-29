# SimiGo Lab MLX Phase-6E Distribution Analysis — 2026-09-29

## Result

```text
PHASE6E = PASS_WITH_BOUNDARY / POST_HOC_DISTRIBUTION_ANALYSIS_COMPLETE / NO_NEW_GPU_RUNS
```

登记：

```text
N5_CELLS_LONG_TAIL_OBSERVED
IQR_FENCES_FLAG_P64_S16_RETAIN_OUTLIER
GPU_TIMEOUT_CELL_REMAINS_UNDERPOWERED_N3
```

这是对 PHASE6D 已有 samples的 post-hoc robust analysis；没有新增 GPU run，
不建立 throughput benchmark 或 segment-size recommendation。

## Method

分析 PHASE6D summary中四个 2-token cells的全部 combined samples：

```text
prefix        = 8 / 64
tokens        = 2
segment sizes = 8 / 16
strategy      = RETAIN / RELEASE_RESTORE
combined n    = 5 for p8-s8, p64-s8, p64-s16
combined n    = 3 for p8-s16 (GPU timeout boundary)
```

统计包含 mean、median、p05/p25/p75/p95、min/max、IQR和 Tukey 1.5×IQR fences。
每个 generation sample同时检查：

```text
generation transition == segment count × token count
```

## Checks

八项 checks全部 PASS：

| Check | Result |
| --- | --- |
| `ALL_EXPECTED_CELLS_PRESENT` | PASS |
| `COMPLETED_CELLS_AT_N5` | PASS |
| `GPU_TIMEOUT_CELL_REMAINS_N3` | PASS |
| `ALL_SAMPLES_WITHIN_CELL_SHARE_ONE_OUTPUT` | PASS |
| `ALL_GENERATION_TRANSITIONS_MATCH_STRUCTURE` | PASS |
| `ACTION_TRANSITION_SEMANTICS_PRESERVED` | PASS |
| `ROBUST_DISTRIBUTION_STATS_COMPUTED` | PASS |
| `NO_NEW_GPU_RUNS_ATTEMPTED` | PASS |

## Generation distribution

| Prefix | Segment size / count | Strategy | n | Median | IQR | p95 | Max | IQR outliers |
| ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 8  | 8 / 6   | RETAIN | 5 | 18,712.341ms | 47,415.174ms | 71,415.639ms | 71,415.639ms | none |
| 8  | 8 / 6   | RELEASE_RESTORE | 5 | 18,723.822ms | 48,704.511ms | 67,757.434ms | 67,757.434ms | none |
| 8  | 16 / 3  | RETAIN | 3 | 27,638.236ms | 4,929.721ms | 36,130.025ms | 36,130.025ms | none |
| 8  | 16 / 3  | RELEASE_RESTORE | 3 | 31,111.494ms | 3,019.259ms | 34,633.377ms | 34,633.377ms | none |
| 64 | 8 / 6   | RETAIN | 5 | 30,476.409ms | 39,356.970ms | 108,314.488ms | 108,314.488ms | none |
| 64 | 8 / 6   | RELEASE_RESTORE | 5 | 30,124.981ms | 42,692.464ms | 87,092.392ms | 87,092.392ms | none |
| 64 | 16 / 3  | RETAIN | 5 | 48,834.662ms | 12,941.541ms | 92,221.424ms | 92,221.424ms | 92,221.424ms |
| 64 | 16 / 3  | RELEASE_RESTORE | 5 | 46,200.180ms | 60,510.874ms | 114,914.198ms | 114,914.198ms | none |

completed n=5 cells均呈现 long tail；prefix 64 / segment 16 的 RETAIN样本
`92,221.424ms` 超过 1.5×IQR upper fence。由于 n很小，IQR outlier不是因果诊断。

## Action distribution highlights

| Prefix | Segment size | Strategy | Action median | Action max | IQR outliers |
| ---: | ---: | --- | ---: | ---: | ---: |
| 8  | 8  | RETAIN | 0.002792ms | 0.397708ms | yes |
| 8  | 8  | RELEASE_RESTORE | 0.004157ms | 32.784917ms | yes |
| 64 | 8  | RETAIN | 0.004709ms | 0.521583ms | yes |
| 64 | 8  | RELEASE_RESTORE | 0.007542ms | 24.931000ms | yes |
| 64 | 16 | RETAIN | 0.004916ms | 0.022125ms | none |
| 64 | 16 | RELEASE_RESTORE | 0.007240ms | 15.095042ms | none |

completed n=5 cells的 action distribution同样显示长尾；p8/s16 只有 n=3且没有
PHASE6D completed samples，不足以比较。

## Semantics

所有 cell内 samples共享同一 generated token output；所有 generation transition
符合 `segment count × token count`。RETAIN action transitions全为 `0`，
RELEASE_RESTORE全为 `1`。因此长尾不代表 Execution State identity/lineage/position
语义失败。

## Artifact

```text
simigo2-experimental/results/backend-conformance/mlx-phase6e-distribution-analysis.json
```

Source：

```text
simigo2-experimental/results/backend-conformance/mlx-phase6d-distribution-partial-summary.json
```

## Finding

```text
N5_CELLS_LONG_TAIL_OBSERVED /
IQR_FENCES_FLAG_P64_S16_RETAIN_OUTLIER /
GPU_TIMEOUT_CELL_REMAINS_UNDERPOWERED_N3 /
NO_CAUSAL_SEGMENT_SIZE_MODEL_ESTABLISHED
```

## Boundary

这是 post-hoc small-n distribution analysis。IQR outlier不是故障判定；n=3 cell
的 IQR本身不稳定。没有新增 GPU run，没有定位 GPU timeout root cause，也没有验证
warm-KV 或 segment-residency policy。

## Non-claims

```text
❌ throughput benchmark
❌ production performance readiness
❌ segment-size recommendation
❌ GPU timeout root cause
❌ warm-KV retention
❌ cross-backend / cross-hardware comparison
```

## Next

1. 用户确认/冷却后决定是否重试 `p8 / tokens2 / segment16`。
2. instrument每 segment materialize / forward / release。
3. 若继续 distribution expansion，使用 counterbalanced runs并报告完整 samples。
