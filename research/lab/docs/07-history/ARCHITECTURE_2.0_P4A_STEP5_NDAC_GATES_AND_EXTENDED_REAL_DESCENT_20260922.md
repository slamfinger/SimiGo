# Architecture 2.0 — P4-A STEP⑤ NDAC Gate 与 Extended-real Descent Boundary

**Date:** 2026-09-22\
**Status:** STEP⑤ OPEN / NDAC ACCEPTED / NECT MODE OPEN\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮裁定

本轮冻结三个门禁边界，并新开一个实质对象边界。

### 通过

1. `|R_s^tau| >= 2` 不进入 NECT 谓词本体，而是独立的 domain admission condition；
2. STEP⑤ target output 只包含 `DOMAIN_INSUFFICIENT`、`NECT_TRUE`、`NECT_FALSE`；
3. `EVIDENCE_INSUFFICIENT` 不属于 STEP⑤ target output，属于正交 evidence layer。

### 新开

当前 finite-witness condition 不能直接冻结。extended-real codomain `[0,+infinity]` 允许：

```text
F_s(Ra) = +infinity
F_s(Rb) <  +infinity
F_s(Rb) <  F_s(Ra)
```

因此必须先裁定：NECT 检测整个 extended-real envelope 的 strict descent，还是只检测 finite-loss region 内部的 descent。

## 2. Domain admission

定义：

```text
NDAC(s)
  iff |R_s^tau| >= 2
```

`NDAC` 是 **NECT Domain Admission Condition**。

它不是 NECT 的定义成分。`Ra < Rb` 的存在已经逻辑蕴含至少两个不同 rate point；把 `|R_s^tau| >= 2` 再硬并入谓词没有增加数学内容，反而会把 predicate 与 evaluability gate 混在一起。

若 `NDAC(s)` 为假，正确输出不是 `NECT_FALSE`，而是：

```text
DOMAIN_INSUFFICIENT
```

含义是：当前 scope 的 reachable rate domain 不足以提出 strict-descent existence question。

## 3. 两个候选 NECT mode

在 envelope defined 且 `NDAC(s)` 通过后，当前存在两个尚未裁决的谓词候选。

### 3.1 Extended-real descent

```text
NECT_E(s)
  iff exists Ra,Rb in R_s^tau
      such that
        Ra < Rb
        and F_s(Rb) < F_s(Ra)
```

该模式检测整个 extended-real envelope 上的 strict descent。它允许：

```text
F_s(Ra) = +infinity
F_s(Rb) <  +infinity
```

因此能识别“更大 rate budget 使 scope 从 infinite-loss 区域进入 finite-loss 区域”。

### 3.2 Finite-finite descent

```text
NECT_F(s)
  iff exists Ra,Rb in R_s^tau
      such that
        Ra < Rb,
        F_s(Ra) < +infinity,
        F_s(Rb) < +infinity,
        F_s(Rb) < F_s(Ra)
``+

该模式只检测 finite-loss region 内部的 strict descent。它会排除 `+infinity -> finite`，即使后者在 `[0,+infinity]` 中是合法严格下降。

历史文档中的 `EC_T` 与当前 `NECT` 别名尚未指定 `E` / `F` mode。在此裁定前，不得把 finite witness condition 当作已经冻结的定义。

## 4. STEP⑤ target adjudication flow

STEP⑤ 的逻辑流程为：

```text
Envelope defined?
  NO  -> STEP④ failure / envelope undefined
  YES
    |
    v
NDAC(s)?
  NO  -> DOMAIN_INSUFFICIENT
  YES
    |
    v
Evaluate selected NECT mode
  TRUE  -> NECT_TRUE
  FALSE -> NECT_FALSE
```

在 mode 未裁定前，当前 target status 是：

```text
NECT MODE UNRESOLVED
```

这不是第四种 target truth status，而是当前研究门尚未完成定义冻结。

## 5. Target status 与 evidence status 分离

STEP⑤ target-level adjudication 只使用：

```text
TargetStatus
  in {
    DOMAIN_INSUFFICIENT,
    NECT_TRUE,
    NECT_FALSE
  }
```

Evidence layer 使用正交轴：

```text
EvidenceStatus
  in {
    NOT_ASSESSED,
    INSUFFICIENT,
    SUFFICIENT
  }
```

示例组合：

| Target | Evidence | 含义 |
|---|---|---|
| `DOMAIN_INSUFFICIENT` | `NOT_ASSESSED` | rate domain 不足以评估 NECT |
| `NECT_TRUE` | `NOT_ASSESSED` | target truth 已由理论/构造证明，尚未进入证据记录 |
| `NECT_FALSE` | `NOT_ASSESSED` | target truth 已证明为无所选 mode 的 descent |
| target truth not yet established | `INSUFFICIENT` | 有限证据不足，但不等于 target false |
| `NECT_TRUE` | `SUFFICIENT` | 后续证据层支持已知 target truth |
| `NECT_FALSE` | `SUFFICIENT` | 后续证据层支持已知 target truth |

禁止构造：

```text
NECT in {true, false, evidence_insufficient}
```

这会把 mathematical truth 与 epistemic status 合成一个变量。

## 6. 禁止 STEP⑤ 输出 evidence insufficiency

STEP⑤ 不负责 finite-sample assessment。

若当前无法证明或否证 NECT，STEP⑤ 记录：

```text
NECT target truth not yet established
```

不得记录：

```text
EVIDENCE_INSUFFICIENT
```

后者属于 future evidence layer / STEP⑩。

这条规则防止以下循环：

```text
STEP⑤: 没有实验，所以 EVIDENCE_INSUFFICIENT
STEP⑥: 因为 STEP⑤ 没通过，所以关闭
```

该循环会把“没测到”偷换成“没发生”。

## 7. NECT_FALSE 的 mode-dependent 含义

`NECT_FALSE` 必须在 mode 冻结后解释。

### 若选择 `NECT_E`

`NECT_E=false` 表示：

```text
for all Ra,Rb in R_s^tau with Ra < Rb:
  F_s(Rb) = F_s(Ra)
```

即 extended-real envelope 在 reachable domain 上完全平坦。这才是 extended-real frontier 的 target-level flat negative。

### 若选择 `NECT_F`

`NECT_F=false` 只表示不存在 finite-finite strict descent。

它不排除：

```text
F_s(Ra) = +infinity
F_s(Rb) <  +infinity
```

因此 `NECT_F=false` 不一定等价于整个 extended-real envelope flat。

## 8. 下一刀

下一刀只裁决一个对象问题：

```text
+infinity -> finite
是否属于 NECT？
```

可选裁定至少包括：

1. `NECT_E`：纳入 `+infinity -> finite`，删除 finite witness precondition；
2. `NECT_F`：只研究 finite-loss region 内部下降，并证明该限制为何是当前研究对象；
3. dual predicate：把 extended descent 与 finite-region descent 作为两个 separately scoped target propositions；
4. `NECT_E=true` 但另设 finite-region annotation，不把两个现象混为同一谓词。

在选择前，STEP⑤ 继续 OPEN，不进入 STEP⑥。

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
