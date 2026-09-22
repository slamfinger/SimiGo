# Architecture 2.0 — P4-A STEP⑤ Semantic Validity 与 NECT Naming Revision

**Date:** 2026-09-22\
**Status:** STEP⑤ OPEN / EC_T SEMANTICALLY VALID / EXISTENCE-NAMING REVISION OPEN\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. 本轮裁定

本轮不攻击 EC_T 的数学形式，而是攻击命名与门禁语义。

| 命题 | 状态 |
|---|---|
| EC_T 数学定义 | PASS as candidate |
| “EC_T = frontier existence” 这一命名 | FAIL |
| “EC_T = nontrivial phenomenon existence” 这一定位 | PASS candidate |

因此 STEP⑤ 不得进入 STEP⑥。当前正式状态是命名修订开放，而不是存在判据关闭。

## 2. 两个 existence 必须分开

### 2.1 Envelope existence

在 STEP④ 最小 contract 下，下包络对象已经定义良好：

```text
F_s(R)
  = inf { Delta_s(P; theta) :
          P in S_det, Rate_X(P) <= R }
```

该对象是否存在、是否 well-defined，属于 STEP④ 的 Envelope Object Definition。平坦 frontier 也属于这一层：对象存在，只是没有下降结构。

### 2.2 Phenomenon existence

EC_T 问的不是：

```text
Does F exist?
```

而是：

```text
Does F contain a nontrivial strict-descent phenomenon?
```

因此 EC_T 不应再被叙述为 “frontier existence criterion”。其准确候选名是：

```text
Nontrivial Phenomenon Existence Criterion
```

简称：

```text
NECT
```

历史文档中的 `EC_T` 可继续作为公式别名，但治理叙述应改用 `NECT`。

## 3. NECT 的非平凡性不是价值判断

`nontrivial` 不表示：

- 有实际价值；
- 下降幅度足够大；
- 存在 knee；
- 能指导 Runtime；
- 具有跨架构意义；
- 值得部署。

这些分别属于 STEP⑥–⑧。

当前 `nontrivial` 只表示函数论意义上的非平坦。由于 cumulative rate-budget semantics 已先验保证：

```text
Ra < Rb  =>  F_s(Rb) <= F_s(Ra)
```

所以 strict descent 就是非平坦的唯一相关形式。

## 4. 与 “tradeoff existence” 的区别

不把 STEP⑤ 命名为 Tradeoff Existence Criterion。

`tradeoff` 比 strict descent 更强。NECT 不证明：

- 某个具体 projection 形成两个 realized Pareto points；
- 存在连续 tradeoff curve；
- 存在经济 exchange rate；
- frontier shape 稳定；
- 两个有限估计点能可靠表现出该交换关系。

这些都不是 STEP⑤ 的对象。

## 5. 非平坦性的精确等价

在 envelope contract 与 cumulative-rate semantics 下：

```text
NECT(s)
iff
  |R_s^tau| >= 2
  and exists Ra,Rb in R_s^tau
      such that
        Ra < Rb,
        F_s(Ra), F_s(Rb) in [0,+infinity),
        F_s(Ra) != F_s(Rb)
```

由于 `F_s` 非增，有限见证点上的 `!=` 必然表现为：

```text
F_s(Rb) < F_s(Ra)
```

若当前 scope 进一步保证所有相关 loss 均有限，则可压缩为：

```text
NECT(s)
iff
  |R_s^tau| >= 2
  and F_s is non-constant on R_s^tau
```

但当前 codomain 是 `[0,+infinity]`，不能默认省略 finite witness condition。

`|R_s^tau| >= 2` 在公式上被 strict descent witness 蕴含，不是额外数学强度。它的治理价值是：domain 不足两个点时，必须输出 domain insufficiency，而不是输出 `NECT=false`。

## 6. Scope closure

NECT 必须逐 track 声明：

```text
NECT^sem(frame, X, theta_sem)

NECT^dep(frame, X, theta_dep, N)
```

或更一般：

```text
NECT^dep(frame, X, theta_dep, mu_D)
```

禁止合并不同 workload regime、不同 economic coordinate 或不同 track 的可达域来制造下降见证。

因此：

```text
NECT^sem = true
NECT^dep = false
```

不是矛盾，而是两个独立 scope closure 的结果。

## 7. 层级冻结候选

当前治理层级应记录为：

```text
STEP④
Envelope Object Definition
  F_AS well-defined

STEP⑤
Nontrivial Phenomenon Existence
  exists strict descent in one declared scope

STEP⑥
Negative / Insufficiency
  what target-level outcome closes or narrows the claim

STEP⑦
Discriminating Power

STEP⑧
Information Value / Cost

STEP⑨
Design / Harness

STEP⑩
Evidence
```

该层级是候选冻结。正式改名仍需下一轮裁定，防止名称变化偷改研究对象。

## 8. 下一刀

下一步不再攻击 strict descent 的数学性，而攻击 NECT 的门禁形式：

1. `|R_s^tau| >= 2` 应作为定义成分、admission condition，还是只作为输出分类；
2. `DOMAIN_INSUFFICIENT`、`NECT=true`、`NECT=false`、`EVIDENCE_INSUFFICIENT` 是否成为 STEP⑤ 的正式输出状态；
3. semantic / deployment-economic scope closure 是否足以阻止合并域见证；
4. “Nontrivial Phenomenon Existence Criterion” 是否正式替代 “Existence Criterion”。

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
