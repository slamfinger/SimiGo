# SimiGo 2.0 — Execution State Engineering Gate v1.0 (Gate B)

Status: EXECUTION_STATE_ENGINEERING_GATE_OPEN / E1_CONTRACT_NEXT
Date: 2026-09-25
Anchor: repository `slamfinger/SimiGo-Lab`, branch `exp/simigo2-experimental`
Semantic source: `SIMIGO2_EXECUTION_CONTINUITY_ARCHITECTURE_v1.0.md` (E0) —
the frozen Track B Execution State semantics registered as the foundational
architecture; Track B research remains CLOSED / FROZEN.
Predecessor: `SIMIGO2_RUNTIME_ENGINEERING_VALIDATION_COMPLETE_v1.0.md`
(Gate A).

## 0. Decision

The Runtime Residency Engineering validation line is complete (Gate A).
SimiGo 2.0 now enters its core engineering line: **Execution State
Engineering** — making the frozen Track B Execution State semantics a
first-class Runtime object for the first time.

This is an engineering gate, not research. It does not reopen Track B
research, F1–F5, A2.0, or any frozen line.

## 1. Core invariant (registered as the 2.0 engineering invariant)

> **Representation migration MUST preserve: Execution Identity, Position,
> Next Input, Continuation Semantics, and Subsequent State Evolution.**

Consequently:

```text
Resident / Evicted / Materialized / Checkpointed / Restored / Migrated
        = Representation State        (physical, Backend-managed)
        ≠ Execution State Identity    (logical, Runtime-owned)
```

A group being evicted does not destroy an Execution State. A checkpoint
does not create a new one. Identity lives on the logical side.

## 2. Work order and per-gate acceptance

### E1 — Execution Continuity Contract (pure Swift, in `SimiGoRuntimeContract`)

Smallest backend-neutral contract, placed in the MLX-free contract target
(enforced by the package graph). Semantic objects:

```text
ExecutionID              stable logical identity of one execution state
ExecutionLineage         parent linkage and branch ancestry
ExecutionPosition        where the execution is in its own timeline
ExecutionContinuation    what a valid continuation is (next input/state)
ExecutionStateHandle     runtime handle binding logical state to lifecycle
ExecutionForkRequest     fork parameters (child derivation)
ExecutionRestoreRequest  restore parameters (logical position target)
ExecutionBranchLifecycle create/attach, continue, fork, restore,
                         reattach, discard
```

Exact type names are implementation decisions; the semantic fields MUST
remain traceable to the frozen Track B invariant. Lifecycle operations are
limited to the Track B set: create/attach, continue, fork, restore,
reattach, discard. No merge, no speculative decoding, no predictor.

Acceptance: contract compiles in the MLX-free target; semantics traceable
to Track B; no physical-representation types.

### E2 — Pure-Swift verification with `FakeExecutionBackend`

State-machine verification of the full lifecycle tree:

```text
A
 ├── continue
 ├── fork → B
 │          ├── continue
 │          ├── restore
 │          ├── reattach
 │          └── discard
 └── continue
```

Minimum assertions (from the E0 architecture registration):

```text
V1  fork(A)→B: A.identity == original A.identity        (parent stable)
V2  B.identity != A.identity; B.lineage.parent == A     (child distinct)
V3  child continuation changes do not pollute the parent (independence)
V4  discard(B); continue(A) uses A's OWN continuation    (no cross-flow)
V5  restore(B, position) restores the LOGICAL execution
    state (identity/position), not a tensor copy
V6  reattach preserves the registered continuation contract
V7  a representation change cannot silently change identity
    or continuation
V8  exactly one authoritative lifecycle record per transition
```

Acceptance: all assertions pass exhaustively over the reachable lifecycle
state space (depth-bounded enumeration, the L2 method).

### E3 — MLX Execution-State adapter

Extend the existing Backend boundary (B3 pattern) with execution-state
operations:

```text
ExecutionContinuityRuntime
        ↓
ExecutionStateBackend Contract
        ↓
MLX Execution-State Adapter
        ↓
MLX physical KV / recurrent state (checkpoint, KV representation,
KVCache.copy(), future shared-prefix primitives)
```

The adapter owns translation between the semantic contract and MLX physical
state. Checkpoint/KV/copy strategies are **Backend Representation Strategy**
— not SimiGo core semantics. SimiGo MUST NOT become a second KV authority.

Acceptance: adapter passes the E2 contract assertions against real MLX
state on one model; no MLX imports in the Controller or contract targets.

### E4 — Continuity + Residency integration

First integration of the two validated capabilities:

```text
ExecutionState
  ├── Logical:    identity / lineage / position / continuation
  └── Physical:   backend state / residency / materialization /
                  eviction / budget
```

Core integration invariant: **changing the physical resource state must not
silently create a new Execution Identity or invalidate the logical
continuation** — an evicted Execution State IS still the same Execution
State. The combined state matrix is derived from actual requirements, not
invented prematurely.

Acceptance: an execution state survives eviction → re-materialization →
restore with identity/continuation unchanged, verified by the E2 assertion
set against the real backend.

### E5 — End-to-end product scenario

```text
Create → Generate → Fork
   ├─ Parent: Continue
   └─ Child:  Continue → Evict → Re-materialize → Restore → Continue
→ Discard child → Parent Continue
```

Final comparison across the whole scenario: Execution Identity, Lineage,
Position, Next Input, Continuation, Token Sequence, Logits.

Acceptance: full-scenario identity PASS on real models; this completes the
Execution State Runtime loop (Execution Semantics + Execution Continuity +
Resource Lifecycle + Backend).

## 3. Boundary discipline (inherited, unchanged)

- No new research; Track B experiments are not rerun; no F1–F5 reopening.
- No second KV authority; no parallel physical-state implementation.
- No merge of execution branches; no speculative execution; no predictor.
- No Router/Expert; no MLX upstream modifications; no async I/O research.
- No performance claims from frozen Track B evidence.
- Any future requirement for these enters through the normal
  authorization boundary.

## 4. Status

```text
Gate A (Runtime Engineering Validation) : COMPLETE
Gate B (Execution State Engineering)    : OPEN
E1 contract                             : NEXT (no code before its tests
                                          are designed — tests-first)
E2 / E3 / E4 / E5                       : NOT STARTED
Research lines                          : all CLOSED / FROZEN
```
