# Architecture 2.0 — P4-A STEP④-A Cost Signature Determinacy Audit

**Date:** 2026-09-23\
**Status:** STEP④-A OPEN / COST SIGNATURE NOT DETERMINED / VALUE DISCIPLINE DEFERRED / STEP④-B BLOCKED\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮唯一问题

本轮只裁定：

```text
冻结的 STEP①–④ semantics 是否足以唯一确定
Sig(C, C_j, C'_j, sigma_D)？
```

不裁定 `V_j` 的具体 value discipline，不裁定 measurability，不审查 expectation、Bayes risk、oracle risk、`D_loss`、`FinLoss`、residual status、Candidate 1/3 或 NECT。

## 2. Cost signature contract

Cost signature 与 value discipline 分离。signature 至少必须固定以下字段：

```text
J
A
W
W_D

for each j in J:
  V_j
  C_j : A × W  -> V_j
  sigma_D : W -> W_D
  C'_j : A × W_D -> V_j
  equality notion on V_j

C-to-(C_j) binding
```

其中：

1. `J` 是 cost component index set；
2. `A` 是 action argument carrier/domain；
3. `W` 是 raw workload/outcome argument carrier/domain；
4. `W_D` 是 factorized workload/outcome argument carrier/domain；
5. `V_j` 是第 `j` 个 cost value space；
6. equality 必须说明在哪个 `V_j` 中成立；
7. `C` 与成本族 `(C_j)` 的 binding 必须显式声明。

以上是 signature fields。它们不预设 `V_j` 是 finite scalar、extended scalar、vector 或 typed record，也不预设 measurability。

## 3. Source audit

当前冻结文本给出的只有：

```text
D = (A, C, Pi_W)
```

以及：

```text
for all j,a,w:
  C_j(a,w) = C'_j(a,sigma_D(w))
```

另有自然语言提示：cost 包括 symbolic recomputation、migration 与 capacity terms。

逐项审计：

| Signature field | 当前状态 |
|---|---|
| `J` | 只有自然语言 component hints；index set 未确定 |
| `A` | 符号已出现；carrier/domain 未声明 |
| `W` | 符号已出现；carrier/domain 未声明 |
| `W_D` | 未出现；factorized target space 未声明 |
| `V_j` | 未声明 |
| `C_j` | 在 identity 中被使用；函数对象未声明 |
| `sigma_D` | minimal witness 名称已冻结；source/target carrier 与 map 未声明 |
| `C'_j` | 在 identity 中被使用；函数对象未声明 |
| equality space | 仅隐含 |
| `C` 与 `(C_j)` 的 binding | 未声明 |

“symbolic recomputation / migration / capacity”只是 semantic hints。它们不能自动变成：

```text
J = { recomputation, migration, capacity }
```

因为这些 term 的边界、粒度、是否独立成项、是否可继续分解，均未由冻结文本确定。

## 4. Non-uniqueness

至少有以下不同 signature 均与当前冻结文本兼容。

### Completion S1

```text
J = {1}
A, W, W_D 为 abstract carriers
V_1 为 abstract value space
C_1 : A × W -> V_1
sigma_D : W -> W_D
C'_1 : A × W_D -> V_1
```

这把全部 cost 内容视为一个 component。

### Completion S2

```text
J = {recomputation, migration, capacity}
```

并为每个 component 分别给定 abstract：

```text
A_j, W_j, W_Dj, V_j
```

以及：

```text
C_j, sigma_Dj, C'_j
```

这与自然语言提示更接近，但当前文本并未证明它唯一正确。

### Completion S3

还可将某个自然语言 term 再拆分。例如 capacity 可能包含 capacity amount、capacity pressure 或 capacity penalty 等不同 aspect。

当前文本没有给出停止拆分的 formal criterion。

因此：

```text
COST_SIGNATURE_UNIQUELY_DETERMINED = FALSE
```

## 5. Field status

```text
SIG_C_DETERMINED            = FALSE
J                           = HINT ONLY / NOT DETERMINED
A                           = SYMBOL ONLY / CARRIER UNDERDECLARED
W                           = SYMBOL ONLY / CARRIER UNDERDECLARED
W_D                         = ABSENT
V_J                         = ABSENT
C_J                         = SYMBOL ONLY / FUNCTION UNDERDECLARED
SIGMA_D                     = SYMBOL ONLY / SIGNATURE UNDERDECLARED
C_PRIME_J                   = SYMBOL ONLY / FUNCTION UNDERDECLARED
EQUALITY_SPACE              = IMPLICIT ONLY
C_TO_COST_FAMILY_BINDING    = ABSENT
```

## 6. Deferred layer

以下判断全部 deferred，不在本轮裁定：

```text
FINITE_SCALAR
EXTENDED_SCALAR
VECTOR
TYPED_RECORD
UNDECLARED
```

不得因为后续 expectation 似乎需要 scalar，就倒推 `V_j` 是 finite scalar。

measurable-space layer 也 deferred。必须先完成 signature carrier/domain declaration，再声明 sigma-algebras 与 measurability。

## 7. STEP④-A closure path

STEP④-A signature stage 只有在显式声明以下内容后才可关闭：

1. `J` 与每个 component 的身份边界；
2. 共享或 per-component 的 `A`；
3. 共享或 per-component 的 `W`；
4. 每个 component 的 `W_D`；
5. 每个 component 的 `V_j` 符号与 equality notion；
6. 每个 `C_j`；
7. 每个 `sigma_D`；
8. 每个 `C'_j`；
9. `C` 与 `(C_j)` 的 binding。

完成后才进入 Cost Value Discipline。仍不得直接进入 STEP④-B Risk Well-definedness。

## 8. Current state

```text
COST_SIGNATURE_UNIQUELY_DETERMINED = FALSE
COST_SIGNATURE                     = UNDERDECLARED
J                                  = NOT DETERMINED
A                                  = CARRIER UNDERDECLARED
W                                  = CARRIER UNDERDECLARED
W_D                                = ABSENT
V_J                                = ABSENT
C_J                                = FUNCTION UNDERDECLARED
SIGMA_D_SIGNATURE                  = UNDERDECLARED
C_PRIME_J                          = FUNCTION UNDERDECLARED
EQUALITY_SPACE                     = IMPLICIT ONLY
C_BINDING                          = ABSENT
VALUE_DISCIPLINE                   = DEFERRED
MEASURABILITY                      = DEFERRED
STEP4_B_RISK_REVIEW                = BLOCKED
FINLOSS_DETERMINACY                = BLOCKED
RESIDUAL_STATUS                    = BLOCKED
NECT_MODE                          = BLOCKED
STEP⑥                              = NOT ENTERED
RQ                                 = NOT ASSIGNED
EXPERIMENT AUTHORIZATION           = NONE
```

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
