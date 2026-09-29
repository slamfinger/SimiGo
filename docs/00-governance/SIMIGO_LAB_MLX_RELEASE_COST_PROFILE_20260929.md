# SimiGo Lab MLX Release Cost Profile — 2026-09-29

## Result

```text
COST3 = PASS / OVERSIZED_MLX_RELEASE_ACTION_ISOLATED_WITH_BOUNDARY
```

登记：

```text
MLX_RELEASE_ACTION_COST_ISOLATED
STALE_RELEASE_NOOP_SEMANTICS_ISOLATED
PREFIX_LENGTH_INDEPENDENT_RELEASE_OBSERVED
```

这是 phase-6 release-action isolation，不是 throughput benchmark 或生产
performance claim。

## Question

前一个 cost profile 发现 oversized lifecycle local cost 的主要部分是 release。
本次把 release action 从 generation 中分离，并区分：

```text
current release: 删除当前 binding，并触发 oversized segment-weight release
stale release:   binding 已不匹配，直接 no-op，不释放 segment weights
restore:         checkpoint representation rebind
```

## Experiment

新增 `runReleaseCostProfile` 和 CLI：

```bash
simigo2-experimental/.build/debug/simigo2ctl mlx-release-cost \
  /Users/mr.simi/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-Next-4bit/snapshots/7b9321eabb85ce79625cac3f61ea691e4ea984b5 \
  --lengths 8,64,256 --samples-per-length 10 --segment-size 8
```

每个 sample 执行：

```text
bind checkpoint @0
capture checkpoint
advance logical position @1
bind current representation
capture current
release current       -> expected segment release + binding removal
restore checkpoint    -> expected rebind @0
release stale @1      -> expected no-op
verify checkpoint survives
```

没有 inference generation。

## Semantic checks

六项 checks 全部 PASS：

| Check | Result |
| --- | --- |
| `CURRENT_RELEASE_REMOVES_BINDING` | PASS |
| `RESTORE_REBINDS_CHECKPOINT` | PASS |
| `STALE_RELEASE_PRESERVES_CHECKPOINT` | PASS |
| `STALE_RELEASE_DOES_NOT_RELEASE_SEGMENTS` | PASS |
| `ALL_LENGTHS_OBSERVED` | PASS |
| `OVERSIZED_PROFILE_UNDER_30GIB` | PASS |

30 个 sample 中，current release 的 segment transition delta 全部为 `1`，
stale release 全部为 `0`。

## Cost observation

30 samples：

| Operation | Mean | Median | p95 | Min | Max |
| --- | ---: | ---: | ---: | ---: | ---: |
| capture checkpoint | 0.000632ms | 0.000334ms | 0.000584ms | 0.000250ms | 0.008333ms |
| capture current | 0.000264ms | 0.000250ms | 0.000375ms | 0.000208ms | 0.000500ms |
| current release | 4.061400ms | 4.037834ms | 4.162667ms | 3.972584ms | 4.620208ms |
| restore checkpoint | 0.000533ms | 0.000500ms | 0.000792ms | 0.000375ms | 0.001167ms |
| stale release no-op | 0.000188ms | 0.000167ms | 0.000292ms | 0.000125ms | 0.000375ms |

按 prefix length：

| Prefix tokens | Current release mean | Stale release no-op mean | Stale / Current |
| ---: | ---: | ---: | ---: |
| 8   | 4.112971ms | 0.000200ms | 0.0000487 |
| 64  | 4.022534ms | 0.000183ms | 0.0000456 |
| 256 | 4.048696ms | 0.000179ms | 0.0000443 |

观测到 current release cost 在 8/64/256 token prefix 下基本一致；
stale release 是 no-op，均值约为 current release 的
`0.0044%–0.0049%`。

## Resource observation

```text
peak footprint      = 1,381 MiB
max swap            = 0 MiB
segment transitions = 30
```

因为本 profile 没有 generation，该 footprint 不与 generation profile 的
`7.7–8.0GiB` 直接比较。

同一 commit 全仓 Swift verification：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifact

```text
simigo2-experimental/results/backend-conformance/mlx-release-cost-profile.json
```

## Finding

```text
CURRENT_RELEASE_COST_APPROXIMATELY_4MS /
STALE_RELEASE_IS_NOOP /
PREFIX_LENGTH_INDEPENDENT_IN_OBSERVED_RANGE /
RESTORE_AND_CAPTURE_ARE_MICROSECOND_SCALE
```

这补上前一个 lifecycle profile 的缺口： oversized release 本身约 `4ms`，
不是因为 token-prefix 长度变化；restore/capture 只在微秒级。 与 generation
paired difference 的小样本波动分开。

## Boundary

结果限定 current Qwen3-Coder-Next-4bit snapshot、segment size 8、6 segments、
prefix lengths 8/64/256、每 length 10 samples、无 generation、本机 harness。
该 run 观测的是当前 release implementation 的 local action，不建立最优 release
策略、生产 performance readiness、跨 backend 或跨硬件结论。

## Non-claims

```text
❌ 4ms 是最优或固有成本
❌ stale no-op 时间在所有系统上恒定
❌ prefix length 无关性已建立为统计曲线
❌ production release policy 已验证
❌ 与 LLAMA release 成本可直接对比
```

## Next

1. 将 release cost 与 generation latency 分开进入统一 factorial report。
2. 若要评估 release 策略，需要比较 retain / segment-release / partial-release
   后续 generation recovery 成本。
3. 继续报告分布，不只使用 mean。
