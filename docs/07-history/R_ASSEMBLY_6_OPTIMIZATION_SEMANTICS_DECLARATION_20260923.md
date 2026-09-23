# R-ASSEMBLY-6 Optimization Semantics Declaration — 2026-09-23

## Researcher declaration

The researcher explicitly declared:

```
R-ASSEMBLY-6 = I2
```

## Declared semantic content

The optimization layer is represented as a two-stage construction:

```
L(g;P,θ) = E_θ[C_LOSS(g(W),W)]

R(P,θ) = OPT_{g ∈ 𝒢_adm(P)} L(g;P,θ)
```

The first stage is a rule-level aggregate evaluation. The second stage applies an abstract optimization operator over the P-dependent admissible rule family.

I2 intentionally keeps `OPT` abstract. It does not select among `min`, `inf`, `argmin`, or another concrete optimization operator.

## Consequences

The current assembly chain is now:

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
OPT over g ∈ 𝒢_adm(P)
    ↓
P-level aggregate decision-loss result
```

This declaration separates rule-level evaluation from the optimization step. It does not instantiate the probability measure, measurable structure, measurability proof, integrability, the exact parameter domain, the concrete admissible family, or the concrete optimization operator.

## What remains undeclared

```
OPT operator                      = UNDECLARED
min vs inf                        = UNDECLARED
argmin / optimizer existence      = UNDECLARED
optimization attainment           = UNDECLARED
exact 𝒢_adm(P)                    = UNDECLARED
exact Dom(R)                      = UNDECLARED
exact parameter domain            = UNDECLARED
expectation existence/finiteness  = GOVERNED BY EXISTING OPEN CONDITIONS
R_OBJECT exact signature          = OPEN
R_ORACLE                          = NOT_DEFINED
Δ                                 = BLOCKED
FinLoss                           = NOT LEGALLY AVAILABLE
NECT                              = BLOCKED
```

I2 therefore advances the assembly by declaring the separation between rule-level aggregate evaluation and the subsequent abstract optimization mechanism, without importing a specific optimization semantics.

## Boundary and authorization

This declaration does not restore historical `δ(I_P)` or `δ ∈ Δ(I_P)`. It does not define `R_oracle`, residual `Δ`, `FinLoss`, or `NECT`.

No implementation, harness, data collection, profiling, measurement, experiment, or STEP⑤/STEP⑥ authorization is created by this declaration.

## Current status

```
R-ASSEMBLY-6 = DECLARED (I2)
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
