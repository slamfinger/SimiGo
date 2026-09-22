# Architecture 2.0 Conceptual Dissection — Current Conclusion — 2026-09-22

> **Purpose:** 在 Architecture 2.0 Research Direction Review 之后，将当前已经形成的概念判断先固化为 durable research memory，再继续进行 Execution State、Boundary、Operational Unit、Residency Unit、Sharding Unit、Management Unit 六者的逻辑剖析。
>
> **Governance status:** 本文是概念分析 / research-memory checkpoint，不是 Research Question、Experiment、Finding、Decision 或 implementation authorization。
>
> **Research-gate effect:** NONE。

## 1. 当前锚点

Track B 的 intellectual closure 已完成。其限定 scope 内的 lifecycle 已冻结：

`fork → continue → branch → representation transition / reattach → continue → discard`

因此当前研究不应继续把 Execution State lifecycle 本身作为新问题。

Architecture 2.0 的真正未决部分不是：

> “Execution State 是否成立？”

而是：

> **Execution State 之外，runtime 中究竟存在什么结构，能够把执行状态、资源关系、生命周期动作与可管理边界联系起来？**

当前不能预先把这个结构命名为 Model Unit、Shard、Residency Unit 或 Management Unit。

## 2. 当前最重要的概念判断

### 2.1 Execution State 不是 Unit

Track B 建立的是一种具有 identity、continuation 与 lifecycle 的逻辑执行状态。

它回答：

> “一个可复用的执行状态能否经历 fork、continue、representation transition、reattach、discard 等生命周期操作？”

它没有回答：

> “这个状态在 runtime 中天然对应哪一个 operational unit？”

因此：

`Execution State ≠ Model Unit`

也不能默认：

`Execution State = Sharding Unit = Residency Unit = Management Unit`

### 2.2 Boundary 是中间层，而不是最终 Unit

当前最值得继续剖析的不是“Unit 是什么”，而是：

> runtime 是否呈现出可以被独立识别的 boundary structure？

当前 STEP④ 的 estimand：

`B(M,W,O)`

候选 descriptor：

`S(b)=<A_b,R_b,C_b,I_b>`

其中：

- A：access / co-access relation；
- R：residency-state change relation；
- C：migration / continuation change relation；
- I：execution identity / continuation association。

这些是观察结构的描述维度，不是 existence criterion。

因此当前逻辑更接近：

`Execution State → Runtime-observable Boundary Structure → ?`

而不是：

`Execution State → Model Unit`

### 2.3 Existence、Controllability、Usefulness 必须分开

即使观察到了 boundary，也不能直接推出它是可管理的 Unit。

需要至少区分三个层次：

1. **Existence**
   - runtime 中是否存在可独立识别的结构边界？

2. **Controllability**
   - 该边界是否可以被 runtime 独立作用、迁移、拆分、合并或改变状态？

3. **Usefulness / economic meaning**
   - 对该边界进行管理是否产生可解释的资源、性能或系统收益？

因此：

`observable boundary ≠ controllable unit ≠ useful management unit`

这三个命题不能在一个实验里被默认合并。

## 3. 六个概念的暂时分层

当前暂时使用以下逻辑层，而不是架构实现层：

`Execution State`
↓
`Runtime Boundary`
↓
`Operational Unit`
↓
`Resource-specific Units`
↓
`Management Unit`

其中 Resource-specific Units 可暂时包括：

- Residency Unit
- Sharding Unit
- 其他未来可能出现的资源操作单元

这里的箭头目前只表示**可能的抽象依赖方向**，不是已证明的包含、同一或因果关系。

## 4. 六者逐一解剖

### 4.1 Execution State

已知：

- 有 execution identity；
- 有 continuation position；
- 可以承载 component-specific state；
- 在 Track B scope 内支持 bounded lifecycle；
- physical representation 可以发生变化而不必改变 state identity。

未知：

- 一个 Execution State 是否天然具有唯一 runtime boundary；
- 一个 runtime boundary 是否只对应一个 Execution State；
- 多个 Execution State 是否可以共享同一个 operational boundary。

因此 Execution State 是已验证的**逻辑执行对象**，但不是已验证的 universal resource-management object。

### 4.2 Runtime Boundary

候选含义：

> runtime 中某些执行、访问、驻留、迁移或 continuation 行为呈现出稳定且可区分的结构边界。

它比“Unit”更弱。

它不要求提前假设：

- 可以独立分配；
- 可以独立迁移；
- 可以独立 shard；
- 有独立 API；
- 有独立 allocator object；
- 有独立 tensor/page/segment 表示。

