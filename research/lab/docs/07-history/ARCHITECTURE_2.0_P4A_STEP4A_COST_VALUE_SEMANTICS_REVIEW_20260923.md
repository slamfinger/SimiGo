# Architecture 2.0 — P4-A STEP④-A Cost Value Semantics Review

**Date:** 2026-09-23\
**Status:** CVSR COMPLETE / COST VALUE SEMANTICS NOT ESTABLISHED / EVIDENCE RECOVERY NEXT\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮范围

本轮只做证据归类，不补定义。

唯一问题：

```text
STEP①–④ 是否已经存在可追溯的 Cost Value Semantics？
```

不选择 `V_j`，不进入 Risk、`FinLoss`、residual status、NECT 或 STEP⑥。

## 2. Evidence statuses

| Status | Meaning |
|---|---|
| `EXPLICIT` | 冻结文本直接声明 |
| `DERIVABLE` | 由已冻结定义严格推出 |
| `CONTEXTUAL_ONLY` | 仅自然语言、领域习惯、例子或直觉 |
| `ABSENT` | 冻结材料没有相关信息 |

治理规则：

```text
CONTEXTUAL_ONLY != DERIVABLE
```

## 3. Scalar evidence

需要证明：

```text
C_j(a,w) in R
```

或至少：

> 每个 `C_j` 输出单一数值。

当前 MCSC 只有：

```text
C_j : A × W -> V_j
```

而 `V_j` 未确定。

自然语言中的 `cost` / `cost component` 最多说明成本语义角色。

因此：

```text
COST_SCALAR_SEMANTICS = CONTEXTUAL_ONLY
```

## 4. Finite evidence

需要证明：

```text
C_j(a,w) < +infinity
```

当前没有明确 finite-value declaration，也无法从未确定的 `V_j` 严格推出。

此前已冻结：

```text
C_FINITEVALUED = UNDECLARED
```

因此：

```text
COST_FINITE_SEMANTICS = ABSENT
```

## 5. Nonnegative evidence

需要证明：

```text
C_j(a,w) >= 0
```

当前没有对应数学声明。

工程语境中的支出、资源消耗或代价只是领域习惯。

因此：

```text
COST_NONNEGATIVE_SEMANTICS = CONTEXTUAL_ONLY
```

## 6. Extended-real evidence

需要证明：

```text
+infinity in V_j
```

并且 `+infinity` 是实际成本值。

此前已有：

```text
LOSS_INFINITY_PREDEFINED = FALSE
IPR_VALUE = UNDECLARED
```

因此：

```text
COST_INFINITY_SEMANTICS = ABSENT
```

不得用 STEP⑤ 曾出现的 `[0,+infinity]` notation 反向补入 STEP④。

## 7. Vector / record evidence

当前没有声明：

```text
V_j = R^k
```

也没有声明：

```text
V_j = TypedRecord
```

因此：

```text
VECTOR_OR_RECORD_SEMANTICS = ABSENT
```

二者仍是开放候选，而不是已有定义。

## 8. Order evidence

当前 `V_j` 未确定，因此也没有独立的 cost-value order declaration。

NECT 中出现的风险值比较：

```text
R_a < R_b
```

不能反向解释为：

```text
V_j already ordered
```

因此：

```text
COST_VALUE_ORDER = ABSENT
```

## 9. Evidence matrix

| Semantic property | Evidence status |
|---|---|
| Scalar | `CONTEXTUAL_ONLY` |
| Finite | `ABSENT` |
| Nonnegative | `CONTEXTUAL_ONLY` |
| Extended-real | `ABSENT` |
| `+infinity` as loss value | `ABSENT` |
| Vector | `ABSENT` |
| Typed record | `ABSENT` |
| Value-space order | `ABSENT` |

因此：

```text
当前不存在完整、可追溯的 Cost Value Semantics。
```

## 10. Common root

此前分散的缺口：

```text
C_FINITEVALUED = UNDECLARED
COST_SIGNATURE = UNDERDETERMINED
VSPACE = UNDECLARED
FINITE_SCALAR = NOT_DERIVABLE
```

现在统一到一个根源：

```text
COST VALUE SEMANTICS NOT ESTABLISHED
```

因此不应分别随意补：

1. `C` finite；
2. `C` nonnegative；
3. `C` scalar；
4. `C` ordered。

应先处理 cost value semantics 层。

## 11. Ruling

```text
CVSR_STATUS = COMPLETE

COST_VALUE_SEMANTICS = NOT_ESTABLISHED

SCALAR       = CONTEXTUAL_ONLY
FINITE       = ABSENT
NONNEGATIVE  = CONTEXTUAL_ONLY
EXTENDED     = ABSENT
INFINITY     = ABSENT
VECTOR       = ABSENT
RECORD       = ABSENT
ORDER        = ABSENT
```

因此：

```text
V_j cannot be uniquely instantiated from existing STEP①–④ material.
```

## 12. Governance fork

现在出现两条合法路径。

### Path A：Evidence Recovery

如果原始 STEP④ 文本、早期冻结材料或研究基线中已存在成本值语义，只是此前审查遗漏，则应先做 evidence recovery。

### Path B：Minimal New Declaration

如果确认原始材料没有该语义，则必须正式打开：

```text
Cost Value Semantics Declaration
```

由研究者明确决定 `C_j` 的值语义。

在此之前，不触碰具体 `V_j` 候选、`FinLoss` 或 NECT。

## 13. Next review

下一刀只做：

```text
Cost Value-Semantics Evidence Recovery Review
```

唯一问题：

```text
在 STEP①–④ 的原始冻结材料中，
是否存在此前审查遗漏、但足以作为 Cost Value Semantics 的明确证据？
```

若无，才正式承认：

```text
STEP④-A requires a new semantic declaration.
```

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
