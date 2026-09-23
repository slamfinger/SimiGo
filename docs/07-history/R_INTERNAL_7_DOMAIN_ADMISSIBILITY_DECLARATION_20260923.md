# R-INTERNAL-7 — Domain Admissibility Declaration

Date: 2026-09-23

## Researcher declaration

```
R-INTERNAL-7 = E7-B
```

## Semantic declaration

```
(g,P,θ) ∈ Dom(L) ⇒ g ∈ 𝒢_adm(P)
```

This declares that any triple admitted to the already-defined loss-evaluation domain must use a decision rule belonging to the P-dependent admissible decision-rule family.

The declaration is one-way. It does not assert that every admissible rule belongs to `Dom(L)`; therefore it does not make admissibility sufficient for expectation legality or finite-real evaluation.

## Preserved boundaries

The declaration preserves:

```
P : PROJECTION_CANDIDATE
δ : DECISION_GENERATION_PARAMETER
θ : REGIME_PARAMETER

𝒢_adm(P) = ADMISSIBLE_DECISION_RULE_FAMILY
𝒢_adm(P) ⊆ { g | g : W → A }

L : Dom(L) → ℝ

(g,P,θ) ∈ Dom(L)
    ⇔
E_θ[C_LOSS(g(W),W)] 合法且为有限实数
```

Therefore E7-B adds only the necessary admissibility implication. It does not define the concrete family, its membership predicate beyond the existing family declaration, the converse implication, the probability space, parameter domain, integrability, a concrete optimization operator, optimizer existence/attainment, R_OBJECT, R_oracle, Δ, FinLoss, NECT, STEP⑤/STEP⑥ entry, implementation, harness, data collection, profiling, measurement, or experiment authorization.

Historical `δ(I_P)` is not restored, and no new δ optimization domain is introduced.

## Current gate state

```
R-INTERNAL-1 = DECLARED (P4)
R-INTERNAL-2 = DECLARED (δ3)
R-INTERNAL-3 = DECLARED (θ2)
R-INTERNAL-4 = DECLARED (G4-4)
R-INTERNAL-5 = DECLARED (L5-3)
R-INTERNAL-6 = DECLARED (E6-4)
R-INTERNAL-7 = DECLARED (E7-B)

R_OBJECT     = NOT_DECLARED
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

No implementation, harness, measurement, data collection, profiling, or experiment authorization is created by this declaration.
