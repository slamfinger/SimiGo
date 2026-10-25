# SimiGo Lab Backend Conformance Opening — 2026-09-29

## Decision

Lab 进入新的研究门：**RQ1 Backend Conformance / OPENING**。

本门响应既定转向：暂停向 SimiGo runtime 增加新功能，把 Lab 重心移到
Execution State 抽象的独立验证。Research State 中的 FORK-3 / P2-ES 已登记
成果继续有效，但不作为继续堆 runtime feature 的授权。

## Research questions

```text
RQ1  Execution State 能否独立于 inference backend 存在？
RQ2  Execution State 能否跨模型架构成立？
RQ3  Execution State 能否在不污染普通 inference hot path 的前提下提供
     capture / fork / restore / release？
```

当前先攻 RQ1。原因是：没有 Backend-neutral conformance harness，RQ2 的
跨架构结果无法排除“同一 backend 特化”的解释；RQ3 也缺少统一的 OFF/ON
比较面。

## Boundary

合法路线是：

```text
Execution State Contract
  → backend adapter
    → backend-specific representation
```

非法路线是：

```text
SimiGo runtime
  → backend A implementation
  → backend B implementation
  → backend C implementation
```

因此本轮只新增最小 conformance battery，不建立第二个 KV authority，
不实现万能推理框架，不改 Coordinator 的逻辑生命周期语义。

## First round evidence — 2026-09-29 03:51 CST

新增：

```text
simigo2-experimental/Tests/SimiGo2ExperimentalTests/
  BackendConformanceMatrixTests.swift
```

同一契约序列覆盖：

```text
create → bind checkpoint → fork → branch divergence
       → stale capture rejection → foreign payload rejection
       → release current representation
       → restore fork point → discard child → parent restore
```

结果：

| Adapter | Result |
| --- | --- |
| `MLXExecutionStateBackend` / `MLXPrefixPayload` | PASS |
| `OversizedSegmentedStateBackend` / `OversizedPrefixPayload` | PASS |

全仓验证：

```text
swift test
XCTest: SimiGoRuntimeContractTests 19/19 PASS
XCTest: SimiGo2ExperimentalTests  136/136 PASS
Swift Testing: 1/1 PASS
Total: 156 PASS / 0 FAIL
Base commit: 669467d + uncommitted conformance harness
```

该结果只证明：两个已存在的 MLX prefix representation strategy 能通过同一
Execution State Contract 序列，且 Backend 不改写 identity、lineage、position
或 continuation。它不证明 RQ1 已经关闭。

## Second round evidence — non-MLX contract + live smoke

新增：

```text
simigo2-experimental/Sources/SimiGo2Experimental/
  LLAMAServerExecutionStateBackend.swift
```

`LLAMAServerExecutionStateBackend` 只拥有 llama-server 路线的
prefix representation binding；llama-server 继续拥有计算和 native runtime
cache。同一 `runConformance(adapter:)` 序列新增第三个入口：

| Adapter | Result |
| --- | --- |
| `LLAMAServerExecutionStateBackend` / `LLAMAServerPrefixPayload` | PASS |

矩阵随后增加同一条共性断言：**释放过期 snapshot 不得清掉新 live binding**。
第一轮执行后，`OversizedSegmentedStateBackend.releaseRepresentation` 使该
断言 FAIL：stale snapshot 触发全局 segment release 并删除当前 binding。
最小根因修复为：先判定 representation 是否仍是 current；stale 直接 no-op；
physical release 后只有仍 current 才清理 binding。修复后三个 backend 均
PASS。该缺陷登记为 `FBC-001`。

全仓验证：

```text
swift test
XCTest: SimiGoRuntimeContractTests 19/19 PASS
XCTest: SimiGo2ExperimentalTests  137/137 PASS
Swift Testing: 1/1 PASS
Total: 157 PASS / 0 FAIL
```

随后使用本机 `llama-server 0.3.0-dev build 10775` 做最小 live smoke：

