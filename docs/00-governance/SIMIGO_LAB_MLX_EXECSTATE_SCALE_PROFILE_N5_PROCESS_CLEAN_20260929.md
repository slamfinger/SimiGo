# SimiGo Lab MLX Execution State Scale Profile N5 Process Clean — 2026-09-29

## Result

```text
COST2-N5-PROCESS-CLEAN = PASS / SEMANTIC_REPLICATION_WITH_LATENCY_OBSERVATION_BOUNDARY
```

登记：

```text
MLX_EXECSTATE_SCALE_N5_PROCESS_CLEAN_PASS
PROCESS_CLEAN_ISOLATION_PASS
PREFIX8_STATE_DIRECT_DELTA_NEAR_ZERO
PREFIX64_AND_256_POSITIVE_MEAN_DELTA_OBSERVED
NO_PERFORMANCE_BENCHMARK_CLAIM
```

本次 run 前后均确认没有 `llama-server` / `simigo2ctl` 进程，也没有 `18080`
listener。它解决了上一轮并发 inference 的主要 process confound，但仍不是
全系统静默、受控性能实验室或 production benchmark。

## Experiment

```bash
simigo2-experimental/.build/debug/simigo2ctl mlx-execstate-scale \
  <LOCAL_HOME>/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-Next-4bit/snapshots/7b9321eabb85ce79625cac3f61ea691e4ea984b5 \
  --lengths 8,64,256 --pairs-per-length 5 --tokens 1 --segment-size 8
```

每个 bucket 5 组 direct-vs-state paired cycles，共 `15` pairs / `30` runs。
wall clock 为 `392.33s`。

## Process-clean context

| Snapshot | Port `18080` | Inference process | Host swap used | `vm.memory_pressure` |
| --- | --- | --- | ---: | ---: |
| before | none | none | `4,481.19 MiB` | `0` |
| after  | none | none | `4,270.44 MiB` | `452` |

before/after 的 residual OS swap 不归因本 run；artifact内本次进程记录的
`maxSwap = 0 MiB`。after 的 `vm.memory_pressure = 452` 仅原样记录；当前
harness没有把该 sysctl 定义为标准化 pressure score。

## Semantic checks

```text
checks = 3/3 PASS
semantic identical = 15/15 pairs
```

| Check | Result |
| --- | --- |
| `ALL_LENGTHS_OBSERVED` | PASS |
| `ALL_SCALE_SEMANTICS_STABLE` | PASS |
| `OVERSIZED_PROFILE_UNDER_30GIB` | PASS |

## Paired observation

每个 bucket `n=5`：

| Prefix tokens | Direct mean / median / stdev ms | State mean / median / stdev ms | Delta mean / median / stdev ms | State local mean ms |
| ---: | ---: | ---: | ---: | ---: |
| 8   | `10213.045383 / 10215.276500 / 15.905009`   | `10221.644900 / 10223.070542 / 41.837238`   | `+8.599517 / -8.149541 / 54.475544`    | `0.010458` |
| 64  | `11594.005225 / 11570.799917 / 73.750789`   | `11688.244108 / 11663.618000 / 79.435383`   | `+94.238883 / +102.098375 / 66.207528` | `0.009783` |
| 256 | `16002.612900 / 15626.499709 / 1163.057204` | `16351.657625 / 16446.894584 / 1187.671352` | `+349.044725 / +313.837041 / 312.741558` | `0.012891` |

与上一轮 n=5相比，process-clean run 的 `64` / `256` 两个 bucket 的 positive
mean delta更大，而 `8` bucket 的 mean接近零、median为负。方向上提示值得继续
检查 prefix-length相关 cost，但样本量、系统调度、Metal/cache行为和 harness
recompute都仍未分离，因此不建立稳定 overhead或曲线结论。

## Resource observation

```text
peak footprint      = 7,155 MiB
max swap            = 0 MiB
segment transitions = 202
```

## Artifact

结果：

```text
simigo2-experimental/results/backend-conformance/mlx-execstate-scale-profile-n5-clean-isolation.json
```

SHA-256：

```text
b07b912b76d56e2cd2a5a77aa6d728f94a4454de572f9738d85c992b53101915
```

Process context：

```text
simigo2-experimental/results/backend-conformance/mlx-execstate-scale-profile-n5-clean-isolation-host-context.json
```

## Finding

```text
SEMANTIC_REPLICATION_PASS /
LONG_PREFIX_POSITIVE_DELTA_REPRODUCED_AT_N5 /
SHORT_PREFIX_DELTA_REMAINS_WITHIN_NOISE /
STATE_LOCAL_COST_REMAINS_MICROSECOND_SCALE
```

Execution State semantics在 process-clean条件下继续 PASS。state local
bookkeeping mean为 `0.009783–0.012891ms`。generation-level delta观察到
prefix-length相关趋势，但仍不足以支持 hot-path overhead 定量结论。

## Non-claims

```text
❌ state overhead等于 +8.599517 / +94.238883 / +349.044725ms
❌ Execution State hot-path regression已建立
❌ prefix-length cost curve已建立
❌ process-clean等于全系统静默或受控性能环境
❌ production throughput或readiness已建立
❌ residual host swap归因于本 run
```

## Next

1. 在同一 process-clean协议下把每 bucket 扩展到 `n=10`。
2. 将 state local operation、segment materialization、prefix recompute和
   generation分离计时。
3. 加入 order counterbalancing、block randomization和置信区间。
4. 把 process/swap/memory-pressure snapshot直接写入 harness artifact，而不是
   依赖外部 wrapper。
