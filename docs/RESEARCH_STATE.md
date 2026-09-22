# SimiGo-Lab Research State

> **This file is the authoritative snapshot of the current SimiGo-Lab research state.
> Conversation memory must not override it.**
> Git 保存事实，会话负责推理：任何“项目到哪了”的问题，先读本文件与所引 endpoint 文档，再回答。

**Last updated**: 2026-09-22（增量泛化规划落盘；P4-A STEP① 继续）

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

## 5. Sealed / Closed

Track B、Track E、P3、H-P1、nodes-out 保持原有 CLOSED / SEALED / FROZEN 状态。历史路线不自动重开。

## 6. Not started / Not defined

| 项 | 状态 | 约束 |
|---|---|---|
| P4（RQ-P4-01） | NOT STARTED / NOT DEFINED | 仍须独立完成 Definition Gate |
| Source/Runtime / RQ-F-01 | RETIRED / NOT DEFINED | 不进入 STEP⑤；此前状态不向 P4 转移 |
| Swift implementation | NOT STARTED / NO BASIS | 不因 P4 重定义获得授权 |

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
- 研究“短周期、增量式、反例驱动”的跨模型泛化方法，但不把它注册为新 RQ。

### Forbidden

- 把 P4 当前定义直接当作已注册 RQ；
- 转移 Track B / Track E 证据为 P4 结论；
- 直接进入 STEP⑤–⑨；
- Runtime implementation / harness construction / data collection / performance measurement；
- 预设 Universal Model Unit / Universal Physical State Representation；
- 扩张为研究全部模型内部知识、语义、概率与表示；
- 继续 RQ-F-01 Source/Runtime boundary/unit 路线；
- 为了“通用”而预先加入未经真实架构反例迫使的抽象层。

## 8. Definition Gate

① 研究对象 → ② Research Question → ③ 独立性 → ④ estimand → ⑤ existence criterion → ⑥ negative criterion → ⑦ discriminating power → ⑧ information value / cost → ⑨ Path / Harness / Experiment。

## 9. 新增研究规划原则

Architecture 2.0 采用：

当前代表性架构 → 最小抽象 → 新架构反例 → 最小必要扩展 → 再验证。

通用性由真实架构反例推动，而不是由想象中的未来模型推动。没有反例，不提前增加抽象层；若面对新架构需要大幅修改既有抽象，则停止继续泛化并重新审查抽象边界。“不能泛化”本身是合法研究结果。

详细规划：docs/07-history/ARCHITECTURE_2.0_INCREMENTAL_GENERALIZATION_PLAN_20260922.md

## 10. 重要边界

SimiGo 1.x product line ≠ SimiGo-Lab 2.0 research line。

事实源优先级：Git 仓库（本文件 + endpoint 文档 + ledger + git log）> 对话记忆。

## 11. 状态维护规则

1. 任何状态变更必须更新本文件并独立 commit；
2. 本文件只记当前状态；
3. RQ ID 一经分配永久占用，废弃用 CLOSED/NOT DEFINED 标注，不复用编号。
