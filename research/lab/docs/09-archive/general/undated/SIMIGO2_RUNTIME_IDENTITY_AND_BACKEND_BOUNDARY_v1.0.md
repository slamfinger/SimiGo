# SimiGo 2.0 — Runtime Identity, Backend Boundary & Current Engineering State v1.0

> **ARCHIVED** 2026-10-20 · line: 通用治理 / 其他 · original: docs/00-governance/SIMIGO2_RUNTIME_IDENTITY_AND_BACKEND_BOUNDARY_v1.0.md
> Evidence status: unchanged (content frozen; moved only)


Status: ARCHITECTURAL_POSITION_REGISTERED / TRACK_B_FOUNDATIONAL / L4B_RECONCILIATION_PASS
Date: 2026-09-25
Branch: `exp/simigo2-experimental`

## 0. Purpose

This document records the SimiGo 2.0 Runtime identity and Backend boundary.
It also records the architectural correction that Track B — Execution Continuity
is a foundational Runtime capability alongside Resource Lifecycle.

It is a design/engineering position, not a new research result. It exists to
prevent later implementation from accidentally coupling SimiGo's identity to
a particular model-computation backend.

## 1. SimiGo's architectural identity

The current architectural definition is:

> **SimiGo manages model lifecycle and runtime resources; Backend manages how
> the model computes.**

Operationally:

```text
SimiGo Runtime
  ├─ Session / Lifecycle
  ├─ Memory Budget
  ├─ Residency Controller
  ├─ Planner
  ├─ Materialization / Eviction
  ├─ Memory Pressure
  └─ Resource Accounting
             │
        Backend Contract
             │
      ┌──────┼──────────┐
      │      │          │
     MLX   Llama      Other
      │      │          │
   model   model      model
 computation computation computation
```

The boundary is:

> **SimiGo does not own model-computation semantics; the Backend supplies
> execution semantics. SimiGo owns the lifecycle/resource state in which that
> computation runs.**

This is the intended long-term architecture.

## 2. Why this boundary is now justified

The frozen research line established, at Layer/Group resolution:

- complete generation execution was measured as FULL;
- no predictive target was established at that resolution;
- residency retention nevertheless has an independent measurable structure;
- reload economics are exactly decomposable as a residency/re-materialization
  trade-off;
- the verified residency mechanism preserves model output identity.

Therefore the central engineering problem is not to make SimiGo understand
Transformer computation or predict which computation will execute. It is to
manage the resources required by an execution supplied by a Backend.

The architectural boundary follows the evidence:

```text
Backend:
    "How does this model compute?"

SimiGo Runtime:
    "How are the model's resources admitted, resident, materialized,
     released, budgeted, reconciled, and recovered while it computes?"
```

## 3. MLX is a Backend, not SimiGo's identity

The current implementation and research evidence are MLX-based.

That establishes:

```text
SimiGo Runtime + MLX Backend = verified execution path
```

It does NOT establish:

```text
SimiGo = MLX
```

Nor does it establish that every model supported by another backend can
already be run through SimiGo.

The dependency on `mlx-swift` / `mlx-swift-lm` should therefore be treated
as a **Backend implementation dependency**, not as an architectural
definition of SimiGo.

This distinction is important because model support can fail at several
different layers:

```text
Model
  ↓
Backend architecture support
  ↓
Backend implementation
  ↓
Swift/native binding
  ↓
Model adapter / loading path
  ↓
SimiGo Backend integration
```

A failure in one layer must not automatically be classified as a failure of
the SimiGo Runtime architecture.

## 4. Backend neutrality: status discipline

The following statements are deliberately separated:

### Verified

- MLX is a working backend for the current SimiGo residency runtime path.
- Real MLX materialization/release/reload behavior has been exercised.
- The residency/controller contracts are designed without requiring planner
  access to MLX/model objects.

### Architecturally intended, not yet cross-backend verified

- A Llama/Meta/native backend can be connected through a backend contract.
- Other computation backends can reuse the same residency/runtime layer.
- Cross-backend semantic equivalence of the residency controller is established.

The last three are **engineering architecture hypotheses/design goals**, not
experimental proofs.

No claim of "universal backend support" is registered here.

## 5. Consequence for model support

SimiGo should not use a single undifferentiated statement such as:

> "SimiGo supports model X."

Instead, later engineering records should distinguish:

1. **Backend can execute the model.**
2. **SimiGo has an adapter/integration for that Backend.**
3. **SimiGo Runtime can manage that model's resource lifecycle.**
4. **The combined path has passed the required identity and runtime tests.**

This yields the more precise relation:

