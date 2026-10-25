# SimiGo Lab RQ3 LLAMA Distinct-Prompt Cardinality Probe — 2026-09-29

## Decision

Protocol：

```text
RQ3.LLAMA.DISTINCT.PROMPT.CARDINALITY.PROBE.V1
```

Result：

```text
COMPLETE / DISTINCT_PROMPT_CARDINALITY_INSTABILITY_OBSERVED
DUPLICATE_PROMPT_CONFOUND_EXCLUDED
```

prior identical-control probe 的 N>=3 mismatch 可能被解释为 duplicate prompt /
duplicate sequence batching artifact。本 probe 用 4 个不同但 token length 相同的
prompt 重跑，N3/N4 仍然不稳定，因此 duplicate-prompt 解释被排除。

## Experiment

新增：

```text
simigo2-experimental/scripts/rq3_llama_distinct_prompt_cardinality_probe.py
```

Server：

```text
llama-server 0.3.0-dev build 10775 commit 67a17c17c
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
ctx2048 / parallel4 / n_slots=4 / n_ctx_slot=512
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

Distinct prompts：

```text
Return exactly one word: ping
Return exactly one word: alpha
Return exactly one word: beta
Return exactly one word: gamma
```

每个 prompt tokenize 后都是 6 tokens。没有 long request，没有 cancellation，
没有 Execution State object。每个 prompt 先串行生成 3 次 single-load reference；
三次全部 token/content stable。然后按 cardinality 1–4 并发运行，每 cardinality
8 cycles。并发响应按 prompt index 与自己的 single-load reference 比较。

## Results

| Cardinality | Batches | Requests | Cycles all matched own reference | Across-cycle stable | Mismatches by prompt |
| ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 8 | 8 | **8/8** | **8/8** | `0/0/0/0` |
| 2 | 8 | 16 | **8/8** | **8/8** | `0/0/0/0` |
| 3 | 8 | 24 | **4/8** | **4/8** | `4/0/0/0` |
| 4 | 8 | 32 | **4/8** | **4/8** | `4/0/0/4` |

single-load references：

```text
prompt 0 stable = true
prompt 1 stable = true
prompt 2 stable = true
prompt 3 stable = true
```

Mismatch slots 不是固定 slot：

```text
N3: prompt0 mismatch见于 slots 0(2),1(1),2(1)
N4: prompt0 mismatch见于 slots 1(2),3(1),0(1)
    prompt3 mismatch见于 slots 3(2),1(1),2(1)
```

Diagnostic client latency 只作运行记录，不是性能结论。

Artifact：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-distinct-prompt-cardinality-no-cancel.json
```

## Finding

> **DISTINCT_PROMPT_CARDINALITY_INSTABILITY_OBSERVED**
> **DUPLICATE_PROMPT_CONFOUND_EXCLUDED**

在移除 duplicate prompt 后，N3 开始出现同一 prompt 偏离自己的 single-load
reference；N4 有两个 prompt 各出现 4/8 mismatch。这说明 instability 不是
identical-prompt artifact，而是一般 concurrent batching / scheduling boundary。

slot 分布不支持“固定 bad slot”解释。

## Boundary

本 run 覆盖 current llama-server build、GGUF model、`parallel4/ctx2048`、4 个
6-token distinct prompts、8 generated tokens 和 1–4 cardinality。它不定位
llama.cpp 内部 batching/reduction 实现，不建立 correctness、性能或 production
readiness claim。

## Non-claims

```text
❌ duplicate prompt 是唯一或主要原因
❌ llama.cpp 内部机制已定位
❌ N3/N4 在所有模型 / backend / prompt / context 下必然不稳定
❌ N1/N2 在所有负载下必然稳定
❌ performance 或 throughput claim 已建立
```

## RQ3 boundary

RQ3 增加：

```text
DISTINCT_PROMPT_CARDINALITY_INSTABILITY_OBSERVED
DUPLICATE_PROMPT_CONFOUND_EXCLUDED
```

RQ3 仍保持 OPEN。
