# Architecture 2.0 Long-Horizon Vision — 最重要思想资产

> 本文是 SimiGo 2.0 的长期思想资产档案。它保存的是未来架构可能继续生长的核心思想，不是当前生产架构、实现规格、研究结果或已注册 RQ。
>
> **Scope:** SimiGo-Lab / Architecture 2.0 only. SimiGo 1.x 产品线不在本文讨论范围。

## 1. 为什么需要保存这组思想

Architecture 2.0 的价值不只在已经完成的 Track B / Track E 研究结果，更在于一组可能改变问题边界的长期思想：

- 智能不等于模型文件；
- 模型不等于当前物理内存中的表示；
- Execution State 不只是 KV；
- Residency 不是一次 load/unload 动作，而是执行过程中的状态；
- runtime 不应只能管理“内存字节”，还应可能管理 execution、state、residency、migration 与 continuation；
- 分片单位不必服从模型语义层级；
- 最终目标不是“尽可能少占内存”，而是维持 **minimum sufficient working set**；
- Planner 可能成为 Execution State、Residency、Compute 三者之上的统一决策层；
- 计算结果本身可以被视为一种可复用的计算资产。

这些思想目前主要属于长期架构假设。它们之所以必须单独保存，是因为未来 Agent 如果只读取当前 RQ / Evidence / Closure，很容易知道“已经证明了什么”，却不知道“为什么 Architecture 2.0 可能继续向哪里生长”。

## 2. 第一性边界：智能 ≠ 模型文件 ≠ 物理内存

一个重要的长期抽象是：

```
Model semantics
      ≠
Logical executable state
      ≠
Physical resident representation
```

模型文件是知识与参数的持久化表示；Execution State 是某次执行所产生并携带的状态；physical memory 只是这些状态在某一时刻的承载位置。

因此可以进一步提出：

```
logical intelligence / execution capability
                ↓
       operational units
                ↓
       residency decisions
                ↓
      physical representation
```

物理内存不是“智能本身”，而是智能在某个执行时刻可被计算硬件使用的物理载体。

**长期意义：** 如果这一抽象成立，SimiGo 的研究对象就不必被“当前内存里装了什么”限定，而可以研究“什么逻辑能力需要在什么时候以什么物理表示驻留”。

**禁止推断：** 这不是已经证明模型可以任意脱离物理内存而保持可执行性。

## 3. 从 Memory Manager 走向 Execution Manager

传统 memory manager 主要回答：

> 哪些 bytes 在内存里？

长期 SimiGo 可能需要回答更高层的问题：

> 哪些 execution state / operational units 当前需要什么 residency，何时迁移，何时物化，何时共享，何时回收，以及如何保持 continuation？

候选控制对象：

```
Execution Manager
├── Execution State
├── Residency State
├── Migration / Materialization
├── Reuse / Sharing
├── Continuation
└── Lifecycle
```

这里的关键不是新增一个“Manager”类，而是**研究控制边界是否应该从 memory ownership 上移到 execution-aware resource management**。

## 4. Residency 是状态，不是动作

长期研究中应避免把 residency 简化为：

```
load()
unload()
```

更丰富的候选状态空间可能是：

```
non-resident
    ↓
materializing
    ↓
resident
    ↓
shared / partial
    ↓
migrating
    ↓
evicting
    ↓
recoverable
```

一个对象可能同时具有：

- logical existence；
- physical residency；
- shared/private status；
- migration status；
- execution association；
- recoverability。

因此未来的 residency 机制可能更接近 **state machine**，而不是简单的 memory operation。

## 5. “智能进入物理内存”应当是预测性的

被动式 memory pressure：

```
memory full
   ↓
evict something
```

可能不是长上下文 execution runtime 的最终形态。

更强的候选机制是：

```
execution frontier
      ↓
future access / co-access estimate
      ↓
working-set prediction
      ↓
residency planning
      ↓
materialize / migrate / evict
```

也就是说，runtime 不是等智能“撞到内存墙”后再处理，而是根据即将发生的执行行为决定什么应该提前进入物理内存。

