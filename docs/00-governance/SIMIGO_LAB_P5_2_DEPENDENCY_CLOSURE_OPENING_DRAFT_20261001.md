# Execution State Dependency Closure Analysis — Opening Draft

日期：2026-10-01  
状态：`P5-2 OPENING DRAFT / ANALYSIS GATE / NOT EXECUTION`  
前置：P4 PASS（拓扑）→ P5-1 INCONCLUSIVE（KV-only rejection）→
P5-2-0 Dependency Map（10 项，根因定位）  
Contract v1.0：`SIMIGO_LAB_EXECUTION_STATE_ARCHITECTURE_CONTRACT_V1_DRAFT_20260930.md`  
Route authority：`SIMIGO_LAB_EXECUTION_STATE_RESEARCH_ROUTE_REDEFINITION_20260929.md`

> **本 draft 是分析，不是实验。** 目标是产出 Execution State 的
> 最小关系闭包定义（Ontology Map），供后续实验设计（P5-3 ablation）
> 或 Palace mapping 使用。不运行模型、不修改 Contract、不选存储方案。

---

## §0 重新定义 Execution State

### §0.1 修正后的定义

**Execution State = 保证未来计算连续性的最小关系闭包。**

这不是一个数据对象。它是一个关系系统：

```text
Execution State =
  Identity relation          （这是哪个状态？）
  + Position relation        （计算进行到哪里？）
  + Semantic Anchor relation （这个状态对应什么语义历史？）
  + Continuation relation    （下一步计算如何接入？）
  + Physical Carrier         （用什么介质承载？）
```

### §0.2 与 Contract v1.0 的关系

Contract v1.0 §1.1 已建立 D/R/P/O/T 分类。本 draft 将 P5-2-0
dependency map 的 10 项与 Contract 分类对照，验证一致性并补全
Contract 未覆盖的 relation 级语义。

### §0.3 非命题（Hard boundaries）

```text
❌ 不证明 Execution State = KV tensor
❌ 不证明 Execution State = hidden state
❌ 不证明 Execution State = database snapshot
❌ 不证明 Execution State = model internal format
❌ 不定义 Palace 为数据库
```

以上全部是 carrier 层对象。Execution State 的定义在 relation 层。

---

## §1 Identity Relation

### §1.1 问题

> 这是哪个状态？两个字节相同的 KV 文件是否代表同一个 Execution State？

### §1.2 依赖项（from P5-2-0 map）

| Dependency | Contract 层 | P5-2-0 # | 必要条件 |
|---|---|---|---|
| `modelId` | R | #6 | model match |
| `kvFingerprint` | R | #5 | config match |
| `storageKey` | D | #8 | sessions pool lookup |
| `checkpointGeneration` | O（History） | #7 | commit identity |
| `cacheSHA256` | P | #7 | content integrity |

### §1.3 闭包要求

Identity 回答"这是哪个状态"需要以下关系的交集非空：

```text
Identity relation =
  model binding          （modelId → 此 KV 由该模型产生）
  + config binding       （kvFingerprint → 此 KV 在该配置下产生）
  + execution binding    （storageKey → 此 KV 属于该 execution）
  + content proof        （SHA256 → 此 KV 是这些字节）
```

缺失后果：`same bytes, wrong meaning` —— 字节一致但语义不同。

### §1.4 Contract 对照

Contract v1.0 `SC-1`（语义唯一权威 = coordinator）已覆盖 execution
binding。本 draft 补充的是 model/config binding：这两个在 Contract 中
归为 R（Runtime），但在 dependency closure 中它们是 continuation
的必要条件——缺失时 restore 本身就会 throw。

### §1.5 Open question

`checkpointGeneration` 是 O（History）——它是 commit 证明，不是语义
状态。但它同时也是 identity 的组成部分（区分同一 session 的不同
checkpoint 版本）。是否需要将 generation 从 O 提升为 identity
relation 的独立组成部分，还是作为 P（content proof）的附属？**OPEN。**

---

## §2 Position Relation

### §2.1 问题

> 计算进行到哪里？`processedTokenCount = 31712` 是什么意思？

### §2.2 依赖项

| Dependency | Contract 层 | P5-2-0 # | 必要条件 |
|---|---|---|---|
| `processedTokenCount` | R | #2 | 从 cache 读取 |
| Token ledger (`cachedTokens`) | R | #4 | bootstrap or prior gen |
| `ExecutionPosition` (Int64) | **D** | Contract §1.1 | 逻辑时间线 |

