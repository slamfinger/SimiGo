# P4-A STEP① 研究对象对抗性审查

日期：2026-09-22
状态：概念研究 / STEP① 审查中
RQ：未分配
实验：未授权

## 1. 研究目的

本轮不是证明 P4，而是主动寻找当前研究对象定义的最小反例、循环定义和不可观测点。

当前工作定义：

> 由一种可明确描述的计算架构差异所诱导、并影响计算继续执行所需状态的一个 Execution State 属性及其可观察后果。

## 2. 第一攻击：Architecture → State 是否一一对应？

不成立，至少不能作为强命题。

同一计算架构可以存在不同实现方式；同一个 continuation requirement 也可能通过不同物理表示承载。

因此不能写成：

Architecture Feature → 唯一 State Representation

较弱且可研究的关系应是：

Architecture Feature → Computation Dependency → Continuation Requirement

再由实现决定具体承载形式。

这意味着 P4 不应把“发现某个 State tensor / buffer”当作发现架构规律本身。

## 3. 第二攻击：Execution State 是否存在循环定义？

当前定义：

> 为了从当前计算位置继续执行而必须被保留、恢复、共享、物化或转移的 state。

这里的“必须”是关键，但“必须”不能仅由观察到的实现对象决定。

例如某实现保留一个缓存，并不自动说明该缓存是语义上不可替代的 continuation state；它可能可以被重算。

因此必须区分：
- physical retained data；
- implementation cache；
- reconstructable intermediate；
- continuation-required information。

当前研究对象若不能做这个区分，会把“当前实现怎么存”误认为“计算继续执行真正需要什么”。

## 4. 第三攻击：同一 State 是否一定产生不同 Resource Behavior？

也不能预设。

即使两个 State 在 continuation semantics 上不同，它们仍可能在某一硬件、某一 workload 下表现出近似相同的资源行为。

因此：

State difference → Resource difference

必须作为后续可证伪关系，而不是定义的一部分。

## 5. 第四攻击：语义 State 是否可观察？

不能假设。

真正可观察的往往是：
- retained representation；
- access pattern；
- growth；
- lifetime；
- reconstruction / materialization；
- reuse；
- resource occupancy。

但这些是 State 的代理或后果，不等于 State 本身。

因此 STEP① 应允许：

Semantic State → observable proxy

而不要求直接“看见 State 本体”。

## 6. 第五攻击：同一 State 是否可能跨 workload 变化？

可能。

Execution State 不是静态模型属性，而可能是：

Architecture + Input / Workload + Computation trajectory → State instance

因此研究对象不能写成：

Architecture → State

更准确的最小关系应为：

Architecture Feature + Computation Context → Continuation Requirement → State Characteristic

这不会把 workload 当成“知识本体”，而是承认执行状态本身具有轨迹依赖。

## 7. 第六攻击：硬件不足是否会阻断 P4？

不必然。

STEP① 的核心关系可以先在语义层进行审查：

Architecture Feature → Computation Dependency → Continuation Requirement

只有进入 State → Resource Behavior 后，硬件条件才逐渐成为决定性因素。

因此当前阶段没有必要先解决完整硬件设施。

## 8. 当前最重要的负面知识

截至本轮审查，以下强命题应主动排除：

1. Architecture Feature 唯一决定物理 State Representation；
2. 观察到的 retained tensor / buffer 必然就是 continuation state；
3. State 差异必然导致 Resource Behavior 差异；
4. State 本体可以直接、无歧义地被观察；
5. Execution State 是模型的静态属性；
6. P4 必须先具备大型硬件才能开始。

这些命题均不应作为 P4 的前提。

## 9. 当前最小稳定对象候选

经过对抗性审查后，当前更稳的对象表达为：

> 一个可明确描述的计算架构差异，在给定计算上下文下，对“继续计算所需信息”的依赖关系造成的可区分变化。

对应链：

Architecture Feature → Computation Dependency → Continuation Requirement → State Characteristic → Observable Proxy

其中：
- Continuation Requirement 是语义核心；
- State Characteristic 是研究描述层；
- Observable Proxy 是实验可观测层。

这比直接把某个物理 State 对象作为研究对象更不依赖具体 Runtime / Framework。

## 10. 当前结论

本轮没有关闭 P4。

但发现了一个重要边界：

> P4 的第一层不应研究“State 长什么样”，而应首先研究“计算继续执行究竟依赖什么信息”。

如果这个层次都无法形成稳定、可区分、与架构差异有关的关系，则无需进入资源行为研究。

下一合法动作仍然不是实验，而是继续完成 STEP① 的对象审查，并判断上述“Continuation Requirement”是否足以形成独立、可证伪的 RQ 候选。