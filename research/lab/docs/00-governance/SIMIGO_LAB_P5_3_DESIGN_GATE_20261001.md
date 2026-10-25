# P5-3 Design Gate: Dual-Track Analysis Draft

日期：2026-10-01  
状态：`P5-3 DESIGN GATE / ANALYSIS ONLY / NOT EXECUTION`  
前置：P5-2-ER PASS-WITH-REVISIONS → closure registered (provisional)  
纪律：只读设计。不运行模型、不实现存储、不修改 Contract。

---

## Track A: Palace Relation Closure Mapping

### A.0 共享抽象假设（待验证）

Palace 和 Execution State 可能共享一个上层抽象：

```text
Relation Closure =
  nodes（实体或状态锚点）
  + relations（节点之间的语义约束）
  + transitions（合法的状态/关系变化）
```

**假设**：Palace = Knowledge Relation Closure（past-oriented）；
Execution State = Computation Relation Closure（future-oriented）。

此假设本身需要审查——如果映射失败，Palace 可能需要独立的抽象框架。

### A.1 映射表（候选对应）

| Execution State closure | Palace candidate | 对应类型 | 置信度 |
|---|---|---|---|
| Identity relation (modelId, storageKey) | Provenance (source, origin, authority) | structural | HIGH |
| Position relation (ExecutionPosition, ledger) | Entity state / temporal position | structural | MEDIUM |
| Semantic Anchor (alignment, content) | Meaning anchor / context reference | semantic | HIGH |
| Continuation relation (nextInput, acceptance) | Reasoning path / query trajectory | functional | MEDIUM |
| Physical Carrier (KV tensors) | Storage backend | implementation | N/A (not shared) |

### A.2 关键差异

```text
Execution State:
  时间方向: future（保存"什么可以继续"）
  生命周期: short-lived（computation session scope）
  一致性: transactional（SC-3 事务窗口）
  载体: backend-specific（KV / hidden state / …）

Palace:
  时间方向: past（保存"已知什么"）
  生命周期: long-lived（knowledge lifetime）
  一致性: eventually consistent（关系可演化）
  载体: storage-agnostic（不选数据库）
```

**核心张力**：Execution State 的一致性是严格的（transactional）；
Palace 的一致性可能是演化式的（eventual）。这个差异决定了两者
不能简单共享一个闭包定义。

### A.3 Palace 是否需要 Schema？

传统：`schema → data → query`

Palace 候选：`raw information → model interpretation → relation
extraction → dynamic topology`

答案不是"有没有 schema"，而是"schema 是预定义的还是涌现的"。

候选层次模型（三层）：

```text
Layer 1: Immutable Evidence（不可变证据层）
  text / image / audio / model output
  timestamp / source / hash
  不可修改、可审计

Layer 2: Relation Graph（关系图层）
  A --mentioned--> B
  A --derived_from--> B
  A --contradicts--> B
  A --same_context--> B
  可演化、可修正、可版本化

Layer 3: Execution Reference（执行引用层）
  this answer
    --generated_under--> state S₀
    --continued_from--> conversation branch
    --derived_from--> evidence entry
  连接 Palace 和 Execution State 的桥
```

### A.4 Open questions

```text
OP-PA-1  Palace 是否需要 transactional consistency？
         （如果只是知识层，eventual 可能够；如果承载 execution
         reference，可能需要更强保证）
OP-PA-2  Layer 2 的关系是否可以被模型自动提取？
         （如果可以，提取质量如何验证？）
OP-PA-3  Layer 3 的桥是否需要和 Execution State 的 continuation
         relation 有相同的形式？（即 Palace 的"下一步"是什么？）
OP-PA-4  Palace 的 identity 和 Execution State 的 identity 是否
         可以共享 provenance 机制？
```

---

## Track B: Execution State Security Boundary Design

### B.0 安全模型转变

```text
传统数据安全:
  "谁能读数据？" → access control

Execution State 安全:
  "谁能继续运行这个状态？" → execution authority control
```

这是不同类别的安全问题。P5-2-ER 确认 capability level =
EXECUTION-LEVEL。

