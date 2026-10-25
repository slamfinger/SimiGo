# Architecture 2.0 — P4-A STEP④-A Cost Object Audit

**Date:** 2026-09-23\
**Status:** STEP④-A OPEN / COST OBJECT INCOMPLETE / C CODOMAIN-MEASURABILITY-FINITENESS UNDERDECLARED\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮范围

本轮只审查 cost object：

```text
C / C_j / C'_j
```

的：

1. signature 与 codomain；
2. measurability 条件；
3. finiteness / value discipline。

不审查 expectation、Bayes risk、oracle risk、excess loss、`FinLoss`、residual domain、Candidate 1/3 或 NECT。

## 2. Source audit

当前冻结文本给出：

```text
D = (A, C, Pi_W)
```

其中 `C` 是 declared cost function，包含 symbolic recomputation、migration 与 capacity terms。

STEP④ 又使用成本族形式：

```text
for all j,a,w:
  C_j(a,w) = C'_j(a,sigma_D(w))
```

由此可确认的事实只有：

| 对象 | 当前状态 |
|---|---|
| 存在一个 cost family，索引为 `j` | 已使用 |
| 存在与 workload / outcome 相关的参数 `w` | 已使用 |
| 存在 action 参数 `a` | 已使用 |
| `C_j` 与 `C'_j` 的 exact domain | 未声明 |
| index set `J` | 未声明 |
| `C_j` / `C'_j` 的 codomain | 未声明 |
| 各 cost term 是否合成 scalar / vector / typed record | 未声明 |
| 相关 measurable spaces | 未声明 |
| `C_j` / `C'_j` 是否 measurable | 未声明 |
| `C_j` / `C'_j` 是否 pointwise finite | 未声明 |
| factorization equality 所在 value space | 仅隐含 |

“包含 symbolic recomputation、migration 与 capacity terms”是语义提示，不是 formal codomain 或 value discipline。

## 3. Codomain 裁定

```text
C_COST_CODEMAIN = UNDECLARED
```

factorization identity：

```text
C_j(a,w) = C'_j(a,sigma_D(w))
```

要求两侧可以在同一个 value space 中比较 equality，但没有声明该 value space 是：

```text
[0,+infinity)
```

还是：

```text
R
```

还是 vector-valued cost，还是 typed cost record。

因此，不能从当前 frame 推出 `C_j` 是 finite scalar cost。也不能因为后续 Bayes risk 期望使用 `C(...)` 而倒推它必须是实数。

## 4. Measurability 裁定

```text
C_MEASURABILITY = UNDERDECLARED
```

为使后续 Risk review 可能成立，最终至少需要声明：

1. outcome/workload space `W` 上的 sigma-algebra；
2. action space `A` 上的 sigma-algebra 或 discreteness/finite-set status；
3. product measurable structure；
4. `C_j` 与 `C'_j` 相对该结构是否 measurable；
5. `sigma_D` 是否 measurable。

其中第 5 项虽涉及 `sigma_D`，但这里是 factorized cost object 的 signature 一部分；不展开审查 expectation。

若未来声明相关空间 finite/discrete，则 measurability 可以变得 trivial，但仍必须显式声明该空间性质。

## 5. Finiteness / value discipline 裁定

```text
C_FINITEVALUED        = UNDECLARED
C_VALUE_DISCIPLINE    = UNDECLARED
```

当前不能宣称：

```text
for all j,a,w:
  C_j(a,w) is finite
```

也不能宣称 `C_j` 只取非负值。

Candidate 2 已被拒绝，因此不得把 `+infinity` 静默用作 loss value。但这不自动决定 raw cost object 必须是 finite scalar；它只禁止未经 STEP④ review 引入 extended-loss semantics。

## 6. STEP④-A 关闭条件

STEP④-A 只有在以下最小声明完成后才可关闭：

1. `J` 与每个 cost component 的身份；
2. 每个 `C_j` 的 domain；
3. 每个 `C'_j` 的 domain；
4. `C_j` 与 `C'_j` 的共同 codomain；
5. relevant measurable spaces；
6. `C_j` / `C'_j` / `sigma_D` 的 measurability status；
7. pointwise value discipline；
8. factorization equality 在该 codomain 中成立。

这些声明完成后，才可进入 STEP④-B Risk Well-definedness。

## 7. Current state

```text
C_OBJECT_COMPLETE             = FALSE
C_SIGNATURE                   = UNDERDECLARED
C_COST_CODEMAIN               = UNDECLARED
C_MEASURABILITY               = UNDERDECLARED
C_FINITEVALUED                = UNDECLARED
C_FACTORIZATION_VALUE_SPACE   = IMPLICIT ONLY
STEP4_B_RISK_REVIEW           = BLOCKED
FINLOSS_DETERMINACY           = BLOCKED
RESIDUAL_STATUS               = BLOCKED
NECT_MODE                     = BLOCKED
STEP⑥                         = NOT ENTERED
RQ                            = NOT ASSIGNED
EXPERIMENT AUTHORIZATION      = NONE
```

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