**重要边界：** access prediction 的可预测性、预测误差代价、instrumentation cost 和 migration cost 均尚未验证。

## 6. Planner：Execution State + Residency + Compute 的统一上层

Architecture 2.0 的长期演化可能需要一个 Planner 层，把三个过去相对分离的问题统一起来：

```
              Planner
                 │
       ┌─────────┼─────────┐
       ↓         ↓         ↓
 Execution     Residency  Compute
   State       /Memory     Plan
```

Planner 的候选职责不是直接执行 kernel，而是决定：

- 当前执行需要哪些 operational units；
- 哪些单位应 resident；
- 哪些可以 shared / non-resident；
- 哪些应提前 materialize；
- 哪些状态值得复用；
- 哪些状态可以 fork；
- 哪些计算应执行、延迟或复用。

这仍是架构假设，不是当前 Runtime2 实现授权。

## 7. Runtime Sharding：分片可以由执行行为产生

传统 sharding 常从 deployment-time 结构出发：

```
model
→ layer
→ device
```

长期 SimiGo 可以探索：

```
runtime access graph
      ↓
co-access clusters
      ↓
operational units
      ↓
dynamic residency / migration groups
```

这意味着“分片”可能不是模型部署前一次性决定的，而可能是 runtime 根据执行行为形成或调整。

这与 RM-025 的 unit-discovery 原则一致：

> **先发现有独立机制身份的 operational unit，再决定如何 sharding。**

## 8. Execution-State Sharding

进一步地，真正值得分片的对象可能不是 model tensor，而是：

> **Execution State 的可独立管理部分。**

候选分解维度：

- continuation dependency；
- access dependency；
- residency dependency；
- migration dependency；
- sharing / COW dependency；
- recomputation boundary。

因此未来可能出现：

```
Model Sharding
      ↓
Execution-State Sharding
```

这不是把模型语义拆得更细，而是寻找“执行过程中可以独立管理”的最小充分单位。

## 9. 计算结果是可复用资产

Architecture 2.0 的一个重要思想延伸是：

> 一次昂贵计算产生的不只是“已经结束的计算”，还可能产生可以继续服务未来执行的计算资产。

候选生命周期：

```
Create
  ↓
Reuse
  ↓
Fork
  ↓
Continue
  ↓
Migrate
  ↓
Materialize
  ↓
Evict
  ↓
Restore
  ↓
Discard
```

Track B 已经验证了 bounded lifecycle 中 fork / continue / reattach / discard 的部分机制；长期视角则把它扩展成完整 execution-asset lifecycle。

**边界：** 当前 Track B 的闭环证据不能自动证明上述全部生命周期在真实生产 runtime 中成立。

## 10. Fork 不是终点，而是生命周期操作之一

早期 Execution State 思考容易把 fork 当成核心终点：

```
state → fork
```

长期视角更接近：

```
Execution State
├── create
├── continue
├── fork
├── share
├── migrate
├── materialize
├── evict
├── restore
└── discard
```

因此未来研究对象应从“有没有 fork”上升为：

> **一个 execution state 能否在完整生命周期中保持身份、可继续性、可迁移性与资源可管理性？**

这也是为什么 Execution State 是比单纯 KV cache 更高的抽象。

## 11. Minimum Sufficient Working Set

“最小化智能进入物理内存”不应被理解为：

> 内存占用越小越好。

真正有意义的长期目标应是：

```
minimum sufficient working set
```

即在满足：

- correctness；
- continuation；
- latency；
- migration cost；
- recomputation cost；
- memory safety；
- required concurrency

的条件下，维持当前执行所必需的最小物理工作集。

因此目标函数可能不是：

```
min(memory)
```

而更接近：

```
min(cost(memory, migration, recompute, latency))
```

subject to execution correctness and continuation constraints。

这使 residency 从“内存节省技巧”上升为 execution planning 问题。

## 12. 不让上游 API 定义研究对象

