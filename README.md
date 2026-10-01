# SimiGo

> **An Execution-State-Centered Runtime for Long-Lived Model Execution**

SimiGo 是一个以 **Execution State（执行状态）** 为核心抽象的本地 AI Runtime，当前运行在 Apple Silicon macOS 上，并通过 OpenAI-compatible API 对外提供模型推理服务。

项目的研究重点已经从“把模型推理跑起来”发展为：

> **将执行身份、连续性与生命周期，与模型表示、物理驻留以及具体 Backend 的实现方式分离。**

## 核心能力

- 基于 MLX / `mlx-swift-lm` 执行本地模型推理
- 提供 OpenAI-compatible API（Chat Completions / Text Completions / Responses）
- 支持流式与非流式生成
- 支持请求取消，以及 generation / suspend / resume 之间的生命周期一致性
- 支持多 Session / 多 Branch 的逻辑隔离
- 支持 Physical KV 与跨会话 Prefix Reuse
- 支持资源准入、物理表示 retention / eviction 与运行状态观测
- 支持官方 Tool Calling，并将 Tool Call 转交外部 Agent
- 支持 Tool Governance：工具调用生命周期治理与结构化拒绝分类
- 支持 Model Capability Contract：运行时明确声明模型能力与运行约束

## Download — v2.1.0 Execution State Reference App

当前公开 DMG：

```text
https://github.com/slamfinger/SimiGo/releases/tag/v2.1.0
```

| Asset | Requirement | Checksum |
|---|---|---|
| `SimiGo-v2.1.0.dmg` | Apple Silicon macOS 26.4+ | 见 Release 页面 |

该 DMG 使用 **ad-hoc signature**，未做 notarization。首次打开若被 Gatekeeper
拦截，请先校验 Release 页面 SHA-256，再移除 quarantine 属性：

```bash
xattr -dr com.apple.quarantine SimiGo.app
```

不要绕过校验直接运行来源不明的副本。

## v2.1.0 — Execution State Reference App

v2.1.0 是 Frozen Execution State Contract 的第一个产品形态 reference
implementation。菜单栏新增 **Execution State Graph** 窗口，把 State 本身作为
一等操作对象：

```text
create → continue → save → fork → continue → save → restore → continue
                                              ↘ discard / release
```

当前 reference app 已实现：

- State Graph UI：用户操作 `ExecutionState`，不是传统 Chat transcript。
- 七操作 lifecycle：`create / continue / save / fork / restore / discard / release`。
- Durable checkpoint：checkpoint 将当前 semantic closure 固化为 durable
  representation；save 不产生新的 semantic state。
- Fail-closed restore：identity、model、anchor、checksum 全部通过才返回
  restored；失败不返回半状态。
- Fork isolation：child 在 fork point value-copy parent closure，parent 不被污染。
- Discard / release 语义：discard 原子移除 checkpoint，禁止 ghost continuation；
  release 只清空 durable binding，不废除 logical state。
- Representation boundary：主 UI 只显示 `Representation: Reference`；MLX、KV、
  prefix 等 carrier 细节只出现在 Representation Declaration diagnostics。

当前 State Graph 功能使用 `R_Reference_v1` 做 contract-shaped reference
carrier，**不宣称** MLX 或 llama.cpp conformance，也不宣称 backend-independent
Execution State。同一 App 仍保留 v2.0 的 MLX Runtime 能力，但 v2.1 的核心边界
是：backend 不再进入 Execution State 产品的顶层概念。

架构映射见
[docs/V2.1_REFERENCE_APP_ARCHITECTURE.md](docs/V2.1_REFERENCE_APP_ARCHITECTURE.md)。

## v2.0 能力：超规模模型执行 + 跨会话前缀共享

main 主线自 v2.0.0-beta.3 起内置两项 Execution State 能力（v1.7 全部
功能不变）：

