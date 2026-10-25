# Architecture 2.0 — P4-A STEP⑤ EC_T Well-definedness 与 Evidence Boundary

**Date:** 2026-09-22\
**Status:** STEP⑤ OPEN / EC_T HARDENED / EXISTENCE-vs-NONTRIVIALITY BOUNDARY OPEN\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮裁定

EC_T 通过本轮攻击后继续作为 STEP⑤ 候选，但 STEP⑤ 仍不 PASS。

本轮正式接受三个边界：

1. 下包络的最小 well-definedness contract 不需要拓扑、紧性、连续性或 attainment；
2. target truth 与 certificate 分层；纯非构造数学证明不改变 EC_T 本体；
3. `failure to establish EC_T` 不等于 `not EC_T`。

同时开启下一刀：STEP⑤ 的“existence”到底指 envelope object 存在，还是 nontrivial strict-descent phenomenon 存在。

## 2. Envelope 最小 contract

固定一个 scope：

```text
s = (X, theta, tau)
```

其中 `tau` 是 `semantic`，或显式带 `N` / `mu_D` 的 `deployment-economic`。冻结策略族与 rate convention 后定义：

```text
P_s(R) = { P in S_det : Rate_X(P) <= R }

R_s = { R : P_s(R) != emptyset }
```

最小 well-definedness contract 为：

```text
for all R in R_s:
  P_s(R) != emptyset
  Delta_s(P; theta) in [0, +infinity]
```

若 STEP④ 的 oracle normalization 保证同一 decision problem 下：

```text
Delta_X(P; theta) = R_X(P; theta) - R_oracle,X(theta) >= 0
```

则 loss codomain 冻结为：

```text
[0, +infinity]
```

于是每个非空可行集的下确界都存在于同一 codomain 中：

```text
F_s(R)
  = inf { Delta_s(P; theta) : P in P_s(R) }
  in [0, +infinity]
```

因此不再为 envelope definition 增加 attainment、compactness、continuity、differentiability 或 minimizer existence 条件。

重要区分：

```text
infimum existence != infimum attainment
```

`F_s(R) = +infinity` 仍是合法 extended-real 值。但 EC_T 的见证点必须有限：

```text
F_s(Ra) < +infinity
F_s(Rb) < +infinity
```

否则 `+infinity < +infinity` 无意义。

## 3. Target truth 与 certificate 分层

EC_T 是 target-level proposition：

```text
EC_T(s)
  iff exists Ra,Rb in R_s
      such that
        Ra < Rb,
        F_s(Ra) < +infinity,
        F_s(Rb) < +infinity,
        F_s(Rb) < F_s(Ra)
```

数学上允许纯非构造证明。EC_T 不要求给出某个实际策略达到 `F_s(Rb)`，也不要求先设计实验。

但“certificate”不是 target truth 本身，而是支持该命题的可审计证明对象。一个可选审计形式是夹逼：

```text
F_s(Rb) <= U_b
L_a <= F_s(Ra)
U_b < L_a
```

因此：

```text
F_s(Rb) <= U_b < L_a <= F_s(Ra)
```

即得严格下降。

`U_b` 可以来自一个具体可行策略的上界；`L_a` 可以来自全体可行策略的理论下界。两侧都不要求 attainment。

夹逼是未来证明/证据层的合法接口，但不写入 EC_T 定义，也不构成实验授权。

## 4. Negation、domain insufficiency 与 evidence insufficiency

在 cumulative rate-budget semantics 下：

```text
Ra <= Rb  =>  P_s(Ra) subseteq P_s(Rb)
```

所以：

```text
F_s(Rb) <= F_s(Ra)
```

当 `|R_s| >= 2` 且 envelope contract 成立时，EC_T 的严格逻辑否定是：

```text
for all Ra,Rb in R_s with Ra < Rb:
  F_s(Rb) = F_s(Ra)
```

即 reachable domain 上的下包络完全平坦。

但以下三类不得合并：

| 状态 | 条件 | 含义 |
|---|---|---|
| Envelope undefined | minimum contract 失败 | frame/scope 不可定义，需新 frame，不是 EC_T negative |
| Domain insufficient | `|R_s| < 2` | 没有可比 rate pair，属 applicability boundary，不是 flat frontier |
| Target-level flat negative | `|R_s| >= 2` 且无 strict descent | EC_T 为假；下包络存在但无非平凡 tradeoff |
| Evidence insufficiency | 当前有限证据未建立 EC_T | 只能说未证明，不能说 EC_T 为假 |

治理规则钉死：

```text
failure to establish EC_T != not EC_T
```

未来有限观察得到：

```text
hat F_s(Rb) = hat F_s(Ra)
```

也只能表示当前证据未分辨下降。真实 frontier 仍可能存在极小但严格的下降。

## 5. Semantic 与 deployment-economic

所有状态均按 track 分别声明：

```text
EC_T^sem(X, theta)

EC_T^dep(X, theta, N)
```

或更一般：

```text
EC_T^dep(X, theta, mu_D)
```

以下不是矛盾：

```text
EC_T^sem = true
EC_T^dep = false
```

它们是两个 scope 的独立 target-level 结果，不得互推。

## 6. 当前边界攻击：Existence 还是 Nontrivial Existence

平坦下包络不是一个不存在的对象。只要 minimum contract 成立，它就是一个已定义的 lower-envelope object，只是没有 nontrivial tradeoff structure。

因此必须把两个词分开：

1. **Envelope existence / object existence**：minimum contract 成立即存在；平坦也存在于 STEP④。
2. **Nontrivial existence**：EC_T 成立；要求至少一处 strict descent。

当前 STEP⑤ 的 substantive gate 实际上是第二层，不是第一层。

由此当前候选命名为：

```text
STEP⑤ Nontrivial Existence Criterion
```

而不是泛化的：

```text
STEP⑤ Existence Criterion
```

这一命名修正尚未正式冻结为 STEP⑤ PASS。它仍是当前待审边界。

## 7. 当前状态

EC_T 已加固为候选命题，但 STEP⑤ 仍 OPEN。

下一步必须裁定：

1. 是否正式把 STEP⑤ 限定为 Nontrivial Existence Criterion；
2. 是否把平坦 envelope 明确归类为“对象存在但 target-level nontriviality 为假”；
3. 是否把 domain insufficient、flat negative、evidence insufficiency 的三分法写入 STEP⑥ 前置边界；
4. 是否保留 `EC_T` 作为唯一 substantive existence notion，还是另设一个只表示 envelope-defined 的弱存在状态。

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
