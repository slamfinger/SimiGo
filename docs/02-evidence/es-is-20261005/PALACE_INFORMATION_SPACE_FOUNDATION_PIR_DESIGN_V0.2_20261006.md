# Physical–Information Reconciliation — v0.2 Design

> **Status:** DESIGN V0.2 + CLARIFICATION ADDENDUM ACCEPTED — MINIMAL PROBE DESIGN COMMISSIONED — IMPLEMENTATION / EXPERIMENT NOT AUTHORIZED
> **Date:** 2026-10-06
> **Supersedes:** PIR Design v0.1, retained as audit input
> **Human direction incorporated:** Query-Priority Reconciliation; two-level freshness priority; ICAC metric direction
> **Immediate predecessor result:** ES-CSP-RUN-01 = PASS — CONTINUATION SUFFICIENT / BOUNDED
> **Scope guard:** design only. No SimiGo code change, no U-A change, no Frozen Contract change, no implementation, no fixture, no experiment, no user-file access or mutation.
> **Review ruling:** `docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_PIR_DESIGN_V0.2_REVIEW_RULING_20261006.md`
> **Clarification addendum:** `docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_PIR_DESIGN_V0.2_CLARIFICATION_ADDENDUM_20261006.md`
> **Acceptance / commission ruling:** `docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_PIR_DESIGN_V0.2_ACCEPTANCE_AND_MINIMAL_PROBE_COMMISSION_20261006.md`

## 1. Core principle

```text
Query-Priority Reconciliation:
Do not synchronize the entire Information Space continuously. When a request
arrives, first resolve the Query Scope, then prioritize physical verification
and update of the objects in that scope that affect the current Information
Closure. Unrelated or low-priority Information may defer reconciliation.
```

Therefore the research question changes from:

```text
Can Information Space synchronize the whole physical world in real time?
```

to:

```text
Given a Query Scope and Freshness Window, can SimiGo restore the information
required by the current request from possibly stale state to executable fresh
state at sufficiently low Information Closure Acquisition Cost?
```

## 2. Query path

### 2.1 Inheritance from v0.1

Unless explicitly modified here, PIR v0.1 remains the inherited basis:

```text
physical change classes      create / modify / delete / move-rename;
freshness policy fields      scope, window, checks, move rule, conflict rule;
freshness verdicts           FRESH / STALE / CHANGED / DELETED / MOVED /
                             CREATED_UNREGISTERED / CONFLICT / INDETERMINATE;
responsibility split         Main Agent/ES, constrained Reconciliation
                             Sub-Agent, passive Information Space, Physical
                             World;
hard boundaries              no business judgment, no user-file mutation, no
                             semantic guess over physical fact, no Execution
                             State expansion.
```

v0.2 adds Query-Priority Reconciliation, logical HOT/COLD priority, auditable
Query Scope, Fresh Closure, and ICAC.

The required conceptual path is:

```text
Query
  → Execution State
  → ① Information Scope Resolution
  → ② Index / Summary candidate narrowing
  → ③ Query-scoped Physical Reconciliation
  → ④ Fresh Information Closure
  → ⑤ Main Agent work
       └── optional deferred background reconciliation
```

The forbidden anti-pattern is:

```text
Query → scan everything → reindex everything → update everything → answer
```

Update cost must be governed primarily by the relevant Query Scope, not by
total Information Space size.

## 3. Layer responsibilities and priorities

| Layer | Responsibility | Priority |
|---|---|---|
| Index | rapidly locate possible candidate objects | highest for query path |
| Summary | narrow candidates to task-relevant objects | highest for query path |
| Identity / Revision | determine whether a registered object may have changed | highest for query path |
| Physical Reconciliation | verify current physical state | highest for query path |
| Relations | supply context needed by the current closure | only when required by scope |
| Other global Information | reconcile deferred stale/unrelated state | background / low priority |
| Full rebuild | exceptional repair only | lowest; not normal query path |

Index and Summary narrow and prioritize. They are not physical facts and cannot
overwrite a typed physical observation or business judgment.

## 4. Two-level Information Space

This is a logical freshness/priority model, not a new backend, schema, store,
or consistency protocol.

```text
                 Information Space
                        |
        +---------------+----------------+
        |                                |
  HOT / QUERY PATH                 COLD / BACKGROUND
  Index                            stale objects
  Summary                          low-priority objects
  Identity                         historical objects
  Revision                         unrelated objects
  scope-relevant Relations         pending deferred reconciliation
        |
        ↓
  Query-Scoped Closure
        |
        ↓
  Main Agent
```

