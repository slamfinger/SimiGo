# Track B Architecture Constraints — 2026-09-22

**Status**: ARCHIVE ARCHITECTURE MAPPING  
**Scope**: Track B — Execution State Lifecycle  
**Repository**: `slamfinger/SimiGo-Lab`  
**Branch**: `refactor/research-archive-20260922`

## 1. Purpose

This document maps the already-closed Track B findings and decisions into
**architecture consequences, interface boundaries, and bounded invariants**.

It is an archive-level architecture mapping. It is **not** a new Architecture
2.0 implementation specification, not a production API proposal, and not a
new research decision.

The existing direction document remains unchanged:

`docs/architecture/ARCHITECTURE_2.0_PRERESEARCH_20260920.md`

No Track B asset is moved, renamed, rewritten, or reopened by this mapping.

**Research-gate effect: NONE.**

- `RESEARCH_STATE.md` is unchanged.
- Definition / Opening STEP ④ estimand remains NOT STARTED.
- No new measurement is authorized.
- Track B remains CLOSED / FROZEN.
- Residency remains a separate future research line.

---

## 2. Architecture mapping rule

The mapping uses four distinct layers:

```
Finding / Decision
      ↓
Architecture consequence
      ↓
Interface boundary / invariant
      ↓
Scope + exclusion
```

A consequence is treated as an **architecture constraint** only where the
closed Track B evidence supports it within its stated test boundary.

Nothing here should be read as proof that the corresponding mechanism is
implemented in the production runtime.

---

## 3. Constraint register

| ID | Finding / Decision | Architecture consequence | Invariant / interface boundary | Scope | Explicit exclusion |
|---|---|---|---|---|---|
| TB-ARC-001 | TB-FND-001; TB-DEC-002 | Execution state must preserve enough identity and state ownership to continue a forked child without changing the parent's continuation. | **Parent continuation invariant**: child execution must not mutate the parent's continuation position or owned state. | Tested hybrid execution-state lifecycle. | Not a universal runtime correctness guarantee. |
| TB-ARC-002 | TB-FND-001, TB-FND-003; TB-DEC-002 | Fork semantics cannot be defined as one generic tensor-copy operation for the tested hybrid model. Component-specific fork semantics are required. | **Component fork-semantics boundary**: attention KV and GDN may use different sharing/isolation mechanisms while presenting one execution-state lifecycle. | Tested Qwen3.5 MoE hybrid layout. | Not a universal rule for all hybrid architectures. |
| TB-ARC-003 | TB-FND-002; TB-DEC-001/003 | Attention history should be representable independently from the private continuation suffix. | **Segment ownership invariant**: historical shared segments remain immutable; each child owns a disjoint append region/suffix. | Tested segment-table/COW prototype. | Does not establish an official paged-KV storage API. |
| TB-ARC-004 | TB-FND-003; TB-DEC-002 | GDN recursive state requires reference-fork semantics rather than token-depth trimming in the tested lifecycle. | **Functional-state fork invariant**: a reference-forked GDN state must remain isolated under the tested functional-update semantics. | Tested GDN state representation. | Does not generalize to arbitrary mutable recurrent state. |
| TB-ARC-005 | TB-FND-004; TB-DEC-005 | Representation transition must be explicit and semantically preserving rather than an implicit change of execution identity. | **Representation equivalence invariant**: segmented/shared → continuous transition preserves execution identity, state values, and continuation semantics within the tested lifecycle. | F5-1/F5-2 tested reattach path. | Does not establish that reattach is always beneficial. |
| TB-ARC-006 | TB-FND-004/005; TB-DEC-004/005 | Migration/reattach has a distinct one-time cost and must be accounted for separately from steady-state decode. | **Migration-cost accounting boundary**: materialization cost is not folded into steady-state performance claims. | Tested Track B representation transitions. | No universal break-even threshold. |
| TB-ARC-007 | TB-FND-006; TB-DEC-006/007 | Transition policy should observe runtime evidence rather than encode unstable depth/segment observations as fixed universal thresholds. | **Adaptive-policy boundary**: policy inputs are observations/estimates; policy output is a transition decision, not a correctness authority. | Tested 64K@S4 prototype/live validation. | Estimator robustness is not closed; no production tuning commitment. |
| TB-ARC-008 | TB-FND-007; TB-DEC-008 | Discard must be modeled as a lifecycle operation on the child, not as adoption of child continuation state by the parent. | **Discard-parent preservation invariant**: discarding a child leaves the parent at its own pre-fork continuation state. | Final Closure v4 lifecycle semantics. | No performance/residency implication. |
| TB-ARC-009 | TB-FND-008; TB-DEC-008 | Execution identity must survive tested representation migration and branch lifecycle operations. | **Execution identity invariant**: representation changes do not silently create a new logical execution or alter its continuation identity. | Frozen Track B lifecycle proposition. | Physical residency transition is outside Track B closure. |
| TB-ARC-010 | TB-FND-001/008; TB-DEC-008 | Execution State should be treated as a higher-level abstraction over component representations, rather than exposing storage layout as the lifecycle contract. | **Lifecycle/storage separation**: Fork, Continue, Reattach, and Discard are lifecycle semantics; Page/Segment/Continuous are representation mechanisms. | Architecture consequence synthesized from frozen Track B scope. | Not a production API specification and not a claim that this abstraction is implemented. |

