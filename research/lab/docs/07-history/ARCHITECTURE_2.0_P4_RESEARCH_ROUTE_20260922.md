# Architecture 2.0 — P4 研究路线

**Date:** 2026-09-22  
**Status:** Route registered / STEP① in progress  
**RQ:** 未分配；路线文件不构成 RQ 注册

## 1. 总体研究链

```
计算架构差异
    ↓
Execution State 差异
    ↓
State 特征
    ↓
资源行为
    ↓
Loading / Residency
    ↓
Layering / Working Set
    ↓
Migration / Placement
    ↓
跨架构 Execution Semantics
    ↓
Runtime Architecture
```

原则：每一段都必须先完成自身的 Definition / Gate，再进入下一段；不得因路线已经确定而预授权后续实验。

## 2. P4-A — Architecture → Execution State

### 研究目标
确定哪些计算架构特征能够稳定地改变 Execution State 的性质，以及这种关系能否被清晰描述。

### 核心关系
```
Architecture Feature
    → Computation Dependency
    → Required Continuation State
```

### 重点属性
- State type
- State growth
- State dependency
- State reuse
- State lifetime
- State access
- State transition
- State materialization / representation transition
- Future-use relation

### 阶段出口
形成可复核的：
> Architecture → Computation → Execution State characteristic map

若架构差异不能稳定映射到 State 差异，则不进入下一阶段。

## 3. P4-B — Execution State → Resource Behavior

研究 State 特征是否产生稳定、可观察的资源行为后果。

重点关系：
```
State Growth   → memory pressure / residency constraint
State Lifetime → residency demand
State Reuse    → shared-state value
State Access   → working set
```

阶段出口：确认 Execution State 是否足以作为 Model/Computation 与 Runtime resource behavior 之间的有效中间抽象。

## 4. P4-C — Resource Behavior → Runtime Mechanism

研究资源行为如何约束 Runtime 机制，而不是预设某一种实现。

重点：Loading、Residency、Layering、Working Set。

阶段出口：如果相同资源行为可以由多个机制等价实现，则结论停留在 Resource Semantics，不强行规定 Runtime 结构。

## 5. P4-D — Migration / Placement

研究 Execution State 是否可以成为 Runtime 中可迁移、可放置、可重新承载的资源语义对象。

候选转换包括：
```
CPU ↔ GPU ↔ Memory ↔ External
Active ↔ Warm ↔ Cold
```

要求：迁移/放置不得破坏 Execution State 的 identity、continuation 与 lifecycle semantics。

## 6. 最终跨架构问题

在前述阶段分别成立后，再研究：
> 不同计算架构的 Execution State 是否能够用一套共享的执行语义描述，而不要求统一物理表示？

## 7. 逐项推进规则

每一项固定经过：
```
① Research Object
② Research Question
③ Independence
④ Estimand
⑤ Existence Criterion
⑥ Negative Criterion
⑦ Discriminating Power
⑧ Information Value / Cost
⑨ Path / Harness / Experiment
⑩ Evidence → Finding → Decision → Closure
```

当前只推进 P4-A 的 STEP①。完成 STEP① 后，再决定是否进入 STEP②；P4-B/C/D 不获得隐含授权。

## 8. 当前边界
- 不研究模型全部知识、语义、概率或知识压缩；
- 不穷举模型内部边界；
- 不预设 Universal Model Unit；
- 不预设 Universal Physical Representation；
- 不把 Track B 的实验结果转移为 P4 结论；
- 不在 RQ 尚未定义前实现、采数、测量或构建 harness。