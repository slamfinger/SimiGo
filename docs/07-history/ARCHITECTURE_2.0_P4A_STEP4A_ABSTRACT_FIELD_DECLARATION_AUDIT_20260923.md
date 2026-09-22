# Architecture 2.0 — P4-A STEP④-A Abstract Field Declaration Audit

**Date:** 2026-09-23\
**Status:** STEP④-A OPEN / ABSTRACT FIELD SCHEMA ADOPTED / FORMAL ARROW-PRODUCT SEMANTICS OPEN / VALUE DISCIPLINE DEFERRED / STEP④-B BLOCKED\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮范围

本轮只审查 MCSC 的 abstract field declarations：

```text
J, A, W, W_D, V_j,
C_j, sigma_D, C'_j,
typed equality, Binding_C
```

裁定它们需要哪些最小形式约束。

本轮不选择 value discipline，不声明 measurability，不审查 expectation/risk/oracle/`D_loss`，不裁定 residual status、Candidate 1/3 或 NECT。

## 2. 核心区分

```text
well-formed abstract signature schema
  !=
semantically instantiated cost object
```

MCSC 现在只能作为 abstract field schema 成立。它还没有给出一个完整 cost object。

因此，字段可以只声明 formal position；其具体数学语义仍可 open。

## 3. Minimal formal constraints adopted

以下约束仅针对 signature schema 本身。

### 3.1 Field distinctness

```text
J, A, W, W_D, V_j,
C_j, sigma_D, C'_j,
equality_j, Binding_C
```

是不同 formal positions。不得未经显式 declaration 将它们等同、合并或互相推导。

### 3.2 J-indexing

`V_j`、`C_j`、`C'_j` 是 `J`-indexed families。

这表示每个 `j:J` 有自己的 value-space symbol 与 function position。

不假设：

1. `J` 非空；
2. `J` finite 或 countable；
3. 不同 `j` 的语义 component 必然不同；
4. 相同语义 component 不能出现在不同 index 下。

semantic component 的唯一性属于后续 instantiation / binding review。

### 3.3 Carrier positions

`A`、`W`、`W_D` 是 carrier/type positions。

只要求有稳定的 typing position，例如：

```text
a:A
w:W
w_D:W_D
```

不要求：

1. 非空；
2. finite/countable；
3. sample-space semantics；
4. state-space semantics；
5. topology；
6. sigma-algebra；
7. specific product representation。

`W_D` 是 `sigma_D` 的 target carrier。它与 `W` 的关系当前只能通过 `sigma_D : W -> W_D` 这个 signature position 表达；不假设 `W_D=W`、quotient、surjection、injection 或 any canonical map。

### 3.4 Value-space positions

`V_j` 是 per-index abstract value carrier family。

不假设：

1. 所有 `V_j` 相同；
2. 存在 shared value space；
3. `V_j` 是 scalar/vector/record；
4. `V_j` finite、nonempty、ordered 或 extended；
5. 不同 `V_j` 之间存在 coercion。

typed equality field 也是一个 formal position：

```text
equality_j
```

它属于 `V_j` 内部。不同 `V_j` 之间没有默认 equality 或 comparison。

`equality_j` 的具体 notion 仍然 deferred。

### 3.5 Function positions

当前保留三个 function positions：

```text
C_j   : A × W     -> V_j
sigma_D : W       -> W_D
C'_j  : A × W_D   -> V_j
```

这只冻结 argument/codomain positions。

不假设：

1. total 或 partial；
2. continuous；
3. measurable；
4. finite-valued；
5. nonnegative；
6. computable；
7. definable by a closed formula；
8. injective/surjective。

## 4. New formal gaps found

为了读出：

```text
A × W
A × W_D
```

与：

```text
-> V_j
```

还需要分别声明两个 formal semantics：

```text
PRODUCT_POSITION_SEMANTICS = UNDERDECLARED
ARROW_SEMANTICS             = UNDERDECLARED
```

### 4.1 Product position

`A × W` 与 `A × W_D` 目前只是 formal domain positions。

尚未声明它们是：

1. set-theoretic product；
2. type-theoretic product；
3. record/product type；
4. formal pairing constructor；
5. shared product 或 per-index product。

### 4.2 Arrow position

箭头当前只表示“从 source position 到 target position 的 function slot”。

尚未声明：

1. total function；
2. partial function；
3. multivalued arrow；
4. relation-valued arrow；
5. partiality 是否需要显式 marker。

这些问题属于 formal signature completion，不是 value discipline。

## 5. Field-by-field ruling

| Field | Abstract declaration | Still open |
|---|---|---|
| `J` | abstract index carrier | membership rule、nonemptiness、cardinality、component-boundary semantics |
| `A` | first cost-input carrier | carrier instantiation、action semantics、nonemptiness |
| `W` | raw cost-input carrier | carrier instantiation、world/input semantics、nonemptiness |
| `W_D` | factorized cost-input carrier | relation to `W`、carrier instantiation |
| `V_j` | per-index value carrier | value discipline、equality notion |
| `C_j` | raw-cost function position | arrow semantics、function definition |
| `sigma_D` | factorization map position | arrow semantics、map definition |
| `C'_j` | factorized-cost function position | arrow semantics、function definition |
| `equality_j` | per-`V_j` typed equality position | equality notion |
| `Binding_C` | required reserved binding field between `C` and `(C_j)_j` | formal kind、definition |

## 6. 裁定

```text
ABSTRACT_FIELD_SCHEMA               = WELL_FORMED AS PLACEHOLDER SCHEMA
MINIMAL_FORMAL_CONSTRAINTS_ADOPTED  = YES
SUBSTANTIVE_STRUCTURAL_CONSTRAINTS  = NONE
PRODUCT_POSITION_SEMANTICS          = UNDERDECLARED
ARROW_SEMANTICS                     = UNDERDECLARED
EQUALITY_NOTION                     = DEFERRED
BINDING_C_KIND                      = UNDERDECLARED
SEMANTIC_INSTANTIATION              = OPEN
VALUE_DISCIPLINE                    = DEFERRED
MEASURABILITY                       = DEFERRED
STEP4_B_RISK_REVIEW                 = BLOCKED
FINLOSS_DETERMINACY                 = BLOCKED
RESIDUAL_STATUS                     = BLOCKED
NECT_MODE                           = BLOCKED
STEP⑥                               = NOT ENTERED
RQ                                  = NOT ASSIGNED
EXPERIMENT AUTHORIZATION            = NONE
```

结论：

> MCSC 不需要现在添加 substantive structural constraints；但它必须先声明 product-position semantics 与 arrow semantics，才能从 abstract schema 变成 closed signature。

## 7. Next formal step

下一步仍属 STEP④-A，只处理两个 formal gaps：

1. `PRODUCT_POSITION_SEMANTICS`；
2. `ARROW_SEMANTICS`。

不进入 Cost Value Discipline，不进入 Risk Well-definedness，不进入 residual status，不进入 NECT。

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
