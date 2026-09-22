# Architecture 2.0 — P4-A STEP⑤ Existence Criterion Candidate

**Date:** 2026-09-22  
**Status:** STEP⑤ OPEN / EC5 CANDIDATE UNDER ATTACK  
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 第一刀

STEP⑤ 先把两个对象分开：

- **弱存在**：`P_AS(X;S_det) != emptyset`。这只说明策略集合非空，可由 `L0` 或一个 trivial encoder 满足，不构成 frontier 存在。
- **非平凡已实现存在**：可达集合中至少有两个不被支配的策略点，形成严格的 Rate–Decision-Loss 反向变化。

因此，数学下确界即使有意义，也不能自动兑换成 frontier 存在。STEP⑤ 关心的是后者。

## 2. Candidate EC5：严格双点见证

固定一个 frame：

```text
(L, Rate convention, D=(A,C,sigma_D,Pi_W), S_det)
```

并固定一个 scope：

```text
(X, semantic 或 deployment-economic, theta_tilde)
```

deployment-economic scope 中按 STEP④ 显式携带 `N` 或 `mu_D`。不把 semantic 与 deployment-economic 的见证合并。

定义：

```text
r_X(P)     = Rate_L,X(P)
l_X(P)     = Delta_X(P; theta_tilde)
P <= Q     iff r_X(P) <= r_X(Q) and l_X(P) <= l_X(Q)
P <  Q     iff P <= Q and (r_X(P) < r_X(Q) or l_X(P) < l_X(Q))
```

`<` 表示 strict Pareto domination。一个策略属于已实现 frontier，当且仅当可达策略族中没有其他策略 strict-dominate 它。

**EC5**：

> 存在 `P0,P1 in P_AS(X;S_det)`，二者的 rate/loss 均为有限 admissible 值，且都不可被 `P_AS(X;S_det)` 中任何策略 strict-dominate，并满足
>
> ```text
> r_X(P0) < r_X(P1)
> l_X(P1) < l_X(P0)
> ```
>
> 则称该 frame/scope 下存在一个 **nontrivial realized Achievable Static Frontier phenomenon**。

这个条件刻意要求两个 frontier 点。一个点只能证明可达或最优，不能证明 tradeoff 结构。一对被支配点也只能说明某些策略排序，不能证明 frontier。

## 3. 为什么这是当前最小判据

EC5 只使用 STEP④ 冻结的坐标：

- 冻结 `L` 与 Rate counting convention；
- 冻结 `D` 与 `sigma_D`；
- 冻结 `S_det`；
- 冻结 scope 中的 workload regime 与 semantic/deployment 分轨；
- 目标层 loss/rate 函数。

它不使用 estimator、finite-sample evidence、projection selection、Runtime adoption、跨架构一致性或 competing projection 的区分结果。

`Eval=(budget, estimator, sampling)` 仍属于后续估计设计。EC5 是 target-level existence certificate，不是 empirical acceptance test。若未来授权实验，也必须另立观察规则，不能把 EC5 误写成统计检验。

## 4. Certificate 形式

一个合法 EC5 见证至少要记录：

1. frame/scope 标识；
2. `P0,P1` 在冻结 `S_det` 中的构造身份；
3. `r_X(P0) < r_X(P1)`；
4. `l_X(P1) < l_X(P0)`；
5. 两者均不可被任何 `P in P_AS(X;S_det)` strict-dominate；
6. 该结论只声明在当前 `X`、当前 workload regime、当前 semantic/deployment scope 内成立。

不允许在见证后更换 Rate convention、成本族、`sigma_D`、`S_det` 或 workload regime。更换即新 frame。

## 5. 防偷渡检查

| 偷渡形式 | EC5 处理 |
|---|---|
| `P_AS` 非空 | 不够；必须有两个 strict frontier 点 |
| 只有 `L0` 或单一 endpoint | 不够；无反向 strict tradeoff |
| infimum sequence / ideal limit | 不够；两个见证必须实际属于 `S_det` |
| 一对单调点但其中一个被支配 | 不够；两个点都必须在 frontier 上 |
| semantic 见证升级为 deployment-economic | 不允许；scope 分别见证 |
| 单架构存在升级为跨架构存在 | 不允许；EC5 本身 frame/scope-indexed |
| projection 能区分 | 不涉及；属 STEP⑦ |
| 区分结果值得成本 | 不涉及；属 STEP⑧ |
| Track B lifecycle 证据 | 不得作为 EC5 见证 |

## 6. EC5 不证明什么

EC5 即使通过，也不证明：

- 真实系统一定能被 finite data 识别；
- 两个 witness 的差异具有实践重要性；
- 该 frontier 能区分 competing projections；
- 它对 Runtime 决策有价值；
- 其他架构、workload regime 或 semantic/deployment scope 也存在；
- STEP⑥ negative / insufficiency criterion 会通过。

严格但极小的差异在 EC5 下可以通过。这只是存在资格；是否“不足”或“有价值”分别留给 STEP⑥ 与 STEP⑧。

## 7. 当前状态

EC5 是候选判据，不是 STEP⑤ PASS。下一步是对它做反向攻击，重点检查：

1. 是否仍能让某个 trivial family 伪装通过；
2. “不可被 strict-dominate”在无限或非闭可达族中是否引入循环或不可审计性；
3. 严格双点条件是否漏掉必要的 attainability boundary；
4. 语义 scope 与 deployment-economic scope 是否需要不同的 second-point condition；
5. 是否有任何措辞提前消费 STEP⑥–⑧。

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
