# ES-R2 — Backend Takeover of an Existing Execution State
Date: 2026-09-30
Status: EXPERIMENT DESIGN / BLOCKED ON ES-R1

## Research question
> Can a different backend take over an existing Execution State when the original MLX Physical Representation is unavailable?

## Dependency
ES-R1 must first establish whether an Execution State can be reused independently of its current Physical Representation.

## Phase A — Seam audit
Trace:
- ExecutionID;
- lineage;
- position;
- continuation/history;
- RepresentationRef;
- BindingRegistry;
- backend adapter;
- materialization/recovery result.

Classify every dependency as:
- Runtime semantic;
- backend-owned;
- representation-dependent;
- MLX-specific;
- unknown.

## Phase B — Heterogeneous representation
Use an existing registered non-MLX adapter.

The experiment must not require the adapter to understand MLX Physical Representation.

The test fixture should contain only synthetic or already-authorized state.

## Phase C — Takeover
Remove or withhold the original representation.

Attempt:
1. identify the same Execution State;
2. establish a backend-local representation;
3. continue from the recorded semantic position;
4. verify identity and lineage;
5. verify continuation behavior.

## Success boundary
Success means semantic continuity survives backend replacement.

It does NOT prove:
- universal artifact portability;
- arbitrary model equivalence;
- production readiness;
- performance parity.

## Failure boundary
If takeover fails, record the first concrete seam:
- missing durable semantic information;
- identity reservation;
- lineage closure;
- position/continuation material;
- backend materialization capability;
- contract violation.

Do not solve multiple gaps in one iteration.

## Exit gate
ES-R2 is sealed only when one minimal boundary is experimentally demonstrated or one concrete blocker is proven.
