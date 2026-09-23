# PDEP-2 Minimum Aggregate Decision-Loss Object Gate

**Date:** 2026-09-23  
**Status:** R-A / R-B / R-C DECLARED / R-D–R-F OPEN / R_OBJECT NOT DECLARED

## 1. Gate Purpose

PDEP-2 has selected the proposition-level route:

```text
PDEP-2 ROUTE = AGGREGATE_DECISION_LOSS
```

The purpose of this gate is to determine the minimum semantic components required before an aggregate decision-loss object can legally exist above the current pointwise cost object.

The researcher has now declared the evaluation target and evaluation input. The remaining aggregate-object components remain open.

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
R-D = OPEN
R-E = OPEN
R-F = CONDITIONAL / OPEN
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
R-D  RESULT CODOMAIN        = OPEN
R-E  DEFINEDNESS / TOTALITY = OPEN
R-F  PARAMETER / REGIME     = CONDITIONAL / OPEN

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
R-D = OPEN
```

The aggregate result codomain remains independently undeclared.

The fact that `C_LOSS` has finite-real codomain does not by itself determine the aggregate codomain.

### R-E — Definedness / Totality

```text
R-E = OPEN
```

The domain on which aggregate loss is defined, and whether the resulting object is total on that domain, remain undeclared.

### R-F — Parameter / Regime

```text
R-F = CONDITIONAL / OPEN
```

Parameter/regime semantics are only required if the eventual aggregate object retains a parameterized form analogous to historical `R(P;θ)`.

No `θ` semantics are currently declared.

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
R-D = OPEN
R-E = OPEN
R-F = CONDITIONAL / OPEN

R_OBJECT = NOT_DECLARED
R_ORACLE = NOT_DEFINED
Δ = BLOCKED
FinLoss = NOT LEGALLY AVAILABLE
NECT = BLOCKED
STEP⑥ = NOT ENTERED
EXPERIMENT AUTH = NONE
HARNESS AUTH = NONE
```

The next gate is R-D / R-E resolution, with expectation-specific prerequisites now explicit. No automatic measure, expectation evaluation, aggregate object, oracle, or residual is instantiated by R-C alone.
