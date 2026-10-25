# Source/Runtime Independence Argument v0.1

**状态**：`STEP ③ DRAFT / EXTERNAL REVIEW PASS — 待登记`  
**日期**：2026-09-22  
**Gate**：Definition / Opening —— §8.1 **STEP ③：为什么它是一个独立问题**  
**边界**：本文仅论证 C1 相对于既有研究的独立性；不完成 estimand（④）、existence criterion（⑤）、insufficiency criterion（⑥）、discriminating power（⑦）、worth measuring（⑧）、Path/Harness/Experiment（⑨）；不分配 RQ ID，不产生采数授权。

## 0. 四问框架

本步不重复 STEP ② 的四道 RQ 资格门。STEP ② 已回答“C1 是否具备进入定义链的资格与最小性”；STEP ③ 只回答“C1 是否是相对于既有研究的独立未知”。

## 1. 已有研究各自知道了什么

| 已确立的知识（署名锚点） | 知识内容 | 知识通道 |
|---|---|---|
| Track B（`4184aa6`） | execution-state migration 的正确性条件：五元组不变式（Identity / Position / NextInput / Continuation）在迁移前后必须等价 | 规范性不变式（应然） |
| P3（`ac71e34` SEALED） | 模拟 residency policy 空间内的频率机制归因：R-W 有限记忆窗口主导，decay 无贡献 | 模拟事件通道 |
| H-P1（`edc4dad` SEALED） | 在预注册信号域与实验边界内，结构信息可转化为 residency 控制信号 | 模拟观测通道 |
| nodes-out（`b6ad7c0`） | frozen accounting 模型内 unit/node byte 恒等闭合；访问模式决定粒度价值原则在其模拟域内成立；另有 runtime 事件路径开销的注册预测，尚未验证 | 模拟账本通道 + 登记态预测 |

这些研究分别回答了 migration correctness、模拟 residency policy 归因、模拟结构信号、模拟粒度/账本关系等问题；均未直接建立真实 Swift/MLX execution 的 Model Unit residency/migration 边界事实。

## 2. 哪些已知推不出目标命题 P

目标命题 P：

> **P：在预注册的模型与 workload 边界内，真实 Swift/MLX execution 的访问与驻留相关行为，是否暴露出具有独立 residency / migration 语义的 Model Unit 边界。**

### 2.1 Track B 不推出 P 或 ¬P

Track B 的五元组是规范性不变式，回答“迁移怎样才保持 execution identity 与 continuation 语义”。它可以约束任何候选粒度上的合法迁移，但不描述真实 runtime 中是否已经存在相应的独立 residency/migration 对象。因此，它对“边界存在性”没有方向性蕴含。

### 2.2 P3 不推出 P 或 ¬P

P3 的归因对象是模拟器中的事件流与 residency policy 空间。真实 allocator、访存与驻留行为是否存在同构的窗口/计数结构，不在 P3 的观测对象内。因此 P3 的结果不能直接转移为真实 runtime 中 Model Unit 边界存在或不存在的结论。

### 2.3 H-P1 不推出 P 或 ¬P

H-P1 证明范围限定于其预注册结构信号域与模拟驻留态。它回答的是结构信息是否能够成为 residency 控制信号，而不是真实 decode execution 是否暴露出具有独立 residency/migration 语义的对象边界。因此二者观测层级不同。

### 2.4 nodes-out 最接近，但仍不推出 P

nodes-out 给出了“访问模式决定粒度价值”的模拟域原则，并登记了 runtime 事件路径开销预测。前者为提出 P 提供了研究动机，后者甚至以存在可测 runtime 路径为前提，均没有回答“runtime 中是否存在可独立定义的 Model Unit”。

尤其是 RM-005 已明确将“真实 Swift/MLX runtime 中尚未建立该原则”作为边界；因此不能把历史上的访问模式原则倒推成真实 runtime unit 已存在的事实，也不能把注册预测当作 P 的证据。

### 2.5 结构性补强：RM-006 的层间不转移

既有证据的主要通道位于抽象机制 / 模拟表示层；P 位于真实 runtime 表示 / runtime 可观测行为层。依据 RM-006 的依赖结构，抽象机制、模拟状态与真实 runtime observable state 之间不存在未经验证的自动同构。因此这里不是简单的“证据数量不足”，而是**既有证据通道在结构上没有覆盖 P 所要求的观测对象**。

