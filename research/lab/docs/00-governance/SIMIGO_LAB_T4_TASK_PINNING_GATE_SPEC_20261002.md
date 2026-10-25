# Gate Spec — T4 Task Pinning Gate（钉定要求；具体任务包待批后冻结）

Date: 2026-10-02  
Status: `GATE OPENED（钉定要求已登记；具体任务包待 human 提供/批准）`  
前置：T4 Experimental Design Gate = SPEC CONFIRMED / PASS
（`cd17b16`，零修改封存）  
层级不变：Spec PASS ✓ → **Task Pinning（本 Gate）** → Experiment
Execution（NOT AUTHORIZED）→ T4 = BLOCKED

## 1. 目的

把已确认的预注册设计（T4 Experimental Design Spec）落成**一份
冻结的任务钉定包（Task Pinning Package）**——执行前把全部实验
自由度封死。核心动作（human 逐字要求）：

> **把 T-3 non-derivable facts 变成一份实验前冻结的具体事实
> 清单**，并能够回答：为什么 cold-start executor 不可能仅凭
> B 指令、当前环境和自身通用能力推出这些事实？

## 2. 钉定包交付物（七件，缺一即不予冻结）

```text
P-1  T-3 具体事实清单（实验前冻结）：
     每条事实 = 内容逐字 + 来源（仅存在于 A 沉淀）+
     non-derivability 论证
P-2  A 的具体沉淀内容全文（逐字，含 Relation 若用）
P-3  A 的自然停止点记录规则（停止点如何认定与登记）
P-4  B 的逐字指令（C-E/C-N 两条件同文，零历史词汇自检）
P-5  预期可观察消费证据清单（哪些 retrieve 应发生在哪些
     使用之前——AC-2 的预登记对照表）
P-6  客观完成判据 + 事实清单映射（T-4 完成标准 ↔ P-1 逐条）
P-7  C-E / C-N 唯一差异声明（store 有无沉淀，其余逐字节同）
```

## 3. T-3 non-derivability 论证标准（本 Gate 最严项）

一条事实计入 P-1，当且仅当：

```text
N-1  来源闭包：事实内容 ⊄（B 指令 ∪ 声明输入 ∪ 工作区 ∪
     执行者通用能力可推闭包）
N-2  推导闭包审计：钉定时显式列出「B 指令+输入+通用能力」
     可推出的闭包集合，证明该事实不在其中
N-3  后验兜底（预注册）：C-N 实跑若产出 P-1 事实 ⇒ 该事实
     T-3 不成立 ⇒ 强命题自动降级弱命题（S-6 预注册衔接，
     非事后惩罚）
```

## 4. 冻结纪律

1. 钉定包七件齐备 + human 批准 ⇒ **hash 封存**（Task Pinning
   PASS）；此后任何改动 = S-7/F6 整轮作废
2. 执行授权 ≠ 本 Gate 产物——钉定冻结后**另行**申请
3. C-A 是否启用 = 钉定包内一并声明（可裁不用）

## 5. 裁定面

具体任务候选由 human 提供，或指定记录者按 T-1…T-6 + 本 Spec
起草钉定包草案再报批。**本 Spec 不钉任何具体任务。**

## 6. Pass / Fail

- **PASS（Task Pinning）** = 七件齐备 + N-1/N-2 论证成立 +
  human 批准冻结（hash 封存）
- **FAIL/退回** = 任一缺失 / N-2 论证不成立 / 命题强度与
  T-3 现实不匹配 ⇒ 退回修改，不得带病冻结
