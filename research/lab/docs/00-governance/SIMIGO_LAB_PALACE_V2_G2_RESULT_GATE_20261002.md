# PALACE V2 G2 Result Gate — HUMAN RULING REGISTERED

日期：2026-10-02  
对象：G2 执行记录（`30f8f4a`/`d5f286e`）  
Verdict：**`G2 CROSS-DOCUMENT WORK — PASS / CLOSED`**  
性质：gate 裁定登记——不产生 PALACE Schema；不预写 G2 补充实验

## 1. 裁定表（human 原文）

| 项目 | 裁定 |
|---|---|
| G2 主实验 | **PASS / CLOSED** |
| T-1 / T-2 / T-3 | **全 PASS** |
| OB-A 已发现信息复用 | **SUPPORTED** |
| OB-B 跨文件映射 | **SUPPORTED** |
| OB-C 工作过程依赖 | **SUPPORTED / 强证据** |
| OB-D 综合与对应 | **SUPPORTED** |
| H-G1-01 | **SUPPORTED — strengthened** |
| H-G1-02 | **SUPPORTED (strong exploratory evidence)** |
| ES 必要性 | **UNPROVEN**（L0+L1 仍可重算） |
| 新 PALACE Schema | **NOT AUTHORIZED** |
| G3 | **UNLOCKED**（Durable Information 问题已自然产生） |

## 2. 关键判读登记（human 归纳，效力高于执行记录原文表述）

### OB-A：复用的对象不是文件路径

被复用的是：发现了什么/比较过什么/哪些数字存在候选对应/哪些不能
对应/哪里口径冲突/哪些问题未闭合——工作过程中实际存在并被后续
步骤使用。术语纪律继续：不定义 Information Object/Relation/
Provenance。

### OB-B：0/26 精确映射是高价值结果

打掉危险假设「相近数字 = 同一东西」。三形态登记：分项级强候选
（0.03%–0.47%，单位未声明 ⇒ **候选 ≠ 可确认对应**）；总量级缺口
（= 当前工作范围的信息层面缺口）；范围外指标（产值/批复/收款
本就不同范围）。跨文件工作必须处理**相似、候选、不可对应、范围
不同**等不同状态——不能把数字匹配简化成搜索命中。登记
Observation：**数字的可发现性 ≠ 可解释性；相似性 ≠ 口径一致**。

### OB-C：最强状态依赖证据形态

T-3 八点综合全部依赖 T-1/T-2/Phase2/G1 累积发现，零新增读取——
「理论上可能依赖」升级为「实际直接使用」。H-G1-02 升格
**SUPPORTED (strong exploratory evidence)**；**ES 必要性保持
UNPROVEN**（L0+L1 仍可重算——控制变量继续有效）。

## 3. G3 解锁（Durable Information）

G3 不从数据库设计开始。第一问（human 原语冻结）：

> **如果今天把当前工作停止，明天重新打开，我究竟需要什么，
> 才能真正从这里继续，而不是重新做一遍？**

观察四类（不定义 schema，只观察实际发生什么）：

```text
① 已经发现过什么（T-1 检查过哪些数字）
② 已经判断过什么（3,761.06 vs 4,200 相关但无法裁决口径）
③ 已经排除过什么（某些数字不属于标后预算范围——传统检索
   系统最容易丢掉的类别）
④ 下一步为什么是下一步（需要寻找 313,356万生产来源）
```

现实成本验证：若明天回来这些全部消失只剩原始文件，用户必须
**重做一遍 T-1/T-2**——这才是 G3 应该验证的现实成本。

## 4. SimiGo ↔ PALACE 边界登记（human 结构）

```text
PALACE G1  我能找到什么？
PALACE G2  已找到的东西能否继续支持下一步工作？
PALACE G3  这些工作信息能否在未来继续存在并支持工作？
SimiGo     这个持续进行中的工作本身如何成为可恢复的
           Execution State？
```

G3 **不是重新定义 Execution State**——第一次把 PALACE 的
Durable Information 与已冻结的 Execution State 放到真实工程
边界上观察：哪些属于 PALACE、哪些最终需要 SimiGo，
**让工程把它们逼出来**。

## 5. Gate state

```text
G0 Memory Backend Survey   CLOSED
G1 Real Corpus Work        CLOSED
OQ-B Drift                 CLOSED
E6 Information Validity    CLOSED
G2 Cross-Document Work     PASS / CLOSED（T-1/T-2/T-3 全 PASS）
H-G1-01                    SUPPORTED — strengthened
H-G1-02                    SUPPORTED (strong exploratory)
ES 必要性                  UNPROVEN
PALACE Schema              NOT AUTHORIZED
G3 Durable Information     UNLOCKED / DESIGN ENTRY
```
