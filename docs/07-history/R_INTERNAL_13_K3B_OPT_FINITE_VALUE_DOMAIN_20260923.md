# R-INTERNAL-13 = K3-B / OPT_FINITE_VALUE_DOMAIN

Date: 2026-09-23

## Declaration

R-INTERNAL-13 = K3-B

Semantic type:
OPT_FINITE_VALUE_DOMAIN

## Semantic declaration

From R-INTERNAL-12:

```
V(P,θ)
=
{L(g;P,θ) | g ∈ 𝒢_adm(P), (g,P,θ) ∈ Dom(L)}
```

E10-B gives a non-empty effective optimization domain, hence:

```
∅ ≠ V(P,θ) ⊆ ℝ
```

However, non-emptiness and real-valued elements alone do not imply that the infimum is finite. Therefore the finite-valued evaluation domain is explicitly scoped as:

```
Dom(R)
=
{(P,θ) | D_opt(P,θ) ≠ ∅ ∧ inf V(P,θ) ∈ ℝ}
```

and, for that domain:

```
R(P,θ) = inf V(P,θ) ∈ ℝ
```

## E11-B scope precization

R-INTERNAL-11 = E11-B previously stated:

```
R(P,θ) ∈ ℝ
```

without defining an exact `Dom(R)`.

R-INTERNAL-13 explicitly refines the applicability scope of that declaration to:

```
E10-B context
∩
{(P,θ) | inf V(P,θ) ∈ ℝ}
```

Equivalently, E11-B’s finite-output claim is now read as applying on `Dom(R)` as defined above.

The prior unconditional reading of E11-B is superseded from R-INTERNAL-13 onward. This is a scope precization/revision of an already registered value-domain claim, not a silent new definition.

## E10-B relation

E10-B’s non-empty effective optimization domain is retained as a necessary condition for R evaluation.

It is not sufficient for finite-valued R.

For example, a non-empty value set can satisfy:

```
V = {-1,-2,-3,...}
```

while:

```
inf V = -∞
```

Thus K3-B is a substantive gate.

## Boundaries

This gate does not declare:

- `Dom(R) ≠ ∅`;
- optimizer existence;
- minimum attainment;
- argmin;
- selector or tie-breaking;
- any global lower-bound axiom on C_LOSS;
- compactness, continuity, measurability, or computability beyond prior declarations;
- any θ-level optimization;
- `A(P,θ)` or another θ-level candidate-value set;
- R_OBJECT, R_ORACLE, Δ, FinLoss, NECT;
- STEP⑤/STEP⑥ entry;
- implementation, harness, data collection, profiling, measurement, or experiment authorization.

Historical `δ(I_P)` is not restored and no new δ optimization domain is introduced.
