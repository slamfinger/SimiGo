# SimiGo 2.0 — Execution-State-oriented Runtime Experiment

> **Historical package README.** The authoritative current state is
> `../README.md`, `../docs/RESEARCH_STATE.md`, and the frozen Execution State
> Contract. The E1–E5 ladder below records the engineering route and is not a
> claim that those are the current active gates.

This directory contains the SimiGo 2.0 experimental runtime and verification code.

## Position

SimiGo is **not** attempting to replace MLX, Llama, or other model-execution backends.

The current experiment asks a narrower systems question:

> **Is Execution State the missing semantic boundary between execution semantics and physical resource management?**

The working hypothesis is expressed as an engineering boundary, not as a claim of a new universal architecture:

```
Execution State
  = logical identity + lineage + position + continuation
  ≠ physical representation
  ≠ residency state
```

The Runtime owns the logical execution contract. The Backend owns physical model state and computation semantics.

## Current engineering gate

```
E1  Execution Continuity Contract       VERIFIED
E2  Fake Runtime lifecycle tree         VERIFIED
E3  MLX Execution-State Adapter         VERIFIED
E4  Continuity + Residency Integration  NEXT
E5  End-to-End scenario                 NOT STARTED
```

Latest registered E3 result: commit `646bc098`, **84/84 tests PASS**.

E3 introduces an MLX-backed representation adapter while keeping physical-state sovereignty in the Backend. The current concrete representation strategy is an implementation strategy, not the semantic definition of Execution State.

## Runtime boundary

```
                    SimiGo Runtime
                         │
              ┌──────────┴──────────┐
              │                     │
      Execution Continuity    Resource Lifecycle
              │                     │
      identity / lineage       residency / materialization
      position / continuation  eviction / resource state
              │                     │
              └──────────┬──────────┘
                         │
                  Backend Adapter
                         │
                         ▼
                        MLX
```

The invariant is:

```
Execution State ≠ KV Cache ≠ Residency State
```

Representation migration must preserve execution identity and continuation semantics.

## What this experiment does not claim

It does not claim:

- a new MLX or Llama implementation;
- a second KV engine;
- universal model-architecture support;
- layer skipping or reduced Transformer computation;
- predictive execution-state demand;
- performance superiority;
- a general-purpose inference architecture.

The purpose is to determine whether the Execution State boundary can be made **concrete, testable, and compatible with a real Backend**.

## Development path

```
E1 Contract
   ↓
E2 Fake Runtime
   ↓
E3 Real Backend Adapter
   ↓
E4 Continuity + Residency
   ↓
E5 End-to-End Identity / Continuation
```

Research depth follows evidence, not curiosity. Frozen research lines remain frozen unless a new decision explicitly reopens them.

## Commands

    swift build
    swift test

The repository's gate documents and `docs/RESEARCH_STATE.md` are authoritative for current status and acceptance criteria.
