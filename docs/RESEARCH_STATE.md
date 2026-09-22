# SimiGo-Lab Research State

> **This file is the authoritative snapshot of the current SimiGo-Lab research state.
> Conversation memory must not override it.**
> Git 保存事实，会话负责推理：任何“项目到哪了”的问题，先读本文件与所引 endpoint 文档，再回答。

**Last updated**: 2026-09-22（记录 Execution-State-oriented Post-Training 假设；P4-A STEP① 继续）

## 0. 状态恢复流程（重进项目时固定执行，不得跳过）

① 读取本文件 → ② 读取当前阶段 endpoint / closure 文档 → ③ 核对最近 git log → ④ 确认状态 → ⑤ 才允许回答或提出动作。

## 1. 当前阶段

Phase: Architecture 2.0 / P4 Redefinition / Pre-definition
Next action: 完成 P4-A STEP① 研究对象逐项审查；通过后再进入 STEP②
Gate status: CLOSED — 旧 Source/Runtime 定义链停止；P4 尚未完成 RQ 定义
RQ ID: 未分配
当前活动文档: docs/07-history/ARCHITECTURE_2.0_P4_REDEFINITION_20260922.md

## 2. 状态词汇表

| 状态 | 含义 | 推理约束 |
|---|---|---|
| SEALED | 结论冻结 | 禁止继续优化该结论 |
| CLOSED | 研究问题已完成合法出口 | 不据此推导立即开始下一实验 |
| OPEN | 当前在册研究问题 | 仅此状态的问题构成当前任务 |
| DEFINED | 已定义但尚未开始 | 仅允许预注册 Allowed 动作 |
| NOT DEFINED | 连问题都尚未正式立项 | 禁止实现/采数/测量 |
| FROZEN | 基础设施可复用，但身份不可变 | 复用必须建立新 provenance |
| SEPARATELY SCOPED | 有关联，但不得并入当前研究 | 禁止跨线引用结论 |

## 3. 研究问题唯一 ID

| ID | 研究问题 | 状态 |
|---|---|---|
| RQ-B-01 | Execution State lifecycle 语义（收敛模型） | CLOSED / FROZEN |
| RQ-P3-01 | Residency policy 频率机制 | P3-A PASS / P3-B R3 CLOSED / P3-C R-W CLOSED·SEALED |
| RQ-H-01 | 结构信号存在性 | CLOSED / SEALED |
| RQ-NO-01 | 取消 node 粒度外化通道 | CLOSED |
| RQ-P4-01 | Architecture-induced Execution State 及其资源生命周期特征 | NOT STARTED / NOT DEFINED |
| RQ-F-01 | Source/Runtime 机制可实现·可验证性 | RETIRED CANDIDATE / NOT DEFINED |

## 4. Mainline

Model Architecture Features → Computation → Execution State → State Characteristics → Resource Behavior → Loading / Residency / Layering / Working Set / Migration → Runtime Architecture

潜在反向研究路径（尚未验证）：

Post-Training → Computation / Execution-State Behavior

## 5. Sealed / Closed

Track B、Track E、P3、H-P1、nodes-out 保持原有 CLOSED / SEALED / FROZEN 状态。历史路线不自动重开。

## 6. Not started / Not defined

| 项 | 状态 | 约束 |
|---|---|---|
| P4（RQ-P4-01） | NOT STARTED / NOT DEFINED | 仍须独立完成 Definition Gate |
| Source/Runtime / RQ-F-01 | RETIRED / NOT DEFINED | 不进入 STEP⑤；此前状态不向 P4 转移 |
| Swift implementation | NOT STARTED / NO BASIS | 不因 P4 重定义获得授权 |
| Execution-State-oriented Post-Training | HYPOTHESIS / NOT REGISTERED | 仅为概念资产；不创建新 RQ，不授权实验/实现/测量 |

## 7. Current gate

P4 / RQ-P4-01
- STEP① 研究对象：WORKING DEFINITION / 审查中
- STEP② Research Question：未开始
- STEP③ Independence：未开始
- STEP④ Estimand：未开始
- STEP⑤–⑨：未开始

### Allowed

- 继续 P4 概念定义；
- 完成 P4-A STEP① 研究对象审查并形成 closure；
- 读取历史 Track B / Track E 资产作为背景约束；
- 历史资产盘点与 Architecture 2.0 概念复盘；
- 研究“短周期、增量式、反例驱动”的跨模型泛化方法，但不把它注册为新 RQ；
- 保存新的、尚未注册的 Architecture 2.0 概念假设。

### Forbidden

- 把 P4 当前定义直接当作已注册 RQ；
- 转移 Track B / Track E 证据为 P4 结论；
- 直接进入 STEP⑤–⑨；
- Runtime implementation / harness construction / data collection / performance measurement；
- 预设 Universal Model Unit / Universal Physical State Representation；
- 扩张为研究全部模型内部知识、语义、概率与表示；
- 继续 RQ-F-01 Source/Runtime boundary/unit 路线；
- 为了“通用”而预先加入未经真实架构反例迫使的抽象层；
- 将 Execution-State-oriented Post-Training 假设直接视为成立的后训练方法或既定架构。

## 8. Definition Gate

