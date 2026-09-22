# Architecture 2.0 — P4-A STEP④-A Minimal Value-Space Declaration Review

**Date:** 2026-09-23\
**Status:** MVSD COMPLETE / MINIMAL REQUIRED DECLARATION = CARRIER-TYPE FAMILY / NO SPECIFIC `V_j` SELECTED\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮范围

本轮只回答：

```text
要使 V_j 从 UNDECLARED 变成 DETERMINATE，
最少必须声明什么？
```

不选择 `V_j` 的具体 carrier，不选择 value discipline，不声明 order，不引入 measurability、definedness、finiteness、Risk、`D_loss`、`FinLoss`、residual status、NECT 或 STEP⑥。

## 2. Background

CVSDR 已裁定：

```text
VSPACE_UNIQUELY_DETERMINED = FALSE
```

原因不是 `V_j` 的某些性质尚待测量，而是 STEP①–④ 没有唯一确定 `V_j` 的基本 type。

当前 signature 位置为：

```text
C_j   : A × W   -> V_j
C'_j  : A × W_D -> V_j
```

因此，最小 declaration 必须先说明这些 target positions 的 carrier/type。

## 3. Three separate layers

### L1 Carrier / Type

回答：

```text
cost output 是什么 type 的对象？
```

这是使 `V_j` determinate 的最小层。

### L2 Admissible Values / Value Discipline

回答：

```text
carrier 中哪些值允许作为 cost output？
```

这不是 carrier 本身。

### L3 Order

回答：

```text
两个 cost output 是否可比较，以及按什么规则比较？
```

这也不是 carrier 本身。

因此：

```text
Carrier != Value Discipline != Order
```

## 4. Carrier 与 order 的关系

声明 carrier 后，不会自动得到 order。

即使未来声明某 carrier 的底层符号与常见数学对象同名，也必须显式声明该 carrier 是否带有：

1. order；
2. order direction；
3. partial/total order；
4. comparison-compatible equality；
5. monotone operations。

当前 P4-A 尚未建立可继承这些结构的 global formal basis。

## 5. Carrier 与 value discipline 的区别

假设未来声明：

```text
C_j : A × W -> R
```

这属于 carrier declaration。

如果再声明：

```text
C_j(a,w) in [0,+infinity)
```

这属于 admissible-value discipline。

二者可写成：

```text
C_j : A × W -> R
Im(C_j) subset [0,+infinity)
```

也可等价地写成：

```text
C_j : A × W -> [0,+infinity)
```

但二者在 declaration responsibility 上不同：

1. 前者显式区分 carrier 与 admitted-image restriction；
2. 后者把 restriction 折叠进 codomain；
3. 不得在未声明顺序的情况下静默互换。

## 6. Minimal declaration levels

### MVSD-1

```text
declare carrier/type family (V_j)_{j in J}
```

这是使 `V_j` determinate 的最小条件。

### MVSD-2

```text
declare carrier/type family
and admissible value discipline A_j subset V_j
```

这已经进入 Value Discipline。

### MVSD-3

```text
declare carrier/type family,
admissible value discipline,
and order structure <=_{V_j}
```

这是完整 cost-value semantic layer，但超过当前 MVSD 的最小要求。

## 7. Ruling

```text
MINIMAL_VALUE_SPACE_DECLARATION =
  CARRIER / TYPE FAMILY DECLARATION
```

同时冻结分层：

```text
VALUE_DISCIPLINE  = SEPARATE LAYER
ORDER_STRUCTURE   = SEPARATE LAYER
MEASURABILITY     = SEPARATE LAYER
FINITEVALUEDNESS  = SEPARATE LAYER
DEFINEDNESS       = SEPARATE LAYER
```

本轮不选择：

1. finite scalar；
2. extended scalar；
3. vector；
4. typed record；
5. shared value space；
6. per-component heterogeneous value spaces；
7. specific admissible subset；
8. specific order。

## 8. Anti-backflow rule

未来若决定：

```text
V_j = [0,+infinity)
```

必须记录这是一次新的：

```text
Value-Space Instantiation
```

不得声称它由 “cost” 一词自动推出。

未来若决定：

```text
V_j = [0,+infinity]
```

还必须重新面对此前 IPR review 对 extended-loss entitlement 的拒绝；MVSD 本身不重开也不裁定 IPR。

## 9. Current state

```text
MVSD_REVIEW                    = COMPLETE
VSPACE_UNIQUELY_DETERMINED     = FALSE
MINIMAL_REQUIRED_DECLARATION   = CARRIER / TYPE FAMILY
CARRIER_TYPE_DECLARATION       = ABSENT
VALUE_DISCIPLINE               = SEPARATE LAYER / UNDECLARED
ORDER_STRUCTURE                = SEPARATE LAYER / UNDECLARED
MEASURABILITY                  = SEPARATE LAYER / UNDECLARED
FINITEVALUEDNESS               = SEPARATE LAYER / UNDECLARED
DEFINEDNESS                    = SEPARATE LAYER / UNDECLARED
NO_SPECIFIC_V_J_SELECTED       = TRUE
NEXT_REVIEW                    = VALUE-SPACE CANDIDATE AUDIT
STEP4_B_RISK_REVIEW            = BLOCKED
FINLOSS_DETERMINACY            = BLOCKED
RESIDUAL_STATUS                = BLOCKED
NECT_MODE                      = BLOCKED
STEP⑥                          = NOT ENTERED
RQ                             = NOT ASSIGNED
EXPERIMENT AUTHORIZATION       = NONE
```

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