- **超规模模型执行**：超过物理内存的大模型（已验证 Qwen3-Coder-Next-4bit，
  41.76 GiB @ 32 GiB 机器）经同一 OpenAI 兼容 API 正常服务——
  placeholder-first 分段加载、persistent-floor 段驻留、严格 Execution
  State 会话，swap 平坦、逐位确定性。
- **跨会话前缀 KV 共享（Execution State 前缀池）**：新会话若与既有会话
  共享对话前缀（agent 重启/重连/换 session 续聊/同文档新会话），直接
  消费已算过的 KV 快照，只付增量——真机实测对话续接池命中轮 TTFT
  201ms 对比冷轮 16,951ms（84 倍）；token 级共享下同文档新会话
  11,620ms → 5,944ms（文档 84% 从池播种）。重启后同样 warm。
  `SIMIGO_PREFIX_POOL=0` 可一键关闭。
  Prefix Pool 同时受逻辑容量与物理磁盘容量约束；当前 Beta 默认分别为
  200,000 message elements 与 16 GiB，并通过既有 LRU 生命周期回收超出
  预算的物理快照。
  **术语约定**：当前 Branch API 是「分支 checkpoint fork」（checkpoint
  复制语义）；「Execution State 共享前缀 fork」（fork point 处共享
  Representation）尚未实现，为登记的 GA 方向。

