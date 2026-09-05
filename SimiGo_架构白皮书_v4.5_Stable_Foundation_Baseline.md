# SimiGo 架构白皮书

## v4.5 Stable Foundation Baseline

### Architecture Evolution Addendum

### Long-Context Resource Governance v1 + Tool Protocol Robustness v1

**项目：** SimiGo · Apple Silicon / macOS  
**架构代号：** Ponytail  
**定位：** Pure Inference Foundation + Shared Local/LAN Inference Node  
**核心能力：** OpenAI-Compatible Protocol + Logical State Isolation + Global Physical KV Reuse + Deterministic Lifecycle + Predictive Admission Control + Tool Protocol Robustness  
**状态：** 稳定架构基线

---

# 1. 基线定义

SimiGo v4.5 是长期稳定参考架构，不是过渡版本。

后续开发不以 4.6 / 4.7 等版本持续重构，而采用：

```text
v4.5 Stable Foundation
        ↓
局部能力增量
        ↓
Benchmark
        ↓
Invariant Audit
        ↓
Stress Test
        ↓
Stable Capability
```

没有必要性证明、Benchmark 或回归验证的新抽象，不进入 Core。

> **稳定性优先于理论完整性。**

本次 Multi-Agent、Long-Context 与 Tool Protocol 压力分析进一步固化以下状态：

```text
Logical State Isolation        正常
Physical KV Reuse              正常
Tool Fingerprint Safety        正常
Lifecycle / Cancellation       基本成立
Long-Context Memory Pressure   已受控于 Predictive Admission Control
Decode Execution Contention    已被压力测试观察
Tool Call Protocol Robustness  增强
```

因此后续演化定义为：

```text
v4.5 Stable Foundation
        +
局部 Execution Capability
        +
Resource Governance Capability
        +
Long-Context Capability
        +
Tool Protocol Robustness Capability
```

不改变 v4.5 Core 的逻辑身份、Physical KV 语义和生命周期不变量。

---

# 2. 产品定位与边界

SimiGo 是：

> **本地高性能 AI Inference Runtime + Local/LAN Shared Inference Node。**

基本链路：

```text
External Agent / Client
        ↓
OpenAI-Compatible API
        ↓
HTTPServer
        ↓
NativeMLX
        ↓
Local Model
```

SimiGo 负责：

```text
Protocol
Tokenization
Prefill
Decode
Physical KV
Prefix Reuse
Streaming
Cancellation
Memory Governance
Observability
Inference Execution Scheduling
Long-Context Resource Governance
Tool Call Parsing / Normalization / Streaming
```

SimiGo 不负责：

```text
Agent Planning
Agent Memory
Agent Decision
Tool Executor
Shell / SSH
Skill / Plugin Execution
```

核心边界：

> **External Agent 决定做什么，SimiGo 负责把模型算出来。**

```text
Agent Runtime ≠ Inference Runtime
```

Tool Call 的执行仍然属于 External Agent / Tool Executor。

SimiGo 只负责：

```text
Model Output
      ↓
Tool Call Parse
      ↓
Normalize
      ↓
Stream
      ↓
Deduplicate
      ↓
Audit
      ↓
External Agent
```

---

# 3. 核心架构域

## 3.1 Protocol Layer

HTTPServer 是薄协议网关，负责：

```text
HTTP
JSON
SSE
Request ID
Connection
Cancellation
Protocol Normalization
Identity Extraction
Responses State
```

不负责：

```text
Physical KV Selection
Physical KV Trim
Generation Policy
Tool Execution
Agent Decision
Inference Execution Scheduling
```

OpenAI Chat / Responses 等协议最终汇聚为 Canonical Generation Request。

---

## 3.2 Logical Identity Layer

Runtime 使用：

```text
Agent
  ↓
Session
  ↓
Logical Branch
  ↓
Request
```

定义：

| 对象 | 职责 |
|---|---|
| Agent | 外部调用方身份 |
| Session | 连续逻辑上下文 |
| Logical Branch | Session 内对话血缘 |
| Request | 一次具体生成 |

执行事务 Key：

```text
AgentExecutionKey
=
AgentId
+
SessionId
+
LogicalBranchId
```

`logicalBranchId` 是一等公民。

> **Runtime 不得从 sessionId 猜测 Branch。**

## 3.2.1 双 Key 粒度不变量（v4.5.1 审计补记）

AgentExecutionKey 派生两个粒度不同的 Key，语义差是架构不变量：

```text
storageKey = AgentId / SessionId                  → Session state 与 KV 归属粒度
gateKey    = AgentId / SessionId / LogicalBranchId → Generation 串行化粒度
```

推论：

```text
同 Session 的不同 Logical Branch 可以并发运行（gateKey 不同），
但它们共享同一份 Session state（storageKey 相同）。
```

因此约束：

1. **任何修改 `sessionCaches[storageKey]` 的代码，必须假设同 Session 的其他 branch
   正在并发读写同一结构**——Mutex 只保证数据结构不撕裂，不保证业务语义的
   branch isolation（如 DegenerationState、Tool Semantic Progress 的跨 branch 可见性）。
2. 未来引入真正的 branch 并行（Batched Decode / 多 branch 并发生成）前，
   必须先为 SessionLogicalState 定义逐字段的并发契约，否则该字段必须收敛为
   branch 私有。
3. 该不变量已由 `SimiGoTests/AgentExecutionKeyTests.swift` 以契约测试锚定
   （`testKeysDifferOnlyByBranch` 验证 storageKey 相同 / gateKey 不同）。

---

# 3.3 Logical State Layer

Logical State 属于：

```text
Agent + Session + LogicalBranch
```

包括：

```text
LogicalBranchState
DegenerationState
Tool Semantic Progress
Session Metadata
```

Logical State 与 Physical KV 生命周期完全解耦。

同时：

```text
Logical State
≠
Execution Scheduling State
≠
Physical KV State
≠
Resource Governance State
≠
Streaming Parser State
```

特别地：

> **Streaming Tool Parser 的瞬时状态不属于 Session、Logical Branch 或 Physical KV。**

它只属于一次 Generation Round。

---

# 4. Logical Isolation + Physical Reuse

这是 SimiGo v4.5 的核心模型：

```text
Session A ≠ Session B
Branch A ≠ Branch B
Logical State A ≠ Logical State B
```

同时：

```text
Session A
Session B
Session C
        ↓
Global Physical KV Pool
        ↓
Exact Token Prefix Match
```

因此：

> **逻辑状态必须隔离，物理计算可以复用。**

这不是上下文串扰，而是：

> **Physical Computation Reuse。**

Session 唯一性不得成为重复 Cold Prefill 的物理边界。

---

# 5. Global Physical KV 复用规则

Physical KV 只有同时满足以下条件才允许复用：

```text
Same Model Generation
+
Same Tool Fingerprint
+
Valid Physical KV Revision
+
Physical Token Prefix Match
+
Physical KV Resident
(or fallback to Cold)
+
Memory Budget Allows
```

最终判断依赖：

```text
Physical Token ID Sequence
```

通过：

```text
computeCommonPrefix(
    cachedTokens,
    promptTokens
)
```

确定实际可复用长度。

不得依据：

```text
SessionId
RequestId
ResponseId
Message Count
String Prefix
Agent Name
Tool Name
```

直接推断 Physical KV 可以复用。

Tool Fingerprint 只能作为语义兼容过滤条件，最终 Physical Prefix 仍必须由实际 Token ID Sequence 决定。

---

# 6. Physical KV 生命周期

标准路径：

```text
Prompt
 ↓
Tokenize
 ↓
Global Physical KV Candidate Search
 ↓
Tool Fingerprint Filter
 ↓
Residency Filter
 ↓
Exact Prefix Match
 ↓
Longest Common Prefix
 ↓
Predictive Admission Control
 ↓
Cold Prefill / Delta Prefill
 ↓
Decode
 ↓
Commit New Physical KV Revision
```

