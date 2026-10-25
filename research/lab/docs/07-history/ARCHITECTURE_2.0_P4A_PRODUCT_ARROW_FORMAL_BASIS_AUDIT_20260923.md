# Architecture 2.0 — P4-A Product/Arrow Formal Basis Audit

**Date:** 2026-09-23\
**Status:** STEP④-A OPEN / PRODUCT-ARROW MATHEMATICAL SEMANTICS UNDECLARED / GLOBAL FORMAL BASIS REQUIRED\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮唯一问题

本轮只裁定：

```text
当前研究所采用的形式基础中，
× 与 -> 是否已有统一且可追溯的语义？
```

不选择 set theory、type theory、record theory 或其他基础；不裁定 total/partial function；不进入 value discipline、Risk、`D_loss`、`FinLoss`、residual status、NECT 或 STEP⑥。

## 2. Traceability audit

| 来源 | 使用情况 | 是否声明 `×` / `->` semantics |
|---|---|---|
| STEP① Bayes-risk 定义 | 使用 function application、expectation、`inf` 等数学记号 | 否 |
| STEP③ architecture independence | 使用 shared functional、input slot 等概念 | 否 |
| STEP④ estimand / factorization | 使用 `C_j(a,w)=C'_j(a,sigma_D(w))` | 否 |
| MCSC skeleton | 使用 `A × W`、`A × W_D`、`-> V_j` | 仅声明为 formal positions |
| Abstract Field audit | 明确 product/arrow semantics open | 是；状态为 `UNDERDECLARED` |

当前没有任何可追溯文本声明 P4-A 全局采用：

1. set-theoretic Cartesian product；
2. type-theoretic product；
3. record/tuple theory；
4. total-function foundation；
5. partial-function foundation；
6. relational foundation；
7. 其他统一 formal basis。

## 3. Ruling

```text
GLOBAL_FORMAL_BASIS                  = UNDECLARED
PRODUCT_POSITION_SEMANTICS           = UNDECLARED
ARROW_POSITION_SEMANTICS             = UNDECLARED
PRODUCT_MATHEMATICAL_SEMANTICS       = UNDECLARED
ARROW_MATHEMATICAL_SEMANTICS         = UNDECLARED
```

因此，MCSC 中的：

```text
C_j : A × W     -> V_j
sigma_D : W     -> W_D
C'_j : A × W_D  -> V_j
```

当前只能读作 signature positions，不能读作已经具有完整数学语义的 set/functions/types。

## 4. Minimal traceable reading

当前唯一可冻结的是 placeholder reading：

```text
A × W     = paired raw-cost source position
A × W_D   = paired factorized-cost source position
->        = function-slot marker
V_j       = target value-position symbol
```

该 reading 不声明：

1. product 的内部元素形式；
2. projection rules；
3. universal property；
4. totality 或 partiality；
5. definedness；
6. function extensionality；
7. application rules；
8. equality compatibility。

换言之：

```text
signature placeholder reading
  !=
mathematical product/arrow semantics
```

## 5. Scope ruling

该缺口不是 Cost Object 局部问题。

`×` 与 `->` 已进入 MCSC；后续 Risk、oracle、`D_loss`、rate/domain 与可能 typed envelope 也可能复用同类记号。因此需要一个 **global P4-A formal basis declaration**。

不得仅为 Cost Object 临时定义一套 `× / ->`，然后让其他对象使用不同隐含语义。

## 6. Required future declaration

下一步应建立：

```text
P4-A GLOBAL FORMAL BASIS DECLARATION
```

其最小内容必须显式声明：

1. foundational universe：set-theoretic、type-theoretic、record-theoretic，或其他；
2. `×` 的 formal semantics；
3. `->` 的 formal semantics；
4. function application rule；
5. equality compatibility rule；
6. substitution rule；
7. definedness marker 是否进入 syntax；
8. 该 basis 是否统一适用于 P4-A 所有后续对象。

仍不要求本轮选择具体 foundation。

## 7. Current state

```text
GLOBAL_FORMAL_BASIS               = UNDECLARED
PRODUCT_POSITION_SEMANTICS        = UNDECLARED
ARROW_POSITION_SEMANTICS          = UNDECLARED
MCSC_READING                      = SIGNATURE PLACEHOLDERS ONLY
COST_LOCAL_FORMAL_BASIS_PATCH     = FORBIDDEN
VALUE_DISCIPLINE                  = DEFERRED
MEASURABILITY                     = DEFERRED
STEP4_B_RISK_REVIEW               = BLOCKED
FINLOSS_DETERMINACY               = BLOCKED
RESIDUAL_STATUS                   = BLOCKED
NECT_MODE                         = BLOCKED
STEP⑥                             = NOT ENTERED
RQ                                = NOT ASSIGNED
EXPERIMENT AUTHORIZATION          = NONE
```

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
