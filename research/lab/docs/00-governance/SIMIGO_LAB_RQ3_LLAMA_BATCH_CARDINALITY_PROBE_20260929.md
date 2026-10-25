# SimiGo Lab RQ3 LLAMA Batch Cardinality Probe — 2026-09-29

## Decision

Protocol：

```text
RQ3.LLAMA.BATCH.CARDINALITY.PROBE.V1
```

Result：

```text
COMPLETE / BATCH_CARDINALITY_THRESHOLD_LOCALIZED
GREEDY_IDENTITY_UNSTABLE_AT_CONTROL_COUNT_3_PLUS
```

这个 probe 把 no-cancel batch identity instability 进一步与 long request 解耦：
只要并发 identical greedy controls 达到 3，就会出现 across-cycle drift；达到 4
时 within-batch mismatch 明显增加。

## Experiment

新增：

```text
simigo2-experimental/scripts/rq3_llama_batch_cardinality_probe.py
```

Server：

```text
llama-server 0.3.0-dev build 10775 commit 67a17c17c
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
ctx2048 / parallel4 / n_slots=4 / n_ctx_slot=512
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

没有 long request，没有 cancellation，没有 Execution State object。每个
cardinality 用 1–4 个完全相同的 `/completion` controls 填充 batch，重复 8 个
cycles；temperature 0，seed 42，`cache_prompt=false`，8 generated tokens。

## Results

| Cardinality | Batches | Requests | Within-cycle stable | Across-cycle stable | Output groups |
| ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 8 | 8 | **8/8** | **8/8** | `is` × 8 |
| 2 | 8 | 16 | **8/8** | **8/8** | `is` × 16 |
| 3 | 8 | 24 | **8/8** | **7/8** | `is` × 21, `wants` × 3 |
| 4 | 8 | 32 | **5/8** | **1/8** | `wants` × 21, `is` × 11 |

Threshold：

```text
N=1,2  stable
N=3    across-cycle drift appears
N=4    within-batch mismatch appears
```

Diagnostic client latency 只作运行记录，不是性能结论。

Artifact：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-batch-cardinality-no-cancel.json
```

## Finding

> **BATCH_CARDINALITY_THRESHOLD_LOCALIZED**

在 current llama-server build、GGUF model 和 4-slot topology 下，并发 identical
greedy controls 的 token identity 从 cardinality 3 开始出现 across-cycle drift，
在 cardinality 4 出现明显 within-batch mismatch。因此先前
`1 long + 3 controls` probe 的 instability 不需要 cancellation，也不需要 long
request；3 个并发 controls 已经足以进入 boundary。

slot 记录显示 mismatch 不是单一 slot 的简单函数。例如 N4 的输出组在不同
slot 组合间变化；不能把它归因于某个固定 slot。

## Boundary

本 run 只覆盖 current llama-server build、GGUF model、`parallel4/ctx2048`、
同一 prompt/token prefix、8 generated tokens 和 1–4 identical controls。它不
定位 llama.cpp 内部调度或 batch reduction 实现，不建立 correctness、性能或
production readiness claim。

## Non-claims

```text
❌ llama.cpp 内部机制已定位
❌ N>=3 输出在所有模型 / backend / context 下必然不稳定
❌ N<=2 在所有负载下必然稳定
❌ performance 或 throughput claim 已建立
❌ production readiness 已完成
```

## RQ3 boundary

RQ3 增加：

```text
BATCH_CARDINALITY_THRESHOLD_LOCALIZED
GREEDY_IDENTITY_UNSTABLE_AT_CONTROL_COUNT_3_PLUS
```

RQ3 仍保持 OPEN。
