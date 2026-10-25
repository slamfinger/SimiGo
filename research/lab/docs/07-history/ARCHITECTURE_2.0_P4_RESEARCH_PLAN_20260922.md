# Architecture 2.0 — P4 研究方案：Execution State → Resource Behavior → Model-side Shaping

Date: 2026-09-22
Status: Research Plan / Definition Gate still active / NOT STARTED
RQ: 未分配；本文不构成 RQ 注册

## 1. P4 的总体目标

P4 不把目标定义为“研究大模型内部所有结构”，也不把目标定义为“找到 Universal Model Unit”。

P4 的核心目标是验证一条受约束的计算架构关系：

> 不同计算架构如何诱导不同的 Execution State，以及这些 State 特征如何进一步形成可观察、可利用的资源行为。

在此基础上，再逐步验证 Runtime 是否能够利用这些 State 语义，以及一个更进一步的假设：

> 如果 Runtime 资源行为与 Execution State 存在稳定关系，那么后训练是否能够反向塑造模型的 Execution-State behavior，使模型本身更适合长上下文、多轮连续计算和状态化 Runtime。

因此 P4 最终形成的候选闭环为：

Model Architecture → Computation → Execution State → Resource Behavior → Runtime

以及尚待验证的反向路径：

Post-Training → Computation / Execution-State Behavior → Resource Behavior → Runtime

注意：后训练路径目前是 P4 的候选扩展假设，不因本方案自动获得实验授权。

## 2. P4 的核心研究对象

当前最小研究对象保持为：

> 一种可明确描述的计算架构差异 → 一个受其影响的 Execution State 属性 → 一个可观察的后果。

其中：

### 2.1 Computation Architecture

只研究能够影响 continuation-relevant state 的计算架构差异，例如：

- 状态是否随上下文增长；
- 状态是否具有历史依赖；
- 状态是否可共享；
- 状态是否分叉；
- 状态是否具有独立生命周期；
- 状态是否需要 materialize / reconstruct / reattach；
- 状态访问是否具有不同局部性或依赖关系。

不因为某结构属于模型架构就自动纳入 P4。

### 2.2 Execution State

工作定义：

> 为了从当前计算位置继续执行而必须被保留、恢复、共享、物化或转移的 continuation-relevant state。

重点属性：

1. type
2. growth
3. dependency
4. reuse
5. lifetime
6. access
7. transition
8. materialization / representation transition
9. future-use relation

### 2.3 Resource Behavior

关注：

- resource occupancy
- state availability
- working set
- loading / materialization cost
- residency demand
- reuse benefit
- migration cost
- lifecycle transition cost

## 3. P4 的研究原则：由小到大，而不是由大到小

P4 不从“所有模型”开始。

采用：

一个代表性计算架构 → 一个最小 State 抽象 → 一个资源后果 → 一个真实反例 → 最小必要扩展 → 再验证

即：

> 先证明一个关系，再扩大关系；先寻找反例，再增加抽象。

没有真实反例，不增加新的抽象层。

如果新的真实架构迫使抽象发生大幅变化，则暂停泛化并重新检查研究边界。

“不能泛化”本身是合法结果。

# 4. P4-A：Architecture → Execution State

## 4.1 目标

回答：

> 一个明确的计算架构差异，是否能够稳定地诱导一个可描述的 Execution-State 差异？

## 4.2 最小关系

Architecture Feature → Computation Dependency → Required Continuation State

## 4.3 第一轮只选择一个代表性架构

不同时研究 Attention、GDN、MoE、Hybrid 等所有类型。

第一轮选择一个能够明确描述 continuation state 的代表性架构，建立最小抽象。

选择标准：

- 架构机制明确；
- State 有明确 continuation relevance；
- State 生命周期可描述；
- 可以产生可区分的状态特征；
- 后续存在现实的第二架构作为反例候选。

## 4.4 P4-A 的主要问题

暂定候选问题：

> 哪些可明确描述的计算架构特征，会稳定地改变 Execution State 的 type、growth、dependency、reuse、lifetime、access 或 transition 属性？

