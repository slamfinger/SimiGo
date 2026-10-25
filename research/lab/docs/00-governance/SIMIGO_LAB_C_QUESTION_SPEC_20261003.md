# Gate Spec — C：Execution State 为什么需要 Information Space（C-SPEC Definition 阶段件）

Date: 2026-10-03  
Status: `C-SPEC FROZEN / HUMAN RE-AUDIT PASS`  
前置：Phase 0 FROZEN / Phase 1 CLOSED / Phase 2 CLOSED /  
B-RB1 EXECUTED + PREREGISTERED READING PASS + EXTERNAL AUDIT PASS /  
B Track CLOSED  
授权范围：本件问题定义已冻结。C-Design 可开启为 DESIGN ONLY，
但尚未开始；C-Impl / C-Execute / Core 改动 / Palace schema /
数据库设计 = 全部未授权。

## 0. Gate 定位

B-RB1 已回答：

```text
在预登记四步结构中，
before Information + after Information + Relation
能否支持 cold-start boundary consumption？
```

答案 = PASS，但结论严格限定在该结构。

C Gate 上升一层，只问：

```text
Execution State 跨生命周期继续工作时，
Information Space 承担了什么不可替代角色？
```

本件不扩展 B Track，也不预设 C 结果。

## 1. 冻结研究问题

```text
C-Q1

当 Execution State 被终止 / 重启 / 转移后，
哪些东西必须存在于 Information Space 中，
Execution State 才能继续工作？
```

`C-Q1` 保留为较宽的研究问题。本轮 C 实验只取其中可对照的
lifecycle slice：

```text
termination → restart → cold start
```

`transfer` 不在本轮实验范围内，也不能从本轮结果外推；它是
未来独立生命周期条件。

`Execution State` 在此指可终止、重启或转移的执行生命周期状态；
本件不修改既有 Execution State contract，也不引入新的执行态语义。

## 2. 最小对照组（仅边界，非实现设计）

同一最小任务、同一外部变化、同一 lifecycle slice、同一
cold-start 要求，在三个边界下对照：

```text
C-A
  只有 Execution State
  没有持久 Information Space

C-B
  Execution State
  + 持久 Information
  - Relation

C-C
  Execution State
  + 持久 Information
  + Relation
```

公共任务骨架：

```text
S0
  ↓
外部真实变化
  ↓
进程终止
  ↓
新进程 cold start
  ↓
要求继续完成任务
```

本轮 lifecycle scope：

```text
termination → restart → cold start
```

```text
transfer = OUT OF SCOPE
```

观察面只登记：

```text
1. 能否恢复？
2. 恢复到什么程度？
3. 缺失的承载物是什么？
```

具体任务材料、持久化形态、schema、进程注入方式和审计判据
归 C-Design；本件不钉定。

## 3. 允许得出的结论范围

允许：

```text
在钉定的任务与执行环境中，
比较 C-A / C-B / C-C 的恢复程度与缺失语义；
支持或反驳该实验域内的必要性命题；
识别 Information 与 Relation 分别承载的最小角色。
```

禁止扩大为：

```text
所有 Agent 都必须如此；
所有 Memory System 都必须如此；
PALACE 的最终 schema 已被证明；
Information Space 是普遍必然系统；
ExecutionCore 能检测 Physical 变化；
B-RB1 的结论被放大。
```

B-RB1 的物理变化证据边界继续有效：变化由外部编排实施并留痕，
ExecutionCore 只消费已观察材料。

## 4. 负空间（C-Spec 阶段零出现）

```text
C-Design / C-Impl / C-Execute
修改 InformationCore / RelationCore / ExecutionCore 语义
新增 InformationChange / Watcher / Observation 等 Core 类型
Palace schema、数据库设计、文件索引
chat history / tool registry / Remote API / Office Backend
taxonomy / activation / ranking / retrieval 策略
把应用集成清单塞入 C Gate
预设 C-A / C-B / C-C 的结果
```

以上可作为后续应用层或更晚 Gate 的候选，不进入本件。

## 5. Gate 推进

```text
C-SPEC（本件）
  ↓ human audit + freeze
C-DESIGN（另行授权）
  ↓
C-IMPL（另行授权）
  ↓
C-EXECUTE（另行授权）
```

当前只请求冻结：C-Q1、三对照边界、结论范围。

## 6. Human Audit 结果

```text
H-1 = PASS WITH CONDITION
H-2 = PASS WITH CONDITION
H-3 = PASS WITH CONDITION
H-4 = FAIL AS CURRENTLY WORDED → revised to lifecycle slice
H-5 = PASS WITH CONDITION
H-6 = PASS

C-SPEC Human Audit = CONDITIONAL PASS / REVISE EXECUTED
C-SPEC Human Re-Audit = PASS
Freeze = EXECUTED
C-Design = OPEN / READY / NOT STARTED
```

除 lifecycle scope 外，其余 audit rulings 登记为 C-Design 输入
约束；本件不新增 schema、操作定义或技术禁止清单。
