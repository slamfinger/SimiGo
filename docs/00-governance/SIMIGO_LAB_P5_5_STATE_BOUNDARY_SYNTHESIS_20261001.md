# P5-5: Execution State Boundary Synthesis

日期：2026-10-01  
状态：`SYNTHESIS DRAFT / ANALYSIS ONLY`  
前置：P4 → P5-1 → P5-2-C → P5-4 全部完成  
Contract v1.0：不变  
目标：钉牢 Execution State 理论边界，为 Palace 留接口

---

## §0 P4→P5-4 推理链回顾

```text
P4:     S₀ 可作为多分支共同基点（topology 存在）
  ↓ 问题：这个基点是什么？
P5-1:   KV carrier alone 不成立（alignment 断裂 → rebuild）
  ↓ 问题：那还需要什么？
P5-2-C: {I,P,A,C} 均为 dependency（closure 存在）
  ↓ 问题：内部是否可合并？
P5-4:   {I,P,A,C} 独立不可替代（L1 minimal set）
```

结论：Execution State 不是任何一个 carrier 对象，而是四类关系的最小闭包。

## §1 Execution State 的边界

### §1.1 属于 State 的（closure members）

| Relation | 定义 | P5-4 证据 |
|---|---|---|
| Identity | 这个状态属于哪个计算上下文 | -I → VALIDATION_REJECTED（硬前置） |
| Position | 计算进行到哪里（token offset ↔ ledger 对齐） | -P → 模型完全丢失会话记忆 |
| Semantic Anchor | 这个状态对应什么语义内容 | PA-2 → 模型跟随 placeholder，不跟随 KV 语义 |
| Continuation | 下一步计算如何接入（Δ 的接受规则） | -C → S₀ 完全未被消费 |

### §1.2 不属于 State 的（carrier / external）

| 对象 | 分类 | 理由 |
|---|---|---|
| KV tensors (.safetensors) | Carrier (P) | 物理介质，可替换 |
| meta.json 文件格式 | Carrier (P) | 序列化格式 |
| token ledger (cachedTokens) | R (runtime bridge) | 可从 prompt 重 bootstrap |
| ChatSession instance | R (runtime) | 进程内对象 |
| 数据库 record | Carrier | 未选型 |
| memory page | Carrier | OS 层 |

### §1.3 边界判定原则

```text
如果替换 carrier（换文件格式 / 换数据库 / 换内存布局）
但四项 relation 保持 → 仍是同一个 Execution State

如果破坏任何一项 relation
即使 carrier 完好 → 不是同一个 Execution State（continuation 失效）
```

## §2 Agent 环境中什么属于 State

### §2.1 分类表

| 项 | 属于 State？ | 分类 | 理由 |
|---|---|---|---|
| 对话历史（user/assistant turns） | **YES → Anchor** | D | 构成 semantic anchor 的内容来源 |
| System prompt | **条件性 → Anchor 或 Runtime Policy** | 见 §2.2 | 取决于是否进入 transformer context |
| Tool definitions（tools 列表） | **YES → Continuation** | D | 定义哪些 Δ 是合法的 continuation |
| Tool call history | **YES → Anchor** | D | 会话语义的一部分 |
| temperature / maxTokens | **NO → Generate Parameter** | R | 影响生成行为，不影响状态身份 |
| UI 设置（markdown/隐藏思考） | **NO → UI layer** | 外部 | 不进入 transformer context |
| 用户账号/权限 | **NO → Security boundary** | 外部 | 限制谁可以访问 State，不是 State 本身 |
| 文件系统状态 | **NO → External world state** | 外部 | State 引用但不包含 |
| KV fingerprint / config | **YES → Identity** | R | 配置变更 → cache 不可复用 |
| modelId | **YES → Identity** | R | 模型绑定 |

### §2.2 System prompt 的归属判定

```text
Prompt 进入 transformer context？
  YES → 语义输入 → 参与 Anchor relation
  NO  → 行为约束 → Runtime policy

具体：
  system prompt（"你是一个严谨助手"）
    → 进入 ChatSession instructions
    → 渲染进 prompt template
    → 参与 token 计数
    → 属于 Semantic Anchor 的组成部分

  display 偏好（"显示 markdown"）
    → 不进入 context
    → 不属于 State
```

### §2.3 判定原则

```text
一个 agent 环境项属于 Execution State 当且仅当：
1. 它参与 transformer context（进入 prompt rendering）
2. 它的变更会导致 continuation 输出不同
3. 它是 {I, P, A, C} 中某项的组成部分或约束条件

不满足以上任一条件 → 不属于 State
```

## §3 与 Palace 的接口（预定义，不进入 Palace 实现）

### §3.1 两层拓扑

```text
Palace（Knowledge Topology）
  保存：Evidence / Facts / Relations / References
  方向：past-oriented（已知什么）
  一致性：eventual（关系可演化）
  载体：TBD（不预选数据库）
       │
       │ reference / provenance
       ▼
Execution State（Computation Topology）
  保存：{I, P, A, C} closure
  方向：future-oriented（什么可以继续）
  一致性：transactional（SC-3 事务窗口）
  载体：backend-specific（KV / hidden state / …）
```

### §3.2 连接点

```text
Palace 的 evidence entry 可以引用一个 Execution State：
  "这个结论是在 State S₀ 下得出的"

Execution State 的 Anchor 可以引用 Palace 的 evidence：
  "这个状态对应的语义内容包括 evidence E₁, E₂"

连接 relation = Identity / Reference（不是内容复制）
```

### §3.3 Palace 不做的事

```text
❌ Palace 不是 Execution State 的存储后端
❌ Palace 不定义 Execution State 的 schema
❌ Palace 不替代 KV cache / hidden state
❌ Palace 不属于 {I, P, A, C} 中任何一项
```

## §4 当前研究边界总结

```text
Execution State =
  最小关系闭包 {Identity, Position, Semantic Anchor, Continuation}

不是 =
  KV cache / snapshot 文件 / history 文本 / token ledger / 数据库对象

验证等级 =
  Level 1 (MLX backend): VALIDATED
  Level 2 (multi-backend): NOT YET
  Level 3 (universal): NOT CLAIMED

Carrier =
  任何能实例化 closure relations 的物理介质
  Carrier ≠ Closure

与 Palace 的关系 =
  共享 Relation Closure 抽象
  通过 Identity/Reference 连接
  各自独立定义，不合并
```
