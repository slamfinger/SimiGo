# SimiGo

> **An Execution-State-Centered Runtime for Long-Lived Model Execution**

SimiGo 是一个以 **Execution State（执行状态）** 为核心抽象的本地 AI Runtime，当前运行在 Apple Silicon macOS 上，并通过 OpenAI-compatible API 对外提供模型推理服务。

项目的研究重点已经从“把模型推理跑起来”发展为：

> **将执行身份、连续性与生命周期，与模型表示、物理驻留以及具体 Backend 的实现方式分离。**

```text
Execution State       ≠ KV Cache
Execution State       ≠ Residency State
Execution Continuity  ≠ Computation Semantics
SimiGo Runtime        ≠ Backend
```

**当前阶段：Experimental Beta / Research Preview。**

已经完成真实设备、真实模型和 Runtime 故障矩阵验证，但目前不宣称为生产级通用推理 Runtime，也不宣称已经完成 Backend-independent Runtime。

## 1. 当前状态

| 项目 | 当前状态 |
|---|---|
| Version | `v2.0.0-beta` |
| Stage | Experimental Beta / Research Preview |
| Platform | Apple Silicon macOS |
| Primary execution substrate | MLX / `mlx-swift-lm` |
| API | OpenAI-compatible |
| Oversized model validation | Qwen3-Coder-Next-4bit |
| Oversized validation machine | 32 GiB Apple Silicon |

当前公开证据已经覆盖：

- Execution State 生命周期与连续性
- Fork / Restore / Reattach / Discard
- Oversized Model 执行
- Segment-level physical residency
- Cancellation
- Runtime consistency contract
- Residency / physical-state reconciliation
- Failure Matrix 全量审计

最新 Failure Matrix 结果：

> **P1 = 0**

剩余项目已经分类为 Beta boundary、GA work item 或 product scope。

## 2. SimiGo 的核心问题

传统本地推理系统通常围绕模型加载、Prefill / Decode、KV Cache、Batch、Memory 和 Scheduler 组织 Runtime。

SimiGo 进一步研究：

```text
已经完成的模型计算
        ↓
可继续执行的状态
        ↓
这个状态能否被保存、继续、Fork、Restore、Reattach、Discard？
        ↓
它能否脱离某一种物理表示继续存在？
```

因此 SimiGo 将 **Execution State** 作为独立于物理表示的 Runtime 概念。

它至少包含：

```text
Execution State
├── identity
├── lineage
├── position
├── continuation
└── lifecycle
```

而物理系统负责：

```text
Representation State
        ↓
Residency State
        ↓
Physical MLX State
```

## 3. 核心架构

```text
HTTP / Product State
        ↕
Execution State
(ID / lineage / position / continuation / lifecycle)
        ↕
Representation State
(prefix / checkpoint / physical representation)
        ↕
Residency State
(resident groups / transfer bookkeeping / DIRTY)
        ↕
Physical MLX State
(tensors / weights / cache)
```

### Execution State

描述“这是哪个执行、从哪里继续、属于哪条 lineage、当前处于什么生命周期”。

它不是 KV Cache 的别名，也不要求永远驻留在某一种物理表示中。

### Representation State

描述 Execution State 当前由什么物理表示承载，例如 prefix、checkpoint、segmented representation，以及未来可能出现的其他 Backend-specific representation。

### Residency State

描述表示当前哪些部分实际驻留，以及加载、释放、eviction 和 reconciliation 的状态。

### Physical MLX State

是当前 MLX Backend 的具体物理实现，包括 tensor、weight、cache 等。

## 4. Execution State 生命周期

```text
create
  ↓
attach
  ↓
continue
  ├──────────────→ fork → child → continue
  ├──────────────→ restore → reattach → continue
  └──────────────→ discard
```

表示可以发生变化：

```text
Representation A
      ↓
evict / release
      ↓
logical Execution State remains
      ↓
reattach / materialize
      ↓
Representation B
      ↓
continue
```

> **释放物理驻留不等于删除 Execution State。**

## 5. Oversized Execution State：已验证

SimiGo 已在真实 Apple Silicon 设备上验证 **Qwen3-Coder-Next-4bit**：模型约 41.76 GiB，在 32 GiB 物理内存环境下进行 Execution State × Oversized Model 验证。

验证覆盖：

- Parent identity stable
- Child lineage traceable
- Fork divergence
- Restore to fork point
- Segment eviction / restore 后继续执行
- Parent non-interference
- Zero swap
- 多次 segment materialize / release transition

在测试范围内，完整 segment eviction 后，逻辑 Execution State 仍可恢复，并通过按需重新物化继续执行。

详细结果：`docs/knowledge/findings/O6_OVERSIZED_EXECUTION_STATE_20260926.md`

## 6. Runtime 一致性

SimiGo 已形成并实现 D1 Runtime Consistency Contract。

一次 Runtime turn 的逻辑 commit boundary 是：

```text
Representation Binding
        +
Execution Position Advance
```

取消采用阶段边界观察语义：

```text
cancel observed before commit
        → ABORT

cancel observed during / after commit
        → COMMIT
```

ABORT 不改变已提交的 position / representation；COMMIT 后即使客户端取消，也不会把已经提交的 Runtime 状态伪装成未提交。

Residency 与 Physical MLX 则通过 reconciliation 进行观察。D1 不宣称 MLX 或进程级 ACID，也不引入 WAL、分布式事务或全局事务协调器。

详细定义：`docs/knowledge/invariants/RUNTIME_CONSISTENCY_CONTRACT_D1_PUBLIC_20260927.md`

