# Architecture 2.0 Origin Reconstruction — From Long-Context Limits to Execution State

**Date:** 2026-09-22  
**Nature:** curated historical reconstruction  
**Authority:** historical/contextual only  
**Scope:** SimiGo-Lab / SimiGo 2.0

> This document reconstructs the earliest recoverable conceptual transition in Architecture 2.0. It is not a verbatim transcript and does not claim an exhaustive chronology.

## 1. The problem existed before “Execution State”

The earliest recoverable 2.0 framing was a practical question:

> How can SimiGo continue to extend local long-context capability when context length, model size, unified memory, and runtime working set increasingly collide?

The first framing naturally produced two directions:

1. **Scale memory / tolerate larger machines.**
2. **Change the computational unit so a complete model + complete context + complete inference is no longer the only possible unit of work.**

The first direction later became the seed of Adaptive Memory.

The second direction became the more consequential architectural branch.

## 2. “Computation decomposition” was the first bridge

The initial decomposition intuition can be represented as:

```
complete context
      ↓
partition
      ↓
independent / partially independent computation
      ↓
intermediate state
      ↓
merge / continue
```

The important conceptual change was not yet a particular Page implementation.

It was the removal of an assumption:

> a long-context inference does not necessarily have to remain one indivisible computation.

This opened several possible mechanisms:
- partitioning computation;
- retaining intermediate state;
- reusing prior computation;
- deriving multiple continuations;
- restoring state instead of recomputing.

At this stage these were candidate mechanisms, not established runtime capabilities.

## 3. The key question shifted from “faster” to “avoid recomputation”

A critical conceptual fork then appeared.

There are two fundamentally different ways to improve a long-context workload:

```
A. make the same computation cheaper
       ↓
   faster prefill / better kernel / less traffic

B. avoid doing the same expensive computation again
       ↓
   retain / reuse / fork execution state
```

This distinction explains the later Track A / Track B split:

- **Track A:** improve the efficiency of one computation;
- **Track B:** turn completed computation into reusable computational state.

The second direction is where “compute once, multiple futures” became meaningful.

## 4. Why existing KV mechanisms were not the complete answer

By the time this distinction became clear, SimiGo already had mechanisms related to:
- chunked prefill;
- KV checkpoint / restore;
- prefix reuse.

These demonstrated that pieces of long-context computation could already be retained or reused.

But they did not by themselves answer the stronger question:

```
Can one execution state
        ↓
produce multiple derived states
        ↓
with identity and continuation preserved?
```

That was the point at which “KV cache optimization” became too narrow a description of the research problem.

The missing abstraction was therefore formulated as **Execution State**.

## 5. “Compute once, multiple futures”

The durable formulation was:

> **Compute once, multiple futures.**

Its meaning is:

```
expensive long-context computation
            ↓
      reusable state
            ↓
      ┌─────┼─────┐
      ↓     ↓     ↓
   future A B     C
```

The value is not simply lower latency for one continuation.

The value is that one expensive computation can become an asset from which several valid continuations can be derived.

This is the conceptual origin of:
- fork;
- branch;
- restore;
- continuation identity;
- child isolation;
- shared historical state;
- lazy materialization.

## 6. The F0 boundary made the abstraction concrete

The later F0 probe supplied an important reality check.

The public runtime surface did not expose the sequence identity required by the intended fork semantics.

This separated two claims:

```
state can be serialized/copied
        ≠
execution identity can be forked
```

A disk fork could reproduce bytes, but its cost was fundamentally different from a low-cost logical fork.

Therefore the research target became:

> Can execution identity and continuation semantics become first-class runtime state?

This was a much stronger and more precise question than “can KV be copied?”

## 7. The hybrid architecture sharpened the model

The Qwen3.5-style hybrid architecture then made the Execution State abstraction more interesting.

The state is heterogeneous:

```
Execution State
├── Attention → historical KV
└── GDN       → recurrent state
```

The early reasoning did not require every component to use identical storage semantics.

Instead:

```
one external Execution State
        ↓
component-specific fork semantics
        ├── attention: shared history + private append
        └── GDN: functional/reference-style fork
```

This established a general architectural principle:

> A unified execution-state lifecycle does not require uniform internal representation.

That principle later became directly relevant to Track B.

## 8. The “split everything into tasks” route was corrected

The original decomposition intuition could easily be overextended into:

```
one large GPU operation
      ↓
many application tasks
      ↓
concurrent execution
```

The physical-resource analysis corrected this.

On one saturated GPU, application-level task multiplication does not create another GPU.

Therefore every decomposition proposal must answer:

> **What additional physical resource or lower-level execution mechanism does this decomposition actually exploit?**

This produced the durable separation:

- application-level splitting on the same saturated GPU → no automatic new parallel resource;
- kernel decomposition → Track A;
- multi-device decomposition → Track C;
- execution-state decomposition/reuse → Track B.

This was a boundary correction, not a rejection of decomposition as a whole.

## 9. The research program consequently moved upward

After existing lower-layer mechanisms and the physical constraints were separated, the unresolved question was no longer simply:

> How do we store more KV?

It became:

> What is the runtime object that carries identity, continuation, residency, migration, reuse, and cost?

That question naturally led from:

```
KV storage
    ↓
Execution State
    ↓
residency
    ↓
runtime-observable boundary
    ↓
operational unit
    ↓
runtime mechanism
```

This upward movement is the conceptual bridge from the original 2.0 idea to the current Source/Runtime research direction.

## 10. What this reconstruction establishes — and what it does not

### Established as historical intellectual lineage

The recoverable lineage is:

```
long-context limit
    ↓
two broad escape routes
    ↓
computation decomposition
    ↓
faster-vs-reuse distinction
    ↓
compute once, multiple futures
    ↓
Execution State
    ↓
identity / continuation / fork
    ↓
heterogeneous state semantics
    ↓
runtime boundary question
```

### Not established by this document

This reconstruction does **not** prove:
- that a production Swift/MLX Execution State implementation exists;
- that a universal Page unit exists;
- that a particular runtime object is the correct Model Unit;
- that access pattern is already a runtime law;
- that semantic-independent runtime control has been demonstrated;
- that Architecture 2.0 itself is production architecture.

Those questions remain governed by current research state and evidence.

## 11. Historical gap retained explicitly

The exact conversation-by-conversation chronology before the formulation “Compute once, multiple futures” is not fully recoverable from retained context.

Accordingly, this document intentionally records the **conceptual lineage**, not a fabricated chronology.

That distinction is part of the archive's provenance discipline.

## 12. Cross-Agent recovery value

A future Agent should be able to read this document and understand why the project did not simply continue adding another KV optimization.

The decisive conceptual transition was:

```
“make long-context computation faster”
              ↓
“avoid repeating expensive computation”
              ↓
“make the computed state reusable”
              ↓
“make the reusable state forkable”
              ↓
“identify the runtime object that can actually carry that semantics”
```

That is the architectural origin that must survive the loss of the original conversation.