因此 Boundary 是目前较合适的**观察层候选概念**。

但 Boundary 是否具有“对象性”，仍未证明。

### 4.3 Operational Unit

候选含义：

> runtime 可以把某个 boundary 当作一个独立操作对象来处理的单位。

这里比 Boundary 多了一层：

`Boundary + independent action`

关键未知：

- “独立操作”需要什么程度？
- 是独立观察即可，还是必须独立控制？
- 是一次动作独立，还是生命周期内持续独立？
- 是否允许多个物理 representation 对应同一个 operational unit？

因此 Operational Unit 不能由 boundary 的存在自动推出。

### 4.4 Residency Unit

候选含义：

> residency 状态、迁移、驻留或驱逐决策可以针对其独立发生的单位。

它天然带有资源管理含义。

因此：

`Residency Unit`

不是单纯的 observational concept。

它至少暗含：

- residency state；
- transition；
- action target；
- resource consequence。

所以不能从“存在 boundary”直接推出“存在 residency unit”。

### 4.5 Sharding Unit

候选含义：

> 一个可以作为分片、拆分、组合或跨设备/执行域分配对象的单位。

它比 residency unit 更强，因为它要求：

- 可划分；
- 可组合；
- 有边界；
- 有跨域 placement 或 ownership 语义。

尤其需要避免：

`can be observed` → `can be sharded`

这一步并不成立。

某个结构可能非常明显，但其跨设备切分代价、依赖关系或 continuation 语义使其无法成为独立 shard。

### 4.6 Management Unit

候选含义：

> runtime 的某种管理机制能够对其执行一组具有一致语义的资源与生命周期操作。

这是六者中最强的概念之一。

它可能同时涉及：

- execution state；
- residency；
- migration；
- compute scheduling；
- ownership；
- lifecycle；
- resource accounting。

因此 Management Unit 更可能是多个下游能力共同作用后的结果，而不是最基础的研究对象。

## 5. 当前最重要的非等价关系

至少应暂时保留以下非等价：

`Execution State ≠ Runtime Boundary`

`Runtime Boundary ≠ Operational Unit`

`Operational Unit ≠ Residency Unit`

`Operational Unit ≠ Sharding Unit`

`Residency Unit ≠ Sharding Unit`

`Management Unit ≠ any single lower-level unit by definition`

以及：

`observability ≠ controllability ≠ usefulness`

这些非等价关系本身就是当前 Architecture 2.0 的重要 negative knowledge。

## 6. 一个更稳健的暂时结构

当前不把 Architecture 2.0 画成固定的树，而暂时采用：

`Execution State`
→ **may expose**
→ `Runtime Boundary Structure`
→ **may support**
→ `Operational Unit`
→ **may admit specialized control domains**
→ `Residency / Sharding / Compute / Management Units`

这是一条研究假设链。

它允许未来出现以下情况，而不破坏上层理论：

### Case A：Boundary ≠ Unit

runtime 可以观察到稳定结构，但没有独立控制能力。

### Case B：Boundary = Operational Unit

观察边界同时具有独立操作语义。

### Case C：一个 Operational Unit → 多个 resource-specific units

同一个 execution object 在 residency 与 sharding 中可能采用不同边界。

### Case D：多个 Execution States → 一个管理边界

管理器可能为了资源优化，把多个逻辑状态聚合管理。

### Case E：同一 logical unit → 多种 physical representations

这与 Track B 已验证的 representation / state identity separation 相容。

因此不能用物理对象的数量反推逻辑对象的数量。

## 7. 当前真正值得追问的概念问题

现在比“Model Unit 是否存在”更基础的问题是：

> **runtime-observable structure 在什么条件下，才有资格被解释为一个独立的 operational object？**

这个问题又可拆成三个概念层：

### Layer 1 — Structure

是否存在可区分的 boundary structure？

### Layer 2 — Objecthood

这个 structure 是否足以支持“这是一个独立对象”的解释？

### Layer 3 — Actionability

这个对象是否具有独立生命周期动作或资源控制语义？

只有进入 Layer 3，才开始自然接近：

- residency unit；
- sharding unit；
- management unit。

因此“Unit existence”本身也可能不是一个单层问题。

## 8. 对当前 RBS 的重新理解

当前 STEP④ 的价值可能正在于：

> 它没有先假定 Unit，而是先测量 runtime 呈现的 boundary structure。

因此：

`B(M,W,O)`

