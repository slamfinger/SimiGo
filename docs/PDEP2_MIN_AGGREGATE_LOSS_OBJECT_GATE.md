# PDEP-2 Minimum Aggregate Decision-Loss Object Gate

**Date:** 2026-09-23  
**Status:** R-A–R-F DECLARED / R-ASM-A DECLARED / R-ASM-B DECLARED / R-ASM-C DECLARED / R-ASM-D DECLARED / R-ASM-E DECLARED / R-ASM-F DECLARED / R-ASSEMBLY-1A DECLARED / R-ASSEMBLY-1B DECLARED / R-ASSEMBLY-1C DECLARED / R-ASSEMBLY-2 DECLARED / R-ASSEMBLY-3 DECLARED / R-ASSEMBLY-4 DECLARED (G2) / R_OBJECT ASSEMBLY GATE OPEN / R_OBJECT NOT DECLARED

## 1. Gate Purpose

PDEP-2 has selected the proposition-level route:

```text
PDEP-2 ROUTE = AGGREGATE_DECISION_LOSS
```

The purpose of this gate is to determine the minimum semantic components required before an aggregate decision-loss object can legally exist above the current pointwise cost object.

The researcher has now declared all six minimum aggregate-object semantic axes. R-ASM-F is declared as COMPOSITE_SIGNATURE. R-ASSEMBLY-1A has declared the evaluation object level as (P, δ), and R-ASSEMBLY-1B has now declared the decision-output bridge as a joint (P, δ) output mechanism. The remaining task is to determine whether, and exactly how, these declarations can be assembled into a legally defined minimum R_OBJECT without importing undeclared semantics.

## 2. Current Boundary

```text
C_LOSS : A × W → ℝ
        ↓
PDEP-2
        ↓
aggregate decision-loss layer
        ↓
R-A = PROJECTION_CANDIDATE
R-B = WORKLOAD_DISTRIBUTION
R-C = EXPECTATION_OVER_WORKLOAD_DISTRIBUTION
R-D = FINITE_REAL
R-E = PARTIAL_DEFINEDNESS
R-F = PARAMETERIZED_REGIME
        ↓
R_OBJECT = NOT_DECLARED
```

The pointwise loss interface remains closed:

```text
C_LOSS : A × W → ℝ = CLOSED
C_LOSS ↔ R BRIDGE = STRUCTURALLY CONSTRAINED / NOT FULLY INSTANTIATED
```

No aggregate construction has yet been declared.

## 3. Current Researcher Declarations

```text
R_OBJECT                    = NOT_DECLARED
R_ASM-A POINTWISE_LOSS_CARRIER = C_LOSS
R_ASM-B REGIME_DISTRIBUTION_INTERFACE = REGIME_INDEXED_WORKLOAD_DISTRIBUTION_FAMILY

R-A  EVALUATION_TARGET      = PROJECTION_CANDIDATE
R-B  EVALUATION_INPUT       = WORKLOAD_DISTRIBUTION
R-C  AGGREGATION_RULE       = EXPECTATION_OVER_WORKLOAD_DISTRIBUTION
R-D  RESULT CODOMAIN        = FINITE_REAL
R-E  DEFINEDNESS / TOTALITY = PARTIAL_DEFINEDNESS
R-F  PARAMETER / REGIME     = PARAMETERIZED_REGIME

C_LOSS : A × W → ℝ          = CLOSED
C_LOSS ↔ R BRIDGE = STRUCTURALLY CONSTRAINED / NOT FULLY INSTANTIATED

W measurable structure     = DECLARED AT FAMILY INTERFACE LEVEL
μ_W formal object          = PARAMETER-INDEXED PROBABILITY-MEASURE FAMILY DECLARED
C_LOSS measurability       = REQUIREMENT DECLARED
expectation                 = SELECTED AS AGGREGATION RULE; MATHEMATICAL INSTANTIATION STILL REQUIRES THE DECLARED MEASURABILITY / DEFINEDNESS CONDITIONS
```

These are researcher-level declarations. No remaining open value is inferred from R-A or R-B.

## 4. Meaning of R-A

```text
EVALUATION_TARGET = PROJECTION_CANDIDATE
```

This declares the class of entity that the future aggregate decision-loss object is intended to evaluate at the target level.

It does **not** yet declare:

