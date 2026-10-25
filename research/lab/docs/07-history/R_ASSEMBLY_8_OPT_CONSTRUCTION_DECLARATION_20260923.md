# R-ASSEMBLY-8 OPT Construction Declaration

**Date:** 2026-09-23

## Researcher declaration

R-ASSEMBLY-8 = K3

The researcher declares the concrete mathematical construction of OPT to remain an abstract scalar optimization operator:

R(P,θ) = OPT_{g ∈ 𝒢_adm(P)} L(g;P,θ)

with the already declared type:

OPT : (𝒢_adm(P), L) → ℝ

## Semantic consequence

K3 keeps the optimization construction abstract. It does not select min, inf, argmin, or another named concrete operator.

Accordingly, this declaration does not assert optimizer existence, attainment, or the existence of a minimizing rule. It also does not instantiate the exact admissible rule family, optimization domain, parameter domain, expectation prerequisites, or the exact definition domain of R.

The scalar-result type declared by R-ASSEMBLY-7 remains in force and remains aligned with R-D = FINITE_REAL.

## Current assembly status

R-ASSEMBLY-1A = DECLARED
R-ASSEMBLY-1B = DECLARED
R-ASSEMBLY-1C = DECLARED (C3)
R-ASSEMBLY-2  = DECLARED (D2)
R-ASSEMBLY-3  = DECLARED (F2)
R-ASSEMBLY-4  = DECLARED (G2)
R-ASSEMBLY-5  = DECLARED (H2)
R-ASSEMBLY-6  = DECLARED (I2)
R-ASSEMBLY-7  = DECLARED (J1)
R-ASSEMBLY-8  = DECLARED (K3)

OPT : (𝒢_adm(P), L) → ℝ
R(P,θ) = OPT_{g ∈ 𝒢_adm(P)} L(g;P,θ)

K3 does not complete R_OBJECT. The exact final signature, definition domain, and all remaining component instantiations remain open.

No R_oracle, residual Δ, FinLoss, NECT, STEP⑤, STEP⑥, implementation, harness, measurement, or experiment authorization is created by this declaration.
