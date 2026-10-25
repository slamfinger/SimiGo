# P4-A：语义投影的信息价值、成本判据与有限可描述性对抗

日期：2026-09-22
状态：概念研究 / STEP① 审查
RQ：未分配
实验：未授权

## 1. 本轮输入

本轮讨论提出三个关键修正：

1. “不同架构独立分析后自然出现共同语义维度”存在研究者先验污染，应降为辅助判据；
2. “语义投影是否有价值”应前置成本—信息价值判据；
3. 可能存在一个更深的幸存者：真实 Runtime 的转移系统不可枚举，有限资源迫使系统使用有限描述，而资源行为可能只依赖状态的低维投影。

本轮不接受这三点为结论，而对它们逐项证伪。

## 2. 第一攻击：自然涌现确实不是强证据

如果研究者已经知道 KV cache、working set、resident set、migration cost 等概念，再要求不同架构独立分析后“收敛”到这些维度，收敛可能来自共同教育、共同术语和共同研究传统。

因此：

自然收敛 ≠ 架构诱导。

结论：

> “自然涌现”最多是辅助证据，不能作为 P4-A 的主要 existence criterion。

更强的判据应转向预测、压缩和决策任务。

## 3. 第二攻击：预测优于直接命名，但“b ≈ a”仍不足以证明充分统计量

设：

(a) architecture-specific internal state
(b) semantic projection

比较二者对目标 resource behavior 的预测。

如果 b 的预测性能接近 a，可以说明在定义好的任务和观测范围内，b 保留了大量与该任务相关的信息。

但：

b ≈ a
≠
b 是全局充分统计量。

原因：

- 目标 resource behavior 只是全部未来行为的一部分；
- workload scope 会限制结论；
- predictor 本身可能补充了 projection 未表达的信息；
- 不同任务可能需要不同投影。

因此更严谨的命题是：

> b 是否是针对预先定义 resource-decision task 的 task-sufficient representation？

而不是宣称“状态的充分统计量”。

## 4. 第三攻击：非劣于专用状态并不自动成立，也不一定是正确门槛

“(b) 不劣于 (a)”听起来清楚，但必须先定义：

- 预测目标；
- 允许误差；
- 允许成本；
- 测量预算；
- 泛化范围。

更重要的是，(a) 拥有比 (b) 更多的信息，本来就可能预测得更好。

因此真正有意义的比较不是单纯：

prediction(b) ≥ prediction(a)

而是：

Information retained
vs.
instrumentation / adaptation cost
vs.
decision loss

也就是说，允许一个较小的 projection 在略有信息损失的情况下，显著降低 Runtime 适配成本。

## 5. 第四攻击：把 STEP⑧ 前置到 STEP①是合理的，但不能偷渡 STEP④–⑨

在 STEP① 阶段讨论“为什么这个对象值得研究”是合法的。

可以问：

> 如果这个 projection 即使存在，也不能减少任何有意义的 Runtime 决策成本，它还有没有成为研究对象的必要？

这是价值筛选，不是 estimand 注册。

因此可以提前定义：

Potential value = decision utility gained − instrumentation / adaptation cost

但不能在 STEP① 阶段直接声称具体 estimand、existence threshold、实验样本量或性能结果已经确定。

## 6. 第五攻击：资源行为低维性只是一个假设

最重要的幸存者候选是：

> Runtime resource behavior 可能是 Execution State 的低维函数。

这不是结论。

完全可能存在：

State = 高维结构
Resource behavior = 依赖大量微观细节

如果如此，一个小维度 semantic projection 会发生系统性信息损失。

因此必须允许：

low-dimensional projection hypothesis
vs.
high-dimensional dependence hypothesis

两者都是待证伪对象。

## 7. 第六攻击：低维 ≠ 唯一 ≠ 语义

即使发现一个低维 projection 能很好预测资源行为，也不能推出：

- 它是唯一 projection；
- 它就是“真实 State”；
- 它对应某个本体论对象；
- 它是所有 Runtime 任务的充分统计量。

最多得到：

> 在指定 resource-decision task、workload scope 和成本约束下，该 projection 保留了足够的信息。

因此“Execution State”最终可能是一个 task-relative abstraction，而不是 universal object。

## 8. 第七攻击：预测任务本身可能反向定义投影

如果我们先选择：

- residency prediction；
- migration cost prediction；
- loading decision；

然后设计一个 projection 专门优化这些任务，那么 projection 的成功可能只是 task-specific feature engineering。

这并不使研究无效，但必须明确：

> 成功证明的是 task-relative utility，而不是 universal semantic identity。

如果要主张跨 Runtime 生命周期的共同语义，则需要多个预注册任务，并检验同一 projection 是否同时保留多个任务所需信息。

## 9. 第八攻击：资源约束提供了非社会学锚点，但仍不保证存在低维摘要

“完整状态+转移关系理论上可表达一切”与“Runtime 无法支付完整描述成本”之间确实存在重要工程差异。

因此：

Theory:
Full State + Transition

Runtime:
Finite observation / finite storage / finite compute

这使“有限可描述性”成为一个合理研究问题。

但从：

有限资源
→ 必须压缩

不能推出：

压缩
→ 必然存在低维、稳定、跨架构 projection。

压缩也可能：
- 高维但稀疏；
- 非线性；
- 动态变化；
- task-specific；
- architecture-specific；
- 无法用固定语义维度表达。

因此资源约束只是提供研究动机，不是 projection existence proof。

## 10. 第九攻击：真正可能成立的命题

经过上述削弱，目前最干净的候选不是：

> Execution State 是状态的低维充分统计量。

而是：

> **在明确的 Runtime resource-decision task 与有限观测/计算预算下，是否存在一个跨架构、低复杂度的 State representation，使决策损失与直接使用架构专用状态相比保持在预先允许范围内，同时显著降低 instrumentation / adaptation cost？**

这是一个明确的 task-relative、cost-relative 命题。

它同时允许三种结果：

### A. 成立
存在稳定的跨架构低复杂度 representation，且 utility/cost 优势明显。

### B. 局部成立
只在特定 workload / resource task / 架构族成立。

### C. 失败
资源行为依赖高维或架构特定细节，projection 无法保持足够信息。

C 是合法研究结果。

## 11. 这改变了 Execution State 的最终身份候选

当前不再建议：

Execution State = universal state object

而是暂定：

> **Execution State = 面向继续计算与 Runtime resource decisions 的、可被压缩/投影/比较的计算状态描述层候选。**

其中“描述层”比“对象”更重要。

如果未来实验发现 projection 根本无法获得足够信息，则连这个描述层都应关闭或重新定义。

## 12. 当前 STEP① 判断

P4-A 仍未正式定义 RQ。

目前已排除：

- Execution State 是新的基础计算对象；
- future-not-fixed 自动产生独立 State；
- Continuation Dependency 天然独立于 Computation Dependency；
- 自然收敛可以单独证明共同语义；
- 资源有限必然产生低维 projection。

当前唯一值得保留的研究候选：

> **有限 Runtime 资源与决策任务是否诱导出具有足够信息价值的、低复杂度且可跨架构比较的 State representation。**

这已经开始逼近 STEP②–④ 的入口，但尚未进入。

## 13. 下一步攻击

下一刀应攻击：

> “低复杂度”究竟如何定义？

如果低复杂度只是“字段少”，它没有意义；
如果按模型参数量、描述长度、测量成本、推理成本、适配成本定义，又可能产生多个互不等价的 complexity。

必须先证明存在一个与 Runtime 决策真正相关的 complexity notion，否则“低维/低复杂度 projection”仍然只是漂亮的叙述。

仍不进入实验。
