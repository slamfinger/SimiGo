# SimiGo Lab RQ3 LLAMA Parallel-6 Cancellation Curve — 2026-09-29

## Result

```text
PARALLEL6 = PASS_WITH_BOUNDARY / HIGHER_CONCURRENCY_CANCEL_IDENTITY_CURVE
LEVELS = L1 / L2 / L3 / L4 / L5
IDENTITY = 10/10 CYCLES
```

登记：

```text
RQ3_LLAMA_PARALLEL6_CANCELLATION_CURVE_PASS
SIX_SLOT_CANCEL_ACCEPTANCE_PASS
SAME_CONCURRENCY_GREEDY_IDENTITY_PASS
L5_FREE_LATENCY_EXCEEDS_PREVIOUS_20S_ASSUMPTION
```

这是 backend cancellation curve，不包含 Execution State 对象，不是 production
cancellation readiness或 performance benchmark。

## Configuration

```text
model              = Cyber-Tiel Coder 35B A3B GGUF MTP UD Q4_K_XL
llama-server slots = 6
context per slot   = observed 512
ubatch             = 8
threads            = 4
cache flags        = no-cache-prompt / no-cache-idle-slots / cache-ram 0
slot similarity    = 0.0
long tokens        = 128
control tokens     = 8
cancel delay       = 100ms
cycles             = 10
seed               = 42
```

每个 cycle先运行同并发 same-load baseline，再启动 long cancelable streams与
short greedy controls。`L=(1..5)`各运行 2 次；control count为 `6-L`。

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
cycles passed cancel                         = 10/10
cycles matched same-concurrency baseline      = 10/10
cycles same-load baseline controls identical  = 10/10
controls started before all long free         = 10/10
```

## Curve observations

| Level | Longs / Controls | Cancel accepted | Free mean | Control client mean |
| ---: | ---: | ---: | ---: | ---: |
| L1 | 1 / 5 | 2/2 | 5,255.238ms | 6,382.651ms |
| L2 | 2 / 4 | 4/4 | 7,901.493ms | 8,469.063ms |
| L3 | 3 / 3 | 6/6 | 12,149.979ms | 12,815.249ms |
| L4 | 4 / 2 | 8/8 | 17,043.556ms | 17,580.300ms |
| L5 | 5 / 1 | 10/10 | 25,527.031ms | 25,838.241ms |

Aggregate：

```text
delete→all long free mean = 13,575.459ms
delete→all long free p95  = 25,641.629ms
delete→all long free max  = 26,673.012ms
```

`controlsFinishedBeforeAllLongFree = 0/10`，因此本 protocol 只要求 control在
cancellation window内启动并与 same-concurrency baseline比较；不声称 control在
free前完成。

## Operational note

一次未落盘的 preparatory t256 / 20s-free-timeout run在 L5 超出 20s 等待后异常
退出；随后 server slots回到 idle。正式 t128 / 60s run完整 PASS。该记录只用于
解释 timeout hardening，不作为 PASS/FAIL evidence。curve 脚本已增加失败路径
落盘。

## Artifact

```text
simigo2-experimental/results/backend-conformance/rq3-llama-concurrency-curve-parallel6-t128.json
```

脚本变更：

```text
simigo2-experimental/scripts/rq3_llama_concurrency_curve.py
```

## Boundary

结果限定 current GGUF snapshot、6-slot server launch、ubatch8、t128 long stream、
L1–L5 workload、100ms cancel delay、seed 42和本机 harness。没有 Execution State
对象参与。不能推广到其他 slot count、token length、模型、硬件、batch配置或
production workload。

## Non-claims

```text
❌ production cancellation readiness
❌ L5 释放延迟可接受
❌ 20s 是通用 free timeout
❌ greedy identity 是 batch invariant
❌ Execution State cancellation 已被本 curve覆盖
❌ >6 slot 或 t256/6-slot closure已完成
```

## Next

1. 如需继续扩容，先运行 L1–L5 / t128 / 8-slot，再考虑 t256。
2. 定位 L5 delete→free超过 20s的 server-side调度或 slot drain机制。
3. 只有在独立 protocol中才把该 backend curve与 Execution State cancellation
   A/B合并比较。