```text
model      Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
prompt     Return exactly one word: ping
sequence   ping → divergent prompt → ping replay
evidence   simigo2-experimental/results/backend-conformance/
           llama-server-live-smoke.json
```

判读：

```text
semanticIdentical = true
branchDiverged    = true
```

这次 smoke 证明 non-MLX llama-server 在分支持后可按同一 prompt prefix
恢复相同的 continuation 结果；性能耗时只作为运行记录，不作性能结论。
当前 live smoke 的 executor 仍是外部 curl 通路，尚未封装为 Swift
representation-consuming executor；因此 RQ1 可判
**PASS_WITH_BOUNDARY / CLOSED-FOR-CURRENT-CONTRACT**，不能判 universal。

## Cross-architecture evidence inventory

既有结果只作为 RQ2 的 partial evidence 登记，不升级为普适结论：

| Model family / architecture | Gate | Result |
| --- | --- | --- |
| Qwen3-Coder-Next / `qwen3_next` | O6 Execution State × oversized | PASS |
| Qwen3-Coder-30B / `Qwen3MoEModel` | E5 real-runtime scenario | PASS |
| Nail-Qwen3.6 / `Qwen35MoEModel` | E5 real-runtime scenario | PASS |
| Gemma-4 coder / `Gemma4Model` | E5 real-runtime scenario | PASS |

Qwen4Exp 当前本地缓存与 Lab 矩阵中均不可用。因此 RQ2 状态为
**PARTIAL / NOT CLOSED**。

## Backend matrix status

| Dimension | Current | Next hardening / missing scope |
| --- | --- | --- |
| Backend | MLX / mlx-swift-lm; llama-server | integrated non-MLX executor is future hardening |
| Representation | prefix recompute; oversized segmented; LLAMA prefix | independent KV-copy strategy |
| Logical contract | same Coordinator/Contract battery | unchanged |
| Model | Qwen3 Next baseline | architecture B is RQ2 evidence, not RQ1 substitute |
| Hot path | 未做干净 OFF/ON A/B | RQ3 required |
| Cancellation | 不在本轮 claim 内 | later workload gate |

## Acceptance for RQ1 closure

状态：1-6 在以下边界内已满足；live executor 集成与 KV-copy strategy
不作为本 boundary 的收口前置。

1. 新增一个非 MLX backend，只实现 `ExecutionStateBackend` 与必要
   representation payload。
2. 同一 conformance battery 不修改语义断言即可接入。
3. Coordinator、lineage、position、continuation 断言保持逐字不变。
4. capture / fork / restore / release 的错误边界全部通过。
5. 失败时不能提交半新 logical state；release 不破坏 still-live representation。
6. 结论只允许写成：“在已列 backend / architecture / workload 条件下成立”，
   不得写成 universal Execution State。

## RQ1 current finding

在当前 contract 的语义范围内，Execution State 可以脱离 MLX 类型体系存在：
`MLXExecutionStateBackend`、`OversizedSegmentedStateBackend` 和
`LLAMAServerExecutionStateBackend` 都能通过同一 Coordinator 生命周期矩阵。
llama-server live smoke 进一步显示，分支执行污染 native cache 后，同一
prompt prefix 的重放结果仍逐字一致。

因此可登记的结论是：

> **Execution State Contract 在已测的 MLX prefix、oversized segmented prefix
> 与 LLAMA-server prefix representation 上成立；这不是普适 claim。**

## Next minimal step

1. RQ3 首轮 no-fork A/B 已完成，详见
   `SIMIGO_LAB_RQ3_LLAMA_HOTPATH_AB_20260929.md`；仍需 fork/restore、
   long-context、memory-pressure 与 cancellation。
2. 如需 E5 级 non-MLX 闭环，再封装最小 `LLAMAServerPrefixExecutor`；
   不引入第二 runtime。
3. RQ2 等待新的 architecture-B workload；Qwen4Exp 当前不可用。
