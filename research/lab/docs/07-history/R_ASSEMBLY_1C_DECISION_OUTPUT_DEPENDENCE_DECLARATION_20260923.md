# R-ASSEMBLY-1C · Decision Output Dependence Declaration

Date: 2026-09-23

## Researcher declaration

~~~text
R-ASSEMBLY-1C
DECISION_OUTPUT_DEPENDENCE = C3

JOINT_OUTPUT_MECHANISM:
    Γ(P, δ) : W → A

POINTWISE_OUTPUT:
    a = Γ(P, δ)(w)

POINTWISE_LOSS:
    C_LOSS(Γ(P, δ)(w), w)
~~~

## Meaning

The researcher explicitly selected **C3**: the composite evaluation object `(P, δ)` produces a decision mapping over the workload carrier `W`; a concrete workload instance `w` is then supplied to that mapping to obtain the action `a ∈ A`.

Thus the decision-output dependence is:

~~~text
(P, δ)
    ↓
Γ(P, δ) : W → A
    ↓  applied to w
a = Γ(P, δ)(w) ∈ A
    ↓
C_LOSS(a, w)
~~~

This is distinct from:

~~~text
C1:
    a = Γ(P, δ)

C2:
    a = Γ(P, δ, w)
~~~

C3 does not declare that the workload **distribution** itself is directly an input to the decision mapping. It declares that the workload **instance** `w` is the argument of the decision mapping produced by `(P, δ)`.

## Deliberately not declared

~~~text
P's concrete representation
δ's concrete signature
W's concrete measurable-space representation
A's concrete action structure
Γ's concrete functional form
decision-rule admissibility
parameter domain / θ
measure notation or a specific probability measure
measurability proof
integrability
expectation existence
optimization domain/operator
min vs inf
optimizer existence
R_OBJECT
R_oracle
Δ
FinLoss
NECT
~~~

It also does not restore the historical `δ(I_P)` construction.

## Consequence for the assembly

The previously open bridge is now semantically constrained as:

~~~text
EVALUATION_OBJECT = (P, δ)

(P, δ)
    ↓
decision mapping Γ(P, δ) : W → A
    ↓
a = Γ(P, δ)(w)
    ↓
C_LOSS(a, w)
    ↓
expectation over the declared workload-distribution family
    ↓
rule-level aggregate evaluation
    ↓
optimization component
    ↓
P-level aggregate decision-loss object
~~~

The chain remains a dependency skeleton, not a complete formula for `R`.

Accordingly:

~~~text
R-ASSEMBLY-1A = DECLARED
R-ASSEMBLY-1B = DECLARED
R-ASSEMBLY-1C = DECLARED (C3)
R_OBJECT      = NOT_DECLARED
R_ASSEMBLY    = OPEN
R_oracle      = NOT_DEFINED
Δ             = BLOCKED
FinLoss       = NOT LEGALLY AVAILABLE
STEP⑤         = NOT ENTERED
EXPERIMENT AUTH = NONE
~~~

No implementation, harness, measurement, or experiment authorization is created by this declaration.