## Cold Prefill

```text
No usable / Evicted Physical KV
 ↓
Predictive Admission Control
 ↓
Full Prompt Prefill
 ↓
Decode
 ↓
Commit Physical KV Revision
```

## Warm Prefill

```text
Resident Physical KV Revision Found
 ↓
Common Prefix
 ↓
Predictive Admission Control
 ↓
KV Copy / Trim
 ↓
Delta Prefill
 ↓
Decode
 ↓
Commit New Physical KV Revision
```

## Exact Match

当：

```text
commonLen == promptTokens.count
```

不得再次执行完整 Prefill。

必要时只执行保证状态正确的 last-token reprime，然后进入 Decode。

---

# 7. Physical Token Ledger

Physical Token Ledger 是：

> **Physical KV 的物理事实来源。**

基本关系：

```text
Prompt Tokens
+
Actual Generated Tokens
        ↓
Physical Token Sequence
        ↔
Physical KV
```

必须保持：

```text
Physical Token Sequence
↔
Physical KV 实际逻辑深度
```

Trim 必须同步修改：

```text
Physical KV
+
Physical Token Ledger
```

Commit 必须保存：

```text
Prompt Tokens
+
Actual Generated Tokens
```

取消、失败或未完成 Generation：

> **不得提交未完成 Physical KV。**

---

# 8. Physical KV Revision

一个 Logical Branch 可以产生多个 Physical KV Revision：

```text
Logical Branch A
 ├── Physical KV Revision 1
 │       └── Resident
 │
 ├── Physical KV Revision 2
 │       └── Non-Resident / Evicted
 │
 └── Physical KV Revision 3
         └── Resident
```

Physical KV Revision 包含双层属性。

### Semantic Layer

```text
logicalBranchId
toolFingerprint
physicalTokens
```

### Physical Layer

```text
kvCache
resident
estimatedResidentBytes
```

Physical KV Revision 是：

> **可复用的计算结果（Reusable Compute Result）。**

如果系统资源不足触发驱逐，仅释放 Physical Layer：

```swift
releasePhysicalMemory()
```

并使：

```text
resident = false
```

逻辑账本：

```text
physicalTokens
```

必须保留。

未来即使再次成为候选 Revision，也只能：

```text
!resident
    ↓
Cold Prefill
```

并记录：

```text
why=evicted
```

Revision Ownership 不等于 Session Ownership。

---

# 9. Revision Count Budget 与 Memory Budget 正交

Runtime 当前定义：

```swift
maxPhysicalKVRevisions = 16
```

它的语义严格限定为：

> **Physical KV Revision 遍历、历史保留与防泄漏数组的上限。**

它不是：

```text
Memory Budget
KV Memory Limit
RSS Limit
Swap Limit
Prefill Admission Limit
```

因此：

```text
maxPhysicalKVRevisions = 16
```

不能被解释为：

```text
最多 16 个 KV 就安全
```

也不能被用来替代：

```text
Predictive Admission Control
```

例如：

```text
16 × 4K Revision
```

可能完全可接受。

而：

```text
3 × 32K Revision
```

可能已经需要大量 Eviction。

因此：

```text
Revision Count Budget
        ≠
Physical Memory Budget
```

Revision Count 的作用主要是：

```text
限制 Revision 历史数量
限制候选搜索规模
防止 Revision 元数据无限增长
降低长期运行的状态积累
```

Memory Budget 则由独立的 Resource Governance 决定。

---

# 10. Tool Fingerprint

Tool Schema 参与 Prompt 语义，因此形成：

```text
Tool Schema
 ↓
Canonical Representation
 ↓
SHA256
 ↓
toolFingerprint
```

Physical KV 复用必须满足：

```text
requestedToolFingerprint
==
revision.toolFingerprint
```

Tool Schema 变化时：

```text
Old Physical KV
 ↓
Semantically Incompatible
 ↓
Physical Residency 可被释放
```

但：

> **Tool Fingerprint 只参与 Physical KV 语义兼容性判断。**

不得控制：

```text
HTTP
Connection
Generation Controller
Agent Decision
Tool Execution
Execution Scheduler
```

---

# 11. Tool Call Architecture

Tool Call 是：

> **模型输出。**

标准路径：

```text
Model
 ↓
Tool Call Parser
 ↓
Structured Tool Call
 ↓
External Agent
 ↓
Tool Executor
```

SimiGo 可以：

```text
Parse
Normalize
Stream
Deduplicate
Audit
```

但：

> **SimiGo 不执行 Tool。**

---

# 12. Structured Tool Call 与 Raw Tool Call 双路径

稳定架构允许两种模型输出路径。

## Primary Path

MLXLMCommon 直接生成结构化：

```text
Generation.toolCall
```

进入：

```text
ParsedToolCall
```

随后：

```text
onToolCall
```

---

## Fallback Path

当模型 / Template / Runtime 没有生成结构化：

```text
Generation.chunk
```

但 chunk 内出现：

```text
<tool_call>
...
</tool_call>
```

则由当前 Generation 独立创建的：

```text
RawToolCallStreamParser
```

进行增量解析。

路径为：

```text
Generation.chunk
        ↓
RawToolCallStreamParser
        ├── Ordinary Text
        │       ↓
        │  StreamTokenFilter
        │       ↓
        │  onChunk
        │
        └── Raw <tool_call>
                ↓
          ParsedToolCall
                ↓
            onToolCall
```

Fallback Parser：

```text
不属于 Session State
不属于 Logical Branch State
不属于 Physical KV
不属于 Scheduler State
```

它只属于：

> **当前 Generation Round。**

---

# 13. Raw Tool Call Parser 增量不变量

Raw Tool Call Parser 必须支持：

```text
<to
ol_
call>
```

以及：

```text
<tool_call>
{
  ...
}
</tool_call>
```

在多个 decode chunk 中被任意切分。

因此禁止使用：

```swift
text.contains("<tool_call>")
```

作为完整解析算法。

必须维护：

```text
Parser Buffer
Parser State
```

直到：

```text
<tool_call>
```

和：

```text
</tool_call>
```

完整形成。

---

# 14. Raw Tool Call 不得泄漏给普通 Text Channel

当检测到：

```text
<tool_call>
```

后：

```text
Tool Call Body
```

不得继续：

```text
onChunk()
```

也不得经过普通：

```text
StreamTokenFilter
```

否则会产生：

```text
assistant.content =
"<tool_call>..."
```

而没有：

```text
tool_calls
```

因此：

> **Tool Protocol 与 Ordinary Text Channel 必须互斥。**

---

# 15. Tool Arguments 语义

`{}` 是合法零参数 Tool Call：

```json
{
  "name": "get_status",
  "arguments": {}
}
```

不得因为参数为空而删除 Tool Call。

但是：

```json
{
  "name": "get_status"
}
```

不是合法的“自动补空参数”行为。

SimiGo 不得自行猜测：

```text
arguments = {}
```

除非原始输出明确表达了：

```text
arguments = {}
```

因此：

```text
Missing arguments
        ≠
Empty arguments
```

必须区分。

---

# 16. Historical Tool Call / Tool Result Fail-Fast

历史 Tool Call / Tool Result 若发生：

```text
Invalid function name
Malformed arguments
Invalid argument type
Invalid protocol shape
Unparseable JSON
```

必须：

> **Fail-Fast。**

不得：

```text
猜测 function name
猜测 arguments
把 malformed JSON 转成 "{}"
静默丢弃整个 Tool Call
```

其中：

```text
null / empty arguments
```

只有在协议层已经明确允许的情况下才能规范为：

```text
{}
```

而不是用猜测替代缺失语义。

---

# 17. Tool Call Deduplication

同一个 Generation Round 内，Structured Tool Call 与 Raw Tool Call Fallback 共用：

```text
attemptedToolSignatures
```

Signature：

