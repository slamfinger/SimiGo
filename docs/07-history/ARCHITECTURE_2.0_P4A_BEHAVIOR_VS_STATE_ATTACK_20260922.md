# P4-A STEP①：Behavior Difference ≠ State Difference 对抗性研究

日期：2026-09-22
状态：概念研究 / STEP① 审查
RQ：未分配
实验：未授权

## 1. 本轮攻击目标

当前最危险的逻辑跳跃是：

> 观察到不同 continuation behavior → 推断存在不同 continuation state。

这个推断并不自动成立。

同一个可观察结果差异，可能来自不同计算路径、随机因素、外部环境、数值误差或其他中间机制。因此本轮不证明 State，而是寻找把“行为差异”归因于 State 所必须满足的最小条件。

## 2. 第一攻击：相同 State 也可能产生不同结果

如果 continuation environment 中存在随机种子、时间、外部资源或非确定性操作，则：

State 相同 ≠ Behavior 必然相同。

因此必须先限定 computational environment，否则行为不是 State 的单独函数。

研究形式应更接近：

Behavior = F(State, Continuation, Environment)

而不是：

Behavior = F(State, Continuation)

## 3. 第二攻击：不同 State 也可能产生相同结果

这是更直接的问题。

两个状态可能在当前 probe 下产生完全相同的输出，但在另一个 continuation 下分叉。

所以：

single-probe equality ≠ state equality

这意味着 probe 的价值不是证明“相同”，而是寻找反例。

一个 probe 能做的是：

Behavior(s1,c) ≠ Behavior(s2,c)
→ s1 与 s2 在该 continuation scope 下不可等价。

它不能直接证明：

Behavior(s1,c) = Behavior(s2,c)
→ s1 = s2。

## 4. 第三攻击：行为差异可能只是计算路径差异

即使环境固定，两个实现也可能采用不同的计算路径，并在某个中间阶段产生不同表示，最终造成行为差异。

这仍然不能直接得到：

Architecture Difference → Execution State Difference。

更谨慎的因果链是：

Architecture Difference
→ Computation Dependency Difference
→ Future Continuation Capability Difference
→ Observable Behavior Difference

此时“State”是解释 continuation capability 的抽象，而不是从单次行为差异中反向强行恢复出来的实体。

## 5. 第四攻击：什么证据才允许引入 State？

需要至少出现一种跨 continuation 的稳定结构：

1. 行为差异可以被一组未来 continuation probe 重复激活；
2. 差异与当前历史/计算上下文具有稳定对应关系；
3. 当相关历史信息被保留、丢弃或重建时，差异呈现可预测变化；
4. 这种变化不是单一输出上的偶然差异，而影响一类未来延续。

注意：第 3、4 条是未来实验可能检验的证据标准，不是当前已获得的实验结果。

## 6. 第五攻击：反事实才更接近 State

真正有价值的不是“两个模型现在输出不同”，而是：

> 如果只改变某个 continuation-relevant information，未来行为是否随之改变？

概念上可以写成：

Current Context H
→ candidate information I
→ continuation behavior B

构造反事实：

H + I
vs.
H − I / reconstructed(I)

如果未来 continuation behavior 系统性改变，则 I 具有 continuation relevance 的证据更强。

但这里仍有一个危险：

“删除 I”可能同时改变很多其他计算条件。

因此真正需要的是 controlled intervention，而不是简单删除某块数据。

## 7. 第六攻击：不要把物理缓存直接当作 State

例如：

physical cache retained
≠
continuation-required information

因为一个缓存可能：
- 可被重算；
- 只是性能优化；
- 可以由其他信息恢复；
- 对某些 continuation 有用，对另一些没有用。

因此 Execution State 的语义层必须与 physical representation 分离。

更合理的三层：

Semantic continuation information
→ Representation
→ Physical resource

## 8. 第七攻击：如果 State 可以被完全重建，它还算 State 吗？

可以。

只要它描述的是：

> 为保持 continuation semantics 所需要的信息关系。

是否长期物理保存是另一个问题。

因此：

semantic existence
≠
physical persistence

而：

physical persistence
≠
semantic necessity

这保持了此前 RM-047 的边界。

## 9. 当前最小归因条件

目前不能说“行为差异证明 State”。

更强的最低条件应是：

> 在受控 continuation environment 中，存在一个可干预的候选信息关系；改变该关系会稳定改变一类未来 continuation behavior，并且该效应可以与其他计算条件变化区分。

这实际上把研究从：

“观察差异”

推进到了：

“寻找可反事实干预的 continuation-relevant information”。

## 10. 一个新的负面边界

如果未来只能观察到：

Architecture A → Output A
Architecture B → Output B

却无法建立：

- continuation scope；
- 可重复差异；
- 反事实干预；
- 跨 probe 稳定性；
- 与其他计算因素的区分；

那么：

> 不得把 Output Difference 升格为 Execution State Difference。

最多只能保留为 Architecture/Computation behavior difference。

## 11. 当前判断

本轮没有关闭 P4-A。

但进一步压缩了 State 的进入资格：

> **Execution State 不能由“不同输出”反推；它至少需要表现为对未来延续行为具有可干预、可重复、可区分影响的信息关系。**

因此下一轮真正应该攻击：

> “可干预的 continuation-relevant information”是否仍然可能只是某种计算路径，而不是一个有独立研究价值的 State 抽象？

如果这个问题无法成立，P4-A 应该关闭，而不是继续给 State 概念增加保护条件。

## 12. 下一步

继续保持：
- 不新增 RQ；
- 不进入实验；
- 不建立 runtime；
- 不要求硬件；
- 不把 Architecture 2.0 扩展为模型知识研究。

下一轮攻击对象：

> **Continuation-relevant information 是否具有独立于具体计算路径的抽象价值？**