① 研究对象 → ② Research Question → ③ 独立性 → ④ estimand → ⑤ existence criterion → ⑥ negative criterion → ⑦ discriminating power → ⑧ information value / cost → ⑨ Path / Harness / Experiment。

## 9. 新增研究规划原则

Architecture 2.0 采用：

当前代表性架构 → 最小抽象 → 新架构反例 → 最小必要扩展 → 再验证。

通用性由真实架构反例推动，而不是由想象中的未来模型推动。没有反例，不提前增加抽象层；若面对新架构需要大幅修改既有抽象，则停止继续泛化并重新审查抽象边界。“不能泛化”本身是合法研究结果。

详细规划：docs/07-history/ARCHITECTURE_2.0_INCREMENTAL_GENERALIZATION_PLAN_20260922.md

## 10. 新增概念假设：Execution-State-oriented Post-Training

当前提出一条潜在反向路径：

Post-Training → Computation / Execution-State Behavior → Resource Behavior → Runtime

核心问题不是直接改变模型参数中的全部知识，而是：

> 受控后训练数据/任务分布，是否能够稳定改变模型在目标任务分布下形成、使用、复用和终止 Execution State 的特征，并进一步改变资源行为？

暂不注册为 RQ。重点约束：

- 不把“高频/低频知识”直接等同于 State Frequency；
- 区分 workload frequency、state activation frequency、state reuse frequency、state lifetime、resource occupancy；
- 不假设 State 与知识类别一一对应；
- 不声称受控数据能够唯一反推出完整模型架构；
- 不声称后训练必然改善长上下文或多轮能力；
- 先验证 repeatability → discriminability → directionality → resource effect → capability preservation → runtime leverage → cross-architecture generalization。

详细记录：
docs/07-history/ARCHITECTURE_2.0_EXECUTION_STATE_ORIENTED_POST_TRAINING_HYPOTHESIS_20260922.md

## 11. 重要边界

SimiGo 1.x product line ≠ SimiGo-Lab 2.0 research line。

事实源优先级：Git 仓库（本文件 + endpoint 文档 + ledger + git log）> 对话记忆。

## 12. P4 逐步证伪与资源条件门（2026-09-22)

P4 后续研究采用“先证伪、后扩展”的门控原则，而不是以证明总假设为目标。

- 最小循环：提出最小假设 → 寻找最低成本反例 → 失败则关闭 → 暂未失败则缩小命题并进入下一层。
- 没有真实架构反例，不增加新的抽象层。
- “不能泛化”本身是合法研究结果。
- P4-A：Architecture → Execution State；若无法稳定产生 continuation-relevant State 差异，则终止。
- P4-B：Execution State → Resource Behavior；若 State 差异不能解释稳定资源后果，则不强行作为 Runtime 核心抽象。
- P4-C/D/E 只有前置关系通过后才逐层开放。
- 后训练仍为候选扩展，不因本原则获得实验授权。

### 硬件条件门

研究不以先搭建完整硬件设施为前提。优先采用最低成本、最小规模、可区分候选命题的实验条件。

只有当前置研究门已经通过、当前硬件成为决定性区分瓶颈、新硬件能明确增加实验能力，并且失败后仍能关闭明确命题时，才考虑扩大硬件能力。不得因为已有硬件投入而维持失去研究价值的方向。

详细记录：docs/07-history/ARCHITECTURE_2.0_P4_FALSIFICATION_AND_RESOURCE_GATE_20260922.md

## 13. P4-A 语义投影价值收缩（2026-09-22）

本轮完成 P4-A 对“共同语义投影”的进一步对抗。当前不再把“自然收敛”作为强 existence criterion；研究者先验污染使其只能作为辅助证据。

当前候选价值判据被收缩为 task-relative / cost-relative 形式：在明确 Runtime resource-decision task、workload scope 与有限观测/计算预算下，是否存在低复杂度 State representation，使决策损失相对 architecture-specific state 保持在允许范围，同时显著降低 instrumentation / adaptation cost。

重要边界：
- prediction(b) ≈ prediction(a) 不等于 global sufficient statistic；
- resource constraints 提供有限可描述性的研究动机，不证明低维 projection 存在；
- low-dimensional / task-specific / high-dimensional architecture-specific dependence 均为合法结果；
- STEP① 可以讨论潜在 information value / cost，但尚未注册 STEP④–⑨ 的具体 estimand、threshold 或实验。

当前仍为 P4-A STEP① WORKING DEFINITION / 审查中，RQ 未分配，实验未授权。

下一概念攻击：Description Language Attack。检查固定 Runtime-side description language 是否真正独立于被测 architecture / projection；是否把复杂度藏进 decoder / ontology / external knowledge；encoder 是否可利用 architecture-specific prior；rate 降低是否真正代表 decision-relevant information compression，而非语义搬运。当前 Rate-Distortion 仅为 STEP① 候选框架，不注册具体 estimand / threshold / experiment。

## 14. 状态维护规则

1. 任何状态变更必须更新本文件并独立 commit；
2. 本文件只记当前状态；
3. RQ ID 一经分配永久占用，废弃用 CLOSED/NOT DEFINED 标注，不复用编号。
