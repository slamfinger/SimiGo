# R-INTERNAL-6 — Expectation Legality / Definition Conditions

Date: 2026-09-23

## Researcher declaration

```
R-INTERNAL-6 = E6-4

(g,P,θ) ∈ Dom(L)
    ⇔
E_θ[C_LOSS(g(W),W)] 合法且为有限实数
```

## Semantic meaning

E6-4 conditions the domain of the already-declared loss evaluation function directly on the legality and finite-real status of its expectation. It does not expand “合法” into a separate declaration of measurability, integrability, or a particular existence theorem.

This closes the expectation legality boundary at the domain-condition level while preserving the previously declared interfaces:

```
L : Dom(L) → ℝ

L(g;P,θ) = E_θ[C_LOSS(g(W),W)]
R(P,θ) = OPT_{g ∈ 𝒢_adm(P)} L(g;P,θ)
```

The declaration does not select a concrete probability space, parameter set, measure notation beyond the already declared parameter-indexed probability-measure family, measurable-space representation, integrability condition, optimization construction, optimizer existence, or final R_OBJECT hierarchy.

## Boundary

E6-4 does not by itself declare:
- a concrete definition of “合法”;
- a separate measurability theorem or integrability class;
- optimizer existence or attainment;
- a concrete R_OBJECT;
- R_oracle;
- Δ;
- FinLoss;
- NECT;
- STEP⑤/STEP⑥ entry;
- implementation, harness, data collection, profiling, measurement, or experiment authorization.

## Current state consequence

```
R-INTERNAL-1 = P4
R-INTERNAL-2 = δ3
R-INTERNAL-3 = θ2
R-INTERNAL-4 = G4-4
R-INTERNAL-5 = L5-3
R-INTERNAL-6 = E6-4

(g,P,θ) ∈ Dom(L)
    ⇔
E_θ[C_LOSS(g(W),W)] 合法且为有限实数

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
