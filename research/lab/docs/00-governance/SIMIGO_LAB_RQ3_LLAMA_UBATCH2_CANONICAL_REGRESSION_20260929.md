# SimiGo Lab RQ3 LLAMA Ubatch2 Canonical Regression — 2026-09-29

## Decision

在 canonical mitigated launch profile 上回归三个 Swift RQ3 harness，登记：

```text
UBATCH2_CANONICAL_HARNESS_REGRESSION_PASS
CANCELLATION_HARNESS_MULTISLOT_WAIT_FIXED
```

这确认 `ubatch2` mitigation 不只适用于独立 Python probe，也支持既有 Swift
representation-consuming hot-path、fork/restore 和 cancellation harness。

## Profile

使用 canonical wrapper：

```bash
LLAMA_PORT=18080 \
  simigo2-experimental/scripts/rq3_llama_server_mitigated.sh MODEL_PATH
```

实际 profile：

```text
llama-server 0.3.0-dev build 10775 commit 67a17c17c
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
ctx2048 / parallel4 / slot512
ubatch2 / threads4 / threads-batch4
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

## Results

### 1. Swift Execution State hot-path A/B

Protocol：

```text
RQ3.LLAMA.SWIFT.EXECSTATE.HOTPATH.AB.V1
```

| Check | Result |
| --- | ---: |
| representation payload consumed | PASS |
| OFF semantic stability | **30/30** |
| Swift Execution State ON stability | **30/30** |
| paired ON−OFF recovery/hot-path mean | `+0.071ms` |
| Swift capture state operation mean | `6.207µs` |

Artifact：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-swift-execstate-hotpath-ab-ubatch2.json
```

### 2. Swift Execution State fork/restore

Protocol：

```text
RQ3.LLAMA.SWIFT.EXECSTATE.FORK.RESTORE.V1
```

| Check | Result |
| --- | ---: |
| restore replay identical | **30/30** |
| branch diverged | **30/30** |
| parent non-interference | **30/30** |
| child restored to fork point | **30/30** |
| replay − reference mean | `+2.069ms` |
| local fork/capture mean | `13.878µs` |
| local release/restore/capture mean | `25.288µs` |

Artifact：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-swift-execstate-fork-restore-ubatch2.json
```

### 3. Swift Execution State cancellation A/B

Protocol：

```text
RQ3.LLAMA.SWIFT.EXECSTATE.CANCELLATION.V1
```

| Check | Result |
| --- | ---: |
| OFF DELETE accepted + recovery identical | **20/20** |
| Swift Execution State ON DELETE accepted + recovery identical | **20/20** |
| OFF DELETE→free mean | `4,151.218ms` |
| ON DELETE→free mean | `4,146.044ms` |
| paired ON−OFF recovery mean | `-0.721ms` |
| local state operation mean | `26.994µs` |

Artifact：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-swift-execstate-cancellation-ubatch2.json
```

## Harness fix

Swift cancellation harness原先等待 `slots.count == 1`，因此不能直接用于
canonical `parallel4` profile。修复为等待所有 slots idle，并将 free timeout
default 从 `5000ms` 提高到 `15000ms`：

```text
simigo2-experimental/Sources/SimiGo2Experimental/
  LLAMAServerExecutionStateCancellation.swift
```

该修复只放宽 multi-slot readiness 判定，不改变 Execution State semantics、
server flags 或 cancellation protocol。旧 single-slot artifacts 不因此失效。

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

本回归覆盖 current llama-server build、GGUF model、canonical
`ubatch2/threads4/parallel4` profile 和已登记 Swift harness workloads。它不
建立 performance claim、production readiness、Metal kernel 根因或跨模型/跨
backend conclusion。`ubatch2` 仍显著放大 long-request latency。

## Non-claims

```text
❌ ubatch2 是通用生产配置
❌ Metal root cause 已定位
❌ 所有 context / model / backend 已验证
❌ performance claim 已建立
```

## RQ3 boundary

RQ3 增加：

```text
UBATCH2_CANONICAL_HARNESS_REGRESSION_PASS
CANCELLATION_HARNESS_MULTISLOT_WAIT_FIXED
```

RQ3 仍保持 OPEN。
