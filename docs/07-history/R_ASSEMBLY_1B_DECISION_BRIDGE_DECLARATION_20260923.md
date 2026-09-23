# R-ASSEMBLY-1B · Decision Bridge Declaration

**Date:** 2026-09-23  
**Researcher declaration:** B3 — Joint `(P, δ)` output mechanism

## 1. Declaration

```text
R-ASSEMBLY-1B  DECISION_OUTPUT_BRIDGE = JOINT_COMPOSITE_OUTPUT_MECHANISM
EVALUATION_OBJECT = (P, δ)
OUTPUT_TARGET = a ∈ A
```

The researcher has declared that the composite evaluation object `(P, δ)` reaches the pointwise decision space `A` through a joint output mechanism associated with the pair `(P, δ)`.

## 2. Scope

This declaration establishes only the bridge kind:

```text
(P, δ) → joint output mechanism → a ∈ A
```

It does not instantiate:

```text
P signature
δ signature
the internal joint mechanism
I_P or P ↦ I_P
a concrete action/output map
decision-rule admissibility
workload dependence of the output
measure or measurability
integrability / expectation existence
optimization domain or operator
min versus inf
optimizer existence
R_OBJECT
R_oracle
Δ / FinLoss / NECT
```

## 3. Non-imported historical semantics

The declaration does not restore the historical construction `δ(I_P)`, `Δ(I_P)`, or any expression of the form `inf_{δ ∈ Δ(I_P)} ...`. Those remain separately undeclared.

## 4. Assembly consequence

The pointwise-loss path is now structurally constrained as:

```text
(P, δ)
    ↓
joint output mechanism
    ↓
a ∈ A
    ↓
C_LOSS(a, w)
    ↓
expectation over declared workload-distribution family
    ↓
rule-level aggregate evaluation
    ↓
optimization component
    ↓
P-level aggregate decision-loss object
```

This is a dependency skeleton, not a complete formula or a declaration of `R_OBJECT`.

## 5. Next dependencies

```text
R-ASSEMBLY-1A = DECLARED
R-ASSEMBLY-1B = DECLARED
R-ASSEMBLY-1C = OPEN
R_OBJECT      = NOT_DECLARED
R_ASSEMBLY    = OPEN
```

The next gate must determine the minimum semantics of the joint output mechanism itself before a legal aggregate object can be assembled.

No implementation, harness, measurement, or experiment authorization is created.
