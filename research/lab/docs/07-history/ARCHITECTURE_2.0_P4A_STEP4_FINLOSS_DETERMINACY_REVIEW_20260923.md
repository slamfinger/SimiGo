# Architecture 2.0 — P4-A STEP④ FinLoss Determinacy Review

**Date:** 2026-09-23\
**Status:** REVIEW-1 COMPLETE / FINLOSS NOT UNIQUELY DETERMINED / STEP④ LOSS OBJECT INCOMPLETE / STEP⑤ NECT MODE BLOCKED\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮唯一问题

本轮只裁定：

```text
冻结的 C / R / D_loss semantics 是否已经唯一确定
FinLoss(P,theta)？
```

不裁定 `R_s^nofin` 的 residual status，不选择 Candidate 1 / Candidate 3，不裁定 `NECT_E / NECT_F`，不进入 STEP⑥。

## 2. 两个层次必须分开

### Policy-level predicate

```text
FinLoss(P,theta)
  iff D_loss(P,theta) is defined
   and D_loss(P,theta) in [0,+infinity)
```

这是策略/参数级 predicate。

### Rate-level domain admission

```text
R_s^FL
  = { R in R_s :
      exists P in P_s(R) such that FinLoss(P,theta) }
```

这是 envelope domain admission set。

二者不等价。前者判定单个策略/参数是否具有 finite loss；后者判定某个 rate 是否至少存在一个 finite-loss policy。

只有先确定 policy-level `FinLoss`，才可能定义：

```text
P_s^FL(R)
  = { P in P_s(R) : FinLoss(P,theta) }
```

进而得到：

```text
R_s^FL
```

以及：

```text
F_s^fin : R_s^FL -> [0,+infinity)
```

## 3. Source audit

冻结语义只给出：

```text
R(P;theta)
  = inf over delta in Delta(I_P)
    E_theta[ C(delta(I_P), W) ]

D_loss(P;theta)
  = R(P;theta) - R_oracle(theta)
```

但它没有声明以下对象：

| 审查项 | 当前状态 |
|---|---|
| `C` 的 codomain | 未声明 |
| `C` 是否 measurable | 未声明 |
| `C` 是否 finite-valued | 未声明 |
| `E_theta[...]` 是否总存在 | 未声明 |
| expectation 是否 finite | 未声明 |
| `Delta(I_P)` 是否非空 | 未声明 |
| empty-set `inf` convention | 未声明 |
| `R(P;theta)` 是否 finite | 未声明 |
| `R_oracle(theta)` 是否 finite | 未声明 |
| subtraction 是否对所有相关情形 well-defined | 未声明 |
| `D_loss` 的 codomain | 未声明 |

## 4. Indeterminacy lemma

冻结关系至少兼容两种不同的 semantic completion。

### Completion F

若补入：

```text
C finite and measurable
all relevant expectations exist and are finite
Delta(I_P) nonempty
R_oracle(theta) finite
```

则对相关 `P,theta`：

```text
FinLoss(P,theta) = true
```

### Completion U

若只保留冻结原文，而不补入上述条件，则可能存在：

```text
P0,theta0
```

使得 expectation 不存在、decision-rule set 为空且没有 inf convention、或 oracle reference 未定义。

此时：

```text
D_loss(P0,theta0) is not defined
FinLoss(P0,theta0) = false / not evaluable
```

这两种 completion 都不与已冻结的形式关系冲突，但会给 `FinLoss` 赋予不同 extension。

因此：

```text
FINLOSS_UNIQUELY_DETERMINED = FALSE
```

## 5. Review-1 result

```text
REVIEW_1 = C
```

含义：

> 当前 STEP①–④ semantics 不能唯一确定 `FinLoss(P,theta)`；loss object definition incomplete，必须回到 STEP④ 补定义。

同时记录：

```text
MISSING_SEMANTIC_PRECONDITIONS = YES
```

缺失项至少包括：

1. loss codomain；
2. cost/risk measurability 与 existence conditions；
3. finite-valued 或其他明确的 value discipline；
4. decision-rule set / inf convention；
5. oracle reference finiteness；
6. excess-loss subtraction 与 nonnegativity condition。

这些属于 STEP④ loss object definition，不属于 STEP⑤ existence criterion。

## 6. Governance consequence

Review-2 被阻断。

原因：`R_s^nofin` 的 residual status 只有在 `FinLoss` 被 STEP④ 合法定义后才有稳定语义。

当前状态：

```text
FINLOSS_UNIQUELY_DETERMINED   = FALSE
REVIEW_1                      = C / STEP4 INCOMPLETE
REVIEW_2                      = BLOCKED
DOMAIN_PARTITION              = STRUCTURAL CANDIDATE ONLY
CANDIDATE_1_REFORMULATED      = BLOCKED PENDING STEP4
CANDIDATE_3                   = NOT ESTABLISHED
RESIDUAL_STATUS               = UNRESOLVED
NECT_MODE                     = BLOCKED
STEP⑥                         = NOT ENTERED
RQ                            = NOT ASSIGNED
EXPERIMENT AUTHORIZATION      = NONE
```

下一步只能做 STEP④ loss object completion：

1. 声明 `C/R/D_loss` 的 codomain；
2. 声明 expectation / inf 的 well-definedness conditions；
3. 声明 oracle reference 的 value discipline；
4. 声明 `D_loss` 的 value discipline；
5. 然后重新审查 `FinLoss` 是否被唯一确定。

不得通过实验、估计结果、NECT 通过/失败或 residual-domain 便利来补 `FinLoss`。

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
