# R-ASSEMBLY-7 OPT Semantic Type Declaration — 2026-09-23

## Researcher declaration

The researcher explicitly declared:

```
R-ASSEMBLY-7 = J1
```

## Declared semantic content

`OPT` is declared as a scalar-value optimization operator:

```
OPT : (𝒢_adm(P), L) → ℝ

R(P,θ) = OPT_{g ∈ 𝒢_adm(P)} L(g;P,θ)
```

This fixes the semantic output type of `OPT` as a scalar finite-real aggregate result. It does not declare `OPT` to return an optimizing rule `g*`.

J1 therefore preserves R-D = FINITE_REAL while keeping the internal optimization construction abstract.

## Consequences

```
(P, δ)
    ↓
Γ(P, δ) = g
    ↓
g : W → A
    ↓
g ∈ 𝒢_adm(P) ?
    ↓
admitted g
    ↓
L(g;P,θ) = E_θ[C_LOSS(g(W),W)]
    ↓
OPT : (𝒢_adm(P), L) → ℝ
    ↓
R(P,θ) ∈ ℝ
```

J1 does not require an explicit optimizer output or an assertion that an optimizer is attained.

## What remains undeclared

```
concrete OPT operator              = UNDECLARED
min vs inf                         = UNDECLARED
argmin / optimizer existence       = UNDECLARED
optimization attainment            = UNDECLARED
exact 𝒢_adm(P)                     = UNDECLARED
exact Dom(R)                       = UNDECLARED
exact parameter domain             = UNDECLARED
expectation existence/finiteness  = GOVERNED BY OPEN CONDITIONS
R_OBJECT exact signature           = OPEN
R_ORACLE                           = NOT_DEFINED
Δ                                  = BLOCKED
FinLoss                            = NOT LEGALLY AVAILABLE
NECT                               = BLOCKED
```

## Boundary and authorization

This declaration does not restore historical `δ(I_P)` or `δ ∈ Δ(I_P)`. It does not define `R_oracle`, residual `Δ`, `FinLoss`, or `NECT`.

No implementation, harness, data collection, profiling, measurement, experiment, or STEP⑤/STEP⑥ authorization is created by this declaration.

## Current status

```
R-ASSEMBLY-7 = DECLARED (J1)
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
