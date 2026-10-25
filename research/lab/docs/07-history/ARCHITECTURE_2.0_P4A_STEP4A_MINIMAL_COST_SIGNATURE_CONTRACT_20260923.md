# Architecture 2.0 — P4-A STEP④-A Minimal Cost Signature Contract

**Date:** 2026-09-23\
**Status:** STEP④-A OPEN / MCSC SKELETON ADOPTED / SEMANTIC INSTANTIATION OPEN / VALUE DISCIPLINE DEFERRED / STEP④-B BLOCKED\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮范围

本轮只冻结 Minimal Cost Signature Contract 的形式位置，简称：

```text
MCSC skeleton
```

它声明 cost signature 必须具备哪些 formal fields。

本轮不声明这些位置的实质性数学语义，不选择 value discipline，不规定 measurability，不绑定 `C` 的组合方式，不进入 STEP④-B。

## 2. MCSC skeleton

最小 signature contract 记为：

```text
MCSC = (
  J,
  A,
  W,
  W_D,
  (V_j)_{j in J},
  (C_j)_{j in J},
  sigma_D,
  (C'_j)_{j in J},
  (=_{V_j})_{j in J},
  Binding_C
)
```

对每个抽象 index `j in J`：

```text
C_j : A × W -> V_j

sigma_D : W -> W_D

C'_j : A × W_D -> V_j
```

factorization equation 的 typed position 为：

```text
C_j(a,w) =_{V_j} C'_j(a,sigma_D(w))
```

## 3. Field declarations

| Field | Skeleton declaration | Still open |
|---|---|---|
| `J` | abstract index-set symbol | 成员、粒度、component boundary |
| `A` | carrier symbol | 具体对象、元素、结构 |
| `W` | raw workload/outcome carrier symbol | 具体对象、元素、结构 |
| `W_D` | factorized carrier symbol | 具体对象、元素、结构 |
| `V_j` | per-component abstract value-space symbol | value discipline |
| `C_j` | raw-cost function signature | function definition |
| `sigma_D` | factorization map signature | map definition |
| `C'_j` | factorized-cost function signature | function definition |
| `=_{V_j}` | equality is typed in `V_j` | eventual equality structure |
| `Binding_C` | reserved relation field between `C` and `(C_j)_j` | formal kind and definition |

`Binding_C` 只是一个 reserved field。它当前不是 sum、tuple、product、aggregation、equality 或任何其他已选组合形式。其 formal kind 与 definition 均 undeclared。

## 4. Non-instantiation boundaries

MCSC skeleton 不允许以下推断：

```text
{recomputation, migration, capacity} = J
```

这些自然语言 term 仍只是 semantic hints。

MCSC skeleton 也不选择：

```text
FINITE_SCALAR
EXTENDED_SCALAR
VECTOR
TYPED_RECORD
```

因此，不能因为 expectation 可能需要 scalar 而把 `V_j` 改成 `[0,+infinity)` 或 `R`。

同样，MCSC skeleton 不声明：

1. `A/W/W_D` 的 sigma-algebra；
2. `sigma_D` 是否 measurable；
3. `C_j/C'_j` 是否 measurable；
4. `C_j/C'_j` 是否 finite-valued；
5. `C_j/C'_j` 是否非负；
6. `C` 如何由 `(C_j)_j` 组合。

## 5. Governance meaning

MCSC skeleton 的采纳只表示：

> 在讨论 cost value discipline 之前，必须先承认并逐项填充这些 formal positions。

它不表示：

```text
COST_SIGNATURE_COMPLETE = TRUE
```

也不表示任何一个 cost component 已经具有 mathematical definition。

当前 relation 仍为：

```text
COST_SIGNATURE_UNIQUELY_DETERMINED = FALSE
MCSC_SKELETON                     = ADOPTED
SEMANTIC_INSTANTIATION            = OPEN
```

## 6. Completion path

MCSC skeleton 的后续填充必须保持 abstraction，并逐项处理：

1. `J` 的 abstract declaration 与 component-boundary criterion；
2. `A/W/W_D` 的 carrier declaration；
3. 每个 `V_j` 的 abstract declaration；
4. 每个 `C_j` 的 formal signature definition；
5. 每个 `sigma_D` 的 formal signature definition；
6. 每个 `C'_j` 的 formal signature definition；
7. 每个 `V_j` 的 equality notion；
8. `Binding_C` 的 formal kind；
9. `C` 与 `(C_j)_j` 的 binding definition。

完成后才可进入 Cost Value Discipline。

仍不得直接进入 STEP④-B Risk Well-definedness。

## 7. Current state

```text
MCSC_SKELETON                   = ADOPTED
J_MEMBERSHIP                    = ABSTRACT / UNDECLARED
A                               = CARRIER SYMBOL ONLY
W                               = CARRIER SYMBOL ONLY
W_D                             = CARRIER SYMBOL ONLY
V_J                             = ABSTRACT SYMBOLS ONLY
C_J                             = SIGNATURE ONLY
SIGMA_D                         = SIGNATURE ONLY
C_PRIME_J                       = SIGNATURE ONLY
BINDING_C                       = RESERVED / UNDECLARED
VALUE_DISCIPLINE                = DEFERRED
MEASURABILITY                   = DEFERRED
STEP4_B_RISK_REVIEW             = BLOCKED
FINLOSS_DETERMINACY             = BLOCKED
RESIDUAL_STATUS                 = BLOCKED
NECT_MODE                       = BLOCKED
STEP⑥                           = NOT ENTERED
RQ                              = NOT ASSIGNED
EXPERIMENT AUTHORIZATION        = NONE
```

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