```text
Tool Name
+
Canonical Arguments
```

因此：

```text
Structured .toolCall
+
Raw <tool_call>
```

若语义相同：

```text
→ 只 forward 一次
```

重复项记录：

```text
[TOOL DEDUP]
```

---

# 18. Partial Dispatch

Partial Dispatch 必须保留：

```text
attemptedSignatures
```

作为本轮后续比较基线。

例如：

```text
Tool A → dispatched
Tool B → dispatcher interrupted
Tool C → not dispatched
```

不能将整个 Generation 伪造为：

```text
all tools forwarded
```

也不能因为：

```text
partial dispatch
```

而自动生成虚假的 Tool Result。

---

# 19. Tool Parse Failure 与 Generation State

如果发生：

```text
Raw <tool_call>
```

但：

```text
ParsedToolCall 生成失败
```

则：

```text
Tool Parse State = Failed
```

这一状态不得被解释为：

```text
Plain Text Generation
```

因此禁止出现：

```text
turnToolCalls = 0
+
rawToolCallDetected = true
+
resetOnPlain()
```

同时：

```text
raw tool-call parse failure
```

必须阻止：

```text
Physical KV Commit
```

防止错误协议结果进入 Global Physical KV。

---

# 20. Tool/KV Commit Invariant

以下状态禁止存在：

```text
rawToolCallDetected = true
+
structuredToolCallCount = 0
+
forwardedToolCount = 0
+
KV Commit = true
```

即：

```text
Raw Tool Call Protocol Failure
        ↓
KV Commit = 0
```

这是 Tool Protocol Robustness 的关键 Invariant。

原因是：

```text
错误 Tool Call 输出
        ↓
普通 assistant text
        ↓
Logical History 污染
+
Physical Token Ledger 污染
+
Physical KV 污染
```

必须在 Generation → Commit 边界阻断。

---

# 21. Tool Call 与 Degeneration State

Degeneration State 仍然属于：

```text
Logical Branch
```

而不是 Tool Parser。

状态流程：

```text
preview()
   ↓
recordBlocked()
commitForwarded()
resetOnPlain()
```

核心不变量：

```text
1 Generation Round
→
0 or 1 State Transition
```

新的 Tool Protocol 规则：

```text
真正无 Tool Call
    ↓
resetOnPlain()

有效 Structured Tool Call
    ↓
preview / forward / commit

Raw Tool Call Parse Failure
    ↓
Fail-Fast
    ↓
不得被当成 Plain Round
```

---

# 22. Degeneration 与 Tool Semantic Progress

检测依据可以包括：

```text
Tool Signature
Tool Result
Semantic Progress
```

达到阈值后：

```text
[BRANCH DEGENERATION BLOCKED]
```

新的 Raw Tool Parser 不改变 Degeneration 的语义。

其职责只有：

```text
把 raw protocol 表达转换成 ParsedToolCall
```

是否属于重复、退化或可 forward，由现有 Logical Branch Degeneration State 决定。

---

# 23. Tool Parsing 与 Physical KV 解耦

Tool Parser：

```text
Parse
Normalize
Emit
```

不拥有：

```text
Physical KV
KV Selection
KV Commit
KV Eviction
```

Physical KV 仍然只依据：

```text
Model Generation
Tool Fingerprint
Token Exact Match
Revision Residency
Memory Governance
```

决定。

因此：

```text
Tool Parser State
        ≠
Physical KV Semantic State
```

---

# 24. Streaming

Streaming 负责：

```text
Generated Output
 ↓
Incremental Parsing
 ↓
Text / Tool Call
 ↓
SSE
```

必须保证：

```text
Event Order
Completion State
No Tail Loss
Cancellation Consistency
```

Streaming Parser 不得反向控制：

```text
Physical KV
Generation Gate
HTTP Lifecycle
Execution Scheduler Policy
```

特别地：

> **Raw Tool Call Parser 只负责把模型流转换为 Structured Tool Call，不负责执行 Tool，不负责改变 KV 策略。**

---

# 25. Stream Flush 顺序

Generation 完成后，Streaming Parser 的 flush 顺序固定为：

```text
Generation End
 ↓
Raw Tool Call Parser Flush
 ↓
Ordinary Stream Token Filter Flush
```

不得颠倒。

原因：

```text
raw <tool_call> 尚未完成
```

不得被 Ordinary Text Filter 当成尾部普通文本。

Generation 结束仍存在未闭合：

```text
<tool_call>
```

必须：

```text
Tool Protocol Failure
```

而不是：

```text
Ordinary Assistant Text
```

---

# 26. Responses API

Responses API 是：

> **Protocol Compatibility Layer。**

协议状态：

```text
responseId
previous_response_id
metadata
protocol context
```

不是 Physical KV State。

正确路径：

```text
previous_response_id
 ↓
Canonical Context
 ↓
Tokenization
 ↓
Global Physical KV Match
```

禁止：

```text
previous_response_id
 ↓
直接指定 Physical KV Revision
```

---

# 27. Responses Tool History

Responses 输入：

```text
function_call
function_call_output
```

可以转换成 Runtime Canonical Message：

```text
assistant
    tool_calls

tool
    tool_call_id
    content
```

但这种转换属于：

```text
Protocol Normalization
```

而不是：

```text
Physical KV Mapping
```

历史进入 NativeMLX 前必须通过：

```text
Message Normalization
+
Historical Tool Call Validation
```

---

# 28. Thinking

当前稳定基线：

```text
disableThinking = true
```

Protocol 可以接收：

```text
enable_thinking
reasoning.effort
```

但必须最终转换为：

```text
Model Configuration
 ↓
Chat Template
 ↓
Generation
```

不能通过生成后文本删除冒充关闭 Thinking。

---

# 29. Runtime Memory Governance

当前核心限制：

```swift
inferenceMemoryLimit = 22 GiB
inferenceCacheLimit = 4 GiB
```

并继续保持：

```text
Memory.memoryLimit
Memory.cacheLimit
```

的运行时限制。

Resource Governance 的主要目标：

```text
在 Prefill / Allocation 发生前
判断新增计算是否会使 Runtime 自身进入危险状态
```

---

# 30. Predictive Admission Control

当前 SimiGo 不采用单纯 RSS 作为 Physical KV Admission 的唯一基础。

当前实现保留 Runtime 自有物理账本：

```text
Current Resident KV Bytes
+
Projected KV Delta
+
Execution Working Set
+
Safety Margin
```

其中：

```text
Execution Working Set = 3 GiB
Safety Margin = 1 GiB
Admission Limit = 22 GiB
```

公式为：

```text
Projected Memory
=
Current Resident KV Bytes
+
Projected KV Delta
+
Execution Working Set
+
Safety Margin
```

如果：

```text
Projected Memory > Admission Limit
```

则：

```text
Lossless Eviction
```

随后再允许：

```text
Prefill
```

---

# 31. RSS 与 Swap 的架构定位

RSS 与 Swap 必须继续观测：

```text
residentMemory
virtualMemory
systemSwapUsed
```

但是：

> **System RSS 与 Internal Physical KV Ledger 是两个不同维度。**

原因：

RSS 可能包含：

```text
Model Weights
MLX Allocator
Metal Mapping
Swift Heap
Framework Memory
Other Runtime Memory
```

因此不能把：

```text
RSS
```

直接等价于：

```text
Physical KV Size
```

也不能简单把 RSS 原值代入当前自有 KV Admission Formula。

---

# 32. System Swap

System Swap 是：

> **诊断指标。**

它不等于：

```text
KV Size
```

也不直接进入：

```text
Admission Formula
```

Swap 的主要用途：

```text
观察 Unified Memory 压力
识别 Runtime / OS thrashing
判断 Admission 是否有效
验证 Request / Session 生命周期结束后的恢复趋势
```

---

# 33. Long-Context Resource Governance

定义：

```swift
longContextThreshold = 16384
```

