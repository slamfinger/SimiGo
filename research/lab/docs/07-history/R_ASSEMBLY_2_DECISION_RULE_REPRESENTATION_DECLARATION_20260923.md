# R-ASSEMBLY-2 Decision Rule Representation Declaration

**Date:** 2026-09-23

## Researcher declaration

The researcher explicitly declared:

```text
R-ASSEMBLY-2 = D2
```

Therefore the decision-rule representation is declared as:

```text
DECISION_RULE_REPRESENTATION = GENERATED_RULE

Γ(P, δ) = g
g : W → A

a = g(w)
```

Under D2, the composite evaluation object `(P, δ)` does not itself become the final decision rule by identity. Instead, `(P, δ)` participates in generating a decision rule `g : W → A` through the already declared joint output mechanism.

This is a semantic declaration at the minimum rule-representation level. It does not instantiate the generation map, the concrete signatures of `P` or `δ`, the admissible rule family, or the conditions under which the generated `g` is admitted.

## Consequence for the existing C3 declaration

The previously declared R-ASSEMBLY-1C = C3 is preserved:

```text
Γ(P, δ) : W → A
a = Γ(P, δ)(w)
```

D2 now gives the interpretation:

```text
Γ(P, δ) = g
g : W → A
a = g(w)
```

and therefore:

```text
C_LOSS(g(w), w)
```

is the pointwise-loss expression induced by the generated decision rule.

D2 is distinct from D1:

```text
D1:
δ : W → A
Γ(P,δ) = δ

D2:
Γ(P,δ) = g
g : W → A
```

No identity `g = δ` is declared.

## What remains undeclared

D2 does not by itself declare:

- the concrete generation operator `Γ`;
- the signature or internal structure of `P`;
- the signature or internal structure of `δ`;
- the admissible decision-rule family;
- the rule-admission predicate;
- the mapping from projection candidate to admissible generated rule;
- the parameter domain;
- the measurable structure on `W`;
- the concrete probability-measure family;
- measurability or integrability proofs;
- the optimization domain or operator;
- minimum versus infimum;
- optimizer existence or attainment;
- the exact composite `Dom(R)`;
- `R_OBJECT`;
- `R_oracle`;
- residual `Δ`;
- `FinLoss`;
- `NECT`;
- STEP⑤, implementation, harness, measurement, or experiment authorization.

Historical `δ(I_P)` is not restored by this declaration.

## Current structural chain

```text
(P, δ)
    ↓
Γ(P, δ) = g
    ↓
g : W → A
    ↓  applied to w
a = g(w)
    ↓
C_LOSS(g(w), w)
    ↓
expectation over the declared workload-distribution family
    ↓
rule-level aggregate evaluation
    ↓
optimization component
    ↓
P-level aggregate decision-loss object
```

This remains a dependency skeleton, not a complete formula for `R_OBJECT`.

## Gate status after declaration

```text
R-ASSEMBLY-1A = DECLARED
R-ASSEMBLY-1B = DECLARED
R-ASSEMBLY-1C = DECLARED (C3)
R-ASSEMBLY-2  = DECLARED (D2)

R_OBJECT      = NOT_DECLARED
R_ASSEMBLY    = OPEN
R_oracle      = NOT_DEFINED
Δ             = BLOCKED
FinLoss       = NOT LEGALLY AVAILABLE
NECT          = BLOCKED
STEP⑤         = NOT ENTERED
EXPERIMENT AUTH = NONE
HARNESS AUTH    = NONE
```

No implementation, harness, measurement, or experiment authorization is created by R-ASSEMBLY-2.
