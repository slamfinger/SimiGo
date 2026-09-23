# PDEP-2 Minimum Aggregate Decision-Loss Object Gate

**Date:** 2026-09-23  
**Status:** R-A DECLARED / R-B–R-F OPEN / R_OBJECT NOT DECLARED

## 1. Gate Purpose

PDEP-2 has selected the proposition-level route:

```text
PDEP-2 ROUTE = AGGREGATE_DECISION_LOSS
```

The purpose of this gate is to determine the minimum semantic components required before an aggregate decision-loss object can legally exist above the current pointwise cost object.

The researcher has now declared the evaluation target only. The remaining aggregate-object components remain open.

## 2. Current Boundary

```text
C_LOSS : A × W → ℝ
        ↓
PDEP-2
        ↓
aggregate decision-loss layer
        ↓
R-A = PROJECTION_CANDIDATE
R-B = OPEN
R-C = OPEN
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
R-B  EVALUATION_INPUT       = OPEN
R-C  AGGREGATION_RULE       = OPEN
R-D  RESULT CODOMAIN        = OPEN
R-E  DEFINEDNESS / TOTALITY = OPEN
R-F  PARAMETER / REGIME     = CONDITIONAL / OPEN

C_LOSS : A × W → ℝ          = CLOSED
C_LOSS ↔ R BRIDGE           = NOT DECLARED
```

These are researcher-level declarations. No remaining open value is inferred from the selected target.

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

## 5. Remaining Decision Surface

### R-B — Evaluation Input

```text
R-B = OPEN
```

The collection/structure supplying pointwise `C_LOSS` evaluations remains unspecified.

No finite collection, indexed workload set, probability model, distribution, empirical sample, or other input structure is selected.

### R-C — Aggregation Rule

```text
R-C = OPEN
```

No relation or operator has been selected for constructing aggregate loss from pointwise costs.

In particular, none of expectation, averaging, summation, weighting, supremum, worst-case, empirical aggregation, or another operator is implied.

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

## 6. C_LOSS Boundary

The current pointwise interface remains:

```text
C_LOSS : D_C → ℝ
D_C = A × W
```

with the current LOSS-4 status that `D_C=A×W` is an MFI placeholder.

The declaration of R-A does not bridge this interface to an aggregate object.

Therefore:

```text
C_LOSS ↔ R BRIDGE = NOT DECLARED
```

A future bridge must explicitly state how a projection candidate and an evaluation input produce the arguments of `C_LOSS`, and how those pointwise evaluations enter the aggregate object.

## 7. Critical Separation

The following remain distinct:

```text
projection candidate
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

Selecting the evaluation target does not legally imply any of the subsequent objects.

## 8. Gate Status

```text
R-A = DECLARED
R-B = OPEN
R-C = OPEN
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

The next gate is therefore R-B/R-C/R-D/R-E/R-F resolution. No automatic R-object construction follows from R-A alone.
