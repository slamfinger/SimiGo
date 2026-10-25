# SimiGo Lab RQ3 LLAMA Cancellation — 2026-09-29

## Question

llama-server 的 explicit cancellation 是否能停止一个已进入 decoding 的
backend request，释放唯一 slot，并让后续 greedy short request 语义恢复？

这是 **backend cancellation control**，没有 Execution State object。

## Experiment

Harness:

```text
simigo2-experimental/scripts/rq3_llama_cancellation.py
```

Server:

```text
llama-server 0.3.0-dev build 10775 commit 67a17c17c
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
ctx512 / parallel1 / n_slots=1
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

Cycle:

```text
1. POST /v1/chat/completions
      stream=true
      X-Conversation-Id=<unique>
      max_tokens=256, temperature=0, seed=42
      "Count from 1 to 500..."
2. wait 100ms
3. DELETE /v1/stream?conv_id=<unique>
4. poll /slots until is_processing=false
5. POST /completion with the fixed greedy reference token prefix
      n_predict=1, seed=42, cache_prompt=false
6. compare recovery token/content with reference
```

20 cycles。

## Results

| Metric | Result |
| --- | ---: |
| DELETE accepted (`204`) | **20/20** |
| recovery token/content identical | **20/20** |
| DELETE → slot free mean | `577.376ms` |
| DELETE → slot free median | `581.312ms` |
| DELETE → slot free p95 | `588.358ms` |
| recovery request client mean | `102.501ms` |

verbosity-6 trace 抽取为：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-cancellation.server-events.json
```

全部 20 个 task 的 server trace 均为：

```text
DELETE -> evict_and_cancel
generation reaches n_gen=1
cancel task observed
next token boundary reaches n_gen=2
slot release
```

也就是 `cancelAtTokenOne=20/20`、`releaseAtTokenTwo=20/20`。

原始 control artifact:

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-cancellation.json
```

## Finding

> **EXPLICIT_BACKEND_CANCEL_AND_RECOVER / SEMANTICS_PASS**

在当前 llama-server resumable-stream 路径、唯一 slot、`ctx512`、
`cacheRam0` 与该 GGUF model 上，explicit DELETE 能取消已进入 decoding 的
request；slot 在当前 decoding boundary 释放，后续 greedy one-token request
全部恢复到 reference token/content。

`577ms` 的 DELETE→free 主要是等待 in-flight prefill / first-token boundary；
不能把它解释为取消延迟上限、生产 cancellation latency 或 Execution State
fork cancellation 成本。

## Non-claims

```text
❌ Execution State cancellation 已完成；本 control 没有 Execution State object
❌ /completion 非流式 client-disconnect 已可靠取消（探索中反而跑满 64 token）
❌ 并发 cancellation / mixed workload 已验证
❌ 跨模型 / backend / context 长度普适
❌ production cancellation readiness
❌ DELETE→free 是最优或通用取消延迟
```

## RQ3 boundary

RQ3 保持：

```text
OPEN / LOCAL_STATE_NON_REGRESSION /
FORK_RESTORE_SEMANTICS_PASS /
SLOT_STATE_CACHE_ROOT_CAUSE_CONFIRMED /
LONG_D_TRANSITION_PILOT_WITHIN_NOISE /
BACKEND_KV_PRESSURE_RECOVERS /
EXPLICIT_BACKEND_CANCEL_AND_RECOVER
```

下一最小缺口仍是 Execution State 侧 cancellation/release/recovery A/B、
并发 cancellation、MLX oversized 等价 A/B，以及 integrated Swift LLAMA
executor。
