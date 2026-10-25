# PALACE-SimiGo Boundary Study — 方向登记（human 裁定）

日期：2026-10-02  
状态：`DIRECTION REGISTERED / BOUNDARY_STUDY_DEFINED / DESIGN_DRAFT_PENDING_HUMAN_INITIATION`  
Registration authority：explicit human direction ruling（本会话）  
前置：G0/G1/OQ-B/E6/G2/G3 全链 CLOSED（G3 收束登记
`SIMIGO_LAB_PALACE_V2_G3_CLOSED_BOUNDARY_STUDY_ENTRY_20261002.md`）

## 1. 核心研究问题（human 原语冻结）

> **如果 PALACE 已经拥有足够完整的信息，两个工作者面对同一个
> 信息世界时，为什么仍然不能互相恢复对方的工作状态？**

比继续扩展 PALACE 信息能力更接近 SimiGo 的核心。

## 2. ES 候选边界测试六问（human 原语冻结）

PALACE 能恢复所有共同信息的情况下，若仍无法回答：

```text
· A 已经检查过什么？
· A 为什么跳过某个文件？
· A 已经排除了什么？
· A 当前正在验证什么？
· A 下一步准备做什么？
· B 接手 A 的工作时究竟缺什么？
```

则这部分才真正有资格成为 **Execution State 的候选边界**。

## 3. 四情况观察矩阵（human 原文冻结）

```text
同一 PALACE
   ├── 人 A / 任务 X / 路径 X
   ├── 人 A / 任务 Y / 路径 Y
   ├── 人 B / 任务 X / 路径 Z
   └── Agent / 任务 X / 路径 W
```

## 4. 分叉连接（与「不同目录就是天然分叉」接续）

```text
信息空间的分叉 → 不同工作 → 不同探索路径 → 不同 Execution State
```

## 5. 价值判定（反向逼出，实证闭环）

若 Boundary Study 最终证明「同一个 PALACE 中，工作者的路径仍然
无法由 PALACE 本身恢复」——那时 SimiGo 的存在价值就不是概念上
的，而是**被 PALACE 实验反向逼出来的**。

终态公式（human 原文）：

> **PALACE 负责「世界」，SimiGo 负责「人在世界中的持续行动」。**

## 6. 当前正式状态（human 保持）

```text
G0→G3                          = CLOSED
H-G1-02                        = SUPPORTED — strong exploratory
ES necessity                   = UNPROVEN
RQ-G3-1 / RQ-G3-2              = 已完成并收束
RQ-G3-3                        = 暂存
```

## 7. 纪律（human 原文语义）

继续坚持：**先观察「什么必须留下」，再决定「应该叫什么」。**

尤其不能先造 DurableInformation / WorkState / Provenance /
Relation 类，再拿实验去证明。让实验逼出自然结构。

## 8. Next

```text
Boundary Study 设计草案 = 待 human 发起后起草
（观察矩阵/测试六问/停点与恢复判据在设计阶段冻结）
```
