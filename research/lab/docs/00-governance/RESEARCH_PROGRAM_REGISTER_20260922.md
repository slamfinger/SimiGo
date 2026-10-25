# Research Program Register

**Purpose:** 当前与未来研究路线的控制面。  
**Authority:** 本文件不替代 `docs/RESEARCH_STATE.md`；具体当前状态仍以 RESEARCH_STATE 与 endpoint/closure 为准。

## 1. Program map

| Line | Purpose | Current state | Dependency / gate | Notes |
|---|---|---|---|---|
| Track B — Execution State | fork / continuation / representation lifecycle | CLOSED / FROZEN | Historical closure | 不自动重开 |
| Track E — Residency | residency policy / P3 / nodes-out | CLOSED / SEALED / archived | Historical closure | 不自动重开 |
| P4 / RQ-P4-01 | Architecture-induced Execution State 及其资源生命周期特征 | NOT STARTED / NOT DEFINED | 独立 Definition gate | 本次重新定义后的主候选 |
| Source/Runtime / RQ-F-01 candidate | Swift/MLX runtime boundary/unit existence | RETIRED CANDIDATE / NOT DEFINED | 不再进入当前 Definition chain | 已从 2.0 主线撤回 |
| Track A — Kernel/Bandwidth | workload-specific kernel opportunity | NOT STARTED / conditional | exp06 roofline gate | 独立 |
| Track D — Adaptive Memory | dynamic memory budget / pressure response | NOT STARTED / independent | 独立定义 | 不自动开启 |
| Track C — Multi-device | multi-device execution orchestration | FUTURE | 独立定义 | 长期 |

## 2. Direction reset

Architecture 2.0 研究边界限定为**计算架构规律**，而不是模型内容/知识规律。

当前主线：

`Model Architecture Features → Computation → Execution State → State Characteristics → Resource Behavior → Loading / Residency / Layering / Working Set / Migration → Runtime Architecture`

## 3. P4 redefinition

P4 不研究“大模型架构本身”，而研究：

> **由不同计算架构诱导形成的 Execution State 及其资源生命周期特征。**

进入 P4 的架构特征必须能够影响至少一个 Execution State 属性：

- State type
- State growth
- State dependency
- State reuse
- State lifetime
- State access
- State transition
- State materialization / representation transition
- Future-use relation

分层、加载、驻留、迁移均作为 State resource lifecycle 的下游问题，不直接从 Model Architecture 跳到 Runtime。

## 4. Definition status

P4 仍未完成正式 RQ 定义。

当前仅完成重新定义与 Definition Gate 准备：

`Research Object → Research Question → Independence → Estimand → Existence Criterion → Negative Criterion → Discriminating Power → Information Value / Cost → Path / Harness / Experiment`

因此：

> **本登记不授权实现、采数或测量。**

## 5. Historical branches

Boundary / Object / Identity / Invariant / Equivalence 等概念探索继续作为历史知识保存，但不属于当前 P4 主线。

Universal Model Unit 不是 P4 的前置假设。

Universal Execution Semantics 与 Universal Physical Representation 必须分离。

