# SimiGo-Lab Research State

> **This file is the authoritative snapshot of the current SimiGo-Lab research state. Conversation memory must not override it.**

**Last updated**: 2026-09-23（R-INTERNAL-18 = ROr-4 / R_ORACLE_DEFERRED 已登记）

## Current research state

Phase: Architecture 2.0 / P4 Redefinition

R-INTERNAL-1 = P4
R-INTERNAL-2 = δ3
R-INTERNAL-3 = θ2
R-INTERNAL-4 = G4-4
R-INTERNAL-5 = L5-3
R-INTERNAL-6 = E6-4
R-INTERNAL-7 = E7-B
R-INTERNAL-8 = E8-C
R-INTERNAL-9 = E9-B
R-INTERNAL-10 = E10-B
R-INTERNAL-11 = E11-B
R-INTERNAL-12 = K3-A / VALUE_INFIMUM
R-INTERNAL-13 = K3-B / OPT_FINITE_VALUE_DOMAIN
R-INTERNAL-14 = K4-A / UNRESOLVED + ATTAINMENT_PREDICATE
R-INTERNAL-15 = K4-B / DEFINE_ARGMIN_SET + ATTAINMENT_EQUIVALENCE
R-INTERNAL-16 = K4-C / UNRESOLVED + UNIQUENESS_PREDICATE
R-INTERNAL-17 = RO-1 / R_OBJECT_VALUE_FUNCTIONAL
R-INTERNAL-18 = ROr-4 / R_ORACLE_DEFERRED

### Current internal interfaces

```
P : PROJECTION_CANDIDATE
δ : DECISION_GENERATION_PARAMETER
θ : REGIME_PARAMETER

𝒢_adm(P) = ADMISSIBLE_DECISION_RULE_FAMILY
𝒢_adm(P) ⊆ {g | g : W → A}

L : Dom(L) → ℝ

R-INTERNAL-8 / E8-C:
(g,P,θ) ∈ Dom(L)
    ⇔
g ∈ 𝒢_adm(P)
    ∧
E_θ[C_LOSS(g(W),W)] 合法且为有限实数

R-INTERNAL-9 / E9-B:
R(P,θ)
=
OPT_{g ∈ 𝒢_adm(P),\,(g,P,θ)∈Dom(L)}
L(g;P,θ)

R-INTERNAL-10 / E10-B:
∃g :
g ∈ 𝒢_adm(P)
∧
(g,P,θ) ∈ Dom(L)

等价地：
{g ∈ 𝒢_adm(P) | (g,P,θ) ∈ Dom(L)} ≠ ∅

R-INTERNAL-11 / E11-B:
R(P,θ) ∈ ℝ

R-INTERNAL-12 / K3-A:
V(P,θ)
=
{L(g;P,θ) | g ∈ 𝒢_adm(P), (g,P,θ) ∈ Dom(L)}

OPT(P,θ) = inf V(P,θ)

R-INTERNAL-13 / K3-B:
V(P,θ) ≠ ∅ and V(P,θ) ⊆ ℝ.

Dom(R)
=
{(P,θ) | D_opt(P,θ) ≠ ∅ ∧ inf V(P,θ) ∈ ℝ}

R(P,θ) = inf V(P,θ) ∈ ℝ,  ((P,θ) ∈ Dom(R))

R-INTERNAL-14 / K4-A:
att : Dom(R) → {true, false}

att(P,θ) ⇔ inf V(P,θ) ∈ V(P,θ)

Dom_att
=
{(P,θ) ∈ Dom(R) | att(P,θ)}

R-INTERNAL-15 / K4-B:
Argmin(P,θ)
=
{g ∈ D_opt(P,θ) | L(g;P,θ) = inf V(P,θ)}
\quad ((P,θ) ∈ Dom(R))

Argmin(P,θ) ≠ ∅
⇔
att(P,θ)

Dom_att
=
{(P,θ) ∈ Dom(R) | Argmin(P,θ) ≠ ∅}

R-INTERNAL-16 / K4-C:
uniq : Dom(R) → {true, false}

uniq(P,θ) ⇔ |Argmin(P,θ)| = 1

Dom_uniq
=
{(P,θ) ∈ Dom(R) | uniq(P,θ)}
```

R-INTERNAL-14 defines the attainment predicate without asserting attainment. R-INTERNAL-15 defines the argmin set on Dom(R) and formally registers the pointwise equivalence between argmin non-emptiness and att. Neither gate asserts that attainment or argmin non-emptiness holds at any particular point.

### Assembly state

```
R-ASSEMBLY-1A = DECLARED (COMPOSITE_PROJECTION_RULE_PAIR)
R-ASSEMBLY-1B = DECLARED (JOINT_COMPOSITE_OUTPUT_MECHANISM)
R-ASSEMBLY-1C = DECLARED (C3)
R-ASSEMBLY-2  = DECLARED (D2)
R-ASSEMBLY-3  = DECLARED (F2)
R-ASSEMBLY-4  = DECLARED (G2)
R-ASSEMBLY-5  = DECLARED (H2)
R-ASSEMBLY-6  = DECLARED (I2)
R-ASSEMBLY-7  = DECLARED (J1)
R-ASSEMBLY-8  = DECLARED (K3)
R-ASSEMBLY-9  = DECLARED (L3)
R-ASSEMBLY-10 = DECLARED (M4)

R_OBJECT     = DECLARED (R : Dom(R) → ℝ)
R_ASSEMBLY   = OPEN
R_ORACLE     = NOT_DEFINED
Δ            = BLOCKED
FinLoss      = NOT LEGALLY AVAILABLE
NECT         = BLOCKED
STEP⑤        = NOT ENTERED
STEP⑥        = NOT ENTERED
EXPERIMENT AUTH = NONE
HARNESS AUTH    = NONE
```

