# Track E(命名待定)Residency Policy 开题 v2(2026-09-21)

**状态**:开题 v2(按审计收紧修订;simulator v0 已开写,数字未出)。
**修订记录**:v1 → v2 三处收紧(审计)+ 一项升格——
① 四决策统一为**单一 Residency Decision**(两方向 action + 访问外部
节点的二次决策),不做四动作 MDP;② LRU/Pressure 明确降为
**baseline/reference**,不是"候选策略答案";③ 0.72 从常量改为**默认
参数 `C_rehydrate=0.72`,必须做 sensitivity sweep**;
④ resident memory cost 升格为 **P0 prerequisite / missing cost
dimension**。
**命名**:Track E 待真源定夺。v1 的 epistemic boundary 保留:

> **M4 证明的是"外化/召回的 cost 可接受性边界",不证明"应该什么时候
> 外化"。** policy 结论必然依赖 workload 假设,一律带假设标注。

## 研究问题与决策结构

阶段问题从"能不能/多少"转向"什么时候"。决策统一为:

```
Residency Decision(核心 action)
        │
   ┌────┴─────┐
   ↓          ↓
RESIDENT   EXTERNALIZE
                │
     workload 访问外部节点时(二次决策)
                │
        ┌───────┴──────┐
        ↓              ↓
    REHYDRATE        SKIP
```

v0 简化(如实标注):所有 access 必须被服务,故 **SKIP 未建模**——
访问外部节点 = 强制 REHYDRATE 并支付 C_rehydrate。SKIP(跳过/降级
执行)属后续版本。

## 假设(先给可被杀死的形态,不预设 H-P1)

- **H-P0**:residency decisions may be determined by memory pressure +
  reuse information alone(通用 eviction 信号已足够)。
- **H-P1**:execution structure(树依赖/未来复用/residency cost/
  state size)adds decision-relevant information beyond generic
  eviction signals。

**若 v0 结果为 LRU ≈ Pressure ≈ anything**:不是失败——结论是该
workload domain 内 residency policy 不需要 execution-aware
intelligence,H-P1 被杀,如实入档。差异出现才有理由进入
Execution-aware Policy(M3-C 的树结果才开始被 policy 消费)。

## 成本模型(v0)

- `C_rehydrate`:**参数,默认 0.72 token-equivalent**(M4 终判精确值;
  sweep ∈ {0.25, 0.5, 0.72, 1, 2, 4, 8})。M4 拆分参考:C_ext ≈
  0.69(27.7–33.4 ms)、C_rehy ≈ 0.03(1.2–1.5 ms)。
- `C_externalize`:参数,默认 0.69。
- **`C_resident` = P0 PREREQUISITE(missing cost dimension)**:
  policy 基本不等式 = Keep-Resident cost vs Externalize + Future
  Rehydrate cost;目前只有右边一半。v0 中 C_resident = 0(未建模,
  显式标注)——**total_policy_cost 因此不含驻留持有成本,全部
  v0 结论限定在 boundary-cost 视角**。P0 补课 = resident bytes 计价
  (M4 未测),完成后不等式才闭合。

## Baselines / Reference / Target(不混淆)

| 角色 | 策略 |
|---|---|
| Baseline | Always Resident(预算不足时记 violation) |
| Baseline | Pressure Threshold(用量 ≥ 90% 预算即按 LRU 序主动外化) |
| Baseline | LRU(被动:准入需空间时外化最久未用) |
| Reference bound | Oracle(预知 next_access,外化最远者) |
| Experiment target | New policy(P3 才登场;v0 不预设形态) |

研究问题不是"我们比 LRU 好",而是:**仅用 recency 是否足够?加入
residency cost / expected reuse 后,决策空间是否出现可观测差异?**

## Simulator v0 最小模型(无 GPU / 无 SimiGo runtime)

```
Node { id, size, resident, last_access, next_access }
Access trace:t0 A, t1 B, …
State:ResidentSet / ExternalizedSet / MemoryUsed
Input:nodes, sizes, trace, memory budget, C_ext, C_rehy, policy
```

指标(A 硬约束优先):
- **A. Memory feasibility**:peak_resident_memory;budget_violations
- **B. Boundary events**:externalize_count;rehydrate_count;
  rehydrate_cost_total
- **C. total_policy_cost**(v0 = C_ext×n_ext + C_rehy×n_rehy;
  不含 C_resident,不含 stall model——后续版本)
- **D. oracle regret**:**描述性指标,不是胜负分**(纪律沿用)

Sensitivity 三重 sweep:budget(20%–100%)× reuse distance
(short/medium/long/very-long)× C_rehydrate(0.25–8)。目标输出不是
"谁赢了",而是:**residency decision 在什么参数区域开始产生可观测
差异**。

## 阶段阶梯(v2 修订:消除 P0 命名冲突)

```
P0 — Cost model closure(C_resident 计价;policy 不等式左边补齐)
P1 — Baseline / reference sanity(LRU/Pressure 健全性;Oracle 须过
     健全性检查 ≤ 一切 baseline,含模型假设检:equal-size?weighted?)
P2 — Sensitivity(budget / locality / C_rehydrate)
P3 — New policy discrimination(可实现 future-reuse 策略 vs LRU;
     H-P0 正式检验;树依赖增量 = H-P1 强形式)
P4 — Live validation(仅当模拟差异 > 噪声;正确性门沿用 M3 主门)
```

**simulator v0 的定位 = P1/P2 exploratory probe**(P0 与 P3 之前的
探索性证据),不占用 P0 命名。v0 已完成:P1(oracle 健全性检查通过)、
P2(三重 sweep);P3 待 new policy 设计。

## 边界

- 本开题不构成架构结论;H-P0/H-P1 之外不引入第三假设;
- v0 数字 = 合成 workload + boundary-cost 视角(C_resident=0),
  不外推真实 runtime;
- Track E 正式命名待真源定夺。
