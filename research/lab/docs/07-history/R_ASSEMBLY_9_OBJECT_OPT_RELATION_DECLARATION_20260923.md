# R-ASSEMBLY-9 Object–Optimization Relation Declaration

**Date:** 2026-09-23

## Declaration

R-ASSEMBLY-9 = L3

## Declared semantics

The composite evaluation object remains `(P, δ)`. The joint generation bridge produces a decision rule `g`, with `(P,δ) ↦ g` and `Γ(P,δ)=g`.

The optimization component remains rule-level and continues to act on `g`:

`R(P,θ) = OPT_{g ∈ 𝒢_adm(P)} L(g;P,θ)`

Thus `(P,δ)` is the evaluation object and generation input, but is not thereby declared to be the optimization variable. No new optimization domain for `δ` is introduced.

## Boundary preserved

This declaration does not instantiate `Γ`, `P`, `δ`, `𝒢_adm(P)`, the parameter domain, the workload-distribution measure family, measurability/integrability requirements, the concrete construction of `OPT`, optimizer existence/attainment, `Dom(R)`, `R_OBJECT`, `R_oracle`, `Δ`, `FinLoss`, or `NECT`.

No implementation, experiment, harness, data collection, or STEP⑤ authorization follows from this declaration.
