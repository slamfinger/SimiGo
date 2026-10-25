# SimiGo Lab RQ3 LLAMA Backend Execution Isolation — 2026-09-29

## Decision

Protocol：

```text
RQ3.LLAMA.DISTINCT.PROMPT.CARDINALITY.PROBE.V1
```

新增 CPU-only 对照后登记：

```text
CPU_ONLY_ACTIVE3_4_STABLE
METAL_ACTIVE3_4_UNSTABLE
BACKEND_EXECUTION_PATH_ISOLATED
```

active batch cardinality 3/4 的 greedy identity drift 只出现在 Metal execution
path；同 model、同 probe、同 prompt、`parallel4`、active3/4 的 CPU-only run
全部 stable。因此 instability 不再是一般 llama-server logic 或一般 batched
compute 的抽象结论，而是当前 Metal execution path boundary。

## Common probe

沿用 distinct equal-length prompt cardinality probe：

```text
prompt0 ping
prompt1 alpha
prompt2 beta
prompt3 gamma
```

每 prompt tokenize 后 6 tokens；每个 backend 先串行建立自身 single-load
reference。cardinality 1–4，各 8 cycles；响应按 prompt index 与当前 backend 的
reference 比较。没有 long request、cancellation 或 Execution State object。

## Configurations

| Config | Device | Slots | Result |
| --- | --- | ---: | --- |
| Metal | `MTL0` | 4 | N3/N4 all-match `4/8`; N4 within mismatch `3/8` |
| CPU-only | `--device none --fit off` | 4 | N1–N4 all-match `8/8` |

CPU-only server:

```text
llama-server 0.3.0-dev build 10775 commit 67a17c17c
--ctx-size 2048 --parallel 4
--device none --fit off
--threads 4 --threads-batch 4
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

CPU-only run 的进程 RSS 约为 `15.5GB`，低于 32GB host 约束。每 prompt 的
3 次 reference 均 stable；CPU greedy outputs 与 Metal reference 不同，这是预期
backend numerical-path difference，因此不做跨 backend直接 token identity 比较。

## Results

CPU-only `--device none`：

| Cardinality | Batches | Requests | All-match cycles | Across-cycle stable |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 8 | 8 | **8/8** | **8/8** |
| 2 | 8 | 16 | **8/8** | **8/8** |
| 3 | 8 | 24 | **8/8** | **8/8** |
| 4 | 8 | 32 | **8/8** | **8/8** |

对照 Metal `parallel4`：

| Cardinality | Batches | Requests | All-match cycles | Across-cycle stable |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 8 | 8 | **8/8** | **8/8** |
| 2 | 8 | 16 | **8/8** | **8/8** |
| 3 | 8 | 24 | **4/8** | **4/8** |
| 4 | 8 | 32 | **4/8** | **4/8** |

Artifact：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-distinct-prompt-cardinality-cpu.json
```

## Finding

> **BACKEND_EXECUTION_PATH_ISOLATED**

在 active batch cardinality 3/4 下，CPU-only path 保持 greedy reference
identity；Metal path 出现 mismatch。这把边界从“active batch >=3 一般会漂移”
进一步收窄为“current Metal active batch execution path 的 backend boundary”。

该结果不定位具体 Metal kernel、graph capture、batch reduction 或内存布局；也不
声称 CPU-only 更正确。不同 backend 可以有不同的 numerical reference。

## Boundary

覆盖 current llama-server build、当前 GGUF model、CPU vs Metal device selection、
4 个 6-token distinct prompts、8 generated tokens、`parallel4/slot512` 和
8 cycles/cardinality。CPU-only 与 Metal 使用各自 reference；不能把两个 backend
的 raw outputs 直接互称相同。

## Non-claims

```text
❌ 具体 Metal kernel / graph / batch reduction 已定位
❌ CPU backend 普遍 deterministic
❌ Metal backend 普遍 non-deterministic
❌ CPU-only 更正确或更适合生产
❌ performance / throughput claim 已建立
❌ 跨模型或跨 backend 普适结论已建立
```

## RQ3 boundary

RQ3 增加：

```text
CPU_ONLY_ACTIVE3_4_STABLE
METAL_ACTIVE3_4_UNSTABLE
BACKEND_EXECUTION_PATH_ISOLATED
```

RQ3 仍保持 OPEN。