- the representation of a projection candidate;
- the domain or codomain of a projection candidate;
- a projection operator;
- how a projection candidate produces decision outputs;
- how a projection candidate connects to `A`, `W`, `W_D`, `I_P`, or `δ`;
- how `C_LOSS` is invoked;
- any aggregation rule;
- any oracle comparison;
- any residual or FinLoss predicate.

Thus:

```text
R-A declaration
    ≠
R_OBJECT definition
```

## 5. Meaning of R-B

```text
EVALUATION_INPUT = WORKLOAD_DISTRIBUTION
```

This declares that the evaluation input to the future aggregate decision-loss layer is a workload-distribution object.

The declaration is intentionally limited to the role of the evaluation input. R-ASM-B further declares that this input is exposed as a family indexed by the regime/parameter dimension. It does **not** instantiate a particular mathematical probability or measure-theoretic structure.

In particular, the following remain undeclared or uninstantiated:

```text
W measurable structure = UNDECLARED
μ_W formal object     = NOT INSTANTIATED
C_LOSS measurability  = UNDECLARED
expectation           = NOT DECLARED
```

Therefore:

```text
WORKLOAD_DISTRIBUTION
    ≠
probability space declaration
    ≠
μ_W instantiation
    ≠
expectation declaration
```

R-B also does not determine the aggregation rule. The future R-C gate must independently state how the workload-distribution input participates in aggregate loss.

## 6. R-C Declaration

```text
R-C AGGREGATION_RULE = EXPECTATION_OVER_WORKLOAD_DISTRIBUTION
```

This is a researcher-level semantic declaration. It establishes that the aggregate decision-loss layer is to aggregate pointwise loss through an expectation taken with respect to the declared workload-distribution input.

It does **not** yet legally instantiate a probability space or measurable space on `W`, a particular measure/probability measure `μ_W`, measurability of the workload-dependent loss mapping, integrability, finiteness of the resulting expectation, the result codomain, aggregate totality/definedness, any parameter `θ`, or an oracle/residual comparison.

Therefore:

```text
R-C = EXPECTATION_OVER_WORKLOAD_DISTRIBUTION
    ≠
μ_W already instantiated
    ≠
expectation already mathematically defined
    ≠
finite aggregate loss already established
```

The expectation operator is now selected, but its mathematical prerequisites remain separate gates.

## 7. Remaining Decision Surface

### R-C — Aggregation Rule

```text
R-C = DECLARED
```

Expectation over the declared workload distribution is now the selected aggregation rule. Its underlying measure/measurable structure and expectation-definedness remain separate gates.

### R-D — Result Codomain

```text
R-D = FINITE_REAL
```

The aggregate decision-loss result is declared to have finite-real codomain. This is a researcher-level declaration for the aggregate object; it does not by itself establish that the expectation exists, is finite, or is total on any domain. Those questions remain governed by R-E.

The fact that `C_LOSS` has finite-real codomain does not by itself determine the aggregate codomain.

### R-E — Definedness / Totality

```text
R-E = PARTIAL_DEFINEDNESS
```

The aggregate decision-loss object is declared as partial: it is defined only on an explicitly declared subset of otherwise candidate inputs. Inputs outside that declared definition domain are not assigned an aggregate decision-loss value. This declaration does not yet specify the definition-domain conditions, and does not by itself instantiate measure, measurability, integrability, or expectation existence.

### R-F — Parameter / Regime

```text
R-F = PARAMETERIZED_REGIME
```

The aggregate decision-loss object is declared to retain a parameter/regime dimension. The aggregate object therefore remains parameterized rather than being reduced to an unparameterized object. This declaration does not yet define the parameter `θ`, its domain, its components, its semantics, or how it enters the workload distribution, projection candidate, pointwise loss, or expectation.

## 8. Expectation-Specific Dependencies

Because R-C selects expectation, the following dependencies are now explicit research gates rather than background assumptions:

```text
WORKLOAD_DISTRIBUTION
        ↓
? measurable structure on W
        ↓
? μ_W
        ↓
? loss mapping induced by projection candidate
        ↓
? measurability
        ↓
? integrability / expectation existence
        ↓
aggregate expectation
```

R-C does not resolve these prerequisites automatically.

## 9. C_LOSS Boundary

The current pointwise interface remains:

```text
C_LOSS : D_C → ℝ
D_C = A × W
```

with the current LOSS-4 status that `D_C=A×W` is an MFI placeholder.

R-B does not bridge this interface to an aggregate object.

Therefore:

```text
C_LOSS ↔ R BRIDGE = STRUCTURALLY CONSTRAINED / NOT FULLY INSTANTIATED
```

A future bridge must explicitly state how a projection candidate and a workload-distribution input induce the arguments of `C_LOSS`, and how those pointwise evaluations enter the aggregate object.

No measurability or expectation semantics are imported by this bridge requirement.

## 10. Critical Separation

The following remain distinct:

```text
projection candidate
        ≠
workload distribution
        ≠
C_LOSS pointwise evaluation
        ≠
aggregation rule
        ≠
R object
        ≠
R_oracle
        ≠
residual Δ
        ≠
FinLoss
```

Selecting R-B does not legally imply any of the subsequent objects.

## 11. Gate Status

```text
R-A = DECLARED
R-B = DECLARED
R-C = DECLARED
R-D = DECLARED
R-E = DECLARED
R-F = DECLARED

R_OBJECT = NOT_DECLARED
R_ORACLE = NOT_DEFINED
Δ = BLOCKED
FinLoss = NOT LEGALLY AVAILABLE
NECT = BLOCKED
STEP⑥ = NOT ENTERED
EXPERIMENT AUTH = NONE
HARNESS AUTH = NONE
```

R-A through R-F have now received researcher-level declarations. These declarations define the remaining semantic axes of the minimum aggregate-loss object gate, but they do not by themselves instantiate R_OBJECT. No automatic measure, expectation evaluation, aggregate object, oracle, or residual is instantiated.


## 12. R-ASM · R_OBJECT Minimal Assembly Gate

R-A through R-F define six semantic axes but do not by themselves compose a complete, evaluable, type-consistent mathematical object.

Current assembly status:

```
R_OBJECT            = NOT_DECLARED
R_ASSEMBLY          = OPEN
C_LOSS ↔ R BRIDGE   = NOT_DECLARED
```

### 12.1 Assembly gaps

The following interfaces remain independently unresolved:

1. **Pointwise loss carrier adoption — RESOLVED**
   ```
   R-ASM-A  POINTWISE_LOSS_CARRIER = C_LOSS
   ```
   The researcher has explicitly declared that the existing closed `C_LOSS : A × W → ℝ` is the pointwise loss carrier used by the PDEP-2 aggregate decision-loss layer. This does not alter the LOSS-3 / LOSS-4 definition or retroactively identify `C_LOSS` with any historical cost slot, Value object, Risk object, or R object. It establishes only the carrier role within the future R assembly.

2. **Decision bridge**
   Historical `δ(I_P)` cannot be treated as a current action-producing construction. The current framework has not declared `I_P`, `P ↦ I_P`, `Δ(I_P)`, `δ)'s signature, or `δ(I_P) ∈ A`.

3. **Workload-distribution / measure interface**
   `R-B` and `R-C` do not instantiate a measurable structure on `W`, a measure `μ_W), a parameter-to-distribution mapping, or expectation prerequisites.

4. **Measurability and integrability**
   `C_LOSS)'s finite-real codomain does not establish measurability or integrability. `R-D=FINITE_REAL` constrains the aggregate result but does not establish existence or finiteness of the expectation.

5. **P-level versus decision-rule-level result**
   A construction of the form
   ```
   R_δ(P,θ) = E[C_LOSS(δ(I_P),w)]
   ```
   would be a decision-rule-level aggregate evaluation. It does not by itself yield historical `R(P;θ)`. An explicit rule is required for eliminating or retaining `δ`.

### 12.2 R-ASM declaration surface

R-ASM-A, R-ASM-B, and R-ASM-C have now been explicitly selected by the researcher. The remaining ASM semantic values remain researcher-decision fields:

```
R-ASM-A  POINTWISE_LOSS_CARRIER = C_LOSS
R-ASM-B  REGIME_DISTRIBUTION_INTERFACE = REGIME_INDEXED_WORKLOAD_DISTRIBUTION_FAMILY
R-ASM-C  DECISION_BRIDGE_KIND = DECISION_RULE_FAMILY_WITH_OPTIMIZATION
R-ASM-D  MEASURE / MEASURABILITY = PARAMETER_INDEXED_PROBABILITY_MEASURE_FAMILY_WITH_MEASURABILITY_REQUIREMENT
R-ASM-C  DECISION_BRIDGE_KIND = DECISION_RULE_FAMILY_WITH_OPTIMIZATION
R-ASM-D  MEASURE / MEASURABILITY = PARAMETER_INDEXED_PROBABILITY_MEASURE_FAMILY_WITH_MEASURABILITY_REQUIREMENT
R-ASM-E  ADMISSION_PREDICATE / Dom(R) = COMPOSITE_ADMISSION_PREDICATE
R-ASM-F  FINAL_OBJECT_SIGNATURE = COMPOSITE_SIGNATURE
```

Current declaration status:

```
R-ASM-A = DECLARED
R-ASM-B = DECLARED
R-ASM-C = DECLARED
R-ASM-D = DECLARED
R-ASM-E = DECLARED
R-ASM-F = NOT_DECLARED
```

Candidate values are not selected by the agent. In particular, no historical `δ(I_P)`, optimization over `Δ(I_P)`, probability measure, fixed action map, or final signature is silently adopted.

### 12.3 R-ASM-E declaration record

The researcher has explicitly declared:

```text
R-ASM-E  ADMISSION_PREDICATE / Dom(R)
        = COMPOSITE_ADMISSION_PREDICATE
