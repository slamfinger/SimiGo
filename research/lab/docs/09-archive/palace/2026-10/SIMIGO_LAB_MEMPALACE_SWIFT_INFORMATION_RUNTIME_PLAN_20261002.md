# MemPalace 原生 Swift 重写与 Information Runtime 实验计划

> **ARCHIVED** 2026-10-20 · line: PALACE / Integrated ES · original: docs/00-governance/SIMIGO_LAB_MEMPALACE_SWIFT_INFORMATION_RUNTIME_PLAN_20261002.md
> Evidence status: unchanged (content frozen; moved only)

## 2026-10-02

> 状态：PLAN / 实验前置
>
> 本文不是 MemPalace 2.0 的最终架构设计，而是从当前 Python MemPalace 源码出发，建立“源码语义审计 → 原生 Swift 最小实现 → 历史数据迁移 → SimiGo 接入 → 真实任务检验”的实验路线。
>
> 核心原则：战略和理念已经形成；下一阶段不继续预设计，而让源码、迁移和真实任务逼出下一层结构。

---

## 1. 战略背景

当前研究路线已经形成以下共同方向：

```
Agent
  ↓
SimiGo Execution
  ↓
Execution State
  ↓
Execution–Information common semantic layer
  ↓
Information
  ↓
physical world
```

SimiGo 尚未真正连接 MemPalace，Information Space 尚未作为实际系统存在。

T1–T3 已经在现有 MemPalace 数据库/Memory 结构上验证了私有连续性与共享信息之间的边界，但这些实验不能直接证明新的 Information Runtime。

因此下一阶段的任务不是继续讨论抽象，而是：

**把现有 MemPalace 作为实验材料，剥离其中真正属于 Information 的语义，并用原生 Swift 建立第一个可运行的 Information Runtime。**

---

## 2. 对当前 MemPalace 源码的初步判断

当前 Python 实现已经包含多个性质不同的层次：

### 2.1 Information candidate

主要来自：

- drawer content
- source / provenance
- temporal metadata
- work records
- diary / report / environment facts
- knowledge-graph facts and relations

但 drawer 本身不能直接等同于 Information，因为其中混合了组织、索引和实现元数据。

### 2.2 Derived retrieval structure

包括：

- Chroma collections
- embeddings
- BM25 / lexical search
- closets
- hybrid ranking
- candidate generation

这些首先视为 Information 的派生检索结构，而不是 Information 本身。

### 2.3 Relation / execution history

包括：

- KnowledgeGraph
- relation / triple
- logstream
- task / artifact / coordination events

这些需要进一步区分 Information relation 与 Execution/coordination event，不能在 Swift 中机械照搬。

### 2.4 Physical implementation

包括：

- ChromaDB
- SQLite
- HNSW
- locks
- cache
- repair / health mechanisms
- MCP transport/runtime

这些属于物理实现或外部访问机制。

---

## 3. 核心重写原则

### P1 — 不是 Python → Swift 翻译

禁止按 Python 文件逐个翻译。

目标是：

```
Python MemPalace implementation
        ↓
semantic audit
        ↓
Information semantics
        ↓
Swift native implementation
```

### P2 — 不以 MCP 为内部架构

不建立：

```
Swift MCP → Swift Core
```

更不建立：

```
Swift MCP → Python MCP → Python implementation
```

MCP 只作为历史外部访问协议；新的内部语义直接建立在 Information operation 上。

### P3 — 不首先复制 Chroma

第一版 Information Runtime 不以 Chroma 为核心依赖。

先验证：

```
Information
    ↓
InformationStore
    ↓
SQLite
```

检索索引是后续派生机制。

### P4 — 不提前定义完整 Information Space

不预先设计大型 schema、知识图谱、层级、自动关系系统。

当前只建立足以迁移、读取和验证真实数据的最小语义。

### P5 — 真实任务产生下一层抽象

后续出现的新机制必须由：

- 迁移问题
- SimiGo Execution
- T1–T3 类型真实任务
- 多执行/多 Agent 行为

逼出来，而不是预先设计。

---

## 4. 总体路线

```
Phase 0
源码语义审计
    ↓
Phase 1
Swift 最小 Information Core
    ↓
Phase 2
旧 Palace → Swift Information 迁移
    ↓
Phase 3
Retrieval 重新实现
    ↓
Phase 4
Relation / provenance / execution event
    ↓
Phase 5
SimiGo Execution 接入
    ↓
Phase 6
真实任务检验 Information Space
```

