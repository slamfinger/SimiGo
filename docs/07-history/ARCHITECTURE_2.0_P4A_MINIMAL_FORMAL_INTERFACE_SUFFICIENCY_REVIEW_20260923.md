# Architecture 2.0 — P4-A Minimal Formal Interface Sufficiency Review

**Date:** 2026-09-23\
**Status:** STEP④-A OPEN / MINIMAL INTERFACE CONDITIONALLY SUFFICIENT / FOUNDATION CHOICE DEFERRED / SEMANTIC INSTANTIATION BLOCKED\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮唯一问题

本轮只裁定：

```text
P4-A 是否可以仅凭一个 foundation-independent minimal formal interface，
在不选择 set theory / type theory / record theory / total-function theory /
partial-function theory 等完整 foundation 的情况下继续？
```

不选择完整 foundation，不定义 total/partial function，不规定 product projection 或 universal property，不进入 value discipline、Risk、`D_loss`、`FinLoss`、residual status、NECT 或 STEP⑥。

## 2. 区分三个层

必须区分：

```text
1. Full foundational semantics
2. P4-A minimal formal interface
3. Semantic cost object
```

### 2.1 Full foundational semantics

这是 `×`、`->`、application、equality、substitution 的完整数学解释。

当前状态：

```text
UNDERDETERMINED
```

### 2.2 P4-A minimal formal interface

这是让 P4-A 的 formal positions 可命名、可审计、可禁止偷渡语义的最小规则层。

它不解释这些 positions 的本体论身份。

### 2.3 Semantic cost object

这是具体的 `C/C_j/C'_j/sigma_D` 数学对象。

当前状态：

```text
BLOCKED
```

## 3. Required interface fields

### 3.1 PAIR_FORMATION

需要保留两个 paired-source positions：

```text
PAIR_RAW       = A × W
PAIR_FACTORIZED = A × W_D
```

MFI 只承诺它们是 paired-source position markers。

不承诺 set-theoretic product、type-theoretic product、record、projection、universal property 或内部元素形状。

### 3.2 PAIR_PROJECTION

当前 P4-A 冻结文本不需要 projection rule。

因此：

```text
PAIR_PROJECTION = NOT_REQUIRED_NOW / DEFERRED
```

不得默认 `A × W` 具有 `fst`、`snd`、surjective pairing 或 uniqueness rule。

### 3.3 FUNCTION_SLOT

需要保留 function-slot marker：

```text
FUNCTION_SLOT(S,T)
```

用于：

```text
C_j   : A × W   -> V_j
sigma_D : W     -> W_D
C'_j  : A × W_D -> V_j
```

MFI 不承诺 total、partial、measurable、finite-valued、computable 或 defined everywhere。

### 3.4 APPLICATION

冻结文本中出现：

```text
C_j(a,w)
sigma_D(w)
C'_j(a,sigma_D(w))
```

因此 MFI 需要一个 formal application placeholder。

但该 placeholder 只允许记录 application term，不解释 evaluation、definedness、return value 或 totality。

### 3.5 TYPED_EQUALITY

factorization identity 需要一个 typed equality placeholder：

```text
=_{V_j}
```

MFI 只记录 equality belongs to `V_j`。

不承诺 equality 的 truth condition、extensionality、decidability、quotient behavior 或 cross-`V_j` comparison。

### 3.6 SUBSTITUTION

为了审计任意 `a,w` 下的 factorization，需要 syntactic substitution placeholder。

MFI 不承诺 substitution theorem、replacement semantics、rewriting system 或 proof rule。

## 4. Sufficiency ruling

MFI 的 sufficiency 必须分层裁定。

```text
MINIMAL_INTERFACE_SUFFICIENT_FOR_NOTATION_GOVERNANCE = TRUE
MINIMAL_INTERFACE_SUFFICIENT_FOR_PLACEHOLDER_MCSC    = TRUE
MINIMAL_INTERFACE_SUFFICIENT_FOR_COST_SEMANTICS      = FALSE
MINIMAL_INTERFACE_REQUIRES_FULL_FOUNDATION_NOW       = FALSE
```

因此路径裁定为 split：

```text
M1 = YES FOR PRE-SEMANTIC NOTATION LAYER
M1 = NO FOR SEMANTIC INSTANTIATION
M2 = NOT TRIGGERED
```

换言之，P4-A 不需要立即选择完整 foundation；但也不能声称 MFI 已经给出 cost semantics。

## 5. What MFI supports

MFI 足以支撑：

1. 命名 `J/A/W/W_D/V_j` 等 formal positions；
2. 记录 paired-source position；
3. 记录 function-slot position；
4. 记录 formal application term；
5. 记录 typed-equality placeholder；
6. 记录 syntactic-substitution placeholder；
7. 禁止偷渡 total/partial、measurable、finite、scalar、set/type semantics。

## 6. What MFI does not support

MFI 不足以支撑：

1. 将 `C_j/C'_j/sigma_D` 实例化为具体函数；
2. 判定 application 的 definedness；
3. 判定 factorization equality 为真；
4. 证明 substitution rule；
5. 选择 `V_j` 的 value discipline；
6. 进入 Risk Well-definedness；
7. 推导 `FinLoss`；
8. 裁定 residual status 或 NECT mode。

## 7. Governance rule

```text
MINIMAL_FORMAL_INTERFACE          = REQUIRED / CONDITIONALLY SUFFICIENT
FULL_FOUNDATION_IMMEDIATE_CHOICE  = NOT REQUIRED
SEMANTIC_INSTANTIATION            = BLOCKED UNTIL MFI INTERPRETATION IS DECLARED
COST_LOCAL_FOUNDATION_PATCH       = FORBIDDEN
```

如果后续任一步需要真实 application evaluation、equality truth、projection rule 或 substitution theorem，则必须先扩展或解释 MFI；不得继续使用 placeholder reading 偷渡结果。

## 8. Current state

```text
GLOBAL_FOUNDATIONAL_THEORY           = UNDERDETERMINED
P4A_MINIMAL_FORMAL_INTERFACE         = REQUIRED / CONDITIONALLY SUFFICIENT
MFI_SUPPORTS_NOTATION_GOVERNANCE     = TRUE
MFI_SUPPORTS_COST_SEMANTICS          = FALSE
PAIR_FORMATION                       = MFI PLACEHOLDER
PAIR_PROJECTION                      = DEFERRED
FUNCTION_SLOT                        = MFI PLACEHOLDER
APPLICATION                          = MFI PLACEHOLDER
TYPED_EQUALITY                       = MFI PLACEHOLDER
SUBSTITUTION                         = MFI PLACEHOLDER
VALUE_DISCIPLINE                     = DEFERRED
MEASURABILITY                        = DEFERRED
MCSC_SEMANTIC_INSTANTIATION          = BLOCKED
STEP4_B_RISK_REVIEW                  = BLOCKED
FINLOSS_DETERMINACY                  = BLOCKED
RESIDUAL_STATUS                      = BLOCKED
NECT_MODE                            = BLOCKED
STEP⑥                                = NOT ENTERED
RQ                                   = NOT ASSIGNED
EXPERIMENT AUTHORIZATION             = NONE
```

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
