# Architecture 2.0 — P4-A STEP④-A Value-Space Candidate Audit

**Date:** 2026-09-23\
**Status:** VSCA COMPLETE / NO CANDIDATE SELECTED / FINITE SCALAR NOT DERIVABLE / EXTENDED SCALAR REJECTED\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮范围

本轮只做 candidate admissibility audit：

```text
STEP①–④ 是否有冻结证据足以支持或排除某个 V_j 候选？
```

不选择最终 `V_j`，不审查 `C_j` 的 definedness、measurability 或 Risk，不进入 `FinLoss`、residual status、NECT 或 STEP⑥。

## 2. Candidate A：finite scalar

候选：

```text
V_j = [0,+infinity)
```

该候选至少包含三个独立语义承诺：

| Promise | Status |
|---|---|
| scalar | `NOT_ESTABLISHED` |
| finite | `NOT_ESTABLISHED` |
| nonnegative | `NOT_ESTABLISHED` |

因此：

```text
V_j = [0,+infinity) = NOT_DERIVABLE / OPEN
```

注意：

```text
NOT_DERIVABLE != REJECTED
```

该候选仍可作为未来语义实例化方向。

## 3. Candidate B：extended scalar

候选：

```text
V_j = [0,+infinity]
```

它至少要求：

1. scalar；
2. nonnegative；
3. extended-valued；
4. `+infinity` 具有成本值语义。

前三项没有充分冻结依据。

第四项与既有裁定冲突：

```text
IPR_VALUE = UNDECLARED
LOSS_INFINITY_PREDEFINED = FALSE
```

因此：

```text
V_j = [0,+infinity] = REJECTED_IN_CURRENT_FRAME
```

这不是说扩展实数在数学上不可用，而是当前冻结语义没有授权 `+infinity` 作为成本值。

## 4. Candidate C：vector

候选示例：

```text
V_j = R^k
```

当前材料没有要求 `k > 1`，也没有冻结多个必须保留为不可聚合向量的成本维度。

因此：

```text
VECTOR = OPEN CANDIDATE
```

但不得默认向量之间存在聚合规则。

## 5. Candidate D：typed record

候选示例：

```text
V_j = TypedCostRecord
```

当前成本描述包含不同语义层面的信息，但未冻结这些信息属于 `C_j` 的输出值，而非 cost object 的定义、输入或 metadata。

因此：

```text
TYPED_RECORD = OPEN CANDIDATE
```

## 6. Candidate E：other

当前不能声明候选集穷尽。

因此：

```text
CANDIDATE_EXHAUSTIVENESS = NOT_ESTABLISHED
OTHER = OPEN
```

## 7. Candidate matrix

| Candidate | Status | Reason |
|---|---|---|
| `[0,+infinity)` finite scalar | `NOT_DERIVABLE / OPEN` | scalar、finite、nonnegative 均未冻结 |
| `[0,+infinity]` extended scalar | `REJECTED_IN_CURRENT_FRAME` | `+infinity` 尚无 loss-value semantics |
| vector | `OPEN` | 未被要求，也未被排除 |
| typed record | `OPEN` | 未被要求，也未被排除 |
| other | `OPEN` | 候选集本身未证明穷尽 |

## 8. Core result

```text
VSCA = COMPLETE

FINITE_SCALAR          = NOT_DERIVABLE / OPEN
EXTENDED_SCALAR        = REJECTED_IN_CURRENT_FRAME
VECTOR                 = OPEN
TYPED_RECORD           = OPEN
OTHER                  = OPEN

CANDIDATE_EXHAUSTIVENESS = NOT_ESTABLISHED
```

之前的 Candidate 1 状态不变：

```text
CONDITIONAL / NOT CHOSEN
```

## 9. Next gate

下一刀只做：

```text
Finite-Scalar Admissibility Review
```

分别审查：

```text
Scalar(C_j)
Finite(C_j)
Nonnegative(C_j)
```

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
