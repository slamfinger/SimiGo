# SimiGo Lab RQ3 LLAMA Parallel-8 Seed-43 Reproduction — 2026-09-29

## Result

```text
PARALLEL8_T128_SEED43 = PASS_WITH_BOUNDARY / REPRODUCTION_RUN
LEVELS = L1-L7
IDENTITY = 14/14 CYCLES
```

登记：

```text
RQ3_LLAMA_PARALLEL8_CANCELLATION_CURVE_SEED43_PASS
EIGHT_SLOT_CANCEL_ACCEPTANCE_REPRODUCED
SAME_CONCURRENCY_GREEDY_IDENTITY_REPRODUCED
```

这是同一 8-slot / t128 protocol的第二 seed reproduction。每个 run 的 controls
只与同一 seed、同一 concurrency level的 same-load baseline比较；不声称 seed42
与 seed43 的 raw output相同。

## Configuration

与 seed42 正式 run相同：

```text
model              = Cyber-Tiel Coder 35B A3B GGUF MTP UD Q4_K_XL
slots              = 8
context per slot   = observed 256
ubatch             = 8
threads            = 4
long tokens        = 128
control tokens     = 8
cancel delay       = 100ms
cycles             = 14
seed               = 43
baseline watchdog  = 120s
control watchdog   = 120s
free watchdog      = 90s
```

`L=(1..7)`各 2 cycles；总 expected DELETE为 `56`。

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
cancel accepted                              = 56/56
cycles passed cancel                         = 14/14
cycles matched same-concurrency baseline      = 14/14
cycles same-load baseline controls identical  = 14/14
controls started before all long free         = 14/14
controls finished before all long free        = 0/14
```

## Seed comparison

| Level | seed42 free mean | seed43 free mean | seed43−seed42 |
| ---: | ---: | ---: | ---: |
| L1 | 4,543.997ms | 4,391.352ms | −152.645ms |
| L2 | 7,512.166ms | 7,327.960ms | −184.206ms |
| L3 | 11,452.115ms | 10,710.654ms | −741.460ms |
| L4 | 18,199.071ms | 14,041.042ms | −4,158.028ms |
| L5 | 27,529.977ms | 17,192.159ms | −10,337.818ms |
| L6 | 29,414.962ms | 32,767.411ms | +3,352.449ms |
| L7 | 35,534.542ms | 38,366.838ms | +2,832.296ms |

Aggregate：

```text
seed42 free mean = 19,169.547ms
seed43 free mean = 17,828.202ms
seed43−seed42    = −1,341.345ms
```

每层只有 `n=2` cycles；这些差值只描述两次 run，不建立 latency distribution、
seed effect或 performance conclusion。语义结论是两个 seeds均通过同一
cancellation/identity protocol。

## Artifacts

```text
simigo2-experimental/results/backend-conformance/rq3-llama-concurrency-curve-parallel8-t128.json
simigo2-experimental/results/backend-conformance/rq3-llama-concurrency-curve-parallel8-t128-seed43.json
```

## Boundary

结果限定 current GGUF snapshot、8-slot launch、observed 256-token per-slot
context、ubatch8、t128 long stream、L1–L7 workload、100ms cancel delay、120s
baseline/control watchdog、90s free watchdog和本机 harness。没有 Execution State
对象参与。不是 production cancellation readiness、performance benchmark或
>8-slot closure。

## Non-claims

```text
❌ seed42 与 seed43 raw generation output相同
❌ latency差值是稳定 seed effect
❌ production cancellation readiness
❌ L6/L7 释放延迟可接受
❌ >8 slot 或 t256 closure已完成
```

## Next

1. 8-slot语义复现已完成；后续扩容前先明确 per-slot context预算。
2. 若继续 slot扩容，运行 10-slot / t128 / seed42，并保留 120s watchdog。
3. t256 closure需要单独 protocol，避免把 256-token slot context与 256-token
   generation混为一谈。
