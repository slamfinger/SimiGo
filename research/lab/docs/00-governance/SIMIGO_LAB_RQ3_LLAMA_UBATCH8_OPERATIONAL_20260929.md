# SimiGo Lab RQ3 LLAMA Ubatch8 Operational Profile — 2026-09-29

## Decision

在 `ubatch8` cancellation curve strict PASS 和三个 Swift canonical harness PASS
之后，将 canonical mitigated launch profile 从 `ubatch2` 升级为 `ubatch8`。

登记：

```text
UBATCH8_CANONICAL_HARNESS_REGRESSION_PASS
MITIGATED_LAUNCH_PROFILE_UPGRADED_TO_UBATCH8
UBATCH8_SELECTED_OVER_UBATCH2_FOR_LOWER_LATENCY
```

## Rationale

| Profile | Cancellation curve | Swift canonical regression | Relative observation |
| --- | --- | --- | --- |
| `ubatch2` | strict PASS | PASS | latency higher |
| `ubatch8` | strict PASS | PASS | observed latency lower than `ubatch2` in same day runs |

`ubatch8` 保留 identity mitigation，同时减少 `ubatch2` 的 serialization penalty。
它仍不是通用生产配置；性能只在当前 harness 运行中观察，没有建立 throughput /
latency production claim。

## Canonical profile

wrapper default 现为：

```text
ctx2048 / parallel4 / slot512
ubatch8 / threads4 / threads-batch4
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

可用环境变量：

```text
LLAMA_SERVER_BIN
LLAMA_HOST
LLAMA_PORT
LLAMA_THREADS
LLAMA_UBATCH
```

如需复现旧 mitigation：

```bash
LLAMA_UBATCH=2 simigo2-experimental/scripts/rq3_llama_server_mitigated.sh MODEL_PATH
```

## Validation

### Cancellation curve

Protocol：

```text
RQ3.LLAMA.CONCURRENCY.CURVE.V1
```

```text
DELETE accepted                 6/6
cycles passed                   3/3
same-load baseline stable       3/3
cancellation identity matched   3/3
DELETE→all-long-free mean       4,806.919ms
control client mean             5,108.428ms
```

### Swift canonical regression

| Harness | Result |
| --- | --- |
| hot-path A/B | OFF/ON semantic `30/30 + 30/30`; paired delta `+1.499ms` |
| fork/restore | four semantic checks `30/30` |
| cancellation A/B | OFF/ON accepted and recovered `20/20 + 20/20` |

Artifacts：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-concurrency-curve-ubatch8.json
  rq3-llama-swift-execstate-hotpath-ab-ubatch8.json
  rq3-llama-swift-execstate-fork-restore-ubatch8.json
  rq3-llama-swift-execstate-cancellation-ubatch8.json
```

## Boundary

本变更只更新 RQ3 research launch profile 和 harness timeout；不修改 Swift
runtime、Execution State backend、llama.cpp 上游或采样逻辑。所有结果限定
current model、prompt、Metal build、`parallel4/slot512` 与 harness workload。
`ubatch8` latency 仍显著高于普通单请求研究运行，不建立生产 readiness。

## Non-claims

```text
❌ ubatch8 是通用生产配置
❌ 性能结论已建立
❌ Metal kernel / graph reduction 根因已定位
❌ 所有模型 / backend / context 已验证
```

## RQ3 boundary

RQ3 增加：

```text
UBATCH8_CANONICAL_HARNESS_REGRESSION_PASS
MITIGATED_LAUNCH_PROFILE_UPGRADED_TO_UBATCH8
UBATCH8_SELECTED_OVER_UBATCH2_FOR_LOWER_LATENCY
```

RQ3 仍保持 OPEN。
