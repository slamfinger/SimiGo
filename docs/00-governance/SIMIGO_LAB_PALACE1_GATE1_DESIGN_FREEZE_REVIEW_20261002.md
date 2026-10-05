# PALACE-1 Gate① Design Freeze Review — HUMAN RULING REGISTERED

日期：2026-10-02  
对象：`SIMIGO_LAB_PALACE1_GATE1_CREATE_IDENTITY_RESERVATION_DESIGN_20261002.md`（`489bd05`）  
Verdict：**`PASS — DESIGN FROZEN / EXECUTION NOT AUTHORIZED`**  
Registration authority：explicit human freeze review（本会话裁定逐字登记）  
Review basis 说明（human 原文立场）：审查以会话内 §1–§11 对照内容为
依据；human 不把未直接读取的正文当作已验证事实

## 1. Gate 项审查结果（human 裁定表，逐字登记）

| Gate 项 | 结论 |
|---|---|
| 单一 Research Question | **PASS** |
| EF-9 baseline 继承边界 | **PASS** |
| Observation / Expected 预登记 | **PASS** |
| Positive / Negative Evidence 对称性 | **PASS** |
| Confounder 控制 | **PASS** |
| Stop / Closure Revision | **PASS** |
| Non-goals | **PASS** |
| Evidence Grade | **PASS** |
| O-4 对照格 | **PASS，且很关键** |
| O-3 P-C2 | **PASS，但必须 fail-open-to-trace，而非判为负证据** |
| O-5 P-C4 | **PASS** |
| 执行授权 | **NOT GRANTED BY THIS REVIEW** |

## 2. 三项关键裁定（执行判读覆盖，效力高于草案原文分支规则）

### R-1 O-4 恒为 control 格

```text
storageKey 寻址跨重启仍存在
        ≠
identity reservation 跨重启仍被保留
```

O-4 成立只证明已有寻址连续性，不得替 EF-9 提供 reservation 证据。
（与设计 §4/§5 P-C3 一致，本裁定钉死其 control 地位——不是
「顺便测一下」。）

### R-2 P-C2 = fail-open-to-trace（修正草案判读的执行语义）

若 O-3 意外发现跨重启重复检测，正确动作不是记录「反例/负证据」，而是：

```text
P-C2 偏离
   ↓
暂停判读
   ↓
追溯隐藏机制 / 已登记机制
   ↓
重新确定 observation boundary
```

理由（human 原文语义）：否则极易把「我们不知道已有机制」误判成
「没有机制」。设计文档正文按 human 裁定不修改；本裁定作为执行期
判读覆盖生效。

### R-3 Positive Evidence 第三条件为非法跳跃闸门

条件 (c)「caller discipline 在崩溃窗口 / 多写者条件下不可替代」
专门阻断以下非法推理：

```text
发现 caller 自己容易重复
        ↓
所以 PALACE 需要 reservation     ← 被本条件阻断
```

## 3. 执行期结论措辞边界（预登记，效力及于结果判读）

即使 O-1…O-6 最终同时出现：

```text
跨重启可重复 identity
+ 没有检测
+ 存在 IC-3/IC-4 约束
+ caller discipline 无法覆盖崩溃/多写者窗口
```

结果首先只能形成：

> **在当前实验条件与既定契约下，durable identity reservation 是
> 支持 PALACE lifecycle identity continuity 的候选语义需求。**

不得立即写成：

> ~~「PALACE 必须有 identity allocator」~~

——后者把**语义需求**偷换成**实现机制**。机制设计（是否需要、何种
allocator）是后续独立 gate 的内容。

## 4. Frozen gate state

```text
PALACE1
└── Lifecycle Storage Opening（REGISTERED / ACTIVATED）
    └── Gate 1: create → durable identity reservation
        ├── Design       ✅ FROZEN（正文不再修改）
        ├── Review       ✅ PASS（本文登记）
        ├── Execution    🔒 NOT YET AUTHORIZED
        └── Next action  → explicit execution authorization
                          （独立状态转换；批准后才构建 §11 R0
                            harness 并执行 O-1…O-6）
```

本裁定不授权执行、不授权 harness 构建、不授权任何实现。