---

## 4. Proposed interface boundary (research-derived, not production API)

The closed Track B evidence supports the following **conceptual** boundary:

```
ExecutionState
├── identity
├── continuation position
├── component states
│   ├── attention KV representation
│   │   └── shared segments + private append regions
│   └── GDN representation
│       └── reference-forked functional state
└── lifecycle operations
    ├── fork
    ├── continue
    ├── reattach / materialize
    └── discard
```

The important architectural separation is:

```
Lifecycle semantics
        ≠
Physical representation
        ≠
Residency location
```

In particular:

- `fork` describes logical derivation of an execution state.
- `reattach/materialize` describes a representation transition.
- Page/segment/continuous forms describe storage representation.
- Residency describes physical location and remains outside Track B closure.

This boundary is an **architecture consequence for future design work**, not an
implementation authorization.

---

## 5. Invariants to carry forward

The following invariants are the durable architecture inputs extracted from the
closed Track B lifecycle:

### I-01 — Parent continuation preservation

A child may advance independently; child execution must not advance or mutate
the parent's continuation.

**Source**: TB-FND-001, TB-FND-007; TB-DEC-002, TB-DEC-008.

### I-02 — Child isolation

A forked child may acquire private state, but private writes must not alter
shared historical state visible to the parent or sibling branches.

**Source**: TB-FND-001/003; TB-DEC-002/003.

### I-03 — Disjoint append ownership

For attention KV, each branch's newly appended region must have unambiguous
ownership. Shared historical segments remain read-only to the branch.

**Source**: TB-FND-002/003.

### I-04 — Functional-state reference-fork isolation

Where a component is reference-forked under functional update semantics, the
logical states must remain isolated even when storage is initially shared.

**Source**: TB-FND-003.

### I-05 — Representation transition semantic equivalence

A representation transition may change physical layout, but must preserve
logical execution identity, state values, and continuation semantics within
the supported lifecycle.

**Source**: TB-FND-004/008; TB-DEC-005/008.

### I-06 — Discard is non-adoption

Discarding a child removes the child branch; it does not replace the parent's
continuation with the child's continuation.

**Source**: TB-FND-007; TB-DEC-008.

### I-07 — Migration cost is separately observable

One-time materialization/reattach cost must remain distinguishable from
steady-state execution cost.

**Source**: TB-FND-004/005; TB-DEC-004/005.

### I-08 — Adaptive policy is non-authoritative

The tested adaptive policy is an optimization mechanism operating on observed
estimates. It must not become the authority for semantic correctness.

**Source**: TB-FND-006; TB-DEC-006/007.

---

## 6. Relationship to Architecture 2.0 prerearch

The existing Architecture 2.0 document identifies Execution State as the first
research track and describes fork/COW, continuation, migration, and lifecycle
semantics as the research direction.

This mapping does **not** revise that direction document. Instead, it adds a
provenance bridge:

```
Track B evidence
  → bounded findings
  → frozen decisions
  → architecture consequences
  → durable invariants
```

The distinction is intentional:

- `ARCHITECTURE_2.0_PRERESEARCH_20260920.md` remains the strategic/forward
  direction document.
- This document records what the closed Track B evidence now constrains in
  future architecture work.
- Neither document establishes production implementation or release readiness.

---

## 7. Explicit non-claims

Track B architecture mapping does **not** establish:

1. general performance superiority;
2. universal estimator robustness;
3. general residency behavior;
4. production API stability;
5. correctness for arbitrary models, runtimes, concurrency modes, or
   hardware;
6. a universal migration break-even threshold;
7. that the tested adaptive policy parameters are production-optimal;
8. that paged KV storage itself should be reimplemented in SimiGo;
9. that Architecture 2.0 is ready for implementation or release.

The Track B closure boundary remains controlling.

---

## 8. Provenance

Primary archive sources:

- `docs/03-findings/TRACK_B_EVIDENCE_TO_FINDINGS_MAP_20260922.md`
- `docs/04-decisions/TRACK_B_DECISION_REGISTER_20260922.md`
- `trackB-execution-state/TRACK_B_CLOSURE_RESULTS_20260921.md`

Strategic architecture context:

- `docs/architecture/ARCHITECTURE_2.0_PRERESEARCH_20260920.md`

Historical experiment records remain in their original Track B paths and are
not replaced by this document.

---

## 9. Gate status

- **Track B**: CLOSED / FROZEN.
- **Architecture mapping**: recorded.
- **Production implementation**: not authorized by this document.
- **New measurement**: not authorized.
- **STEP ④ estimand**: NOT STARTED.
- **Residency**: separate future research line.
- **Next archive action**: continue mapping other already-registered research
  assets only where provenance and status are explicit.