策略：

```text
Prompt < 16K
    ↓
Normal Admission Policy
```

```text
Prompt >= 16K
    ↓
Long-Context Admission Policy
    ↓
Stronger Eviction
```

当前实现允许：

```text
达到普通释放目标后
额外释放约 2 GiB
```

用于保护后续 Decode 的 Unified Memory 空间。

这一策略只改变：

```text
Residency Policy
Eviction Intensity
```

绝不改变：

```text
Physical KV Semantic Reuse
```

---

# 34. Long-Context 的 Semantic Invariant

长上下文不会改变：

```text
Tool Fingerprint
Token Exact Match
Common Prefix
Logical Ledger
Revision Semantics
```

因此：

```text
Long Context
    ≠
新的 KV Semantic Key
```

也不意味着：

```text
Long Context
    → 禁止 Physical Reuse
```

其作用仅为：

```text
Long Context
    →
更积极释放不活跃 Physical Residency
```

---

# 35. Lossless Eviction

Eviction 只允许释放：

```text
Physical Layer
```

即：

```text
kvCache
```

而保留：

```text
physicalTokens
logicalBranchId
toolFingerprint
```

所以：

```text
Evicted Revision
```

仍是逻辑上有效的 Revision Record。

以后命中该 Revision 时：

```text
resident=false
        ↓
Cold Prefill
```

并记录：

```text
why=evicted
```

---

# 36. Revision Count 与 Memory Governance 的严格分工

两套机制必须保持正交：

```text
Revision Count
负责：

    Revision 历史边界

    遍历成本

    状态泄漏防护

Memory Governance
负责：

    Residency

    Eviction

    Prefill Admission

    Physical Memory Pressure
```

因此：

```text
maxPhysicalKVRevisions = 16
```

不能替代：

```text
22 GiB Admission Limit
```

同样：

```text
22 GiB Admission Limit
```

不能替代 Revision Count Bounding。

---

# 37. 两层并发与生命周期门禁

v4.5 原有两层 Gate 保持不变。

## Tier 1：RuntimeLifecycleGate

负责：

```text
start()
stop()
```

保证：

```text
Runtime N
```

完全结束后才能进入：

```text
Runtime N+1
```

不得发生：

```text
Old Runtime
+
New Runtime
```

生命周期重叠。

---

## Tier 2：SessionGenerationGate

负责：

```text
Agent
+
Session
+
LogicalBranch
```

同一 Logical Branch 内严格串行：

```text
Read State
 ↓
Preview
 ↓
Generate
 ↓
Tool Dispatch
 ↓
Commit / Compensation
```

保证：

> **Exactly One Acquire → Exactly One Release**

---

# 38. Inference Execution Scheduler

在两个 Gate 之下可以存在：

```text
Inference Execution Scheduler
```

职责：

```text
Runnable Request Management
Prefill Scheduling
Decode Scheduling
Decode Batching
Execution Fairness
Execution Arbitration
```

Scheduler 属于：

> **Execution Plane。**

不属于：

```text
Logical State Plane
Physical KV Semantic Plane
Protocol Plane
Agent Runtime
```

Logical Branch 串行，不等于 Model Compute 必须全局串行。

不同：

```text
AgentExecutionKey
```

可以共享 Model Execution。

---

# 39. Prefill Scheduler

PrefillScheduler 作为内部组件保留。

原则：

```text
同一 Logical Branch 保持生成顺序
全局 Prefill 并发受资源预算控制
Decode 不重复获取不必要的 Prefill 独占
Global Physical KV Reuse 减少重复 Prefill
```

---

# 40. Prefill / Decode Arbitration

大 Delta Prefill 可以采用局部 Chunking：

```text
Large Delta
 ↓
Prefill Chunk
 ↓
Arbitration
 ↓
Decode Epoch
 ↓
Next Prefill Chunk
```

实验参数：

```text
prefillChunkSize
```

当前基线仍：

```text
1024
```

可以比较：

```text
256
512
1024
```

不得未经 Benchmark 固化新的理论最优值。

---

# 41. Cancellation

Cancellation：

```text
Client Disconnect / Cancel
 ↓
Cancellation
 ↓
Generation Cancel
 ↓
Stop Stream
 ↓
Skip unfinished Physical KV Commit
 ↓
Release Temporary Resources
 ↓
CANCELLED
```

Cancelled / Completed Request 不得重新进入 Scheduler Runnable Set。

同时：

```text
Cancelled Generation
```

不得把：

```text
actualGeneratedTokens
```

作为新的完整 Physical KV Revision 提交。

---

# 42. Tool Call 与 Cancellation

如果 Cancellation 发生于：

```text
RawToolCallParser
```

或：

```text
Structured Tool Call
```

尚未完成 dispatch：

```text
forwardedToolCount == 0
```

不得伪造：

```text
Tool Completed
```

如果发生 Partial Dispatch：

```text
attemptedSignatures
```

仍然保留本轮比较基线。

---

# 43. Physical KV Commit

Physical KV Commit 必须同时满足：

```text
Generation Complete
+
Not Cancelled
+
Not Interrupted
+
Tool Protocol Valid
+
No Degeneration Circuit Break
+
All Forwarded Tool Calls Valid
+
Valid Prompt
+
Valid KV Cache
```

其中新增：

> **Tool Protocol Valid 是 Physical KV Commit 的必要条件。**

因此：

```text
Raw Tool Parse Failure
```

必须导致：

```text
KV Commit = 0
```

---

# 44. Physical KV Commit 内容

Commit：

```text
Prompt Tokens
+
Actual Generated Tokens
```

形成：

```text
Physical Token Sequence
```

禁止保存：

```text
Expected Tokens
Predicted Tokens
String-reconstructed Tokens
Incomplete Tokens
Uncommitted Tool Text
```

Physical Token Ledger 必须来自实际 Runtime Generation。

---

# 45. Physical KV Selection

Candidate Search：

```text
Global Physical KV Pool
 ↓
Tool Fingerprint Filter
 ↓
Physical Token Prefix Compare
 ↓
Longest Common Prefix
 ↓
Resident Check
```

选择不使用：

```text
Session ID
Request ID
Response ID
Tool Name
Message Count
```

作为直接 Physical KV 地址。

---

# 46. Global KV Pool

Global Physical KV Pool 是：

> **计算结果共享池。**

不是：

```text
Conversation Memory
Session Store
Response Store
Agent Memory
```

因此：

```text
Global Physical KV
```

可以跨：

```text
Agent
Session
Logical Branch
```

复用，只要：

```text
Model
+
Tool Fingerprint
+
Token Prefix
+
Residency
+
Memory Governance
```

全部满足。

---

# 47. Responses State 与 Physical KV 解耦

Responses：

```text
responseId
previous_response_id
StoredResponse
historyMessages
```

只能管理：

```text
Protocol State
Logical Context
```

不能直接代表：

```text
Physical KV Revision
```

因此：

```text
previous_response_id
```

绝对不是：

```text
Physical KV Key
```

---

# 48. Observability

主 Trace：

```text
~/.simigo/logs/native_mlx_trace.log
```

必须能够证明 Runtime 实际发生了什么。

## Scheduler / Generation

```text
[REQUEST]
[GENERATION START]
[GATE]
[PREFILL WAIT]
[CANCEL REQUEST]
[CANCELLED]
```

## Tool

```text
[TOOL]
[RAWTOOL]
[STOOL]
[TDUP]
[TDROP]
[TPFAIL]
```

其中：

```text
[RAWTOOL]
```

表示模型 chunk 中发现 raw `<tool_call>` 协议。

```text
[STOOL]
```

表示最终形成 Structured Tool Call。

```text
[TPFAIL]
```

表示 Raw Tool Call Protocol Parsing Failure。

## KV

```text
[KV DIAGNOSTIC]
[KV SELECT]
[KV COPY]
[KV COMMIT]
[KV MISS]
```

