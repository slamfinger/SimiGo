# R-INTERNAL-14 = K4-A / UNRESOLVED + ATTAINMENT_PREDICATE

Date: 2026-09-23

## Declaration

R-INTERNAL-14 = K4-A

Semantic type:

`UNRESOLVED` with authorized attainment predicate

## Semantic declaration

R-INTERNAL-12 fixes the value-level construction:

```
OPT(P,θ) = inf V(P,θ)
```

R-INTERNAL-13 restricts the finite-valued applicability domain to:

```
Dom(R)
=
{(P,θ) | D_opt(P,θ) ≠ ∅ ∧ inf V(P,θ) ∈ ℝ}
```

K4-A leaves attainment unresolved. It does not assert that the infimum is attained.

The maximum currently legal object for the attainment question is the predicate:

```
att : Dom(R) → {true, false}

att(P,θ) ⇔ inf V(P,θ) ∈ V(P,θ)
```

with its truth domain:

```
Dom_att
=
{(P,θ) ∈ Dom(R) | att(P,θ)}
```

This predicate formalizes the distinction:

```
R(P,θ) ∈ ℝ  ⇏  inf V(P,θ) ∈ V(P,θ)
```

For example, a value set of the form

```
V = (0,1)
```

has a finite infimum (0), while (0\notin V).

## Resolution status

K4-A = K4-A-1 / UNRESOLVED.

No attainment instance is declared true or false at any point.

No non-emptiness claim is made for `Dom_att`.

No relation such as `Dom_att = Dom(R)` or `Dom_att = ∅` is declared.

No `min` notation is introduced. `OPT(P,θ) = inf V(P,θ)` remains the current construction.

## Boundaries

This gate does not declare:

- optimizer existence;
- attainment at any specific `(P,θ)`;
- `Dom_att ≠ ∅`;
- `Dom_att = Dom(R)`;
- `Dom_att = ∅`;
- minimum attainment or any `min`-based reformulation;
- argmin set semantics;
- selector;
- uniqueness;
- tie-breaking;
- compactness;
- continuity;
- measurability;
- finiteness/cardinality assumptions on the optimization domain;
- any conditional attainment framework or sufficient-condition family;
- any θ-level optimization;
- `A(P,θ)`;
- historical `δ(I_P)`;
- R_OBJECT, R_ORACLE, Δ, FinLoss, NECT;
- STEP⑤/STEP⑥ entry;
- implementation, harness, data collection, profiling, measurement, or experiment authorization.

No topology or structural condition is introduced or pre-authorized by this gate.

## Forward interface boundary

The attainment predicate is the only object authorized on this gate.

A future argmin gate may independently define an argmin set and establish any desired equivalence between non-emptiness of that set and `att(P,θ)`. Such an equivalence is not declared here.

The selector/tie-breaking layer remains separate.

## Researcher decision

The researcher explicitly selected:

```
K4-A = K4-A-1 (UNRESOLVED)

AUTHORIZED:
att : Dom(R) → {true,false}
Dom_att = {(P,θ) ∈ Dom(R) | att(P,θ)}

NOT AUTHORIZED:
any attainment assertion, conditional framework, argmin, selector, uniqueness, tie-breaking
```
