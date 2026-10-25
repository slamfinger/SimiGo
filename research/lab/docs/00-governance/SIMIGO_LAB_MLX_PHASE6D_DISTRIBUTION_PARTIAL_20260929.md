# SimiGo Lab MLX Phase-6D Distribution Partial — 2026-09-29

## Result

```text
PHASE6D = PARTIAL_PASS_WITH_BOUNDARY / DISTRIBUTION_EXPANSION_PARTIAL / GPU_TIMEOUT_BOUNDARY
```

登记：

```text
THREE_CELLS_DISTRIBUTION_EXPANDED_TO_N5
P8_S16_GPU_TIMEOUT_BOUNDARY
ACTION_AND_GENERATION_DISTRIBUTIONS_OBSERVED
```

这是 targeted distribution expansion，不是 throughput benchmark、production
performance claim 或 segment-size recommendation。

## Design

对 PHASE6A/B 的 2-token cells增加 2 cycles per strategy：

```text
prefix        = 8 / 64
tokens        = 2
segment sizes = 8 / 16
strategy      = RETAIN / RELEASE_RESTORE
target        = PHASE6A 1 + PHASE6B 2 + PHASE6D 2 = 5 per strategy
```

结果：

```text
p8 / segment 8   = expanded to n=5
p64 / segment 8  = expanded to n=5
p64 / segment 16 = expanded to n=5
p8 / segment 16  = remains n=3 after repeated Metal GPU timeout
```

## GPU timeout boundary

`p8 / tokens2 / segment16` 的 PHASE6D cell连续尝试 2次，均未产生 measured
report，错误为：

```text
METAL command buffer execution failed:
kIOGPUCommandBufferCallbackErrorTimeout
```

按空转熔断，不再自动重试。该事件登记为 harness/environment boundary；没有任何
Execution State semantic assertion失败，因此不能解释为 Execution State语义错误。

## Checks

| Check | Result |
| --- | --- |
| `ALL_COMPLETED_REPORTS_PASS` | PASS |
| `ALL_COMPLETED_PAIRED_OUTPUTS_EXACT` | PASS |
| `THREE_CELLS_EXPANDED_TO_N5` | PASS |
| `P8_S16_REMAINS_N3_AFTER_GPU_TIMEOUT` | PASS |
| `RETAIN_NEVER_RELEASES_SEGMENTS` | PASS |
| `RELEASE_ALWAYS_RELEASES_SEGMENTS` | PASS |
| `GENERATION_TRANSITIONS_MATCH_STRUCTURE` | PASS |
| `ALL_COMPLETED_RUNS_ZERO_SWAP` | PASS |
| `ALL_COMPLETED_PROFILES_UNDER_30GIB` | PASS |
| `TARGET_MATRIX_FULLY_EXPANDED_TO_N5` | **NOT COMPLETE** |

所有 completed runs的 paired generated token IDs/text exact；RETAIN action
transitions全为 `0`，RELEASE_RESTORE全为 `1`；generation transitions符合
`segment count × token count`。

## Distribution observation

combined samples：

| Prefix | Segment size / count | n | RETAIN generation median | RELEASE generation median | RETAIN generation mean | RELEASE generation mean |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 8  | 8 / 6   | 5 | 18,712.341ms | 18,723.822ms | 38,679.013ms | 38,210.537ms |
| 8  | 16 / 3 | 3 | 27,638.236ms | 31,111.494ms | 31,884.130ms | 32,872.436ms |
| 64 | 8 / 6   | 5 | 30,476.409ms | 30,124.981ms | 51,056.256ms | 48,867.334ms |
| 64 | 16 / 3 | 5 | 48,834.662ms | 46,200.180ms | 57,027.586ms | 70,047.466ms |

> 精确 stdev以 summary artifact为准；本表列出 mean并强调 distribution方向。PHASE6D
> 后完成 cells的动作成本也出现较大波动，不能把 action mean解释为稳定开销。

 replicated结论：segment size 16 虽然transition更少，但在多数可用对比中仍表现
更慢或更不稳定；不过 PHASE6D 自身遇到 GPU timeout，说明该 cell的运行成本/环境
敏感性更高。

## Resource / stability

已完成 PHASE6D runs：

```text
max swap = 0 MiB
peak footprint <= 30 GiB gate
```

但 repeated GPU timeout只发生在 `p8/t2/segment16`。这不能定位为 segment size
单独致因；可能与连续负载、GPU command scheduling、系统状态或该 cell运行时间有关。

## Verification

本轮只新增 distribution raw/summary artifacts，不改 Swift runtime。最近全仓 Swift
verification保持：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifacts

```text
mlx-release-recovery-distribution-p8-t2-s8.json
mlx-release-recovery-distribution-p64-t2-s8.json
mlx-release-recovery-distribution-p64-t2-s16.json
mlx-phase6d-distribution-partial-summary.json
```

所有文件位于：

```text
simigo2-experimental/results/backend-conformance/
```

`p8/t2/segment16` 无 PHASE6D JSON artifact，因为两次尝试都在 measured report产生
前遇到 GPU timeout。

## Boundary

三个 cells提升到 combined `n=5`，一个 cell保持 `n=3`。summary不是完整 target
matrix，也不是统计显著结论。GPU timeout只说明当前 harness/Metal command在此
cell遇到环境边界，不能定位 root cause。

## Non-claims

```text
❌ full n=5 matrix 已完成
❌ GPU timeout root cause 已定位
❌ segment size 16 语义错误
❌ warm-KV retention 已验证
❌ release-policy recommendation 已建立
❌ production performance readiness 已建立
```

## Next

1. 等待/冷却后由用户确认是否单独重试 `p8/t2/segment16`。
2. instrument每 segment materialize/forward/release，而不是只观测 transition。
3. 对 completed n=5 cells报告完整 median / IQR / p95，并检测 outlier。
4. 若继续 full matrix，应降低单次 workload或分批运行以避免 GPU timeout。
