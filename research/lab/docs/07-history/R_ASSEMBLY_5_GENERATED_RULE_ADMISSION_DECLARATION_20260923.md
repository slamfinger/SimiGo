# R-ASSEMBLY-5 Generated Rule Admission Declaration

**Date:** 2026-09-23  
**Researcher declaration:** R-ASSEMBLY-5 = H2

## Declaration

```text
Γ(P, δ) = g
```

Generation and admissibility are declared as separate stages:

```text
Γ(P, δ) = g
        ↓
check:
    g ∈ 𝒢_adm(P) ?
        ↓
only an admitted g enters optimization
```

## Semantic meaning

H2 declares conditional admission. The generated rule g is not, by generation alone, guaranteed to belong to the P-specific admissible family. Membership in 𝒢_adm(P) is checked independently, and only an admitted rule is eligible for the optimization stage.

This preserves the prior declarations:

```text
R-ASSEMBLY-1C = C3
Γ(P, δ) : W → A

R-ASSEMBLY-2 = D2
Γ(P, δ) = g
g : W → A
a = g(w)

R-ASSEMBLY-3 = F2
𝒢_adm ⊆ { g | g : W → A }
g ∈ 𝒢_adm

R-ASSEMBLY-4 = G2
𝒢_adm(P) ⊆ { g | g : W → A }
```

With H2, the legally declared relationship is:

```text
Γ(P,δ) = g
AND
[g ∈ 𝒢_adm(P)] is an independent admission condition
```

The following are not declared:

- Γ(P,δ) automatically guarantees g ∈ 𝒢_adm(P);
- feasibility is built into Γ itself;
- a concrete definition of 𝒢_adm(P);
- the rule-admission predicate's internal structure;
- the optimization domain or operator;
- minimum versus infimum;
- optimizer existence or attainment;
- a concrete parameterization of the rule family;
- any direct dependence on δ or θ beyond the already declared (P,δ) generation mechanism;
- restoration of historical δ(I_P) or δ ∈ Δ(I_P).

## Assembly consequence

The current semantic chain becomes:

```text
(P, δ)
    ↓
Γ(P, δ) = g
    ↓
g : W → A
    ↓
independent admission check
    ↓
g ∈ 𝒢_adm(P) ?
    ↓
if admitted → optimization
if not admitted → no optimization entry for g
```

This is a semantic declaration only. It does not instantiate R_OBJECT, R_ORACLE, Δ, FinLoss, NECT, STEP⑤, implementation, harness, measurement, or experiment authorization.

## Status

```text
R-ASSEMBLY-5 = DECLARED (H2)
R_OBJECT = NOT_DECLARED
R_ASSEMBLY = OPEN
R_ORACLE = NOT_DEFINED
Δ = BLOCKED
FinLoss = NOT LEGALLY AVAILABLE
NECT = BLOCKED
STEP⑤ = NOT ENTERED
HARNESS AUTH = NONE
EXPERIMENT AUTH = NONE
```
