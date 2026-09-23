# R-INTERNAL-8 = E8-C

Date: 2026-09-23

## Declaration

R-INTERNAL-8 = E8-C

## Semantic declaration

The loss-evaluation domain is closed by the biconditional:

```
(g,P,θ) ∈ Dom(L)
    ⇔
g ∈ 𝒢_adm(P)
    ∧
E_θ[C_LOSS(g(W),W)] 合法且为有限实数
```

## Meaning

E8-C makes admissibility in the P-dependent decision-rule family and legality/finite-real status of the expectation jointly necessary and sufficient for membership in Dom(L).

This closes the current resolution level of the loss-evaluation domain without expanding the word “合法” into separate declarations of measurability, integrability, or a specific expectation-existence theorem.

## Preserved interfaces

```
P : PROJECTION_CANDIDATE
δ : DECISION_GENERATION_PARAMETER
θ : REGIME_PARAMETER

𝒢_adm(P) = ADMISSIBLE_DECISION_RULE_FAMILY
𝒢_adm(P) ⊆ {g | g : W → A}

L : Dom(L) → ℝ
L(g;P,θ) = E_θ[C_LOSS(g(W),W)]

R(P,θ) = OPT_{g ∈ 𝒢_adm(P)} L(g;P,θ)
```

R-INTERNAL-7 = E7-B is subsumed as the necessary admissibility direction of this biconditional.

## Boundaries

No concrete probability space, parameter set, measurable-loss construction, integrability condition, optimization construction, optimizer existence/attainment, R_OBJECT, R_ORACLE, Δ, FinLoss, NECT, STEP⑤/STEP⑥ entry, implementation, harness, data collection, profiling, measurement, or experiment authorization is declared by this gate.

Historical δ(I_P) is not restored and no new δ optimization domain is introduced.
