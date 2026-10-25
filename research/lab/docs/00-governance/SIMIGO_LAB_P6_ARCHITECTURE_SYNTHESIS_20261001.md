# P6: Architecture Synthesis — Frozen Model

日期：2026-10-01  
状态：`SYNTHESIS DRAFT / FREEZE CANDIDATE`  
前置：P4 → P5-1 → P5-2-C → P5-4 → P5-5 全部完成  
Contract v1.0：上游语义参照，本文不修改 Contract  
方法：从已验证的实验结果合成，不引入新假设

---

## §0 核心定义（冻结候选）

> **Execution State is not a stored artifact. It is the minimal
> relation closure that preserves computational continuity.**

> Execution State 不是被保存的对象，而是保证计算连续性的最小关系闭包。

这一定义来自 P4→P5-4 实验链的归纳，不是先验假设。

## §1 推理链（证据基础）

```text
P4      S₀ topology 存在（多分支共同基点）
P5-1    KV carrier alone 不成立（KV ≠ State）
P5-2-C  {I,P,A,C} 均为 continuation 必要依赖
P5-4    {I,P,A,C} 独立不可替代（L1 minimal set）
P5-5    State boundary 定义（carrier ≠ closure）
```

## §2 Execution State Ontology（三层模型）

```text
┌─────────────────────────────────────────────────┐
│              Reference Layer                     │
│   Palace ←→ Execution State                     │
│   (Identity/Reference relation connects them)   │
├─────────────────────────────────────────────────┤
│              Closure Layer                       │
│   Execution State = {I, P, A, C}                │
│                                                 │
│   Identity:    which computation?               │
│   Position:    where in computation?            │
│   Anchor:      what does it mean?               │
│   Continuation: how to continue?                │
├─────────────────────────────────────────────────┤
│              Carrier Layer                       │
│   Physical media that instantiates closure      │
│   KV tensors / hidden state / file / DB / …     │
│   Carrier ≠ Closure (substitution test)         │
└─────────────────────────────────────────────────┘
```

### §2.1 Closure 四关系的结构

```text
              Identity
                  │
                  │  "which computation?"
                  │
    Anchor ──── Execution State ──── Position
                  │  "what meaning?"     "where?"
                  │
            Continuation
               "how to continue?"
```

### §2.2 四关系的独立必要性（P5-4 实验证据）

| Relation | 回答 | 缺失后果 | P5-4 证据 |
|---|---|---|---|
| Identity | 这是哪个计算？ | 拿错状态 / 拒绝加载 | -I → VALIDATION_REJECTED |
| Position | 计算进行到哪里？ | 有内容但不知进度 | -P → 模型丢失全部记忆 |
| Semantic Anchor | 状态对应什么语义？ | 位置正确但意义错误 | PA-2 → 模型跟随 placeholder |
| Continuation | 下一步如何接入？ | 有过去但无未来路径 | -C → S₀ 完全未被消费 |

## §3 Carrier / Closure / Reference 关系

### §3.1 判定原则

```text
一个对象 X 属于 Execution State 当且仅当：
1. X 是 {I, P, A, C} 中某项的组成部分或约束条件
2. 移除 X 导致 continuation 失效
3. X 的变更导致 continuation 语义改变

一个对象 Y 是 Carrier 当且仅当：
1. Y 承载 closure relations 的物理表示
2. 替换 Y（保持 relations）不改变 Execution State identity
3. Y 的格式/位置/实现与 closure 定义无关
```

### §3.2 Agent 环境归属速查

```text
┌────────────────────────┬───────────┬─────────────────────┐
│ Agent 环境项            │ 分类       │ 理由                │
├────────────────────────┼───────────┼─────────────────────┤
│ 对话历史                │ A (Anchor)│ 语义内容来源         │
│ System prompt           │ 条件 A    │ 进入 context 则是   │
│ Tool definitions        │ C (Cont.) │ 定义合法 Δ          │
│ Tool call history       │ A (Anchor)│ 会话语义的一部分     │
│ temperature/maxTokens   │ R (Runtime)│ 影响生成但不影响身份 │
│ kvFingerprint           │ I (Identity)│ 配置绑定           │
│ modelId                 │ I (Identity)│ 模型绑定           │
│ UI 设置                 │ 外部       │ 不进入 context      │
│ 用户权限                │ Security  │ 限制访问，非 State  │
│ 文件系统状态             │ 外部       │ External world     │
└────────────────────────┴───────────┴─────────────────────┘
```

## §4 Security Boundary 入口点

### §4.1 安全模型

```text
传统：data access control → "谁能读数据？"
Execution State：execution authority control → "谁能继续运行？"
```

### §4.2 安全不变量（来自 P5-2-ER）

```text
INV-S1  possession ≠ capability（需 identity credential）
        当前：NOT SATISFIED
INV-S2  authority ∉ State（工具权限由 runtime 管理）
        当前：SATISFIED ✓
INV-S3  cross-user transfer 需 consent + audit
        当前：NOT SATISFIED
INV-S4  revocation ≠ deletion（须阻止计算继续）
        当前：NOT SATISFIED
```

### §4.3 Security 与 Closure 的关系

```text
Security 限制的是：谁可以触发 continuation
Security 不改变：closure 的定义
Security 作用层：Reference Layer（Identity relation 的访问控制）

INV-S2 特别重要：authority 不持久化在 State 中。
这意味着 State 泄露 = context 泄露，不是 authority 泄露。
```

## §5 Palace 未来接口约束

### §5.1 共享抽象

```text
Relation Closure =
  nodes + relations + transitions

Palace:
  nodes = evidence entities
  relations = knowledge connections
  transitions = belief updates
  方向：past-oriented

Execution State:
  nodes = computation anchors
  relations = {I, P, A, C}
  transitions = continuation paths
  方向：future-oriented
```

### §5.2 连接约束

```text
连接类型：Identity / Reference（不是内容复制）
Palace evidence 引用 ES State → provenance
ES Anchor 引用 Palace evidence → semantic source
二者不合并 schema
二者不共享存储
二者通过 reference id 关联
```

### §5.3 Palace 必须等待的条件

```text
1. P6 本文档 human review PASS
2. Security INV-S1..S4 状态确认（至少当前缺口被承认）
3. Palace 设计不得假设 Execution State = 任何 carrier 格式
4. Palace 三层模型（Evidence → Relation → ExecutionRef）
   中的 Layer 3 必须通过 Identity/Reference 连接，不复制内容
```

## §6 Non-claims（冻结）

```text
❌ 不证明 Execution State = KV / database / 任何 carrier
❌ 不证明 Universal Minimal Closure（Level 3 需 multi-backend）
❌ 不定义 Palace schema
❌ 不实现 Security mechanism（只定义 invariant 入口点）
❌ 不修改 Contract v1.0
❌ 不选存储方案
```

## §7 P6 后路线

```text
P6 Architecture Synthesis（本文件）
  │
  ├─▶ Human review → FREEZE or REVISE
  │
  ├─▶ Palace Mapping（知识拓扑 → 接口约束已定义）
  │    前提：P6 frozen + Security invariants acknowledged
  │
  ├─▶ Security Design（INV-S1/S3/S4 → 具体机制）
  │    前提：P6 frozen
  │
  └─▶ Product Integration
       前提：P6 frozen + Palace interface stable
```
