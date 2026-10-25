# SimiGo Lab RQ3 LLAMA Swift Execution State Hot-path A/B — 2026-09-29

## Decision

新增最小 Swift representation-consuming LLAMA transport，并把普通生成
OFF/ON 通路登记为：

```text
SWIFT_EXECSTATE_HOTPATH_INTEGRATION_PASS
```

它补上“Python mirror 之外，Swift 端也能消费 `LLAMAServerPrefixPayload`”
这一缺口。RQ3 仍保持 OPEN；本证据不覆盖 cancellation、fork/restore、MLX
oversized 或 production readiness。

## Minimal implementation

新增：

```text
simigo2-experimental/Sources/SimiGo2Experimental/
  LLAMAServerExecutionStateExecutor.swift
  LLAMAServerExecutionStateAB.swift
```

CLI：

```text
simigo2ctl llama-execstate-ab
```

`LLAMAServerExecutionStateExecutor` 只做 HTTP request 和 payload type check。
ON 路径从 `LLAMAServerExecutionStateBackend` capture
`LLAMAServerPrefixPayload`，再由 Swift executor 提取 token prefix 请求
llama-server。llama-server 继续拥有 inference 和 native runtime cache；
没有第二 KV authority 或通用推理 runtime。

## Experiment

Protocol：

```text
RQ3.LLAMA.SWIFT.EXECSTATE.HOTPATH.AB.V1
```

Backend：

```text
llama-server 0.3.0-dev build 10775 commit 67a17c17c
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
ctx512 / parallel1 / n_slots=1
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

每个 paired cycle 内 OFF/ON 顺序交替；OFF 直接发送固定 token prefix；ON 先
capture Swift backend representation，再通过 executor 消费同一 prefix。
`cache_prompt=false`，temperature 0，seed 42，8 generated tokens，30 paired
samples。

## Results

| Check | Result |
| --- | ---: |
| Warm representation payload consumed | PASS |
| OFF semantic stability | `30/30` |
| Swift Execution State ON semantic stability | `30/30` |
| OFF client mean / median | `338.788 / 334.816ms` |
| ON client mean / median | `338.781 / 334.513ms` |
| paired ON−OFF client mean | `-0.007ms` |
| paired ON−OFF client median | `+0.174ms` |
| Swift capture state operation mean | `6.171µs` |

Artifact：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-swift-execstate-hotpath-ab.json
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

这只证明当前 Swift HTTP executor 能消费当前 prefix representation，并在
普通生成 A/B 中保持 reference 语义与 local-state non-regression。它不是
fork/restore executor、cancellation executor、streaming production client、
performance claim、上游 llama.cpp claim 或跨 backend conclusion。

## Non-claims

```text
❌ Swift cancellation integration 已完成
❌ Swift fork/restore executor integration 已完成
❌ MLX oversized equivalent A/B 已完成
❌ production readiness 已完成
❌ 耗时可外推到其他模型、prompt、context、并发或网络条件
```
