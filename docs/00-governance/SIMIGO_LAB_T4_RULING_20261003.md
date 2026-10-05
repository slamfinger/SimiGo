# T4 终裁 — STRONG PROPOSITION / T4 PASS（TASK-DOMAIN BOUNDED）

Date: 2026-10-03  
Chain: Experimental Design PASS → Task Pinning PASS/HASH FROZEN →
Execution PASS → **Attribution = STRONG PROPOSITION**  
Status: `T4 = PASS / STRONG ATTRIBUTION (TASK-DOMAIN BOUNDED) / CLOSED`

## 1. human 终裁（逐字要点）

**强命题格，T4 = PASS（限定于本任务域）。**依据冻结的 S-6 / S-9
判据，四项条件均满足：T-3 = PASS / AC-1 = PASS / AC-2 = PASS /
AC-3 = PASS。

三条证据链同时成立（缺一不构成强命题）：

1. **T-3 成立**：C-N 未产生 P-1 opaque facts，non-derivability
   后验未被击穿
2. **AC-2 成立**：B-E 先 fetch 后生成摘要；取回内容与最终数值
   逐项对应——存在 **Information → 消费 → continuation 产物**
   的时间与内容因果链
3. **AC-3 成立**：相同 B 指令下 C-N 无法取得待办事实，未产生
   摘要，未用虚构内容冒充完成

⇒ 本冻结任务与实验条件下：

> **Information boundary 是完成该 continuation 任务的必要条件。**

## 2. 强命题外延封死（不得升级）

本强命题**不能升级为**「InformationCore 对一般 SimiGo
continuation 都是必要条件」。证据支持范围：

```text
本实验任务域 + 本实验 cold-start 条件 + 冻结的 A/B 结构
+ 冻结的 T-3 facts
        ↓
Information boundary
        ↓
该 continuation 的必要条件
```

**本任务域中的必要性，不是普遍定理。**

无效触发复核：B-E 瞬时自校验混淆已自行纠正且未破坏 AC-1/AC-2；
B-N 工具字符串探测未产出 T-3 facts 或任何 F1–F6 内容 ⇒ 按预注册
纪律，**未触发整轮作废或强命题降级条件**。

## 3. T4 最终状态

```text
T4 Experimental Design = PASS
T4 Task Pinning        = PASS / HASH FROZEN
T4 Execution           = PASS
T4 Attribution         = STRONG PROPOSITION

结论范围：Information boundary
        = 本冻结任务域 continuation 的必要条件
```

## 4. 研究结论登记（Track D 记忆边界线阶段性结论）

自 T1–T3 记忆生态实验起、经 palace 语义审计与边界冻结、至
InformationCore/RelationCore 双核与 T4，本线已建立的完整结论链：

```text
① 语义面      palace 机制中剥离出 Information/Continuity/机制
              三分（Phase 0，服务树锚定）
② 契约面      InformationStore S1–S6 ∥ RelationStore R1–R6
              （对称、backend-independent、first-write-wins）
③ 实现面      InformationCore / RelationCore（Swift，零第三方，
              受保护文件零 diff 纪律全程保持）
④ 结构面      接入边界 / backend 独立性 / 持久化语义三 Gate
              结构证明（含真实跨包 path dependency）
⑤ 因果面      T4 强命题：Information boundary = 本冻结任务域
              continuation 的必要条件（T-3/AC-1/2/3 全过，
              C-N 阴性对照失败且零虚构）
```

**数据库是实现选择，而不是架构前提；Information boundary 是
（本任务域已证必要的）continuation 基座。**

## 5. 下一阶段

T4 已收口。后续方向（跨任务复现 / Execution 层 / 其他）= 待
human 指令另行开 Gate；不自行跨 Gate、不扩面。Finding-1 审计
教训与全部负空间纪律继续有效。