## Resource Governance

```text
[ADMISSION]
[ADMISSION WARN]
```

## Long Context

应能够观察：

```text
Prompt Token Count
Delta Token Count
Projected Memory
Evicted Revision Count
Estimated Freed Bytes
```

## Memory

```text
[MEM]
[SUM]
```

包含：

```text
RSS
Virtual Memory
System Swap
Internal KV Revision Count
Physical Token Count
```

但：

> **RSS / Swap 是 Observation，不等于 Internal KV Ledger。**

---

# 49. Tool Observability 最低信息集

每次 Tool Protocol 事件至少应能够关联：

```text
requestId
session
branch
toolName
toolCallCount
rawToolCallDetected
forwardedCount
```

故障时至少能够区分：

```text
1. No Tool Call
2. Structured Tool Call
3. Raw Tool Call Fallback
4. Raw Tool Parse Failure
5. Tool Dedup
6. Degeneration Block
```

禁止出现无法区分：

```text
"tool=0"
```

到底是：

```text
真的没有 Tool
```

还是：

```text
Tool Parser 失败
```

---

# 50. Performance Principle

Physical KV Reuse 是手段，不是最终 KPI。

每次优化必须同时观察：

```text
TTFT
Prefill tok/s
Decode tok/s
Aggregate Decode tok/s
Per-request Decode tok/s
Scheduler Wait
Total Latency
Tail Latency
Resident Memory
System Swap
Physical KV Residency
Tool Parse Correctness
Tool Dispatch Correctness
Stability
```

最终标准：

> **End-to-End Latency + Stability。**

例如：

```text
Physical KV Reuse ↑
TTFT ↓
Decode ↓↓
Swap ↑↑
Total Latency ↑
```

则：

> **优化失败。**

同样：

```text
Tool Parser Accuracy ↑
```

但：

```text
Latency ↑↑
Memory ↑↑
Stream Stability ↓
```

也不能直接进入 Stable Capability。

---

# 51. Benchmark Baseline

维持原有 Benchmark Definition。

Level 0~10 重点增加：

```text
Tool Protocol Correctness
Raw Tool Fallback Correctness
Malformed Tool Call Fail-Fast
Tool Dedup Correctness
Tool/KV Commit Invariant
```

Admission 重点监控：

```text
[ADMISSION] 触发频次
Eviction Count
Estimated Freed Bytes
Physical KV Residency
RSS
Swap
```

---

# 52. Tool Protocol Benchmark

最低 Tool Benchmark 集：

### Test A：Structured Tool

```text
Generation.toolCall
```

期望：

```text
tool=1
forwarded=1
kv=1
```

### Test B：Raw Tool Fallback

```text
Generation.chunk("<tool_call>...")
```

期望：

```text
raw=1
structured=1
forwarded=1
```

### Test C：Chunk Split

例如：

```text
"<to"
"ol_"
"call>"
```

期望：

```text
仍正确生成 ParsedToolCall
```

### Test D：Malformed Tool

期望：

```text
TPFAIL
KV=0
```

### Test E：Incomplete Tool at EOS

期望：

```text
TPFAIL
KV=0
```

### Test F：Duplicate Tool

期望：

```text
TDUP
forwarded once
```

---

# 53. Invariant Audit

新增 Tool / KV Invariant：

禁止：

```text
rawToolCallDetected = true
+
turnToolCalls = 0
+
KV Commit = true
```

禁止：

```text
Raw Tool Protocol Failure
+
Normal Plain State Transition
```

禁止：

```text
Malformed Tool Call
+
Assistant History Normalization
```

禁止：

```text
Incomplete Tool Call
+
onChunk
```

禁止：

```text
Tool Parser State
+
Session / KV State Persistence
```

---

# 54. Resource Governance Audit

必须同时检查：

```text
Revision Count
Internal KV Estimate
Projected Delta KV
Working Set
Safety Margin
Admission Limit
Residency
Eviction
RSS
Swap
```

必须保持：

```text
Revision Count Budget
≠
Memory Budget
```

并且：

```text
Swap
≠
KV Size
```

---

# 55. Stop / Teardown Invariant

Stop 必须：

```text
Close Admission
 ↓
Cancel Waiters
 ↓
Drain Owners
 ↓
Release Physical KV
 ↓
Clear Memory
 ↓
Verify Runtime State
```

不得：

```text
直接清空 active ownership
```

必须保证：

```text
Old Runtime
```

完全结束后，才能启动：

```text
New Runtime
```

---

# 56. Long-Context 实机基线

历史实机测试：

```text
Prompt
≈ 12K → 14K → 19K → 23K → 26K → 29K → 31K → 34K
```

观察到：

```text
Global Physical KV Reuse 持续存在
Decode Throughput 随上下文增长下降
单 Agent Long Context 可以产生巨大 Swap Pressure
```

因此：

```text
Multi-Agent Contention
```

与：

```text
Long-Context Memory Pressure
```

必须分别验证。

---

# 57. Long-Context 资源策略

Long Context：

```text
>= 16384 tokens
```

触发：

```text
Stronger Eviction
```

允许：

```text
额外约 2GB 防御性空间
```

但：

```text
Physical Token Ledger
```

绝不能被删除。

换言之：

```text
Eviction
=
Release Physical Residency
```

不是：

```text
Delete Semantic Revision
```

---

# 58. New Capability 准入标准

新的局部能力必须：

```text
不破坏 v4.5 Lifecycle
+
不破坏 Physical KV Invariants
+
存在 Benchmark 必要性
+
可以局部实现
+
可以回退
+
不改变 Agent Runtime 边界
```

优先进入实验轨道：

```text
Scheduler Observability
Generation Gate Observability
Decode Quantum
Controlled Batched Decode
Prefill / Decode Arbitration
Scheduler Cancellation
Tool Protocol Robustness
Raw Tool Fallback
```

---

# 59. 禁止未经验证进入 Core 的方向

不得因为理论完整性直接引入：

```text
新的 Agent Orchestrator
新的 Session Ownership Model
新的 Physical KV Semantic Key
Disk KV Cache Paging / Restore
未经 Benchmark 的 Continuous Batching
未经 Benchmark 的全局 Scheduler 重构
```

---

# 60. Ponytail 核心铁律

### 原有 v4.5 铁律

