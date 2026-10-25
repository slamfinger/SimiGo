# Architecture 2.0 — P4-A STEP④-A Cost Value-Semantics Evidence Recovery Review

**Date:** 2026-09-23\
**Status:** CVS-ERR COMPLETE / NO RECOVERABLE EVIDENCE / EVIDENCE RECOVERY FAILED / NEW DECLARATION REQUIRED\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮范围

本轮只检查 STEP①–④ 已冻结正式材料中是否存在可追溯的 Cost Value Semantics 证据。

不提出新的候选值空间，不做数学补定义，不选择 `V_j`，不进入 Risk、`D_loss`、`FinLoss`、residual status、NECT 或 STEP⑥。

## 2. Admission rules

目标命题为：

```text
there exists ECVS such that ECVS implies Cost Value Semantics
```

证据只能来自 STEP①–④ 已冻结正式研究材料。

以下来源不得使用：

1. STEP⑤ 后续 notation；
2. 后续讨论形成的直觉；
3. 工程领域常识；
4. “cost 通常是钱”；
5. 为了让 `FinLoss` 成立而倒推的定义。

## 3. E1：`C_j` definition itself

当前冻结的成本结构核心是：

```text
C_j(a,w) = C'_j(a,sigma_D(w))
```

另有自然语言描述：

> cost includes symbolic recomputation, migration, capacity terms.

这些内容可以支持 `C_j` 承担成本组件评价角色。

但没有声明：

```text
C_j(a,w) in R
```

也没有声明：

```text
C_j(a,w) in [0,+infinity)
```

因此：

```text
CVS-E1 = ROLE EVIDENCE ONLY
```

不能作为 value-space evidence。

## 4. E2：Risk definition

现有形式为：

```text
R(P,theta) = inf over delta E_theta[ C(delta(I_P),W) ]
```

该形式看似已经对 `C` 使用了 expectation、infimum 与后续 risk comparison。

但其出现不能反向确定 `C` 的 codomain。

要严格建立 expectation，仍需声明：

1. measurable structure；
2. integrability 或 extended expectation convention；
3. value-space compatibility。

这些此前均未冻结。

因此：

```text
CVS-E2 = DERIVATION INSUFFICIENT
```

不能从 Risk 反推出：

```text
C in [0,+infinity)
```

## 5. E3：Oracle / `D_loss`

已有：

```text
D_loss(P,theta) = R(P,theta) - R_oracle(theta)
```

这是下游对象链：

```text
C -> R -> D_loss
```

如果 `C` 的 value semantics 尚未确定，则 Risk 与 `D_loss` 的完整数学 well-definedness 也尚未完成。

因此：

```text
CVS-E3 = DOWNSTREAM DEPENDENCY
```

不能反向补语义。

## 6. E4：非负性是否隐藏在 “excess loss” 中

`D_loss` 名称中的 “excess loss” 不构成公理。

此前冻结的是：

```text
D_loss = R - R_oracle
```

而不是已经证明的：

```text
D_loss >= 0
```

即使后续能够证明：

```text
D_loss >= 0
```

也不能直接推出：

```text
C_j >= 0
```

因此：

```text
CVS-E4 = NO COST-VALUE EVIDENCE
```

## 7. E5：`+infinity`

此前 IPR review 已有：

```text
LOSS_INFINITY_PREDEFINED = FALSE
IPR_VALUE = UNDECLARED
```

因此 STEP①–④ 没有合法证据证明 `+infinity` 是一个成本值。

STEP⑤ 曾出现 extended-real envelope 形式，但不能回写 STEP①–④。

因此：

```text
CVS-E5 = ABSENT
```

## 8. Evidence recovery table

| Evidence route | Can it determine Cost Value Semantics? |
|---|---|
| `C_j` cost-component definition | No；role evidence only |
| `C_j = C'_j ∘ sigma_D` | No；structural evidence only |
| Risk | No；downstream dependency |
| Oracle | No；downstream dependency |
| `D_loss` | No；downstream dependency |
| “excess loss” name | No |
| STEP⑤ extended-real notation | Forbidden retroactive source |
| `+infinity` | No frozen `LOSS_VALUE` evidence |

## 9. Final ruling

```text
CVS_ERR                            = COMPLETE
COST_VALUE_SEMANTICS_EVIDENCE      = NOT_FOUND
EVIDENCE_RECOVERY                  = FAILED
COST_VALUE_SEMANTICS               = NOT_ESTABLISHED
NEW_DECLARATION_REQUIRED           = TRUE
```

这里的 `FAILED` 指 evidence recovery 未找到可恢复证据，不是研究流程执行失败。

该结果的意义是：

> 这不是暂时没有找到，而是对 STEP①–④ 冻结材料完成证据恢复后，仍不存在足以确定 `V_j` 的既有声明。

## 10. Consequence

继续审查候选已经没有意义。

正式进入：

```text
STEP④-A Minimal Cost Value-Semantics Declaration
```

但该 declaration 不得由 agent 或 notation 自动填写。

## 11. Current state

```text
CVS_ERR                            = COMPLETE
COST_VALUE_SEMANTICS_EVIDENCE      = NOT_FOUND
EVIDENCE_RECOVERY                  = FAILED
COST_VALUE_SEMANTICS               = NOT_ESTABLISHED
NEW_DECLARATION_REQUIRED           = TRUE
VALUE_DISCIPLINE                   = BLOCKED
STEP4_B_RISK_REVIEW                = BLOCKED
FINLOSS_DETERMINACY                = BLOCKED
RESIDUAL_STATUS                    = BLOCKED
NECT_MODE                          = BLOCKED
STEP⑥                              = NOT ENTERED
RQ                                 = NOT ASSIGNED
EXPERIMENT AUTHORIZATION           = NONE
```

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
