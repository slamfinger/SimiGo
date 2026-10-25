# SimiGo Lab RQ3 LLAMA Concurrent Cancellation — 2026-09-29

## Question

显式取消一个 stream 时，另一个并发 short request 是否能正常完成并保持
greedy 语义？这是从单路 cancellation recovery 扩展到 **unaffected-control**
的 backend pilot。

仍然没有 Execution State object。

## Experiment

Harness:

```text
simigo2-experimental/scripts/rq3_llama_concurrent_cancellation.py
```

Server:

```text
llama-server 0.3.0-dev build 10775 commit 67a17c17c
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
ctx1024 / parallel2 / n_slots=2 / n_ctx_slot=512
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

每 cycle：

```text
1. POST /v1/chat/completions
      stream=true, X-Conversation-Id=<unique>
      208-token prompt, max_tokens=256
2. 立刻并发 POST /completion
      fixed 6-token prefix, n_predict=1
3. 100ms 后 DELETE /v1/stream 取消长请求
4. 等待 n_predict=256 的 slot 不再 processing
5. 对比 short control 与 pre-run greedy reference
```

20 cycles。

## Results

| Metric | Result |
| --- | ---: |
| DELETE accepted (`204`) | **20/20** |
| control token/content identical | **20/20** |
| control started before long request freed | **20/20** |
| control finished while long request still active | **20/20** |
| DELETE → long slot free mean | `705.564ms` |
| DELETE → long slot free median | `706.760ms` |
| DELETE → long slot free p95 | `720.590ms` |
| control client mean | `509.130ms` |

verbosity-6 trace 抽取为：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-concurrent-cancellation.server-events.json
```

| Server trace check | Result |
| --- | ---: |
| explicit cancel task observed | `20/20` |
| cancel at `n_gen=1` | `20/20` |
| long release at `n_gen=2` | `20/20` |
| short control released before long release | `20/20` |

原始 control artifact:

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-concurrent-cancellation.json
```

## Finding

> **CONCURRENT_BACKEND_CANCEL_WITH_UNAFFECTED_CONTROL / SEMANTICS_PASS**

在当前 `parallel2 / ctx1024 / cacheRam0` llama-server 配置和该 GGUF model
上，显式取消一个 active stream 不会阻止另一个并发 greedy request 完成；
20/20 次 control 与 reference token/content 一致。server trace 同时确认
short control 先释放，被取消的长请求随后在 token boundary 释放。

`705ms` 的 DELETE→long-free 包含并发资源竞争、等待 in-flight work 与
first-token boundary，不能解释为取消延迟上限或生产 cancellation SLA。

## Non-claims

```text
❌ Execution State cancellation / branch recovery 已验证
❌ 超过 2 路并发已收口
❌ cancellation 下吞吐或延迟回归已收敛
❌ 生产 cancellation readiness
❌ 跨模型 / backend / context 长度普适
```

## RQ3 boundary

RQ3 保持：

```text
OPEN / LOCAL_STATE_NON_REGRESSION /
FORK_RESTORE_SEMANTICS_PASS /
SLOT_STATE_CACHE_ROOT_CAUSE_CONFIRMED /
LONG_D_TRANSITION_PILOT_WITHIN_NOISE /
BACKEND_KV_PRESSURE_RECOVERS /
EXPLICIT_BACKEND_CANCEL_AND_RECOVER /
CONCURRENT_BACKEND_CANCEL_WITH_UNAFFECTED_CONTROL
```

下一个最小缺口仍是 Execution State 侧 cancellation/release/recovery A/B、
MLX oversized 等价 A/B、更高并发曲线，以及 integrated Swift LLAMA executor。
