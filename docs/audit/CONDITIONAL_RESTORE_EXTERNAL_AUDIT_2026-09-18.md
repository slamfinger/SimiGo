# Conditional Restore 外部代码审计登记 — 2026-09-18

## Scope

外部审计对 `main` @ `7ccd136`（rollforwardRisk 放宽 + live-extend 对照臂，
较上轮审计基线 `53c219b` 新增 2 commit / 4 文件）的复审意见登记。
**Runtime 代码未因本登记变更。**

## Executive conclusion

**当前 HEAD 通过：无新 P0；无代码级 P1；主要缺口为实验统计（非代码）。**

| 项目 | 判定 |
|---|---|
| Conditional Restore 主逻辑 | ✅ 稳定 |
| rollforwardRisk（`return !calls.isEmpty`） | ✅ 本次修正正确 |
| delta gate | ✅ 合理 |
| CJK 估算 | 🟡 数据积累阶段 |
| prefill staircase | ✅ 实测有效 |
| 2048 深档问题 | ✅ 已基本定位 |
| LIVE control | ✅ 已补齐 |
| restore residual overhead | 🟡 ~1.0–1.3× 信号，需补 n |
| 统计显著性 | 🟡 n=1，不下最终结论 |

## 审计认定的关键点

1. **risk 简化正确**：判定模型从「猜 tool_calls 形状」升级为
   「存在 tool_calls 即风险来源，交给 delta gate 做成本决策」；
   `22,094 tok/36.3s` 生产逃逸证据支撑放宽。
2. **未变成无脑 restore**：放宽的代价只是多一次便宜的 restore 判断，
   误触发 ~1–2s vs 漏报 36–490s 的成本结构成立。
3. **LIVE 对照臂闭环**：问题从「restore 是否有巨大惩罚」推进到
   「residual overhead ~1.0–1.3×」；深度税为 NativeMLX/模型执行固有
   （LIVE 自身 723→205 tok/s，3.5× 退化），非 SimiGo restore 问题。

## 审计标记的缺口与措辞纪律

- LIVE workload（每轮 +40k chars）与 restore benchmark 增量形态不同，
  `1.2×` 只能作**状态形态对照**，不得写成 universal restore overhead。
  稳妥表述：「当前受控 benchmark 显示，阶梯 prefill 修复后 derived 相对
  live 额外差距约 1.0–1.3×；此前 4–6× 主要来源已定位为深档 prefill
  chunk + swap，而非 Conditional Restore 本身。」
- 三臂实验均 n=1。

## 采纳的行动项（顺序）

1. **不再修改 `rollforwardRisk`**（防过拟合）；由 risk heuristic 向
   cost-based admission 演进，继续积累 deltaTokensEst/deltaTokensCJK、
   8192 gate 与实际 restore 成效数据。
2. **固定当前二进制**，重复 LIVE / 1024 / 2048 三臂实验补 n
   （审计最高优先动作）。
3. 期间穿插 **Execution Fork F0 探针**（只读、零行为变更，与跑分不冲突；
   见 `docs/experiments/EXECUTION_FORK_F0_PROBE_20260918.md`）。
4. 数据齐备后再决策：V1.5 停在 Conditional Restore，还是向
   Execution Fork 推进。

审计原文结论引用：「这轮最重要的成果不是 `return !calls.isEmpty`，而是
『生产分歧→风险模型→delta 门→阶梯修复→受控对照→LIVE 对照→residual
overhead』证据链闭合；现在该补统计，不该再改代码。」