这是 Architecture 2.0 最重要的方法论边界之一：

> **API 能看到什么，不等于系统理论上存在什么。**

例如当前 runtime API 可能没有：

- sequence identity；
- first-class Execution State；
- runtime residency state；
- semantic-independent operational unit。

这只能说明当前接口没有暴露这些概念，不能反过来证明它们不存在。

因此研究顺序应保持：

```
theoretical object
      ↓
runtime-observable boundary
      ↓
existence criterion
      ↓
independent observation
      ↓
implementation path
```

而不是：

```
available API
      ↓
assume that is the research object
```

这条原则尤其重要，因为它防止 SimiGo 被当前 MLX / Swift API 的偶然边界锁死。

## 13. Semantic-light Runtime

长期理想状态可以写成：

```
semantic-assisted
        ≠
semantic-dependent
```

runtime 可以知道 layer / block / attention / MLP 等语义并利用它们优化，但核心 Execution State / Residency mechanism 尽可能依赖：

- access；
- co-access；
- residency；
- migration；
- reuse；
- continuation；
- cost。

这与 RM-024～RM-028 连成一条长期架构线：

```
Execution State
      ↓
semantic-light operational units
      ↓
runtime sharding
      ↓
residency planning
      ↓
minimum sufficient working set
      ↓
logical intelligence > simultaneously resident representation
```

最后一项只是长期目标假设，不是当前实现结论。

## 14. 最终长期图景

把上述思想压缩后，Architecture 2.0 的远期候选图景可以表示为：

```
                 Logical Model / Intelligence
                            │
                            ↓
                    Execution State
                            │
             ┌──────────────┼──────────────┐
             ↓              ↓              ↓
        Continuation      Access       Reuse/Fork
             │              │              │
             └──────────────┼──────────────┘
                            ↓
                  Operational Unit Discovery
                            ↓
                    Runtime Sharding
                            ↓
                       Planner
                 ┌──────────┼──────────┐
                 ↓          ↓          ↓
            Residency    Migration   Compute
                 │          │          │
                 └──────────┼──────────┘
                            ↓
                Minimum Sufficient Working Set
                            ↓
                 Physical Memory / Devices
```

远期愿景不是“把更多模型塞进 RAM”，而是：

> **让逻辑上的可用智能、执行状态与物理驻留之间解耦，使 runtime 能根据执行需求动态决定什么在物理内存中、以什么表示存在、何时迁移、何时共享、何时恢复，同时保持 execution identity 与 continuation。**

## 15. 研究边界

本文所有内容均属于：

- FUTURE ARCHITECTURE HYPOTHESIS；
- LONG-HORIZON VISION；
- NOT AN RQ；
- NOT IMPLEMENTATION AUTHORITY。

本文不：

- 改变 `RESEARCH_STATE.md`；
- 打开 STEP⑤；
- reopen Track B；
- reopen Track E；
- 注册 RQ；
- 授权 Swift/MLX 实现；
- 授权数据采集或实验；
- 把 Architecture 2.0 假设升级为已证明机制。

未来任何一项思想若进入正式研究，仍必须经过：

```
Memory / Vision
      ↓
Research Object
      ↓
Independence
      ↓
Estimand
      ↓
Existence Criterion
      ↓
Insufficiency
      ↓
Discriminating Power
      ↓
Information Value / Cost
      ↓
Path / Harness / Experiment
      ↓
Evidence
      ↓
Decision
      ↓
Architecture Constraint
```

## 16. 思想资产定位

这份档案的目的不是预测 SimiGo 最终一定会变成什么，而是保存一个关键转折：

```
make long-context computation faster
              ↓
avoid repeating expensive computation
              ↓
make computed state reusable
              ↓
make reusable state forkable
              ↓
identify the runtime object carrying that semantics
              ↓
separate logical intelligence from physical residency
              ↓
manage execution-aware working sets
```

如果未来若干年后 SimiGo 的研究边界发生变化，这条思想链仍应作为 Architecture 2.0 的 intellectual provenance 保留下来。
