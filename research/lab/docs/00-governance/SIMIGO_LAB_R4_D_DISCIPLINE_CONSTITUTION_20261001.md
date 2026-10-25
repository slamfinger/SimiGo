# R4 D — Research Discipline Constitution（实验宪法）

日期：2026-10-01  
状态：`C_PASS_REFRAMING_ACCEPTED / D_CONSTITUTION_REGISTERED / P4_DESIGN_NOT_OPEN`  
裁定人：human（C 门裁定：YES）  
效力：本宪法对 Phase R4 后续一切工作（P4 设计/执行/裁定、P5）具约束
力；修订须经 human。

## 0. C 门裁定记录

**C = PASS / REFRAMING ACCEPTED**——P4/P5 进入 SimiGo 核心研究问题。
理由（human 四条，登记）：①A 线把问题从「State 是什么」改成可检验的
行为判据（S+X→Y 非内部实现定义）；②B 线确认真缺口——fork/shared
base 既未被否证也未被证明；③P4 正落 SimiGo 原始核心问题（让已形成的
执行状态成为后续计算的基础——从工程直觉变独立研究命题）；④P5 服从
P4 不倒置（否则滑向 backend 性能实验）。

本 YES 只授权进入 D 门：**不授权 P4 执行，不提前定义 State 内部形态**。

## 1. 实验宪法（D1–D8，human 原文）

```text
D1 — Common Base        必须存在同一个已形成的 S₀
D2 — Two Independent Futures
                        至少两个真正不同的未来输入/分支
D3 — Independence       A、B 分支不得互相污染
D4 — Independent Sample 不能只在当前 Qwen3-Next / 当前 session 上证明
D5 — Observation Discipline
                        observation null ≠ mechanism null
D6 — No Construct-Then-Claim
                        人工制造出来的 carrier 不能证明原系统中该
                        State 形式原本存在
D7 — Backend Boundary   backend 可以负责增量计算，但 backend 内部
                        机制不得被偷偷提升为 SimiGo 的 State 定义
D8 — No Premature P5    P4 没有成立以前，不研究「节省多少计算」「是
                        否真的没有重算」等 P5 问题
```

## 2. 拓扑优先原则

**P4 首先只问拓扑，不问性能**：

```text
              ┌──→ Future A
S₀ ───────────┤
              └──→ Future B
```

要证明的是：**A、B 确实从同一个 S₀ 出发，并且之后可以独立演化**——
而不是先证明「这样比重跑 History 快多少」。

## 3. 失败有效性条款（human 原文，写死）

> **P4 如果最后失败，也必须允许它以「共同基点目前无法成立」的形式
> 成为有效研究结果；不能为了让路线成立而修改判据。**

任何判据修订（含 A 线 SUFF/IDENT 的实例化偏差）必须在设计文档中预注
册并经 human 确认；事后改判据 = 无效裁定。

## 4. 门位

```text
R4-0 PASS → A1-A4 PASS → B PASS → C PASS / REFRAMING ACCEPTED
  → D Research Discipline Confirmation（本文，当前）
  → P4 Design（Common Base / Divergence / Independence）
  → Human authorization → P4 Execution → P5
```

## 5. 禁止事项

```text
❌ 现在进入 P4 实验或执行
❌ 提前定义 State 内部形态
❌ P4 设计/裁定中引入性能问题（D8）
❌ backend 内部机制升格为 State 定义（D7）
❌ 为使路线成立而修改判据（§3）
```
