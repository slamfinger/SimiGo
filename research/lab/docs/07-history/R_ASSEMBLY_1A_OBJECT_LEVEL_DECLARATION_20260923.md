# R-ASSEMBLY-1A · Evaluation Object Level Declaration

**Date:** 2026-09-23  
**Researcher declaration:** Option ③ — `(P, δ)`

## 1. Declaration

```text
R-ASSEMBLY-1A  EVALUATION_OBJECT_LEVEL = COMPOSITE_PROJECTION_RULE_PAIR
EVALUATION_OBJECT = (P, δ)
```

The evaluation object is declared at the composite level of a projection candidate `P` paired with a decision rule `δ`.

## 2. Scope

This declaration establishes only the object-level pairing:

```text
(P, δ) = candidate evaluation object level
```

It does not instantiate:

```text
δ signature
P signature
P → decision-rule-family bridge
δ output ∈ A bridge
I_P or P ↦ I_P
rule admissibility
measure or measurability
integrability / expectation existence
optimization domain or operator
min versus inf
R_OBJECT
R_oracle
Δ / FinLoss / NECT
```

## 3. Non-imported historical semantics

The declaration does not restore the historical construction `δ(I_P)`, `Δ(I_P)`, or any expression of the form `inf_{δ ∈ Δ(I_P)} ...`. Those remain separately undeclared.

## 4. Next dependencies

```text
R-ASSEMBLY-1A = DECLARED
R-ASSEMBLY-1B = OPEN
R-ASSEMBLY-1C = BLOCKED_BY_1B
R_OBJECT     = NOT_DECLARED
R_ASSEMBLY   = OPEN
```

The next decision surface is the bridge from the composite object `(P, δ)` to the pointwise decision output required by `C_LOSS : A × W → ℝ`.

No implementation, harness, measurement, or experiment authorization is created.
