# SimiGo Lab RQ3 LLAMA Parallel-8 Cancellation Curve — 2026-09-29

## Result

```text
PARALLEL8 = PASS_WITH_BOUNDARY / HIGHER_CONCURRENCY_CANCEL_IDENTITY_CURVE
LEVELS = L1-L7
IDENTITY = 14/14 CYCLES
```

登记：

```text
RQ3_LLAMA_PARALLEL8_CANCELLATION_CURVE_PASS
EIGHT_SLOT_CANCEL_ACCEPTANCE_PASS
SAME_CONCURRENCY_GREEDY_IDENTITY_PASS
THIRTY_SECOND_BASELINE_WATCHDOG_INSUFFICIENT
```

这是 no-Execution-Object backend cancellation curve；不是 production readiness或
performance benchmark。

## Configuration

```text
model              = Cyber-Tiel Coder 35B A3B GGUF MTP UD Q4_K_XL
llama-server slots = 8
context per slot   = observed 256
ubatch             = 8
threads            = 4
cache flags        = no-cache-prompt / no-cache-idle-slots / cache-ram 0
slot similarity    = 0.0
long tokens        = 128
control tokens     = 8
cancel delay       = 100ms
cycles             = 14
seed               = 42
baseline watchdog  = 120s
control watchdog   = 120s
free watchdog      = 90s
```

`L=(1..7)`各运行 2 次；control count为 `8-L`。总 DELETE expected为：

```text
2 × (1+2+3+4+5+6+7) = 56
```

## Checks

| Check | Result |
| --- | --- |
| `ALL_CANCELS_ACCEPTED` | PASS |
| `ALL_CONTROL_BATCHES_COMPLETED` | PASS |
| `CONTROLS_OVERLAPPED_CANCELLATION_WINDOW` | PASS |
| `SAME_LOAD_BASELINE_STABLE` | PASS |
| `GREEDY_IDENTITY_ACROSS_CANCEL` | PASS |

计数：

```text
cycles passed cancel                         = 14/14
cancel accepted                              = 56/56
cycles matched same-concurrency baseline      = 14/14
cycles same-load baseline controls identical  = 14/14
controls started before all long free         = 14/14
controls finished before all long free        = 0/14
```

`controlsFinishedBeforeAllLongFree = 0` 是 protocol边界：只要求 control进入
cancellation window并与同并发 baseline identity一致。

## Curve observations

| Level | Longs / Controls | Cancel accepted | Free mean | Control client mean |
| ---: | ---: | ---: | ---: | ---: |
| L1 | 1 / 7 | 2/2 | 4,543.997ms | 5,470.855ms |
| L2 | 2 / 6 | 4/4 | 7,512.166ms | 8,158.419ms |
| L3 | 3 / 5 | 6/6 | 11,452.115ms | 12,286.665ms |
| L4 | 4 / 4 | 8/8 | 18,199.071ms | 18,928.587ms |
| L5 | 5 / 3 | 10/10 | 27,529.977ms | 28,148.408ms |
| L6 | 6 / 2 | 12/12 | 29,414.962ms | 29,969.048ms |
| L7 | 7 / 1 | 14/14 | 35,534.542ms | 35,832.972ms |

Aggregate：

```text
delete→all long free mean = 19,169.547ms
delete→all long free p95  = 35,734.813ms
delete→all long free max  = 37,726.799ms
```

## Operational note

第一次 8-slot attempt使用旧的固定 30s baseline/control watchdog，在 same-load
baseline controls处超时且未进入正式 report。slots随后回到 idle。脚本已改为
`--long-timeout-ms` / `--control-timeout-ms`，并在 baseline controls失败时落盘
failure artifact。正式 protocol使用 120s watchdog后完整 PASS。

这不建立“30s 不够”的通用结论；它只证明当前 8-slot / t128 / 7-control workload
可超过 30s，120s 足够完成本次 run。

## Artifact

```text
simigo2-experimental/results/backend-conformance/rq3-llama-concurrency-curve-parallel8-t128.json
```

脚本变更：

```text
simigo2-experimental/scripts/rq3_llama_concurrency_curve.py
```

## Boundary

结果限定 current GGUF snapshot、8-slot server launch、observed per-slot context
256、ubatch8、t128 long stream、L1–L7 workload、100ms cancel delay、120s baseline/
control watchdog、90s free watchdog、seed 42和本机 harness。没有 Execution State
对象参与。不能推广到其他 slot count、context length、模型、硬件或 production。

## Non-claims

```text
❌ production cancellation readiness
❌ 8-slot 释放延迟可接受
❌ 120s 是通用 watchdog
❌ greedy identity 是 batch invariant
❌ Execution State cancellation 已被本 curve覆盖
❌ >8 slot 或 t256/8-slot closure已完成
```

## Next

1. 在继续扩容前，先定位 8-slot的 per-slot context从 512降至 256对 identity和
   free latency的影响。
2. 若继续 slot扩容，优先复现 8-slot / t128 second seed，再考虑 10-slot。
3. t256 closure需要单独 protocol，并使用显式 per-slot context预算。
