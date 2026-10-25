# SimiGo Lab RQ3 LLAMA Active Concurrency Threshold — 2026-09-29

## Decision

Protocol：

```text
RQ3.LLAMA.DISTINCT.PROMPT.CARDINALITY.PROBE.V1
```

新增 `parallel2 / active2` 对照后登记：

```text
ACTIVE_BATCH_COUNT_TWO_STABLE
ACTIVE_BATCH_COUNT_THREE_OR_MORE_UNSTABLE
ACTIVE_CONCURRENCY_THRESHOLD_LOCALIZED
```

greedy identity drift 的阈值不是客户端提交数量，而是 simultaneous active batch
cardinality：1 或 2 stable，3 或 4 unstable。

## Experiment

继续使用 distinct equal-length prompt probe：

```text
prompt0 ping
prompt1 alpha
prompt2 beta
prompt3 gamma
```

每 prompt tokenize 后 6 tokens；先串行生成 3 次 single-load reference，三次均
stable。cardinality 1–4，各 8 cycles；响应按 prompt index 与自身 reference
比较。没有 long request、cancellation 或 Execution State object。

本轮 server：

```text
llama-server 0.3.0-dev build 10775 commit 67a17c17c
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
ctx1024 / parallel2 / n_slots=2 / n_ctx_slot=512
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

当客户端 cardinality 为 3 或 4 时，第三个及之后请求在 server 排队；任一时刻最多
2 个 active sequences。

## Result

| Cardinality | Submitted | Max active | Batches | Requests | All-match cycles | Across-cycle stable |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 1 | 1 | 8 | 8 | **8/8** | **8/8** |
| 2 | 2 | 2 | 8 | 16 | **8/8** | **8/8** |
| 3 | 3 | 2 | 8 | 24 | **8/8** | **8/8** |
| 4 | 4 | 2 | 8 | 32 | **8/8** | **8/8** |

Artifact：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-distinct-prompt-cardinality-parallel2-active2.json
```

## Cross-config threshold

| Configuration | Max active | N1 | N2 | N3 | N4 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `parallel1` queued | 1 | `8/8` | `8/8` | `8/8` | `8/8` |
| `parallel2` queued | 2 | `8/8` | `8/8` | `8/8` | `8/8` |
| `parallel4` active | 3–4 | `8/8` | `8/8` | **`4/8`** | **`4/8`** |

因此边界可精确化为：

```text
active batch cardinality 1–2  => observed stable
active batch cardinality 3–4  => observed unstable
```

这与 identical-control cardinality probe 一致：parallel4 下 N3 开始出现
across-cycle drift，N4 出现明显 within-batch mismatch。

## Boundary

本 run 覆盖 current llama-server build、GGUF model、6-token distinct prompts、
8 generated tokens、`parallel2/slot512` 和 8 cycles/cardinality。排队请求的
到达/唤醒顺序没有被 server trace 逐项定位；不能声称队列中完全不存在瞬时 batch
组成差异。结论限定为：在该配置下，客户端 N3/N4 不再引发 mismatch。

## Non-claims

```text
❌ llama.cpp 内部 kernel / batch reduction 机制已定位
❌ active>=3 在所有模型 / backend / context 下必然不稳定
❌ active<=2 在所有负载下必然稳定
❌ performance 或 throughput claim 已建立
❌ production readiness 已完成
```

## RQ3 boundary

RQ3 增加：

```text
ACTIVE_BATCH_COUNT_TWO_STABLE
ACTIVE_BATCH_COUNT_THREE_OR_MORE_UNSTABLE
ACTIVE_CONCURRENCY_THRESHOLD_LOCALIZED
```

RQ3 仍保持 OPEN。
