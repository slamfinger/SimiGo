# SimiGo-Lab Research State

> **This file is the authoritative snapshot of the current SimiGo-Lab research state.
> Conversation memory must not override it.**
> Git 保存事实，会话负责推理：任何“项目到哪了”的问题，先读本文件与所引 endpoint 文档，再回答。

**Last updated**: 2026-09-22（STEP② 首轮 RQ candidate 已形成；正在攻击 Rate–Decision-Loss frontier 的定义独立性）

## 0. 状态恢复流程（重进项目时固定执行，不得跳过）

① 读取本文件 → ② 读取当前阶段 endpoint / closure 文档 → ③ 核对最近 git log → ④ 确认状态 → ⑤ 才允许回答或提出动作。

## 1. 当前阶段

Phase: Architecture 2.0 / P4 Redefinition / STEP② Research Question
Next action: 攻击 Rate–Decision-Loss frontier 对 Description Language 与 Decision Problem Family 选择的依赖；通过 STEP② acceptance gate 后再进入 STEP③
Gate status: OPEN — STEP① contract accepted by human researcher; STEP② active
RQ ID: 尚未分配（STEP② 定义中）
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
| RQ-P4-01 | Architecture-induced Execution State 及其资源生命周期特征 | STEP② DEFINITION IN PROGRESS / NOT REGISTERED |
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
- STEP① 研究对象：ACCEPTED BY HUMAN RESEARCHER
- STEP② Research Question：OPEN / DEFINITION IN PROGRESS
- STEP③ Independence：未开始
- STEP④ Estimand：未开始
- STEP⑤–⑨：未开始

### Allowed

- 继续 P4 概念定义；
- 正式定义、压缩并对抗 P4-A Research Question；
- 完成 STEP② acceptance gate；
- 读取历史 Track B / Track E 资产作为背景约束；
- 历史资产盘点与 Architecture 2.0 概念复盘；
- 研究“短周期、增量式、反例驱动”的跨模型泛化方法，但不把它注册为新 RQ；
- 保存新的、尚未注册的 Architecture 2.0 概念假设。

### Forbidden

- 把 STEP② 草案直接当作已注册 RQ；
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

Description Language Attack 已进一步收缩为可审计的成本会计与证伪协议：采用 Codebook / Rate / Decoder 三项成本分账；decoder 冻结并公开为 artifact，runtime 只能使用冻结 decoder + 码流；decoder spec 不得携带被测架构专属实现事实；L₀ 定义为 byte-level direct dump 的零失真 reference language。上述内容仍属于 STEP① 候选定义，不构成 Runtime API。

Analytic Encodability Attack 已进一步收缩为 **Static Derivability** 标准：一个从未运行过目标模型的 agent，应仅凭允许的静态 architecture / computation-structure description 导出 Encoder_X。允许 architecture spec、声明式结构、计算语义、依赖/type/shape 信息及静态阅读源码；禁止执行后通过 trace、benchmark、memory behavior、migration/materialization behavior、decision labels 或 workload trace 发现/调整编码字段。约束的是知识来源，而非禁止 Architecture X → Encoder_X。

下一步记录一个未来的 **Novel-Architecture Probe**：未来评估应包含熟悉架构家族、结构不同的已知家族，以及至少一个编码者既有经验之外的架构或 purpose-built variant。若 analytic encoding 仅在熟悉家族成立而新结构需要大量人工修改，则应记录为 applicability boundary，而非 universal validity。该项属于未来 STEP②–⑨ 设计约束，当前不授权实验。

同时保留非二元候选：Architecture → analytic structural skeleton → minimal measured coefficients → projection → Runtime decision。状态结构字段可能可静态解析，而 migration granularity、reconstruction order、reattach feasibility 等 transition/materialization 字段可能需要少量实测。后续可将问题收缩为“完成 analytic skeleton 所需的最小经验信息量”，但当前没有 measurement authorization。

为防止 STEP① 把研究对象与完整实验协议混为一体，现明确区分 **Definition Layer** 与 **Evaluation-Constraint Layer**。Definition Layer 保留固定 language L、frozen decoder、L₀、A:D regime、analytic provenance requirement；未来 Evaluation-Constraint Layer 才承载 two-part accounting 的 operationalization、decoder-in-the-loop、六项攻击目标的具体测试、novel-architecture sampling、rate/distortion estimand、measurement budget/threshold。后者当前只保留 provenance，不构成实验授权。

