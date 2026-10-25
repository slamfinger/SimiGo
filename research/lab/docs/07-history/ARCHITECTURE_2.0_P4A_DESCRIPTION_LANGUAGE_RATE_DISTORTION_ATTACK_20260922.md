# Architecture 2.0 P4-A — Description Language / Rate-Distortion Attack

Date: 2026-09-22
Status: STEP① conceptual attack / not an RQ / no experiment authorization

## 1. Candidate refinement

P4-A 当前将“低复杂度”候选进一步收缩为：在一套预先固定、独立于被测架构的 Runtime-side description language / schema / DSL 下，用码长（rate）描述 State representation，并以 Runtime resource-decision loss 作为 distortion，形成 task-relative 的 rate-distortion 候选。

关键纪律：description language 必须先于观察任何架构-specific projection 而固定，否则语言本身可能被 projection 反向优化，形成循环论证。

## 2. Rate-distortion 形式

概念结构：

fixed description language L → architecture-specific State → encoder → shared semantic representation → code length (rate) ↔ decision loss (distortion) → Runtime decision

当前并不注册具体 rate、distortion、阈值、预算或实验；这些仍属于 STEP④–⑨。

## 3. Description Language Attack

“固定语言”本身不能自动保证客观复杂度。至少存在以下风险：

- opaque primitive 可把复杂度藏进 decoder / external semantics；
- language expressivity 不同会改变同一 State 的码长；
- encoder 可能利用 architecture-specific prior，从而获得不公平的 rate advantage；
- 更短的 code 可能只是把语义搬进 language，而非真正压缩 decision-relevant information。

因此下一关键问题不是“字段多少”，而是：**rate 到底应计算 representation 的码长，还是连同解释/解码该 representation 所需的语义成本一起计算？**

## 4. Regime dependency

Projection 的成本具有不同频率结构：

- architecture adaptation cost：runtime development-side，近似 O(A)；
- instrumentation / inference / translation cost：runtime decision-side，近似 O(D)。

因此 projection utility 没有无条件答案，而依赖 A:D deployment regime。architecture 少、decision volume 高的场景可能偏向专用 fast path；architecture 多、频繁切换的场景可能更能体现 shared projection 的价值。

由此，未来 STEP② scope 应显式记录适用的 architecture population / decision regime，而不能假设普适价值。

## 5. B 结果应以边界为发现

若最终出现局部成立（B），核心结果不应只是“B 成立”，而应识别 projection utility 的 applicability boundary：task × architecture family × workload × resource regime。

边界本身可以成为 Architecture 2.0 的信息资产：它揭示共同语义投影在哪些架构差异下保持决策信息、在哪些差异下必须扩展或失效。

因此未来设计若获授权，应主动寻找边界，而非只选择最容易成立的架构/任务组合。

## 6. Current conceptual candidate

当前仍不主张 Execution State 是新的基础计算对象。更稳妥的候选是：

> 在固定 Runtime-side description language 下，是否存在跨架构、有限码长、具有足够 Runtime decision information 的 State representation；其价值取决于 decision distortion、description/observation cost 与 deployment regime。

## 7. Next falsification gate

下一刀固定为 **Description Language Attack**：

1. 固定语言是否真的独立于被测 architecture 与 projection；
2. code length 是否把复杂度藏进 decoder / ontology / external knowledge；
3. architecture-specific prior 是否允许 encoder “作弊”；
4. rate 降低是否真正意味着 decision-relevant information compression，而非语义搬运。

若该攻击不能通过，Rate-Distortion 框架退回；若能通过，才进入后续更具体的 STEP① 收缩。

## 8. Governance boundary

本记录不创建新的 RQ，不授权 harness、implementation、data collection 或 performance measurement。P4-A 仍处于 STEP① WORKING DEFINITION / 审查中。
