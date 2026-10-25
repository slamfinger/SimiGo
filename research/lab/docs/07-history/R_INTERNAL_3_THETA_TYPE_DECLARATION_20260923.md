# R-INTERNAL-3 — θ TYPE DECLARATION

Date: 2026-09-23

The researcher explicitly declared:

```text
R-INTERNAL-3 = θ2
θ : REGIME_PARAMETER
```

## Semantic declaration

θ is declared as the regime-parameter carrier corresponding to the previously declared `R-F = PARAMETERIZED_REGIME`.

This closes θ only at the declared type/semantic level. It does not instantiate:

- a concrete parameter set;
- topology, dimension, or coordinate representation;
- a concrete probability measure;
- a one-to-one identification with a particular probability-measure parameterization;
- measurability or integrability conditions;
- expectation existence or numerical values.

The declaration is compatible with R-ASM-B and R-ASM-D, which establish a regime-indexed workload-distribution / probability-measure family with a measurability requirement. Those interfaces remain abstract.

## Current assembly context

```text
P : PROJECTION_CANDIDATE
δ : DECISION_GENERATION_PARAMETER
θ : REGIME_PARAMETER

(P,δ) ↦ g
Γ(P,δ) = g
g : W → A
g ∈ 𝒢_adm(P)
L(g;P,θ) = E_θ[C_LOSS(g(W),W)]
R(P,θ) = OPT_{g ∈ 𝒢_adm(P)} L(g;P,θ)
```

The exact R_OBJECT input hierarchy remains undeclared under R-ASSEMBLY-10 = M4.

## Boundary

```text
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

No implementation, harness, data collection, profiling, measurement, or experiment authorization is created by this declaration.
