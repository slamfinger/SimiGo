# SimiGo Lab RQ3 LLAMA Swift Execution State Fork/Restore — 2026-09-29

## Decision

把 Swift representation-consuming integration 从普通 hot-path 扩展到 live
fork / diverge / release / restore / replay，登记为：

```text
SWIFT_EXECSTATE_FORK_RESTORE_INTEGRATION_PASS
```

RQ3 仍保持 OPEN。Swift cancellation integration 和 MLX oversized equivalent
A/B 仍未收口。

## Minimal implementation

新增：

```text
simigo2-experimental/Sources/SimiGo2Experimental/
  LLAMAServerExecutionStateForkRestore.swift
```

CLI：

```text
simigo2ctl llama-execstate-fork-restore
```

每 sample 用新的 `ExecutionContinuityCoordinator` 驱动
`LLAMAServerExecutionStateBackend`，再由 Swift
`LLAMAServerExecutionStateExecutor` 消费 `LLAMAServerPrefixPayload`。
llama-server 继续拥有 inference 和 native cache；没有第二 KV authority。

## Sequence

```text
create/bind parent at position 0
→ coordinator fork child at fork point
→ capture parent checkpoint
→ reference generation
→ advance/bind parent to position 1
→ advance/bind child to divergent position 1
→ divergent generation
→ release divergent representation
→ restore child to position 0
→ capture restored representation
→ replay generation
```

固定 greedy token prefix：

```text
parent     [5423, 6681, 799, 3299, 25, 29018]
divergent  [12139, 279, 2235, 1622, 13, 3301, 6681, 25, 8029, 13053]
```

## Experiment

Protocol：

```text
RQ3.LLAMA.SWIFT.EXECSTATE.FORK.RESTORE.V1
```

Backend：

```text
llama-server 0.3.0-dev build 10775 commit 67a17c17c
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
ctx512 / parallel1 / n_slots=1
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

请求使用 `cache_prompt=false`、temperature 0、seed 42、8 generated tokens、
30 samples。这与此前 Python fork/restore run 相邻但不完全同配置；因此本
run 不与旧 cost 数字做直接 paired comparison。

## Results

| Check | Result |
| --- | ---: |
| restore replay identical | **30/30** |
| branch diverged | **30/30** |
| parent non-interference | **30/30** |
| child restored to fork point | **30/30** |

Timing 只作当前 harness 运行记录：

| Metric | Mean |
| --- | ---: |
| reference client | `355.008ms` |
| divergent client | `450.940ms` |
| replay after restore client | `356.934ms` |
| replay − reference | `+1.926ms` |
| local fork + capture | `16.071µs` |
| local release + restore + capture | `34.044µs` |

Artifact：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-swift-execstate-fork-restore.json
```

## Verification

修改 Swift 后重新执行：

```text
swift test
```

Result：

```text
SimiGoRuntimeContractTests 19/19 PASS
SimiGo2ExperimentalTests   137/137 PASS
Swift Testing              1/1 PASS
Total                     157 PASS / 0 FAIL
```

## Boundary

这是当前 token-prefix representation、当前 coordinator/backend/HTTP
composition、当前 GGUF model 和 short-prompt workload 的 harness-level live
integration evidence。它不是 streaming production client、cancellation
integration、性能 claim、上游 llama.cpp claim 或跨 backend conclusion。

## Non-claims

```text
❌ Swift cancellation executor integration 已完成
❌ MLX oversized equivalent A/B 已完成
❌ production readiness 已完成
❌ 耗时可外推到所有 prompt、context、模型、backend 或网络条件
❌ 本 run 可与旧 Python cost run 直接 paired compare
```
