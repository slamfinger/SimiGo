# P4-A STEP①：Continuation Probe 判别集对抗性研究

日期：2026-09-22
状态：概念研究 / STEP① 审查
RQ：未分配
实验：未授权

## 1. 本轮目标

上一轮将 Continuation Requirement 收缩为未来延续语义中的区分关系。本轮继续攻击：

> 有限 continuation probes 是否能够提供足够的信息，区分真正影响继续计算的状态差异？

## 2. 第一攻击：有限 probe 不可能证明全空间等价

成立。

如果允许的未来延续集合 C 无限或极大，有限 probe 集 P ⊂ C 永远不能证明：

对所有 c ∈ C，Behavior(s1,c) = Behavior(s2,c)。

因此实验不能声称发现“绝对 continuation equivalence”。

研究结论必须限定为：

> 在定义好的 probe domain P / C_scope 内观察到的 continuation distinguishability。

这不是致命问题，但要求研究对象从一开始就带有 scope。

## 3. 第二攻击：随机抽样可能完全错过关键差异

存在。

两个状态可能在绝大多数普通 continuation 上表现一致，只在极少数 continuation 上分叉。

因此随机 probe 的“多数一致”不能推出等价。

这直接对应此前的高频/低频问题：低概率并不意味着无意义。

所以 probe 设计不能只追求覆盖率，还必须寻找高区分度 continuation。

## 4. 第三攻击：如何寻找高区分度 probe？

可以把 probe 看作对当前状态差异的主动攻击，而不是普通 workload sampling。

候选策略不是“随机多测”，而是：

1. 先确定状态差异候选；
2. 找到最可能依赖该差异的未来操作；
3. 构造最小 continuation；
4. 看是否产生可重复行为分叉；
5. 若不能分叉，则降低该 State 差异的 continuation relevance。

这使研究从 passive observation 转向 falsification-oriented probing。

## 5. 第四攻击：如果 probe 本身依赖未知 State，就循环了

这是当前最危险的问题之一。

如果我们必须先知道 State 才能设计 probe，那么就无法用 probe 独立发现 State。

因此第一阶段 probe 不应要求知道具体 State 表示。

更安全的输入是：

Architecture difference + computation context + admissible continuation operation

输出观察的是 continuation behavior。

即：

Architecture → computation context → continuation probe → observable behavior

而不是：

先看见 State → 再设计 probe → 证明 State 存在。

## 6. 第五攻击：行为差异也可能来自随机性或外部因素

成立。

因此一个 probe 产生一次行为差异不足以证明 continuation state 差异。

最低要求应包括：

- 固定环境；
- 明确随机性处理；
- 重复 probe；
- 排除外部状态变化；
- 比较差异的稳定性。

这些是未来实验条件，不是当前已完成的实验。

## 7. 第六攻击：最小 probe 集是否存在？

不能假设存在一个全局最小 probe 集。

更合理的是定义相对于一个研究范围的：

> sufficient probe set

即在给定架构、计算上下文和候选差异范围内，能够稳定区分至少一个目标 continuation property 的最小或近似最小 probe 集。

因此未来可以研究：

Probe set size ↔ distinguishability ↔ cost

而不是寻找所谓 Universal Probe Set。

## 8. 第七攻击：如果所有 probe 都区分不出来呢？

这是合法的关闭条件。

若在预先定义的 probe domain 内，经过足够的 adversarial probes 仍没有稳定差异，则不能说 State 一定不存在；但可以得到：

> 在该研究范围与观测能力下，没有发现架构差异导致 continuation behavior 的可区分变化。

如果这已经覆盖了 P4-A 所声称的最小对象范围，则可以关闭该研究线。

## 9. 当前形成的三级证伪结构

### Level 1：存在性

是否存在任何 continuation probe，使架构差异对应的状态关系产生可重复行为差异？

### Level 2：稳定性

这种差异能否在重复试验、受控环境下稳定出现？

### Level 3：区分度

差异是否足够明显，能够排除随机性、实现噪声和普通输出偶然差异？

只有 Level 1–3 都成立，才有资格进入更高层的 State characterization。

## 10. 一个重要的新边界：观察对象可能不是 State，而是 State 的未来可区分能力

因此 P4-A 的研究对象进一步可以压缩成：

> **架构差异是否改变当前计算状态在限定未来延续空间中的可区分能力。**

这里不需要假定 State 的物理表示。

可以形成：

Architecture Feature
→ Computation Dependency
→ Future-Continuation Distinguishability
→ Observable Behavior

Execution State 仍然是解释这一关系的中间概念，但不再被要求先以一个物理对象被直接发现。

## 11. 当前结论

本轮没有关闭 P4-A。

但成功排除了一个不必要的强要求：

> 不需要证明一个 Universal Continuation Probe Set。

只需要在明确的研究 scope 内寻找足以攻击目标关系的 sufficient probe set。

同时确定一个真正的负面出口：

> 如果经过设计好的 adversarial probes，在限定 scope 内始终没有稳定、可重复的 continuation distinguishability，则 P4-A 可以在该 scope 内关闭。

## 12. 下一步

下一轮继续攻击“Future-Continuation Distinguishability”本身：

> 行为差异究竟如何排除“只是输出差异”，并证明它对应 continuation state 的差异，而不是任意计算路径差异？

仍不进入实验，直到 STEP① 完成。