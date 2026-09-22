# Architecture 2.0 P4：逐步证伪与实验条件门禁

日期：2026-09-22

## 1. 当前研究原则

P4 不以“证明 Execution State 是通用中间抽象”为目标，而采用逐步证伪路线：

> 先寻找最便宜、最直接的反例；只有当前命题经得住反例攻击，才进入下一层。

核心链：

Model Architecture → Computation → Execution State → Resource Behavior → Runtime

研究不要求每一层最终成立；任何一条关键关系被稳定证伪，都可以形成有效的 Negative Finding / Closure。

## 2. 最小证伪循环

每一阶段遵循：

1. 提出最小假设；
2. 寻找最低成本的反例；
3. 若失败，关闭该方向；
4. 若暂未失败，缩小命题并进入下一层；
5. 新架构只在真实反例出现时迫使抽象扩展；
6. 每次扩展后重新攻击旧结论。

因此：

> No counterexample, no new abstraction layer.

“无法跨架构泛化”本身也是合法研究结果。

## 3. P4 的逐层证伪门

### P4-A：Architecture → Execution State

先问：

> 一个明确的计算架构差异，是否稳定地产生可描述、与继续计算相关的 Execution-State 差异？

若无法稳定观察，P4-A 终止。

### P4-B：Execution State → Resource Behavior

只有 P4-A 成立后才进入：

> Execution State 的属性是否稳定地产生资源行为后果？

重点观察 State growth、lifetime、reuse、access、transition 与 working set、residency、loading/materialization、reuse cost 等关系。

若 State 差异不能解释稳定资源差异，不强行把 Execution State 作为 Runtime 核心抽象。

### P4-C：Resource Behavior → Runtime

只有 P4-B 成立后才研究：

> 资源行为是否能够被 Runtime 机制稳定利用？

不预设某一种实现。

### P4-D：Migration / Placement

只有 P4-C 有稳定信息价值后，才研究 Execution State 是否可以作为跨资源迁移、驻留和放置的语义单位。

### P4-E：Post-Training → Execution-State Behavior

后训练方向属于候选扩展，不提前授权。

只有 A/B 已形成稳定关系后，才测试：

Post-Training → Computation / Execution-State Behavior → Resource Behavior

其目标不是预设“后训练一定能够改造 Execution State”，而是寻找反例。

## 4. 硬件条件门

研究阶段不以“先搭完整硬件设施”为前提。

遵循：

理论可证伪 → 低成本观测 → 小规模实验 → 判断研究价值 → 再增加硬件 → 高成本实验

而不是：

先扩大硬件 → 再寻找办法让假设成立。

硬件不足时，首先降低实验规模、控制变量、缩小模型或缩短任务，只要仍然能够区分候选命题即可。

只有证据明确表明当前硬件已经成为决定性限制，并且前置命题已经通过证伪门，才考虑增加硬件能力。

## 5. 资源投入原则

禁止因为已有硬件投入而继续维持一个已经失去研究价值的方向。

硬件扩充必须回答：

- 当前已经通过了哪一个研究门？
- 下一步哪一个问题无法在现有条件下区分？
- 新硬件增加的实验能力是什么？
- 如果新实验失败，能够关闭哪个命题？

如果不能回答上述问题，不增加硬件。

## 6. 当前研究状态

本文件不创建新的 RQ，不授权实验，不改变 P4 当前 Definition Gate。

当前唯一合法动作仍是：

> 完成 P4-A STEP① 研究对象审查，然后才决定是否进入 STEP②。

本文件的作用是为后续研究增加“逐步证伪 + 条件门禁”原则。
