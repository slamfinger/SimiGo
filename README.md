# SimiGo

> Apple Silicon macOS 本地高性能 AI 推理 Runtime

SimiGo 是运行在 Apple Silicon macOS 上的本地 AI 推理 Runtime，同时可以作为局域网共享推理节点，对外提供 OpenAI-compatible API。

SimiGo 的定位很简单：**外部 Agent 决定做什么，SimiGo 负责把模型安全、高效、可观测地算出来。**

## 核心能力

- 基于 MLX / `mlx-swift-lm` 执行本地模型推理
- 提供 OpenAI-compatible API（Chat Completions / Text Completions / Responses）
- 支持流式与非流式生成
- 支持请求取消与生命周期安全收敛
- 支持多 Session / 多 Branch 的逻辑隔离
- 支持 Physical KV 与 Prefix Reuse
- 支持资源准入、物理缓存淘汰与运行状态观测
- 支持官方 Tool Calling，并将 Tool Call 转交外部 Agent
- 支持 Tool Governance：工具调用生命周期治理与结构化拒绝分类
- 支持 Model Capability Contract：运行时明确声明模型能力与运行约束

## Runtime 三层契约

SimiGo 的核心不是一个 API 转发层，而是一个可靠的 Agent Runtime。
三层契约共同构成 Runtime 的能力边界：

```text
             SimiGo Agent Runtime
                      │
      ┌───────────────┼───────────────┐
      ↓               ↓               ↓
 Capability      Generation       Tool Governance
   Contract         Truth          Contract
   （P1-1）         （P1-2）        （P1-3）
      │               │               │
      │            ┌──┴──┐            │
      │            ↓     ↓            │
      │        usage    cache        │
      │        ledger   reuse        │
      │                              │
      └──────────────────────────────┘
                    ↓
         可靠的本地 Agent Runtime
```

| 契约 | 保证 | 实测 |
|---|---|---|
| **Capability** | Runtime 明确知道模型能做什么、不能做什么、哪些未验证 | `/v1/models` 透出三态能力声明 |
| **Generation Truth** | usage 来自真实 token ledger，不是估算 | input/output/total/cached 与 [MLX] 逐轮吻合 |
| **Tool Governance** | 每个工具调用有完整生命周期事件链 | REQUESTED→VALIDATED→RESULT(observed) |

可靠性保证：

- **失败分类**：每次失败都有明确的 reason（`cancelled_by_client` / `cancelled_by_runtime` / `model_execution_error` / …），不再笼统 `cancelled_or_failed`
- **取消→释放强保证**：客户端断连 → 生成取消 → gate 释放 → 下一请求接棒（实测 2ms）
- **状态真实性**：排队中的请求 LC 保持 QUEUED，不虚假 RUNNING
- **KV 配置指纹**：KV 配置变更时旧缓存自动失效，全量 prefill
- **Session LRU**：超出上限自动驱逐最久未用会话，释放 KV 后 `Memory.clearCache()`

## 核心架构

```text
External Agent
      ↓
OpenAI-compatible API
      ↓
Protocol Gateway
      ↓
Canonical Generation Request
      ↓
MLXLMCommon
      ↓
Inference Runtime
 ┌────┼───────────────┐
 │    │               │
Context  Execution   Physical KV
 │       │               │
Session  Prefill/Decode  Token Ledger
Branch   Cancellation    Prefix Reuse
Request  Execution Policy Residency
 └───────┼───────────────┘
         ↓
Resource Governance + Lifecycle + Observability
```

最重要的原则是：

> **官方推理能力优先，SimiGo 负责 Runtime 能力，而不是重新实现模型协议。**

## SimiGo 不负责什么

SimiGo 不负责：

- Agent 规划与决策
- Agent Memory
- Tool 实际执行
- Shell / SSH / Skill / Plugin 执行
- Agent 编排

模型产生的 Tool Call 是推理结果。SimiGo 可以解析、规范化并转交，但不执行 Tool。

## 文档体系

| 文档 | 定位 |
|---|---|
| [`README_base.md`](README_base.md) | **架构白皮书**：定义核心架构、边界与长期不变量 |
| [`docs/decisions/`](docs/decisions/) | **架构决策**：记录为什么采用某个长期设计 |
| [`docs/lessons/`](docs/lessons/) | **工程经验**：记录踩坑、故障分析与经验，不自动升级为架构规则 |
| [`docs/experiments/`](docs/experiments/) | **实验记录**：记录尚未进入核心架构的方案与验证 |
| [`docs/benchmarks/`](docs/benchmarks/) | **性能与正确性数据**：保存可重复的实机测量结果 |
| [`部署指南.md`](部署指南.md) | **部署说明**：本地与局域网使用方式 |

## 架构演进纪律

SimiGo 不采用“发现一个问题，就增加一条铁律”的演进方式。

```text
问题 / 经验
    ↓
Lesson
    ↓
Experiment / Test
    ↓
Benchmark / Evidence
    ↓
ADR
    ↓
必要时才进入 Core Invariant
```

只有经过长期验证、并且不依赖某个具体实现的原则，才进入架构白皮书。

因此：

- **白皮书**回答“什么不能被破坏”。
- **架构决策**回答“为什么这样设计”。
- **工程经验**回答“我们踩过什么坑”。
- **实验记录**回答“这个想法是否成立”。
- **基准数据**回答“实测到底怎么样”。

## 当前基线

- 平台：macOS + Apple Silicon
- 应用：SwiftUI 菜单栏应用
- 推理基础：MLX / `mlx-swift-lm`
- API：OpenAI-compatible
- 架构白皮书：v5.0 Core Architecture Baseline

## 设计目标

SimiGo 的核心目标不是复制某个现有推理框架，而是在官方 MLX 推理能力之上，建立一个边界清晰、资源可控、逻辑隔离、可取消、可观测，并能够持续演进的本地 Inference Runtime。