```text
Model compatibility
        ≠
Backend compatibility
        ≠
SimiGo Runtime compatibility
        ≠
Verified end-to-end support
```

## 6. Execution Continuity is a first-class Runtime capability

The resource-oriented Runtime description is incomplete without Track B.
SimiGo Runtime has two primary dimensions:

    Execution Continuity
        Execution Identity / Lineage / Position / Continuation
        Fork / Branch / Restore / Reattach / Discard

    Resource Lifecycle
        Residency / Budget / Materialization / Eviction / Pressure

These dimensions are intentionally separate. Execution State is not KV Cache,
not Residency State, and not a residency window.

Track B is classified as:

    Research:       CLOSED / FROZEN
    Architecture:   FOUNDATIONAL / PRESERVED
    Product:        FIRST-CLASS RUNTIME CAPABILITY
    Engineering:    IMPLEMENTATION PATH DEFINED

The detailed architecture and implementation sequence are registered in
SIMIGO2_EXECUTION_CONTINUITY_ARCHITECTURE_v1.0.md.

The critical ownership boundary is unchanged: SimiGo owns logical execution
identity and lifecycle semantics, while the Backend owns physical KV/state
representation and actual model computation. SimiGo MUST NOT create a second
physical-KV authority.

## 7. Current engineering implementation state

The research line remains:

    CLOSED / FROZEN

The residency engineering line has progressed through L4-B:

    Requirements                    COMPLETE
    Verification Design             COMPLETE
    Implementation L1/L2            PASS
    Controller                      PASS
    L3 Fault Injection              PASS
    L4-A MLX Backend Adapter        PASS
    L4-B Real Reconciliation        PASS / FIVE MODELS
    L4-C Real Generation Identity   NEXT

Execution Continuity is now registered as a foundational product architecture
line. Its pure-Swift contract and contract tests should be designed before
connecting the semantic layer to a real MLX execution-state adapter.

### L1/L2 implementation gate

Remote commits landed:

- `942f0a9` — L1 contract tests
- `3042b70` — L2 state-machine tests
- `2f8bd0c` — minimal L2 state-machine skeleton

The first real `swift test` execution produced:

```text
60 tests / 6 failures
```

The failures were classified rather than silently absorbed:

- **F-L1-1** — planner incorrectly filled unhinted optional groups;
  implementation defect. Fixed.
- **F-L2-1** — `auditMismatch` used the wrong effect label;
  implementation/skeleton defect. Fixed.
- **F-L2-2** — `recover()` replayed from an empty state and could lose the
  original initial resident set, violating INV-1. Latent defect found by
  code audit; fixed and explicitly tested.

After repair:

```text
60 / 60 PASS
```

The planner repair was additionally checked against the two registered
research artifacts (budget sweep and trace replay). Both were
bit-for-bit identical to their archived outputs. Therefore the implementation
fix caused no registered research-line change.

Registered implementation gate result:

```text
IMPLEMENTATION_L1_L2_GATE_PASS
CONTROLLER_IMPLEMENTATION_NEXT
```

Commit:

```text
254638b
```

## 8. Development boundary that must remain stable

Future implementation MUST preserve the following separation:

```text
SimiGo Runtime
    │
    ├── owns lifecycle/resource state
    ├── owns budget/residency accounting
    ├── owns controller decisions
    └── owns materialization lifecycle contract
             │
             ▼
        Backend Contract
             │
    ├── owns model loading semantics
    ├── owns forward/generation semantics
    ├── owns architecture-specific computation
    └── owns backend-specific execution details
```

In particular:

- the planner MUST NOT acquire model/backend semantics;
- the controller MUST NOT become a model-architecture interpreter;
- MLX-specific behavior MUST stay behind the Backend/Materializer boundary;
- adding another Backend MUST NOT require rewriting the residency theory or
  controller state machine merely because its computation architecture differs;
- Backend neutrality must not be claimed as verified until a second backend
  actually passes the required integration/identity battery.

## 9. Relation to the frozen research line

Nothing in this document reopens:

- predictor research;
- Router/Expert observation;
- probability/demand modeling;
- execution-locality research at the closed resolution;
- retention optimization theory;
- the A2.0 theory line;
- production MLX modification;
- async I/O;
- any frozen Optimal*/Demand/Probability vocabulary.

The Backend boundary is an engineering architecture decision derived from the
existing evidence. It is not a new research object.

## 10. One-sentence identity

For future design reviews, the shortest stable statement is:

> **SimiGo Runtime manages Execution Continuity and Resource Lifecycle;
> the Backend manages physical model execution and computation semantics.**

This sentence is the architectural anchor for subsequent SimiGo 2.0 engineering.