更像是一个**结构性观察量**。

未来如果 STEP⑤ 继续，应先回答：

> 哪些 boundary properties 是把“观察到的结构”提升为“独立对象”所不可缺少的？

而不是直接规定：

> 一个 Model Unit 必须具备 A/B/C/D/E 五个属性。

这一区别很重要，因为后者容易再次把预设架构偷偷写入 existence criterion。

## 9. 当前禁止的逻辑跳跃

暂时明确禁止：

1. Execution State 已验证 → Model Unit 已验证；
2. Boundary 可观察 → Boundary 可独立控制；
3. Boundary 可控制 → Boundary 值得管理；
4. 可独立管理 → 可以 sharding；
5. 可以 sharding → 可以 residency；
6. residency state 存在 → predictive residency 已成立；
7. 需要 planner → planner 必须成为 runtime component；
8. Architecture 2.0 图景完整 → 各组件已经存在；
9. 上游 API 有某个对象 → 该对象就是研究对象；
10. 某个实验支持某一边界 → 整个 Architecture 2.0 成立。

## 10. 当前概念上的核心发现（非正式 Finding）

目前可以作为 research memory checkpoint 固化：

> **Architecture 2.0 的关键未知可能不是“哪个 Unit 应该成为 runtime 的基本单位”，而是“runtime 是否自然产生一种独立于模型语义的、可观察并可能进一步获得操作语义的 boundary structure”。**

进一步：

> **Unit 更可能是 boundary structure 在获得 objecthood、independent actionability 与 resource semantics 之后的解释，而不是研究开始时预设的原子对象。**

这仍是概念假设，不是 Finding，不进入 Finding Register。

## 11. 下一阶段概念剖析顺序

继续概念分析时，建议严格沿：

`Execution State`
→ `Boundary`
→ `Objecthood`
→ `Actionability`
→ `Resource semantics`
→ `Residency / Sharding / Management`

逐层检查。

每一层都问四个问题：

1. 它比上一层新增了什么语义？
2. 它是否可以在没有下一层概念的情况下成立？
3. 哪些属性是逻辑必需，哪些只是工程便利？
4. 什么情况下下一层根本不会出现？

这样可以避免为了最终架构目标反向定义基础对象。

## 12. Governance

本文不改变：

- Track B = CLOSED / FROZEN；
- Track E = CLOSED / SEALED；
- P3 / H-P1 / nodes-out 状态不变；
- P4 = NOT STARTED；
- RQ-F-01 = NOT DEFINED；
- STEP④ = PASS；
- STEP⑤ = UNSTARTED；
- 无新 RQ；
- 无实验；
- 无 implementation authorization；
- 无 measurement authorization。

**Research-gate effect: NONE.**

## 13. Recovery sentence

> “Track B 已证明 bounded Execution State lifecycle，但没有证明任何 universal Unit。当前应把 Execution State、Runtime Boundary、Operational Unit、Residency Unit、Sharding Unit、Management Unit 分层剖析，先研究 boundary 如何获得 objecthood 与 actionability，再讨论资源管理单位；STEP⑤ 尚未启动。”


## 14. Further checkpoint: from boundary to objecthood

上一轮分析进一步把当前问题压缩为：

`runtime behavior → observed structure → boundary → objecthood → actionability → resource semantics → management abstraction`

这里出现了一个比“Model Unit existence”更基础的未知：**Boundary 与 Objecthood 之间的逻辑跃迁是什么？**

### 14.1 Boundary 仍然只是结构解释

一个 boundary 可以表现为：

- access/co-access 的结构分界；
- residency transition 的结构分界；
- migration/continuation 行为的分界；
- execution identity/continuation association 的分界。

但这些都只能说明：

> “这里存在可区分的 runtime structure。”

不能自动说明：

> “这里存在一个独立对象。”

### 14.2 Objecthood 的核心不是“有名字”，而是可独立指认

暂时把 objecthood 理解为一个待定义的逻辑属性：

> 在给定 observation domain 内，某个 boundary 所指向的结构是否能够被持续地指认为“同一个东西”，而不是仅仅在某次运行中出现的一组相关行为。

这引入了一个关键区别：

`pattern recurrence ≠ object identity`

一次实验中反复出现某种结构，并不自动意味着存在稳定对象。

因此未来必须区分：

- **结构可重复**：类似结构在不同观察中出现；
- **对象可追踪**：可以把某一实例在状态变化前后识别为同一个逻辑对象；
- **对象可区分**：可以与相邻/其他对象区分；
- **对象可解释**：其边界不是仅由分析者任意切出来的描述区域。

