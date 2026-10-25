# Architecture 2.0 — P4-A STEP⑤ Infinity-to-Finite Semantic Admissibility

**Date:** 2026-09-22\
**Status:** STEP⑤ OPEN / NDAC ACCEPTED / NECT MODE OPEN / SAT_INF_FIN DEFINED\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮边界

本轮不裁定 `NECT_E` 或 `NECT_F`。

先把唯一刀口转化为 semantic admissibility test：

```text
SAT_INF_FIN
```

问题不是“哪个定义看起来更好”，而是：

```text
+infinity -> finite
是否满足 NECT 所要识别的 nontrivial phenomenon 的身份条件？
```

四项检查全部完成后，`NECT_E / NECT_F` 才有资格进入裁定。

## 2. 待测现象

设 envelope contract 已成立，且 `NDAC(s)` 已通过。待测现象为：

```text
exists Ra,Rb in R_s^tau
such that
  Ra < Rb,
  F_s(Ra) = +infinity,
  F_s(Rb) <  +infinity
```

在 extended-real order 中，这是 strict descent：

```text
F_s(Rb) < F_s(Ra)
```

但它是否属于 NECT 的 substantive phenomenon，取决于 `+infinity` 在当前对象中的语义身份。

## 3. 四项 identity check

### 3.1 Domain identity

必须满足：

```text
Ra,Rb in R_s^tau
Ra < Rb
NDAC(s) = true
Envelope defined
```

两个 rate point 必须属于同一个 declared scope：

```text
(frame, X, theta, tau)
```

semantic 与 deployment-economic 不得合并；不同 workload regime 或 economic coordinate 不得合并。

注意：`F_s(Ra)=+infinity` 不表示 `R_a` 不在 reachable domain。reachable domain 只要求存在至少一个策略；它不要求存在 finite-loss 策略。

### 3.2 Order identity

当前 codomain 是：

```text
[0,+infinity]
```

在这个 codomain 中，对任意 finite `a`：

```text
a < +infinity
```

这是合法 extended-real order。

但必须先确认 `+infinity` 是 loss value，不是 `UNDEFINED`、`NOT_EVALUABLE` 或 missing-data marker。

若 `+infinity` 实际上表示“无法评估”，则：

```text
NOT_EVALUABLE < finite
```

不是合法 order relation，SAT 直接失败。

### 3.3 Substantive identity

`+infinity` 至少要区分三种 provenance：

| 标记 | 含义 | 初步 SAT 结果 |
|---|---|---|
| `ACTUAL_INFINITY_LOSS` | 冻结成本族把 `+infinity` 作为 decision-loss value 使用；envelope 因此为 `+infinity` | 可作为 legitimate strict descent 候选 |
| `FINITE_REALIZABILITY_BOUNDARY` | `+infinity` 记录当前 rate budget 下不存在 finite-loss 可达成员；进入 finite point 是 finite-loss realizability onset | 是否属于目标现象待裁 |
| `EVALUATION_NA` | 评估失败、对象未定义或数据缺失标记 | 不属于 strict descent，SAT 失败 |

核心问题是第二类与第一类的分界。

`FINITE_REALIZABILITY_BOUNDARY -> finite` 可能只是 **finite-loss realizability boundary**，而不是 decision-loss 数值本身的下降。但因为 `R_a` 上并非空集，它也不是普通 infeasibility。

因此不能凭直觉排除。必须先裁定：finite-loss realizability onset 是否属于当前 NECT 要捕获的目标现象。

### 3.4 Degeneracy risk

若纳入 `+infinity -> finite`，则任何具有如下形状的 scope 都会成为 `NECT_E=true`：

```text
prefix of +infinity
followed by one finite value
followed by a flat finite segment
```

这类现象应标记为：

```text
FINITE_ONSET_ONLY
```

这不一定是否认其现象身份。它只说明 NECT 需要区分两类 descent：

```text
FINITE_TO_FINITE descent

INFINITY_TO_FINITE descent
```

degeneracy risk 不能替代对象裁定，也不得引入幅度阈值、Runtime value 或实践重要性判断。它只是要求 NECT 输出不得把不同类型的 strict descent 静默混合。

## 4. SAT 结果语义

`SAT_INF_FIN` 不是新的 STEP⑤ target output。它是 mode adjudication 前的对象资格审查。

其合法结果仅限定为：

```text
ADMISSIBLE
INADMISSIBLE
CONDITIONAL / PROVENANCE OPEN
```

不得输出：

```text
EVIDENCE_INSUFFICIENT
```

当前唯一待裁核心是：

```text
ACTUAL_INFINITY_LOSS 和 FINITE_REALIZABILITY_BOUNDARY
是否都满足 NECT 的 substantive identity？
```

若都满足，则 `NECT_E` 是自然的 general predicate。

若只有 finite-loss region 内部下降满足，则应正式命名：

```text
NECT_F
```

并说明排除 `+infinity -> finite` 是对象定义中的有意 restriction。

若二者是不同现象，则应使用 dual predicate 或 typed annotation，而不得用一个 NECT 静默覆盖。

## 5. 对两个 mode 的影响

### 若最终选择 `NECT_E`

则 finite-witness precondition 必须删除。

否则会出现定义不一致：

```text
谓词语义承认 +infinity -> finite 是 strict descent，
但前置条件把它挡掉。
```

若保留区分，应加入 typed annotation：

```text
FINITE_TO_FINITE
INFINITY_TO_FINITE
```

### 若最终选择 `NECT_F`

则必须冻结一条对象层面的研究理由，说明为什么 finite-loss realizability onset 不属于当前 NECT。

不允许只说：

```text
infinity 不是真实 loss
```

因为当前 STEP④ envelope 已经采用 extended-real semantics。若要排除，必须在对象定义中说明排除理由，而不是在谓词中悄悄删除。

## 6. 当前状态

已冻结的是 SAT 的检查框架。

尚未裁定：

1. `ACTUAL_INFINITY_LOSS` 是否全部纳入 NECT；
2. `FINITE_REALIZABILITY_BOUNDARY` 是否属于 substantive phenomenon；
3. `+infinity -> finite` 是否需要 typed descent annotation；
4. `NECT_E / NECT_F / dual predicate` 谁成为 STEP⑤ 正式对象。

当前状态保持：

```text
STEP⑤ OPEN
NDAC ACCEPTED
NECT MODE OPEN
SAT_INF_FIN DEFINED
RQ NOT ASSIGNED
NO EXPERIMENT AUTHORIZATION
```

不推进 STEP⑥。

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