### Core aggregate construction

```
Γ(P,δ) = g
g : W → A

L(g;P,θ) = E_θ[C_LOSS(g(W),W)]

R(P,θ)
=
OPT_{g ∈ 𝒢_adm(P),\,(g,P,θ)∈Dom(L)}
L(g;P,θ)

R(P,θ) ∈ ℝ
```

OPT is concretized as a value-level infimum by R-INTERNAL-12. R-INTERNAL-13 establishes the finite-value applicability domain for that construction. R-INTERNAL-14 defines the attainment predicate without asserting attainment. The non-emptiness of `Dom(R)` and `Dom_att` itself is not declared.

### Research boundaries

R_OBJECT is declared as the value functional R : Dom(R) → ℝ; under RO-1, the research object is the optimal value, while Argmin / att / uniq and their domains remain auxiliary diagnostic/semantic objects and are not deleted. R_ORACLE remains undefined by the current framework. Δ remains blocked. FinLoss and NECT remain unavailable. Historical STEP⑤ formulation remains historical/conditional only. No STEP⑤/STEP⑥ entry, implementation, harness, data collection, profiling, measurement, or experiment authorization follows from R-INTERNAL-15.

R-INTERNAL-16 does not introduce topology or any structural condition, and does not pre-authorize future sufficient-condition families. It does not declare optimizer existence at any point, attainment at any point, minimum attainment, `min` reformulation, selector/tie-breaking, canonical choice, uniqueness at any particular point, compactness, continuity, measurability, finiteness/cardinality assumptions, any θ-level optimization, `A(P,θ)`, historical `δ(I_P)`, R_OBJECT, R_ORACLE, Δ, FinLoss, or NECT. The uniqueness predicate itself is defined, but no instance is asserted to satisfy it.

The authorized forward interface after R-INTERNAL-16 is:
```
att : Dom(R) → {true,false}
Argmin(P,θ) = {g ∈ D_opt(P,θ) | L(g;P,θ) = inf V(P,θ)}
Argmin(P,θ) ≠ ∅ ⇔ att(P,θ)
Dom_att = {(P,θ) ∈ Dom(R) | Argmin(P,θ) ≠ ∅}
uniq : Dom(R) → {true,false}
uniq(P,θ) ⇔ |Argmin(P,θ)| = 1
Dom_uniq = {(P,θ) ∈ Dom(R) | uniq(P,θ)}
```

The equivalence is registered as the formal bridge between attainment and argmin non-emptiness. R-INTERNAL-16 defines only the uniqueness predicate and its truth domain; it does not assert uniqueness anywhere. Selector/tie-breaking remains a separate layer.

Historical `δ(I_P)` is not restored and no new δ optimization domain is introduced.

R-INTERNAL-17 / RO-1 explicitly keeps `δ(I_P)` BLOCKED and does not introduce any new δ optimization domain. `Δ` remains BLOCKED; `FinLoss` remains NOT LEGALLY AVAILABLE; `NECT` remains BLOCKED. θ-level optimization and `A(P,θ)` remain excluded. No approximation/gap object is introduced.

R-INTERNAL-16 does not declare `Dom_uniq ≠ ∅`, does not assert `uniq` is true at any point, and does not create a selector from uniqueness. The observation that `uniq(P,θ)` is false whenever `Argmin(P,θ)=∅` is a direct consequence of the registered definitions, not a separate assertion.


### R-INTERNAL-18 / ROr-4 — R_ORACLE deferred

R-INTERNAL-18 = ROr-4 / DEFERRED

R_ORACLE : NOT_DEFINED

暂缓理由：
1. 无已登记消费者：Δ = BLOCKED，gap/D 未声明，STEP⑤ = NOT ENTERED。
2. 来源形态未决：P-free 可容许类 / 理论基准均未声明。
3. 历史公式 D(P;θ) = R(P;θ) − R_oracle(θ) 仅为历史内容，不被本面恢复。

合法重开条件（二选一，各自独立开面）：
- A. 出现已登记的参照值消费问题——且该比较面必须先论证其对 Δ BLOCKED 的合法绕行路径。
- B. 结构面声明 oracle 来源（P-free 类 / 理论基准及其定义域）。

本面产出是“暂缓”边界记录本身，不声明 R_ORACLE 对象接口。

R-INTERNAL-18 不引入：
- gap / D / suboptimality 的任何形式（含定义性占位）；
- 历史 δ(I_P)、新的 δ 优化域、A(P,θ)、θ 层优化；
- Δ、FinLoss、NECT；
- 任何 selector、tie-breaking、canonical optimizer、g*；
- topology、compactness、continuity、measurability、finiteness/cardinality assumptions；
- implementation、harness、data collection、profiling、measurement、experiment authorization。

Argmin / att / uniq 维持 RO-1 下辅助对象地位，不因本面变动。

R_ASSEMBLY = OPEN
R_OBJECT = DECLARED (R : Dom(R) → ℝ)
R_ORACLE = NOT_DEFINED
Δ = BLOCKED
FinLoss = NOT LEGALLY AVAILABLE
NECT = BLOCKED
STEP⑤ = NOT ENTERED
STEP⑥ = NOT ENTERED
EXPERIMENT AUTH = NONE
HARNESS AUTH = NONE
