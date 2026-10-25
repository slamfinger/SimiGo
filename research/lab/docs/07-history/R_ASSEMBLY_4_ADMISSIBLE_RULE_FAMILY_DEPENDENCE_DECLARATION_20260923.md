# R-ASSEMBLY-4 Admissible Rule-Family Dependence Declaration

**Date:** 2026-09-23  
**Researcher declaration:** R-ASSEMBLY-4 = G2

## Declaration

The researcher explicitly selected **R-ASSEMBLY-4 = G2**.

Therefore the admissible decision-rule family is declared at the following structural level:

    𝒢_adm(P) ⊆ { g | g : W → A }

    g ∈ 𝒢_adm(P)

This declares that the admissible decision-rule family may vary with the projection candidate P.

## Relation to prior assembly declarations

The prior declarations remain unchanged:

    Γ(P, δ) = g
    g : W → A
    a = g(w)
    g ∈ 𝒢_adm(P)

R-ASSEMBLY-3 = F2 remains the declaration that the rule family is an independent admissible family. R-ASSEMBLY-4 now specifies its dependence at the projection-candidate level.

G2 does not declare a direct dependence of the admissible rule family on δ or θ. This is a dependency declaration only; it does not preclude such dependence from being represented later through other already-declared structures, but no such direct dependence is introduced here.

## Critical separation

The following remain distinct:

    g : W → A
    g ∈ 𝒢_adm(P)
    COMPOSITE_ADMISSION_PREDICATE
    optimization domain
    R_OBJECT

G2 does not instantiate the concrete family 𝒢_adm(P), its parameterization, the rule-admission predicate, the generation guarantee Γ(P,δ) ∈ 𝒢_adm(P), the optimization domain/operator, minimum versus infimum, optimizer existence, or the exact Dom(R).

Historical δ(I_P) is not restored, and no statement δ ∈ Δ(I_P) is introduced.

## Current consequence

    R-ASSEMBLY-4 = DECLARED (G2)
    DECISION_RULE_FAMILY_DEPENDENCE = PROJECTION_CANDIDATE
    𝒢_adm(P) ⊆ {g | g : W → A}
    g ∈ 𝒢_adm(P)

    R_OBJECT = NOT_DECLARED
    R_ASSEMBLY = OPEN
    R_ORACLE = NOT_DEFINED
    Δ = BLOCKED
    FinLoss = NOT LEGALLY AVAILABLE
    NECT = BLOCKED
    STEP⑤ = NOT ENTERED
    HARNESS AUTH = NONE
    EXPERIMENT AUTH = NONE

No implementation, harness, measurement, or experiment authorization is created by this declaration.