1. **v4.5 是稳定基线，不为实验能力反复重构 Core。**
2. **SimiGo 是 Inference Runtime，不是 Agent Runtime。**
3. **HTTPServer 是 Protocol Gateway，不进入 Physical KV Core。**
4. **Agent / Session / LogicalBranch 是逻辑身份；Request 是一次生成。**
5. **SessionId 唯一，不等于 Physical KV 必须隔离。**
6. **Logical State 必须隔离；Physical Computation 可以共享。**
7. **Namespace 负责逻辑隔离，Token Exact Match 决定 Physical KV Reuse。**
8. **Physical KV 复用必须满足 Model Generation + Tool Fingerprint + Prefix Match + Revision Resident。若非 Resident，降级为 Cold 并记录 `why=evicted`。**
9. **Physical Token Ledger 是 Physical KV 的物理事实来源。**
10. **Physical Token 与 Physical KV 逻辑映射必须同步。**
11. **Trim 必须同步作用于 Physical KV 与 Ledger。**
12. **Delta Prefill 必须从 commonLen 开始。**
13. **Exact Match 不得再次完整 Prefill。**
14. **Commit 必须保存真实生成 Token。**
15. **Physical KV Revision 是计算结果，包含逻辑状态和物理状态的双层属性。它不是 Session 所有权。**
16. **Tool Fingerprint 只参与 Physical KV 语义兼容。**
17. **Tool Call 属于模型输出，SimiGo 不执行 Tool。**
18. **`{}` 是合法零参数 Tool Call，不得猜测参数。**
19. **历史协议损坏必须 Fail-Fast。**
20. **Degeneration State 属于 Logical Branch，不属于 Physical KV。**
21. **Partial Dispatch 必须保留 attemptedSignatures。**
22. **Cancel-before-dispatch 不得制造伪状态跃迁。**
23. **Client disconnect 必须进入 Cancellation。**
24. **Cancellation 不得提交未完成 Physical KV。**
25. **同一 Logical Branch 必须串行。**
26. **Runtime Lifecycle 必须全局串行。**
27. **Stop 必须 Close Admission → Cancel Waiters → Drain Owners → Release Physical KV → Clear Memory。**
28. **不得直接清空 active ownership。**
29. **Cache 必须有界，进入 Prefill 前必须经过 Predictive Admission Control 的严格测算。**
30. **Streaming Parser 不得控制 Physical KV 或 Generation Lifecycle。**
31. **Responses State 不是 Physical KV State。**
32. **previous_response_id 不是 Physical KV Key。**
33. **KV Reuse 不是最终 KPI，End-to-End Latency + Stability 才是。**
34. **任何 Physical KV 优化不得破坏 HTTP、SSE、Cancellation、Tool Call 或 Generation 正确性。**
35. **每次 Runtime 修改必须 Benchmark；每次 Physical KV 修改必须 Invariant Audit。**
36. **没有 Benchmark / Audit / Stress Test 的核心修改不得进入稳定基线。**
37. **一次只引入一个主要变量，性能回退立即回退实验。**
38. **Multi-Agent Physical KV 是优化能力，不是新的 Agent Runtime。**
39. **Local/LAN Node 是服务能力，不是 Agent Orchestration。**
40. **Protocol Compatibility 不得污染 Generation Lifecycle。**
41. **Session 唯一性不得成为重复 Cold Prefill 的理由。**
42. **Global Physical KV 是计算复用层，不是对话状态层。**
43. **任何共享 Physical KV 的前提都是严格的 Model / Tool / Token 语义一致性。**
44. **Logical Branch 串行不等于 Model Execution 必须全局串行；不同 AgentExecutionKey 可以通过 Inference Execution Scheduler 共享 Model Compute。**
45. **Resource Policy 可以驱逐 Physical KV，改变 `resident` 状态，但绝不能篡改和删除 Logical Ledger。**
46. **Cancelled / Completed Request 不得重新进入 Execution Scheduler Runnable Set。**
47. **一个 Request 在同一 Scheduling Epoch 中不得重复参与 Decode。**
48. **Decode Scheduler 必须同时关注 Aggregate Throughput、Per-request Throughput、Short-request Fairness 与 End-to-End Latency。**
49. **Prefill Chunking 必须保护已有 Decode Progress，不得无限期阻塞 Runnable Decode。**
50. **Batched Decode 是局部 Execution Capability，不改变 Logical State Model。**
51. **Execution Scheduler 属于 Execution Plane，不拥有 Agent / Session / LogicalBranch State。**
52. **Resource Governance Scope 与 Semantic Reuse Scope 已完全正交。**
53. **Global Physical KV Selection 可以共享；Resource Budget、Residency 与 Eviction 独立进行。**
54. **Decode Contention 的具体根因必须由 Instrumentation / Profiling 证明，不得把单一假设直接固化为 Core 语义。**
55. **任何 Scheduler 优化必须证明 End-to-End Latency 与 Stability 改善后才能进入 Stable Capability。**
56. **`longContextThreshold` 已实际接入 Physical KV Resource Governance，成为触发长上下文强清扫策略的依据。**
57. **Long Context 改变了 Eviction Policy 的驱逐强度，但绝对不改变 Physical KV Semantic Reuse 的匹配前提。**
58. **Physical KV Resource Budget 不再由 Revision Count 表示；其核心算法为 Internal Resident KV Ledger + Projected KV Delta + Working Set + Safety Margin。**
59. **Revision Count Budget 与 Physical Memory Budget 是两个独立维度，互相不可替代。**
60. **单 Agent Long-Context Memory Pressure 必须与 Multi-Agent Decode Contention 分开验证。**
61. **System Swap 是诊断指标，不得直接等同于 KV Size，也不得放入当前 Internal KV Admission Formula 中作为硬限制。**
62. **Agent / Request 结束后必须验证 Task、KV Residency、Resident Memory 与 Swap 趋势，而非仅看逻辑状态。**
63. **Long-Context Resource Policy 的具体阈值、Working Set 和 Safety Margin 经验参数必须由实机 Benchmark 提供背书。**
64. **`Memory.clearCache()` 只允许作为释放显存引用的辅助手段，不得作为主要 Lifecycle 拦截动作。**

---

# 61. Tool Protocol Robustness 新增铁律

65. **Structured `Generation.toolCall` 是 Tool Call 主路径；Raw `<tool_call>` Parser 只是局部 fallback。**
66. **Raw Tool Call Parser 只能存在于当前 Generation Round，绝不能跨 Generation、Session、Logical Branch 或 Physical KV 复用状态。**
67. **Raw `<tool_call>` 必须采用增量状态机解析，不得依赖单个 decode chunk 的完整标签。**
68. **进入 `<tool_call>` 状态后，Tool Call Body 不得泄漏到普通 `onChunk` 文本通道。**
69. **Raw Tool Call Fallback 与 Structured Tool Call 必须使用统一的 Tool Signature Dedup 机制。**
70. **Tool Parser Failure 不得被解释为 Plain Text Generation。**
71. **Raw Tool Call Parse Failure 必须阻止本轮 Physical KV Commit。**
72. **以下状态属于禁止状态：`rawToolCallDetected=true + turnToolCalls=0 + KV Commit=true`。**
73. **Malformed 或 Incomplete Raw Tool Call 必须 Fail-Fast，不得猜测 Tool Name 或 Arguments。**
74. **`arguments={}` 是合法 zero-argument Tool Call；Missing Arguments 不得自动推断成 `{}`。**
75. **Tool Protocol Validity 是 Physical KV Commit 的必要条件之一。**
76. **Tool Protocol Parser 不得拥有 Physical KV、Generation Gate、Scheduler 或 Tool Executor。**
77. **Tool Parser 的瞬时状态不得成为 Logical State。**
78. **Streaming Parser 的 Flush 顺序必须是 Raw Tool Parser → Ordinary Text Filter。**
79. **Generation EOS 时未闭合的 Raw Tool Call 必须视为 Protocol Failure，而不是 Assistant Text。**
80. **Tool Protocol Observability 必须能够区分 No Tool、Structured Tool、Raw Fallback、Parse Failure、Dedup 和 Degeneration Block。**
81. **Tool Parse Failure、Malformed History 和 Incomplete Tool Call 不得产生正常 Tool Completion 事件。**
82. **Tool Call 正确性优先于通过增加容错而保持表面生成连续性；协议损坏必须明确暴露。**

---

# 62. Resource Governance 新增校正规则

83. **`maxPhysicalKVRevisions` 只控制 Revision 历史数量，不代表 Memory Budget。**
84. **`maxPhysicalKVRevisions` 调整不得被当作 Memory Optimization 的替代方案。**
85. **Internal Resident KV Ledger、Projected KV Delta、Working Set、Safety Margin 组成当前 Admission 的核心预算模型。**
86. **RSS、Virtual Memory、System Swap 属于观察指标，与 Internal KV Ledger 保持语义分离。**
87. **不得因为 RSS 数值下降或上升而直接推断 Physical KV 大小。**
88. **Eviction 必须 Lossless：只释放 Physical Residency，保留 Logical Ledger。**
89. **Long-Context Policy 可以提高 Eviction 强度，但不得改变 KV Semantic Match Rules。**
90. **Revision Count Budget 与 Resource Budget 必须保持正交，不得使用 Revision Count 代替 Admission Control。**

---

# 63. Final Architecture Model

最终 Runtime 层级：

