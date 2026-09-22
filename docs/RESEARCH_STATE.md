# SimiGo-Lab Research State

> **This file is the authoritative snapshot of the current SimiGo-Lab research state.
> Conversation memory must not override it.**
> Git 保存事实，会话负责推理：任何“项目到哪了”的问题，先读本文件与所引 endpoint 文档，再回答。

**Last updated**: 2026-09-22（P4 路线落盘；P4-A STEP① 开始）

## 0. 状态恢复流程（重进项目时固定执行，不得跳过）

```
① 读取本文件（RESEARCH_STATE）
        ↓
② 读取当前阶段的 endpoint / closure 文档
        ↓
③ 核对最近 git log 与本文件是否一致
        ↓
④ 按 §2 状态词汇确认 sealed / closed / open / not-started
        ↓
⑤ 才允许回答问题或提出动作
```

## 1. 当前阶段

```
Phase:        Architecture 2.0 / P4 Redefinition / Pre-definition
Next action:  完成 P4-A STEP① 研究对象逐项审查；通过后再进入 STEP②
Gate status:  CLOSED — 旧 Source/Runtime 定义链停止；P4 尚未完成 RQ 定义
RQ ID:        未分配
当前活动文档: docs/07-history/ARCHITECTURE_2.0_P4_REDEFINITION_20260922.md
```

## 2. 状态词汇表（禁止跨阶段推理）

| 状态 | 含义 | 推理约束 |
|---|---|---|
| SEALED | 结论冻结 | 禁止“继续优化该结论”类推理 |
| CLOSED | 研究问题已完成合法出口 | 禁止据此推导“立即开始下一实验” |
| OPEN | 当前在册研究问题 | 仅此状态的问题构成当前任务 |
| DEFINED | 已定义但尚未开始 | 仅允许其预注册 Allowed 动作 |
| NOT DEFINED | 连问题都尚未正式立项 | 禁止一切实现/采数/测量动作 |
| FROZEN | 基础设施可复用，但身份不可变 | 复用必须建立新 provenance 锚点 |
| SEPARATELY SCOPED | 有关联，但不得并入当前研究 | 禁止跨线引用结论 |

## 3. 研究问题唯一 ID

| ID | 研究问题 | 状态 | 锚点 |
|---|---|---|---|
| RQ-B-01 | Execution State lifecycle 语义（收敛模型） | CLOSED / FROZEN | `4184aa6` |
| RQ-P3-01 | Residency policy 频率机制 | P3-A 终判 PASS / P3-B R3 CLOSED / P3-C R-W CLOSED·SEALED | `ff52943` / `072fc2f` / `ac71e34` |
| RQ-H-01 | 结构信号存在性 | CLOSED / SEALED | `edc4dad` |
| RQ-NO-01 | 取消 node 粒度外化通道：粒度 / correctness / 边界成本 | CLOSED | `2cf244e` + `b6ad7c0` |
| RQ-P4-01 | Architecture-induced Execution State 及其资源生命周期特征 | NOT STARTED / NOT DEFINED | — |
| RQ-F-01 | Source/Runtime 机制可实现·可验证性 | RETIRED CANDIDATE / NOT DEFINED | 方向重审 2026-09-22 |

## 4. Mainline

```
当前 Architecture 2.0 主线：
Model Architecture Features
        ↓
Computation
        ↓
Execution State
        ↓
State Characteristics
        ↓
Resource Behavior
        ↓
Loading / Residency / Layering / Working Set / Migration
        ↓
Runtime Architecture
```

历史主线与已关闭路线保留在历史文档中，不自动重开。

## 5. Sealed / Closed 清单

Track B、Track E、P3、H-P1、nodes-out 均保持原有 CLOSED / SEALED / FROZEN 状态。

## 6. Not started / Not defined

| 项 | 状态 | 约束 |
|---|---|---|
| P4（RQ-P4-01） | NOT STARTED / NOT DEFINED | 重新定义后仍须独立完成 Definition Gate |
| Source/Runtime / RQ-F-01 candidate | RETIRED / NOT DEFINED | 不进入 STEP⑤；此前状态不向 P4 转移 |
| Swift implementation | NOT STARTED / NO BASIS | 不因 P4 重定义而获得授权 |

## 7. Current gate

```
P4 / RQ-P4-01
  STEP① 研究对象：WORKING DEFINITION / 审查中
  STEP② Research Question：未开始
  STEP③ Independence：未开始
  STEP④ Estimand：未开始
  STEP⑤ Existence Criterion：未开始
  STEP⑥ Negative Criterion：未开始
  STEP⑦ Discriminating Power：未开始
  STEP⑧ Information Value / Cost：未开始
  STEP⑨ Path / Harness / Experiment：未开始
```

### Allowed

- 继续 P4 的概念定义；
- 完成 P4-A STEP① 研究对象逐项审查并形成 closure 记录；
- 读取历史 Track B / Track E 资产作为背景约束；
- 继续历史资产盘点；
- 继续 Architecture 2.0 概念复盘。

### Forbidden

- 把 P4 当前定义直接当作已注册 RQ；
- 把 Track B / Track E 的证据直接转移为 P4 结论；
- 直接进入 STEP⑤–⑨；
- runtime implementation / harness construction；
- data collection / performance measurement；
- 预设 Universal Model Unit；
- 预设 Universal Physical State Representation；
- 把“模型架构”扩张为研究全部模型内部知识、语义、概率与表示；
- 继续 RQ-F-01 Source/Runtime boundary/unit 路线。

## 8. Definition Gate

```
① 研究对象是什么
② 研究问题是什么
③ 为什么它是一个独立问题
④ estimand 是什么
⑤ 什么观察结果构成“存在”
⑥ 什么结果构成“不足以支持存在”
⑦ discriminating power 是否成立
⑧ 值得测吗（成本-信息量比）
⑨ 通过后才决定 Path / Harness / Experiment
```

## 9. 重要边界

SimiGo 1.x product line ≠ SimiGo-Lab 2.0 research line。

事实源优先级：Git 仓库（本文件 + endpoint 文档 + ledger + git log）> 一切对话记忆。

## 10. 状态维护规则

1. 任何状态变更必须更新本文件并独立 commit；
2. 本文件只记当前状态；
3. RQ ID 一经分配永久占用，废弃用 CLOSED/NOT DEFINED 标注，不复用编号。