这些目前都是概念候选，不是 STEP⑤ criterion。

### 14.3 一个新的关键问题：identity 从哪里来？

Track B 已经证明 Execution State 可以具有 identity，并且 representation 可以变化而不改变 state identity。

但这并不证明：

> runtime boundary 自己拥有 identity。

因此需要严格区分：

`Execution-State identity`

与：

`Boundary identity`

与：

`Operational-object identity`

三者可能相同，也可能不同。

尤其存在一种可能：

`one Execution State → multiple runtime boundaries`

以及：

`multiple runtime structures → one operational object`

因此不能从 Track B 的 identity 直接外推 boundary identity。

### 14.4 Boundary → Objecthood 可能需要“跨状态保持”的能力

如果一个所谓 boundary 只在：

`state S0`

中存在，而到了：

`state S1`

representation、residency 或 continuation 改变后完全无法对应，那么它更像一个 observation pattern，而不是对象。

这提示一个重要的候选概念：

> **objecthood may require cross-state referential continuity**

也就是：

> 在对象发生合法 runtime transition 后，仍然能够判断“这是同一个对象”。

但这仍然只是概念候选，不能提前升级成 existence criterion。

### 14.5 这与 Track B 的 representation/state identity separation 形成真正连接

Track B 已经给出：

`state identity ≠ physical representation`

现在 Architecture 2.0 要继续问的可能是：

`boundary identity ≠ physical representation ?`

以及进一步：

`operational-object identity ≠ physical representation ?`

如果未来能够建立这种分离，那么 Architecture 2.0 的抽象层会出现一个非常重要的结构：

`logical identity → changing runtime boundary / representation`

而不是：

`object = fixed memory region`

这可能比“Model Unit”本身更基础。

### 14.6 但 identity 仍不足以产生 actionability

即使某个 boundary 可以跨状态被识别为同一个对象：

`identity`

仍然不意味着：

`actionability`

因为还需要问：

> runtime 是否有语义上独立的动作可以作用于这个对象？

因此暂时保留：

`identity → objecthood`

只是候选关系，而不是充分条件。

更准确的结构仍是：

`structure → boundary interpretation → objecthood? → actionability?`

### 14.7 一个潜在的“最小对象”问题

现在可以提出一个更尖锐的问题：

> **如果把一个 runtime structure 切得更细或更粗，什么时候它仍然保持同样的 identity、transition semantics 与 action semantics？**

这可能引出“最小充分对象”问题。

但必须注意，它不能直接等同于：

- 最小 tensor；
- 最小 page；
- 最小 segment；
- 最小 layer；
- 最小 memory block。

“最小”必须是语义最小，而不是物理尺寸最小。

因此暂时可以区分：

`physical granularity`

与：

`semantic granularity`

与：

`operational granularity`

三者不应默认相同。

### 14.8 当前新的核心压缩

本轮分析后，当前最值得保留的概念链是：

`Observed Structure`
→ `Boundary`
→ **Does the boundary denote a persistent distinguishable identity?**
→ `Objecthood`
→ **Can independent semantically meaningful actions target it?**
→ `Actionability`
→ `Residency / Sharding / Compute semantics`
→ `Management abstraction`

因此当前未知已经从：

> “Model Unit 是否存在？”

进一步收缩为：

> **runtime 中被观察到的 boundary，何时不再只是一个分析上的分区，而成为一个能够跨合法状态变化持续被指认、并可能承载独立动作语义的对象？**

这仍然不是正式 Research Question。

### 14.9 Negative knowledge added by this checkpoint

本轮明确排除：

- recurrence 不等于 identity；
- identity 不等于 actionability；
- boundary 不等于 object；
- object 不等于 management unit；
- physical granularity 不等于 semantic granularity；
- semantic granularity 不等于 operational granularity；
- Execution State identity 不等于 boundary identity；
- representation stability 不是 objecthood 的必要前提，因为 Track B 已证明 identity 与 representation 可以分离。

### 14.10 Governance

本 checkpoint 不改变：

- Track B = CLOSED / FROZEN；
- Track E = CLOSED / SEALED；
- P3 / H-P1 / nodes-out 状态不变；
- P4 = NOT STARTED；
- RQ-F-01 = NOT DEFINED；
- STEP④ = PASS；
- STEP⑤ = UNSTARTED；
- 无新 RQ；
- 无实验；
- 无 implementation / measurement authorization。

**Research-gate effect: NONE.**
