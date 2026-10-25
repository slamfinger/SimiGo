# Source/Runtime Research Question Definition v0.1

**状态**：`DRAFT / EXTERNAL QUESTION-DEFINITION REVIEW REQUIRED`  
**日期**：2026-09-22  
**Gate**：Definition / Opening —— §8.1 **STEP ②：研究问题是什么**；本文档完成 Q2.1 裁定 + C1 问题候选问句  
**边界**：不定义 estimand（④）、existence criterion（⑤）、insufficiency criterion（⑥）、discriminating power（⑦）、worth measuring（⑧）、Path/Harness（⑨）；不产生采数授权；**RQ ID 不分配**。

## 0. 锚点与依据

| 项 | 值 |
|---|---|
| 状态事实源 | `docs/RESEARCH_STATE.md` |
| STEP ① | Opening v0.1（`b2d4583`）外审 PASS（`6c0a1ec` 登记） |
| 外审保留意见 | C1 表达性约束仅为可检验边界，②–④步禁 implementation-first（约束力） |
| 思想层引用 | `docs/RESEARCH_MEMORY.md` RM-001（研究树）/ RM-005（访问模式原则）/ RM-006（抽象→runtime 链）/ RM-007（unit discovery 先于实现）——均为 CANDIDATE/HYPOTHESIS 态，本文引用其**结构**，不引用其为事实 |
| RQ-F-01 | 仍 NOT DEFINED |

## 1. 四道 RQ 资格门（STEP ② 方法论产物，永久标尺）

| 门 | 内容 | 防止的失败模式 |
|---|---|---|
| G1 新未知量 | 必须存在尚未知道的事实 | 把实现任务包装成研究 |
| G2 不可由旧结论推出 | 未知量无法由既有 CLOSED/SEALED 研究直接导出 | 旧实验换 runtime 后伪装成新发现 |
| G3 双向结果 | "存在 / 不存在"两种结果都有信息价值 | 研究问题预设"必须找到答案" |
| G4 有限出口 | "不存在"能在有限对象空间 + 有限观察边界内合法结束问题 | 无限搜索 / 无限更换候选对象 |

**措辞边界**：四门是候选资格的**标尺**；通过四门 = 有资格进入定义链。**不等于**第③～⑧步（estimand / existence / insufficiency / discriminating power / worth measuring）已完成任何证明。

## 2. Q2.1 裁定

**Q2.1**：Source/Runtime 未知性的最小独立研究对象是什么——C1、C2，还是 C1 × C2？

**裁定（双方确认）**：**C1 = Model Unit，为最小研究对象。**

### 2.1 决定性表述

> **C1 是在不预设机制的情况下，可以独立形成"未知量 → 双向结果 → 有限出口"的最小对象。**

C1 获选**不是因为"最完整"**——完整性不是研究价值；是三个选项在四道门下结构性不对称的结果。

### 2.2 依据一：四道门逐项套用

| 门 | C1 单独 | C2 单独 | C1 × C2 |
|---|---|---|---|
| G1 新未知量 | ✅ 真实 execution 是否暴露可独立驻留/迁移的自然边界 | ✅ 有新未知 | ✅ 复合未知 |
| G2 不可推导 | ✅ 模拟结论不转移（RM-006 链第一级断层） | ✅ | ✅ |
| G3 双向结果 | ✅ 存在→产生有限 unit 对象空间；不存在→粒度管理缺自然支撑，均为决策相关信息 | ⚠️ 无载体定义时"对应物"判据是松的 | ⚠️ 复合结果归因困难 |
| G4 有限出口 | ✅ 对象空间有限：给定模型的对象分解图有限 + 预注册 workload 集内可判定 | ❌ **结构性失败**：机制必须有载体；unit 空间未定义时观测边界欠定，补定义只能偷偷引入 C1 假设 | ❌ 乘积空间最大；在 C1 未答前捆绑未问前提 |

### 2.3 依据二：RM-006 依赖序

```text
abstract mechanism → runtime representation → runtime-observable state
                                          → controllable mechanism → measurable effect
```

机制是"可观测状态"的性质，**必须有载体**。C1 问链上第一层未知（runtime 暴露什么对象）；C2 问第三层以后（机制是否可控可观测）。跳过 C1 直接问 C2 = 在载体未知条件下问机制——即 C2 单独在 G4 失败的结构根源：**C2 不是独立问题，是欠定问题**。

## 3. Dormant branch 处理

### 3.1 C2 → `DORMANT`

不是被否决，是**当前缺少独立定义域**。合法重入路径：

1. **顺序分支**：C1 出答案后，在发现的 unit 对象空间上重新提出机制问题；
2. **并行分支**：若未来能独立论证某条 C2 问题不依赖 C1 的答案，可另立 RQ。

重入裁定发生在第③/⑧步或未来开门动作，不在本文预设。

### 3.2 C1 × C2 → `DORMANT / DOWNSTREAM COMBINATION`

合法研究方向，**非否决**。它依赖 C1 未知量解决后的**新定义**——C1 的结果可能改变 C2 的问题空间。按 RM-001 研究树登记为分叉，不按线性任务列表处理。

## 4. C1 研究问题候选：正式问句

**正式问句**：

> 在预注册的模型与 workload 边界内，真实 Swift/MLX execution 的访问与驻留相关行为，**是否暴露出**具有独立 residency / migration 语义的 **Model Unit 边界**？

措辞精度说明：

1. 简称 "C1 = Model Unit 存在性" 仅作内部指代；正式表述**不得**写成"自然 unit 存在"——存在性未知必须保留在问句形态中；
2. "是否暴露出……边界"保证两种读数（暴露 / 未暴露）都是问句的合法答案；
3. 括号内边界（哪些模型、哪些 workload、哪些观测通道）属第⑤⑥步定义域，本文**不预填**。

双向出口的方向价值（登记，非判据）：

- **暴露**：产生有限的 unit 对象空间，供后续机制问题（C2 重入路径 a）与架构分层/分片讨论（RM-002，思想层候选）使用；
- **未暴露**：真实 runtime 的粒度管理缺自然支撑，policy 级机制只能在约定（非自然）边界上运作——研究树登记重要边界信息，属合法研究出口（RM-001 死枝登记）。

## 5. 明确未做（状态纪律）

| 项 | 归属 |
|---|---|
| estimand | 第④步 |
| existence criterion | 第⑤步 |
| insufficiency criterion | 第⑥步 |
| discriminating power | 第⑦步 |
| worth measuring | 第⑧步 |
| Path / Harness / Experiment | 第⑨步 |
| **RQ ID 分配** | **整条 RQ 定义完成后——Q2.1 裁定 ≠ RQ ID 分配完成** |

## 6. 门位快照（与 RESEARCH_STATE.md 同步修订）

```text
GATE Definition/Opening        OPEN — STEP ② 进行中（Q2.1 已裁定）
Q2.1 最小研究对象              C1 SELECTED AS MINIMAL OBJECT（双方裁定）
C2                             DORMANT
C1 × C2                        DORMANT / DOWNSTREAM COMBINATION
STEP ② 剩余                    本文档外审；C1 问句细化
STEP ③–⑨                       NOT STARTED
RQ-F-01                        NOT DEFINED（不变）
FROZEN 资产 / DATA COLLECTION  不变
```