**下一概念攻击固定为 Decision-Loss Well-Definedness Attack。** 核心问题：在不引入 Runtime implementation 的情况下，Decision Loss D 能否被定义为不依赖研究者任意选择、且足以区分 projection 的量。若可以由形式化 decision model 定义，则继续 STEP①/后续定义；若必须引入 decision process、simulation 或 executable harness，则必须显式开启 Harness Authorization Gate，禁止因 D 难定义而隐式进入实现。

上述内容仍处 STEP①，不创建 RQ，不授权 implementation、harness、data collection 或 measurement。

## 14. 状态维护规则

1. 任何状态变更必须更新本文件并独立 commit；
2. 本文件只记当前状态；
3. RQ ID 一经分配永久占用，废弃用 CLOSED/NOT DEFINED 标注，不复用编号。

## 15. P4-A STEP① 契约接受与 STEP② 开放（2026-09-22）

研究者明确接受 P4-A STEP① candidate contract，并正式授权进入 STEP② Research Question。

STEP① 已接受的契约包括：固定 Description Language、frozen decoder、L₀、O(A)/O(D) regime、Static Derivability、analytic skeleton + minimal measured coefficients 候选，以及 Bayesian decision problem / Blackwell framework 下的 Decision Loss 定义。决策问题写为 `𝓓=(𝓐,𝓒,Π_W)`，projection 的损失以相对 full-information/oracle 的 Bayes risk excess cost 表示；参数族内 dominance 发生反转时，边界本身可成为 applicability finding。

Decision-Loss 的形式化闭合了 STEP① 的定义问题，但不证明跨架构 projection 已存在、低码率、低维度或具有 Runtime 实用价值。

### STEP② 的合法范围

STEP② 当前只负责：
- 将接受的契约压缩为 precise、independent、falsifiable Research Question；
- 继续进行必要的概念反例与范围收缩；
- 明确 RQ 的对象边界、比较范围与不可推断项；
- 完成 STEP② acceptance gate。

禁止：
- 自动把草案升级为注册 RQ；
- 自动进入 STEP③–⑨；
- Runtime / harness / profiling / data collection / measurement；
- 重新研究 Track B 已闭合的 lifecycle semantics；
- 将 Decision-Loss 形式化误读为 projection 已被验证。

若未来预定义 decision-problem family 被证明无法解析评估，才可单独开启 definition-stage executable artifact mini-gate；该 artifact 只能检验定义自洽性，不产生研究证据。STEP⑨ research harness 仍需注册 RQ 与后续设计门。

**Current status:** STEP② OPEN / RQ CANDIDATE UNDER ATTACK / RQ ID NOT YET ASSIGNED / NO EXPERIMENT AUTHORIZATION

**Next formal checkpoint:** STEP② Research Question definition/acceptance gate。

## 13.2 P4-A STEP② 首轮 RQ candidate 与 Frontier 独立性攻击（2026-09-22）

STEP① 契约已接受后，正式进入 STEP②。首轮 RQ candidate 被压缩为：

> 在固定 Description Language 与预定义 Decision Problem Family 下，State representation 的描述成本与 Runtime Decision Loss 之间是否存在可重复、可区分的 Rate–Decision-Loss frontier？

信息充分性必须受 Rate 约束，否则完整 State / L₀ 可平凡保留全部信息。当前采用候选形式 D*(R)=min over P with Rate(P)≤R of D(P)，以避免人为指定固定 K。

Cross-architecture extension 暂不作为核心 RQ 前提，而是后续比较：frontier 是否具有可比较共性，以及其适用边界由 architecture、workload、resource regime 如何决定。

### 当前 STEP② 首个攻击

必须攻击：Rate–Decision-Loss frontier 是否只是由研究者选择的 Description Language L 与 Decision Problem Family 人为定义出来的数学对象，而不是 Architecture-induced phenomenon？

其中分别检查：
- Rate(P) 对 Description Language / primitive vocabulary 的依赖；
- D(P) 对 decision family、workload prior、cost model 的依赖；
- 所谓 frontier 的定性结构是否在预先允许的选择族中保持稳定。

当前没有任何 robustness 结论；该问题仍处于概念攻击阶段。

**Current status:** STEP② OPEN / RQ CANDIDATE UNDER ATTACK / RQ ID NOT YET ASSIGNED / NO EXPERIMENT AUTHORIZATION