```

This declares that the admissible domain of the aggregate decision-loss object is governed by a composite admission predicate rather than by a single isolated condition.

The declaration is intentionally **predicate-family level** and does not silently instantiate the component predicates or their exact logical form. In particular, it does not by itself select or define:

```text
projection / regime admissibility predicate
measurability predicate
integrability predicate
expectation-existence predicate
finite-real-result predicate
logical conjunction / disjunction structure
parameter-domain conditions
decision-rule admissibility conditions
```

The declaration therefore establishes the following semantic direction only:

```text
candidate aggregate input
        ↓
COMPOSITE_ADMISSION_PREDICATE
        ↓
if admitted: aggregate decision-loss object may be defined
if not admitted: R has no value at that input
```

It does not itself prove that any concrete candidate satisfies the predicate, nor does it instantiate `Dom(R)` as a concrete set.

Accordingly:

```text
R-ASM-E = DECLARED
R_OBJECT = NOT_DECLARED
R_ASSEMBLY = OPEN
R_oracle = NOT_DEFINED
Δ = BLOCKED
FinLoss = NOT LEGALLY AVAILABLE
```

No STEP⑤, harness, implementation, measurement, or experiment authorization is created by this declaration.

### 12.4 Minimal placeholder only

Before the remaining ASM fields are resolved, the strongest current statement is only:

```
Dom(R) = UNDECLARED
R : Dom(R) → ℝ
```

where even this is a typed placeholder expressing R-D/R-E, not a declared R object.

Therefore:

```
R_OBJECT = NOT_DECLARED
R_ASSEMBLY = OPEN
R-ASM-A = DECLARED (C_LOSS)
```

Completion of R-ASM does not automatically authorize `R_oracle`, residual `Δ`, FinLoss, NECT, STEP⑤, implementation, harness, or experiment.


## 13. R-ASM-B declaration record

The researcher has explicitly declared:

```
R-ASM-B  REGIME_DISTRIBUTION_INTERFACE
        = REGIME_INDEXED_WORKLOAD_DISTRIBUTION_FAMILY
```

This records the regime/parameter-indexed family role of the workload-distribution input. It does not instantiate a concrete parameter domain, measurable structure, measure family, or probability-space semantics.

## 14. R-ASM-C declaration record

The researcher has explicitly declared:

```
R-ASM-C  DECISION_BRIDGE_KIND
        = DECISION_RULE_FAMILY_WITH_OPTIMIZATION
```

This establishes the decision bridge as a family of decision rules together with an optimization operation that maps the rule-level aggregate evaluation toward the P-level aggregate decision-loss object.

The declaration is intentionally **structural but not yet fully instantiated**. It does not silently restore the historical `δ(I_P)`, `Δ(I_P)`, or any particular optimization expression. In particular, the following remain independently undeclared:

```
I_P representation                    = UNDECLARED
P ↦ I_P                               = UNDECLARED
decision-rule family / admissibility  = NOT INSTANTIATED
decision-rule signature               = UNDECLARED
optimization domain                   = UNDECLARED
optimization operator                 = UNDECLARED
minimum vs infimum                     = UNDECLARED
attainment / optimizer existence      = UNDECLARED
projection candidate → rule family    = UNDECLARED
rule output → A bridge                 = UNDECLARED
```

The selected bridge therefore opens the semantic route:

```
PROJECTION_CANDIDATE
        ↓
