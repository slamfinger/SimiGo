# SimiGo Lab RQ3 LLAMA Batch Identity Probe — 2026-09-29

## Decision

Protocol：

```text
RQ3.LLAMA.BATCH.IDENTITY.PROBE.V1
```

Result：

```text
COMPLETE / NO_CANCEL_BATCH_IDENTITY_INSTABILITY_OBSERVED
CANCELLATION_CAUSALITY_NOT_SUPPORTED
```

这个 probe 回应 higher-concurrency curve 的 identity mismatch：在没有 DELETE、没
有 cancellation 的 same-load repeat 中，llama-server 仍然出现 concurrent greedy
token/content 不稳定。因此不能把先前 mismatch 归因于 cancellation；可登记的局
部化结论是 current llama-server concurrent scheduling / batching boundary，
不是 llama.cpp 内部实现机制。

## Experiment

新增：

```text
simigo2-experimental/scripts/rq3_llama_batch_identity_probe.py
```

Server：

```text
llama-server 0.3.0-dev build 10775 commit 67a17c17c
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
ctx2048 / parallel4 / n_slots=4 / n_ctx_slot=512
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

每 cycle：

```text
1 long full-completion chat request
+ 3 greedy /completion controls
= 4 slots filled
```

没有 resumable-stream DELETE，没有 cancellation，没有 Execution State object。
16 cycles，temperature 0，seed 42，long `n_predict=256`，control
`n_predict=8`。

## Results

| Check | Result |
| --- | ---: |
| batches completed | **16/16** |
| within-cycle all controls identical | **8/16** |
| within-cycle mixed controls | **8/16** |
| across-cycle stable vs cycle 0 | **8/16** |
| all controls matched single-load reference | **8/16** |

全部 48 个 control outputs 分成两组：

```text
" or pong\n\n<think>\nThe user is"     32
" or pong\n\n<think>\nThe user wants"  16
```

Diagnostic wall-time 只作运行记录：

```text
control client mean  1,960.671ms
control client max   1,978.441ms
long client mean    12,485.307ms
```

Artifact：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-batch-identity-no-cancel.json
```

## Finding

> **NO_CANCEL_BATCH_IDENTITY_INSTABILITY_OBSERVED**

在完全删除 cancellation 的 same-load repeat 中，8/16 batches 的 3 个 greedy
controls 没有全部一致。这个比例足以解释 higher-concurrency curve 中观察到的
strict identity mismatch 边界；后者不应被解释为 DELETE 引发的语义破坏。

可登记：

```text
CANCELLATION_CAUSALITY_NOT_SUPPORTED
```

更精确地说：current llama-server concurrent scheduling / batching 下，同一
greedy request batch 的 token identity 不是 stable invariant。内部 scheduling、
batch composition、sampling 或上游实现路径仍未定位。

## Boundary

本 run 覆盖 current llama-server build、GGUF model、`parallel4/ctx2048`、
1 long + 3 controls、16 cycles。它不是 Execution State failure、production
readiness、性能 claim、上游 llama.cpp 源码定位或跨 backend conclusion。

## Non-claims

```text
❌ cancellation 导致 identity mismatch
❌ llama.cpp 内部机制已定位
❌ higher-concurrency semantic closure 已完成
❌ production readiness 已完成
❌ performance / throughput claim 已建立
```

## RQ3 boundary

RQ3 增加：

```text
NO_CANCEL_BATCH_IDENTITY_INSTABILITY_OBSERVED
CANCELLATION_CAUSALITY_NOT_SUPPORTED
```

RQ3 仍保持 OPEN。后续如果继续这条线，应比较 no-cancel batching、single-slot
baseline 与 slot-to-response mapping，而不是把 strict token identity 当作
higher-concurrency cancellation gate。
