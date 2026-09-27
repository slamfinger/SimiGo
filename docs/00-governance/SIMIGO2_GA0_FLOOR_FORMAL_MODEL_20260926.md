# SimiGo-Lab — GA-0: Floor Formal Model (Design, No Code) — 2026-09-26

Status: GA0_FLOOR_FORMAL_MODEL_REGISTERED / AWAITING_REVIEW
Scope: the eight questions from the work-item review, answered from the
actual implementation (`OversizedSegmentedEngine` + `ResidencyController`).
Definition only — no code changes.

## The eight answers

**1. What does floor describe?**
A load-time residency POLICY parameter: which switch_mlp units load with
real weights at startup and are exempt from per-unit streaming eviction
(protected via the post-forward pressure target `core + floor`, not via
an immovability flag). It does NOT describe a memory guarantee, a
physical observation, or an Execution State attribute.

**2. Who owns floor?**
The ENGINE derives and owns it (load-time parameter: unit chunking +
`floorUnits` derivation from `floorBudgetMiB`). The CONTROLLER reflects
the floor in its bookkeeping after the bootstrap admission (floor units
enter `residentGroupIDs` via a logged load) and ENFORCES it via the
pressure target (`respondToMemoryPressure(targetBytes: floorResidentBytes)`).
Ownership is single: the engine sets it; the controller accounts for it.

**3. Runtime policy or physical fact?**
Runtime policy — a load-time residency decision. It is not derived from
physical observation and is never recalculated from one. (C_model, by
contrast, IS calibrated from physical observation at T0 — the two are
independent axes: policy vs observation offset.)

**4. active / resident / releasable**

```text
active (Execution State)   logical handle: identity/lineage/position/
                           continuation/lifecycle — no memory semantics
resident (Residency)       groups the controller has committed: core +
                           admitted floor units + current streamed unit
releasable (pressure)      resident groups above the pressure target =
                           streamed non-floor units (target=0: everything
                           except core)
physical (MLX wired)       aggregate via observation + C_model; per-group
                           physical residency is NOT directly queried
```

**5. C_model vs floor — independent axes**
C_model calibrates the OBSERVATION offset (T0: observed MLX active − core
bookkeeping). Floor determines the BOOKKEEPING CONTENT (which units count
as resident). INV-3 = |observed − (bookkeeping + C_model)| ≤ ε with
bookkeeping including floor units. Changing floor never changes C_model;
changing C_model never changes floor.

**6. Reconciliation never recalculates floor.**
recover() rebuilds the bookkeeping FROM THE TRANSFER LOG — the log
contains the bootstrap floor admissions, so the rebuilt bookkeeping
retains the floor. The floor parameter is policy state set at load and
unchanged by reconcile. Divergence persistence surfaces as DIRTY/turn
failure, never as a floor recalculation.

**7. target=0 unreleasable base: CORE ONLY (alwaysResident).**
Floor units are regular controller groups — `newSession`'s
`respondToMemoryPressure(targetBytes: 0)` evicts them too (full reset to
the core floor, then re-admission on the next turn bootstrap). So floor
protection is TARGET-DEPENDENT, not structural. To make the floor a
protected structural base, floor units would need `alwaysResident: true`
in the inventory — that is the one code-level decision GA-0 leaves open
(policy choice: structural floor vs target-dependent floor).

**8. Execution State decoupling: YES, by construction.**
floor changes never alter identity/lineage/position/continuation (E4
invariant at segment granularity, O6-verified). `newSession` resets floor
residency and the Execution State TOGETHER by design; a floor change alone
never touches the Execution State.

## The formal model (one paragraph)

Floor = a load-time Residency POLICY parameter owned by the engine: the
prefix of streaming units whose weights are wired at startup and exempt
from per-unit streaming eviction, with the pressure target set to
core + floor. It is not a memory guarantee, not an Execution State
attribute, and not recalculated from observation. C_model is the
independent observation-offset constant calibrated at T0. The atomic pair
(representation binding + logical position) is unaffected by either.

## GA-0 decision required (one policy choice)

```text
floor protection semantics:
  (a) structural — floor units marked alwaysResident in the inventory
      (eviction-immune by controller contract)
  (b) target-dependent — current behavior (floor survives while the
      pressure target ≥ core+floor; target=0 evicts it too)
```

Beta ships (b) with floor=0 (no floor units). GA decides whether the
floor becomes a structural invariant (a) when a non-zero floor is needed.

## Token Ledger (next gate, definition preview)

Scope: a per-execution ledger of confirmed (position, prefix length,
representation payload) triples — strengthening the chain position ↔
prefix ↔ representation ↔ residency with an auditable count. NOT a KV
cache, NOT a scheduler. Minimal implementation = engine-side counters +
report fields; coordinator-level audit trail after review.

---

Artifacts: this document; implementation `OversizedSegmentedEngine.swift`
(floor derivation lines + pressure targets); verified behavior in
`results/o5-sweep/` floor sweeps.