### §2.3 闭包要求

Position 不是计数器。它是一个 anchored location：

```text
Position relation =
  physical position      （processedTokenCount：cache 内部的 token 偏移）
  + semantic position    （ExecutionPosition：逻辑时间线上的 canonical 位置）
  + ledger anchor        （cachedTokens：哪些 token 已被 cache 表示）
```

P5-1 教训：`processedTokenCount = 31712` 但 `cachedTokens = []` 时，
`mainCacheIsAligned = false` → rebuild。物理 position 存在但 ledger
anchor 缺失 → 计算不能继续。

### §2.4 Contract 对照

Contract `ExecutionPosition` 是 D 层的逻辑时间线。`processedTokenCount`
是 R 层的物理偏移。两者必须通过 ledger 桥接。P5-1 的失败发生在 R 层
bridge 断裂，不是 D 层 position 错误。

### §2.5 Open question

`cachedTokens` 的 token IDs 是 R 还是 D？它们表示"哪些 token 已经被
cache 消化"——这是一个计算事实，不是语义选择。但它们是 runtime 派生的
（从 prompt tokenization 产生）。**倾向 R，待 ablation 确认。**

---

## §3 Semantic Anchor Relation

### §3.1 问题

> 当前状态对应什么语义历史？state 存在但没有解释力时，它是什么？

### §3.2 依赖项

| Dependency | Contract 层 | P5-2-0 # | 必要条件 |
|---|---|---|---|
| History text (in prompt) | **D** | #3 | prompt tokens ≥ processedTokens |
| `Conversation` (transcript) | **D** | #10 | created from history param |
| `ExecutionContinuation.nextInput` | **D** | Contract §1.1 | next input |

### §3.3 闭包要求

Semantic Anchor 不是"保存全部历史文本"。它是"存在一个锚点使 state
可以被解释"：

```text
Semantic Anchor relation =
  alignment anchor       （prompt tokenization 能解释 processedTokenCount）
  + semantic content     （anchor 的内容与 state 产生的语境一致）
  + continuation input   （nextInput 定义 Δ 的接入点）
```

P5-1 根因：alignment anchor 断裂（31712 tokens 的 cache 无法被 212
tokens 的 prompt 解释）。即使 KV 完好，anchor 缺失 → state 不可解释
→ rebuild。

### §3.4 Contract 对照

Contract `ExecutionContinuation.nextInput` 是 D。`history text` 在
dependency map 中也是 D（#3 = "prompt token count ≥ processedTokenCount"
的必要条件）。但两者的角色不同：

- `nextInput` = **forward-facing**（下一步要接什么）
- `history text` = **backward-facing**（这个状态从哪里来）

Contract 目前只覆盖 forward。backward anchor 的语义地位需要 P5-2
closed 后才能决定是否提升为 D 的组成部分。

### §3.5 Open question

Semantic Anchor 的最小形式是什么？
```text
候选 A：完整 history text（当前 ChatSession 要求）
候选 B：token count + content hash（足够 alignment 但不保存全文）
候选 C：position-only anchor（ExecutionPosition 即可，无需文本）
```
**OPEN——这是 P5-3 ablation axis A 的核心问题。**

---

## §4 Continuation Relation

### §4.1 问题

> 下一步计算如何接入？当前状态接受什么形式的 Δ？

### §4.2 依赖项

| Dependency | Contract 层 | P5-2-0 # | 必要条件 |
|---|---|---|---|
| `ExecutionContinuation` (nextInput / continuationID) | **D** | Contract §1.1 | delta input acceptance |
| `isPrefix(existing, incoming)` | R | generateUsingChatSession | prefix check |
| `PromptCacheReusePolicy` | R | ChatSession internal | cache reuse decision |

### §4.3 闭包要求

Continuation 定义"什么输入可以从此状态继续"：

```text
Continuation relation =
  acceptance rule        （Δ 必须满足什么条件？prefix-compatible）
  + execution boundary   （哪个 Execution 可以从这个 State 继续？identity 桥）
  + generation path      （接续后走 extend / rebuild / rewind？）
```

### §4.4 Contract 对照

Contract `ExecutionContinuation` 已定义 nextInput 和 continuationID
为 D。dependency map 补充的是 acceptance rule 和 generation path
在 R 层的具体形式（prefix check、cache reuse policy）。

