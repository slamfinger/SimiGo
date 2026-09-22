# SimiGo-Lab Research State

> **This file is the authoritative snapshot of the current SimiGo-Lab research state.
> Conversation memory must not override it.**

**Last updated**: 2026-09-22（STEP④ Estimand PASS；正式进入 STEP⑤ Existence Criterion）

## 1. 当前阶段

Phase: Architecture 2.0 / P4 Redefinition / STEP⑤ Existence Criterion
Next action: 定义 Achievable Static Frontier 的最小、可证伪、非循环 existence criterion；不得预设非空、非退化、低码率、跨架构共性或 Runtime value
Gate status: OPEN — STEP① accepted; STEP② accepted; STEP③ passed; STEP④ passed; STEP⑤ active
RQ ID: 尚未分配（正式 RQ registration 尚未发生）
当前活动文档: docs/07-history/ARCHITECTURE_2.0_P4A_STEP4_ESTIMAND_PASS_STEP5_OPEN_20260922.md

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
| RQ-P4-01 | Architecture-induced Execution State 及其资源生命周期特征 | STEP④ PASS / STEP⑤ OPEN / NOT REGISTERED |
| RQ-F-01 | Source/Runtime 机制可实现·可验证性 | RETIRED CANDIDATE / NOT DEFINED |

## 4. Mainline

Model Architecture Features → Computation → Execution State → State Characteristics → Resource Behavior → Loading / Residency / Layering / Working Set / Migration → Runtime Architecture

潜在反向研究路径（尚未验证）：

Post-Training → Computation / Execution-State Behavior

## 5. Sealed / Closed

Track B、Track E、P3、H-P1、nodes-out 保持原有 CLOSED / SEALED / FROZEN 状态。历史路线不自动重开。

## 6. Not started / not defined

| 项 | 状态 | 约束 |
|---|---|---|
| P4-A existence criterion | STEP⑤ OPEN | 只允许定义与对抗 existence criterion，不授权实验 |
| Source/Runtime / RQ-F-01 | RETIRED / NOT DEFINED | 不进入 STEP⑤；此前状态不向 P4 转移 |
| Swift implementation | NOT STARTED / NO BASIS | 不因 STEP⑤ 获得授权 |
| Execution-State-oriented Post-Training | HYPOTHESIS / NOT REGISTERED | 不创建新 RQ，不授权实验/实现/测量 |

## 7. Current gate

P4 / RQ-P4-01 candidate
- STEP① 研究对象：ACCEPTED BY HUMAN RESEARCHER
- STEP② Research Question：ACCEPTED / GATE PASSED
- STEP③ Independence：PASS
- STEP④ Estimand：PASS / CLOSED FOR CURRENT FRAME
- STEP⑤ Existence Criterion：OPEN / IN PROGRESS
- STEP⑥–⑨：未开始

### Allowed

- 继续定义与对抗 STEP⑤ existence criterion；
- 使用已冻结的 L、D、sigma_D、S_det、rate convention、oracle normalization 与 scope；
- 设计最低成本的概念反例；
- 如确有必要，可要求本地 agent 执行已获授权的研究动作，并由 ChatGPT 获取、审查、分析结果；当前 STEP⑤ 尚未授予此类实验权限；
- 读取 Track B / Track E 历史资产作为背景约束，但不得转移其证据为 P4 结论。

### Forbidden

- 自动把 P4 candidate 升级为注册 RQ；
- 进入 STEP⑥–⑨；
- Runtime implementation / research harness / data collection / profiling / performance measurement；
- 预设 frontier 非空、非退化、低码率、共同形状或 Runtime usefulness；
- 把 P_AS 非空、单个 endpoint、L₀ trivial encoder 或数学 infimum 自动视为科学意义上的 existence；
- 重新研究 Track B 已闭合的 State lifecycle semantics；
- 将 Execution-State-oriented Post-Training 假设视为已成立。

## 8. Definition Gate

① 研究对象 → ② Research Question → ③ 独立性 → ④ estimand → ⑤ existence criterion → ⑥ negative / insufficiency criterion → ⑦ discriminating power → ⑧ information value / cost → ⑨ Path / Harness / Experiment。

## 9. P4 方法原则

Architecture 2.0 采用：当前代表性架构 → 最小抽象 → 新架构反例 → 最小必要扩展 → 再验证。

通用性由真实架构反例推动，而不是由想象中的未来模型推动。没有反例，不增加抽象层；“不能泛化”本身是合法研究结果。

## 10. 当前 STEP⑤ 入口约束

STEP④ 已将 estimand 固定为 frame-indexed Achievable Static Frontier。关键定义资产包括：

- S_det：确定性、预注册静态派生策略族；
- 固定 Rate counting convention；
- D=(A,C,sigma_D,Pi_W)；
- sigma_D：冻结成本族的最小因子化见证；
- Eval=(budget, estimator, sampling)；
- theta_tilde：联合决策相关层的 workload-regime 分布 / pushforward；
- semantic 与 deployment-economic frontier 分轨，后者显式带 N 或更一般 mu_D；
- 跨架构比较仅在公共可达 rate domain 上进行；不可评估或不可达区间记录为 applicability boundary；
- Target ≠ Estimator ≠ Observed frontier；STEP④ 不证明 finite-sample identifiability。

STEP⑤ 的唯一当前问题是：什么最小、可证伪、非循环的观察条件，才使该 frontier 在给定 frame/scope 内获得“存在”资格，而不偷渡价值、优越性或泛化结论。

## 11. Governance

本次 STEP④→STEP⑤ 是研究治理状态转换。没有新增实验、harness、implementation 或 measurement authorization。
