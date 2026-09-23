# A2.0 Interface Sufficiency Audit

**Date**: 2026-09-23  
**Status**: EXPLORATORY_AUDIT_REGISTERED / CORE_CLOSURE_PARTIAL  
**Nature**: black-box sufficiency audit; no new semantic object, definition, route, implementation, or experiment

## 1. Question

After model-internal methods are replaced by a black box, does the surviving
A2.0 candidate core suffice to describe a complete evaluated behavior system?

The audited candidate components are:

```text
P
θ
𝒢_adm(P)
Dom(L)
L / V / R
Execution / Trajectory surface
C0–C5 computational-semantics observations
```

This audit does not redefine these components and does not declare a new core.

## 2. Sufficiency criterion

The black-box core is considered sufficient only if it can express, without
reference to model internals:

1. the observable task/projection;
2. the external evaluation regime;
3. the admissible behavior interface;
4. whether behavior is legally evaluable;
5. the value/loss set and minimum value;
6. the declaration-to-execution boundary;
7. whether executed behavior remains semantically consistent with declaration.

## 3. Value-level closure

At the value-evaluation layer, the candidate core is closed:

```text
P       fixes the observable task/projection side.
θ       fixes the external evaluation regime.
𝒢_adm   fixes the admissible behavior interface.
Dom(L)  fixes whether behavior is legally evaluable.
L       assigns evaluated cost.
V       collects attainable evaluated values.
R       takes the infimum of that value set.
```

So the existing structure can already express:

```text
Which behaviors are admissible?
Which of them are legally evaluable?
What values are attainable?
What is the infimum?
```

This closure is method-independent: it does not need transformer, attention,
MoE routing, sampling implementation, training, or model-specific mechanisms.

## 4. Execution-level closure

At the executable-semantics layer, closure is only partial.

The registered current interface has a behavioral mapping:

```text
g : W → A
```

and a loss evaluation:

```text
C_LOSS(g(W),W)
```

but it does not register an abstract observable execution/trajectory interface as
a first-class A2.0 core component. In the concrete instance `P0/θ0′`, trajectory
and runtime semantics were introduced locally, but that does not make them a
registered architecture-independent core interface.

`C0–C5` provides an observational schema for whether a declared computational
object is routed, instantiated, executed, and semantically consistent. However,
it is still an observation schema, not a formal execution interface.

Therefore:

```text
Value closure       = CLOSED at candidate level
Execution closure   = OPEN / PARTIAL
Overall sufficiency = PARTIAL
```

## 5. Component sufficiency table

| Component | Value closure | Executable closure | Audit note |
| --- | --- | --- | --- |
| `P` | PASS | PARTIAL | Gives task/projection, not runtime execution by itself. |
| `θ` | PASS | PASS as regime side | Supplies external evaluation regime, not model internals. |
| `𝒢_adm(P)` | PASS | PARTIAL | Gives admissible behavior interface, but not an explicit trajectory/state boundary. |
| `Dom(L)` | PASS | PARTIAL | Defines evaluation legality after behavior is available. |
| `L / V / R` | PASS | NOT ALONE | Evaluates behavior; does not define execution observation. |
| Execution/Trajectory | NOT CURRENTLY CORE | OPEN | Needed for executable closure but not formally declared. |
| `C0–C5` | OPEN | PASS as observation schema | Observes declaration-to-execution consistency; not a formal execution object. |

## 6. Result

The surviving black-box core is sufficient for a **value-level evaluated system**:

```text
P
+ θ
+ 𝒢_adm(P)
+ Dom(L)
+ L / V / R
```

It is not yet certified sufficient for a complete **executable semantic system**,
because an architecture-independent execution/trajectory observation surface is
still missing from the registered core.

The distinction is:

```text
Evaluable behavior system        = candidate closure exists
Executable semantic system       = closure remains OPEN
```

## 7. Directional conclusion

The likely common core is not a common internal method and not a common rule
enumerator. It is closer to:

```text
observable task/projection
    +
external evaluation regime
    +
admissible behavior interface
    +
evaluation domain
    +
value/risk structure
    +
execution boundary
```

The only unclear member is the execution/trajectory surface.

## 8. Next decision surface

A future exploratory decision must classify the execution/trajectory surface as:

```text
1. missing Layer-A candidate;
2. concrete-instance-only detail;
3. derivable implicitly from W, A, and C_LOSS.
```

No option is selected here.

## 9. Boundaries

This audit does not declare a new execution object, trajectory object, state
object, behavioral-equivalence object, `[g]`, `R-INTERNAL-20`, route selection,
R_ORACLE, Δ/gap, FinLoss, NECT, STEP⑤/STEP⑥, implementation, harness, data
collection, profiling, measurement, or experiment authorization.
