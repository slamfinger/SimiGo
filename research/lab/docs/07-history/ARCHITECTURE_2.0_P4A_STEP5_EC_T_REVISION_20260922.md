# Architecture 2.0 — P4-A STEP⑤ EC5 裁定与 EC_T 修订

**Date:** 2026-09-22  
**Status:** STEP⑤ OPEN / EC5 REJECTED / EC_T CANDIDATE  
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. EC5 裁定

前一版 EC5 不通过。

它成功排除了 `P_AS != emptyset`、单 endpoint、`L0` 和被支配双点，但仍把几个不同对象压在一起：

1. target-level existence；
2. finite observation certificate；
3. Pareto point set；
4. STEP④ 定义的 lower-envelope function；
5. infimum 是否被实际策略达到。

因此，“存在两个不可被 strict-dominate 的策略”不是当前 estimand 的最小存在判据。无限策略族中的不可支配性是全称性质，不能由有限候选点直接证明；同时 Pareto 点集也不是 STEP④ 已经冻结的函数型对象。

EC5 中的“realized frontier”措辞一并撤回。是否有人达到 infimum 是 attainment / realization 问题，不是 STEP⑤ target-level existence 的必要条件。

## 2. 三层分离

STEP⑤ 必须固定以下三层：

### 2.1 Envelope object defined

给定 frame 与 scope，若 rate-budget 可行集非空且 loss codomain 允许取 infimum，则下包络对象定义：

```text
F_AS,X^(tau,theta)(R)
  = inf { Delta_X^tau(P; theta) :
          P in S_det, Rate_X(P) <= R }
```

其 domain 是实际可达 rate domain：

```text
R_X^(tau,theta)
  = { R : exists P in S_det,
          Rate_X(P) <= R }
```

这只是 STEP④ 对象在当前 scope 中 well-defined，不等于非平凡 frontier 现象。

### 2.2 Nontrivial target-level existence：EC_T

当前存在判据改为：

```text
EC_T(frame, X, theta, tau):
  exists Ra,Rb in R_X^(tau,theta)
  such that
    Ra < Rb,
    F_AS,X^(tau,theta)(Ra) < infinity,
    F_AS,X^(tau,theta)(Rb) < infinity,
    F_AS,X^(tau,theta)(Rb) < F_AS,X^(tau,theta)(Ra)
```

也就是说，在固定 frame/scope 中，增加可用 rate budget 能严格降低最优可达 decision loss。

EC_T 不要求存在某个策略等于 infimum，也不要求有限数据观察到下降。

### 2.3 Empirical existence evidence：EC_E

未来若授权实验，有限候选集或样本得到的只能是：

```text
hat F(Rb) < hat F(Ra)
```

它属于 empirical existence evidence，不是 EC_T 本身。该观察规则不得在 STEP⑤ 内预设。

## 3. 为什么 strict descent 不是偷渡结论

STEP④ 的 rate constraint 是 cumulative budget semantics：

```text
Ra <= Rb  =>  P_X(Ra) subseteq P_X(Rb)
```

因此更大的可行集不可能提高 infimum：

```text
F_AS,X(Rb) <= F_AS,X(Ra)
```

所以在这个 frame 中，函数型 frontier 只可能非增。若出现上升，说明 rate convention、scope 或 frame 已经被改变，而不是 frontier 出现了异常。

由此，非平凡性不预设“我们希望看到改善”。它只有一种数学形式：

```text
exists Ra < Rb: F(Rb) < F(Ra)
```

否则下包络在可达 domain 上是平坦的。平坦下包络可以继续作为 negative / boundary finding，但不能通过 EC_T。

## 4. 离散、稀疏、分段常数与局部 tradeoff

EC_T 不要求 continuum，也不要求密集 frontier。

以下情况均可合法进入判据：

- 可达 rate domain 离散；
- frontier 分段常数；
- 严格下降只发生在一个局部区间；
- Pareto 可达点很少；
- 下降幅度极小但仍有限且严格。

这些性质是否“足够”，分别属于 STEP⑥ negative / insufficiency、STEP⑦ discriminating power 或 STEP⑧ information value，不由 EC_T 判定。

如果把 STEP④ 的函数型 estimand 改成非函数型 frontier、randomized policy frontier或多目标 Pareto poset，那不是 STEP⑤ 修复，而是新 frame，需要重新过门。

## 5. semantic 与 deployment-economic 分离

EC_T 必须逐 track 实例化：

```text
EC_T^sem(frame, X, theta)
```

只判定 semantic lower-envelope 是否存在严格下降。

```text
EC_T^dep(frame, X, theta, N)
```

或更一般：

```text
EC_T^dep(frame, X, theta, mu_D)
```

只判定 deployment-economic lower-envelope 是否存在严格下降。

两个方向都不得互推。semantic 下降不保证 deployment-economic 下降；deployment-economic 无改善也不否定 semantic 现象。

## 6. Certificate 边界

合法的 EC_T target-level certificate 至少记录：

1. 完整 frame 标识：`L`、Rate convention、`D`、`sigma_D`、`S_det`；
2. 完整 scope 标识：`X`、workload regime、semantic 或 deployment-economic track；
3. `Ra,Rb` 属于当前实际可达 rate domain；
4. 两个下包络值有限；
5. `F(Rb) < F(Ra)` 的严格性来源；
6. 结论不得超出当前 `frame x X x theta x tau`。

不允许见证后更换 rate counting、成本族、`sigma_D`、策略族、workload regime 或 track。任何更换都是新 estimand。

## 7. EC_T 不证明什么

EC_T 即使通过，也不证明：

- infimum 被某个 `S_det` 成员达到；
- finite sample 能识别下降；
- 下降幅度有实践重要性；
- projection 或 Runtime 能利用该下降；
- competing projections 会被区分；
- 其他架构、workload、track 或 regime 也存在；
- STEP⑥ negative / insufficiency criterion 会通过。

EC_T 通过只表示：在当前 target frame/scope 中，非平凡 strict-descent phenomenon 获得 target-level existence 资格。

## 8. 当前状态

EC_T 替换 EC5，但仍不是 STEP⑤ PASS。

下一攻击面收窄为：

1. loss codomain 与 infimum well-definedness 的最小形式条件；
2. target-level certificate 是否允许纯非构造证明，还是必须给出可审计的下降构造；
3. 平坦、稀疏、极小下降与不可达区间的正式记录格式；
4. semantic / deployment-economic 的 scope closure，避免经济坐标在见证后回流修改 semantic 目标；
5. EC_T 与 STEP⑥ negative criterion 的边界是否足够干净。

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