```text
                 External Agent
                       │
                       ▼
              OpenAI-Compatible API
                       │
                       ▼
                 HTTPServer
             Protocol Gateway
                       │
                       ▼
                 NativeMLX
                       │
        ┌──────────────┼────────────────┐
        │              │                │
        ▼              ▼                ▼
   Logical Plane   Execution Plane   Resource Plane
        │              │                │
        │              ├─ Gate          ├─ Admission
        │              ├─ Scheduler     ├─ Residency
        │              ├─ Prefill       └─ Eviction
        │              └─ Decode
        │
        ├─ Agent
        ├─ Session
        ├─ Logical Branch
        └─ Degeneration
        │
        ▼
   Generation Round
        │
        ├─ Structured Tool Call
        │
        ├─ Raw Tool Fallback
        │
        └─ Ordinary Text
        │
        ▼
   Physical Token Ledger
        │
        ▼
   Global Physical KV Pool
```

---

# 64. Unified Runtime Flow

标准生成流程：

```text
Request
 ↓
AgentExecutionKey
 ↓
SessionGenerationGate
 ↓
Message Normalization
 ↓
Tool Schema Normalization
 ↓
Tokenization
 ↓
Tool Fingerprint
 ↓
Semantic Progress
 ↓
Global Physical KV Candidate Search
 ↓
Exact Token Prefix Match
 ↓
Predictive Admission Control
 ↓
KV Copy / Trim / Cold Prefill
 ↓
Generation
        ├───────────────┐
        │               │
        ▼               ▼
Structured Tool     Raw Tool Fallback
        │               │
        └───────┬───────┘
                ▼
        ParsedToolCall
                │
                ▼
        Dedup / Degeneration
                │
                ▼
        External Agent
                │
                ▼
        Generation Completion
                │
                ▼
        Physical KV Commit
```

任何以下情况：

```text
Cancellation
Malformed Tool Call
Incomplete Tool Call
Parser Failure
Generation Interrupted
Degeneration Circuit Break
```

都必须阻止：

```text
未完成 Physical KV Commit
```

---

# 65. 最终统一结论

SimiGo v4.5 Stable Foundation 的最终原则：

> **逻辑隔离，执行共享，计算复用，预测治理，协议严格。**

进一步展开：

```text
Logical Isolation
        ↓
Agent / Session / Logical Branch

Execution Sharing
        ↓
Gate / Scheduler / Prefill / Decode

Physical Reuse
        ↓
Exact Token Prefix + Tool Fingerprint

Resource Governance
        ↓
Internal KV Ledger + Projected Delta + Working Set + Margin

Long-Context Governance
        ↓
Stronger Eviction without Semantic Deletion

Tool Protocol Robustness
        ↓
Structured Primary Path + Raw Fallback + Fail-Fast

Lifecycle Determinism
        ↓
Acquire → Execute → Commit / Cancel → Release
```

最终架构必须长期保持：

```text
Agent Runtime
    ≠
Inference Runtime

Logical State
    ≠
Physical KV State

Streaming Parser State
    ≠
Logical State

Revision Count
    ≠
Memory Budget

RSS
    ≠
KV Size

Swap
    ≠
KV Size

Responses State
    ≠
Physical KV State

Tool Execution
    ≠
Inference Runtime
```

并且：

> **Physical KV Reuse 是性能手段，不是最终 KPI。**

> **Long-Context Resource Policy 决定 Physical KV 在资源压力下应该保留多少，但绝不改变 Physical KV 的 Semantic Reuse 规则。**

> **Tool Protocol Robustness 负责保证模型输出可以被正确识别、规范化和转发，但不进入 Agent Tool Execution。**

> **一次错误 Tool Protocol 解析不得污染 Logical History，也不得污染 Physical KV。**

> **Revision Count 用于限制计算结果历史规模；Predictive Admission Control 负责实际物理资源治理。两者永远正交。**

> **System Swap 是运行时压力的诊断信号，不是 KV 语义，也不是当前 Admission Formula 的直接输入。**

> **任何新能力只有在 Benchmark、Invariant Audit 和 Stress Test 证明稳定收益后，才能成为 Stable Capability。**

> **SimiGo v4.5 Stable Foundation 的核心铁律保持不变：稳定性优先于理论完整性。**

---

## Architecture Identity

```text
Ponytail

Logical Isolation
        +
Execution Sharing
        +
Physical Compute Reuse
        +
Predictive Resource Governance
        +
Strict Tool Protocol Handling
        +
Deterministic Lifecycle
```

**最终原则：**

> **逻辑隔离，执行共享，计算复用，预测治理，协议严格。**

---

## v4.5 Addendum — OpenAI Session / Physical KV Decoupling

本节记录 2026-09-02 对 OpenAI-compatible HTTPServer 进行的一次实际运行验证，以及由此正式确立的 Session / Physical KV 解耦原则。

### A. 问题背景

原 OpenAI Chat / Completions 适配层在没有显式 Session 时，会根据 messages 前缀推导稳定 Session：

```text
messages.prefix(2)
        ↓
content.prefix(512)
        ↓
SHA256
        ↓
inferred:<digest>
```

该机制原意是让无状态 OpenAI 客户端的连续请求获得稳定 Session，但实际运行中可能将原本需要独立生命周期的不同请求映射到同一个 Session，并放大同一 Session Generation Gate 的等待。

### B. 本次正式修正

OpenAI Chat / Completions 现在遵循：

```text
Explicit Session
        ↓
Preserve Client Session
```

若没有显式 Session：

```text
每个 HTTP Request
        ↓
独立 request-scoped Session
```

不再使用：

```text
messages → inferred Session
```

也不再为了 KV Reuse 主动压缩不同 Session。

### C. KV Reuse 不再依赖 Session 相同

新的正确链路为：

```text
OpenAI Request A
session=A
        │
        └─────────┐
                  │
OpenAI Request B  │
session=B         │
        │          ▼
        └────→ Global Physical KV Pool
                     │
                     ▼
             Tool Fingerprint
                     │
                     ▼
             Exact Token Prefix
                     │
                     ▼
               Physical Reuse
```

因此：

```text
Session A ≠ Session B
```

并不意味着：

```text
KV(A) ≠ KV(B)
```

### D. 实测验证

2026-09-02 实测中，OpenAI 请求产生不同 Session：

```text
s=b99cf3
s=9c685c
s=b84a00
s=7be176
```

对应 Gate 日志均可观察到：

```text
[GATE] wait=0.0ms
```

同时，不同 Session 仍成功复用 Global Physical KV，例如：

```text
[s=9c685c] [KVC] src=G rev=f4beb3 ... ktok=309 revs=1 ok
[s=b84a00] [KVC] src=G rev=f4beb3 ... ktok=309 revs=1 ok
```

进一步出现：

```text
[s=7be176]
[KCP] src=G rev=7f9874 cache=7679 kv=40 p=10301 cp=7646
[KVR] src=G i=0 rev=7f9874 cache=7679 cp=7646 d=2655 hit=74.2%
```

这证明：

```text
不同 Session
        +
Global Physical KV Prefix Match
        +
Physical KV Reuse
```

可以同时成立。

### E. 架构结论

因此 v4.5 正式确认：

> **Session Identity 与 Physical KV Identity 必须解耦。**

> **Session 表示逻辑上下文归属；Physical KV 表示已经完成的物理计算结果。**

> **不得为了 Physical KV Reuse 而改变 Protocol Session Identity。**

> **OpenAI-compatible HTTPServer 应尽可能忠实保留客户端的逻辑 Session；是否复用 KV 由 Physical KV Runtime 根据实际 Token Prefix、Tool Fingerprint、Revision Residency 和 Resource Governance 独立决定。**

### F. 对 Multi-Agent 架构的意义

这一修正正式确立：

```text
Goal Agent
    ↓
独立 Logical Session

Execution Agent A
    ↓
独立 Logical Session

Execution Agent B
    ↓
独立 Logical Session

        ↓
Global Physical KV Pool
        ↓
Physical Compute Reuse
```

