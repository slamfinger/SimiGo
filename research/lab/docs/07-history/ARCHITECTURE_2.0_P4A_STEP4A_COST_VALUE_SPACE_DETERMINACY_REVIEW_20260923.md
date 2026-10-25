# Architecture 2.0 — P4-A STEP④-A Cost Value-Space Determinacy Review

**Date:** 2026-09-23\
**Status:** CVSDR COMPLETE / `VSPACE_UNIQUELY_DETERMINED = FALSE` / MINIMAL MISSING DECLARATION NEXT\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮唯一问题

本轮只裁定：

```text
STEP①–④ 的冻结材料是否足以唯一确定 V_j？
```

不讨论 `C_j` 的有限性、definedness、measurability、Risk、oracle、`D_loss`、`FinLoss`、residual status、NECT 或 STEP⑥。

## 2. Audit object

当前 signature 只给出：

```text
C_j   : A × W   -> V_j
C'_j  : A × W_D -> V_j
```

以及 typed equality position：

```text
C_j(a,w) =_{V_j} C'_j(a,sigma_D(w))
```

此前已确认：

1. `V_j` 没有具体 carrier 声明；
2. 没有共享值空间声明；
3. 没有 scalar / vector / record 声明；
4. 没有有限值或扩展实数声明。

## 3. “cost” 不能确定 `V_j`

自然语言中的：

```text
cost / costs / cost component
```

只能确定语义角色：

```text
cost-related object
```

不能逻辑推出：

```text
V_j = R
```

也不能推出：

```text
V_j = [0,+infinity)
```

更不能推出：

```text
V_j = [0,+infinity]
```

原因是：

```text
cost concept != specific mathematical codomain
```

在没有冻结声明时，成本可能被表示为 finite scalar、extended scalar、multidimensional vector、typed record 或其他结构。

## 4. Factorization equality 不能确定 `V_j`

等式：

```text
C_j(a,w) =_{V_j} C'_j(a,sigma_D(w))
```

只要求两侧处于同一个 typed equality context。

它说明：

> 两个 cost component output 必须在同一比较语境中出现。

但它不说明该语境是 `R`、`[0,+infinity)`、`[0,+infinity]`、`R^k` 还是 typed record。

因此：

```text
Equality != Scalarity
Equality != Order
Equality != Finiteness
```

## 5. “cost includes ...” 不能确定 `V_j`

STEP①–④ 中的自然语言提示包括 symbolic recomputation、migration 与 capacity terms。

这些最多支持弱结论：

```text
there exist cost components
```

不能支持：

```text
V_j = R
```

也不能支持：

```text
V_j = [0,+infinity)
```

## 6. 不能从后续 Risk 结构反推

当前合法方向仍是：

```text
C -> R -> R_oracle -> D_loss
```

后续对象尚未完成 definition completion。

因此不能因为预期会有：

```text
D_loss >= 0
```

就反向声称：

```text
C_j in [0,+infinity)
```

该推导属于 semantic backfill，已被治理规则禁止。

## 7. Candidate landscape

以下候选仅登记为 audit candidates，不在本轮选择。

| Candidate | Description | Status |
|---|---|---|
| V1 | finite nonnegative scalar cost | candidate；尚未由冻结材料确定 |
| V2 | extended scalar cost | candidate；但此前 `[0,+infinity]` entitlement 已被拒绝，不得默认复活 |
| V3 | multidimensional cost vector | candidate；尚未由冻结材料确定 |
| V4 | typed cost record | candidate；尚未由冻结材料确定 |
| Other | 其他必要结构 | 可在后续 candidate audit 中登记 |

这些候选没有被证明等价，也没有被冻结材料唯一排序。

## 8. Ruling

```text
VSPACE_UNIQUELY_DETERMINED = FALSE
VALUE_SPACE_TYPE           = UNDECLARED
VALUE_SPACE_ORDER          = UNDECLARED
VALUE_SPACE_FINITE         = UNDECLARED
VALUE_SPACE_EXTENDED       = UNDECLARED
VALUE_SPACE_STRUCTURE      = UNDECLARED
```

关键语义是：

```text
V_j undetermined
  !=
V_j determined but properties unknown
```

当前缺口更靠前：

> 连 `V_j` 的基本 type 都尚未被 STEP①–④ 唯一确定。

## 9. Consequence

合法顺序是：

```text
MCSC
  -> Value-Space Determinacy
  -> FALSE
  -> Minimal Missing Declaration
  -> Value-Space Instantiation
  -> Value Discipline
```

不是：

```text
V_j
  -> “成本当然非负”
  -> [0,+infinity)
```

后者会破坏前述治理链。

## 10. Next review

下一刀为：

```text
Minimal Value-Space Declaration Review
```

唯一问题是：

> 若只允许增加最小语义声明，什么信息是不可再省的？

至少需分层审查：

1. carrier / type；
2. admissible values；
3. order structure。

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
