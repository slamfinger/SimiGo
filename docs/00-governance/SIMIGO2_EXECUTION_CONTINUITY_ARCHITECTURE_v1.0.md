# SimiGo 2.0 — Execution Continuity Architecture & Engineering Path v1.0

Status: ARCHITECTURAL_POSITION_REGISTERED / TRACK_B_FOUNDATIONAL / ENGINEERING_PATH_DEFINED
Date: 2026-09-25
Branch: exp/simigo2-experimental

## 0. Purpose

This document registers Track B — Execution State Fork as a foundational SimiGo Runtime architecture source and defines how its frozen research results are carried into product engineering.

This is not a reopening of Track B research. Track B remains CLOSED / FROZEN.

The purpose is to prevent the execution-continuity capability proved and defined by Track B from being lost while the 2.0 engineering line implements Residency, Controller, Materializer, and Backend boundaries.

The product architecture therefore treats Execution Continuity and Resource Lifecycle as two first-class Runtime capabilities.

## 1. Architectural decision

The existing SimiGo 2.0 anchor remains valid:

> SimiGo manages model lifecycle and runtime resources; Backend manages how the model computes.

The expanded architecture anchor is:

> SimiGo does not decide what the model computes. SimiGo maintains which execution state is active, how that state continues or branches, and how that state is represented and managed as a runtime resource; the Backend owns the model's physical execution and computation semantics.

The Runtime therefore has two primary dimensions:

    SimiGo Runtime
    ├── Execution Continuity
    │   ├── Execution Identity
    │   ├── Lineage
    │   ├── Position
    │   ├── Next Input
    │   ├── Continuation
    │   ├── Fork
    │   ├── Branch
    │   ├── Restore
    │   ├── Reattach
    │   └── Discard
    │
    └── Resource Lifecycle
        ├── Residency
        ├── Budget
        ├── Materialization
        ├── Eviction
        ├── Memory Pressure
        └── Resource Accounting

These dimensions are distinct:

    Execution State ≠ Residency State
    Execution State ≠ KV Cache
    Execution Continuity ≠ Resource Residency

They must not be collapsed into a single controller abstraction.

## 2. Track B is a foundational architecture source

Track B established the following semantic convergence:

    Execution State
        = KV / physical execution state
        + Identity
        + Position
        + Next Input
        + Continuation Semantics

The physical state component is backend/model dependent. The semantic Execution State contract is a Runtime-level concern.

The frozen Track B invariant is:

> Representation migration must preserve execution identity and continuation.

This is stronger than preserving KV elements alone. A valid representation migration must preserve, as applicable:

- execution identity;
- lineage;
- execution position;
- next-input state;
- continuation token/state;
- subsequent execution-state evolution.

Track B explicitly does not establish a general residency policy and does not replace the Residency line. Its frozen closure also records that Residency and Closure are separate concerns.

## 3. Product importance

Track B must occupy a significant position in the SimiGo product architecture.

    SimiGo 2.0 Runtime
             │
    ┌────────┴────────┐
    │                 │
Execution Continuity  Resource Lifecycle
    │                 │
 Fork / Branch /      Residency / Budget /
 Restore / Reattach   Materialize / Eviction
    │                 │
    └────────┬────────┘
             │
      Execution State
             │
      Backend Boundary
             │
            MLX

The two sides answer different questions:

- Execution Continuity: which execution state exists, where it is in its lineage/position, and what continuation is valid?
- Resource Lifecycle: where the physical state is resident, what budget it consumes, and how it is materialized or released?

A fork is therefore not a residency window. A residency window protects resources during an execution interval; a fork derives a new execution state.

## 4. Critical ownership boundary

SimiGo MUST NOT become a second KV/state implementation.

    SimiGo Runtime owns:
        Execution State semantic identity
        lineage
        position / continuation contract
        fork / branch / restore lifecycle
        representation policy
        resource lifecycle

    Backend owns:
        physical KV / recurrent state representation
        model-specific state tensors
        actual state mutation
        forward / generation semantics
        architecture-specific computation

The Runtime may hold handles, metadata, lineage, and lifecycle state, but it must not establish a parallel physical-KV authority competing with the Backend.

## 5. Engineering path

### E0 — Architecture registration

Completed by this document:

- Track B formally registered as foundational architecture;
- Execution Continuity separated from Residency;
- Execution State semantic boundary recorded;
- no-second-KV-authority boundary recorded;
- Track B research remains CLOSED/FROZEN.

### E1 — Pure Swift Execution Continuity contract

Create the smallest backend-neutral contract for Runtime use.

Candidate semantic values/operations include:

    ExecutionID
    ExecutionLineage
    ExecutionPosition
    ExecutionContinuation
    ExecutionStateHandle
    ExecutionForkRequest
    ExecutionRestoreRequest
    ExecutionBranchLifecycle

