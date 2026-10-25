# Research Road Space After Concrete Underdetermination

**Date**: 2026-09-23  
**Status**: ROAD_SPACE_REGISTERED / NO_ROUTE_SELECTED  
**Nature**: research-navigation record; no new R-INTERNAL semantic object

## 1. Trigger

The Concrete Argmin Cardinality Audit showed that, under
`FULL_VISIBLE_HISTORY_RULE_SPACE`, the point-mass instance does not determine
the exact rule-level argmin cardinality:

```text
R(P0,θ0′)=5376
att(P0,θ0′)=true
uniq(P0,θ0′)=false
realized optimal action-sequence count=4
|Argmin(P0,θ0′)|≥4
exact |Argmin(P0,θ0′)|
  =UNDERDETERMINED_BY_CURRENT_DECLARATIONS
```

The researcher then accepted this boundary:

```text
ACCEPT_UNDERDETERMINATION / NO_RULE_DOMAIN_COMPLETION_NOW
```

The result is therefore a legitimate branching point, not a failure requiring
immediate repair.

## 2. Road-space status

Five possible research roads are registered. None is selected. Registering a
road does not open its gate, authorize its definitions, or imply that its
objects already exist.

```text
ROAD_SPACE_STATUS = REGISTERED
SELECTED_ROUTE = NONE
```

## 3. Registered roads

### Road 1 — Rule-Domain Completion

Core question:

```text
What is the complete rule object?
```

Possible subject matter includes the visible-history universe, totality,
admissible histories, off-trajectory behavior, finite-state structure,
randomization, and rule equivalence.

This is the most direct route to converting

```text
exact |Argmin(P0,θ0′)|=UNDERDETERMINED
```

into a determinate rule-level cardinality. It is a definition-deepening route
and remains deliberately not entered under the accepted-underdetermination
policy.

### Road 2 — Instance Family

Core question:

```text
How does R vary across a declared family of instances?
```

A future family would require a new instance-index surface before questions
such as continuity, monotonicity, Lipschitz-type bounds, optimizer change, or
structural stability can be legally asked.

This is a larger transition from single-instance semantic audit toward
optimization-landscape or sensitivity analysis. No instance family is declared.

### Road 3 — Single-Instance Identifiability

Core question:

```text
How much rule information does one observation instance identify?
```

The current underdetermination already exhibits the motivating phenomenon:
distinct rules may agree on the realized trace under `(P0,θ0′)` while remaining
distinct as rules. A future identifiability route would need to declare an
observation semantics and an explicit behavioral-equivalence relation before
using quotient notation.

This road is natural after the underdetermination result, but it is not entered.

### Road 4 — Multi-Instance Identification

Core question:

```text
When does a family of instances identify a rule?
```

A future route would study whether distinct rules that agree on one instance can
be separated by additional instances, and what completeness means for an
instance family.

This depends on prior decisions about observation, behavioral equivalence, and
instance-family indexing. No second instance or instance family is declared.

### Road 5 — Computational Semantics

Core question:

```text
How can the mathematical object become an executable software object?
```

This route concerns formal semantics versus executable semantics for objects
such as problem, parameter, state, history, action, rule, trajectory, loss,
value, and argmin.

It is intentionally deferred until the relevant mathematical objects are more
stable. No implementation, harness, executable design, data collection,
measurement, or experiment authorization is created.

## 4. Relation among Roads 1, 3, and 4

The immediate conceptual tree is:

```text
Concrete Argmin Cardinality Audit
              ↓
     UNDERDETERMINED
              ↓
   ┌──────────┴──────────┐
   │                     │
Rule-Domain       Accept Current
Completion        Rule Space
   │                     │
Rule-level         Identifiability
exactness                ↓
                  Single-instance /
                  Multi-instance
                  identification
```

Road 1 would directly resolve underdetermination by completing the rule domain.
Roads 3 and 4 would instead study what remains identifiable without changing the
current representation. These are different questions and must not be silently
substituted for one another.

## 5. Selection rule

No route has priority merely because it continues the current chain.

A route may be selected only through an explicit researcher decision that names
the route and the concrete consumer or research question. Until then:

```text
R-INTERNAL = IDLE
R_ASSEMBLY = CLOSED
STEP⑤ = NOT ENTERED
STEP⑥ = NOT ENTERED
SELECTED_ROUTE = NONE
```

## 6. Boundaries

This record does not declare a new semantic object, instance family, observation
semantics, behavioral equivalence, quotient, selector, canonical optimizer,
tie-breaking rule, R_ORACLE, executable interface, harness, or experiment. It
does not unblock Δ/gap, FinLoss, or NECT, and it does not authorize
implementation, data collection, profiling, measurement, or experimentation.
