# Gate D Sub-Gate — Concurrency Boundary — Contract

**Date**: 2026-09-27 · **Status**: CONTRACT / DEFINED (reviewer ruling
executed verbatim; implementation planning is the next step — no code
this gate)

**Core principle**: Gate D concurrency correctness protects **physical
operations in flight** — never Bindings; dedup protects **the
materialization WORK of one Ref** — never Executions.

---

## D-C1 — PhysicalUseCount protects physical operations, not Bindings

```text
materialize(Ref X)
   ├─ acquirePhysicalUse(X)
   ├─ read / load / validate / construct materialization
   └─ releasePhysicalUse(X)
```

`PhysicalUseCount > 0` ⇒ eviction candidate must DEFER physical delete.

**Eviction deferred ≠ Artifact pinned** — it only means the current
physical operation has not finished. The Binding Lease (❌ Gate D-I5)
and the Physical Operation Handle (✅ v1) are different things; this
distinction is written into the contract permanently.

## D-C2 — last-live-materialization disappearance is NOT a global event

`live materialization` disappearing ≠ `artifact eviction`:

```text
P live=false, C live=true, artifact available
  → P REATTACHABLE, C ATTACHED_LIVE   (artifact still there)
P live=false, C live=false, artifact unavailable
  → both REMATERIALIZATION_REQUIRED
```

The "last live disappears" observation point is simply one Execution's
Session Registry / materialization state changing; Resolution derives
states at QUERY time. **No global `RefState = NO_LIVE_MATERIALIZATION`**
is introduced — it would reverse-pollute Execution Resolution with
Representation state.

## D-C3..C4 — Ref-scoped single-flight materialization

```text
P ── materialize(Ref X) ─┐
                         ├──→ ONE physical materialization
C ── materialize(Ref X) ─┘     (both wait on the same work)
```

Not two independent full loads.

```text
D-C3  concurrent materialize of the same RepresentationRef uses
      Ref-scoped single-flight
D-C4  single-flight is a performance/resource-correctness mechanism,
      NOT Binding semantics — both Executions keep their own Bindings;
      MaterializationKey = canonical RepresentationRef, NEVER
      ExecutionID (Execution identity ≠ Materialization work identity)
```

## D-C5 — single-flight success ≠ automatic attachment

After the work completes: candidate materialization → P attachment and
C attachment are SEPARATE commit boundaries. Each Execution enters
ATTACHED_LIVE only through its own attachment/commit. Otherwise one
Execution's failure could pollute the other.

## D-C6 — eviction × single-flight race (the implementation-boundary race)

```text
T1: P requests materialize(X)
T2: C requests materialize(X)
T3: Pool eviction(X)
  if T1 acquired protection, T2 joined → T3 DEFERS physical delete
  after work completes and release(X) → X re-enters eviction eligibility
```

**The single-flight WORK itself must hold the transient physical-use
protection** — not caller-acquire/caller-release (which would let the
second joiner or an async materialization lifecycle escape protection).

## D-C7 — failure path

```text
MaterializationWork fails (corrupt / incompatible / hash mismatch)
  → candidate rejected
  → artifact isolate/invalidate
  → Binding(P) active, Binding(C) active   (unchanged)
  → each resolution → REMATERIALIZATION_REQUIRED
NEVER: materialize failure → Binding.detach()
```

## Ownership (final)

```text
Binding Registry                                → Execution → Ref
                                                semantic relations
PrefixPool / ArtifactStore                      → Artifact eviction /
                                                residency
RepresentationResolver + Materialization        → availability /
Coordinator                                        physical-use
                                                   protection /
                                                   single-flight
```

Gate C's `available()` remains read-only and cheap — it does not touch
the transient counter.

## Implementation planning (next step; three questions only)

1. Which layer of `ExecutionStatePrefixPool` carries
   `PhysicalUseCount`;
2. Which layer carries the Ref-scoped single-flight;
3. How `PrefixSnapshotStore` rescan / eviction / load integrate WITHOUT
   breaking the passed P2 eviction-persistence semantics.

Only after these three answers does FORK-3 actual code work begin.