The exact type names are implementation decisions; the semantic fields must remain traceable to the frozen Track B invariant.

The contract MUST NOT import MLX, MLXLMCommon, model architecture types, or physical KV implementations.

Initial lifecycle operations should be limited to those established by Track B:

    create / attach
    continue
    fork
    restore
    reattach
    discard

Do not add merge, speculative decoding, predictor logic, or new execution research merely because the abstraction exists.

### E2 — Contract tests without MLX

Before connecting a real backend, test the semantic state machine using a pure Swift fake backend.

Minimum engineering assertions:

1. parent identity remains stable after fork;
2. child identity/lineage is distinct and traceable;
3. child continuation is independently represented;
4. discard leaves the parent at its own valid continuation;
5. restore returns the same logical execution identity/position;
6. reattach preserves the registered continuation contract;
7. representation changes cannot silently change identity or continuation;
8. lifecycle transitions have one authoritative state record.

This is an engineering contract test, not a new scientific experiment.

### E3 — Backend adapter boundary

Extend the existing Backend boundary with execution-state operations without moving physical state ownership into SimiGo.

    ExecutionContinuityRuntime
            ↓
    ExecutionStateBackend Contract
            ↓
    MLX Execution-State Adapter
            ↓
    MLX physical KV / recurrent state

The MLX adapter owns translation between the semantic contract and actual MLX state representation. The Runtime owns the logical lifecycle and identity.

### E4 — Connect Execution Continuity to Residency

Only after the semantic contract is stable should execution state and residency be integrated.

    Execution State
          │
          ├── logical identity / continuation
          │
          └── physical representation
                    │
                    ├── resident
                    ├── evicted
                    └── re-materialized

The critical invariant is:

> Changing the physical resource state must not silently create a new Execution Identity or invalidate the logical continuation.

The exact combined state matrix should be derived from actual product requirements rather than invented prematurely.

### E5 — Real MLX integration and identity verification

The real integration gate should verify semantic preservation through the existing identity battery.

Initial target: semantic preservation, not performance superiority.

Performance, memory cost, and fork latency are separate engineering measurements and must not be presented as Track B research conclusions.

## 6. Relationship to current 2.0 engineering

The current Residency engineering line remains valid.

The immediate L4-C gate remains the real-generation identity check for the Controller + Backend path.

Track B registration does not invalidate or restart L1/L2/L3/L4-A/L4-B.

The intended sequence is:

    L4-B reconciliation PASS
          ↓
    L4-C generation identity
          ↓
    stabilize Backend Runtime contract
          ↓
    Execution Continuity pure-Swift contract
          ↓
    Execution Continuity contract tests
          ↓
    MLX Execution-State adapter
          ↓
    Continuity + Residency integration

This avoids two mistakes:

1. allowing Residency work to erase Execution Continuity from the product architecture;
2. interrupting the validated Residency engineering line by reopening Track B research.

## 7. Explicitly not being done

This architecture registration does not authorize:

- rerunning Track B Closure experiments;
- reopening F1/F2/F3/F4/F5 research;
- creating a new KV engine;
- implementing a parallel KV authority;
- Router/Expert research;
- execution-demand prediction;
- speculative execution;
- predictor/probability models;
- performance claims derived from frozen Track B evidence;
- merging execution branches;
- new MLX upstream modifications;
- async I/O research;
- any previously frozen research line.

A future requirement for any of these must enter through the normal engineering/research authorization boundary.

## 8. Product-level capability

The long-term product capability is not merely KV fork.

> A long-lived Execution State can be continued, forked, restored, reattached, and discarded while its physical representation can be managed independently by the Runtime, without changing its execution identity or continuation semantics.

This creates a distinct SimiGo Runtime capability for long-lived agent sessions, multi-turn continuation, branchable execution, checkpoint/restore, resource-constrained execution, execution-state migration, and future multi-branch or multi-agent workflows.

These are product architecture targets, not claims that all are already implemented or verified.

## 9. Frozen boundaries

    Execution State ≠ KV Cache ≠ Residency State
    Fork ≠ Residency Window
    Logical Execution Identity ≠ Physical Tensor Location
    Execution Continuity ≠ Computation Semantics
    SimiGo Runtime ≠ Backend

These boundaries are architectural invariants.

## 10. Final position

Track B is now formally classified as:

    Research status:
        CLOSED / FROZEN

    Architectural status:
        FOUNDATIONAL / PRESERVED

    Product status:
        FIRST-CLASS RUNTIME CAPABILITY

    Engineering status:
        ARCHITECTURE REGISTERED / IMPLEMENTATION PATH DEFINED

The central architectural principle is:

> SimiGo Runtime manages Execution Continuity and Resource Lifecycle; Backend manages physical model execution and computation semantics.

Track B is therefore not a discarded predecessor of the Residency runtime. It is the Execution Continuity foundation on which the broader SimiGo 2.0 Runtime should be built.