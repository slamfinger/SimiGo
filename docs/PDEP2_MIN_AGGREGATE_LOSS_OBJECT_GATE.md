# PDEP-2 Minimum Aggregate Decision-Loss Object Gate

**Date:** 2026-09-23  
**Status:** CONCEPTUAL GATE ANALYSIS / NO R OBJECT SELECTED / NO AGGREGATION RULE SELECTED

## 1. Gate Purpose

PDEP-2 has selected the proposition-level route:

```text
PDEP-2 ROUTE = AGGREGATE_DECISION_LOSS
```

The purpose of this gate is therefore narrower than LOSS-5: identify the minimum semantic components that must be declared before an aggregate decision-loss object can legally exist above the current pointwise cost object.

This gate does not choose those components.

## 2. Current Boundary

```text
C_LOSS : D_C → ℝ
D_C = A × W
        ↓
PDEP-2
        ↓
aggregate decision-loss layer
        ↓
R_OBJECT = NOT_DECLARED
```

The only currently declared loss evaluation is pointwise finite-real evaluation.

## 3. Minimal Dependency Decomposition

An aggregate object cannot be obtained merely by renaming `C_LOSS`. At minimum, the framework must distinguish:

```text
(1) EVALUATION TARGET
    What entity is assigned an aggregate loss?

(2) EVALUATION INPUT / DOMAIN
    Over what declared collection of pointwise evaluations is loss formed?

(3) AGGREGATION RELATION / RULE
    How are pointwise C_LOSS values related to the aggregate object?

(4) AGGREGATE RESULT CODOMAIN
    What mathematical value set contains the aggregate result?

(5) DEFINEDNESS / TOTALITY
    On which declared domain is the aggregate object defined?

(6) PARAMETER / REGIME DEPENDENCE
    Whether and how θ or an equivalent evaluation context enters the object.
```

Items (1)-(5) are structural requirements for an aggregate object. Item (6) is required only if the intended object retains the historical parameterized form `R(P;θ)`.

## 4. Important Separation

The following are distinct semantic questions:

```text
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
FinLoss predicate
```

In particular, selecting an aggregate-decision-loss route does not legally imply:

- expectation;
- probability;
- averaging;
- supremum / worst case;
- weighting;
- empirical aggregation;
- optimization;
- oracle comparison.

Each would require an explicit declaration if eventually used.

## 5. Candidate Abstract Shape

Before choosing semantics, the most that can be stated without over-declaration is an abstract role-level shape:

```text
R : D_R → Y_R
```

where:

```text
D_R = aggregate-evaluation input domain        [UNDECLARED]
Y_R = aggregate-loss codomain                  [UNDECLARED]
mapping / construction of R                    [UNDECLARED]
definedness rule                               [UNDECLARED]
```

If the historical parameterized form is retained, the role-level shape may instead be recorded as:

```text
R(P;θ)
```

but this notation alone still does not define `D_R`, `Y_R`, aggregation, or parameter semantics.

## 6. Minimum Gate Questions

The researcher decision surface is now:

### R-A — Evaluation Target

What does the aggregate loss evaluate?

Possible semantic families include:

- a decision strategy / policy;
- a representation / projection;
- a decision process;
- another explicitly declared object.

No family is selected here.

### R-B — Evaluation Input

What supplies the pointwise `C_LOSS` evaluations?

Possible families include:

- a finite collection;
- an indexed workload set;
- a workload distribution / probability model;
- another declared evaluation structure.

No family is selected here.

### R-C — Aggregation Rule

How is aggregate loss constructed from pointwise costs?

Possible families include:

- a declared algebraic aggregation;
- expectation / integral;
- supremum / worst-case;
- weighted aggregation;
- another explicitly declared operator.

No rule is selected here.

### R-D — Result Codomain

What is the codomain of aggregate loss?

This must be declared independently of the finite-real codomain of `C_LOSS`.

No codomain is selected here.

### R-E — Definedness

On what domain is the aggregate object defined, and is it total there?

No definedness rule is selected here.

### R-F — Parameter / Regime

Does aggregate loss retain a parameter or workload-regime argument analogous to historical `θ`?

No parameter semantics are selected here.

## 7. Critical Finding

The PDEP-2 route selection has removed one ambiguity:

```text
P4-A requires an aggregate-decision-loss layer
    = ROUTE SELECTED
```

but it has not removed the semantic underdetermination inside that layer:

```text
aggregate decision loss
    ↓
target ? 
input ?
aggregation ?
codomain ?
definedness ?
parameter/regime ?
```

Therefore the next gate is an **R-object construction gate**, not STEP⑤ execution.

## 8. Governance

```text
STEP④-A                  = CLOSED
STEP④-B                  = COMPLETE
LOSS-3                   = CLOSED
LOSS-4                   = CLOSED
LOSS-5                   = RESOLVED AT CURRENT LEVEL
PDEP-2 ROUTE             = AGGREGATE_DECISION_LOSS
R_OBJECT                 = NOT_DECLARED
R_ORACLE                 = NOT_DEFINED
Δ                        = BLOCKED
FinLoss                  = NOT LEGALLY AVAILABLE
NECT                     = BLOCKED
STEP⑥                    = NOT ENTERED
EXPERIMENT AUTH          = NONE
HARNESS AUTH             = NONE
```

No semantic value is selected by this document.
