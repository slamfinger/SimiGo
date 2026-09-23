# A2.0 Historical Scope Decomposition Retrospective

**Date**: 2026-09-23  
**Status**: HISTORICAL_DECOMPOSITION_REGISTERED / NO_ROUTE_SELECTED  
**Nature**: retrospective governance record; no new semantic object, theory, route, implementation, or experiment

## 1. Purpose

This record registers a retrospective interpretation of why the frozen A2.0 path
became overextended. The diagnosis is not that loading, residency, execution-state,
and evaluation were worthless. The issue is that they belonged to different research
layers but were placed in the same theoretical architecture.

## 2. Decomposed concerns

### A. Execution-state structure

Candidate behavioral structure:

```text
state → action → next state → later behavior → evaluation
```

This layer concerns behavior, history, state dependency, future admissibility, and
final evaluation. It may contain a cross-method common structure because different
internal mechanisms can still expose a state/decision/next-state pattern.

This remains only a future observation candidate. It does not reopen A2.0 or select
a route.

### B. Model lifecycle / residency

Implementation/lifecycle chain:

```text
model declaration
→ checkpoint / weights
→ load
→ instantiate
→ memory residency
→ runtime execution
```

This layer asks how a declared computational object becomes an executable object in
an environment. The recent Gemma 4 and Muse-Glimmer probes support its value as an
observational boundary:

```text
declaration ≠ routing ≠ instantiation ≠ execution ≠ semantic consistency
```

However, this supports a computational-semantics observation layer, not an A2.0
behavioral-theory core.

### C. Value / optimization abstraction

The frozen A2.0 value core reduced to:

```text
disciplined generic optimization schema candidate
```

That result remains frozen.

### D. Model-internal mechanisms

Transformer, MoE, attention, RoPE, sampling, training, and model-specific mechanisms
remain outside the useful A2.0 boundary and should stay black-boxed for this purpose.

## 3. Retrospective diagnosis

The likely structural problem was scope mixing:

```text
model lifecycle / residency
    +
execution-state evolution
    +
behavior evaluation / optimization
```

were treated as one architecture. Engineeringly, the chain

```text
model → layering → load → residency → execution → state → action → evaluation
```

looked complete. Theoretically, however, it mixed at least three distinct questions:

1. computational-object lifecycle;
2. execution-state evolution;
3. behavior evaluation/optimization.

## 4. Two opposite abstraction failures

The frozen A2.0 path exposed opposite extremes:

```text
too abstract:
    value core → generic optimization schema
    specificity disappears

too concrete:
    checkpoint / loader / runtime / memory / model internals
    platform and model-specific differences explode
```

This explains why adding layers made the architecture feel complete while reducing
its theoretical clarity.

## 5. Correct future placement

If these concerns are studied later, they should remain separated:

```text
Model / Runtime implementation
    ↓
Computational-semantics boundary
    ↓
Declaration → Instantiation → Execution
    ↓
Execution-state structure
    ↓
Evaluation
```

Loading and residency belong primarily to computational-object lifecycle and
implementation-boundary semantics. Execution-state belongs to behavioral structure.
They are related but should not be forced into one theoretical object.

## 6. Boundaries

This retrospective does not define execution-state, lifecycle, residency, or any new
formal object. It does not reopen A2.0, create `R-INTERNAL-20`, select a route,
authorize implementation, or authorize experiments. The A2.0 value core remains
frozen as a disciplined generic optimization schema candidate.
