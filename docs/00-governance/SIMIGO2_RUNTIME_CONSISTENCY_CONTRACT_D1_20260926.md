# SimiGo-Lab — Runtime Consistency Contract D1 (Draft for Review) — 2026-09-26

Status: CONTRACT_D1_DRAFT / AWAITING_REVIEW
Scope: FM-04 cancellation contract · FM-05 cross-layer commit boundary ·
INV-3 reconciliation semantics. Definition only — no code in this round.

Baseline: a209944 (FM-01/02/03 closed). Five state layers:
HTTP/Product ← Execution State ← Representation ← Residency ← Physical MLX.

---

## 1. Turn Transaction Model (the unit of consistency)

One API turn = one transaction. Phases:

```text
P0  acquire lifecycle lock            (await)
P1  continuation judgment             (in-memory)
P2  per-unit cycle ×N:                (await per unit)
      admit(unit) → forward(unit) → [pressure evict if streamed]
P3  project + sample token            (sync, per token)
P4  PHYSICAL COMMIT: bind(N+1)        (in-memory, infallible)
P5  LOGICAL COMMIT: advance → N+1     (in-memory, infallible)
P6  HISTORY + sessionInfo record      (in-memory, infallible)
P7  release lock                      (await)
```

P4–P6 contain NO suspension points: once P4 starts, the section runs to
completion regardless of task cancellation. P4–P6 together are the
**commit section**.

## 2. FM-04 — Cancellation Contract

**Rule: cancellation resolves at phase boundaries only, to exactly one of
ABORT or COMMIT. No half-commit state exists.**

```text
cancellation observed…                        resolution
────────────────────────────────────────────────────────────
before P0 / during P0                     → ABORT   (nothing mutated)
during P2 (between unit cycles)           → ABORT   (position unchanged;
                                                      unit residency is
                                                      mechanics; INV-1
                                                      converges it)
during P3 (between tokens)                → ABORT   (position unchanged)
during P4–P6 (commit section)             → NOT HONORED — the section
                                                      has no await points
                                                      and completes
after P6                                → COMMIT   (turn is durable; the
                                                      client may not have
                                                      received the response;
                                                      retry judgment uses the
                                                      canonical state)
```

Mechanism: cooperative cancellation checked ONLY at the per-token
boundary of P2/P3 (a cancellation token evaluated before each unit
admission and before each token sample). The commit section P4–P6 never
checks cancellation. This yields exactly two outcomes per cancelled turn:

```text
ABORT:  position unchanged; unit residency mechanics converge via INV-1;
        generated partial tokens discarded
COMMIT: turn durable at N+1
```

Registered consequence (GA): streaming a partial response to the client
under ABORT would violate the two-outcome rule; beta serves tokens only
for completed (non-cancelled) turns.

## 3. FM-05 — Cross-Layer Commit Boundary

**The conversation-atomic boundary covers Execution State + Representation
only. Residency and Physical MLX are mechanics layers with their own
consistency proofs — deliberately NOT inside the conversation transaction.**

```text
atomic pair (turn commit):
    Representation binding (N+1)  ← physical, infallible assignment
    Execution State position (N+1) ← logical, infallible advance
    order: physical FIRST, logical SECOND (fail → logical unchanged)

mechanics layer (not in the transaction):
    Residency bookkeeping — INV-1-consistent after EVERY transition
    (admit/evict are individually logged+committed), converges within
    each unit cycle; it is the mechanism by which the atomic pair is
    realized, not a participant in its atomicity.

presentation layer (outside runtime):
    UI transcript — never a restore source (established).
```

Per-layer failure obligations:

```text
layer            failure obligation
Execution State  in-memory operations: infallible by construction;
                 no rollback needed
Representation   bind = single dict write after guard: infallible post-guard
Residency        INV-1 per transition; DIRTY on reconciled divergence;
                 recover() is the registered repair path
Physical MLX     update(verify: []) assignment sequence: all-or-nothing by
                 construction (no throw sites); MLX-internal faults are a
                 vendor-boundary concern (FM-08, registered)
```

## 4. INV-3 — Reconciliation Semantics (consistency-model role)

INV-3 (`|observedIdle − (residentBookkeeping + C_model)| ≤ ε`) is the
**periodic proof** that the Residency bookkeeping still describes physical
reality. It is NOT a transaction participant — it detects silent
divergence (missed eviction, external interference, allocator drift).

Production integration definition (for implementation after review):
- observe after each unit-cycle release (post clearCache),
- calibrated C_model per model class (registered constants; oversized
  engine C_model requires its own calibration pass — GA item),
- divergence → surface as DIRTY through the existing
  respondToMemoryPressure/recover path, never silently ignored.

## 5. FM-09 — reattach obligation (defined while auditing)

reattach makes the logical state active with NO physical precondition
(Execution State ≠ Residency, by definition). The physical obligation is
LAZY and carried by the next forward: per-unit admissions materialize
required units on demand; their failure is a TURN failure (fail-fast) and
never a reattach failure.

## 6. What this contract deliberately does NOT define (GA)

- Floor redesign (floorBudgetMiB disabled; unit-derived floor crash).
- Token ledger integration (usage accounting).
- Cancellable HTTP responses with partial-token COMMIT semantics.
- Concurrent oversized sessions (single-flight contract stands).

---

Review disposition requested: approve/modify D1 (cancellation resolution
table), D2 (atomic-pair vs mechanics-layer boundary), D3 (INV-3 as
detection-not-transaction), D4 (reattach lazy obligation). On approval,
FM-04/FM-05 implementation order: cancellation token plumbing → INV-3
calibration → production reconcile integration.
