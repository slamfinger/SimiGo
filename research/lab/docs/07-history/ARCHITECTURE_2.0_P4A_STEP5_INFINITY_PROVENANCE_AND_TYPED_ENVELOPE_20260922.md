# Architecture 2.0 — P4-A STEP⑤ Infinity Provenance 与 Typed Envelope

**Date:** 2026-09-22\
**Status:** STEP⑤ OPEN / NDAC ACCEPTED / SAT_INF_FIN DEFINED / IPR REQUIRED / NECT MODE OPEN\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮边界

本轮不裁定 `NECT_E` 或 `NECT_F`。

先拆一个更底层的问题：

```text
envelope 中的 +infinity
是 loss value，还是 finite-loss feasibility boundary 的 encoding？
```

若二者在同一 envelope 中共存，是否必须作语义区分？

结论是：**不能让同一个 `+infinity` 符号静默承载两种语义。**

## 2. 三个不同 domain

固定 scope `s` 后，已有 reachable domain：

```text
R_s = { R : P_s(R) != emptyset }
```

再显式定义 finite-loss domain：

```text
R_s^fin
  = { R in R_s :
      exists P in P_s(R)
      such that Delta_s(P; theta) < +infinity }
```

以及 no-finite-loss region：

```text
R_s^nofin = R_s \ R_s^fin
```

若 `F_s(R)=+infinity`，则必有：

```text
R in R_s^nofin
```

但这个等式只说明没有 finite-loss 成员，不说明 `+infinity` 的语义身份。

## 3. Infinity provenance rule

NECT mode 裁定前，frame 必须声明：

```text
IPR(R) in {
  LOSS_VALUE,
  BOUNDARY_ENCODING,
  MIXED,
  NA
}
```

| Provenance | 含义 | NECT 可用性 |
|---|---|---|
| `LOSS_VALUE` | `+infinity` 是冻结成本族给出的 ordered extended-real loss value | 可作为 `NECT_E` 候选对象 |
| `BOUNDARY_ENCODING` | `+infinity` 只是 “no finite-loss member” 的 sentinel，不是 loss magnitude | 不得直接与 finite loss 作 `<` 比较 |
| `MIXED` | 同一 envelope 中两种用法共存 | raw `F_s` 不是单一语义对象，必须先 typed split |
| `NA` | evaluation failure / missing data / undefined object | 不是 loss，必须移出 target envelope |

`IPR` 必须属于 frame-level 预注册语义，不能在看到 descent 结果后选择。

## 4. Typed envelope

如果 `IPR=MIXED`，raw：

```text
F_s : R_s -> [0,+infinity]
```

不再是 NECT 的合法定义对象。必须先拆成不同类型，例如：

```text
T_s(R) in {
  FINITE_LOSS(a),
  ACTUAL_INFINITY_LOSS,
  NO_FINITE_LOSS_MEMBER,
  UNDEFINED
}
```

其中：

1. `FINITE_LOSS(a)` 中的 `a` 是 ordered finite loss；
2. `ACTUAL_INFINITY_LOSS` 是 ordered extended-real loss value；
3. `NO_FINITE_LOSS_MEMBER` 是 finite-realizability boundary tag，不是可与 finite number 直接比较的 loss magnitude；
4. `UNDEFINED` 不属于 target envelope。

由此可派生一个独立的 finite-realizability indicator：

```text
B_s^fin(R)
  = 1, if R in R_s^fin
  = 0, otherwise
```

`B_s^fin(Ra)=0` 到 `B_s^fin(Rb)=1` 是 finite-loss realizability onset。它是一个候选语义对象，但不得在未裁定前静默并入 NECT。

## 5. 对 `+infinity -> finite` 的约束

只有当 `Ra` 处的 `+infinity` 满足：

```text
IPR(Ra) = LOSS_VALUE
```

时，才有合法的 extended-real comparison：

```text
F_s(Rb) < F_s(Ra)
```

若 `IPR(Ra)=BOUNDARY_ENCODING`，则：

```text
finite loss < boundary sentinel
```

是 category error，不是 NECT 的 strict descent。

若 `IPR=MIXED`，必须先 typed split。否则两个不同现象会被压进同一个谓词：

1. ordered loss下降；
2. finite-loss realizability onset。

## 6. 对 NECT mode 的影响

### 6.1 若全帧声明 `LOSS_VALUE`

则 `NECT_E` 有清晰对象：

```text
F_s : R_s -> [0,+infinity]
```

其中 `+infinity` 真正参与 order。

此时 `+infinity -> finite` 是 extended-real strict descent 候选。

### 6.2 若全帧声明 `BOUNDARY_ENCODING`

则 `+infinity` 不是 loss magnitude。

研究对象应显式转向：

```text
finite-loss domain transition
```

或只使用 finite-loss region：

```text
R_s^fin
```

此时 `NECT_F` 是自然候选，但尚未裁定。

### 6.3 若 `MIXED`

必须先定义 typed envelope，不能直接裁定 `NECT_E / NECT_F`。

否则 NECT 的 “nontrivial phenomenon” 会同时混合 loss descent 与 realizability transition，破坏对象身份。

## 7. Governance consequence

STEP④ 已冻结 loss codomain `[0,+infinity]`，但这不自动声明 `+infinity` 的 provenance。

因此 STEP⑤ 当前新增一个模式裁定前置条件：

```text
IPR_DEFINED
```

若当前 frame 无法声明 `IPR`，则不得在 STEP⑤ 强行选择 NECT mode；应回到 STEP④ 的 envelope object definition 审查 typed codomain，而不是事后改写 estimand。

## 8. 当前状态

已冻结本轮边界：

1. `R_s`、`R_s^fin`、`R_s^nofin` 必须分开；
2. `+infinity` 必须声明 `LOSS_VALUE`、`BOUNDARY_ENCODING`、`MIXED` 或 `NA`；
3. `MIXED` 必须先 typed split；
4. `NA` 不属于 target envelope；
5. finite-loss realizability onset 不得静默并入 NECT。

当前状态保持：

```text
STEP⑤ OPEN
NDAC ACCEPTED
SAT_INF_FIN DEFINED
IPR REQUIRED
NECT MODE OPEN
RQ NOT ASSIGNED
NO EXPERIMENT AUTHORIZATION
```

不推进 STEP⑥。

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
