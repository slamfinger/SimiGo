# SimiGo 2.0 — Execution Continuity Runtime Experiment & Engineering Path v1.1

Status: **RUNTIME_EXPERIMENT_POSITION_REGISTERED / TRACK_B_FOUNDATIONAL / E3_VERIFIED / E4_NEXT**  
Date: 2026-09-25  
Branch: `exp/simigo2-experimental`

## 0. Purpose

This document registers the frozen Track B Execution State semantics as the semantic source for a **SimiGo Runtime experiment**.

The project does **not** claim a new general model-execution architecture. SimiGo does not reimplement MLX, Llama, or another model backend. The experiment asks:

> **Is Execution State the missing semantic boundary between model execution semantics and physical resource management?**

Track B remains CLOSED / FROZEN. The current work is engineering verification of whether that boundary can be made concrete on top of an existing Backend.

## 1. Experimental position

The central Runtime proposition is:

> **SimiGo Runtime manages Execution Continuity and Resource Lifecycle; Backend manages physical model execution and computation semantics.**

This is an experimental integration boundary, not a claim that SimiGo has replaced or superseded existing inference runtimes.

The Runtime separates two dimensions:

```
SimiGo Runtime
├── Execution Continuity
│   ├── Execution Identity
│   ├── Lineage
│   ├── Position
│   ├── Continuation
│   ├── Fork
│   ├── Restore
│   ├── Reattach
│   └── Discard
│
└── Resource Lifecycle
    ├── Residency
    ├── Materialization
    ├── Eviction
    ├── Budget
    └── Resource Accounting
```

The distinction is:

```
Execution State ≠ Residency State
Execution State ≠ KV Cache
Execution Continuity ≠ Computation Semantics
```

## 2. Frozen semantic source

Track B established the invariant:

> **Representation migration must preserve execution identity and continuation.**

For the current Runtime experiment, preservation includes:

- execution identity;
- lineage;
- execution position;
- next-input state;
- continuation semantics;
- subsequent execution-state evolution.

Physical state is Backend/model dependent. The Runtime contract carries logical execution semantics and lifecycle; it does not become a second physical-state authority.

## 3. Backend sovereignty

SimiGo MUST NOT become a second KV/state implementation.

```
SimiGo Runtime
    logical Execution State
    identity / lineage / position / continuation
    lifecycle and representation binding
            │
            ▼
    Backend Representation Strategy
            │
            ▼
    MLX physical state / model execution
```

KV, Tensor, checkpoint, cache, materialization and other physical representations remain Backend concerns.

The Runtime may hold opaque handles and metadata needed to preserve continuity, but the Backend remains authoritative for physical model state and computation semantics.

## 4. Engineering experiment path

### E0 — Semantic position registration

Completed.

Track B semantics are preserved as the source of the current experiment without reopening the research line.

### E1 — Pure Swift Execution Continuity Contract

**VERIFIED.**

The contract is MLX-free and expresses logical values for identity, lineage, position, continuation, lifecycle, fork and restore.

### E2 — Fake Runtime lifecycle verification

**VERIFIED.**

The Fake Runtime exercised the lifecycle tree and eight registered constraints. Representation migration was tested as orthogonal to lifecycle transitions.

### E3 — Real Backend representation adapter

**VERIFIED.**

Latest registered result: `646bc098`, **84/84 PASS**.

E3 introduces:

- `ExecutionStateBackend` over opaque `ExecutionRepresentation`;
- MLX-backed representation strategy;
- execution-state coordinator implementing the E1 lifecycle;
- explicit representation binding/history;
- sovereignty checks preventing the representation layer from creating or mutating Execution Identity, Lineage, Position or Continuation;
- representation bindings kept separate from lifecycle records.

The current concrete representation strategy is an implementation strategy only. It does not redefine Execution State.

### E4 — Continuity + Residency integration

**NEXT.**

The next experiment combines the two already validated dimensions:

```
Execution State
    ├── logical identity / lineage / continuation
    │
    └── physical representation
             ├── resident
             ├── evicted
             └── re-materialized
```

The critical test is:

> Changing physical resource state must not silently create a new Execution Identity or invalidate the logical continuation.

E4 must use the existing Residency machinery rather than create a competing resource authority.

### E5 — End-to-end execution-state scenario

Target scenario:

```
Create → Generate → Fork
   ├─ Parent: Continue
   └─ Child: Continue → Evict → Re-materialize → Restore → Continue
→ Discard Child → Parent Continue
```

The final gate compares logical identity/lineage/position/continuation and real execution outputs. Performance superiority is not the initial acceptance criterion.

## 5. Explicit boundaries

This experiment does not authorize:

- re-running Track B research;
- a new KV engine;
- a parallel KV authority;
- Router/Expert research;
- predictor/probability models;
- speculative execution;
- branch merge;
- new MLX upstream modifications;
- async I/O research;
- universal model-architecture claims;
- performance claims not independently measured.

A future requirement enters through a separate engineering or research decision.

## 6. Why the experiment matters

The intended contribution is deliberately narrow:

> **to test whether Execution State can serve as a concrete Runtime boundary that remains independent of physical representation while integrating with an existing high-quality model Backend.**

The project therefore should not be described as “a new inference architecture” unless later evidence justifies such a stronger claim.

The current and preferred description is:

> **SimiGo — an Execution-State-oriented Runtime experiment.**

## 7. Final position

Current research status:

```
Track B research       CLOSED / FROZEN
Runtime experiment     ACTIVE
E1                     VERIFIED
E2                     VERIFIED
E3                     VERIFIED
E4                     NEXT
E5                     NOT STARTED
```

The working question remains open:

> **Is Execution State the missing boundary?**

The experiment proceeds by making that boundary concrete and testing it against the existing implementation, rather than assuming the answer in advance.