### §4.5 Open question

acceptance rule 是否是 Execution State 的组成部分，还是 backend
implementation 细节？如果 different backend 有不同的 acceptance rule
（例如 LLAMA adapter 用不同的 prefix 逻辑），acceptance rule 应该归入
R 还是作为 Contract 层的 interface 定义？**OPEN。**

---

## §5 Physical Carrier

### §5.1 问题

> 用什么介质承载以上关系？

### §5.2 依赖项

| Dependency | Contract 层 | P5-2-0 # | 必要条件 |
|---|---|---|---|
| KV tensors (.safetensors) | **P** | #1 | SHA256 match |
| `cacheSHA256` | **P** | #7 | integrity proof |

### §5.3 Carrier ≠ Definition

Carrier 使 Execution State 可执行。但 carrier 不定义 Execution State。
同一 Execution State 可以有不同的 carrier（KV tensors / hidden state /
其他 format），只要 identity + position + anchor + continuation
关系保持。

P5-1 排除的简化：
> "把 KV cache 单独拿出来就是 Execution State"

这一排除的理由不是 KV 不重要，而是 KV 是 carrier 层——没有
identity/position/anchor/continuation 关系，KV 无法独立充当 State。

---

## §6 Ontology Map（P5-2 输出）

```text
              Future Computation
                       ▲
                       │
              Continuation Relation
              （acceptance rule + boundary + path）
                       ▲
                       │
   Identity ◄── Execution State ──► Position
   Relation        Closure          Relation
   （which state）                  （where in computation）
                       │
                       ▼
              Semantic Anchor Relation
              （alignment + content + input point）
                       │
                       ▼
                 Physical Carrier
                 （KV / hidden state / …）
```

### §6.1 闭包检查清单（五问）

| 缺失 | 后果 |
|---|---|
| Physical Carrier | 无法执行 |
| Identity | 无法确认 |
| Position | 无法定位 |
| Semantic Anchor | 无法解释 |
| Continuation | 无法继续 |

### §6.2 与 Palace 的关系（初探，不定义）

```text
Palace:
  Long-lived Knowledge Topology
  past-oriented（保存"已知什么"）
  node + relation + reference

Execution State:
  Short-lived Computation Topology
  future-oriented（保存"什么计算可以继续"）
  node + relation + transition
```

共同结构：不是存储内容，而是 `nodes + relations + transitions`。

差异：时间方向（past vs future）和生命周期（long-lived vs short-lived）。

Palace mapping 留待 P5-3（如果激活）。

---

## §7 Open Points Ledger

| # | 问题 | 来源 | 状态 |
|---|---|---|---|
| OP-P5-1 | `checkpointGeneration` 的 identity 地位（O→identity 提升？） | §1.5 | OPEN |
| OP-P5-2 | `cachedTokens` 的 D/R 分类（R 派生但计算事实） | §2.5 | OPEN（倾向 R） |
| OP-P5-3 | Semantic Anchor 最小形式（full text / hash / position-only） | §3.5 | OPEN（P5-3 axis A） |
| OP-P5-4 | acceptance rule 的层归属（Contract interface vs backend R） | §4.5 | OPEN |
| OP-P5-5 | backward anchor（history text）是否提升为 D 组成部分 | §3.4 | OPEN |

以上 open points 不在本 draft 内解决。它们构成 P5-3 ablation 设计的
输入和 Security boundary 审查的前置。

---

## §8 Capability Risk（Security boundary 预审）

如果 Execution State 确实是"使未来计算继续的关系闭包"，那么掌握
这个闭包意味着什么？

```text
能力：从任意 S₀ 恢复未来计算
       = 在任意 backend 上重现一个 execution 的 continuation
       = 不需要重新 prefill 全部历史
       = 不需要原始 context
       = 只需要关系闭包
```

这是一个**执行能力**（execution capability），不是数据访问能力。
持有者可以：
1. 在没有原始对话文本的情况下继续一个 conversation
2. 在不同 backend 之间迁移 computation
3. 从一个状态点分叉出多个未来（P4 已证明拓扑可行）

**风险不在数据泄露（KV 不含可读文本），而在计算接管——
不需要知道"说了什么"，只需要知道"从哪里继续"。**

此项需要在 P5-3/P5-4 之前完成边界审查。
