# Research Dependency Map

**Purpose:** 明确哪些研究依赖哪些前置问题/知识，防止关闭一个问题后自动推导另一个问题已被回答。

## 1. Current Architecture 2.0 dependency map

```
Model Architecture Features
        ↓
Computation
        ↓
Execution State
        ↓
State Characteristics
        ↓
Resource Behavior
        ↓
Loading / Residency / Layering / Working Set / Migration
        ↓
Runtime Architecture
```

这是一条当前研究方向链，不表示任何下游 RQ 已经注册或继承上游证据。

## 2. Historical dependency

```
Execution State (Track B)
        ↓
Residency / policy
        ↓
P3
        ↓
H-P1
        ↓
nodes-out
        ↓
Track E CLOSED
```

该链仅用于 provenance 与知识承接。

## 3. P4 dependency principle

P4 的逻辑关系是：

`Architecture feature → Computation dependency → Execution State property → Resource behavior`

不是：

`Architecture feature → Runtime unit`

因此 P4 不需要预设 Model Unit，也不需要假设所有模型拥有统一物理 State layout。

## 4. P4 Definition Gate

P4 必须独立经过：

`Research Object → RQ → Independence → Estimand → Existence → Negative → Discriminating Power → Information Value → Experiment`

Track B 的历史结论可以作为约束或先验背景，但不能转移为 P4 结果。

## 5. Independent branches

Track A、Track D、Track C 仍为独立未来/休眠分支；RQ-F-01 已退休；Boundary/Object/Identity 等概念线保留为历史资产。

## 6. Agent rule

当 Agent 发现一个“看起来已经被以前研究回答”的问题时，必须核对：

- 是否为同一个 RQ；
- 是否使用同一 estimand；
- 是否处于同一 observation domain；
- 是否有合法 provenance；
- 是否有 endpoint 明确授权。

否则只能作为相关历史证据处理。
