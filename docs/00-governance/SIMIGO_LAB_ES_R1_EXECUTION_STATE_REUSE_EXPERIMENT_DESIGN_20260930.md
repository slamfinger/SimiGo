# ES-R1 — Execution State Reuse After Representation Loss
Date: 2026-09-30
Status: EXPERIMENT DESIGN / OPEN

## Research question
> Representation disappears. Can the existing Execution State still be read and reused to continue execution without complete history and without full cold prefill?

## Why this experiment exists
PALACE-1 established that current cold recovery can use conversation history after checkpoint/prefix representations are absent. That proves a recovery path, but it does not prove that cold prefill is necessary.

This experiment isolates that ambiguity.

## Phase A — Read-only fact trace
Trace the complete lifecycle of one successful Execution State through:
- identity;
- lineage;
- position;
- continuation information;
- durable metadata;
- RepresentationRef;
- BindingRegistry;
- checkpoint/prefix artifacts;
- restore;
- attach/materialize;
- generation.

For every item classify:
- Runtime-owned;
- Durable semantic information;
- Runtime binding;
- Physical representation;
- observability/history;
- transient/reconstructable;
- unknown.

Do not add code in Phase A.

## Phase B — Representation-loss boundary
Use a disposable copy/fixture only.

Record:
1. State before loss;
2. exact Physical Representation removed;
3. exact information remaining;
4. every API/path that can still consume that information.

Do not mutate the real user store.

## Phase C — Reuse attempt
Attempt the smallest existing/public path that can:
- create a fresh runtime binding;
- identify the same Execution State;
- restore its position;
- continue from that position;
- avoid reading the complete conversation history;
- avoid full prefill.

If no such path exists, record the exact first missing seam. Do not immediately invent a schema.

## Phase D — Semantic equivalence
Use a deterministic probe.

Compare:
- baseline continuation from the live state;
- continuation after Representation loss and State reuse.

The primary result is semantic continuity, not latency.

## Phase E — Cold-prefill control
Run the existing history-based cold path as the control.

This establishes that:
- cold prefill is available;
- reuse, if successful, is a distinct path;
- the two paths are not being confused.

## Pre-registered outcomes
R1-A: STATE-REUSABLE-WITHOUT-FULL-PREFILL
R1-B: STATE-EXISTS-BUT-NO-REUSE-SEAM
R1-C: REPRESENTATION-IS-SEMANTICALLY-REQUIRED
R1-D: INCONCLUSIVE

R1-C must not be inferred merely because current code lacks a reuse API.

## Required evidence
A successful result requires an observed execution trace, not code inspection alone.

A failed result must identify the first concrete information/seam that is absent.

## Safety / publication boundary
This is internal research. Do not publish concrete recovery recipes, local paths, persistence-field combinations, isolation-bypass methods, or procedures that could expose another person's state.

## Exit gate
Only after R1 is sealed may ES-R2 backend takeover be executed.
