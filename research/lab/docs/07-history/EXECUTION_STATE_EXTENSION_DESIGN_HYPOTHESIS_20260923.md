# Execution-State Extension Design Hypothesis

**Date**: 2026-09-23  
**Status**: HYPOTHESIS_REGISTERED / NOT_FORMALIZED / ROUTE_UNSELECTED  
**Nature**: exploratory separation hypothesis; no new semantic object, definition, route, implementation, or experiment

## 1. Hypothesis

For a large model decomposed into layers with a resident core, execution-state
forking may provide the upstream structure for deciding:

```text
state fork
→ reachable landing / extension point
→ required capability
→ layering / residency / loading policy
→ implementation selection
```

The hypothesis is that execution-state determines reachable branches, while model
layering, residency, and loading are downstream extension design.

## 2. Separation registered by the hypothesis

```text
Execution-state semantics
  S_t → a_t → S_{t+1}
  fork: S_t → {S_{t+1}^A, S_{t+1}^B}
  landing / extension classification

Extension design
  branch or landing → required capability
  capability → required layer / resident set / load policy / prefetch policy

Implementation
  capability requirement → loader/runtime/open-source code
```

The statement:

```text
branch B requires layer L_i
```

is therefore downstream of execution-state unless the requirement is derivable from
the already-declared transition semantics.

## 3. Important distinction

The existence of a state fork is an execution-state question.

Classifying a landing or extension point is also an execution-state question when the
classification is determined by declared state/transition semantics.

Choosing the loading policy for that landing point is extension design.

Thus:

```text
state semantics ≠ capability mapping ≠ loading policy ≠ implementation choice
```

## 4. Resident-core layering

If a model has:

```text
L0 = resident core
L1,L2,L3 = conditional or extension layers
```

then a possible downstream pattern is:

```text
S_t → fork
fork A requires L1
fork B requires L2
L0 remains resident
L1/L2 are loaded, prefetched, or excluded by policy
```

Different policies—full load, dynamic load, prefetch, cache-aware load, or
prediction-based load—may realize the same execution-state fork structure.

## 5. Open-source implementation

Excellent open-source code may accelerate implementation, but it is not theoretical
evidence. It belongs to the implementation selection layer after:

```text
required capability → design constraints → implementation choice
```

## 6. Required future tests

Before this hypothesis becomes a formal surface, it must be adversarially compared
with:

```text
generic state machines;
workflow systems;
planning graphs;
dynamic programming;
policy/capability tables;
stochastic forks.
```

The key question is whether the mapping

```text
landing / branch → required capability
```

is derivable from execution-state semantics or is an additional design assumption.

## 7. Boundaries

This record does not define execution-state, fork, landing, extension, capability,
layer, residency, loading policy, or a new architecture. It does not reopen A2.0,
create `R-INTERNAL-20`, select a route, authorize implementation, or authorize
experiments.