### B.1 四维权限模型（候选）

```text
维度 1: Ownership（所有权）
  谁拥有 S？
  候选: user / agent / application / organization
  当前实现: 未定义——checkpoint 文件无 owner 标记

维度 2: Transfer（转移权限）
  S₀ --fork--> S₁：S₁ 继承什么？
  候选: state transferable, authority NOT transferable
  当前实现: context 可转移（P5-2-ER B3 确认），authority 由
  runtime 独立管理（安全），但隐含假设部分转移（风险）

维度 3: Revocation（撤销权限）
  如何 invalidate 一个已导出的 State？
  当前实现: 不存在（P5-2-ER B4 确认）
  候选方案:
    a. cryptographic credential binding（checkpoint 携带可撤销凭证）
    b. lineage tombstone + coordinator enforcement（当前部分存在）
    c. model binding（撤销模型访问 → 状态失效）

维度 4: Audit（审计）
  谁在何时使用了哪个 State 做了什么？
  当前实现: lineage log 存在但非安全审计（无防篡改）
```

### B.2 关键安全不变量（候选）

```text
INV-S1: State possession alone ≠ computation capability
        （必须有 identity credential 才能启动 continuation）

INV-S2: Authority is NEVER carried by State
        （工具权限由 runtime 配置，不持久化在 checkpoint 中）

INV-S3: Cross-user State transfer requires explicit consent + audit

INV-S4: Revocation must be possible without physical file deletion
        （撤销 ≠ 删除；须阻止计算继续）
```

INV-S2 当前已满足（NativeMLX 工具权限在 runtime 层配置，不在
SessionCacheMetadata 中持久化）。这是一个**已实现的安全属性**。

INV-S1 当前不满足——checkpoint 文件 + 兼容 runtime = capability。
没有额外的 credential gate。

INV-S3 当前不满足——无 consent 机制。

INV-S4 当前不满足——无 revocation 机制。

### B.3 Open questions

```text
OP-SB-1  Credential 绑定的最小形式是什么？
         （HMAC? 公钥签名? 需要多少密钥管理基础设施？）
OP-SB-2 INV-S2 在 cross-backend 场景下是否仍成立？
         （如果 LLAMA adapter 持久化了不同的 metadata？）
OP-SB-3  Audit trail 是否需要 cryptographic integrity？
         （log 本身可否被篡改？）
OP-SB-4  State ownership 是否需要与 Palace Layer 1 evidence
         的 source/authority 对齐？
```

---

## Dual-track synthesis

### 交叉点

Palace Layer 3 (Execution Reference) 是两条线的自然连接点：

```text
Palace（知识拓扑）
  Layer 3: "这个结论是在什么 Execution State 下得出的？"
     │
     ▼
Execution State（计算拓扑）
  Identity: "这个 State 属于哪个 execution？"
     │
     ▼
Security（权限边界）
  "谁有权从这个 State 继续？"
```

这个三层结构（knowledge → computation → authority）可能是 SimiGo
架构的核心分层——比"数据库 + 推理"更清晰。

### 前置条件

在进入实验（P5-3 ablation 或 Palace prototype）之前，必须确认：

```text
1. 闭包定义是 provisional 的——实验结果可能修订它
2. 安全模型在当前实现中的缺口（INV-S1/S3/S4）不是本阶段必修——
   它们是 production gate，不是 research gate
3. Palace 的三层模型是候选——不预定义 schema
```

---

## P5-3 route（post-gate）

```text
P5-3 Design Gate（本文件）
  │
  ├─▶ Human review: Palace 是否属于主线？Security 是否升级？
  │
  ├─▶ P5-3A: Palace Mapping → 关系闭包共享抽象验证
  │    （理论分析 → 可能的 prototype design → 不选数据库）
  │
  ├─▶ P5-3B: Security Boundary → 权限模型设计
  │    （INV-S1..S4 → credential 形式 → 不立即实现）
  │
  └─▶ P5-3C: Dependency Ablation（实验）
       （axes A/B/C → 只有在 A/B 确认方向后才执行）
```

当前 blocker：human review of this design gate。
