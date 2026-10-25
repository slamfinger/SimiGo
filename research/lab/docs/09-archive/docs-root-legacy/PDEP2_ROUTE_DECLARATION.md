# PDEP-2 Route Declaration — Aggregate Decision Loss

**Date:** 2026-09-23  
**Status:** RESEARCHER ROUTE DECLARATION / NO R OBJECT DEFINITION

## 1. Researcher Declaration

The researcher has selected the continuation route:

```text
PDEP-2 ROUTE = AGGREGATE_DECISION_LOSS
```

This is a proposition-level route selection. It resolves the Direction A / Direction B choice identified by the post-LOSS-5 dependency review.

## 2. Meaning of the Route

The selected route means that the P4-A research proposition is intended to retain an evaluation layer capable of expressing **aggregate decision loss** above the currently declared pointwise cost object.

Current boundary:

```text
V_j ∈ ℝ^k
    ↓
C_VALUE = [V_1,V_2,...]
    ↓
C_LOSS : D_C → ℝ
    ↓
D_C = A × W
    ↓
[PDEP-2 ROUTE = AGGREGATE_DECISION_LOSS]
    ↓
[R OBJECT NOT YET DECLARED]
```

The route therefore identifies the required semantic direction, but it does not itself define the mathematical object that realizes that direction.

## 3. What This Declaration Does Not Select

The following remain undeclared or blocked:

```text
R_OBJECT                       = NOT_DECLARED
R_CODOMAIN                     = UNDECLARED
AGGREGATION_RULE               = UNDECLARED
EVALUATION_INPUT               = NOT_SELECTED
EVALUATION_OBJECT              = NOT_SELECTED
θ_ROLE                         = UNDECLARED
R_oracle                       = NOT_DEFINED_BY_CURRENT_FRAMEWORK
Δ                              = BLOCKED
FinLoss                        = NOT LEGALLY AVAILABLE
NECT                           = BLOCKED
```

No expectation, probability distribution, average, supremum, worst-case rule, weighted aggregation, empirical estimator, optimization rule, or other concrete construction is implied by the route declaration.

## 4. Relationship to LOSS-5

This declaration does **not** reopen or alter the completed LOSS-5 resolution.

```text
LOSS-5_STATUS       = SUSPENDED_AT_CURRENT_RESOLUTION_LEVEL
LOSS-5_COMPLETENESS = REACHED
R_OBJECT_SCHEMA     = A
R_OBJECT            = NOT_DECLARED
```

Schema A remains the current LOSS-5 state. The present declaration instead establishes that the broader P4-A proposition will proceed, if continued, along the aggregate-decision-loss route.

Thus:

```text
PDEP-2 ROUTE ≠ R_OBJECT DEFINITION
PDEP-2 ROUTE ≠ AGGREGATION RULE
PDEP-2 ROUTE ≠ R_OBJECT_SCHEMA
```

## 5. Consequence for the Next Gate

The next work item is no longer to decide whether P4-A requires an object above `C_LOSS`. That proposition-level route choice has now been made.

The next independent semantic task is to determine, by explicit researcher declaration, the minimum object schema required to instantiate aggregate decision loss above:

```text
C_LOSS : D_C → ℝ
```

without importing undeclared probabilistic, workload, optimization, oracle, or experimental semantics.

No such object is defined by this document.

## 6. Governance

```text
STEP④-A VALUE SEMANTICS     = CLOSED
STEP④-B VALUE DISCIPLINE    = COMPLETE
LOSS-3                       = CLOSED
LOSS-4                       = CLOSED
LOSS-5                       = RESOLVED AT CURRENT LEVEL
PDEP-2 ROUTE                 = AGGREGATE_DECISION_LOSS
R_OBJECT                     = NOT_DECLARED
NECT                         = BLOCKED
STEP⑥                        = NOT ENTERED
RQ REGISTRATION              = NONE
EXPERIMENT AUTHORIZATION     = NONE
HARNESS AUTHORIZATION        = NONE
```

No historical document is retroactively rewritten. The route declaration records a new researcher decision and leaves prior historical formulations intact.
