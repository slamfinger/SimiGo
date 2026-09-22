# P4-A：与 Track B 的边界对抗及研究对象再压缩

日期：2026-09-22
状态：概念研究 / STEP① 审查
RQ：未分配
实验：未授权

## 1. 本轮问题

上一轮发现，使用“反事实干预 continuation-relevant information”寻找 Execution State，容易重新进入 Track B 已经验证的 fork / continuation / state manipulation 路径。

因此本轮直接攻击：

> 如果 Track B 已经证明 Execution State 可以被 fork、continue、reattach、discard，那么 P4-A 还需要证明什么？

## 2. Track B 已经关闭的命题

Track B 已经在其限定范围内验证了：

- Execution State 可以作为 continuation 的可操作抽象；
- fork 后 parent / child continuation correctness 可保持；
- 不同 State component 可以采用不同 fork semantics；
- shared / segmented representation 可以重新 materialize / reattach；
- discard 不破坏 parent；
- bounded lifecycle 可以成立。

因此 P4 不应重新证明：

- State 是否存在；
- State 是否可 fork；
- State 是否能继续计算；
- State 是否能 reattach；
- State 是否可以作为运行时操作对象。

这些属于 Track B 的历史基础，不能重新注册成 P4-A 的新发现。

## 3. P4-A 如果继续，必须改变问题

P4-A 的真正新增问题只能是：

> **不同计算架构是否诱导出不同的 continuation dependency / State characteristics？**

其最小关系应为：

Architecture Feature
→ Computation Dependency
→ Continuation Requirement / State Characteristic

而不是：

Architecture Feature
→ State exists

## 4. 第一攻击：架构差异可能只是实现差异

成立。

两个架构的实现可能使用不同的数据结构，但 continuation semantics 完全相同。

因此：

physical representation difference ≠ architectural continuation difference

P4-A 不能以 tensor layout、cache layout、具体对象数量等直接作为架构差异。

## 5. 第二攻击：架构差异可能导致相同 State characteristic

也成立。

不同计算架构可能最终都只需要：

- 相同类型的历史信息；
- 相同的 continuation dependency；
- 相同的生命周期；
- 相同的可重用性。

如果如此，P4-A 得到的不是“每种架构都有独特 State”，而可能是：

> 不同架构共享某种 continuation semantic。

这反而可能成为 Architecture 2.0 的重要结果。

## 6. 第三攻击：架构差异也可能被 workload 抵消

同一架构在不同 workload 下可能表现出不同 State characteristics。

因此不能写成：

Architecture → State Property

更准确的是：

Architecture × Computation Context / Workload
→ Continuation Dependency

因此 P4-A 的结论必须绑定 computation context。

## 7. 第四攻击：如果所有架构都表现一样怎么办？

这是合法的负面结果。

如果在有区分力的架构比较中，所有观察到的 continuation dependency 都可以用同一个抽象解释，那么：

- 不应强行寻找 architecture-specific State；
- P4-A 可以转向“architecture-independent continuation semantics”；
- 甚至可以成为跨架构 Execution Semantics 的正向证据候选。

所以 P4-A 的目标不是证明“不同架构一定不同”。

## 8. 第五攻击：P4-A 是否只是 Track B 的横向扩展？

存在这个风险。

如果 P4-A 最终只是：

架构 A → fork
架构 B → fork
架构 C → fork

然后比较 fork 是否成功，

那么它没有真正离开 Track B。

因此“fork correctness”不能成为 P4-A 的区分变量。

P4-A 必须比较的是：

> 在相同 continuation semantics 目标下，不同架构对“继续计算所需信息”的依赖结构是否不同。

## 9. 第六攻击：什么才算真正新的 State characteristic？

候选不应是具体表示，而应是架构诱导的关系，例如：

- 依赖的是历史全部信息还是可压缩摘要；
- 依赖关系是否随时间增长；
- 是否存在不可替代的历史依赖；
- continuation dependency 是否具有不同的增长 / 衰减 / 重建性质；
- 某类状态是否具有不同的 reuse / materialization 条件。

这些仍只是候选属性，不是已成立结论。

## 10. 当前最重要的边界

Track B：

> 给定 Execution State，研究它的生命周期操作是否正确、可复用、可迁移。

P4-A：

> 给定不同计算架构，研究它们对 continuation-relevant information 的依赖是否呈现稳定、可比较的差异或共同结构。

因此：

Track B = State lifecycle semantics

P4-A = Architecture-induced State dependency

二者可以连接，但不能互相替代。

## 11. P4-A 当前最小研究对象

经本轮压缩，暂定为：

> **在明确计算上下文下，由计算架构差异诱导的 continuation dependency / State characteristic。**

这里暂时不定义具体 State 对象，不定义 Runtime 单元，也不定义物理表示。

## 12. 当前判断

本轮没有关闭 P4-A。

但关闭了一个错误入口：

> 通过重新操作 State 来“发现 State”。

Track B 已经承担了 State 的可操作性基础，因此 P4-A 不应再次证明 State existence / forkability。

P4-A 若继续，其新增价值必须来自：

Architecture → Computation Dependency → Continuation Dependency

而不是：

Architecture → Forkable State

## 13. 下一刀

继续攻击：

> “Continuation Dependency”是否只是对计算图/算法依赖关系的另一种命名？

如果答案是肯定的，P4-A 可能没有独立研究对象，应关闭或并回已有计算架构研究。

如果答案是否定的，则必须找出它与普通 computation dependency 的最小不可约差异。

仍不进入实验。
