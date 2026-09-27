# SimiGo 2.0 — Execution State Engineering Gate v1.0 (Gate B)

Status: **EXECUTION_STATE_ENGINEERING_GATE_OPEN / E3_VERIFIED / E4_NEXT**  
Date: 2026-09-25  
Anchor: repository `slamfinger/SimiGo-Lab`, branch `exp/simigo2-experimental`  
Semantic source: `SIMIGO2_EXECUTION_CONTINUITY_ARCHITECTURE_v1.0.md` (E0) — frozen Track B Execution State semantics registered as the source of the Runtime experiment; Track B research remains CLOSED / FROZEN.  
Predecessor: `SIMIGO2_RUNTIME_ENGINEERING_VALIDATION_COMPLETE_v1.0.md` (Gate A).

## 0. Decision

The Runtime Residency Engineering validation line is complete (Gate A).

SimiGo 2.0 now runs a focused **Execution-State-oriented Runtime experiment**: test whether Execution State can form a stable semantic boundary between execution continuity and physical resource management on top of an existing Backend.

This is an engineering experiment, not a claim of a new general inference architecture. It does not reimplement MLX/Llama and does not reopen Track B research.

## 1. Core invariant

> **Representation migration MUST preserve: Execution Identity, Position, Next Input, Continuation Semantics, and Subsequent State Evolution.**

Consequently:

```
Resident / Evicted / Materialized / Checkpointed / Restored / Migrated
        = Representation State        (physical, Backend-managed)
        ≠ Execution State Identity    (logical, Runtime-owned)
```

## 2. Work order and acceptance

### E1 — Execution Continuity Contract

**VERIFIED.**

Pure Swift, MLX-free contract in `SimiGoRuntimeContract`. It defines the smallest logical surface for identity, lineage, position, continuation, lifecycle, fork and restore.

### E2 — Fake Runtime lifecycle verification

**VERIFIED.**

Commit: `f4e279a`  
Result: **95/95 PASS**.

The eight registered constraints all passed, including parent/child independence, logical restore, reattach continuity, representation/lifecycle orthogonality, and one authoritative lifecycle record per transition.

### E3 — MLX Execution-State Adapter

**VERIFIED.**

Commit: `646bc098`  
Result: **84/84 PASS**.

E3 introduces:

```
ExecutionContinuityRuntime
        ↓
ExecutionStateBackend
        ↓
MLXExecutionStateBackend
        ↓
Backend Representation
```

The current representation strategy is an implementation strategy, not the semantic definition of Execution State. The adapter operates through opaque representation payloads and explicitly preserves Runtime sovereignty over Execution Identity, Lineage, Position and Continuation.

The current implementation also records representation binding/history separately from lifecycle transitions. Representation bindings are not themselves lifecycle transitions.

SimiGo remains prohibited from becoming a second KV authority.

### E4 — Continuity + Residency integration

**NEXT.**

Acceptance target:

> An Execution State survives physical eviction → re-materialization → restore without changing logical identity or invalidating continuation.

E4 must reuse the existing validated Residency machinery. It must not introduce a competing resource authority.

### E5 — End-to-end scenario

**NOT STARTED.**

Target:

```
Create → Generate → Fork
   ├─ Parent: Continue
   └─ Child: Continue → Evict → Re-materialize → Restore → Continue
→ Discard Child → Parent Continue
```

Final acceptance compares logical Execution State fields and real execution outputs.

## 3. Boundary discipline

- No new Track B research.
- No second KV authority.
- No parallel physical-state implementation.
- No branch merge.
- No speculative execution or predictor.
- No Router/Expert research.
- No MLX upstream modifications.
- No async I/O research.
- No performance superiority claims without separate measurement.
- No universal model-architecture claim.

## 4. Current status

```
Gate A (Runtime Engineering Validation) : COMPLETE
Gate B (Execution State Engineering)    : OPEN

E1 Contract                         : VERIFIED
E2 Fake Runtime                    : VERIFIED — 95/95
E3 MLX Adapter                     : VERIFIED — 84/84
E4 Continuity + Residency          : NEXT
E5 End-to-End                      : NOT STARTED

Track B research                   : CLOSED / FROZEN
```

The project description remains deliberately narrow:

> **SimiGo is an Execution-State-oriented Runtime experiment exploring whether Execution State is the missing semantic boundary between execution semantics and physical resource management.**