**T4 只能发生在 Phase 5 之后。**

---

# Phase 0 — MemPalace 源码语义审计

## 目标

建立当前 Python MemPalace 的行为基线，而不是评价代码好坏。

## 审计范围

按真实行为路径追踪：

1. 写入路径
2. 读取路径
3. 检索路径
4. drawer 生命周期
5. closet 生命周期
6. KnowledgeGraph 生命周期
7. diary 生命周期
8. logstream 生命周期
9. multi-agent / lock
10. physical storage
11. MCP tool → domain operation 映射

## 主要产物

建立：

```
MEMPALACE_SOURCE_SEMANTIC_MAP
```

每项至少记录：

| 当前实现 | 行为 | 语义候选 | 派生结构 | 物理实现 |
|---|---|---|---|---|
| drawer | 写入/读取内容 | Information candidate | — | Chroma |
| closet | 候选聚合 | — | retrieval structure | Chroma/metadata |
| embedding | 相似检索 | — | retrieval index | vector store |
| KG triple | 关系 | Information relation candidate | graph index | SQLite |
| logstream event | 协调/执行历史 | Execution event candidate | event cursor | SQLite |
| MCP tool | 外部调用 | domain operation adapter | — | MCP |

**Gate 0：**

- 每条核心业务路径可追踪到物理存储。
- 能明确哪些东西只是 Memory implementation detail。
- 尚未开始 Swift 大规模编码。

---

# Phase 1 — Swift 最小 Information Core

## 目标

证明一个不依赖 Python、不依赖 MCP、不依赖 Chroma 的 Information runtime 可以存在。

## 第一批代码只允许很小

建议最初只有：

```
Information
InformationStore
InformationQuery
SQLiteStore
```

最小行为：

```
create
read
update
delete
list
```

最小必要信息：

- identity
- content
- provenance
- temporal metadata

暂不实现：

- MCP
- KnowledgeGraph 完整系统
- embedding
- HNSW
- closet
- layers
- 自动知识发现

## Gate 1

必须证明：

- native Swift
- 无 Python runtime
- 无 Python subprocess
- 可独立运行
- SQLite 持久化
- Information 可以创建、读取、修改、删除
- provenance 可追溯

---

# Phase 2 — 历史 Palace 迁移

## 目标

把现有 MemPalace 当作历史材料，而不是新系统运行时。

路线：

```
existing Python Palace
        ↓
read-only extraction
        ↓
Swift importer
        ↓
Swift Information Store
```

第一阶段重点迁移：

- drawer content
- identifiers
- source/provenance
- temporal metadata
- 当前 T1/T2/T3 相关材料

不首先迁移：

- HNSW 内部文件
- Chroma 私有索引状态
- Python runtime state
- MCP session state

## 验证

至少进行：

1. 数量一致性
2. ID 一致性
3. 内容 hash 一致性
4. metadata 可追溯
5. T1/T2/T3 关键记录可重新读取

## Gate 2

旧 Palace 可以作为输入；Swift Information Store 可以独立重建相同的核心信息。

---

# Phase 3 — Retrieval 重新实现

## 原则

Retrieval 是 Information 的访问机制，不定义 Information 本身。

第一步：

```
Information
    ↓
SQLite / FTS5
    ↓
lexical candidate
```

第二步再验证：

```
embedding
    ↓
vector candidate
```

最后再研究：

```
lexical
+
vector
+
metadata
    ↓
candidate/ranking
```

## 实验问题

重点不是“Swift 是否复制了 Python 搜索效果”，而是：

1. Information 是否脱离 Chroma 独立存在？
2. retrieval 是否可以替换？
3. 不同 retrieval backend 是否可以操作同一 Information？
4. ranking/closet 等结构是否只是派生物？

## Gate 3

Information 与 Retrieval 在实现上真正分离。

---

# Phase 4 — Relation / Provenance / Execution Event

这一阶段才处理当前：

- KnowledgeGraph
- relation
- provenance
- logstream

## 原则

不直接复制现有 KG schema。

先区分：

```
Information relation
        vs
Execution event
        vs
coordination event
```

