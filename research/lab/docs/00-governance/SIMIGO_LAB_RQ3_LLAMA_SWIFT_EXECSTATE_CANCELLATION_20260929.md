# SimiGo Lab RQ3 LLAMA Swift Execution State Cancellation — 2026-09-29

## Decision

把 Swift coordinator/backend integration 扩展到 explicit llama-server
cancellation recovery，登记为：

```text
SWIFT_EXECSTATE_CANCELLATION_INTEGRATION_PASS
```

RQ3 仍保持 OPEN。这是当前 harness 的 cancellation isolation evidence，
不是 production readiness 或取消延迟上限。

## Minimal implementation

新增：

```text
simigo2-experimental/Sources/SimiGo2Experimental/
  LLAMAServerExecutionStateCancellation.swift
```

CLI：

```text
simigo2ctl llama-execstate-cancel
```

每 cycle 建立 root/child 两个 logical execution：
root 绑定固定 greedy recovery token prefix；child 绑定 tokenize 后的 long
prompt prefix。Swift `LLAMAServerExecutionStateExecutor` 最后消费 restored
root representation。llama-server 继续拥有 inference、resumable stream、
native cache 和 slot；没有第二 KV authority。

## Sequence

OFF：

```text
start resumable long chat stream
→ wait 100ms
→ DELETE /v1/stream?conv_id=...
→ wait sole slot free
→ direct greedy root completion recovery
```

Swift Execution State ON：

```text
capture root representation
→ capture child representation
→ start resumable long chat stream
→ wait 100ms
→ explicit DELETE
→ wait sole slot free
→ release child representation
→ coordinator restore root at position 0
→ capture restored root
→ Swift executor replay one-token recovery
```

## Experiment

Protocol：

```text
RQ3.LLAMA.SWIFT.EXECSTATE.CANCELLATION.V1
```

Backend：

```text
llama-server 0.3.0-dev build 10775 commit 67a17c17c
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
ctx512 / parallel1 / n_slots=1
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

20 paired cycles，每 cycle 内 OFF/ON 顺序交替；long request 256 predicted
tokens，100ms 后 DELETE；recovery 为 one-token greedy completion，
temperature 0，seed 42。

## Results

| Check | Result |
| --- | ---: |
| OFF DELETE accepted + recovery identical | **20/20** |
| Swift Execution State ON DELETE accepted + recovery identical | **20/20** |
| OFF DELETE→free mean / median | `581.350 / 584.507ms` |
| ON DELETE→free mean / median | `574.579 / 569.988ms` |
| OFF recovery client mean / median | `101.881 / 102.158ms` |
| ON recovery client mean / median | `101.499 / 100.086ms` |
| paired ON−OFF recovery mean | `-0.382ms` |
| Swift capture/release/restore/capture per ON cycle mean | `20.827µs` |

Artifact：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-swift-execstate-cancellation.json
```

本轮没有重新抽取 verbosity-6 server trace。`DELETE` accepted、slot free 和
recovery identity 由本 artifact 直接记录；token-boundary cancel 行为由同一
llama-server build 的前置 explicit cancellation trace evidence 支持。

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

本证据覆盖 current one-slot topology、one long child stream、short root
recovery 和 local prefix representation isolation。long child stream 本身不消费
child representation；child state 用于验证 cancellation/release 后 root
continuation 不受影响。

## Non-claims

```text
❌ production cancellation readiness 已完成
❌ DELETE→free 是取消延迟上限或通用成本
❌ MLX oversized equivalent A/B 已完成
❌ 更高并发 cancellation 曲线已收口
❌ 耗时可外推到其他模型、prompt、context、backend 或并发条件
```
