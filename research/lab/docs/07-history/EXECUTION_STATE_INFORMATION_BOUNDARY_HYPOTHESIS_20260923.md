# Execution-State Information Boundary Hypothesis

**Date**: 2026-09-23  
**Status**: HYPOTHESIS_REGISTERED / NOT_FORMALIZED / ROUTE_UNSELECTED  
**Nature**: exploratory boundary hypothesis; no new semantic object, definition, route, implementation, or experiment

## 1. Question

Can execution-state decide which model layers or compressed representations are
needed without understanding model-internal semantics?

This becomes important when model layers are heterogeneous, mixed, compressed, or
grouped by data similarity rather than being independently and uniformly useful.

## 2. Candidate separation

```text
Execution state
  = what execution path/state is current or likely next

Capability demand
  = what capability/representation class is required

Model representation / metadata
  = how layers or data groups are organized, compressed, or shared

Loading / residency
  = which representation enters memory and when
```

The key boundary is:

```text
execution-state → capability demand
```

If this mapping is available outside the model black box, execution-state can remain
an independent runtime-control information source. If it requires hidden weights,
attention, activations, routing traces, or internal semantic interpretation, then the
claimed execution-state is already coupled to model-internal computation.

## 3. Layer-similarity / compression case

If layers such as:

```text
L1,L2,L3,L7
```

are highly similar in data structure, statistical properties, or computation
behavior, they may be represented by a compressed or shared capability group:

```text
{L1,L2,L3,L7} → C1
```

Then execution-state only needs:

```text
current/future state → capability demand C1
```

It does not need to know the individual layer organization.

## 4. Heterogeneous / context-dependent case

If layers are mixed representations, or usefulness depends on runtime context:

```text
Pr(L_i useful | S_t,H_t)
```

then execution-state alone may not know why `L_i` is relevant. That knowledge may
come from one of three different information sources:

```text
1. External observable state:
   S_t,H_t → demand probability

2. Static model structure / metadata:
   model representation → demand mapping

3. Runtime internal signals:
   hidden state / attention / activation / routing → demand mapping
```

These are different theoretical and engineering interfaces and must not be mixed.

## 5. Boundary consequence

If external observations suffice, execution-state can remain a black-box upstream
control structure:

```text
execution state
→ capability demand
→ compression/layout policy
→ loading/residency
```

If runtime internal signals are required, then the system needs an explicit
model-representation or internal-observation interface. In that case, execution-state
independence must be re-audited: it may no longer be an external state, but part of
the model's internal computation boundary.

## 6. Status

```text
EXECUTION_STATE_INDEPENDENCE = CONDITIONAL
CONDITION                    = capability demand must be computable without model internals
DATA COMPRESSION             = SEPARATE REPRESENTATION/LAYOUT QUESTION
FORMALIZATION                = NOT AUTHORIZED
```

Layer homogeneity, average mixing, or other compression structures are useful test
conditions, not assumptions to build into execution-state.

## 7. Boundaries

This record does not define layer, capability, compression, metadata, representation
similarity, demand probability, policy, execution interface, `R-INTERNAL-20`, route
selection, R_ORACLE, Δ/gap, FinLoss, NECT, STEP⑤/STEP⑥, implementation, harness,
data collection, profiling, measurement, or experiment work.