decision-rule family
        ↓
pointwise decision output in A
        ↓
C_LOSS
        ↓
expectation over workload distribution
        ↓
rule-level aggregate evaluation
        ↓
optimization over the declared rule family
        ↓
P-level aggregate decision-loss object
```

The arrow chain above is a dependency skeleton, not a declared formula. No particular rule family, admissibility predicate, optimization criterion, infimum/minimum convention, or optimizer is legally instantiated by R-ASM-C alone.

Accordingly:

```
R-ASM-C = DECLARED
R_OBJECT = NOT_DECLARED
R_ASSEMBLY = OPEN
R_oracle = NOT_DEFINED
Δ = BLOCKED
FinLoss = NOT LEGALLY AVAILABLE
```

No STEP⑤, harness, implementation, measurement, or experiment authorization is created by this declaration.


## 15. R-ASM-D declaration record

The researcher has explicitly declared:

```text
R-ASM-D  MEASURE / MEASURABILITY
        = PARAMETER_INDEXED_PROBABILITY_MEASURE_FAMILY_WITH_MEASURABILITY_REQUIREMENT
```

This establishes the workload-distribution side of the aggregate-loss assembly as a parameter-indexed family of probability measures, together with a measurability requirement for the workload-dependent loss mapping used by the expectation.

The declaration advances the expectation boundary beyond the previous placeholder state. It does not silently instantiate a concrete parameter set, a concrete measurable-space notation, a particular probability measure, a particular measurable loss function, integrability conditions, or expectation values. Measurability is a requirement of the aggregate construction; it is not a claim that the current `C_LOSS` interface has already been proved measurable under a concrete structure.

Accordingly:

```text
R-ASM-D = DECLARED
R_OBJECT = NOT_DECLARED
R_ASSEMBLY = OPEN
R_oracle = NOT_DEFINED
Δ = BLOCKED
FinLoss = NOT LEGALLY AVAILABLE
```

No STEP⑤, harness, implementation, measurement, or experiment authorization is created by this declaration.


## 16. R-ASM-F declaration record

The researcher has explicitly declared:

    R-ASM-F  FINAL_OBJECT_SIGNATURE = COMPOSITE_SIGNATURE

This establishes that the final signature of the aggregate decision-loss object is to be represented at a composite-signature level, combining the already declared semantic axes rather than selecting a single-axis minimal signature. The declaration is structural and does not itself instantiate the exact domain/codomain notation, parameter domain, decision-rule signature, optimization operator, measure-family notation, component admission predicates, or a concrete mathematical formula for R.

Accordingly:

    R-ASM-F = DECLARED
    R_OBJECT = NOT_DECLARED
    R_ASSEMBLY = OPEN
    R_oracle = NOT_DEFINED
    Δ = BLOCKED
    FinLoss = NOT LEGALLY AVAILABLE
    STEP⑤ = NOT ENTERED
    EXPERIMENT AUTH = NONE

No automatic formula, oracle, residual, FinLoss, NECT, STEP⑤, implementation, harness, measurement, or experiment authorization is created by this declaration.


## 17. R-ASSEMBLY-1B declaration record

The researcher explicitly declared:

```text
R-ASSEMBLY-1B  DECISION_OUTPUT_BRIDGE = JOINT_COMPOSITE_OUTPUT_MECHANISM
EVALUATION_OBJECT = (P, δ)
OUTPUT_TARGET = a ∈ A
```

This establishes that the composite evaluation object `(P, δ)` reaches the pointwise decision space `A` through a joint output mechanism. It does not instantiate a concrete action map, restore `δ(I_P)`, define `I_P`, or otherwise import the historical decision-rule construction.

The resulting structural path is:

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

Accordingly:

```text
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
```

No implementation, harness, measurement, or experiment authorization is created by this declaration.

## 12.5 R-ASSEMBLY-1C declaration record

The researcher explicitly declared:

~~~text
R-ASSEMBLY-1C  DECISION_OUTPUT_DEPENDENCE = C3

JOINT_OUTPUT_MECHANISM:
    Γ(P, δ) : W → A

POINTWISE_OUTPUT:
    a = Γ(P, δ)(w)
~~~

C3 establishes that (P, δ) produces a decision mapping whose input is a workload instance w. The resulting action is:

~~~text
a = Γ(P, δ)(w) ∈ A
~~~

and the pointwise loss carrier is therefore invoked as:

~~~text
C_LOSS(Γ(P, δ)(w), w)
~~~

This is distinct from:

~~~text
C1: a = Γ(P, δ)

C2: a = Γ(P, δ, w)
~~~

In C3, the workload instance w is the argument of the decision mapping produced by (P, δ). The workload distribution is not declared to be a direct input to Γ; its role remains on the aggregation side through R-B / R-C and R-ASM-B / R-ASM-D.

The declaration does not instantiate Γ's concrete functional form, P or δ signatures, a concrete W measurable-space representation, A structure, decision-rule admissibility, parameter domain, probability measure notation, measurability proof, integrability, expectation existence, optimization domain/operator, min vs inf, optimizer existence, R_OBJECT, R_oracle, Δ, FinLoss, or NECT. It also does not restore historical δ(I_P).

The resulting dependency skeleton is:

~~~text
(P, δ)
    ↓
Γ(P, δ) : W → A
    ↓  applied to w
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


## 12.6 R-ASSEMBLY-2 declaration — decision rule representation

The researcher explicitly declared:

```text
R-ASSEMBLY-2 = D2
```

Therefore:

```text
DECISION_RULE_REPRESENTATION = GENERATED_RULE

