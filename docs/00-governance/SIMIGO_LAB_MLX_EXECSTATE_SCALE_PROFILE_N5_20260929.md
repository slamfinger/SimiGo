# SimiGo Lab MLX Execution State Scale Profile N5 — 2026-09-29

## Result

```text
COST2-N5 = PASS / OVERSIZED_MLX_TOKEN_LENGTH_REPLICATION_WITH_BOUNDARY
```

登记：

```text
MLX_EXECSTATE_SCALE_N5_REPLICATION_PASS
PAIRED_STATE_DIRECT_DELTAS_NOT_STABLE_AT_N5
STATE_LOCAL_COST_MICROSECOND_SCALE
NO_PERFORMANCE_BENCHMARK_CLAIM
```

这是 phase-6 scale observation 的 `n=5` replication，不是 throughput
benchmark、生产 performance claim 或跨模型/跨硬件比较。

## Experiment

复用 `runScaleSweep`，把每个 prefix length 的 paired cycles 从 `2` 提高到
`5`：

```bash
simigo2-experimental/.build/debug/simigo2ctl mlx-execstate-scale \
  <LOCAL_HOME>/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-Next-4bit/snapshots/7b9321eabb85ce79625cac3f61ea691e4ea984b5 \
  --lengths 8,64,256 --pairs-per-length 5 --tokens 1 --segment-size 8
```

每个 bucket 交替运行 direct-vs-state：

```text
direct: seed + filler prefix + root input，无 Execution State binding
state:  bind prefix -> capture -> consume representation
        -> advance/bind -> release stale
```

## Semantic checks

```text
checks = 3/3 PASS
```

| Check | Result |
| --- | --- |
| `ALL_LENGTHS_OBSERVED` | PASS |
| `ALL_SCALE_SEMANTICS_STABLE` | PASS |
| `OVERSIZED_PROFILE_UNDER_30GIB` | PASS |

## Paired observation

每个 bucket `n=5`。`State−Direct` 为同 pair 内的差值：

| Prefix tokens | Direct mean / median / stdev ms | State mean / median / stdev ms | Delta mean / median / stdev ms | State local mean ms |
| ---: | ---: | ---: | ---: | ---: |
| 8   | `10347.051942 / 10343.566625 / 38.835722` | `10319.162092 / 10303.022041 / 40.765232` | `-27.889850 / -14.784833 / 51.927615` | `0.033925` |
| 64  | `11657.396400 / 11651.864875 / 42.755855` | `11682.952442 / 11658.074417 / 47.915331` | `+25.556042 / +40.793125 / 75.081490`  | `0.010392` |
| 256 | `14588.178175 / 14583.505333 / 72.350282` | `14694.253184 / 14674.410167 / 48.356080` | `+106.075009 / +96.983626 / 77.262420` | `0.010392` |

prefix `8` 的 state local mean 被一个 `0.131542ms` sample 拉高；其中位数仍是
`0.010959ms`。因此当前证据只支持 state local bookkeeping 处于 microsecond
scale，不支持稳定 overhead估计。

## Resource observation

```text
peak footprint      = 7,617 MiB
max swap            = 0 MiB
segment transitions = 202
```

## Environment boundary

复核时本机没有活跃 `llama-server` 或 `simigo2ctl` 进程，`18080` 无监听；
系统 memory pressure 为 `0`。用户另外观察到 llama-server 与 simigo2ctl 同时
运行时 host swap 达 `21.51 GiB`。artifact 内本 run 记录为
`maxSwap = 0 MiB`，所以该 host swap 不能当作本 run 内 swap 证据。

但如果并发进程与本次 run 时间重叠，CPU/GPU/内存调度仍是潜在 confound。
因此本报告只接受 semantic / Execution State replication PASS；所有 paired
latency 和 local-cost observation 继续保持 bounded interpretation。后续若要把
这些数字升级为 cost characterization，必须在无并发 inference 进程、内存压力
受控、记录 host resource context 的条件下 rerun。

## Artifact

```text
simigo2-experimental/results/backend-conformance/mlx-execstate-scale-profile-n5.json
```

SHA-256：

```text
1f5f0b48c110660e103146be88e782053133f3de9b7998f1c311bcb8945e472b
```

## Finding

```text
TOKEN_LENGTH_LATENCY_TREND_REPRODUCED /
PAIRED_DELTA_SIGNS_AND_MEDIANS_NOT_STABLE_ENOUGH_FOR_OVERHEAD_CLAIM /
STATE_LOCAL_COST_REMAINS_MICROSECOND_SCALE
```

与 `n=2` pilot相比，`n=5` 提高了 observation density并保持 semantic PASS，但仍
不足以建立置信区间、曲线模型或生产 hot-path non-regression结论。

## Non-claims

```text
❌ state overhead 稳定为 -27.889850 / +25.556042 / +106.075009ms
❌ prefix-length latency 曲线已建立
❌ production throughput 或 hot-path non-regression 已建立
❌ 21.51GiB host swap 是本 run 内 resource 证据
❌ 与 LLAMA 或跨硬件成本可直接比较
```

## Next

1. 在无并发 inference workload 的 clean host state 下复测。
2. 增加 samples、order counterbalancing和置信区间报告。
3. 将 prefix length、generated tokens、segment size、retain/release 与 warm/cold
   segment residency 分离为 full factorial。
4. 对每次 run 记录 host process set、swap、compressor和 memory pressure context。
