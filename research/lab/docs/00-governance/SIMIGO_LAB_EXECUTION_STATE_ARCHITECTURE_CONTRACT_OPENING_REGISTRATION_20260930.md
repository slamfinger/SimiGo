# Execution State Architecture Contract Opening Registration — 2026-09-30

## Registration status

```text
ARCHITECTURE_CONTRACT_OPENING = PASS / REGISTERED / ACTIVATED
Contract synthesis / audit    = ACTIVE / NOT YET EXECUTED
Current blocker               = none
```

## Source decision

Participant opening draft:
`docs/00-governance/SIMIGO_LAB_EXECUTION_STATE_ARCHITECTURE_CONTRACT_OPENING_DRAFT_20260930.md`
commit: `0573ec3`

External review:
`docs/00-governance/SIMIGO_LAB_EXECUTION_STATE_ARCHITECTURE_CONTRACT_OPENING_DRAFT_EXTERNAL_REVIEW_20260930.md`
verdict: `PASS / ACTIVATION_REQUIRED`
commit: `dcfe9e0`

Human registration decision:

```text
登记 Architecture Contract opening PASS，并激活 contract synthesis。
```

## Registered research question

在已登记的 E1+E3+B1 seam、Execution Semantic Snapshot 边界以及 PALACE-1
durable-state boundary 基础上，定义独立于 MLX、具体 backend、model format
和 physical representation 的 Execution State Architecture Contract，使
「同一 Execution State」的语义不依赖具体实现，并为后续 PALACE durable-state
与 Backend Independence 提供唯一上游语义基准。

## Registered synthesis disciplines

```text
1. synthesis ≠ re-litigation — 不重新证明已经登记的事实；每条契约陈述
   可追溯登记工件
2. open points 不静默解决 — 冲突、G-7、G-10、Phase B 条件等保持开放，
   只能经各自 gate 解决
3. v1.0 是新的上游语义参照 — 登记后代码/登记行为与 Contract 的双向漂移
   均进入 contract-change 检测（S2 扩展 C-13 类信号）
```

## Registered scope

AC-1 Semantic Core（route Q2/Q3）/ AC-2 Identity·Continuity same-vs-new
State 判据（route Q1）/ AC-3 Representation Boundary 四态结果（route
Q4/Q5/Q6）/ AC-4 Backend Independence 准入标准 → 产出 Execution State
Architecture Contract v1.0 draft（版本化；修订只能经 contract gate）。

## Authorization boundary

```text
❌ 生产实现 / 代码重设计
❌ storage / persistence format / API / protocol 选择
❌ 第二个 backend
❌ 修改任何已登记语义（冲突 → open point）
❌ 新增测试（re-run 须 hash 级绑定）
❌ PALACE 消费（接口须显式 bridging registration）
❌ performance / universal portability claim
```

## Next gate step

synthesis 完成并提交后 → external review → registration（契约 v1.0 成为
登记上游锚点）。

## Inherited constraints

Phase B 六条件、Phase C 四 strengthening、M-1…M-5、G-1…G-10、Round 1 四
strengthening、seam stability standing 纪律（S2/S6 + 触发点）、evidence-
source-state 纪律——全部继承，无一因本登记关闭。
