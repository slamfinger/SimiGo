# R-INTERNAL-9 = E9-B

Date: 2026-09-23

## Declaration

R-INTERNAL-9 = E9-B

## Semantic declaration

The effective optimization domain is explicitly restricted by both P-dependent admissibility and loss-evaluation domain membership:

```
g ∈ 𝒢_adm(P)
∧
(g,P,θ) ∈ Dom(L)
```

Accordingly, the aggregate construction is represented at the current abstraction level as:

```
R(P,θ)
=
OPT_{g ∈ 𝒢_adm(P),\,(g,P,θ)∈Dom(L)}
L(g;P,θ)
```

## Relation to E8-C

R-INTERNAL-8 = E8-C already declares:

```
(g,P,θ) ∈ Dom(L)
⇔
g ∈ 𝒢_adm(P)
∧
E_θ[C_LOSS(g(W),W)] 合法且为有限实数
```

R-INTERNAL-9 makes the Dom(L) restriction explicit at the optimization-domain interface rather than leaving it implicit in the notation for R.

## Boundaries

OPT remains an abstract scalar optimization operator. No min / inf / argmin / optimizer existence or attainment is declared.

No concrete admissible-rule family, probability space, parameter domain, measurable-loss construction, integrability condition, optimizer, R_OBJECT, R_ORACLE, Δ, FinLoss, NECT, STEP⑤/STEP⑥ entry, implementation, harness, data collection, profiling, measurement, or experiment authorization is declared by this gate.

Historical δ(I_P) is not restored and no new δ optimization domain is introduced.