重点验证：

```
Information A
      ↑
  observed/created by
      ↑
Execution
      ↓
Information B
```

关系优先来自真实 Execution 行为，而不是初始化时自动生成。

## Gate 4

至少能表达：

- source/provenance
- Information → Information relation
- Execution 产生/引用/修改 Information 的事实
- 不把 coordination event 错当 Information

---

# Phase 5 — SimiGo Execution 接入

这是整个路线的关键实验。

目标：

```
Agent
  ↓
SimiGo Execution
  ↓
Execution State
  ↓
Execution–Information semantic layer
  ↓
Swift Information
  ↓
physical persistence
```

## 第一实验

重做 T1–T3 类型任务。

观察：

### 1. Information creation

Execution 是否自然产生可共享 Information？

### 2. Information activation

已有 Information 存在时，新的 Execution 是否知道相关历史存在？

特别验证此前 BR-5 得出的结论：

> Information 的存在与 Execution 读取 Information 是两个不同语义。

### 3. Executor replacement

继续使用已经冻结的 operational test：

> 移除当前 executor 的连续性上下文后，这条信息是否仍然对理解、验证、继续或复用工作有价值？

### 4. Private/shared boundary

继续验证：

```
Execution → private continuity
Execution → shared Information
```

而不是重新设计边界。

---

# Phase 6 — Information Space 实验

只有 Phase 5 成功后，才允许把系统称为真正的 Information Space 实验。

重点不是规模，而是：

```
Execution A
   ↓
Information
   ↓
Execution B
   ↓
read / validate / modify / derive
   ↓
Information
   ↓
Execution C
```

然后观察：

- topology 是否自然形成
- relation 是否由行为产生
- retrieval 是否足够
- activation semantic 是否自然出现
- 哪些 Memory 机制仍然必要
- 哪些旧 MemPalace 机制可以消失
- 哪些新机制是现实任务逼出来的

**此阶段才进入 T4。**

---

# 5. 明确的禁止事项

在本计划完成前：

- 不做完整 MemPalace 2.0 schema
- 不把现有 Python 类逐个翻译成 Swift
- 不建立 Swift MCP 核心层
- 不把 Chroma 作为 Swift 核心依赖
- 不预先复制 layers / closets / tunnels 等全部机制
- 不提前构建完整 Knowledge Graph
- 不把当前 Memory 结构直接命名为 Information Space
- 不在 SimiGo 尚未接入前宣称 T4 成立

---

# 6. 最终验收链

整个路线最终必须形成一条可重复实验链：

```
旧 MemPalace
     ↓
源码语义审计
     ↓
Information extraction
     ↓
Swift native Information Runtime
     ↓
旧 Palace migration
     ↓
retrieval
     ↓
relation/provenance
     ↓
SimiGo Execution
     ↓
T1/T2/T3 replay
     ↓
T4
     ↓
真实任务产生下一轮架构
```

真正的成功标准不是“Swift 版 MemPalace 功能齐全”。

而是：

> **能够证明 Information 可以脱离当前 Memory 实现独立存在，并且 SimiGo Execution 可以在这个 Information 上产生、读取、验证、修改和继续工作。**

如果这条链成立，MemPalace 的 Swift 重写就不再只是一次技术迁移，而成为 **Execution–Information 共同语义层的第一次运行时实验**。

---

## 当前状态

- 战略/理念：已形成
- T1–T3：已完成并形成边界证据
- Private/Shared boundary：已冻结 BR-1、BR-2、BR-3、BR-5；BR-4、BR-6 继续观察
- MemPalace Python 源码：已开始语义审计
- Information Space：尚不存在
- SimiGo ↔ MemPalace：尚未连接
- Swift 重写：尚未开始
- T4：暂缓

## 下一执行顺序

```
0. 完成 MemPalace Source Semantic Map
        ↓
1. 建立 Swift Information Core
        ↓
2. 迁移现有 Palace 核心信息
        ↓
3. 验证 Retrieval 与 Information 分离
        ↓
4. 验证 Relation / Execution Event 边界
        ↓
5. 接入 SimiGo Execution
        ↓
6. 重跑真实任务
        ↓
7. T4
```

本文记录的是**实验路线，不是未来架构承诺**。后续每个阶段都必须以实际代码和实验结果决定下一阶段。
