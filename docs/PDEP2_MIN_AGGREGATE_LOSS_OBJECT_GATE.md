# PDEP-2 Minimum Aggregate Decision-Loss Object Gate

**Date:** 2026-09-23  
**Status:** R-A–R-F DECLARED / R_OBJECT ASSEMBLY GATE OPEN / R_OBJECT NOT DECLARED

## 1. Gate Purpose

PDEP-2 has selected the proposition-level route:

```text
PDEP-2 ROUTE = AGGREGATE_DECISION_LOSS
```

The purpose of this gate is to determine the minimum semantic components required before an aggregate decision-loss object can legally exist above the current pointwise cost object.

The researcher has now declared all six minimum aggregate-object semantic axes. The remaining task is to determine whether, and exactly how, these declarations can be assembled into a legally defined minimum R_OBJECT without importing undeclared semantics.

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
C_LOSS ↔ R BRIDGE = NOT DECLARED
```

No aggregate construction has yet been declared.

## 3. Current Researcher Declarations

```text
R_OBJECT                    = NOT_DECLARED

R-A  EVALUATION_TARGET      = PROJECTION_CANDIDATE
R-B  EVALUATION_INPUT       = WORKLOAD_DISTRIBUTION
R-C  AGGREGATION_RULE       = EXPECTATION_OVER_WORKLOAD_DISTRIBUTION
R-D  RESULT CODOMAIN        = FINITE_REAL
R-E  DEFINEDNESS / TOTALITY = PARTIAL_DEFINEDNESS
R-F  PARAMETER / REGIME     = PARAMETERIZED_REGIME

C_LOSS : A × W → ℝ          = CLOSED
C_LOSS ↔ R BRIDGE           = NOT DECLARED

W measurable structure     = UNDECLARED
μ_W formal object          = NOT INSTANTIATED
C_LOSS measurability       = UNDECLARED
expectation                 = SELECTED AS AGGREGATION RULE, NOT YET INSTANTIATED
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

The declaration is intentionally limited to the role of the evaluation input. It does **not** instantiate a particular mathematical probability or measure-theoretic structure.

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
C_LOSS ↔ R BRIDGE = NOT DECLARED
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

1. **Pointwise loss carrier adoption**
   ```
   R_POINTWISE_LOSS_CARRIER = NOT_DECLARED
   ```
   Although `C_LOSS : A × W → ℝ` is closed, it is a new independent loss object and does not automatically become the pointwise carrier of R.

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

No ASM semantic value is selected by this gate. The following remain researcher-decision fields:

```
R-ASM-A  POINTWISE_LOSS_CARRIER
R-ASM-B  REGIME_DISTRIBUTION_INTERFACE
R-ASM-C  DECISION_BRIDGE_KIND
R-ASM-D  MEASURE / MEASURABILITY
R-ASM-E  ADMISSION_PREDICATE / Dom(R)
R-ASM-F  FINAL_OBJECT_SIGNATURE
```

All six are currently:

```
NOT_DECLARED
```

Candidate values are not selected by the agent. In particular, no historical `δ(I_P)`, optimization over `Δ(I_P)`, probability measure, fixed action map, or final signature is silently adopted.

### 12.3 Minimal placeholder only

Before the ASM fields are resolved, the strongest current statement is only:

```
Dom(R) = UNDECLARED
R : Dom(R) → ℝ
```

where even this is a typed placeholder expressing R-D/R-E, not a declared R object.

Therefore:

```
R_OBJECT = NOT_DECLARED
R_ASSEMBLY = OPEN
```

Completion of R-ASM does not automatically authorize `R_oracle`, residual `Δ`, FinLoss, NECT, STEP⑤, implementation, harness, or experiment.