Γ(P, δ) = g
g : W → A

a = g(w)
```

Under D2, the composite evaluation object `(P, δ)` does not itself become the final decision rule by identity. Instead, `(P, δ)` participates in generating a decision rule `g : W → A` through the already declared joint output mechanism.

This is a minimum-level semantic declaration only. It does not instantiate the generation map, the concrete signatures of `P) or `δ`, the admissible rule family, or the conditions under which the generated `g` is admitted.

The previously declared R-ASSEMBLY-1C = C3 is preserved:

```text
Γ(P, δ) : W → A
a = Γ(P, δ)(w)
```

D2 gives this the interpretation:

```text
Γ(P, δ) = g
g : W → A
a = g(w)
```

and therefore the pointwise loss carrier is reached as:

```text
C_LOSS(g(w), w)
```

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

D2 does not declare a concrete generation operator `Γ`, signatures of `P) or `δ`, an admissible rule family, a rule-admission predicate, a concrete projection-to-rule mapping, a parameter domain, a concrete measurable structure, a concrete probability-measure family, measurability or integrability proofs, an optimization domain/operator, minimum versus infimum, optimizer existence, the exact composite `Dom(R)`, `R_OBJECT`, `R_oracle`, residual `Δ`, `FinLoss`, `NECT`, or STEP⑤/implementation/harness/measurement/experiment authorization. Historical `δ(I_P)` is not restored.

The resulting dependency skeleton is:

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

Accordingly:

```text
R-ASSEMBLY-2 = DECLARED (D2)
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

## R-ASSEMBLY-3 declaration — 2026-09-23

The researcher explicitly declared **R-ASSEMBLY-3 = F2**.

Decision-rule family:

    𝒢_adm ⊆ { g | g : W → A }
    g ∈ 𝒢_adm

This makes the rule family an independent admissible family. Not every mapping W→A is automatically eligible for the optimization component.

The prior D2 representation is preserved:

    Γ(P, δ) = g
    g : W → A
    a = g(w)

with the additional condition g ∈ 𝒢_adm.

F2 does not instantiate the concrete rule family, its parameterization, the exact optimization domain/operator, min versus inf, optimizer existence, or the exact Dom(R). It does not identify 𝒢_adm with the R-ASM-E composite admission predicate, restore historical δ(I_P), or instantiate R_OBJECT, R_oracle, Δ, FinLoss, or NECT.

Current consequence:

    R-ASSEMBLY-3 = DECLARED (F2)
    DECISION_RULE_FAMILY = INDEPENDENT_ADMISSIBLE_FAMILY
    𝒢_adm ⊆ {g | g : W → A}
    g ∈ 𝒢_adm

    R_OBJECT = NOT_DECLARED
    R_ASSEMBLY = OPEN
    R_ORACLE = NOT_DEFINED
    Δ = BLOCKED
    FinLoss = NOT LEGALLY AVAILABLE
    NECT = BLOCKED
    STEP⑤ = NOT ENTERED
    HARNESS AUTH = NONE
    EXPERIMENT AUTH = NONE

No implementation, harness, measurement, or experiment authorization is created by this declaration.

## R-ASSEMBLY-4 declaration — 2026-09-23

