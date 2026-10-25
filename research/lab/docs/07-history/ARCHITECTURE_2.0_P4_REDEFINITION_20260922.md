# Architecture 2.0 — P4 重新定义与构建

**Date:** 2026-09-22  
**Status:** Definition Gate preparation / NOT STARTED  
**RQ:** 未分配；本文不构成 RQ 注册

## 1. 为什么重新定义 P4

此前 P4 曾被概括为“核心驻留结构/状态机制”或“研究大模型如何分层、加载、驻留”。

这一表述过于直接地把 **Model Architecture → Runtime** 相连，容易把研究扩展为“研究所有模型架构”，进而重新进入模型内部知识、结构与表示的无限细分。

本次重新定义明确：

> P4 不研究“大模型架构本身”，而研究**计算架构诱导形成的 Execution State 及其资源生命周期特征**。

只有能够改变 Execution State 的形成、规模、依赖、复用、生命周期、访问或状态转换的架构特征，才进入 P4 的研究边界。

## 2. P4 的研究对象

暂定研究对象：

> **Architecture-induced Execution State：由不同计算架构形成、并对 Runtime 资源行为具有约束作用的 Execution State 及其特征。**

这里的“架构”指计算架构，不等于模型全部内部结构。

这里的“Execution State”指为了让计算继续执行而必须携带、保持、恢复或转移的状态语义。

这里的“资源行为”包括但不限于：

- Loading
- Residency
- Layering
- Working Set
- Migration
- Resource placement

## 3. Architecture 2.0 的三层边界

### 3.1 Model / Computation：怎么计算

不同模型可以采用不同计算机制：

`Attention → State_A`  
`GDN → State_B`  
`MoE → State_C`  
`Hybrid → State_D`

P4 不要求这些 State 具有相同物理表示。

### 3.2 Execution State：为了继续计算必须携带什么

Execution State 是 Model/Computation 与 Runtime 之间的抽象边界。

重点关注其：

- identity
- continuation position
- state type
- dependency
- growth pattern
- reuse relation
- lifetime
- access pattern
- representation transition

### 3.3 Runtime：如何承载这些状态

Runtime 面向 Execution State 组织：

- loading
- residency
- layering
- working set
- migration
- placement
- reuse
- discard

因此核心关系不是：

`Model Architecture → Runtime`

而是：

`Model Architecture → Computation → Execution State → Resource Behavior → Runtime Mechanism`

## 4. P4 的核心命题边界

P4 后续需要检验的不是“哪种模型最好”，也不是“模型应该怎样分层”，而是：

> **不同计算架构产生的 Execution State 特征，是否构成稳定且可观察的资源行为约束，并由此形成不同的 Runtime 承载机制。**

当前仅作为研究方向，不作为已验证命题。

## 5. 进入 P4 的架构特征过滤器

一个模型架构特征只有在能够影响以下至少一个 Execution State 属性时，才有资格进入 P4：

1. State type
2. State growth
3. State dependency
4. State reuse
5. State lifetime
6. State access
7. State transition
8. State materialization / representation transition
9. Future-use relation

反之，仅因为某结构“属于模型架构”而研究，不属于 P4。

## 6. 分层、加载、驻留的重新定义

### 6.1 Model layering ≠ Execution-State layering

模型内部层级描述的是计算结构。

Execution-State layering 描述的是状态的资源生命周期，例如：

`Active → Warm → Cold → External / Reconstructable`

两者不能互相替代。

### 6.2 Loading

P4 中 Loading 不预设为“磁盘 → 内存”。

更高层的定义是：

> Execution State 从不可直接参与当前计算的资源状态进入可继续计算状态的状态转换。

其实现可能包括 load、materialize、reconstruct、reattach、migrate 等。

### 6.3 Residency

Residency 不仅回答“状态在哪里”，还涉及：

- 可用性
- 资源占用
- 保持时间
- 可操作粒度
- 访问代价
- 状态转换代价

因此 Residency 是 Execution-State resource lifecycle 的一个组成部分，而非独立于 State 的简单内存位置属性。

## 7. 与 Track B 的关系

Track B 已 CLOSED / FROZEN，不重新打开。

P4 使用 Track B 作为历史基础约束：

`Execution State → identity / continuation / fork / reattach / discard`

P4 的新问题是：

`Architecture → Execution-State characteristics → resource behavior`

因此：

> Track B 是 P4 的前置知识来源之一，但不是 P4 的继续实验。

旧证据不得自动转移为 P4 的结论。

## 8. Universal Semantics ≠ Universal Representation

P4 不要求寻找 Universal Model Unit，也不要求所有模型拥有统一的物理 State layout。

目标应保持在：

> **Universal Execution Semantics / shared execution vocabulary**

而不是：

> Universal Physical Representation。

因此不同模型可以有不同 State：

`State_A, State_B, State_C...`

只要能够在更高层表达共同的 continuation / lifecycle semantics，即可成为 Runtime 抽象的候选基础。

## 9. P4 当前主链

`Model Architecture Features`
→ `Computation Dependency`
→ `Execution State`
→ `State Characteristics`
→ `Resource Behavior`
→ `Loading / Residency / Layering / Working Set / Migration`
→ `Runtime Architecture`

这是一条**研究方向链**，不是 RQ、Claim 或 Architecture authorization。

## 10. Definition Gate 状态

本文件完成的是 STEP① 的重新定义准备。

尚未完成：

- STEP② Research Question
- STEP③ Independence
- STEP④ Estimand
- STEP⑤ Existence Criterion
- STEP⑥ Negative / Insufficiency Criterion
- STEP⑦ Discriminating Power
- STEP⑧ Information Value / Cost
- STEP⑨ Path / Harness / Experiment

因此：

> **P4 仍为 NOT STARTED。本文不授权实现、采数或测量。**

## 11. 明确排除

以下方向继续保留为历史知识，但不属于当前 P4 主线：

- 模型全部知识与语义规律；
- 模型知识压缩；
- 全部概率结构；
- 穷举模型内部边界；
- Universal Model Unit；
- Boundary → Object → Actionability → Unit 的必经路线；
- 直接从 Model Architecture 跳到 Runtime Unit 的 implementation-first 路线。

## 12. 当前最小研究对象

P4 应尽量从最小对象开始：

> **一种可明确描述的计算架构差异 → 一个受其影响的 Execution State 属性 → 一个可观察的资源生命周期现象。**

在此之前，不扩大模型集合、不预设统一 State layout、不预设 Runtime unit、不进入实验。

