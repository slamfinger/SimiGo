# Architecture 2.0 Research Program Reclassification — 2026-09-22

> **Purpose:** 在重新回到 Architecture 2.0 起点、确认 Execution State 为核心架构主干后，对 SimiGo-Lab 当前研究课题进行一次方向性重分类。
>
> **Status:** Research-direction review / program triage. 本文不是新的 Finding，也不是新的 RQ 注册。
>
> **Core conclusion:** Architecture 2.0 的核心研究对象是大模型作为计算系统所遵循的稳定架构规律，而不是穷尽模型承载的知识、规则、语义、概率及其内部数据规律。Execution State 是当前最稳定的架构抽象。围绕“识别所有边界/通用 Unit”的 Source/Runtime 路线因此停止作为 2.0 主线。

## 1. 新的 Architecture 2.0 主干

`Expensive computation → Reusable Execution State → Continuation / Fork / Lifecycle → Representation transition → Runtime carrying / reuse → Residency / Loading / Layering / Migration`

职责分离：

- Model implementation / MLX-LM / specific model architecture：**how to compute**
- Execution State：**what continuation-relevant execution state exists**
- Runtime：**how to carry / reuse / load / reside / migrate that state**

“通用 Execution State”指执行语义上的通用，不要求所有模型内部 State 数据结构相同。

## 2. 研究对象边界

### 不作为 Architecture 2.0 核心对象

以下方向不再作为 2.0 主线：

- 穷举模型知识及其规则；
- 穷举模型语义与概念关系；
- 穷举模型概率结构；
- 识别模型承载内容的全部边界；
- 从内容规律继续推导 universal object / universal unit。

这些方向可能具有独立的机器智慧、知识表示或模型科学价值，但与当前 Architecture 2.0 的计算架构主线不同。

### 作为 Architecture 2.0 核心对象

- Execution State；
- execution continuation / fork / lifecycle；
- logical state 与 physical representation 的分离；
- Execution State 的复用；
- 围绕 Execution State 的加载、驻留、迁移与分层；
- 未来可能的 execution-aware resource management。

## 3. 课题重分类

| 课题 | 原状态 | 新处理 | 理由 |
|---|---|---|---|
| Track B — Execution State lifecycle | CLOSED / FROZEN | **结题，永久冻结** | 已完成 bounded lifecycle；不再作为新问题继续 |
| Residency M1–M4 | FINAL PASS | **结题，封口归档** | 历史 residency 基础结果已完成；不得重写为通用架构结论 |
| P3-A / P3-B / P3-C | CLOSED / SEALED | **结题，封存** | 历史 policy 线已完成，不因 2.0 新主干重开 |
| H-P1 | CLOSED / SEALED | **结题，封存** | 已完成结构信号存在性问题 |
| nodes-out / Track E | CLOSED / archived | **结题，封存** | 已完成其独立研究问题；不再自动延伸 |
| RQ-F-01 Source/Runtime 机制存在性候选 | NOT DEFINED | **撤销候选 / 终止当前路线** | 其“boundary → unit”研究对象边界已被判断为偏离 2.0 主干；此前 STEP④ 仅属于该历史候选定义，不转移给新课题 |
| P4 / RQ-P4-01 核心驻留结构/状态机制 | NOT STARTED | **保留，作为下一候选主线** | 直接承接 Execution State → Residency，属于计算架构而非模型内容规律；必须独立 Definition gate |
| Track A — Kernel/Bandwidth | NOT STARTED / conditional | **非 2.0 主线，保持 dormant/conditional** | 属于 workload-specific 性能/内核问题，不是当前 Execution State 主线 |
| Track D — Adaptive Memory | NOT STARTED / independent | **保留为后续独立课题** | 与 runtime resource management 有关，但不应自动从当前主线开启 |
| Track C — Multi-device | FUTURE | **保留为远期课题** | 属于执行资源编排的后续问题，当前无独立定义 |
| Boundary / Object / Identity / Invariant / Equivalence 概念线 | discussion / concept | **作为历史思想资产封存，不立项** | 已帮助完成方向修剪，但继续发展会进入模型规律/机器智慧方向 |

## 4. 当前真正需要继续的研究

当前不需要同时推进多个方向。

最自然的候选主线只有：

`Execution State → Residency / Loading`

其中已有基础：

- Execution State lifecycle 已经在 Track B scope 内得到验证；
- Residency 历史研究已产生 M1–M4、P3 等结果；
- 下一步不是再次证明 Execution State，而是研究**计算架构层面的驻留/加载机制**。

现有 `RQ-P4-01` 因此保留为候选，但仍必须独立回答：

1. 研究对象是什么；
2. 研究问题是什么；
3. 为什么独立；
4. estimand 是什么；
5. 什么观察构成存在；
6. 什么结果不足以支持存在；
7. discriminating power；
8. 信息价值与成本；
9. 才决定实验/实现路径。

**本次重分类不启动 P4。**

## 5. 已经可以真正“放下”的东西

需要明确放下，而不是留在“下一步可能继续”的模糊状态：

### 5.1 “识别所有边界”

停止作为 Architecture 2.0 主线。

不是因为边界概念错误，而是因为“所有边界”会把研究对象不断推向模型内部内容、知识、规则、语义和概率结构，最终接近机器智慧生成/知识组织问题。

### 5.2 “寻找 universal Model Unit”

停止作为当前 2.0 目标。

Execution State 已经足以作为核心逻辑执行抽象，不需要先证明存在一个跨模型、跨资源、跨语义的 universal Unit。

### 5.3 “Boundary → Object → Actionability → Unit”

作为当前主线停止扩展。

这条概念链保留为历史探索资产和 negative knowledge，不注册 RQ。

### 5.4 “Source/Runtime existence”当前候选

当前 RQ-F-01 不进入 STEP⑤。

此前 STEP④ 的 PASS 是历史定义链状态，不能迁移给 P4，也不能成为继续推进 Source/Runtime 的理由。

## 6. 新的研究树形态

当前不构建完整 intellectual tree，只保留已经足够稳定的主干：

`long-context cost`
→ `avoid repeated computation`
→ `Compute Once / Multiple Futures`
→ `Execution State`
→ `fork / continue / lifecycle`
→ `representation transition`
→ **Residency / Loading / Layering / Migration**

旁枝：

`Execution State`
→ `Boundary / Object / Identity / Equivalence`
→ **停止 / 封存**

未来旁枝：

`Execution State`
→ `Multi-device`

以及：

`Runtime resource management`
→ `Adaptive Memory`

这些未来枝条不自动开放。

## 7. “完成”的新判断

Architecture 2.0 当前并不是“所有问题都解决了”。

更准确的是：

> **核心研究对象已经重新确定，偏离主线的枝条已经能够被识别和修剪，下一条合法研究路径也重新变得清晰。**

因此这一次的成果不是新增一个复杂架构，而是减少了研究空间：

`无限模型内容规律` → 排除

`universal Unit` → 排除为必要前提

`Execution State` → 保留为核心主干

`Residency / Loading` → 下一候选研究方向

## 8. Governance

本文件：

- 不 reopen Track B；
- 不 reopen Track E；
- 不注册 RQ-F-01；
- 不启动 P4；
- 不执行实验；
- 不进行 runtime implementation；
- 不进行 measurement。

P4 如未来启动，必须从独立 Definition gate 开始，而不能继承 RQ-F-01 的 STEP④ 状态。

**Research-gate effect: DIRECTION RESET ONLY.**
