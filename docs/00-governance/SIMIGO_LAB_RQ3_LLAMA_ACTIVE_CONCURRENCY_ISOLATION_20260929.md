# SimiGo Lab RQ3 LLAMA Active Concurrency Isolation — 2026-09-29

## Decision

Protocol：

```text
RQ3.LLAMA.DISTINCT.PROMPT.CARDINALITY.PROBE.V1
```

新增三配置对照后登记：

```text
ACTIVE_SLOT_CONCURRENCY_CAUSAL_BOUNDARY
QUEUED_N4_STABLE
CONTINUOUS_BATCHING_FLAG_NOT_SUFFICIENT
```

同一组 distinct equal-length prompt 在 4 路客户端并发下，只有 multi-slot active
execution 出现 greedy identity drift；`parallel1` 将同一 4 路客户端请求排队串行
执行时完全 stable。

## Common experiment

4 个 distinct prompt，每个 6 tokens：

```text
ping / alpha / beta / gamma
```

每 prompt 先串行生成 3 次 single-load reference，均 stable。然后 cardinality
1–4，各 8 cycles；并发响应按 prompt index 与自己的 reference 比较。没有 long
request、cancellation 或 Execution State object。

## Three configurations

| Config | Slots | Flag | N3 all-match | N4 all-match | Finding |
| --- | ---: | --- | ---: | ---: | --- |
| A | 4 | continuous batching enabled | `4/8` | `4/8` | unstable |
| B | 4 | `--no-cont-batching` | `4/8` | `4/8` | unstable; flag alone not sufficient |
| C | 1 | queued serial execution | **`8/8`** | **`8/8`** | stable |

Config A/B 的 mismatch 模式也一致：

```text
N3: prompt0 mismatch 4/8
N4: prompt0 mismatch 4/8; prompt3 mismatch 4/8
```

Config C 中 N1–N4 的 80 个请求全部与各自 reference 一致。

## Interpretation

> **ACTIVE_SLOT_CONCURRENCY_CAUSAL_BOUNDARY**

mismatch 的必要条件不是客户端提交 4 个请求，而是这些请求在多个 slot 中进入
active concurrent execution。`--no-cont-batching` 不能消除该边界，说明当前
观察不能归因于这个单一开关；parallel1 串行化则消除 mismatch。

这进一步排除：

```text
客户端排队数量
duplicate prompt
cancellation
long request
```

并继续局部化到 llama-server multi-slot concurrent execution / batching。内部
kernel、batch reduction 或 scheduler 机制仍未定位。

## Artifacts

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-distinct-prompt-cardinality-no-cancel.json
  rq3-llama-distinct-prompt-cardinality-no-contbatch.json
  rq3-llama-distinct-prompt-cardinality-parallel1.json
```

## Boundary

覆盖 current llama-server build、GGUF model、4 个 6-token distinct prompts、
8 generated tokens、8 cycles/cardinality。不定位 llama.cpp 内部实现，不建立
correctness、性能、production readiness 或跨 backend claim。

## Non-claims

```text
❌ continuous batching 开关是唯一原因
❌ llama.cpp 内部 kernel/scheduler 机制已定位
❌ parallel1 在所有负载下必然 deterministic
❌ N>=3 在所有模型 / backend / context 下必然不稳定
❌ production readiness 已完成
```

## RQ3 boundary

RQ3 增加：

```text
ACTIVE_SLOT_CONCURRENCY_CAUSAL_BOUNDARY
QUEUED_N4_STABLE
CONTINUOUS_BATCHING_FLAG_NOT_SUFFICIENT
```

RQ3 仍保持 OPEN。