因此 Goal / Execution 可以保持逻辑隔离，而无需牺牲已有上下文的物理复用能力。

这是 v4.5 从“Session-based KV reuse”进一步演进到：

> **Global Physical Compute Reuse**

的重要架构转折。

---

## v4.5 Addendum — Current Runtime Efficiency Baseline

基于 2026-09-02 实测，当前 OpenAI 路径已观察到：

```text
Distinct Session IDs          正常
Gate Wait ≈ 0ms               已恢复
Cross-Session KV Reuse        已验证
Physical KV Prefix Match      已验证
ToolFP Mismatch Handling      正常进入严格过滤
Cancellation Cleanup          可观察闭环
```

当前仍需独立优化：

```text
Cold Prefill Throughput
Tool Fingerprint Reuse Coverage
Prefill Wait
Decode Throughput
Long-Context Memory Pressure
Decode Scheduling Contention
```

这些属于下一阶段局部 Execution / Resource Capability，不应重新改变 v4.5 的 Logical Identity 与 Global Physical KV 语义。

---

## v4.5 Addendum — Runtime Lifecycle Control Plane 收敛

本节记录 2026-09-04 对生命周期收敛代码的架构审核结论，以及 2026-09-05 按审核结论完成的重新收敛。对应收敛文档（SimiGo架构收敛.md）Commit 1-3：Lifecycle Model / State Machine / Lifecycle Coordinator。

### A. 审核背景

首轮收敛实现经审核确认以下缺陷（构成重新收敛的必要性证明）：

```text
P0-1  terminate() 绕过迁移表直接赋值，先于真实资源释放记录 RELEASED
P0-2  成功路径无 STREAMING/COMPLETING 迁移点，成功请求永不 RELEASED，
      且被统一记录为 "Request failed or cancelled"
P0-3  生命周期状态字典无界增长
P1-4  迁移表偏离收敛文档 §3（私自加入 CREATED→RUNNING、
      CANCELLING→RELEASED 跳过 DRAINING 等边）
P1-5  Text Completions / Responses 未接入注册与终止
P1-6  Trace 不落盘、身份字段恒空
P1-7  Stream 状态机与 Invariant Checker 为零调用死代码
P1-8  默认 MainActor 隔离使生命周期调用弹到主线程
P1-9  生命周期测试矩阵 0/17
```

### B. 重新收敛后的实现形态

唯一账本 + 唯一身份 + 唯一终止入口：

```text
RuntimeLifecycleCoordinator（被动账本）
 ├── states[requestID]      唯一身份 → RuntimeState
 ├── identities[requestID]  agentID + sessionID
 └── finish()               统一终止入口
```

两条合法收敛链（对应收敛文档 §2/§5）：

```text
成功：… → COMPLETING → COMPLETED → RELEASING → RELEASED
异常：任何状态(≠RELEASED) → CANCELLING → DRAINING → RELEASING → RELEASED
```

迁移表严格等于收敛文档 §3，唯一补充边：

```text
RUNNING → COMPLETING
（非流式请求无 STREAMING 阶段；生产路径接入 STREAMING 细分后
  回归 RUNNING → STREAMING → COMPLETING）
```

生命周期 Trace 事件集（[LIFECYCLE] 前缀，写入 native_mlx_trace.log）：

```text
REGISTER / REGISTER_DUPLICATE
STATE_TRANSITION / INVALID_TRANSITION / TRANSITION_UNKNOWN
FINISH_UNKNOWN / FINISH_DUPLICATE / FORCE_RELEASED / RELEASED
TASK_ENDED / TASK_ENDED_UNKNOWN
INVARIANT_TASK_ENDED_AFTER_RELEASE
```

### C. 与 v4.5 Core 的关系

Lifecycle Control Plane 是纯被动账本（Passive Ledger）：

```text
只记录状态与不变量观测
不拥有 / 不直接释放 Physical KV / Session / Task / Stream
真实资源释放仍由 NativeMLX 既有 Teardown 链执行
```

因此不改变：

```text
Physical KV 语义与 Reuse 规则
RuntimeLifecycleGate / SessionGenerationGate 双层门禁
Tool Protocol 与 Streaming Parser 边界
Stop / Teardown Invariant
```

实现为单文件 + 调用点接入，可整体回退。

### D. 关键设计裁决

```text
1. Stream 独立状态机暂不引入：SSE 出口既有 closed/canSend 防护已覆盖
   Emit-After-Close 不变量（收敛文档 §6 / Invariant 5）；
   存在等价防护时不得引入平行实现。
2. 独立 verifyInvariants API 删除；Invariant 1 以真实钩子落地：
   NativeMLX 请求任务收尾回报 noteRequestTaskEnded，
   若 RELEASED 先于任务收尾，Trace 记录
   INVARIANT_TASK_ENDED_AFTER_RELEASE。
3. 生命周期状态必须有界：RELEASED 条目按上限逐出，防止状态积累。
4. 六个 HTTP handler（chat / text / responses × streaming / non-streaming）
   全部接入 register → queued → running → finish；
   register 在身份确定之后 await，禁止 fire-and-forget 注册。
```

### E. 验证状态与准入结论

```text
xcodebuild BUILD SUCCEEDED
项目编译零警告（并发隔离警告清零）
启动自检（Release 生效）：
    正常完成 → RELEASED
    取消管道收敛 + 重复 finish 幂等
    RELEASED 终态拒绝迁移（Invariant 6）
    未知身份拒绝迁移（唯一身份）
```

按 §58 准入标准与铁律 35/36：

> **本轮收敛当前处于实验轨道。在完成收敛文档 §10 完整测试矩阵（17 场景）与实机 Benchmark / Stress（Task、KV Residency、Resident Memory、Swap 回归）验证之前，不视为 Stable Capability。**

仍属下一阶段的项：

```text
收敛文档 §10 完整 17 行测试矩阵（独立 Test Target）
STREAMING / COMPLETING 生产迁移点接入（NativeMLX 生成循环）
Trace 携带 kvTokens / memory（§8 完整信息集）
```

### F. Lifecycle Control Plane 新增铁律

91. **Request 必须先注册唯一身份；注册之后的一切状态变化必须经迁移表校验的 transition()，表外迁移一律 INVALID 并写入 Trace。**
92. **RELEASED 是唯一终态：RELEASED 之后拒绝一切迁移；任何请求无论正常完成、取消、错误或断连，最终必须收敛到 RELEASED。**
93. **所有终止路径统一汇入 finish()：成功走 COMPLETING→COMPLETED→RELEASING→RELEASED，异常走 CANCELLING→DRAINING→RELEASING→RELEASED；重复 finish 必须幂等且仅记录 Trace。**
94. **Lifecycle Control Plane 是被动账本：只记录状态与不变量观测，不拥有、不直接释放 Physical KV、Session、Task 或 Stream；真实资源释放仍由 NativeMLX 既有 Teardown 链执行。**
95. **账本不得先于真实资源收尾伪造 RELEASED；NativeMLX 请求任务收尾必须回报 noteRequestTaskEnded，RELEASED 先于任务收尾必须在 Trace 中暴露（Invariant 1 观测点）。**
96. **生命周期状态必须有界：RELEASED 条目必须按上限逐出，禁止无界状态积累。**
97. **生命周期 Trace 统一写入 native_mlx_trace.log（[LIFECYCLE] 前缀）；每条必须含 event 与 request，agent / session / from / to / reason 在已知时必须携带。**
98. **存在等价既有防护时不得引入平行状态机；Emit-After-Close 防护由 SSE 出口的 closed/canSend 检查承担。**
99. **RUNNING→COMPLETING 是迁移表的受审补充边（非流式请求无 STREAMING 阶段）；STREAMING 细分接入后，生产路径必须回归 RUNNING→STREAMING→COMPLETING。**