## 7. Residency 与资源治理

SimiGo 将 Residency 与 Execution State 分开。

当前 Runtime 可以：

- admit physical resources
- materialize representation
- release / evict physical residency
- reattach logical state
- reconcile bookkeeping 与物理观察
- 在压力下释放非核心驻留

Floor 是 Residency policy，而不是 Execution State。

```text
Floor ≠ Execution State
Floor ≠ Physical observation
```

当前 beta 的 floor 配置为 0。正式语义为 **TARGET-DEPENDENT**：floor 并不是结构性的“永不释放”；target=0 仍意味着清理全部非 core residency。

详细定义：`docs/knowledge/invariants/GA0_FLOOR_POLICY_20260927.md`

## 8. Failure Matrix

SimiGo 对 Runtime 操作进行跨状态层故障审计。

覆盖操作包括：

`create / attach / continue / fork / restore / reattach / discard / bindRepresentation / releaseRepresentation / materialize / evict / generate / newSession / HTTP request`

每项分别检查：

`success / physical failure / cancellation / mid-exception / repeat / concurrency`

并观察五层状态：

```text
Execution State
Representation State
Residency State
Physical MLX State
HTTP / Product State
```

最终结果：

> **FAILURE_MATRIX_COMPLETE / P1_ZERO**

详细结果：`docs/knowledge/findings/FAILURE_MATRIX_FINAL_20260926.md`

## 9. Product / API 能力

SimiGo 当前仍提供完整的本地模型服务能力，包括：

- OpenAI-compatible API
- Streaming / non-streaming generation
- Session / Branch 逻辑隔离
- 请求取消
- Tool Call 解析与转交
- Tool Governance
- Model Capability Contract
- Physical KV / Prefix Reuse
- Resource admission / eviction
- Runtime lifecycle
- Observability

SimiGo 不执行 Agent Tool，也不负责 Agent 的规划、决策、Memory 或编排。

## 10. Backend 边界

MLX 是 SimiGo 当前主要的具体执行 Backend / substrate，但 **MLX 不是 SimiGo 的定义**。

长期需要验证的问题是：当模型、物理表示和 Backend 改变后，Execution State 的 identity、lineage、position、continuation 和 lifecycle 是否仍然成立。

目前 Backend Conformance 仍属于后续验证工作，因此 SimiGo **不宣称已经完成 Backend-independent Runtime**。

## 11. 文档体系

公开文档已经从单纯的产品说明扩展为研究证据链：

```text
Research Story
      ↓
Execution State architecture
      ↓
Runtime consistency
      ↓
Oversized execution evidence
      ↓
Failure Matrix
      ↓
Residency policy
```

| 文档 | 定位 |
|---|---|
| `README.md` | 项目入口、当前状态、能力与研究方向 |
| `README_base.md` | 核心架构白皮书 |
| `docs/research/` | 研究故事与长期问题演进 |
| `docs/knowledge/findings/` | 已验证的研究 / 工程结果 |
| `docs/knowledge/invariants/` | 已形成稳定边界的不变量与契约 |
| `docs/decisions/` | 架构决策 |
| `docs/lessons/` | 工程经验与故障分析 |
| `docs/experiments/` | 尚未进入核心架构的实验 |
| `docs/benchmarks/` | 可重复的实机测量与性能数据 |
| `部署指南.md` | 本地与局域网部署 |

`README.md` 回答：**SimiGo 现在是什么、已经证明了什么、当前边界在哪里、下一步研究什么。**

`README_base.md` 回答：**哪些架构原则应该长期保持不变。**

## 12. 当前研究路线

```text
Runtime / Residency / E2E
        ↓
Execution State
        ↓
Failure Matrix
        ↓
Runtime Consistency
        ↓
Oversized Execution
        ↓
GA-0 Floor Formalization
        ↓
Token Ledger
        ↓
UI Branch / Backend Conformance
```

### 已完成

- Execution State 基础生命周期
- Oversized Execution State 验证
- D1 Runtime Consistency
- Cancellation
- INV-3 reconciliation
- Failure Matrix
- GA-0 Floor policy formalization

### 当前工作

- Token Ledger 的进一步实现与回归验证

### 后续方向

- UI Branch sessions
- Coordinator standalone concurrency
- MLX internal fault boundary
- Backend Conformance
- 更广泛的模型 / workload 验证

这些方向都需要通过实际证据逐步收敛，不会因为进入路线图就自动成为 Core Architecture。

## 13. SimiGo 不是什么

SimiGo 当前不定位为：

- vLLM 的替代品
- 通用生产级 inference server
- Agent Framework
- Agent Memory
- Tool Executor
- 单纯的 KV Cache Manager
- 只负责启动外部推理进程的 Process Wrapper

更准确的定位是：

> **一个以 Execution State 为核心抽象、正在通过真实模型、真实设备和故障矩阵持续验证的实验性 Runtime。**

## 14. Long-term thesis

> **如果 Execution State 的身份、连续性和生命周期可以独立于其物理表示，那么 Runtime 就可以围绕“可继续执行的状态”而不是某一种具体缓存结构进行组织。**

当前证据已经支持这一方向的多个关键组成部分，但更广泛的 Backend、模型和 workload 泛化仍需要继续验证。

因此，SimiGo 的长期目标不是不断增加 Runtime 中的特殊对象，而是：

```text
更清晰的状态边界
        ↓
更少的隐式耦合
        ↓
更可验证的 Runtime semantics
        ↓
更广泛的 Backend / Model conformance
```

## License

See the repository license file for the current licensing terms.