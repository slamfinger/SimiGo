# Architecture 2.0 — P4-A IPR Declaration Audit 与 STEP④ Typed-Codomain Review

**Date:** 2026-09-22\
**Status:** IPR UNDECLARED / STEP④ TYPED-CODOMAIN REVIEW OPEN / STEP⑤ MODE ADJUDICATION BLOCKED\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮唯一任务

本轮只对当前 P4-A frame 声明：

```text
IPR in {
  LOSS_VALUE,
  BOUNDARY_ENCODING,
  MIXED,
  NA
}
```

不裁定 `NECT_E / NECT_F`，不进入 STEP⑥。

## 2. Source audit

当前 frame 的原始 decision-loss 定义为：

```text
R(P; theta)
  = inf over delta in Delta(I_P)
    E_theta[ C(delta(I_P), W) ]

D(P; theta) = R(P; theta) - R_oracle(theta)
```

审计结果：

| 检查项 | 结果 |
|---|---|
| 成本函数 `C` 是否声明 codomain | 未声明 |
| Bayes risk `R(P;theta)` 是否声明 codomain | 未声明 |
| `D(P;theta)` 是否声明 codomain | 未声明 |
| `+infinity` 是否被声明为 ordered loss value | 否 |
| `+infinity` 是否被声明为 no-finite-loss sentinel | 否 |
| 是否存在多种 `+infinity` 用法可证明混合 | 未证明 |
| `+infinity` 是否被声明为 evaluation failure / NA marker | 未证明 |

STEP⑤ 后续引入的最小 contract：

```text
Delta_s(P; theta) in [0,+infinity]
```

只声明了可能取值范围与 infimum well-definedness，没有声明 `+infinity` 的 provenance。

因此：

```text
[0,+infinity] codomain != IPR declaration
```

## 3. Declaration result

当前 frame 不能推出：

```text
IPR = LOSS_VALUE
```

因为 extended-real codomain 本身不证明 `+infinity` 是 decision-loss magnitude。

当前 frame 也不能推出：

```text
IPR = BOUNDARY_ENCODING
```

因为 `F_s(R)=+infinity iff no finite-loss member` 只是 extended-real arithmetic 的可能结果，不等于 frame 已把 `+infinity` 定义为 sentinel。

当前 frame 也不能推出：

```text
IPR = MIXED
```

因为没有证据表明两种用法已被同时预注册。

当前 frame 更不能因 declaration failure 被改写为：

```text
IPR = NA
```

`NA` 是 target envelope 中 evaluation failure / missing-data 的类型，不是 “我们尚未声明 provenance” 的 epistemic status。

正式裁定：

```text
IPR_VALUE        = UNDECLARED
IPR_DECLARATION  = FAILED
```

## 4. Governance consequence

由于 NECT mode 依赖 `+infinity` 的语义身份，declaration failure 会阻断 STEP⑤ mode adjudication。

因此触发一个窄口径审查：

```text
STEP④ Typed-Codomain Review
```

该审查不整体重开 STEP④ Estimand，也不改变已冻结的：

- `L` 与 Rate convention；
- `D=(A,C,sigma_D,Pi_W)` 的决策语义；
- `S_det`；
- workload quotient；
- semantic / deployment-economic 分轨；
- oracle normalization 规则。

它只审查一件事：

> 当前 envelope 的 extended-real codomain 是否把 `+infinity` 的 loss-value semantics 与 finite-loss boundary encoding 压进了同一个对象。

若答案是肯定的，必须先回到 STEP④ 做 typed codomain definition，而不是修改 NECT 来适应语义混合对象。

## 5. Review 的最小候选空间

Typed-codomain review 只允许审查以下三类声明：

### A. Finite-loss codomain

```text
Delta in [0,+infinity)
```

若采用，则 `+infinity` 不进入 target envelope；no-finite-loss 情形必须另行表示为 applicability / realizability boundary。

### B. Ordered extended-loss codomain

```text
Delta in [0,+infinity]
```

若采用，则必须明确：

```text
IPR = LOSS_VALUE
```

即 `+infinity` 是 ordered decision-loss value，而不是 sentinel。

### C. Typed pair / tagged envelope

```text
T in {
  FINITE_LOSS(a),
  ACTUAL_INFINITY_LOSS,
  NO_FINITE_LOSS_MEMBER,
  UNDEFINED
}
```

若采用，则必须定义哪些类型之间允许 order comparison，哪些只允许 realizability transition。

三类之外，不得通过实验结果、estimator 行为或 NECT 通过/失败反推 codomain。

## 6. Current state

```text
IPR_VALUE                       = UNDECLARED
IPR_DECLARATION                 = FAILED
STEP④ TYPED-CODOMAIN REVIEW     = OPEN
STEP⑤ NECT MODE ADJUDICATION    = BLOCKED
STEP⑥                           = NOT ENTERED
RQ                              = NOT ASSIGNED
EXPERIMENT AUTHORIZATION        = NONE
```

下一步只做 STEP④ typed-codomain review；在 `IPR_VALUE` 被可靠声明前，不得裁定 `NECT_E / NECT_F`。

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