这仍须经过正式 STEP② 才能成为 RQ。

## 4.5 P4-A 出口

形成：

Architecture → Computation → Execution-State Characteristic Map

出口条件：

- State 差异可以被明确描述；
- 差异具有重复性；
- 差异不是单纯语义标签；
- 差异与 continuation 有明确关系；
- 不依赖 Universal Physical Representation。

# 5. P4-B：Execution State → Resource Behavior

只有 P4-A 合法 closure 后进入。

## 5.1 核心问题

> Execution State 的哪些属性会稳定地产生资源行为后果？

重点关系：

State Growth → Memory / Working-Set Pressure

State Lifetime → Residency Demand

State Reuse → Reuse Value

State Access → Working-Set / Locality

State Transition → Loading / Materialization Cost

## 5.2 关键目标

验证 Execution State 是否真的是：

> Model / Computation 与 Runtime Resource Behavior 之间有信息价值的中间抽象。

如果 State 信息不能比直接观察 Runtime 指标提供额外解释能力，则不能强行把 Execution State 定义成 Runtime 的核心抽象。

## 5.3 出口

形成：

Execution-State Property → Resource Behavior

的可复核映射。

# 6. P4-C：Resource Behavior → Runtime Mechanism

只有 P4-B 成立后进入。

## 6.1 目标

不预设 Runtime 的具体实现，而研究：

> 给定 Resource Behavior，哪些 Runtime 机制是必要的、可替代的或无关的？

重点：

- Loading
- Residency
- Layering
- Working Set
- Reuse
- Discard

如果多个 Runtime 机制能够产生等价的资源语义：

> 结论停留在 Resource Semantics，不强行规定一种 Runtime Architecture。

因此：

Resource Semantics ≠ Implementation Choice

# 7. P4-D：Migration / Placement

只有 P4-C 合法 closure 后进入。

研究 Execution State 能否成为 Runtime 中可迁移、可放置、可重新承载的资源语义对象。

候选状态：

Active ↔ Warm ↔ Cold ↔ External / Reconstructable

候选位置：

CPU ↔ GPU ↔ Memory ↔ External

核心约束：

> Migration / Placement 不得破坏 Execution State 的 identity、continuation 和 lifecycle semantics。

这一阶段的目的不是寻找固定的“最佳放置策略”，而是确认：

> Execution State 是否足以作为跨资源层迁移的语义单位。

# 8. P4-E：Post-Training → Execution-State Behavior

这是本次新增的核心候选扩展。

P4-E 不在当前 Definition Gate 中自动启动。

它建立在 P4-A/B 至少获得稳定关系之后。

## 8.1 核心假设

> 受控后训练数据分布与任务分布，可能稳定改变模型在目标任务分布下形成、使用、复用和终止 Execution State 的方式，并进一步改变 Resource Behavior。

目标不是直接改变“模型知道什么”，而是研究：

> 能否改变模型如何计算、如何形成状态、如何复用状态以及状态如何持续。

## 8.2 后训练在这里扮演什么角色

不是：

Post-Training → Output Alignment

而是增加：

Post-Training → Computation / Execution-State Behavior

因此可能形成：

Training Distribution
→ Computation Behavior
→ Execution State
→ Resource Behavior

## 8.3 高频 / 低频必须重新定义

不能直接研究“模型里的高频知识 / 低频知识”。

必须区分：

- Workload Frequency
- State Activation Frequency
- State Reuse Frequency
- State Lifetime
- Resource Occupancy

不能从 State Frequency 直接推断 Knowledge Frequency。

## 8.4 P4-E 的最小验证阶梯

E1 — Repeatability：同一受控任务分布是否产生稳定的 State 特征？

E2 — Discriminability：不同任务分布是否产生可区分的 State 行为？

E3 — Directionality：改变后训练任务/数据分布后，State 行为是否发生方向一致的变化？

E4 — Resource Effect：State 行为变化是否进一步改变 resource occupancy、reuse、residency demand、transition cost、working-set behavior？

