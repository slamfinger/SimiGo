# Architecture 2.0 — P4-A STEP⑤ Existence Criterion 开门

**Date:** 2026-09-22  
**Status:** STEP⑤ OPEN / EXISTENCE CRITERION  
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. STEP⑤ 研究问题

STEP⑤ 不再讨论 estimand 如何定义。当前 estimand 已由 STEP④ 固定为 frame-indexed Achievable Static Frontier。

本阶段只问：

> **什么最小、可证伪、非循环的观察条件，才足以使 Achievable Static Frontier 在给定 frame 与 scope 内获得“存在”资格？**

存在资格不是价值判断，不等于优越性、低码率、跨架构泛化或 Runtime usefulness。

## 2. 继承的冻结资产

STEP⑤ 继承 STEP④ 已闭合的：

- Description Language L 与 Rate counting convention；
- Decision Problem Family D=(A,C,sigma_D,Pi_W)；
- sigma_D 的联合因子化 / 最小充分见证；
- S_det 确定性静态派生策略族；
- workload parameterization 与 oracle normalization；
- semantic / deployment-economic dual-track；
- 架构公共 rule slots 与 X input slot separation；
- Target、Estimator、Observed frontier 的严格区分。

STEP⑤ 不得为了定义 existence criterion 而重新修改上述 frame。

## 3. 第一轮必须攻击的偷渡

### 3.1 P_AS 非空 ≠ 科学意义上的 existence

若存在任意一个可构造 encoder，则 P_AS 非空。但 L₀ / 完整 state / 单一 trivial encoder 可以平凡产生非空集合。

因此 existence criterion 不能退化为“集合非空”。

### 3.2 Endpoint ≠ frontier structure

只有 L₀ endpoint 或另一端的极限点，并不足以证明存在具有研究意义的 Rate–Decision-Loss tradeoff 结构。

是否需要至少两个以上可区分的可达 rate/loss 点、局部非平凡性或其他条件，必须作为本阶段的候选而非预设结论。

### 3.3 Mathematical infimum ≠ realizable encoder

STEP④ 使用的是 S_det 实际可达策略族，因此 existence criterion 必须围绕实际可构造对象，而不是依赖不可实现的数学 infimum。

### 3.4 Local observation ≠ cross-architecture existence

单架构、单 workload、单 resource regime 的 frontier 现象，只能证明该 scope 下的 existence。不能自动升级为跨架构共同存在。

### 3.5 Projection usefulness ≠ existence

“projection 能改善 Runtime 决策”属于 information value / cost 层，不应偷渡到 existence criterion。

### 3.6 Track B evidence ≠ P4-A existence evidence

Track B 已 CLOSED/FROZEN。其 fork / continue / reattach / discard 证据不得转移为 P4-A frontier existence 证据。

## 4. Governance boundary

STEP⑤ 当前只允许：

- 定义 existence criterion；
- 构造最低成本、纯概念的反例；
- 检查 criterion 是否被 trivial encoder、endpoint、infimum 或 scope 偷渡击穿。

当前仍无 Runtime implementation、research harness、profiling、data collection、performance measurement authorization。

如后续发现存在资格只能通过真实运行才能判断，必须先单独审查是否开启相应实验授权，不得由 STEP⑤ 自动获得。

## 5. 后续门

STEP⑤ 通过后，才进入 STEP⑥ Negative / Insufficiency Criterion。存在资格本身不证明该 frontier 足以区分 competing projections，也不证明其具有 information value。

**Current status:** STEP⑤ OPEN / EXISTENCE CRITERION IN PROGRESS / RQ ID NOT YET ASSIGNED / NO EXPERIMENT AUTHORIZATION
