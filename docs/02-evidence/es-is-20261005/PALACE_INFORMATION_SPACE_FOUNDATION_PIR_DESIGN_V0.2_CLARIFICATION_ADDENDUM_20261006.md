# PIR Design v0.2 — Clarification Addendum

> **Status:** CLARIFICATION ADDENDUM DELIVERED FOR HUMAN REVIEW — IMPLEMENTATION / EXPERIMENT NOT AUTHORIZED
> **Date:** 2026-10-06
> **Clarifies:** PIR Design v0.2 at `ce10827`
> **Review basis:** Human CONDITIONAL PASS ruling
> **Revision type:** definitional/measurement clarification only; no architecture change

## 1. Effect

This addendum does not replace PIR Design v0.2. It locks the five definitions
required by the Human review and must be read together with v0.2.

PIR v0.2 remains CONDITIONAL PASS until this addendum is accepted.

## 2. F1 — Query Scope has two components

`Query Scope` is not only a set of already-known objects. It is a composite,
auditable control object for one request.

```text
Query Scope
├── Information Scope
│     known registered Information / Identity / Closure references that may
│     affect the request.
|
└── Physical Scope
      the declared physical observation boundary used to discover create,
      move, rename, or otherwise unregistered relevant objects.
```

`Information Scope` answers:

```text
Which already registered objects must be checked?
```

`Physical Scope` answers:

```text
Where may lawful physical observation look for new, moved, renamed, or
otherwise unknown relevant objects?
```

Example shape:

```text
Information Scope:
  registered project/cost objects, relevant session records, and related
  artifact references.

Physical Scope:
  declared project directory roots;
  declared file-class filters;
  declared relevant session roots;
  explicit depth/boundary and exclusion rules.
```

`CREATED_UNREGISTERED` is valid only for objects found inside the declared
`Physical Scope`. Objects outside that scope are not claimed as discovered and
do not make the reconciliation incomplete for this query.

Physical discovery remains bounded:

```text
no global filesystem scan;
no watching;
no unrestricted recursive search;
only pre-declared roots/filters/exclusions;
typed result for every accepted physical candidate.
```

## 3. F2 — Scope Resolution and Reconciliation are separate measurements

ICAC measurement must separate:

```text
A. Scope Resolution
   N / existing Information Space → candidates → accepted Query Scope

B. Physical Reconciliation
   accepted Query Scope → physical checks → Fresh Closure
```

Required stage decomposition:

```text
S0  request/policy load
S1  Information Scope Resolution from existing IS
S2  Physical Scope Resolution and bounded physical candidate discovery
S3  Candidate Retrieval / accepted-scope assembly
S4  Physical Reconciliation checks
S5  IS update records, if separately authorized
S6  Fresh Closure reconstruction
```

The future `N=10,000 / R=20 / M=5` shape must be interpreted as:

```text
N  total registered Information objects before query;
R  accepted Information Scope size;
M  relevant physical changes within the accepted/relevant scope;
P  bounded physical candidates exposed by the declared Physical Scope.
```

The experiment must report Scope Resolution and Physical Reconciliation
separately. It must not hand an oracle-known relevant set directly to
reconciliation and call the result Scope Resolution.

For evaluation only, a ground-truth oracle may know the planted relevant set,
but that oracle must not be an input to the lawfully measured reconciliation
path.

## 4. F3 — ICAC is a cost vector, not a scalar

The prior formula is retained only as a decomposition of concerns:

```text
ICAC decomposition concerns =
    Scope Resolution
  + Candidate Retrieval
  + Physical Reconciliation
  + IS Update
  + Closure Reconstruction
```

It must not be computed as a single dimensionless scalar by adding
milliseconds, object counts, bytes, syscalls, and update counts.

Required ICAC vector:

```json
{
  "latency_ms": {
    "scope_resolution": 0,
    "candidate_retrieval": 0,
    "physical_reconciliation": 0,
    "is_update": 0,
    "closure_reconstruction": 0
  },
  "objects": {
    "total_registered_n": 0,
    "index_candidates": 0,
    "information_scope_accepted": 0,
    "physical_candidates": 0,
    "physical_checks": 0,
    "changed_found": 0,
    "closure_references": 0
  },
  "bytes": {
    "payload_bytes_read": 0,
    "digest_bytes_read": 0
  },
  "syscalls": {
    "stat": 0,
    "open": 0,
    "read": 0
  },
  "updates": {
    "is_update_records": 0
  },
  "blockers": {
    "typed_blocker_count": 0
  }
}
```

Only same-unit values may be summed, such as `latency_ms` subfields. Other
dimensions remain separate.

A `Weighted ICAC` scalar is forbidden unless a later, pre-registered review
defines units, normalization, and weights.

## 5. F4 — Freshness Window has two independent meanings

The ambiguous symbol `W` is split.

### A. Freshness Age Window — `W_age`

```text
physical_observation_age <= W_age
```

This bounds how far the accepted Information observation may lag the physical
world.

### B. Reconciliation Latency Budget — `W_latency`

```text
query_receipt → Fresh Closure available <= W_latency
```

This bounds how quickly SimiGo must make a usable Fresh Closure available to
Execution State.

The two windows are independent. A result must report both and may pass one
while failing the other.

The future experiment shape therefore becomes:

```text
N         = 10,000 registered Information objects
R         = 20 accepted Information Scope objects
M         = 5 relevant physical changes
P         = bounded Physical Scope candidates
W_age     = pre-registered freshness age window
W_latency = pre-registered query-to-fresh-closure latency budget
```

No value is commissioned.

## 6. F5 — HOT/COLD is request-relative

HOT/COLD is not a permanent object property.

```text
HOT = required by the effective Query Scope for the current request.
COLD = not required by the effective Query Scope for the current request.
```

Historical Information is not inherently COLD. If the user asks about historical
change, historical Information enters the HOT query path.

Age, recency, media type, and storage location may inform candidate ranking but
do not by themselves determine HOT/COLD. The effective scope decision must be
recorded per query.

## 7. Resulting review object

The current review object is:

```text
PIR Design v0.2
+ this Clarification Addendum
```

If accepted, the next separate artifact is a Minimal PIR Probe Design.

That later design must still require:

```text
Human design review;
explicit experiment authorization;
separate fixture authorization;
implementation authorization;
and no user-file mutation.
```

This addendum commissions none of them.
