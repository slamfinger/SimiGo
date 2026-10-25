# SimiGo Lab RQ3 LLAMA Higher-Concurrency Cancellation Curve — 2026-09-29

## Decision

Protocol：

```text
RQ3.LLAMA.CONCURRENCY.CURVE.V1
```

严格 overall 判定：

```text
FAIL / GREEDY_IDENTITY_NOT_BATCH_TRANSITION_INVARIANT
```

可分离登记：

```text
HIGHER_CONCURRENCY_CANCEL_ACCEPTANCE_COMPLETION_PASS
GREEDY_IDENTITY_BOUNDARY_OBSERVED
```

也就是说：所有 explicit DELETE 都被接受，所有并发 control batch 都完成；
但在当前 llama-server 配置下，greedy token/content identity 跨 cancellation-induced
batch transition 不是稳定 invariant。不能把本实验报告为并发语义 closure。

## Implementation

新增：

```text
simigo2-experimental/scripts/rq3_llama_concurrency_curve.py
```

每个 level 使用 `parallel4 / ctx2048 / n_slots=4` 填满全部 slot：

```text
L1 = 1 long stream + 3 greedy controls
L2 = 2 long streams + 2 greedy controls
L3 = 3 long streams + 1 greedy control
```

每个 cycle 先运行同负载 full-completion baseline：相同数量 long request 运行到
完成，同时相同数量 controls 激活。然后运行 cancellation arm：相同数量 resumable
long streams 全部 explicit DELETE，相同数量 controls 保持并发。controls 与
same-load baseline 逐 index 比较。每 level 重复 2 次，共 6 cycles。

## Setup

```text
llama-server 0.3.0-dev build 10775 commit 67a17c17c
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
ctx2048 / parallel4 / n_slots=4 / n_ctx_slot=512
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

Long request：

```text
POST /v1/chat/completions
stream=true
208-token prompt
n_predict=256
100ms 后 DELETE
```

Control：

```text
POST /completion
fixed 6-token greedy prefix
n_predict=8
temperature=0 / seed=42 / cache_prompt=false
```

## Results

| Check | Result |
| --- | ---: |
| DELETE accepted | **12/12** |
| control batches completed | **6/6** |
| controls started before all longs free | **6/6** |
| same-load baseline stable | **5/6** |
| cancellation controls matched same-load baseline | **5/6** |

Observations：

- cycle 0 / L1：cancellation arm controls 与 same-load baseline 不一致。
- cycle 3 / L1：same-load baseline controls 自身不一致。
- 其余 cycles 的 same-load baseline 与 cancellation identity 均 match。

Latency 只作运行记录：

| Level | Long streams | Controls | DELETE→all-long-free mean | Control client mean |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 1 | 3 | `1,089.059ms` | `1,547.686ms` |
| 2 | 2 | 2 | `1,667.971ms` | `2,117.699ms` |
| 3 | 3 | 1 | `2,179.503ms` | `2,439.610ms` |

`controlsFinishedBeforeAllLongFree` 为 `0/6`：在本次 pilot 中，取消后的 long
slots 平均先释放，control batch 随后完成。因此它不再复现 parallel2 报告中
“control 完成时 long 仍 active”的时序。

Artifact：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-concurrency-curve.json
```

## Finding

> **HIGHER_CONCURRENCY_CANCEL_ACCEPTANCE_COMPLETION_PASS**
> **GREEDY_IDENTITY_BOUNDARY_OBSERVED**

在 `parallel4 / ctx2048 / cacheRam0` 当前模型与 prompt 下，explicit DELETE 能
在 1–3 路 active long stream 场景中全部接受；所有 control batch 都完成。但
strict greedy token/content identity 在 cancellation-induced batch transition
下出现 1/6 mismatch；same-load baseline 自身也出现 1/6 mismatch。因此当前
结论只能登记为 completion/acceptance pass 加 identity boundary，不能登记为
higher-concurrency semantic closure。

## Boundary

本 run 覆盖 current llama-server build、GGUF model、4-slot topology、
256-token long requests、8-token greedy controls、6 cycles。未抽取新的
verbosity-6 trace；本 artifact 直接记录 DELETE status、slot free、control
completion 和 identity 比较。性能与延迟只作运行记录，不是吞吐或 SLA claim。

## Non-claims

```text
❌ higher-concurrency semantic closure 已完成
❌ greedy identity 对 batch transition 稳定
❌ production cancellation readiness 已完成
❌ 延迟或吞吐结论已建立
❌ 跨模型 / backend /更长 context /更高 slot 数已证明
```

## RQ3 boundary

RQ3 增加：

```text
HIGHER_CONCURRENCY_CANCEL_ACCEPTANCE_COMPLETION_PASS
GREEDY_IDENTITY_BOUNDARY_OBSERVED
```

RQ3 仍保持 OPEN。下一步应先定位 batch-transition identity mismatch 的机制，
或改用 task-ID / response-level completion semantics，而不是将其解释为
Execution State failure。
