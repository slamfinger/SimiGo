# Gate Spec — T4 Cross-Task Replication Gate（A；仅边界登记，零任务设计）

Date: 2026-10-03  
Status: `A GATE OPEN / INITIAL BOUNDARY REGISTERED / 零任务设计零实验`  
前置：T4 = PASS / STRONG ATTRIBUTION (TASK-DOMAIN BOUNDED) / CLOSED
（`72eb6a7` 链）；B（Execution 层）= DEFERRED

## 1. 唯一研究问题（human 逐字）

> 在保持 T4 已验证的 Information boundary、cold-start、C-E/C-N
> 归因框架不变的前提下，对一个**结构独立的第二 continuation
> task**进行复现，能否再次获得与 T4 同方向的「Information
> boundary 对 continuation 的必要性」证据？

## 2. Gate 边界（human 裁定表，逐字）

| 项目 | 本 Gate 状态 |
|---|---|
| 第二任务 | **待设计** |
| 任务结构 | **待设计** |
| T-3 非推导事实 | **待设计** |
| 混淆变量控制 | **待设计** |
| C-E / C-N | **继承 T4 框架** |
| cold-start | **继承 T4 框架** |
| InformationCore | **冻结，不修改** |
| RelationCore | **冻结，不修改** |
| SimiGo Integration | **冻结，不修改** |
| T4 原结论 | **不得修改** |
| 实验执行 | **未授权** |

## 3. 硬约束（human 逐字六条）

1. **不得把第二任务设计成 T4 的换皮版本**——必须结构独立，
   否则不能提供有效的 cross-task replication
2. **不得反向修改 T4**——A 不复现时，结论表达为复制结果及其
   边界，不回溯修改已 CLOSED 的 T4
3. **不得提前规定第二任务必须成功**——结果可为 PASS、未复现、
   或因设计/执行问题 INCONCLUSIVE
4. **T-3 必须重新审查**——不机械复制 T4 具体事实，只继承
   「T-3 作为强/弱命题切换器」的方法原则
5. **混淆变量必须在任务设计阶段显式登记**——不允许实验后才
   补充解释
6. **不得引入新的记忆机制**——InformationCore 仍是唯一允许的
   外部 memory boundary；不得加入 palace、预置历史、workspace
   archaeology、hidden cache 等渠道

## 4. 阶段链与开门纪律（human 定稿）

```text
A-Spec（本件）
  ↓
Task Selection / Design      ← 子 Gate，须明确开门
  ↓
T-3 + Confound Audit         ← 子 Gate，须明确开门
  ↓
Task Pinning / Hash Freeze   ← 子 Gate，须明确开门
  ↓
Execution Authorization      ← 子 Gate，须明确开门
  ↓
Replication Result
```

**Task Selection / T-3 / Confound Design 不由当前记录状态自动
授权；必须在对应阶段明确开门。**

## 5. 当前状态

```text
T4 Cross-Task Replication Gate = OPEN
A-Spec      = OPEN / INITIAL BOUNDARY REGISTERED（本件）
A-Task      = NOT DESIGNED
A-T-3       = NOT DESIGNED
A-Confounds = NOT DESIGNED
A-Pinning   = NOT OPEN
A-Execution = NOT AUTHORIZED
```

## 6. 下一步

**任务选择/设计子 Gate**（由 human 开门）——不是直接进入实验。
记录者在子 Gate 开门前零任务设计动作。