详见 [docs/RELEASE_v2.0.0-beta.md](docs/RELEASE_v2.0.0-beta.md)；
从源码构建需与
[SimiGo-Lab](https://github.com/slamfinger/SimiGo-Lab) 双仓兄弟克隆，
步骤见 [部署指南.md](部署指南.md) 第六节。

## 开源边界

SimiGo 采用 **Open Research / Open Core / Bounded Product** 结构：

- Execution State Contract、研究文档与证据记录采用 **CC-BY-4.0**。
- Runtime、conformance suite 与 v2.1 Execution State reference app 采用
  **Apache-2.0**，允许研究、复现、fork、商业集成和独立实现。
- 本仓库不发布模型权重；模型永远是独立的外部授权资产。
- Hosted、Enterprise、管理面、商业支持与专有集成不在本许可证授权范围内。
- `SimiGo` 名称与官方品牌不随源码许可证授予；fork 不得暗示官方身份。见
  [TRADEMARKS.md](TRADEMARKS.md)、[OPEN_SOURCE.md](OPEN_SOURCE.md)、
  [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 与 [NOTICE](NOTICE)。

## Runtime 三层契约

SimiGo 的核心不是一个 API 转发层，而是一个可靠的 Agent Runtime。
三层契约共同构成 Runtime 的能力边界：

```text
Execution State       ≠ KV Cache
Execution State       ≠ Residency State
Execution Continuity  ≠ Computation Semantics
SimiGo Runtime        ≠ Backend
```

**当前阶段：v2.1.0 Reference App / Research Preview，不是 GA。**

已经完成真实设备、真实模型和 Runtime 故障矩阵验证，但目前不宣称为生产级通用推理 Runtime，也不宣称已经完成 Backend-independent Runtime。

## 1. 当前状态

| 项目 | 当前状态 |
|---|---|
| Version | `v2.1.0` (build 10, tag `v2.1.0`) |
| Stage | Execution State Reference App / Research Preview |
| Platform | Apple Silicon macOS |
| Minimum macOS | 26.4 |
| Primary execution substrate | MLX / `mlx-swift-lm` |
| Reference carrier | `R_Reference_v1` |
| API | OpenAI-compatible |
| Oversized model validation | Qwen3-Coder-Next-4bit |
| Oversized validation machine | 32 GiB Apple Silicon |

当前公开证据已经覆盖：

- Execution State 生命周期与连续性
- Fork / Restore / Reattach / Discard / Release
- Save / checkpoint 与 fail-closed restore（v2.1 reference app）
- Oversized Model 执行
- Segment-level physical residency
- Cancellation
- Runtime consistency contract
- Residency / physical-state reconciliation
- Durable Execution State checkpoint integrity
- Cross-session Prefix Reuse 与物理 retention
- Release suspend / resume lifecycle consistency
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
continue
  ├──────→ fork → child → continue → save → restore → continue
  ├──────→ save / checkpoint → durable representation
  └──────→ discard / release
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

Beta release 还验证了 generation 与 suspend / resume 之间的生命周期一致性。
Runtime 在 request admission 阶段建立 generation ownership，使 idle suspend
不会卸载仍处于准入但尚未注册为 active task 的执行请求。

## 7. Residency 与资源治理

SimiGo 将 Residency 与 Execution State 分开。

当前 Runtime 可以：

- admit physical resources
- materialize representation
- release / evict physical residency
- reattach logical state
- reconcile bookkeeping 与物理观察
- 在压力下释放非核心驻留

对于需要持久化的 Physical Representation，Beta Runtime 同时提供
ownership-aware retention policy：

- active Execution State 对应的 checkpoint 不参与自动淘汰；
- 不完整或无法配对的 checkpoint artifact 视为 orphan 并回收；
- 非 active checkpoint 在物理预算超限时按保存时间进行 LRU 回收；
- Prefix Pool 在既有逻辑容量之外增加物理字节预算。

当前 Beta 默认物理预算为：

```text
branch checkpoints : 64 GiB
prefix pool        : 16 GiB
```

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
| `docs/history/CORE_ARCHITECTURE_BASELINE_V5_20260912.md` | 历史 v5 架构白皮书，已 superseded |
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

当前 SimiGo 已完成 Execution State 基础语义、Runtime 一致性、物理表示治理、
真实设备验证、Contract formalization 与 **Abstraction Freeze**；v2.1.0 开始
进入 Frozen Contract 的产品形态 reference implementation 阶段。

```text
Execution State
        ↓
Lifecycle consistency
        ↓
Representation / Residency separation
        ↓
Runtime consistency
        ↓
Oversized Execution
        ↓
Persistence / Prefix Reuse
        ↓
Backend / Model Conformance
```

### 已完成

- Execution State 基础生命周期
- Oversized Execution State 验证
- D1 Runtime Consistency
- Cancellation
- INV-3 reconciliation
- Failure Matrix
- GA-0 Floor policy formalization
- Token Ledger
- Durable checkpoint integrity
- Generation / save / load / delete lifecycle race validation
- Ownership-aware checkpoint retention
- Prefix Pool physical-byte budget
- Release suspend / resume lifecycle validation
- Execution State Contract v1.0-amended freeze
- MLX / llama.cpp cross-backend continuation evidence（bounded claim）
- v2.1 Reference App：seven-operation lifecycle / State Graph / durable checkpoint

### 当前工作

- v2.1.0 reference app 收敛与 public release hygiene
- Contract conformance / Representation Declaration 工程化
- 后续 backend adapter 与 conformance battery 生态

### 后续方向

- Coordinator standalone concurrency
- Backend Conformance
- External Representation Declarations
- State Graph persistence / conflict semantics
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

> **一个以 Execution State 为核心抽象，并通过真实模型、真实设备、故障矩阵与 Frozen Contract conformance 持续验证的 Runtime。**

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

SimiGo 使用分层许可：源码与可执行参考材料为 **Apache-2.0**；研究文档、Contract
与实验证据为 **CC-BY-4.0**；`SimiGo` 名称与官方品牌不随源码许可授予。模型权重
不随本仓库或 DMG 分发。

详见 [LICENSE](LICENSE)、[LICENSE-DOCS](LICENSE-DOCS)、[NOTICE](NOTICE)、
[OPEN_SOURCE.md](OPEN_SOURCE.md)、[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
与 [TRADEMARKS.md](TRADEMARKS.md)。
