# Architecture 2.0 — P4-A STEP④ Infinity-Loss Entitlement Ruling

**Date:** 2026-09-22\
**Status:** STEP④ TYPED-CODOMAIN REVIEW OPEN / CANDIDATE 2 REJECTED / IPR UNDECLARED / NECT MODE BLOCKED\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮唯一问题

本轮只裁定：

```text
当前已冻结的 frame semantics 是否已经赋予 +infinity
作为单一 ordered loss value 的合法资格？
```

不裁定 `NECT_E / NECT_F`，不进入 STEP⑥。

## 2. Source audit

当前 frame 的核心定义为：

```text
R(P; theta)
  = inf over delta
    E_theta[ C(delta(I_P), W) ]

D(P; theta) = R(P; theta) - R_oracle(theta)
```

已冻结事实：

| 对象 | 当前状态 |
|---|---|
| 成本函数 `C` | 已声明、已冻结，但未声明 codomain |
| Bayes risk `R` | 已定义形式，但未声明 codomain |
| excess loss `D` | 已定义形式，但未声明 codomain |
| `+infinity as LossValue` | 未定义 |
| `+infinity as NoFiniteLossMember` | 未定义 |
| `+infinity as EvaluationNA` | 未定义 |

STEP⑤ 曾引入：

```text
Delta_s(P; theta) in [0,+infinity]
```

但这是后续 well-definedness contract，不是 STEP①–④ 已有 frame semantics。它不能回溯性赋予 `+infinity` ordered loss-value status。

## 3. Candidate 2 ruling

Candidate 2 要求：

```text
F_s : R_s -> [0,+infinity]
```

且 `+infinity` 是 ordered decision-loss value。

裁定：

```text
CANDIDATE_2_ELIGIBLE = FALSE
LOSS_INFINITY_PREDEFINED = FALSE
```

理由：

1. 当前 frame 没有 `C/R/D -> [0,+infinity]` 的既有声明；
2. extended-real notation 本身不构成 `+infinity` 的语义承诺；
3. STEP⑤ 不能为了支持 NECT_E 而事后补造该语义；
4. 因此当前 codomain 不能合法承载 `+infinity` 的单一 ordered loss-value semantics。

## 4. Candidate 1 condition

Candidate 1 是：

```text
F_s : R_s -> [0,+infinity)
```

它不是“忽略 infinity”。

若选择 Candidate 1，必须同时满足其一：

1. **Finite completeness**：

```text
for all relevant P,theta:
  Delta(P; theta) < +infinity
```

或

2. **Explicit finite-loss restriction**：

```text
S_det^fin(s)
  = { P in S_det :
      Delta_s(P; theta) < +infinity }
```

并且所有 no-finite-loss 情形移出 target domain，另行表示为 applicability / realizability boundary。

当前尚不能选择 Candidate 1，因为 `C/R/D` 的 finite completeness 尚未由既有 frame 声明或证明。

## 5. Candidate 3 condition

Candidate 3 是 typed/tagged envelope：

```text
T in {
  FINITE_LOSS(a),
  ACTUAL_INFINITY_LOSS,
  NO_FINITE_LOSS_MEMBER,
  UNDEFINED
}
```

它只有在现有对象语义同时需要表示两类不同事实时才必要：

1. 真实 infinite decision loss；
2. no finite-loss member / realizability boundary。

当前 frame 没有定义其中任何一类 `+infinity`。

因此：

```text
CANDIDATE_3_NECESSARY = NOT ESTABLISHED
```

不得因为 typed envelope “更安全”而选择 Candidate 3。类型增加本身是新的建模承诺。

## 6. Ruling summary

| Candidate | 当前裁定 | 原因 |
|---|---|---|
| Candidate 1 `[0,+infinity)` | CONDITIONAL / NOT CHOSEN | 需要先声明 finite completeness 或显式 finite-loss restriction |
| Candidate 2 `[0,+infinity]` | REJECTED | 当前 frame 未定义 `+infinity` 为 ordered loss value |
| Candidate 3 typed envelope | NOT ESTABLISHED | 尚未证明必须同时表示两种 infinity semantics |

正式状态：

```text
LOSS_INFINITY_PREDEFINED   = FALSE
IPR_VALUE                  = UNDECLARED
CANDIDATE_2                = REJECTED
FINITE_COMPLETENESS        = UNDECLARED
TYPED_SPLIT_NECESSITY      = NOT ESTABLISHED
NECT MODE ADJUDICATION     = BLOCKED
STEP⑥                      = NOT ENTERED
```

## 7. Next review action

下一步仍属 STEP④ typed-codomain review，只做二选一前置审查：

1. 判定当前冻结 `C/R/D` 是否已经满足或需要显式声明 finite completeness；
2. 判定是否存在既有语义必须同时表示 actual infinity loss 与 no-finite-loss member。

若前者成立且后者不成立，Candidate 1 可进入冻结候选。

若后者成立，Candidate 3 才可进入冻结候选。

若二者都不成立，不得为 NECT 便利而发明新的 infinity semantics。

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