The researcher explicitly declared **R-ASSEMBLY-4 = G2**.

The admissible decision-rule family is projection-candidate dependent:

```text
𝒢_adm(P) ⊆ { g | g : W → A }
g ∈ 𝒢_adm(P)
```

This preserves R-ASSEMBLY-3 = F2: the rule family remains an independent admissible family, while its family-level identity is allowed to vary with the projection candidate (P).

The prior assembly chain remains:

```text
(P, δ)
    ↓
Γ(P, δ) = g
    ↓
g : W → A
    ↓
g ∈ 𝒢_adm(P)
    ↓
optimization
```

G2 is a dependency declaration only. It does not instantiate the concrete family, its parameterization, a rule-admission predicate, a guarantee that Γ(P,δ) belongs to 𝒢_adm(P), the optimization domain/operator, minimum versus infimum, optimizer existence, or the exact `Dom(R)`.

G2 does not declare a direct dependence of 𝒢_adm on δ or θ. No such dependence is imported by this declaration.

The R-ASM-E composite admission predicate remains distinct from rule-family membership:

```text
g ∈ 𝒢_adm(P)
        ≠
COMPOSITE_ADMISSION_PREDICATE
```

Historical `δ(I_P)` is not restored, and no statement `δ ∈ Δ(I_P)` is introduced.

Current consequence:

```text
R-ASSEMBLY-4 = DECLARED (G2)
DECISION_RULE_FAMILY_DEPENDENCE = PROJECTION_CANDIDATE
𝒢_adm(P) ⊆ {g | g : W → A}
g ∈ 𝒢_adm(P)

R_OBJECT = NOT_DECLARED
R_ASSEMBLY = OPEN
R_ORACLE = NOT_DEFINED
Δ = BLOCKED
FinLoss = NOT LEGALLY AVAILABLE
NECT = BLOCKED
STEP⑤ = NOT ENTERED
HARNESS AUTH = NONE
EXPERIMENT AUTH = NONE
```

No implementation, harness, measurement, or experiment authorization is created by this declaration.


## R-ASSEMBLY-5 declaration — 2026-09-23

The researcher explicitly declared **R-ASSEMBLY-5 = H2**.

H2 establishes conditional admission: generation of a rule and admissibility of that rule are separate stages.

```text
Γ(P, δ) = g
        ↓
check:
    g ∈ 𝒢_adm(P) ?
        ↓
only an admitted g enters optimization
```

The generated rule is not declared admissible merely because it was generated. Membership in the projection-candidate-dependent admissible family 𝒢_adm(P) is an independent condition for entering the optimization stage.

This preserves the preceding declarations:

```text
R-ASSEMBLY-1C = C3
Γ(P, δ) : W → A
a = Γ(P, δ)(w)

R-ASSEMBLY-2 = D2
Γ(P, δ) = g
g : W → A
a = g(w)

R-ASSEMBLY-3 = F2
𝒢_adm ⊆ { g | g : W → A }
g ∈ 𝒢_adm

R-ASSEMBLY-4 = G2
𝒢_adm(P) ⊆ { g | g : W → A }
g ∈ 𝒢_adm(P)
```

The legal relationship is now:

```text
Γ(P, δ) = g
AND
[g ∈ 𝒢_adm(P)] is an independent admission condition
```

H2 does not declare that generation guarantees admissibility, nor that feasibility is built into Γ. It also does not instantiate the concrete rule family, admission predicate, optimization domain/operator, minimum versus infimum, optimizer existence, parameterization, or exact Dom(R). Historical δ(I_P) and δ ∈ Δ(I_P) remain unreinstated.

Current assembly chain:

```text
(P, δ)
    ↓
Γ(P, δ) = g
    ↓
g : W → A
    ↓
independent admission check
    ↓
g ∈ 𝒢_adm(P) ?
    ↓
if admitted → optimization
if not admitted → no optimization entry for g
```

Accordingly:

```text
R-ASSEMBLY-5 = DECLARED (H2)
R_OBJECT = NOT_DECLARED
R_ASSEMBLY = OPEN
R_ORACLE = NOT_DEFINED
Δ = BLOCKED
FinLoss = NOT LEGALLY AVAILABLE
NECT = BLOCKED
STEP⑤ = NOT ENTERED
HARNESS AUTH = NONE
EXPERIMENT AUTH = NONE
```

No implementation, harness, measurement, or experiment authorization is created by this declaration.
