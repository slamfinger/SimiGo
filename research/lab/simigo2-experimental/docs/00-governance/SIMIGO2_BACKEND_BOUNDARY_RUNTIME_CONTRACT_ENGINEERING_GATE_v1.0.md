# SimiGo 2.0 — Backend Boundary / Runtime Contract Engineering Gate v1.0

Status: NEXT_ENGINEERING_GATE_REGISTERED / L1_L2_PRECONDITION_PASS
Date: 2026-09-25
Branch: `exp/simigo2-experimental`

## 0. Decision

The SimiGo 2.0 engineering direction is refined as follows:

> **SimiGo is a Runtime that manages model lifecycle and runtime resources; the Backend manages how the model computes.**

Therefore the next implementation gate is **Backend Boundary / Runtime Contract**, before production Controller implementation.

The purpose is not to add a second backend. The purpose is to make the existing:

`Controller → Materializer → MLX`

chain depend on a backend-neutral Runtime Contract.

## 1. Why this gate comes first

The existing L1/L2 verification has already established the pure planner and state-machine contract. The current state-machine remains a verification skeleton, while the existing materialization code is MLX-specific.

Implementing the production Controller directly against MLX would risk making the Controller an MLX Controller and create later architectural refactoring.

The correct dependency direction is:

`SimiGo Runtime → Runtime Contract → Backend implementation → Compute`

not:

`SimiGo Runtime → MLX APIs`

## 2. Scope

This gate SHALL:

1. Define a small, pure-Swift Backend/Materializer contract.
2. Keep the contract free of MLX imports and model-architecture types.
3. Define the runtime-facing operations required by the frozen residency contract:
   - materialize/load a group;
   - evict/release a group;
   - expose/reconcile runtime residency or memory accounting;
   - execute the required runtime audit/reconciliation boundary.
4. Make the Controller depend on the contract, not on MLX.
5. Implement MLX as the first concrete backend/materializer behind that boundary.
6. Add unit tests proving the Controller-facing contract can be exercised without MLX.
7. Preserve the existing L1/L2 behavior and all research artifacts.

## 3. Explicit non-goals

This gate MUST NOT:

- implement a second backend;
- claim cross-backend verification;
- redesign the frozen residency research;
- introduce Predictor/Probability/Demand research;
- add Router/Expert observation;
- modify MLX internals;
- introduce async I/O;
- turn the Backend contract into a model framework;
- move tokenization, generation, attention, architecture interpretation, or model semantics into SimiGo Runtime.

## 4. Boundary responsibilities

### SimiGo Runtime owns

- session/lifecycle state;
- host-supplied memory budget;
- residency bookkeeping;
- Controller state;
- Planner invocation;
- admission/recovery/pressure decisions;
- transfer audit trail;
- resource accounting.

### Backend owns

- model loading semantics;
- model-specific materialization;
- release/eviction implementation;
- model/architecture-specific execution details;
- backend-specific memory behavior;
- forward/generation semantics.

### Contract owns only the bridge

The contract expresses what the Runtime needs from a Backend. It MUST NOT express how a model computes.

## 5. First implementation target

The first concrete path remains:

`SimiGo Runtime → MLX Backend → Apple Silicon unified memory`

MLX is therefore a **validated Backend implementation**, not the definition of SimiGo.

The unified-memory hardware model is treated as an engineering environment, not as a Backend API. SimiGo manages runtime resource state over that shared memory; the Backend remains responsible for turning residency operations into valid compute-backend state.

## 6. Support-status discipline

The following distinctions remain mandatory:

1. Backend can execute a model.
2. SimiGo has a Backend integration.
3. SimiGo Runtime can manage its resource lifecycle.
4. The combined path passes identity/runtime verification.

`Model compatibility ≠ Backend compatibility ≠ SimiGo Runtime compatibility ≠ verified end-to-end support`

No "universal backend" claim is authorized by this gate.

## 7. Revised execution plan

The previous sequence:

`Controller → L3 → L4`

is replaced by:

```
Research
  CLOSED / FROZEN
      ↓
Requirements
  COMPLETE
      ↓
Verification Design
  COMPLETE
      ↓
L1/L2
  60/60 PASS
      ↓
[CURRENT GATE]
Backend Boundary / Runtime Contract
      ↓
MLX Backend Adapter
      ↓
Controller production body
      ↓
L1/L2 regression
      ↓
L3 Fault Injection
      ↓
L4 Real Runtime Verification
```

A gate is passed only when its executable verification evidence exists.

## 8. Immediate work order

### B1 — Contract surface
Define the smallest Backend/Materializer protocol and its value/report types.

### B2 — Contract tests
Add pure-Swift tests for:
- deterministic transfer result handling;
- load/evict success and failure;
- byte/report propagation;
- audit/reconciliation result propagation;
- no dependency on MLX types.

### B3 — MLX implementation
Wrap the existing validated MLX materialization/release behavior behind the contract.

### B4 — Controller integration
Implement the production Controller against the contract only.

### B5 — Regression gate
Run the existing L1/L2 suite and verify no registered research artifact changes.

Only after B1–B5 pass:

### L3 — Fault injection
Implement F1–F8 against the Controller + mock Backend.

Then:

### L4 — Real runtime
Connect Controller + MLX Backend to real models and execute INV-3 / output identity / runtime reconciliation.

## 9. Architectural acceptance criteria

This gate is complete only if all are true:

- Controller source has no MLX dependency.
- Runtime Contract source has no MLX dependency.
- MLX-specific operations are isolated behind the concrete Backend implementation.
- L1/L2 remain passing.
- No research-line artifact changes.
- A mock Backend can exercise Controller behavior without MLX.
- Existing real MLX behavior remains reachable through the new boundary.
- No cross-backend support claim is made.

## 10. Frozen research boundary

This gate does not reopen the research line.

The following remain closed:

- execution locality at Layer/Group resolution;
- predictor;
- Router/Expert;
- probability/demand modeling;
- retention optimization;
- A2.0 theory line;
- production MLX modification;
- async I/O;
- frozen Optimal*/Demand/Probability vocabulary.

The Backend Boundary is an engineering architecture decision derived from the already registered evidence.

## 11. Anchor

> **SimiGo does not decide what the model computes; it decides in what resource state the model runs.**

And:

> **MLX is the first Backend, not SimiGo's identity.**
