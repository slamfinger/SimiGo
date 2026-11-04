# Runtime Consistency Contract — D1 (Public)

Status: IMPLEMENTED / VERIFIED
Date: 2026-09-27

## Purpose

D1 defines the consistency boundary for one SimiGo Runtime turn. It deliberately does not introduce distributed transactions, persistent WAL, global rollback, or a transaction coordinator.

## State layers

```text
HTTP / Product
      ↓
Execution State
      ↓
Representation
      ↓
Residency
      ↓
Physical MLX
```

## Logical commit boundary

The Runtime logical commit is the pair:

1. representation binding for position N+1;
2. execution position advance to N+1.

The binding is established first and the logical position advances second. The commit section is non-suspending, so cancellation cannot split the pair.

## Cancellation

Cancellation is phase-boundary observation semantics:

- observed before the commit boundary → ABORT;
- observed during or after the commit section → COMMIT.

ABORT leaves the logical position and committed representation unchanged and discards partial generated tokens. COMMIT makes the turn durable even if the client-side cancellation arrives too late to be observed before commit.

## Reconciliation

INV-3 checks whether residency bookkeeping still describes physical reality:

```text
|observedPhysicalBytes - (residentBookkeeping + C_model)| ≤ ε
```

Reconciliation is an observation/detection mechanism. Divergence becomes visible through DIRTY/recovery; reconciliation is not a transaction participant.

## Reattach

Reattach restores logical Execution State without requiring immediate physical residency. Physical materialization is lazy and occurs on the next forward through per-unit admission.

## Boundary

D1 supports Runtime-level logical consistency. It does not claim physical MLX ACID semantics or process-crash atomicity.