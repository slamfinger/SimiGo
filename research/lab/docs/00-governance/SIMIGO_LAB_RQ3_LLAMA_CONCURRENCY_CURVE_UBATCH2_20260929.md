# SimiGo Lab RQ3 LLAMA Concurrency Curve with Ubatch2 — 2026-09-29

## Decision

Protocol：

```text
RQ3.LLAMA.CONCURRENCY.CURVE.V1
```

将 cardinality probe 发现的 mitigation 放回原始 higher-concurrency cancellation
curve。3-cycle run 判定：

```text
PASS_WITH_BOUNDARY / UBATCH2_CURVE_STRICT_PASS
UBATCH2_MITIGATES_CANCELLATION_IDENTITY
HARNESS_FREE_TIMEOUT_MUST_SCALE_WITH_UBATCH2
```

这修复了 default `ubatch512` curve 中的 same-load baseline instability 和
cancellation identity mismatch。但 `ubatch2` 显著放大 latency；这不是性能修复，
也不是 production recommendation。

## Setup

Server：

```text
llama-server 0.3.0-dev build 10775 commit 67a17c17c
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
ctx2048 / parallel4 / slot512
--ubatch-size 2
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

Harness：

```text
simigo2-experimental/scripts/rq3_llama_concurrency_curve.py
--cycles 3
--expected-slots 4
--cancel-delay-ms 100
--prediction-tokens 256
--control-tokens 8
--free-timeout-ms 15000
--seed 42
```

Curve levels：

```text
L1 = 1 long stream + 3 controls
L2 = 2 long streams + 2 controls
L3 = 3 long streams + 1 control
```

每个 level 先运行同负载 full-completion baseline，再运行相同 slot 占用的
explicit cancellation arm。

## Results

| Check | Result |
| --- | ---: |
| DELETE accepted | **6/6** |
| cancellation cycles passed | **3/3** |
| control batches completed | **3/3** |
| same-load baseline stable | **3/3** |
| cancellation controls matched same-load baseline | **3/3** |
| controls started before all longs free | **3/3** |
| controls finished before all longs free | **0/3** |

所有 strict checks 均 PASS：

```text
ALL_CANCELS_ACCEPTED                       true
ALL_CONTROL_BATCHES_COMPLETED              true
CONTROLS_OVERLAPPED_CANCELLATION_WINDOW    true
SAME_LOAD_BASELINE_STABLE                  true
GREEDY_IDENTITY_ACROSS_CANCEL              true
```

Latency 只作运行记录；`ubatch2` 的代价很大：

| Level | Long streams | DELETE→all-long-free mean | Control client mean |
| ---: | ---: | ---: | ---: |
| 1 | 1 | `4,201.325ms` | `4,691.426ms` |
| 2 | 2 | `8,090.322ms` | `8,352.944ms` |
| 3 | 3 | `13,633.230ms` | `13,854.959ms` |

Artifact：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-concurrency-curve-ubatch2-cycles3.json
```

## Harness timeout observation

第一次尝试使用原 default `free-timeout-ms=5000` 运行 6 cycles，在 cycle1
报 `cancelled long streams did not free`；该失败没有产出 artifact。随后以
`free-timeout-ms=15000` 重跑并通过。因此使用 `ubatch2` 时，5 秒 free timeout
不再适合 heavy curve；复现命令应显式使用 15s 或更大值。不能将第一次 timeout
解释为 slot leak。

## Finding

> **UBATCH2_MITIGATES_CANCELLATION_IDENTITY**

`ubatch2` 同时消除：

```text
same-load baseline greedy instability
cancellation-arm greedy identity mismatch
```

但这只是 current harness / model / Metal / 6-token prompt / short-control
boundary 内的 mitigation。`ubatch2` 的 4.2–13.6 秒释放/控制耗时说明它不适合
作为性能修复；它只是隔离并稳定了 numerical batching boundary。

## Boundary

本 run 覆盖 current llama-server build、GGUF model、`parallel4/slot512`、
`ubatch2`、L1-L3 cancellation curve 和 3 cycles。未测量吞吐或性能收益；没有
定位具体 Metal kernel / graph reduction；没有测试其他模型、backend、prompt
长度或 ubatch 值。

## Non-claims

```text
❌ ubatch2 是通用生产配置
❌ performance regression 已修复
❌ Metal kernel / graph reduction 根因已定位
❌ 其他模型或 backend 必然稳定
❌ production readiness 已完成
```

## RQ3 boundary

RQ3 增加：

```text
UBATCH2_CURVE_STRICT_PASS
UBATCH2_MITIGATES_CANCELLATION_IDENTITY
HARNESS_FREE_TIMEOUT_MUST_SCALE_WITH_UBATCH2
```

RQ3 仍保持 OPEN。
