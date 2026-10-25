# R-INTERNAL-4 — 𝒢_adm(P) STRUCTURE / TYPE DECLARATION

Date: 2026-09-23

The researcher explicitly declared:

```text
R-INTERNAL-4 = G4-4

𝒢_adm(P) = ADMISSIBLE_DECISION_RULE_FAMILY
𝒢_adm(P) ⊆ {g | g : W → A}
```

## Semantic boundary

This closes the structure/type level of the P-dependent admissible decision-rule family while preserving the minimum abstract representation already established by R-ASSEMBLY-3 = F2 and R-ASSEMBLY-4 = G2.

No separate candidate-rule space, rule-parameter space, or additional parameter such as η is introduced.

The declaration does not:

- identify δ with a rule parameter;
- make δ a function W → A;
- introduce θ-dependence into 𝒢_adm(P);
- instantiate the concrete family;
- define its membership predicate;
- impose topology or measurable structure;
- parameterize the family;
- instantiate the optimization operator;
- establish optimizer existence or attainment;
- define the exact Dom(R).

## Current chain

```text
P : PROJECTION_CANDIDATE
δ : DECISION_GENERATION_PARAMETER
θ : REGIME_PARAMETER

𝒢_adm(P) = ADMISSIBLE_DECISION_RULE_FAMILY
𝒢_adm(P) ⊆ {g | g : W → A}

Γ(P,δ) = g
        ↓
g ∈ 𝒢_adm(P) ?
        ↓
L(g;P,θ) = E_θ[C_LOSS(g(W),W)]
        ↓
OPT
```

The family remains P-dependent only, as declared by G2.

## Gate status

```text
R-INTERNAL-1 = DECLARED (P4)
R-INTERNAL-2 = DECLARED (δ3)
R-INTERNAL-3 = DECLARED (θ2)
R-INTERNAL-4 = DECLARED (G4-4)

R_OBJECT     = NOT_DECLARED
R_ASSEMBLY   = OPEN
R_ORACLE     = NOT_DEFINED
Δ            = BLOCKED
FinLoss      = NOT LEGALLY AVAILABLE
NECT         = BLOCKED
STEP⑤       = NOT ENTERED
STEP⑥       = NOT ENTERED
EXPERIMENT AUTH = NONE
HARNESS AUTH    = NONE
```

No implementation, harness, measurement, data collection, profiling, or experiment authorization is created by this declaration.
