# Architecture 2.0 — P4-A STEP④-A Minimal Formal Basis Sufficiency Review

**Date:** 2026-09-23\
**Status:** MFB-SR COMPLETE / MFB-S / MINIMAL_INTERFACE_ONLY / FULL FOUNDATION NOT REQUIRED\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮范围

本轮只审查 Minimal Formal Basis Sufficiency：

```text
MFB-SR
```

不选择完整 mathematical foundation，不规定 product universal property，不裁定 total/partial function，不进入 value discipline、measurability、Risk、`D_loss`、`FinLoss`、residual status、NECT 或 STEP⑥。

## 2. 六项最小操作裁定

| Operation | MFB-SR ruling | Reason |
|---|---|---|
| Pair formation | `MINIMAL_REQUIRED` | `A × W` 与 `A × W_D` 已作为 paired source positions 出现 |
| Projection | `NOT_REQUIRED` | 当前 MCSC 不拆解 pair 内部结构 |
| Function slot | `MINIMAL_REQUIRED` | `C_j`、`sigma_D`、`C'_j` 已作为 mapping positions 出现 |
| Application | `MINIMAL_REQUIRED` | `C_j(a,w)`、`sigma_D(w)`、`C'_j(a,sigma_D(w))` 已出现 |
| Typed equality | `MINIMAL_REQUIRED` | `=_{V_j}` 已出现在 factorization identity 中 |
| Substitution | `NOT_REQUIRED` | 当前没有依赖 substitution rule 的推导 |

因此：

```text
B_min = {
  Pair Formation,
  Function Slot,
  Application,
  Typed Equality
}
```

Projection 与 Substitution 不进入 `B_min`。

## 3. 各 operation 的最小含义

### Pair Formation

允许保留：

```text
(a,w)
```

与：

```text
(a,w_D)
```

作为 paired input positions。

这不声称 `A × W` 是 set-theoretic Cartesian product、type-theoretic product、record type 或满足 universal property。

### Function Slot

允许表达：

```text
C_j   : A × W   -> V_j
sigma_D : W     -> W_D
C'_j  : A × W_D -> V_j
```

这只是 function-slot placement。

不得推出：

1. total；
2. everywhere-defined；
3. measurable；
4. computable；
5. continuous；
6. finite-valued。

### Application

允许形成：

```text
C_j(a,w)
sigma_D(w)
C'_j(a,sigma_D(w))
```

这只是 application position。

不保证这些 term defined、evaluable、finite 或有值。

### Typed Equality

允许表达：

```text
C_j(a,w) =_{V_j} C'_j(a,sigma_D(w))
```

最小含义是两侧位于同一个 `V_j` value position，并在该 value position 内作 equality judgment。

这不选择 `V_j` 的 value discipline。

## 4. Sufficiency ruling

```text
MINIMAL_FORMAL_BASIS_SUFFICIENT = TRUE
```

该 `TRUE` 的范围仅是：

> 最小形式接口足以支撑当前 MCSC 继续向下一层推进。

它不表示：

1. `A/W/W_D` 已有具体数学定义；
2. `V_j` 已有 value-space definition；
3. `C_j/C'_j` 已有完整定义；
4. measurability 已确定；
5. finite-valuedness 已确定；
6. Risk 已 well-defined；
7. `FinLoss` 已可推导。

## 5. Foundation ruling

```text
GLOBAL_FORMAL_BASIS = MINIMAL_INTERFACE_ONLY
FULL_FOUNDATION     = UNDECLARED / NOT REQUIRED NOW
PRODUCT_MATHEMATICAL_SEMANTICS = UNDECLARED
ARROW_MATHEMATICAL_SEMANTICS   = UNDECLARED
```

不需要现在选择：

1. set theory；
2. type theory；
3. category theory；
4. relational theory；
5. partial-function theory；
6. 某种具体形式系统。

## 6. Supersession note

本文裁定 supersede 前一版 MFI 审查中将 `SUBSTITUTION` 列为 placeholder 的做法。

当前冻结为：

```text
SUBSTITUTION = NOT_REQUIRED
PAIR_PROJECTION = NOT_REQUIRED
```

若未来需要 substitution 或 projection，必须重新通过 STEP④-A review 显式引入。

## 7. Current state

```text
MFB_SR                             = COMPLETE
MINIMAL_FORMAL_BASIS_SUFFICIENT    = TRUE
B_MIN                              = PAIR / FUNCTION_SLOT / APPLICATION / TYPED_EQUALITY
PROJECTION                         = NOT_REQUIRED
SUBSTITUTION                       = NOT_REQUIRED
GLOBAL_FORMAL_BASIS                = MINIMAL_INTERFACE_ONLY
FULL_FOUNDATION                    = UNDECLARED
PRODUCT_MATHEMATICAL_SEMANTICS     = UNDECLARED
ARROW_MATHEMATICAL_SEMANTICS       = UNDECLARED
VALUE_DISCIPLINE                   = DEFERRED
STEP4_B_RISK_REVIEW                = BLOCKED
FINLOSS_DETERMINACY                = BLOCKED
RESIDUAL_STATUS                    = BLOCKED
NECT_MODE                          = BLOCKED
STEP⑥                              = NOT ENTERED
RQ                                 = NOT ASSIGNED
EXPERIMENT AUTHORIZATION           = NONE
```

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