### 2.6 反向自查：P 未被构造成必真

模型语义层存在 layer / block 等分解事实，并不等价于 runtime 行为已经暴露出独立 residency/migration 边界。P 问的是后者；因此“模型有层级”不能作为 P 的构造性证明。

## 3. 缺失的未知量究竟是什么

缺失未知量是：

> **真实 Swift/MLX execution 的行为层粒度结构事实：在预注册观察边界内，其访问、共访问与驻留相关行为是否稳定地显现出可作为独立对象观察的对象边界，并支持把该对象与 residency / migration 语义关联起来。**

这里的“稳定地显现”“独立对象”“residency / migration 关联”是本步对未知量的概念描述，不是第⑤步 existence criterion，也不是第④步 estimand；具体可测量量、存在判据与不足判据均留到后续步骤定义。

当前关键事实是：已有主线证据没有打开“真实 runtime 行为观测”这一通道。因此该未知量不是已答问题的剩余参数，而是一条尚未建立证据的独立观测通道。

## 4. 解决它为什么形成新的知识状态

C1 的两种合法方向都会改变后续研究的知识边界，但具体出口不预设第⑤/⑥步的判据。

### 4.1 若在预注册边界内获得足以支持“暴露”的证据

将首次建立一个受实验边界约束的真实 runtime Model Unit 对象域。届时 C2 的机制问题才获得一个不再依赖假设的载体空间；同时，关于模型分解/分片与访问模式的既有思想假设可被重新评价——究竟得到支持、限定还是被否定，由后续证据决定。

### 4.2 若在预注册边界内不足以支持“暴露”

则可登记一个受边界约束的负向知识状态：**在该模型、workload 与观察边界内，未获得足以支持自然 Model Unit residency/migration 边界存在性的证据。** 这不会证明“任何 runtime 都不存在自然粒度”，也不会直接证明 policy 机制“只能”在约定边界上运行；它只关闭当前定义域内的该未知量，并为研究树考虑其他 workload 类或非粒度机制提供边界信息。

因此，C1 的解决不是重复既有研究，而是会首次决定“真实 runtime 是否提供后续机制研究所需的对象载体”这一知识状态。

## 5. 独立性主张

C1 的独立性可精确归结为四点：

1. **非重跑**：证据通道不同。既有研究主要来自规范性不变式、模拟事件、模拟结构信号与模拟账本；C1 所需的是真实 Swift/MLX runtime 行为观测。
2. **非推论**：Track B、P3、H-P1、nodes-out 均不能从其既有观测对象直接蕴含 P 或 ¬P；缺口具有结构性的层间边界，而非单纯增加样本即可填补的同一问题。
3. **非工程**：C1 的两个方向都改变对真实 runtime 对象空间的知识状态。实现、harness 与性能测量并不是本步的结论或授权。
4. **上游定义域作用**：C1 的结果将决定后续机制问题是否拥有经验载体域；因此它是后续定义链的重要上游未知量，而不是在册问题的重复或其工程实现。

## 6. 明确未做

- 未完成第④步 estimand。
- 未定义第⑤步 existence criterion。
- 未定义第⑥步 insufficiency criterion。
- 未进行第⑦步 discriminating-power 论证。
- 未进行第⑧步 worth-measuring 论证。
- 未决定第⑨步 Path / Harness / Experiment。
- 未分配 RQ ID。
- 未产生任何采数、实现或测量授权。

## 7. 外审结论

**PASS（可登记）。**

理由：

- 四问均直接回答 STEP ③ 的独立性问题；
- 未用 STEP ② 四道资格门替代独立性论证；
- 明确区分规范性知识、模拟知识、登记态预测与真实 runtime 未知量；
- 对 nodes-out 的“最接近”关系未越界为证据；
- 对负向结果的表述收缩到预注册观察边界，避免从“不足以支持”升级为全局不存在；
- 未把第④–⑨步的定义内容伪装成已完成；
- C1 仍保持未知性，未预选具体 Model Unit 家族。

**登记前状态建议：**
`STEP ③ DRAFT / EXTERNAL REVIEW PASS — 待登记`

外审 PASS 不等于状态登记；第④步仅在 STEP ③ 经仓库登记后解锁。