E5 — Capability Preservation：行为改变是否保持原有能力，特别观察 output quality、long-context behavior、multi-turn continuation、task coverage。

E6 — Runtime Leverage：Runtime 是否能够实际利用被塑造后的 State 行为？

E7 — Cross-Architecture：换一个真实不同的计算架构后，原抽象是否仍成立、哪个部分失效、最小扩展是什么、是否需要放弃该抽象。

# 9. P4-E 最重要的实验逻辑

不能从：

限定数据 → Execution State → 完整模型架构

直接推导。

正确逻辑是：

Controlled Workload
→ Computation Response
→ Observable Execution-State Feature
→ Repeatability / Discriminability
→ Resource Consequence

然后才研究：

Post-Training Intervention
→ State Behavior Change
→ Resource Behavior Change

因此：

> 限定任务分布首先是一个 probing method；后训练是否能够利用这种关系，是第二层问题。

# 10. P4 的跨架构泛化方案

P4 不追求一次性证明“所有大模型”。

采用增量泛化：

Stage 1：架构 A

A → State-A → Resource-A

建立最小抽象。

Stage 2：引入架构 B。

不是先修改理论，而是先问：

> A 的抽象能否自然描述 B？

Stage 3：如果失败，记录具体反例：

Counterexample → Failure Location

然后寻找：

Minimal Necessary Extension

Stage 4：重新验证 A + B。

Stage 5：再进入架构 C。

最终得到的不是：

“所有模型都有完全相同的 State。”

而是：

> 不同计算架构是否存在足够稳定的共享 Execution Semantics。

# 11. P4 的完整 Gate

每一个子阶段都必须独立通过：

① Research Object
→ ② Research Question
→ ③ Independence
→ ④ Estimand
→ ⑤ Existence Criterion
→ ⑥ Negative Criterion
→ ⑦ Discriminating Power
→ ⑧ Information Value / Cost
→ ⑨ Path / Harness / Experiment
→ ⑩ Evidence → Finding → Decision → Closure

当前只允许：

> P4-A STEP① 研究对象审查。

P4-B/C/D/E 均不获得隐含实验授权。

# 12. P4 的成功条件

P4 不以“证明一套完整 Architecture 2.0”为成功标准。

至少存在四种合法结果：

### Result A — Stable Relation

Architecture → Execution State → Resource Behavior

稳定成立。

### Result B — Partial Generalization

关系只在部分架构成立，但边界可以明确描述。

### Result C — Counterexample

不同架构之间无法维持当前抽象。

“不能泛化”成为研究结果。

### Result D — Model-side Shaping

进一步证明后训练能够稳定改变 Execution-State behavior，并产生可利用的 Resource Behavior 改变。

只有达到 D，才可以进一步讨论：

> Execution-State-oriented Post-Training 是否构成一种新的模型改造路径。

# 13. 最终可能形成的 Architecture 2.0

如果各阶段分别成立，最终架构不是简单的：

Model → Runtime

而可能是：

Model Architecture
→ Computation
→ Execution State
→ Resource Behavior
→ Runtime

同时：

Post-Training
→ Computation / Execution-State Behavior
→ Resource Behavior

形成双向闭环：

Training / Model
↕
Execution State
↕
Runtime

这将使 Architecture 2.0 的研究对象从“Runtime 如何适配大模型”进一步扩展到：

> 如何通过可验证的训练与运行时机制，共同塑造大模型的计算状态行为。

但这一最终表述只作为远期研究假设，不作为当前已证实架构。

# 14. 当前执行结论

P4 当前仍然：

NOT STARTED / NOT DEFINED

当前唯一合法动作：

> 完成 P4-A STEP① 研究对象审查。

下一步不是写代码，也不是立即做后训练实验。

下一步应该把 P4-A 的研究对象压缩到一个可以在不依赖实验的情况下定义清楚、可以被证伪、可以独立估计的 Research Question 候选。

只有该候选通过 Definition Gate，才进入正式研究。
