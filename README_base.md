# SimiGo 核心架构白皮书

> **本地 AI 推理 Runtime + 本地/局域网共享推理节点**

SimiGo 运行在 Apple Silicon macOS 上，对外提供 OpenAI-compatible API，底层基于 MLX / `mlx-swift-lm` 执行模型推理。

本文档是 SimiGo 的**唯一核心架构参考**。它只定义长期稳定、跨实现仍成立的架构原则，不把某一次故障、某个版本的参数或某个临时解决方案升级为永久规则。

**当前架构基线：v5.0 Core Architecture Baseline（2026-09-12，随官方 ChatSession 迁移收敛）。**

核心依赖：[mlx-swift](https://github.com/ml-explore/mlx-swift) 0.31.6 · [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) `main` 分支（钉定 `238ad74`，含官方 PromptCacheReusePolicy token 账本与 `cacheStatus()` 遥测）。

---

# 一、架构定位

## 1.1 一句话定义

> **SimiGo 是基于 MLXLMCommon 的本地 Inference Runtime；保持官方推理语义不变，只负责请求规范化、模型执行、Physical KV 复用、资源治理、并发隔离、取消、生命周期收敛和可观测性，并通过 OpenAI-compatible API 向外提供服务。**

核心原则只有一句：

> **保持官方推理协议语义不变。**

## 1.2 SimiGo 负责

```text
协议接入与规范化
        ↓
统一生成请求
        ↓
模型推理执行
        ↓
Physical KV 与前缀复用
        ↓
资源治理
        ↓
取消与生命周期管理
        ↓
运行观测
```

## 1.3 SimiGo 不负责

```text
Agent 规划
Agent 决策
Agent Memory
Tool 实际执行
Shell / SSH / Skill / Plugin 执行
Agent 编排
```

模型产生的 Tool Call 属于**模型输出**。SimiGo 可以依据官方推理结果进行规范化和转交，但不执行 Tool，也不拥有 Agent 状态。

---

# 二、核心架构模型

SimiGo 不再把“Agent、Scheduler、Batch、Tool Parser、KV、Lifecycle”全部视为同等级核心对象。

真正稳定的核心只有七个领域：

```text
┌────────────────────────────────────────────┐
│ 1. Protocol                                │
│    API 接入、请求规范化、响应输出            │
├────────────────────────────────────────────┤
│ 2. Context                                 │
│    Session / Branch / Request               │
├────────────────────────────────────────────┤
│ 3. MLX Execution                           │
│    Prefill / Decode / Cancellation          │
├────────────────────────────────────────────┤
│ 4. Physical KV                             │
│    Token Ledger / Prefix Reuse / Residency  │
├────────────────────────────────────────────┤
│ 5. Resource                                │
│    Admission / Memory / Eviction            │
├────────────────────────────────────────────┤
│ 6. Lifecycle                               │
│    Start / Cancel / Complete / Release      │
├────────────────────────────────────────────┤
│ 7. Observability                           │
│    Trace / Metrics / Failure Evidence       │
└────────────────────────────────────────────┘
```

Scheduler、Batch、长上下文策略、缓存数量、内存阈值等属于**实现机制或实验能力**，不得反过来定义核心架构身份。

## 2.1 数据流

```text
External Agent
      ↓
OpenAI-compatible API
      ↓
Protocol
      ↓
Canonical Generation Request
      ↓
Context
      ↓
Resource Admission
      ↓
MLX Execution
      ├── Prefill
      └── Decode
      ↓
Generation Result
      ↓
Stream / Tool Call / Final Response
```

Physical KV 横跨执行过程，但不成为 Context 的业务身份：

```text
Context
   │
   ├──────────────→ MLX Execution
   │                       │
   │                       ↓
   └──────────────→ Physical KV
                           │
                           ↓
                    Resource Governance
```

---

# 三、Context：逻辑上下文

## 3.1 逻辑关系

```text
Session
  └── Logical Branch
        └── Request
```

`Agent` 可以作为外部调用方身份或协议元数据存在，但不是 Physical KV 的拥有者，也不是推理核心必须采用的唯一身份模型。

## 3.2 Logical Isolation

不同逻辑上下文必须相互隔离：

```text
Session A ≠ Session B
Branch A  ≠ Branch B
Request A ≠ Request B
```

逻辑隔离并不意味着物理计算必须隔离。

```text
Session A ─┐
Session B ─┼→ Physical KV Pool
Session C ─┘
              ↓
        精确 Token 前缀匹配
```

已经完成且语义兼容的物理计算可以跨 Session 复用。

## 3.3 状态分离

至少保持以下状态边界：

```text
Logical Context State
        ≠
Execution State
        ≠
Physical KV State
        ≠
Resource State
        ≠
Protocol / Stream State
```

某次 Generation 的临时变量、解析状态或流式状态，不得因为实现方便而成为 Session 或 Physical KV 的持久状态。

---

# 四、Canonical Generation Request

不同 API 可以有不同输入表达，但进入推理核心后必须收敛为统一的生成请求语义：

```text
HTTP / OpenAI API
        ↓
Protocol Normalization
        ↓
Canonical Generation Request
        ↓
MLXLMCommon
```

协议层的 `responseId`、`previous_response_id`、HTTP 请求编号等信息不能直接决定 Physical KV 是否可复用。

Physical KV 的复用依据是**模型计算语义与实际 Token 序列**，而不是协议对象名称。

---

# 五、MLX Execution：官方推理优先

## 5.1 官方能力是事实来源

SimiGo 底层已经依赖 `mlx-swift-lm / MLXLMCommon`。

因此能力处理顺序必须是：

```text
官方能力已经存在
        ↓
直接使用

官方存在缺口
        ↓
确认是上游缺口还是上游 Bug
        ↓
最小必要适配
```

禁止因为一次模型兼容问题，就在 SimiGo 内建立一套与官方协议平行的完整实现。

### 5.1.1 当前落地形态（2026-09-12）

上述原则已完整落地，具体契约如下：

```text
mlx-swift-lm main（238ad74）
      ↓
ChatSession 拥有 conversation / KV / token 账本
（PromptCacheReusePolicy：appendSuffix / trimToCommonPrefix / rebuild）
      ↓
SimiGo 每轮只传增量消息（官方契约：传入消息会追加进内部
conversation，传全量会造成重复），会话连续性由
AgentExecutionKey.storageKey 分桶 + 语义签名
（role + content + 工具存在性）判定
```

KV 前缀调和（含 tool 轮生成流与模板重渲染的差异）全部由官方账本承担；
SimiGo 通过官方遥测观测命中：`cacheEfficiency` / `cachedPromptTokenCount` / `cacheStatus()`。

实测锚点（Nail-Qwen3.6-35B-A3B，2026-09-12）：首轮全量 prefill 16290 token ≈ 67s；
warm 轮 `promptTokens=16~472`、`cacheEff=0.97~1.00`、TTFT 0.8~2.7s，
tool 轮不再断开复用。

## 5.2 Tool Calling

官方 `Generation.toolCall` 是 Tool Call 的核心来源：

```text
MLXLMCommon
      ↓
Generation.toolCall
      ↓
规范化
      ↓
onToolCall
      ↓
External Agent / Tool Executor
```

SimiGo 不执行 Tool。

官方 main 已同时提供解析失败的显式信号：`Generation.rejectedToolCall` 携带拒绝原因，
SimiGo 只做留痕（reason / toolName），不重新解释 raw 输出、不猜测 Tool Call。

**协议边界规范化**：OpenAI wire format 的 `function.arguments` 是字符串化 JSON，
官方 `ToolCall` 按对象解码——回灌 assistant 消息时必须在边界先规范化，
否则客户端回显会静默丢失 tool_calls，导致会话连续性误判与 KV 复用断裂（2026-09-12 修复）。

历史存在的 `RawToolCallStreamParser / ToolCallTemplates` 已删除：上游解析与
`rejectedToolCall` 已完整覆盖目标模型，按本节原则移除后备机制。
`StreamTokenFilter` 现在是纯表现层（thinking 标签清理），不参与 Tool 协议。

## 5.3 边界验证

Runtime 只做必要验证：

```text
官方结果能否安全转换
        ↓
必要字段是否存在
        ↓
是否能够安全转交
```

缺失信息不得由 SimiGo 猜测填充。

---

# 六、Physical KV：已完成计算的复用结果

## 6.1 定义

> **Physical KV 是已经完成的模型计算结果，不是 Conversation Memory、Session Store 或 Agent Memory。**

**所有权（2026-09-12 起）**：Physical Token Ledger、前缀精确匹配、trim/rebuild 决策
由官方 `ChatSession` 实现（KVCacheStorage + Conversation 账本 + PromptCacheReusePolicy）；
SimiGo 不再维护自研 Revision 池、自研准入账本或平行的 Token Ledger。
本节其余文字是这些机制必须满足的语义契约，无论实现归属谁。

## 6.2 复用条件

候选 Physical KV 必须同时满足：

```text
同一模型计算语义
        +
兼容的语义元数据
        +
Physical KV 可使用或可重建
        +
实际 Token ID 前缀精确匹配
```

最终的前缀匹配必须基于真实 Token ID Sequence。

以下信息都不能单独决定复用：

```text
SessionId
RequestId
ResponseId
Message Count
字符串前缀
Agent Name
Tool Name
```

## 6.3 Physical Token Ledger

Physical Token Ledger 是 Physical KV 的物理事实来源：

```text
实际输入 Token
      +
实际生成 Token
      ↓
Physical Token Sequence
      ↔
Physical KV
```

新的 Revision 只能建立在已经真实生成并提交的 Token 上。

未完成、已取消或失败的生成不得伪装成完整 Revision。

## 6.4 Prefill

标准执行路径：

```text
Prompt
  ↓
Tokenize
  ↓
KV Candidate Search
  ↓
Exact Token Prefix Match
  ↓
Resource Admission
  ├── Cold Prefill
  └── Delta Prefill
  ↓
Decode
  ↓
Commit Physical KV Revision
```

具体分块大小、是否进行末 Token 重算、缓存对象如何保存，属于实现策略，不属于核心架构。

## 6.5 淘汰

核心原则：

```text
释放 Physical Residency
        ≠
删除有效的 Logical Record
```

资源不足时可以释放物理驻留；如果逻辑记录仍然有效，就必须保留足以判断 Token 事实和重建可能性的元数据。

## 6.6 Tool Fingerprint

Tool Fingerprint 的正确定位是：

```text
Tool Schema
    ↓
Canonical Representation
    ↓
Fingerprint
    ↓
KV Semantic Compatibility Filter
```

它是 Physical KV 的**语义兼容元数据**，不是 Tool Runtime。

---

# 七、Resource：资源治理

资源治理的职责是：**在可能发生大规模物理分配之前判断是否安全。**

当前实现（2026-09-12）：分配边界委托官方 MLX 内存治理——
`Memory.memoryLimit = 22 GiB`、`Memory.cacheLimit = 4 GiB`（`Lifecycle/RuntimeTuning.swift`），
外加 Responses 协议状态的存储保留上限（64 条 / 1800s）。
v4.5 的自研预测式准入账本已随自研 KV 栈退役；本节概念模型保留为演进原则，
若长上下文页出现象复现，Admission 权重预算（v4.5 已验证）是首选恢复项。

概念模型：

```text
Projected Memory
 = Resident KV
 + Projected KV Delta
 + Execution Working Set
 + Safety Margin
```

这里的具体数字不是架构规则。

例如：

```text
Memory Limit
Cache Limit
Revision Limit
Long Context Threshold
Prefill Chunk Size
```

都属于 Runtime Tuning，应通过实机数据调整。

系统 RSS、Virtual Memory、Swap 是观察指标，不等于 Physical KV 大小：

```text
RSS  ≠ KV Size
Swap ≠ KV Size
```

---

# 八、Execution：并发与执行机制

## 8.1 Gate

同一逻辑执行上下文的状态修改必须遵守并发契约。

当前实现为两层：

```text
RuntimeLifecycleGate   start/stop 生命周期全局互斥（Runtime N 与 N+1 不重叠）
SessionGenerationGate  同一 AgentExecutionKey 内生成严格串行
                       （官方 ChatSession 非线程安全，这是互斥的必要条件，非第二套 KV Runtime）
```

但这不意味着整个模型计算必须全局串行：

```text
Logical Branch 串行
        ≠
Model Compute 全局串行
```

## 8.2 Scheduler

Scheduler 是实现机制。

可以存在：

```text
Runnable Queue
Prefill Scheduling
Decode Scheduling
Arbitration
Batch Formation
Decode Quantum
```

但以下内容都不是永久架构规则：

```text
FIFO
固定时间片
固定 Batch Size
固定 Chunk Size
固定公平算法
```

它们必须由测试和 Benchmark 证明价值。

## 8.3 Batch

Batch 只属于 Execution：

```text
Request A ─┐
Request B ─┼→ Model Forward
Request C ─┘
```

Batch 不拥有：

```text
Session
Branch
Agent
Tool
Lifecycle
```

未来任何 Batch 能力都必须首先证明：

```text
逻辑状态不污染
KV 行彼此独立
取消不会误伤其他请求
Token 对账正确
生命周期能够独立结束
```

因此 Batch 可以继续演进，但不进入当前 Core Identity。

---

# 九、Lifecycle：生命周期收敛

生命周期的核心不是规定大量状态名称，而是保证**最终一定收敛**。

抽象过程：

```text
Created
   ↓
Running
   ↓
Completed / Failed / Cancelled
   ↓
Releasing
   ↓
Released
```

核心要求：

1. 终止请求不得继续产生新的有效执行结果；
2. 资源最终必须释放或回收到合法状态；
3. 已结束请求不得重新复活；
4. 取消与失败都必须能够安全收敛；
5. 清理过程不能破坏其他逻辑上下文。

具体状态枚举、Trace 字段和辅助函数属于实现层。

当前实现（`Lifecycle/RuntimeLifecycle.swift`）：`RuntimeLifecycleCoordinator` 被动账本 +
合法迁移表 + `finish()` 统一终止入口（成功与取消两条链全部收敛到 RELEASED，重复 finish 幂等）。
迁移表包含 `CREATED → COMPLETING`：SSE 直发收口后协议层不再执行 QUEUED/RUNNING 迁移，
请求从 CREATED 直接进入完成路径（2026-09-12 修复：缺此边时每次正常完成都触发
`FORCE_RELEASED reason=unexpected table rejection`）。Trace 为紧凑格式
（`[LC] <EVENT> r=… s=…`），异常迁移（FORCE_RELEASED）与取消路径完整留痕。

---

# 十、Observability：证据优先

可观测性不是业务状态的替代品，而是判断 Runtime 是否正确的证据系统。

至少需要能够回答：

```text
请求何时进入 Runtime？
请求为什么等待？
使用了多少 Prefill？
复用了多少 Physical KV？
生成了多少 Token？
为什么取消？
为什么失败？
资源为什么拒绝？
何时释放？
```

Trace、Metrics、Benchmark 和 Failure Evidence 应进入独立工程文档，而不是不断增加 Core Invariant。

当前证据形态（`~/.simigo/logs/native_mlx_trace.log`，紧凑格式）：

```text
[CFG] / [NODE] / [READY]        启动：配置来源与关键参数、后端与绑定地址、就绪
[LC]                            REGISTER / RELEASED(reason) / FORCE_RELEASED（异常迁移信号）
[MLX]                           session messages history delta reuse ttft
                                cacheTokens cacheHitTokens cacheEff promptTokens promptTime tps
[prefixMismatch]                会话连续性失配定位（index / role / toolFlag / 两侧消息数）
```

其中 `cacheEff` / `cacheHitTokens` / `promptTokens` 直接来自官方
`GenerateCompletionInfo` 与 `cacheStatus()`——复用命中是官方账本的事实输出，
不是 SimiGo 的自我推断。实测样本（2026-09-12）：
`reuse=true ttft=2015ms cacheTokens=16299 cacheHitTokens=16299 cacheEff=1.00 promptTokens=17`。

---

# 十一、十二条核心不变量

这些才是当前真正意义上的“铁律”。

### 1. 推理边界

SimiGo 是 Inference Runtime，不是 Agent Runtime。

### 2. 官方协议优先

官方 `MLXLMCommon` 已提供的推理能力必须优先直接使用；本地不得无理由重建平行协议。

### 3. 逻辑隔离

不同 Session、Branch、Request 的逻辑状态必须独立。

### 4. 物理复用基于计算结果

Physical KV 可以跨逻辑上下文复用，但只能依据实际计算语义与 Token 前缀判断。

### 5. Token 是物理事实

Physical Token Ledger 必须与实际已经生成并提交的 Token 保持一致。

### 6. 语义兼容先于复用

Physical KV 只有在模型、输入语义及必要兼容元数据满足条件时才允许复用。

### 7. 状态必须分离

逻辑、执行、Physical KV、资源、协议状态不得互相冒充所有权。

### 8. 资源必须有边界

可能产生大规模物理分配的操作必须受到资源准入约束。

### 9. 淘汰不能制造事实错误

释放物理驻留不能篡改仍然有效的逻辑记录和 Token 事实。

### 10. 取消必须安全

取消必须阻止后续无效提交，并且不能破坏其他请求或上下文。

### 11. 生命周期必须收敛

请求无论完成、失败还是取消，都必须最终进入可释放、不可复活的终态。

### 12. 核心设计必须有证据

一个实现经验只有在经过测试、实机验证和长期证明，并且确实属于架构正确性的必要条件时，才可以升级为 Core Invariant。

---

# 十二、什么不属于白皮书

以下内容默认不进入 Core Architecture：

```text
某次 Bug 的修复方式
某个模型的特殊兼容代码
某个版本的内存阈值
某个版本的 Batch Size
某个 Parser 的具体状态机
某个 Scheduler 的具体算法
某个 Trace 字段
某次 Benchmark 的最佳参数
某个上游版本的临时 workaround
```

这些内容必须进入：

```text
docs/lessons/
docs/decisions/
docs/experiments/
docs/benchmarks/
```

---

# 十三、架构知识的晋升路径

```text
工程问题 / 踩坑
        ↓
工程经验（Lesson）
        ↓
实验 / 测试（Experiment / Test）
        ↓
实机证据（Benchmark / Evidence）
        ↓
架构决策（ADR）
        ↓
长期必要且实现无关
        ↓
Core Invariant
```

禁止反向过程：

```text
一次 Bug
   ↓
一条铁律
   ↓
更多代码
   ↓
更多特殊情况
   ↓
更复杂的 Runtime
```

SimiGo 的长期目标是**减少核心概念，而不是不断增加核心概念。**

---

# 十四、推荐仓库文档结构

```text
README.md
README_base.md
部署指南.md

docs/
├── decisions/
│   └── README.md
├── lessons/
│   └── README.md
├── experiments/
│   └── README.md
└── benchmarks/
    └── README.md
```

职责严格分开：

| 文档 | 回答的问题 |
|---|---|
| `README.md` | SimiGo 是什么、能做什么、如何开始 |
| `README_base.md` | SimiGo 的核心架构是什么、什么不能被破坏 |
| `decisions/` | 为什么最终选择这个设计 |
| `lessons/` | 我们从哪些问题和失败中学到了什么 |
| `experiments/` | 某个尚未确定的想法是否成立 |
| `benchmarks/` | 实机测量到底得到了什么数据 |
| `部署指南.md` | 如何部署和使用 |

---

# 十五、最终架构

```text
                         External Agent
                              │
                              ▼
                    OpenAI-compatible API
                              │
                              ▼
                         ┌──────────┐
                         │ Protocol │
                         └────┬─────┘
                              │
                              ▼
                    Canonical Generation
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
          Context         Execution      Resource
              │               │               │
              │          Prefill/Decode       │
              │          Cancellation         │
              │               │               │
              └───────────────┼───────────────┘
                              ▼
                       ┌────────────┐
                       │ Physical KV│
                       └─────┬──────┘
                             │
                    Token Ledger / Reuse
                             │
                             ▼
                         MLX / MLXLMCommon
                             │
                             ▼
                       Generation Result
                             │
                ┌────────────┼────────────┐
                ▼            ▼            ▼
             Text         Tool Call     Failure
                │            │            │
                └────────────┼────────────┘
                             ▼
                         External Agent

        Lifecycle 与 Observability 横向贯穿整个 Runtime
```

最终原则：

> **SimiGo 的核心不是拥有更多机制，而是拥有更清晰的边界。**

> **官方推理负责“模型如何工作”，SimiGo 负责“Runtime 如何安全、高效、可控地运行模型”。**
