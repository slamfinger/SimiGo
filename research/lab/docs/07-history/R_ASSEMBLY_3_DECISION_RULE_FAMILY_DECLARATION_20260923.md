# R-ASSEMBLY-3 Decision-Rule Family Declaration

**Date:** 2026-09-23  
**Researcher declaration:** R-ASSEMBLY-3 = F2

## Declaration

The researcher explicitly selected **R-ASSEMBLY-3 = F2**.

Therefore the decision-rule family is declared at the following structural level:

    𝒢_adm ⊆ { g | g : W → A }
    g ∈ 𝒢_adm

This declares an independent admissible decision-rule family rather than treating every mapping W→A as automatically eligible.

## Relation to prior assembly declarations

R-ASSEMBLY-1A, 1B, 1C and 2 remain unchanged. In particular:

    Γ(P, δ) : W → A
    Γ(P, δ) = g
    g : W → A
    a = g(w)

Under F2, the generated rule must additionally satisfy:

    g ∈ 𝒢_adm

## Critical separation

Rule-family admissibility is a component-level condition. It is distinct from the overall R-ASM-E composite admission predicate and from the optimization domain.

F2 does not declare the concrete definition of 𝒢_adm, its parameterization, additional structure, a guarantee that Γ(P,δ) lands in 𝒢_adm, the optimization domain/operator, minimum versus infimum, optimizer existence, or the exact Dom(R).

Historical δ(I_P) is not restored, and no statement δ ∈ Δ(I_P) is introduced.

## Current consequence

    R-ASSEMBLY-3 = DECLARED (F2)
    DECISION_RULE_FAMILY = INDEPENDENT_ADMISSIBLE_FAMILY
    𝒢_adm ⊆ {g | g : W → A}
    g ∈ 𝒢_adm

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