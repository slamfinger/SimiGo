# Track E nodes-out Definition Recovery / Definition Lock(2026-09-22)
**DRAFT v1.0 待审核(远端裁定门:Definition Lock PENDING → 本文响应)**

> 背景:H-P1 CLOSED/SEALED(edc4dad)后,nodes-out UNLOCKED 但
> Definition Lock PENDING——远端要求先恢复 Track B/M3 原始定义再写
> 正式开题。本文 = Definition Recovery 结果 + Definition Lock 提案;
> 只锁边界,不设计实验,不含实现/采数。

## 1. 考古证据(检索范围与命中)

| 检索域 | 术语命中 | 结论 |
|---|---|---|
| `trackB-execution-state/`(Track B 全部 8 份文档) | **0**(grep "nodes-out"/"节点外化"/"挤出";"nodes" 仅页恢复/共享驻留语境路过) | **Track B 无此概念** |
| `ARCHITECTURE_2.0_PRERESEARCH_20260920.md` | "nodes" 0 次 | 无 |
| `RESIDENCY_POLICY_OPENING_20260921.md` | 0 | 无(术语晚于开题) |
| `RESIDENCY_M1–M4_RESULTS` | "nodes" 仅为节点计数;**无 "nodes-out" 术语** | M3/M4 有 node 粒度 residency **语义**,无此**术语** |
| `RESIDENCY_P01_COST_UNIT_DRAFT_20260921.md`(commit 0b88517→cb66671→fa28ab6) | **首次出现**:三候选计价之一 "**nodes-out 挤出计价**" | 唯一历史锚点 |
| `RESIDENCY_H-P1_OPENING_20260922.md` L22–23 | "nodes-out = 串行…答'**节点/结构从 residency 系统移除后会怎样**'";L41/L130 标注"**待决**" | 占位工作描述,非定义 |
| `RESIDENCY_P3_RESULTS_20260921.md` 等 P3 链 | "nodes-out 评估"列入后续候选(与 structure-aware 并列) | 延续占位 |

## 2. 恢复结论(核心发现)

**"nodes-out" 不存在 Track B/M3 原始定义,亦无任何已被正式定义的
历史形态可恢复。**它是 2026-09-21 P0.1 Cost Unit Definition 中提出的
resident opportunity cost 候选计价概念("挤出计价"),提出当日即随三
候选整体移出规范目标、归入 **Deferred**;此后仅作为串行链占位词被
引用(H-P1 开题,标注"待决")。因此,Definition Lock 的性质不是
"恢复",而是**首次正式定义**,其历史依据只有一条:挤出计价语境
(P0.1)+ M3/M4 的 node 粒度 residency 二态语义(resident/externalized,
C_ext/C_rehy)+ H-P1 串行链占位描述。此结论本身即远端"定义不足"
判断的实证落档。

## 3. 远端 5 问逐答(证据 → 锁定提案;提案待审核确认)

### Q1 nodes-out 是对象还是通道?
证据:P0.1 语境=事件流/计价对象(被挤出节点的反事实成本);H-P1
占位=机制/通道("从 residency 系统移除")。
**锁定提案**:nodes-out = **节点外化通道(node externalization
pathway)**——capacity 驱逐时 EXTERNALIZE 动作在节点粒度上的通道;
非 Track B 执行态迁移机制(那是 KV+Identity+Position+NextInput+
Continuation 的整体 fork/reattach,与 node 外化正交)。

### Q2 "移除"的精确含义(A–F)?
| 选项 | 与历史锚点关系 | 提案 |
|---|---|---|
| A 完全取消 nodes-out | 无锚点 | 排除(与 simulator 现实矛盾:容量约束必须有外化动作) |
| B 不再作为策略选择 | 部分契合占位义 | 并入主提案 |
| C 不再允许 resident | 无锚点 | 排除 |
| D nodes-out 状态迁移到 KV | 与 Track B 迁移语义交叉,但无历史锚点 | 排除为独立选项 |
| E execution state 重编码 | 无锚点 | 排除 |
| F 仅取消某个外化/迁移通道 | **最贴候选 1/2 语义** | **主提案** |
**锁定提案**:nodes-out"移除" = **F——取消节点粒度的外化/迁回
通道**,考察 residency 二态退化为非节点粒度(如统一 KV 块粒度)后,
迁移正确性与边界成本的变化。此为提案,最终含义由审核方在 A–F 中
裁定。

### Q3 "仅保留 KV 常驻/外化二态"是否原始比较域?
**不是原始比较域**(无原始定义可依)。状态:候选实验模型,须经
审核方确认后方可写进正式开题;在审核确认前禁止使用该二态模型
推导任何结论。

### Q4 execution state 拆分定义
按 Track B 收敛模型(4184aa6,冻结)拆分:KV state / Identity /
Position / Next Input / Continuation Semantics(五元组)+ parameter
residency(模型权重侧,与 KV 正交)。nodes-out(按 Q1 提案)只触及
**KV state 的驻留粒度维度**;Identity/Position/NextInput/Continuation
不受影响——这是"迁移正确性"可判定的关键(统一不变式"migration
must preserve execution identity and continuation"照旧适用)。

### Q5 成本通道不直接继承 H-P1
H-P1 的 J(C_ext×#ext + C_rehy×#rehy) 可作基础设施,但 nodes-out 若
取消节点粒度通道,至少新增候选通道:**state 迁移/重编码成本、
correctness 违例成本、粒度变化导致的容量-字节数关系变化**
(节点 78,246 KiB 的计账单位失效)。均须独立定义,禁止塞进既有 J。
具体数值定义留待正式开题(本文不定义)。

## 4. Definition Lock(提案版;PASS 后进入 10 节正式开题)

> nodes-out ≡ 节点外化通道(capacity 驱逐时节点粒度 EXTERNALIZE/
> REHYDRATE 路径);"移除 nodes-out" ≡ 取消该通道,residency 二态
> 退化为非节点粒度(具体粒度=正式开题的定义项,不在本文预填)。
> 研究问题(占位转正式,待审核):通道取消后,execution state 迁移
> 正确性(五元组不变式)与边界成本如何变化?

**审核需裁定项**:①Q1/Q2 锁定提案是否接受(或改选他项);②Q3
KV 二态候选模型是否批准为正式开题的比较域;③Q5 新成本通道清单
是否需增删。裁定后按远端 10 节结构写正式 DRAFT(①原始定义(本文)
②研究问题 ③移除边界 ④execution state 定义 ⑤KV/node residency
边界 ⑥correctness 定义 ⑦cost channels ⑧与 H-P1/P3 继承关系
⑨禁止的解释 ⑩Exit criteria);Implementation/采数继续 LOCKED。

## 5. 证据索引

- P0.1:`RESIDENCY_P01_COST_UNIT_DRAFT_20260921.md` L22(Deferred
  表)、L119–121(三候选移出规范);commits 0b88517/cb66671/fa28ab6
- H-P1 开题:`RESIDENCY_H-P1_OPENING_20260922.md` L22–23/41/130
  (串行占位,"待决")
- Track B:`trackB-execution-state/` 全目录 0 命中(grep 记录于
  本文 §1);`TRACK_B_CLOSURE_RESULTS_20260921.md`(五元组收敛模型)
- M3/M4:`RESIDENCY_M3*_RESULTS_20260921.md`/`RESIDENCY_M4_RESULTS_
  20260921.md`(node 粒度 residency 语义;无此术语)
