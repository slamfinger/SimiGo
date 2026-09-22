# Architecture 2.0 — P4-A STEP④ Finite Completeness 与 Boundary Status Audit

**Date:** 2026-09-22\
**Status:** STEP④ REVIEW OPEN / ENVELOPE FINITE COMPLETENESS NOT ESTABLISHED / BOUNDARY STATUS UNRESOLVED / NECT MODE BLOCKED\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮范围

本轮只完成两项审查：

1. 当前 frame 是否已经保证 envelope finite completeness；
2. 若存在 no-finite-loss region，它应属于 applicability boundary，还是当前 frame 必须表示的对象。

不裁定 Candidate 1 / Candidate 3，不裁定 `NECT_E / NECT_F`，不进入 STEP⑥。

## 2. 定义

固定 scope `s` 后：

```text
P_s(R) = { P in S_det : Rate_X(P) <= R }

R_s    = { R : P_s(R) != emptyset }
```

再定义 finite-loss subproblem：

```text
P_s^fin(R)
  = { P in P_s(R) :
      Delta_s(P; theta) is defined and finite }

R_s^fin
  = { R in R_s : P_s^fin(R) != emptyset }

B_s = R_s \ R_s^fin
```

Envelope finite completeness 为：

```text
EFC(s)
  iff for all R in R_s:
    F_s(R) is defined
    and F_s(R) in [0,+infinity)
```

注意：

1. `P_s(R) != emptyset` 只保证存在可达策略，不保证存在 finite-loss 策略；
2. `EFC(s)` 不成立，不等于已经证明 `B_s != emptyset`；
3. `EFC(s)` 未被证明，也不得通过引入 `+infinity` loss value 来修补。

## 3. Finite completeness source audit

当前 frame 的原始定义为：

```text
R(P; theta)
  = inf over decision rules delta
    E_theta[ C(delta(I_P), W) ]

D(P; theta) = R(P; theta) - R_oracle(theta)
```

审计结果：

| 证明义务 | 当前状态 |
|---|---|
| `C` 的 codomain 已声明为 finite | 未声明 |
| 每个 admissible cost term 均 finite | 未声明 |
| expectation 对所有相关 `P,theta` well-defined | 未声明 |
| expectation finite / integrability condition | 未声明 |
| Bayes risk `R(P;theta)` finite | 未声明 |
| oracle `R_oracle,X(theta)` finite | 未声明 |
| excess loss `D(P;theta)` finite | 未声明 |
| 每个 `R in R_s` 至少存在一个 finite-loss policy | 未声明 |

因此：

```text
EFC_DERIVABLE_FROM_FROZEN_FRAME = FALSE
ENVELOPE_FINITE_COMPLETENESS    = NOT ESTABLISHED
```

同样地：

```text
B_S_EXISTENCE = NOT ESTABLISHED
```

不能由 “finite completeness 未证明” 反推 `B_s` 非空。

## 4. Boundary status

若 `B_s` 非空，其状态只能通过显式 Step④ review 决定，不能静默选择。

### 4.1 Applicability boundary

只有当 Step④ 明确改用 finite-loss estimand domain：

```text
R_s^fin
```

并把 `B_s` 声明为 applicability / realizability boundary 时，该分类才成立。

Step④ 已有规则只处理 “无可达 encoder” 的情形。这里的 `B_s` 不同：`P_s(R)` 非空，只是没有已定义的 finite-loss 成员。因此不得用既有 unreachable-encoder 规则自动类推。

### 4.2 Representation gap

若维持 STEP④ 原始承诺：

```text
envelope domain = R_s
```

则 `B_s != emptyset` 会使 Candidate 1 出现 representation gap：原 domain 中有些 reachable rate 无法由 `[0,+infinity)` valued envelope 表示。

这种情况不能通过悄悄缩小 domain 修复。

### 4.3 Typed split

只有当 frame 还必须同时表示 actual infinity loss 与 no-finite-loss member 时，typed split 才获得实质理由。

当前没有任何既有定义证明这一点。

## 5. 裁定

```text
ENVELOPE_FINITE_COMPLETENESS = NOT ESTABLISHED
B_S_EXISTENCE                = NOT ESTABLISHED
BOUNDARY_STATUS              = UNRESOLVED

CANDIDATE_1                  = CONDITIONAL / NOT CHOSEN
CANDIDATE_3                  = NOT ESTABLISHED
IPR_VALUE                    = UNDECLARED
NECT MODE ADJUDICATION       = BLOCKED
STEP⑥                        = NOT ENTERED
```

当前 Step④ text 已把 `R_X` 声明为 envelope domain。因此，即使未来发现 `B_s != emptyset`，也不得静默把它改成 `R_s^fin`。任何 domain narrowing 都必须作为 typed-codomain review 的显式裁定入档。

## 6. 下一步的合法出口

下一步必须在以下显式声明中选择或继续审查：

1. **FC proof**：从冻结 `C/R/D` 语义证明 `EFC(s)` 对所有相关 scope 成立；
2. **Restricted finite-loss domain**：显式把 target domain 改为 `R_s^fin`，并把 `B_s` 声明为 applicability boundary；
3. **Typed codomain**：给出既有语义为何必须同时表示 actual infinity loss 与 no-finite-loss member 的证明；
4. **继续 unresolved**：若现有 frame 仍不足以裁定，则保持 STEP④ review open。

不得通过实验、估计结果或 NECT 通过/失败反推上述任何声明。

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