The goal is:

```text
high-priority fresh consistency for information needed by the current
Execution State;

deferred consistency permitted for information not needed by the current
Execution State.
```

This does not weaken U-A carrier guarantees or reinterpret Frozen Contracts.

## 5. Query Scope

A Query Scope is the pre-declared set of objects/closures that may affect the
current request.

It must record:

```text
QS-1  query identifier and request boundary;
QS-2  candidate source: index/summary/exact identifiers;
QS-3  selected relevant objects;
QS-4  excluded objects and exclusion reason class;
QS-5  required freshness checks per object class;
QS-6  relations required for the current closure;
QS-7  freshness window and conflict policy.
```

Scope Resolution must be auditable. If Index or Summary proposes a candidate,
the record must distinguish:

```text
candidate proposed by derived access;
candidate accepted into Query Scope;
candidate physically verified;
candidate rejected or deferred.
```

## 6. Fresh Closure

A Fresh Closure is the smallest lawful closure needed for the current request.

It must contain:

```text
objective/request boundary;
scope-relevant Information references;
current physical reconciliation observations;
identity / revision / provenance;
required relations;
continuation or answer-support boundary;
typed unresolved/conflict items, if any.
```

If any required object cannot be brought to the freshness window, the closure
must carry a typed blocker:

```text
FRESH_WITHIN_WINDOW
STALE_BEYOND_WINDOW
PHYSICALLY_CHANGED
PHYSICALLY_DELETED
PHYSICALLY_MOVED
CREATED_UNREGISTERED
CONFLICT
INDETERMINATE
```

It must not silently use stale or guessed state as fresh.

## 7. ICAC — Information Closure Acquisition Cost

ICAC is the PIR research metric direction.

```text
ICAC =
    Scope Resolution Cost
  + Candidate Retrieval Cost
  + Physical Reconciliation Cost
  + IS Update Cost
  + Closure Reconstruction Cost
```

Candidate cost units:

```text
elapsed time per phase;
number of index candidates inspected;
number of objects accepted into Query Scope;
number of physical checks;
bytes/stat calls/digest checks;
number of IS update records;
closure reconstruction effort;
typed blocker count.
```

Primary research ratio:

```text
Scope-Cost Dependence =
  cost growth as a function of Query Scope size
versus
  cost growth as a function of total Information Space size.
```

The desired PIR property is:

```text
cost primarily depends on Query Scope,
not total Information Space size.
```

## 8. Deferred background reconciliation

Objects outside the current Query Scope may be deferred.

Deferred work must remain:

```text
explicitly recorded;
priority-classified;
provenance-bearing;
non-blocking for the current request;
separately authorized as implementation/research work.
```

Background reconciliation must not silently mutate user files, rewrite history,
or promote guessed state.

## 9. Future minimal experiment shape — NOT COMMISSIONED

A future first experiment may be pre-registered as:

```text
N  = 10,000 Information objects
R  = 20 objects in the current Query Scope
M  = 5 physical changes among those relevant objects
W  = fixed freshness window
P  = query-priority reconciliation only
```

Question:

```text
Can SimiGo discover the actual relevant changes and construct a Fresh Closure
within the declared window, while physical-check cost remains bounded primarily
by R rather than N?
```

Candidate primary checks:

```text
P1  physical checks are bounded by accepted Query Scope plus a declared
    candidate-miss allowance, not by N.
P2  all M relevant changes are represented by typed observations.
P3  all R scope objects receive a freshness verdict.
P4  the Fresh Closure is complete or carries typed blockers.
P5  no unrelated object is updated merely because it exists in IS.
P6  no semantic guess substitutes for a physical check.
```

This is a design-direction experiment shape only. It is not commissioned, not
implemented, and has no fixture or run authorization.

## 10. Hard boundaries

This design does not authorize:

```text
implementation;
experiment;
fixture creation;
filesystem scanning;
continuous synchronization;
filesystem watching;
full rebuild as a normal query path;
new backend/store/schema;
carrier migration;
MemPalace integration;
MCP integration;
remote API use;
user-file mutation;
business judgment by reconciliation;
semantic guessing over physical fact;
U-A, Manifest, UA, PB, InformationCore, RelationCore, or Frozen Contract
change.
```

## 11. Decision requested

This document requests Human review only.

```text
ACCEPT DESIGN V0.2   register Query-Priority Reconciliation and ICAC as the
                     PIR design basis; a separate minimal probe design would
                     then require its own review.
REVISE DESIGN        return with registered defects.
REJECT DESIGN        do not proceed.
```

No implementation or experiment authorization is requested.
