# SimiGo Lab RQ3 LLAMA Execution State Cancellation A/B — 2026-09-29

## Decision

新增最小 Execution State-side cancellation isolation control，结果登记为：

```text
EXECUTION_STATE_CANCEL_ISOLATION_PASS
```

RQ3 仍为 OPEN。该证据只说明：显式取消 child request、释放 child
representation、恢复 pre-cancel root snapshot 后，root continuation 能恢复到
reference token/content；它不是 production cancellation、Swift integrated
executor 或 native runtime cancellation claim。

## Setup

Backend 与既有 explicit cancellation control 相同：

```text
llama-server 0.3.0-dev build 10775 commit 67a17c17c
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
ctx512 / parallel1 / n_slots=1
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

新增脚本：

```text
simigo2-experimental/scripts/
  rq3_llama_execution_state_cancellation.py
```

20 个 paired cycles，每个 cycle 内 OFF/ON 顺序交替。OFF 是既有 backend
cancel/recovery control；ON 在同一 backend 序列外围增加 local prefix
representation mirror：

```text
bind child from template
  → capture child
  → capture root snapshot
  → start resumable child stream
  → wait 100ms
  → DELETE /v1/stream
  → wait sole slot free
  → release child
  → restore root snapshot
  → greedy one-token recovery /completion
```

该 mirror 只保存 prompt-token prefix representation。llama-server 继续拥有
inference 和 native runtime cache；脚本不接管 KV，也不建立第二 runtime。

## Results

| Check | Result |
| --- | ---: |
| OFF DELETE accepted | **20/20** |
| Execution State ON DELETE accepted | **20/20** |
| OFF recovery token/content identical | **20/20** |
| Execution State ON recovery token/content identical | **20/20** |
| OFF DELETE→free mean | `576.891ms` |
| ON DELETE→free mean | `576.769ms` |
| OFF recovery client mean | `102.883ms` |
| ON recovery client mean | `102.971ms` |
| paired ON−OFF recovery client mean | `+0.088ms` |
| paired ON−OFF recovery client median | `+0.675ms` |
| local state operations per ON cycle, mean | `24.225µs` |

Measured local operations:

| Operation | n | Mean |
| --- | ---: | ---: |
| bind | 20 | `5.760µs` |
| capture | 40 | `1.873µs` |
| release | 20 | `5.440µs` |
| restore | 20 | `6.410µs` |

原始证据：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-execution-state-cancellation-ab.json
```

## Boundary

这是 local prefix representation mirror 的 harness-level A/B，不是 Swift
`LLAMAServerExecutionStateBackend` integrated executor A/B。root 与 child 都是
当前 prefix representation strategy；不代表 MLX oversized tensor/segment
equivalence，也不代表所有 cancellation timing。

新 artifact 记录 DELETE accepted、slot free 与 recovery identity。本轮没有
重新抽取新的 `n_gen` server trace；token-boundary cancellation 行为由同一
build 的前置 explicit cancellation trace evidence 支持。`577ms` DELETE→free
包含等待 in-flight prefill / first-token boundary，不是取消延迟上限。

## Non-claims

```text
❌ Swift LLAMA executor integration 已完成
❌ MLX oversized cancellation/release/recovery equivalence 已完成
❌ 更高并发曲线已收口
❌ production cancellation readiness 已完成
❌ local state overhead 可外推到所有 prompt/model/context
```
