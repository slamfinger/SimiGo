# Architecture 2.0 — P4-A STEP④ Domain/Codomain Orthogonality Ruling

**Date:** 2026-09-23\
**Status:** STEP④ REVIEW OPEN / DOMAIN PARTITION ADOPTED / CANDIDATE 1 REFORMULATED / CANDIDATE 2 REJECTED / CANDIDATE 3 NOT NECESSARY / NECT MODE BLOCKED\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮裁定

本轮不再证明：

```text
for all R in R_s: F_s(R) < +infinity
```

该命题混淆了两个独立对象：

1. loss codomain 是否 finite；
2. `R_s` 是否就是 loss function 的完整 domain。

正式裁定：

```text
R_s = R_s^fin disjoint-union R_s^nofin
```

loss-valued envelope只定义在 finite-loss domain 上：

```text
F_s^fin : R_s^fin -> [0,+infinity)
```

`R_s^nofin` 不编码为 `+infinity`，也不参与 loss order。

## 2. Domain partition

定义 finite-loss evaluation predicate：

```text
FinLoss(P,theta)
  iff Delta_s(P;theta) is defined
   and Delta_s(P;theta) in [0,+infinity)
```

再定义：

```text
S_det^fin
  = { P in S_det : FinLoss(P,theta) }

P_s^fin(R)
  = { P in P_s(R) : FinLoss(P,theta) }

R_s^fin
  = { R in R_s : P_s^fin(R) != emptyset }

R_s^nofin
  = R_s \ R_s^fin
```

在 `R_s^fin` 上定义：

```text
F_s^fin(R)
  = inf { Delta_s(P;theta) : P in P_s^fin(R) }
```

因为 `P_s^fin(R)` 非空且值域为 `[0,+infinity)`，其 infimum 存在且 finite。infimum attainment 仍不需要。

## 3. Candidate 状态更新

| Candidate | 状态 | 说明 |
|---|---|---|
| Candidate 1 original：`F_s:R_s->[0,+infinity)` | SUPERSEDED | 不再要求 finite completeness over `R_s` |
| Candidate 1 reformulated：`F_s^fin:R_s^fin->[0,+infinity)` | CONDITIONAL CANDIDATE | 只表示 finite-loss layer |
| Candidate 2：`F_s:R_s->[0,+infinity]` | REJECTED | `+infinity` 没有既有 ordered loss-value 语义 |
| Candidate 3 typed envelope | NOT NECESSARY FOR RESIDUAL | `R_s^nofin` 由 domain partition 表示，不需要 `+infinity` tag |

`Candidate 1 reformulated` 仍不是最终冻结。它还必须通过两项后续审查：

1. `FinLoss(P,theta)` 必须由冻结 frame semantics 合法定义；
2. `R_s^nofin` 的 residual status 必须显式裁定。

## 4. Residual-domain status

`R_s^nofin` 的语义不是 loss value，而是 domain partition 的 residual：

```text
R in R_s^nofin
  means R is reachable
  but P_s^fin(R) is empty.
```

它不表示：

```text
F_s(R) = +infinity
```

因此也不存在：

```text
F_s^fin(R_b) < F_s^fin(R_a)
```

当 `R_a in R_s^nofin` 且 `F_s^fin(R_a)` undefined 时。

`R_s^nofin` 的最终 status 仍有两个候选：

| Status | 含义 |
|---|---|
| `APPLICABILITY_DOMAIN_EXCLUSION` | 这些 reachable states 不进入当前 loss estimand domain |
| `REACHABLE_BUT_NON_LOSS_VALUED` | 这些 states 保留在 reachable bookkeeping 中，但不进入 loss order |

二者都禁止把 residual 写成 `+infinity`。选择哪个 status 是下一步 STEP④ review 的任务。

## 5. NECT domain consequence

本裁定不选择 `NECT_F`。

它只确立一个后果：若未来 NECT 使用 `F_s^fin`，则两个比较点必须同属：

```text
R_s^fin
```

原因是 `F_s^fin` 在 `R_s^nofin` 上没有定义。

`R_s^nofin -> R_s^fin` 只能称为 realizability transition 候选，不能称为 strict descent。

`NECT_E` 目前没有可用的 extended-real loss object；`NECT_F` 也尚未被裁定为 NECT domain。二者保持 conceptually open，但 mode adjudication 继续被 blocking。

`NDAC` 已接受的 gate 身份不变。其最终适用 domain 必须等 NECT domain consequence 裁定后统一表述。

## 6. Review queue

当前 STEP④ review 只剩三个问题：

### Review-1：Loss-domain definition

裁定 `FinLoss(P,theta)` 是否可由冻结 `C/R/D` semantics 合法定义，而不是由实验或 NECT 结果反推。

### Review-2：Residual-domain status

裁定 `R_s^nofin` 是：

```text
APPLICABILITY_DOMAIN_EXCLUSION
```

还是：

```text
REACHABLE_BUT_NON_LOSS_VALUED
```

### Review-3：NECT domain consequence

只有完成 Review-1/2 后，才能问：

```text
NECT strict descent 是否只定义在 R_s^fin 上？
```

这一步不得提前裁掉 `NECT_F`。

## 7. Current state

```text
CANDIDATE_2                    = REJECTED
DOMAIN_PARTITION               = ADOPTED
CANDIDATE_1_REFORMULATED       = CONDITIONAL CANDIDATE
FINITE_COMPLETENESS_OVER_R_S   = NOT REQUIRED
R_S_NOFIN_INFINITY_ENCODING    = FORBIDDEN
CANDIDATE_3                    = NOT NECESSARY FOR RESIDUAL
IPR_VALUE                      = UNDECLARED
RESIDUAL_STATUS                = UNRESOLVED
NECT_MODE                      = BLOCKED / CONCEPTUALLY OPEN
STEP⑥                          = NOT ENTERED
RQ                             = NOT ASSIGNED
EXPERIMENT AUTHORIZATION       = NONE
```

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
