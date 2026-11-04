# GA-0 — Floor Residency Policy

Status: FORMALIZED / TARGET-DEPENDENT
Date: 2026-09-27

## Definition

The floor is a Residency policy parameter owned by the engine. It describes which streaming units are admitted with real weights at startup and exempted from normal per-unit streaming eviction through the pressure target.

It is not a memory guarantee, physical observation, or Execution State attribute.

## Ownership

```text
Engine      → derives the floor policy
Controller  → accounts for and enforces the resulting target
Observation → independent physical fact
```

## Floor and C_model

The floor controls the content of residency bookkeeping. C_model calibrates the physical-observation offset. They are independent axes and reconciliation does not recalculate the floor.

## Final policy ruling

GA0_FLOOR_POLICY = TARGET_DEPENDENT

Floor units are not structurally eviction-immune. A target of zero releases non-core residency, including floor units. Only the core residency base is structural.

This preserves target=0 as the unified semantics for clearing non-core residency.

## Execution State separation

Changing floor policy does not change execution identity, lineage, position, or continuation. Floor belongs to Residency policy, not Execution State.

## Current beta

The beta configuration uses floor = 0. Non-zero floor behavior remains a later GA policy surface.