# Future Execution State Mechanisms — Semantic Independence, Model Decomposition, and Minimal Residency Intelligence

**Date:** 2026-09-22  
**Nature:** future architecture hypothesis / research-memory anchor  
**Authority:** non-authoritative; does not open an RQ or authorize implementation  
**Scope:** SimiGo-Lab / future Architecture 2.0+ work

> This document records future mechanisms that were explicitly identified as important architectural questions. They are preserved as hypotheses so that a future Agent does not lose them, but none is treated as established runtime capability.

## 1. The three future questions

The future Execution State line contains at least three distinct questions:

1. **Semantic independence** — can the Execution State mechanism operate without depending on upstream model semantics?
2. **Model decomposition** — can large models be represented, sharded, layered, or otherwise partitioned according to runtime needs rather than requiring the upstream semantic hierarchy as the physical control boundary?
3. **Minimal intelligence in residency** — can the system keep the intelligence required for residency decisions as small as possible, deriving placement/migration decisions from observable runtime behavior rather than embedding a large amount of model-specific knowledge?

These questions are related, but they must not be collapsed into one claim.

## 2. Execution State without upstream semantic dependency

The target distinction is:

```
semantic-assisted
    = upstream semantics are available and may improve decisions

semantic-dependent
    = the mechanism cannot function without upstream semantics
```

The stronger future architecture would aim for:

```
Model / Runtime
      ↓
observable execution behavior
      ↓
access / co-access
residency / migration
continuation / reuse
      ↓
Execution State mechanism
```

In that design, knowledge such as “this is layer 23”, “this is attention”, or “this is an MLP” may be metadata or an optimization hint rather than a hard architectural dependency.

### Important boundary

Semantic independence does **not** mean semantic blindness.

A future implementation may legitimately consume model metadata when it is available. The research question is whether that metadata is **necessary for correctness or existence of the mechanism**, rather than merely useful for optimization.

This directly extends RM-004 and RM-008.

## 3. Model sharding / layering as a runtime problem

The upstream model hierarchy may look like:

```
model
  → layer
      → block
          → attention / MLP
              → tensor
```

A runtime-oriented decomposition may instead need:

```
model
  → execution-state units
      → residency units
          → migration units
              → physical storage regions
```

or, depending on observed behavior:

```
model
  → dynamically co-accessed groups
      → independently resident regions
```

Therefore “分片” and “分层” should remain open concepts rather than prematurely meaning “split by layer”.

The future research question is not:

> Which layer should be put into memory?

It is closer to:

> What decomposition of a model can preserve execution semantics while allowing independently managed residency, migration, reuse, and continuation?

Possible dimensions include:
- layer/block decomposition;
- tensor or tensor-slice decomposition;
- execution-state decomposition;
- dynamically co-accessed groups;
- physical memory regions;
- hybrid combinations.

No one of these is currently selected as the universal unit.

## 4. Minimal intelligence for physical-memory residency

A particularly important future direction is to minimize the amount of “intelligence” required to decide what should physically reside in memory.

The desired architecture is not a large model-specific residency oracle. It is closer to:

```
execution demand
      ↓
observable access / co-access
      ↓
small policy state
      ↓
residency / migration action
```

The policy should ideally need only the minimum information required to make a correct or useful placement decision.

Candidate observable signals include:
- recent access;
- co-access frequency;
- reuse distance;
- residency state;
- migration cost;
- continuation association;
- remaining work;
- memory pressure.

The list is a hypothesis inventory, not a committed instrumentation schema.

### Why this matters

If residency requires deep knowledge of the upstream model, then the runtime becomes tightly coupled to:
- model family;
- model graph structure;
- framework-specific semantic APIs;
- upstream naming and object identity.

If residency can be driven largely by observable behavior, the mechanism could potentially become:
- more model-family agnostic;
- less dependent on upstream semantic changes;
- applicable across different execution representations;
- easier to move between runtime implementations.

These are potential consequences, not established results.

## 5. A possible architecture

A future architecture may eventually separate four layers:

```
┌─────────────────────────────────────┐
│ Model semantics                     │
│ optional hints / metadata           │
└──────────────────┬──────────────────┘
                   │ optional
                   ▼
┌─────────────────────────────────────┐
│ Execution State                     │
│ identity / continuation / branches  │
└──────────────────┬──────────────────┘
                   ▼
┌─────────────────────────────────────┐
│ Runtime-observable structure        │
│ access / co-access / residency      │
│ migration / continuation relations  │
└──────────────────┬──────────────────┘
                   ▼
┌─────────────────────────────────────┐
│ Minimal residency policy             │
│ keep / evict / migrate / materialize│
└─────────────────────────────────────┘
```

The central design aspiration is that the lower layers should not require the upper semantic layer merely to exist.

## 6. Relation to the current Source/Runtime research direction

The current RBS work defines a runtime boundary object:

```
B(M,W,O) = runtime-observable boundary structure
```

with candidate descriptive relations:

```
S(b) = <A_b, R_b, C_b, I_b>
```

This future mechanism line asks a subsequent question:

> If such runtime-observable structure exists, can it support an Execution State / residency mechanism without requiring upstream semantic interpretation?

That is a future bridge only.

It does **not** mean that the current RBS definition has already answered semantic independence.

## 7. Research decomposition that should be preserved

These future questions should eventually be separated into at least:

### FES-01 — Semantic independence

Can the mechanism operate when upstream semantic labels/structure are unavailable, while retaining the required execution behavior?

### FES-02 — Runtime decomposition

Can a model be partitioned into independently manageable units using runtime-observable properties while preserving required execution semantics?

### FES-03 — Minimal residency intelligence

What is the minimum information required for a residency policy to make the required placement/migration decisions?

These are candidate future questions only. They are **not registered RQs**.

## 8. What must be demonstrated before implementation authority

A future study should first establish, independently for each question:

```
research object
    ↓
independence
    ↓
estimand
    ↓
existence criterion
    ↓
insufficiency criterion
    ↓
discriminating observation
    ↓
information value / cost
    ↓
runtime mechanism
```

Only after the corresponding research gate is passed should a concrete Swift/MLX implementation be authorized.

## 9. Explicit non-claims

This document does not establish that:
- current MLX/Swift exposes a semantic-independent execution-state mechanism;
- layer-independent sharding is already possible;
- dynamic co-access is the correct universal partitioning principle;
- residency can be solved with a small policy;
- model semantics are unnecessary in every runtime;
- a particular allocator, tensor, page, layer, block, or KV segment is the correct physical unit;
- any of these mechanisms should be implemented now.

## 10. Relationship to durable memory

Related durable memories:
- RM-003 — semantic hierarchy may differ from residency hierarchy
- RM-004 — can SimiGo work without upstream semantic dependency?
- RM-005 — access pattern may determine useful unit
- RM-007 — unit discovery precedes implementation choice
- RM-008 — semantic independence is stronger than semantic availability
- RM-022 — mechanism existence must precede implementation authority
- RM-023 — research object can move upward when lower layers are already available

This document extends those memories by grouping the future mechanism questions into a coherent architecture hypothesis without promoting them to current research state.

## 11. Status

**FUTURE ARCHITECTURE HYPOTHESIS / CANDIDATE RESEARCH FAMILY / NOT REGISTERED**

Current authority remains `docs/RESEARCH_STATE.md`.
