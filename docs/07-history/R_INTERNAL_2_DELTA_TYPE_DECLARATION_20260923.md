# R-INTERNAL-2 — δ Type Declaration

**Date:** 2026-09-23

## Researcher declaration

R-INTERNAL-2 = δ3

## Declared semantics

δ is declared as an abstract decision-generation parameter:

```text
δ : DECISION_GENERATION_PARAMETER
```

δ is therefore not declared to be the final decision rule itself. It participates with P as input to the already declared generation mechanism:

```text
(P, δ) ↦ g
Γ(P, δ) = g
g : W → A
```

## Compatibility

This declaration is consistent with:

- R-ASSEMBLY-1A = COMPOSITE_PROJECTION_RULE_PAIR;
- R-ASSEMBLY-1B = JOINT_COMPOSITE_OUTPUT_MECHANISM;
- R-ASSEMBLY-1C = C3;
- R-ASSEMBLY-2 = D2;
- R-ASSEMBLY-9 = L3;
- R-INTERNAL-1 = P4.

No identity `δ = g` is declared, and historical `δ(I_P)` is not restored.

## Non-imported semantics

This declaration does not instantiate the internal representation of δ, its parameter space, cardinality, topology, algebraic structure, relation to I_P, admissibility, optimization domain, or any dependence on θ. It does not define δ as a function W → A and does not introduce a new δ optimization domain.

It also does not instantiate θ, the structure of `𝒢_adm(P)`, the domain of L, expectation legality/existence, R_OBJECT, R_ORACLE, Δ, FinLoss, or NECT.

No implementation, harness, measurement, data collection, profiling, experiment, STEP⑤, or STEP⑥ authorization is created.

## State transition

```text
R-INTERNAL-2 = DECLARED (δ3)
R_OBJECT     = NOT_DECLARED
R_ASSEMBLY   = OPEN
R_ORACLE     = NOT_DEFINED
Δ            = BLOCKED
FinLoss      = NOT LEGALLY AVAILABLE
NECT         = BLOCKED
STEP⑤       = NOT ENTERED
STEP⑥       = NOT ENTERED
```
