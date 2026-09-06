# SimiGo 架构指引

> **本地高性能 AI Inference Runtime + Local/LAN 共享推理节点**
>
> External Agent 决定做什么，SimiGo 负责把模型算出来。

本文档是 SimiGo 的**唯一权威架构参考**，整合并取代原《架构白皮书 v4.5 Stable Foundation Baseline》《架构收敛》《BatchedDecode 实验轨》三份文档。全文以**铁律编号（1–99）**作为稳定引用锚点——代码评审、架构裁决均以其为准绳。

SimiGo 是运行在 Apple Silicon Mac 上的本地推理运行时：以菜单栏应用形态常驻，对外暴露 **OpenAI 兼容 API**（Chat Completions / Text Completions / Responses，Streaming / Non-Streaming），底层基于 **MLX** 完成真正的推理执行。

| | |
|---|---|
| 应用版本 | v1.1（`MARKETING_VERSION = 1.1`） |
| 架构基线 | **v4.5 Stable Foundation Baseline**（长期稳定参考架构，非过渡版本） |
| 平台 | macOS（Apple Silicon），SwiftUI 菜单栏应用（`LSUIElement`） |
| 核心依赖 | [mlx-swift](https://github.com/ml-explore/mlx-swift) 0.31.6 · [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) 3.31.4 · [swift-transformers](https://github.com/huggingface/swift-transformers) 1.3.3 |
| 测试 | `SimiGoTests`，21 用例（`xcodebuild test` 驱动） |
| 其他文档 | [部署指南.md](部署指南.md)（LAN 节点部署手册） |

---

## 目录

- [第一部分 产品定位与演化纪律](#第一部分-产品定位与演化纪律)
- [第二部分 逻辑平面：身份、隔离与物理复用](#第二部分-逻辑平面身份隔离与物理复用)
- [第三部分 工具协议（Tool Protocol Robustness）](#第三部分-工具协议tool-protocol-robustness)
- [第四部分 执行平面：协议、门禁、调度与取消](#第四部分-执行平面协议门禁调度与取消)
- [第五部分 资源平面：内存治理与准入](#第五部分-资源平面内存治理与准入)
- [第六部分 运行时生命周期控制平面](#第六部分-运行时生命周期控制平面)
- [第七部分 实验轨道：Controlled Batched Decode](#第七部分-实验轨道controlled-batched-decode)
- [第八部分 可观测性、性能与审计](#第八部分-可观测性性能与审计)
- [第九部分 终态架构模型](#第九部分-终态架构模型)
- [第十部分 铁律全集（1–99）](#第十部分-铁律全集199)
- [第十一部分 仓库结构与构建](#第十一部分-仓库结构与构建)

---

# 第一部分 产品定位与演化纪律

## 1.1 产品边界

SimiGo **负责**：

```text
Protocol · Tokenization · Prefill · Decode · Physical KV · Prefix Reuse
Streaming · Cancellation · Memory Governance · Observability
Inference Execution Scheduling · Long-Context Resource Governance
Tool Call Parsing / Normalization / Streaming
```

SimiGo **不负责**：

```text
Agent Planning · Agent Memory · Agent Decision
Tool Executor · Shell / SSH · Skill / Plugin Execution
```

核心边界：**Agent Runtime ≠ Inference Runtime**（铁律 2）。Tool Call 的执行属于外部 Agent / Tool Executor；SimiGo 只负责把模型输出解析、归一化、去重、审计后流式送达。

## 1.2 基线定义与演化管道

v4.5 是长期稳定参考架构，不是过渡版本。后续开发**不以 4.6 / 4.7 等版本持续重构**，而采用固定管道（铁律 1）：

```text
v4.5 Stable Foundation
        ↓
局部能力增量 → Benchmark → Invariant Audit → Stress Test → Stable Capability
```

**稳定性优先于理论完整性。** 当前基线状态：

```text
Logical State Isolation        正常
Physical KV Reuse              正常
Tool Fingerprint Safety        正常
Lifecycle / Cancellation       基本成立
Long-Context Memory Pressure   已受控于 Predictive Admission Control
Decode Execution Contention    已被压力测试观察
Tool Call Protocol Robustness  增强
```

## 1.3 新能力准入标准（铁律 35/36）

新的局部能力必须同时满足：

```text
不破坏 v4.5 Lifecycle
+ 不破坏 Physical KV Invariants
+ 存在 Benchmark 必要性
+ 可以局部实现
+ 可以回退
+ 不改变 Agent Runtime 边界
```

**禁止**未经验证直接进入 Core 的方向：新的 Agent Orchestrator、新的 Session Ownership Model、新的 Physical KV Semantic Key、Disk KV Cache Paging / Restore、未经 Benchmark 的 Continuous Batching、未经 Benchmark 的全局 Scheduler 重构。

优先进入实验轨道的方向：Scheduler Observability、Generation Gate Observability、Decode Quantum、Controlled Batched Decode、Prefill / Decode Arbitration、Scheduler Cancellation、Tool Protocol Robustness、Raw Tool Fallback。

---

# 第二部分 逻辑平面：身份、隔离与物理复用

## 2.1 身份模型

```text
Agent → Session → Logical Branch → Request
```

| 对象 | 职责 |
|---|---|
| Agent | 外部调用方身份 |
| Session | 连续逻辑上下文 |
| Logical Branch | Session 内对话血缘 |
| Request | 一次具体生成 |

执行事务 Key：`AgentExecutionKey = AgentId + SessionId + LogicalBranchId`。`logicalBranchId` 是一等公民，**Runtime 不得从 sessionId 猜测 Branch**（铁律 4）。

### 双 Key 粒度不变量

一个 Key 派生两个粒度，语义差是架构不变量：

```text
storageKey = AgentId / SessionId                  → Session state 与 KV 归属粒度
gateKey    = AgentId / SessionId / LogicalBranchId → Generation 串行化粒度
```

推论：**同 Session 的不同 Logical Branch 可以并发运行（gateKey 不同），但它们共享同一份 Session state（storageKey 相同）。** 由此约束：

1. 任何修改 `sessionCaches[storageKey]` 的代码，必须假设同 Session 的其他 branch 正在并发读写同一结构——Mutex 只保证数据结构不撕裂，不保证业务语义的 branch isolation（如 DegenerationState、Tool Semantic Progress 的跨 branch 可见性）。
2. 未来引入真正的 branch 并行（Batched Decode / 多 branch 并发生成）前，必须先为 SessionLogicalState 定义逐字段的并发契约，否则该字段必须收敛为 branch 私有。
3. 该不变量已由 `SimiGoTests/AgentExecutionKeyTests.swift` 以契约测试锚定（`testKeysDifferOnlyByBranch` 验证 storageKey 相同 / gateKey 不同）。

### Logical State 层

Logical State 属于 `Agent + Session + LogicalBranch`，包括：

```text
LogicalBranchState · DegenerationState · Tool Semantic Progress · Session Metadata
```

五态严格分离，不得混淆：

```text
Logical State ≠ Execution Scheduling State ≠ Physical KV State
             ≠ Resource Governance State  ≠ Streaming Parser State
```

特别地：**Streaming Tool Parser 的瞬时状态不属于 Session、Logical Branch 或 Physical KV**，只属于一次 Generation Round。

## 2.2 逻辑隔离 + 物理复用（核心模型）

```text
Session A ≠ Session B；Branch A ≠ Branch B；Logical State A ≠ Logical State B
（逻辑状态必须隔离）

Session A / B / C → Global Physical KV Pool → Exact Token Prefix Match
（物理计算可以复用）
```

> **这不是上下文串扰，而是 Physical Computation Reuse。Session 唯一性不得成为重复 Cold Prefill 的物理边界**（铁律 6/7/41）。

**复用规则**——Physical KV 只有同时满足以下条件才允许复用（铁律 8）：

```text
Same Model Generation + Same Tool Fingerprint + Valid Physical KV Revision
+ Physical Token Prefix Match + Physical KV Resident（否则降级 Cold）+ Memory Budget Allows
```

最终判断只依赖 `computeCommonPrefix(cachedTokens, promptTokens)` 的**实际 Token ID Sequence**；**不得**依据 SessionId / RequestId / ResponseId / Message Count / String Prefix / Agent Name / Tool Name 直接推断可复用。Tool Fingerprint 只能作为语义兼容过滤条件。

**Session 与 Physical KV 解耦（Addendum A）**：OpenAI Chat / Completions 层曾有 `messages.prefix(2) → SHA256 → inferred:<digest>` 的会话推导机制，2026-09-02 起正式废除：

```text
Explicit Session → Preserve Client Session
No Session       → 每个 HTTP Request 独立 request-scoped Session
```

实测验证：不同 Session（`s=b99cf3` / `s=9c685c` / `s=b84a00` / `s=7be176`）`[GATE] wait=0.0ms`，同时跨 Session 成功复用同一 Revision（`[KVR] cp=7646 d=2655 hit=74.2%`）。架构结论：**Session Identity 与 Physical KV Identity 必须解耦**；Session 表示逻辑上下文归属，Physical KV 表示已完成的物理计算结果；不得为了 KV Reuse 改变 Protocol Session Identity。这确立了 Goal Agent / Execution Agent A / B 各自独立 Logical Session、底层共享 Global Physical KV Pool 的 Multi-Agent 形态。

## 2.3 Physical KV 生命周期

标准路径：

```text
Prompt → Tokenize → Global Physical KV Candidate Search → Tool Fingerprint Filter
       → Residency Filter → Exact Prefix Match → Longest Common Prefix
       → Predictive Admission Control → Cold / Delta Prefill → Decode
       → Commit New Physical KV Revision
```

| 路径 | 触发条件 | 流程 |
|---|---|---|
| **Cold Prefill** | 无可用 / 已驱逐的 Physical KV | Admission Control → 全量 Prefill → Decode → Commit |
| **Warm Prefill** | 命中 resident Revision | Common Prefix → Admission Control → KV Copy / Trim → Delta Prefill → Decode → Commit |
| **Exact Match** | `commonLen == promptTokens.count` | **不得再次完整 Prefill**；必要时只做 last-token reprime，然后进入 Decode（铁律 12/13） |

Delta Prefill 必须从 commonLen 开始；Trim 必须同步作用于 Physical KV 与 Ledger（铁律 11）。

## 2.4 Physical Token Ledger

> **Physical Token Ledger 是 Physical KV 的物理事实来源**（铁律 9）。

基本关系：

```text
Prompt Tokens + Actual Generated Tokens → Physical Token Sequence ↔ Physical KV
```

必须保持 Token Sequence 与 KV 实际逻辑深度同步；Commit 必须保存 Prompt Tokens + **Actual** Generated Tokens，禁止保存 Expected / Predicted / String-reconstructed / Incomplete Tokens（铁律 14）。取消、失败或未完成的 Generation **不得提交未完成 Physical KV**（铁律 24）。

## 2.5 Physical KV Revision

一个 Logical Branch 可以产生多个 Revision，每个 Revision 含双层属性：

| 层 | 属性 |
|---|---|
| Semantic Layer | `ownerStorageKey`（agent/session 归属）· `logicalBranchId` · `toolFingerprint` · `physicalTokens` |
| Physical Layer | `kvCache` · `resident` · `estimatedResidentBytes` |

> **Physical KV Revision 是可复用的计算结果（Reusable Compute Result），不是 Session 所有权**（铁律 15）。

资源不足触发驱逐时只释放 Physical Layer（`releasePhysicalMemory()`，`resident = false`），**逻辑账本 `physicalTokens` 必须保留**。被驱逐的 Revision 仍是逻辑上有效的 Revision Record，未来命中时走 Cold Prefill 并记录 `why=evicted`——这就是 **Lossless Eviction**（铁律 45/88）：Eviction = 释放 Physical Residency，不是 Delete Semantic Revision。

**同 owner 无损替换**（2026-09-06 审计裁决）：全局池选源命中时仅当源 revision 与请求**同 ownerStorageKey 且同分支**，才允许在深拷贝取代后立即释放源的物理层（串行链路下一轮只复用最新 revision）；跨会话同名分支源必须保留——`PhysicalKVRevision` 自此携带 `ownerStorageKey`，禁止凭同名分支号误判归属（否则 LAN 多用户默认分支同为 `main` 时发生跨会话驱逐乒乓）。选源与归属裁决由 `NativeMLX.selectKVSourceLocked`（纯函数）承担，契约测试见 `KVSourceSelectionTests`。

## 2.6 Revision Count 与 Memory Budget 正交

```swift
maxPhysicalKVRevisions = 16   // RuntimeTuning.swift
```

其语义严格限定为 **Revision 遍历、历史保留与防泄漏数组的上限**（铁律 83）。它**不是** Memory Budget / KV Memory Limit / RSS Limit / Swap Limit / Prefill Admission Limit，不能被解释为"最多 16 个 KV 就安全"，也不能替代 Predictive Admission Control——`16 × 4K Revision` 可能完全可接受，`3 × 32K Revision` 可能已需大量 Eviction（铁律 59/84/90）。

| Revision Count 负责 | Memory Governance 负责 |
|---|---|
| Revision 历史边界 | Residency |
| 遍历成本 | Eviction |
| 状态泄漏防护 | Prefill Admission / Physical Memory Pressure |

## 2.7 Long-Context 资源治理

```swift
longContextThreshold = 16384
```

```text
Prompt < 16K → Normal Admission Policy
Prompt ≥ 16K → Long-Context Admission Policy → Stronger Eviction（在普通释放目标后额外约 2 GiB 防御性空间）
```

该策略只改变 Residency Policy 与 Eviction Intensity，**绝不改变 Physical KV Semantic Reuse**（铁律 56/57/89）：Long Context 不是新的 KV Semantic Key，也不禁止 Physical Reuse；Physical Token Ledger 绝不能被删除。

实机基线（§56）：Prompt 12K → 34K 递增实测中，Global Physical KV Reuse 持续存在，Decode Throughput 随上下文增长下降，单 Agent Long Context 可产生巨大 Swap Pressure。因此 **Multi-Agent Contention 与 Long-Context Memory Pressure 必须分开验证**（铁律 60）。

---

# 第三部分 工具协议（Tool Protocol Robustness）

## 3.1 Tool Fingerprint

```text
Tool Schema → Canonical Representation → SHA256 → toolFingerprint
```

Physical KV 复用必须满足 `requestedToolFingerprint == revision.toolFingerprint`；Tool Schema 变化时旧 KV 语义不兼容，其 Physical Residency 可被释放。但 **Tool Fingerprint 只参与 Physical KV 语义兼容性判断**（铁律 16），不得控制 HTTP、Connection、Generation Controller、Agent Decision、Tool Execution、Execution Scheduler。

## 3.2 双路径架构

Tool Call 是**模型输出**（铁律 17）。SimiGo 可以 Parse / Normalize / Stream / Deduplicate / Audit，但**不执行 Tool**。

| 路径 | 来源 | 处理 |
|---|---|---|
| **Primary** | MLXLMCommon 直接生成 `Generation.toolCall` | → `ParsedToolCall` → `onToolCall` |
| **Fallback** | `Generation.chunk` 中出现 `<tool_call>...</tool_call>` | → `RawToolCallStreamParser` 增量解析：Ordinary Text → StreamTokenFilter → onChunk；Raw Body → ParsedToolCall → onToolCall |

**Raw Parser 归属约束**（铁律 66）：不属于 Session State / Logical Branch State / Physical KV / Scheduler State，只属于当前 Generation Round，绝不能跨 Generation、Session、Logical Branch 复用状态。

## 3.3 增量解析与通道互斥

**增量不变量**（铁律 67）：`<to` / `ol_` / `call>` 这类被 decode chunk 任意切分的标签必须正确解析，因此禁止 `text.contains("<tool_call>")` 式的完整解析算法，必须维护 Parser Buffer + Parser State 直到标签完整形成。

**通道互斥**（铁律 68）：检测到 `<tool_call>` 后，Tool Call Body 不得继续进入 `onChunk()` 或普通 StreamTokenFilter——否则会产生 `assistant.content = "<tool_call>..."` 而没有 `tool_calls` 字段。**Tool Protocol 与 Ordinary Text Channel 必须互斥。**

## 3.4 语义规则

| 规则 | 内容 |
|---|---|
| **Arguments 语义**（铁律 18/74） | `{}` 是合法零参数 Tool Call，不得因参数为空删除；但 `{ "name": "get_status" }` 缺失 arguments **不是**合法的自动补空——`Missing arguments ≠ Empty arguments`，SimiGo 不得自行猜测 |
| **Fail-Fast**（铁律 19/73） | 历史 Tool Call / Result 出现 Invalid function name、Malformed arguments、Invalid type、Invalid protocol shape、Unparseable JSON 时必须 Fail-Fast；不得猜测 name、猜测 arguments、把 malformed JSON 转成 `{}`、静默丢弃 Tool Call |
| **Dedup**（铁律 69） | 同一 Generation Round 内 Structured 与 Raw Fallback 共用 `attemptedToolSignatures`（Tool Name + Canonical Arguments）；语义相同只 forward 一次，重复项记录 `[TOOL DEDUP]` |
| **Partial Dispatch**（铁律 21） | 必须保留 `attemptedSignatures` 作为本轮后续比较基线；不得把部分派发伪造成 all tools forwarded，也不得自动生成虚假 Tool Result |
| **Parse Failure**（铁律 70/71） | Raw `<tool_call>` 解析失败时 `Tool Parse State = Failed`，**不得**被解释为 Plain Text Generation；必须阻止 Physical KV Commit |

## 3.5 Tool/KV Commit Invariant（关键不变量）

以下状态禁止存在（铁律 72）：

```text
rawToolCallDetected = true + structuredToolCallCount = 0 + forwardedToolCount = 0 + KV Commit = true
```

原因链：错误 Tool Call 输出 → 普通 assistant text → Logical History 污染 + Physical Token Ledger 污染 + Physical KV 污染。必须在 Generation → Commit 边界阻断（铁律 75：**Tool Protocol Valid 是 Physical KV Commit 的必要条件**）。完整 Commit 条件见 [4.6 节](#46-physical-kv-commit)。

## 3.6 Degeneration 状态机

Degeneration State 属于 **Logical Branch**，不属于 Tool Parser 或 Physical KV（铁律 20）。状态流程：

```text
preview() → recordBlocked() → commitForwarded() → resetOnPlain()
核心不变量：1 Generation Round → 0 or 1 State Transition
```

规则：真正无 Tool Call → `resetOnPlain()`；有效 Structured Tool Call → preview / forward / commit；Raw Tool Call Parse Failure → Fail-Fast，不得被当成 Plain Round。检测依据可以是 Tool Signature / Tool Result / Semantic Progress，达到阈值后输出 `[BRANCH DEGENERATION BLOCKED]`。Raw Parser 不改变 Degeneration 语义——它只负责把 raw 协议表达转换成 ParsedToolCall，是否重复/退化由 Logical Branch Degeneration State 决定。

## 3.7 解耦与 Thinking

**Tool Parsing 与 Physical KV 解耦**（铁律 76/77）：Parser 只 Parse / Normalize / Emit，不拥有 Physical KV、KV Selection、KV Commit、KV Eviction；KV 仍只依据 Model Generation / Tool Fingerprint / Token Exact Match / Revision Residency / Memory Governance 决定。

**Thinking**：当前稳定基线 `disableThinking = true`。Protocol 可接收 `enable_thinking` / `reasoning.effort`，但必须转换为 Model Configuration → Chat Template → Generation，**不能通过生成后文本删除冒充关闭 Thinking**。

---

# 第四部分 执行平面：协议、门禁、调度与取消

## 4.1 Protocol Layer

HTTPServer 是**薄协议网关**，只负责：HTTP / JSON / SSE / Request ID / Connection / Cancellation / Protocol Normalization / Identity Extraction / Responses State（铁律 3）。不负责 Physical KV Selection、KV Trim、Generation Policy、Tool Execution、Agent Decision、Inference Execution Scheduling。OpenAI Chat / Responses 等协议最终汇聚为 **Canonical Generation Request**（铁律 40：Protocol Compatibility 不得污染 Generation Lifecycle）。

## 4.2 Responses API

Responses API 是 **Protocol Compatibility Layer**。`responseId` / `previous_response_id` / `metadata` 是协议状态，不是 Physical KV State（铁律 31/32）：

```text
正确：previous_response_id → Canonical Context → Tokenization → Global Physical KV Match
禁止：previous_response_id → 直接指定 Physical KV Revision
```

`function_call` / `function_call_output` 可转换为 Canonical Message（`assistant.tool_calls` / `tool.tool_call_id`），但这属于 Protocol Normalization 而非 Physical KV Mapping；历史进入 NativeMLX 前必须通过 Message Normalization + Historical Tool Call Validation。

## 4.3 Streaming 与 Flush 顺序

Streaming 负责 Generated Output → Incremental Parsing → Text / Tool Call → SSE，必须保证 Event Order、Completion State、No Tail Loss、Cancellation Consistency。**Streaming Parser 不得反向控制 Physical KV、Generation Gate、HTTP Lifecycle、Execution Scheduler Policy**（铁律 30）。

Generation 完成后 flush 顺序固定（铁律 78）：

```text
Generation End → Raw Tool Call Parser Flush → Ordinary Stream Token Filter Flush
```

不得颠倒——raw `<tool_call>` 尚未完成时不能被 Ordinary Text Filter 当成尾部普通文本。Generation 结束仍存在未闭合的 `<tool_call>` 必须判定为 **Tool Protocol Failure**（铁律 79），而不是 Ordinary Assistant Text。

## 4.4 两层并发与生命周期门禁

| 层 | Gate | 职责 |
|---|---|---|
| Tier 1 | `RuntimeLifecycleGate` | `start()` / `stop()` 生命周期互斥：Runtime N 完全结束后才能进入 Runtime N+1，不得出现 Old + New Runtime 生命周期重叠（铁律 26） |
| Tier 2 | `SessionGenerationGate` | 同一 Logical Branch（`gateKey`）内严格串行：Read State → Preview → Generate → Tool Dispatch → Commit / Compensation（铁律 25）；跨 Key 并行；保证 **Exactly One Acquire → Exactly One Release** |

Shutdown 固定顺序：`server.stop → prefillScheduler.cancelAll → gate.beginShutdown → cancel request/generation tasks → await tasks → gate.awaitDrain`。drain 永不悬挂、shutdown 后 acquire 必被拒绝的不变量由 `SessionGenerationGateTests` 的千轮 acquire/shutdown 交替压测钉死。

## 4.5 Scheduler

两个 Gate 之下可存在 **Inference Execution Scheduler**：Runnable Request Management / Prefill Scheduling / Decode Scheduling / Decode Batching / Execution Fairness / Arbitration。它属于 Execution Plane，不拥有 Agent / Session / LogicalBranch State（铁律 51）。

- **PrefillScheduler** 原则：同一 Logical Branch 保持生成顺序；全局 Prefill 并发受资源预算控制；Decode 不重复获取不必要的 Prefill 独占；Global Physical KV Reuse 减少重复 Prefill。
- **Prefill / Decode Arbitration**：大 Delta 可局部 Chunking——`Large Delta → Prefill Chunk → Arbitration → Decode Epoch → Next Prefill Chunk`。`prefillChunkSize` 当前基线 1024，可比较 256/512/1024，**不得未经 Benchmark 固化新的理论最优值**（铁律 37）。
- **关键区分**（铁律 44）：Logical Branch 串行 ≠ Model Compute 全局串行；不同 AgentExecutionKey 可以共享 Model Execution。

## 4.6 Physical KV Commit

Commit 必须同时满足（铁律 75）：

```text
Generation Complete + Not Cancelled + Not Interrupted + Tool Protocol Valid
+ No Degeneration Circuit Break + All Forwarded Tool Calls Valid
+ Valid Prompt + Valid KV Cache
```

Commit 内容 = Prompt Tokens + Actual Generated Tokens → Physical Token Sequence（铁律 14）。禁止保存 Expected / Predicted / String-reconstructed / Incomplete Tokens / Uncommitted Tool Text。Raw Tool Parse Failure 必须导致 `KV Commit = 0`。

## 4.7 KV Selection 与 Global Pool

Candidate Search 顺序：`Global Pool → Trimmable Cache Filter → Resident Filter → Tool Fingerprint Filter → Physical Token Prefix Compare → Longest Common Prefix`。**不使用** Session ID / Request ID / Response ID / Tool Name / Message Count 作为 Physical KV 地址（铁律 7）。Trimmable 与 Resident 过滤均在候选阶段前置淘汰（铁律 8：非驻留源降级 Cold）——evicted revision 的长前缀不得挤掉本可安全复用的较短 resident 源。

> **Trimmable Cache 门禁**：混合注意力架构（如 qwen3_5_moe 的线性注意力层持 `MambaCache` recurrent state）的 cache 不可按前缀截断——copy 携带全量 state、trim 为 no-op，部分前缀复用会让线性层在包含源后缀的状态上续算，静默污染生成且长度对账不可见。非全可裁剪（`isTrimmable`，同 mlx `canTrimPromptCache` 谓词）的 revision 不作复用候选（宁可冷启，不毒化）；其 revision 仍正常提交/驱逐，受 Memory Governance 约束。

> **Global Physical KV Pool 是计算结果共享池，不是 Conversation Memory / Session Store / Response Store / Agent Memory**（铁律 42）。可跨 Agent / Session / Logical Branch 复用，只要 Model + Tool Fingerprint + Token Prefix + Residency + Memory Governance 全部满足（铁律 43）。Global Selection 可以共享；Resource Budget、Residency 与 Eviction 独立进行（铁律 53）。

## 4.8 Cancellation

```text
Client Disconnect / Cancel → Cancellation → Generation Cancel → Stop Stream
→ Skip unfinished Physical KV Commit → Release Temporary Resources → CANCELLED
```

- Cancelled / Completed Request 不得重新进入 Scheduler Runnable Set（铁律 46）；一个 Request 在同一 Scheduling Epoch 不得重复参与 Decode（铁律 47）。
- Cancelled Generation 不得把 `actualGeneratedTokens` 作为新的完整 Revision 提交（铁律 24）。
- Tool Call 与 Cancellation（铁律 22）：Cancellation 发生在 RawToolCallParser 或 Structured Tool Call 尚未完成 dispatch（`forwardedToolCount == 0`）时，不得伪造 Tool Completed；Partial Dispatch 仍保留 `attemptedSignatures` 基线。

## 4.9 Stop / Teardown Invariant

Stop 必须按固定顺序（铁律 27）：

```text
Close Admission → Cancel Waiters → Drain Owners → Release Physical KV → Clear Memory → Verify Runtime State
```

不得直接清空 active ownership（铁律 28）；Old Runtime 完全结束后才能启动 New Runtime。`Memory.clearCache()` 只允许作为释放显存引用的辅助手段，不得作为主要 Lifecycle 拦截动作（铁律 64）。

---

# 第五部分 资源平面：内存治理与准入

## 5.1 Runtime Memory Governance

```swift
inferenceMemoryLimit = 22 GiB    // admissionMemoryLimitBytes
inferenceCacheLimit  = 4 GiB
```

并继续保持 `Memory.memoryLimit` / `Memory.cacheLimit` 运行时限制。Resource Governance 的主要目标：**在 Prefill / Allocation 发生前，判断新增计算是否会使 Runtime 自身进入危险状态**（铁律 29：Cache 必须有界，进入 Prefill 前必须经过 Predictive Admission Control 严格测算）。

## 5.2 Predictive Admission Control

SimiGo 不采用单纯 RSS 作为 Admission 基础，而是保留 Runtime 自有物理账本：

```text
Projected Memory = Current Resident KV Bytes + Projected KV Delta + Execution Working Set + Safety Margin

Execution Working Set = 3 GiB    Safety Margin = 1 GiB    Admission Limit = 22 GiB
```

若 `Projected Memory > Admission Limit` → 先 **Lossless Eviction**，再允许 Prefill。当前实现补充：分支命中时副本 KV（copied KV）计入投影（源 Revision 仍 resident 时只计差额）；eviction 后仍超预算则硬拒绝请求（`RuntError.admissionExceeded`），止住 OOM / 权重页出导致的 decode 掉速。权重感知预算：权重体积实测前 resolve HF snapshot 符号链接；全部调参常量集中在 `Lifecycle/RuntimeTuning.swift`，杜绝裸字面量（铁律 35/63）。

## 5.3 RSS 与 Swap 的架构定位

必须持续观测 `residentMemory` / `virtualMemory` / `systemSwapUsed`，但（铁律 61/86/87）：

- **System RSS 与 Internal Physical KV Ledger 是两个不同维度**：RSS 可能包含 Model Weights / MLX Allocator / Metal Mapping / Swift Heap / Framework Memory / Other Runtime Memory，不能直接等价于 Physical KV Size，也不能把 RSS 原值代入 Admission Formula。
- **System Swap 是诊断指标**：不等于 KV Size，不直接进入 Admission Formula；用途是观察 Unified Memory 压力、识别 Runtime / OS thrashing、判断 Admission 有效性、验证请求生命周期结束后的恢复趋势。
- Agent / Request 结束后必须验证 Task、KV Residency、Resident Memory 与 Swap 趋势，而非仅看逻辑状态（铁律 62）。

---

# 第六部分 运行时生命周期控制平面

源自架构收敛设计（8 步模型），实现形态经 2026-09-04 架构审核后重新收敛。核心目标：

> **每一个 Request 从创建到释放，都有唯一身份、明确状态、明确 Owner、合法状态迁移、完整 Trace，并且任何异常最终都能收敛到 Release。**

## 6.1 对象模型与所有权原则

正确结构——Runtime 拥有资源，Agent 只是参与者：

```text
Runtime
 ├── Request
 │    └── GenerationTask
 │          └── Session
 │                └── KV
 └── Agent
       └── observes / drives Request
```

**Agent 不应该拥有底层 Runtime**（不得形成 `Agent → Session/KV/Task/Stream` 的所有权链），否则 Agent 退出后 Task / KV / Session 仍存活，SW 指标不下降。Agent 只做五件事：

```text
submit Request · receive Stream · send tool call · request cancellation · observe lifecycle
```

> **Agent 可以请求 Runtime 结束，但是不能自己决定 Runtime 如何释放。** 调用 `agent.cancel(requestID)`，而不是 `agent.session.remove()` / `agent.task.deregister()` / `agent.kv.release()`。这样 Agent 即使 exit / crash / disconnect，Runtime 仍能完成 CANCELLING → DRAINING → RELEASING → RELEASED。

释放顺序必须与创建顺序相反：

```text
Request → Task cancel → Stream drain → KV detach → Session release → Task release → Request release
```

## 6.2 状态机与合法迁移表

统一 `RuntimeState`，两条收敛链：

```text
成功链：CREATED → QUEUED → RUNNING →（STREAMING）→ COMPLETING → COMPLETED → RELEASING → RELEASED
异常链：任何状态（≠RELEASED）→ CANCELLING → DRAINING → RELEASING → RELEASED
```

合法迁移表（表外一律 `INVALID_TRANSITION` 并记录 Trace）：

| 当前状态 | 允许迁移到 |
|---|---|
| CREATED | QUEUED |
| QUEUED | RUNNING / CANCELLING |
| RUNNING | STREAMING / COMPLETING / CANCELLING |
| STREAMING | COMPLETING / CANCELLING |
| COMPLETING | COMPLETED / CANCELLING |
| COMPLETED | RELEASING |
| CANCELLING | DRAINING |
| DRAINING | RELEASING |
| RELEASING | RELEASED |

核心规则：

- **RELEASED 是唯一终态**：之后拒绝一切迁移（`RELEASED → RUNNING` 等一律 INVALID）（铁律 92）。
- **所有终止路径统一汇入 `finish()`**：成功走 COMPLETING → COMPLETED → RELEASING → RELEASED，异常走 CANCELLING → DRAINING → RELEASING → RELEASED；重复 finish 幂等且仅记录 Trace（铁律 93）。
- 一切状态变化必须经迁移表校验的 `transition()`，不得直接赋值（铁律 91）。
- `RUNNING → COMPLETING` 是受审补充边——非流式请求无 STREAMING 阶段；STREAMING 细分接入生产路径后须回归 `RUNNING → STREAMING → COMPLETING`（铁律 99）。

## 6.3 实现形态：被动账本

```text
RuntimeLifecycleCoordinator（被动账本）
 ├── states[requestID]      唯一身份 → RuntimeState（RELEASED 条目按上限逐出，状态有界——铁律 96）
 ├── identities[requestID]  agentID + sessionID
 └── finish()               统一终止入口
```

**被动账本原则**（铁律 94）：只记录状态与不变量观测，不拥有、不直接释放 Physical KV / Session / Task / Stream；真实资源释放仍由 NativeMLX 既有 Teardown 链执行。**账本不得先于真实资源收尾伪造 RELEASED**（铁律 95）：NativeMLX 请求任务收尾必须回报 `noteRequestTaskEnded`，若 RELEASED 先于任务收尾，Trace 记录 `INVARIANT_TASK_ENDED_AFTER_RELEASE`（Invariant 1 的真实钩子观测点）。

六个 HTTP handler（chat / text / responses × streaming / non-streaming）全部接入 `register → queued → running → finish`；register 在身份确定之后 await，禁止 fire-and-forget 注册。

## 6.4 关键设计裁决

1. **Stream 独立状态机暂不引入**（收敛设计 §6）：SSE 出口既有的 `closed` / `canSend` 防护已覆盖 Emit-After-Close 不变量（收敛设计 Invariant 5）——**存在等价既有防护时不得引入平行实现**（铁律 98）。
2. **独立 `verifyInvariants` API 删除**：Invariant 以真实钩子落地（见 6.3）。
3. 生命周期状态必须有界（铁律 96）。
4. Trace 统一写入 `native_mlx_trace.log`（`[LIFECYCLE]` 前缀），每条必含 `event` 与 `request`；`agent / session / from / to / reason` 已知时必须携带（铁律 97）。

重新收敛的必要性（首轮实现审核确认的缺陷）：terminate() 绕过迁移表伪造 RELEASED、成功路径永不 RELEASED、状态字典无界增长、迁移表私自加边、Text/Responses 未接入、Trace 不落盘、死代码、MainActor 隔离弹跳、测试矩阵 0/17。

## 6.5 生命周期 Invariant 与测试矩阵

七条核心 Invariant：

```text
1. RELEASED request    ⇒ no active GenerationTask
2. RELEASED task       ⇒ no active Stream
3. released Session    ⇒ no attached KV
4. active GenerationTask ⇒ valid Session
5. stream CLOSED       ⇒ cannot emit token
6. RELEASED            ⇒ no future state transition
7. Agent EXITED        ≠ Runtime RELEASED
```

最终目标：**无论发生什么，活跃 Runtime 最终都必须收敛到 0 个不可达对象**。诊断视角——一条请求应能直接看到完整生命周期时间线（CREATED → … → RELEASED + Task/Session/Stream/KV/Memory 收尾状态）；若 Agent 已退出而 SW 指标未下降，Invariant Checker 应能报出 `RUNTIME INVARIANT VIOLATION`。

17 场景测试矩阵（生命周期测试不只要测"正常请求能不能生成"）：

| 场景 | 预期 | 场景 | 预期 |
|---|---|---|---|
| 正常完成 | RELEASED | Model error | RELEASED |
| 用户取消 | RELEASED | Prefill error | RELEASED |
| Agent 退出 | RELEASED | Decode error | RELEASED |
| Client 断开 | RELEASED | OOM | RELEASED |
| Stream error | RELEASED | Timeout | RELEASED |
| Tool call 中断 | RELEASED | KV reuse 失败 | RELEASED |
| Session 过期 | RELEASED | 重复 cancel | 不崩溃 |
| 重复 release | 不崩溃 | stream 重复 close | 不崩溃 |
| token after close | 丢弃 + Trace | | |

**落地状态**：

| 收敛设计章节 | 状态 |
|---|---|
| 对象模型 / 状态机 / 迁移表 / Coordinator / Trace | ✅ 已落地（Commit 1–3 + 5） |
| Invariant Checker | ✅ 以真实钩子落地（`noteRequestTaskEnded`） |
| Stream 独立状态机 | ⛔ 裁决不引入（等价防护已存在，铁律 98） |
| §10 完整 17 行测试矩阵（实机） | ⏳ 下一阶段 |
| STREAMING / COMPLETING 生产迁移点接入、Trace 携带 kvTokens / memory | ⏳ 下一阶段 |

---

# 第七部分 实验轨道：Controlled Batched Decode

**定位**：LAN 多用户并发吞吐——把"GPU 时间分片"升级为"批内真并发"。**纪律**：实验轨道准入（§1.3）/ 铁律 35（Benchmark 背书）/ 铁律 37（一次一个变量）/ 未验证不进 Core。

## 7.1 必要性证明（2026-09-05 实测）

| 场景 | 每路 decode | 聚合 |
|---|---|---|
| 单流 | 28–33 tok/s | 28–33 |
| 3 流并发（1×29.8K Agent + 2×200B 测试） | **7–10 tok/s** | **≈25（恒定）** |

聚合吞吐 ≈ 单流总量：GPU 按 token 时间分片，每流解码都完整读取激活权重（MoE 激活 3B ≈ 2GB+/token），N 路并发 = N× 权重读取。内存侧无压力（weight-aware budget + KVTRIM 后 rss 7.1G / sw 1.59G 平稳）——**唯一瓶颈是带宽复用**。

## 7.2 依赖侦查结论（Phase 0，实测包源码）

| 项 | 结论 | 影响 |
|---|---|---|
| `ModelContainer.generate` | prefill 独占（`context.read`），**decode 多流并发**（权重只读） | 并发调度无需改依赖 ✓ |
| `KVCache` 协议 | 单一 `offset` + 均匀 causal mask | 通用连续批处理需自定义 BatchedKVCache |
| SDPA / MoE gate | batch 原生（B 维独立注意力；gate 逐 token） | 前向数学 batch-safe ✓ |
| RoPE | `applyRotaryPosition` 支持 `.batch(MLXArray)` 逐序列位置 ✓ | — |
| 投机解码 | 基建齐备；本模型无 MTP 头 | 需外挂 draft，仅单流加速 |

## 7.3 技术路线与阶段

- **A（主线）Pad-to-align 批处理**：自建 `BatchedKVCache`（K 序列 pad 至组内 S_max）+ 逐序列 RoPE + 自建 decode loop。预估 400–600 行 + 模型前向手术。
- **B（否决）同长对齐合并**：LAN 场景几乎不自然对齐，无价值。
- **C（替代，单流）投机解码**：需外挂 draft 模型，tokenizer 兼容性风险；不解决并发分片，挂起。

Phase 1（✅）并发观测基建：`[GENERATION START] decodeStreams=N`、State 计数、峰值统计——三流实测 `decodeStreams=3` 可见。

## 7.4 Phase 2 NO-GO 门（架构止损）

对 mlx-swift-lm 3.31.4 包源码逐层核查确认：

```text
1. Nail-Qwen3.6 / Tiel-Coder 均为 Qwen3_5MoeForConditionalGeneration
   = Mamba(线性注意力) + FullAttention 混合架构
2. FullAttention 层支持逐序列 RoPE 位置 ✓
3. 线性注意力层使用 MambaCache（递归状态），无 batch 语义，
   自定义 BatchedKVCache 无法覆盖 Mamba 层（状态语义在包内部）
4. 模型侧不消费 LMInput.Text.mask（左填充掩码无注入点）
5. 结论：不等长批处理需要上游（mlx-swift-lm）为混合架构提供
   batch 语义的 MambaCache + 逐序列 RoPE 管线 —— 属上游工程
```

按铁律 82（正确性优先）与"先证明再固化"：**在依赖提供 batch 语义前，不实施批处理解码**。带病上线（静默输出污染）的代价高于收益。Phase 3/4（pad-to-align / 双客户端 Stress）随 Phase 2 阻断；依赖升级/上游合入后重开。

**回退设计**：Phase 2 起全部代码置于 `RuntimeTuning.batchedDecodeEnabled`（默认 false）之后，删除即回退；不改 Logical State Model（铁律 50）。

**非目标**：不做 PagedAttention 级 KV 分页管理；不动 SessionGenerationGate 语义（铁律 25/26）；不为本能力改动 Protocol 层。

## 7.5 修订后的 LAN 容量路线

```text
现状（KVTRIM + weight-aware budget 已落地）：
    1–2 路 30K Agent 并发 + 轻用户，每路 25–33 tok/s
扩容杠杆（按可行性排序）：
    1. 多节点：第二台 Mac 同构部署 + 客户端路由（线性扩容，零代码）→ 见部署指南
    2. 换 KV 更轻模型（dense 7–14B 4bit，KV/token 降 3×，并发 ×3）
    3. 上游依赖升级后重开本实验轨 Phase 2
```

---

# 第八部分 可观测性、性能与审计

## 8.1 Observability 事件集

主 Trace：`~/.simigo/logs/native_mlx_trace.log`，必须能够证明 Runtime 实际发生了什么。

| 域 | 事件前缀 |
|---|---|
| Scheduler / Generation | `[REQUEST]` `[GENERATION START]` `[GATE]` `[PREFILL WAIT]` `[CANCEL REQUEST]` `[CANCELLED]` |
| Tool | `[TOOL]` `[RAWTOOL]`（chunk 中发现 raw 协议）`[STOOL]`（最终形成 Structured）`[TDUP]` `[TDROP]` `[TPFAIL]`（解析失败） |
| KV | `[KV DIAGNOSTIC]` `[KV SELECT]` `[KV COPY]` `[KV COMMIT]` `[KV MISS]` |
| Resource Governance | `[ADMISSION]` `[ADMISSION WARN]`（另含 `[ADMISSION OBS]` / `[ADMISSION BLOCK]`） |
| Lifecycle | `[LIFECYCLE]`（REGISTER / STATE_TRANSITION / INVALID_TRANSITION / RELEASED / INVARIANT_TASK_ENDED_AFTER_RELEASE 等） |
| Memory | `[MEM]` `[SUM]`（RSS / Virtual / Swap / Revision Count / Physical Token Count） |

Long Context 应能观察：Prompt Token Count、Delta Token Count、Projected Memory、Evicted Revision Count、Estimated Freed Bytes。**RSS / Swap 是 Observation，不等于 Internal KV Ledger。**

**Tool Observability 最低信息集**：每次 Tool Protocol 事件至少关联 `requestId / session / branch / toolName / toolCallCount / rawToolCallDetected / forwardedCount`；故障时必须能区分：No Tool Call / Structured / Raw Fallback / Raw Parse Failure / Dedup / Degeneration Block 六种情况——禁止出现无法区分 `tool=0` 到底是"真的没有 Tool"还是"Tool Parser 失败"（铁律 80/81）。

## 8.2 Performance Principle

Physical KV Reuse 是手段，不是最终 KPI（铁律 33）。每次优化必须同时观察：

```text
TTFT · Prefill tok/s · Decode tok/s · Aggregate / Per-request Decode tok/s
Scheduler Wait · Total / Tail Latency · Resident Memory · System Swap
Physical KV Residency · Tool Parse / Dispatch Correctness · Stability
```

最终标准：**End-to-End Latency + Stability**。反例：Reuse ↑ 而 TTFT ↓、Decode ↓↓、Swap ↑↑、Total Latency ↑ → **优化失败**；Tool Parser Accuracy ↑ 但 Latency ↑↑、Memory ↑↑、Stream Stability ↓ → 不得进入 Stable Capability（铁律 34/55）。

## 8.3 Benchmark 基线

Level 0–10 重点增加：Tool Protocol Correctness / Raw Fallback Correctness / Malformed Fail-Fast / Dedup Correctness / Tool-KV Commit Invariant。Admission 重点监控：`[ADMISSION]` 触发频次、Eviction Count、Estimated Freed Bytes、KV Residency、RSS、Swap。

**Tool Protocol 最低 Benchmark 集**：

| Test | 输入 | 期望 |
|---|---|---|
| A Structured | `Generation.toolCall` | `tool=1 forwarded=1 kv=1` |
| B Raw Fallback | `chunk("<tool_call>...")` | `raw=1 structured=1 forwarded=1` |
| C Chunk Split | `"<to"` `"ol_"` `"call>"` | 仍正确生成 ParsedToolCall |
| D Malformed | 非法 JSON | `TPFAIL kv=0` |
| E Incomplete at EOS | 未闭合标签 | `TPFAIL kv=0` |
| F Duplicate | 语义重复调用 | `TDUP forwarded once` |

## 8.4 审计与效率基线

**Invariant Audit**（§53）禁止状态：`rawToolCallDetected=true + turnToolCalls=0 + KV Commit=true`；Raw Tool Protocol Failure + Normal Plain State Transition；Malformed Tool Call + Assistant History Normalization；Incomplete Tool Call + onChunk；Tool Parser State + Session/KV State Persistence。

**Resource Governance Audit**（§54）必须同时检查：Revision Count / Internal KV Estimate / Projected Delta KV / Working Set / Safety Margin / Admission Limit / Residency / Eviction / RSS / Swap；保持 Revision Count Budget ≠ Memory Budget、Swap ≠ KV Size。

**当前效率基线**（2026-09-02 实测）：Distinct Session IDs 正常 / Gate Wait ≈ 0ms 已恢复 / Cross-Session KV Reuse 已验证 / Prefix Match 已验证 / ToolFP Mismatch 严格过滤 / Cancellation Cleanup 闭环。待独立优化：Cold Prefill Throughput、ToolFP Reuse Coverage、Prefill Wait、Decode Throughput、Long-Context Memory Pressure、Decode Scheduling Contention——属下一阶段局部能力，不应重新改变 v4.5 的 Logical Identity 与 KV 语义。

---

# 第九部分 终态架构模型

## 9.1 Runtime 层级

```text
                 External Agent
                       │
                       ▼
              OpenAI-Compatible API
                       │
                       ▼
                 HTTPServer（Protocol Gateway）
                       │
                       ▼
                 NativeMLX
                       │
        ┌──────────────┼────────────────┐
        ▼              ▼                ▼
   Logical Plane   Execution Plane   Resource Plane
        │              │                │
        │              ├─ Gate          ├─ Admission
        │              ├─ Scheduler     ├─ Residency
        │              ├─ Prefill       └─ Eviction
        │              └─ Decode
        │
        ├─ Agent / Session / Logical Branch / Degeneration
        │
        ▼
   Generation Round（Structured Tool Call / Raw Tool Fallback / Ordinary Text）
        │
        ▼
   Physical Token Ledger → Global Physical KV Pool
```

## 9.2 Unified Runtime Flow

```text
Request → AgentExecutionKey → SessionGenerationGate → Message Normalization
       → Tool Schema Normalization → Tokenization → Tool Fingerprint → Semantic Progress
       → Global Physical KV Candidate Search → Exact Token Prefix Match
       → Predictive Admission Control → KV Copy / Trim / Cold Prefill
       → Generation ─┬─ Structured Tool ─┐
                     └─ Raw Tool Fallback ┴→ ParsedToolCall → Dedup / Degeneration
       → External Agent → Generation Completion → Physical KV Commit
```

任何 Cancellation / Malformed / Incomplete Tool Call / Parser Failure / Generation Interrupted / Degeneration Circuit Break 都必须阻止未完成 Physical KV Commit。

## 9.3 最终统一结论

> **逻辑隔离，执行共享，计算复用，预测治理，协议严格。**

```text
Logical Isolation           → Agent / Session / Logical Branch
Execution Sharing           → Gate / Scheduler / Prefill / Decode
Physical Reuse              → Exact Token Prefix + Tool Fingerprint
Resource Governance         → Internal KV Ledger + Projected Delta + Working Set + Margin
Long-Context Governance     → Stronger Eviction without Semantic Deletion
Tool Protocol Robustness    → Structured Primary + Raw Fallback + Fail-Fast
Lifecycle Determinism       → Acquire → Execute → Commit / Cancel → Release
```

架构必须长期保持的不等式：

```text
Agent Runtime ≠ Inference Runtime          Logical State ≠ Physical KV State
Streaming Parser State ≠ Logical State     Revision Count ≠ Memory Budget
RSS ≠ KV Size                              Swap ≠ KV Size
Responses State ≠ Physical KV State        Tool Execution ≠ Inference Runtime
```

核心裁决：Physical KV Reuse 是性能手段不是 KPI；Long-Context 策略决定资源压力下保留多少 KV 但绝不改变 Semantic Reuse 规则；一次错误 Tool Protocol 解析不得污染 Logical History 与 Physical KV；Revision Count 与 Predictive Admission 永远正交；System Swap 是诊断信号不是 Admission 输入；任何新能力只有 Benchmark + Invariant Audit + Stress Test 证明稳定收益后才能成为 Stable Capability。

**Architecture Identity**：Ponytail = Logical Isolation + Execution Sharing + Physical Compute Reuse + Predictive Resource Governance + Strict Tool Protocol Handling + Deterministic Lifecycle。

---

# 第十部分 铁律全集（1–99）

## v4.5 核心铁律（1–64）

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

## Tool Protocol Robustness（65–82）

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

## Resource Governance（83–90）

83. **`maxPhysicalKVRevisions` 只控制 Revision 历史数量，不代表 Memory Budget。**
84. **`maxPhysicalKVRevisions` 调整不得被当作 Memory Optimization 的替代方案。**
85. **Internal Resident KV Ledger、Projected KV Delta、Working Set、Safety Margin 组成当前 Admission 的核心预算模型。**
86. **RSS、Virtual Memory、System Swap 属于观察指标，与 Internal KV Ledger 保持语义分离。**
87. **不得因为 RSS 数值下降或上升而直接推断 Physical KV 大小。**
88. **Eviction 必须 Lossless：只释放 Physical Residency，保留 Logical Ledger。**
89. **Long-Context Policy 可以提高 Eviction 强度，但不得改变 KV Semantic Match Rules。**
90. **Revision Count Budget 与 Resource Budget 必须保持正交，不得使用 Revision Count 代替 Admission Control。**

## Lifecycle Control Plane（91–99）

91. **Request 必须先注册唯一身份；注册之后的一切状态变化必须经迁移表校验的 transition()，表外迁移一律 INVALID 并写入 Trace。**
92. **RELEASED 是唯一终态：RELEASED 之后拒绝一切迁移；任何请求无论正常完成、取消、错误或断连，最终必须收敛到 RELEASED。**
93. **所有终止路径统一汇入 finish()：成功走 COMPLETING→COMPLETED→RELEASING→RELEASED，异常走 CANCELLING→DRAINING→RELEASING→RELEASED；重复 finish 必须幂等且仅记录 Trace。**
94. **Lifecycle Control Plane 是被动账本：只记录状态与不变量观测，不拥有、不直接释放 Physical KV、Session、Task 或 Stream；真实资源释放仍由 NativeMLX 既有 Teardown 链执行。**
95. **账本不得先于真实资源收尾伪造 RELEASED；NativeMLX 请求任务收尾必须回报 noteRequestTaskEnded，RELEASED 先于任务收尾必须在 Trace 中暴露（Invariant 1 观测点）。**
96. **生命周期状态必须有界：RELEASED 条目必须按上限逐出，禁止无界状态积累。**
97. **生命周期 Trace 统一写入 native_mlx_trace.log（[LIFECYCLE] 前缀）；每条必须含 event 与 request，agent / session / from / to / reason 在已知时必须携带。**
98. **存在等价既有防护时不得引入平行状态机；Emit-After-Close 防护由 SSE 出口的 closed/canSend 检查承担。**
99. **RUNNING→COMPLETING 是迁移表的受审补充边（非流式请求无 STREAMING 阶段）；STREAMING 细分接入后，生产路径必须回归 RUNNING→STREAMING→COMPLETING。**

---

# 第十一部分 仓库结构与构建

## 11.1 代码结构（三平面映射）

```text
SimiGo/
├── App/            # SwiftUI 菜单栏入口、设置、模型选择
├── Protocol/       # HTTPServer + Chat/Completions/Responses 三个 API 域（Protocol Gateway）
├── Inference/      # NativeMLX 三平面核心：Gate、Scheduler、KV、Stream Filter、Lifecycle Gates
├── Lifecycle/      # RuntimeLifecycleCoordinator（生命周期账本）、RuntimeTuning（集中调参）
├── Model/          # 模型类型与节点配置
├── Observability/  # TraceLogger（native_mlx_trace.log）
└── System/         # 服务编排、进程/环境管理
SimiGoTests/        # 单元测试（21 用例）
```

## 11.2 构建与测试

**环境要求**：Apple Silicon Mac · Xcode 26.5+ · macOS 26.4+ SDK。

```bash
# 构建
xcodebuild build -project SimiGo.xcodeproj -scheme SimiGo -destination 'platform=macOS'

# 运行单元测试
xcodebuild test -project SimiGo.xcodeproj -scheme SimiGo -destination 'platform=macOS'
```

当前测试矩阵：`SessionGenerationGateTests`（同 Key 串行 / 跨 Key 并行 / shutdown 拒绝 / 千轮 acquire-shutdown 压测钉死 drain 不变量）、`AgentExecutionKeyTests`（身份归一化 + 双 Key 契约）、`PhysicalTokenRecorderTests`（并发计数守恒回归）、`RuntimeTuningContractTests`（准入预算常量契约）。生命周期 17 场景实机矩阵为下一阶段工作（见 6.5）。

## 11.3 运行

构建后从菜单栏图标启动服务、选择本地模型目录即可；API 地址可一键复制。LAN 第二节点部署与多节点扩容见 [部署指南.md](部署指南.md)。
