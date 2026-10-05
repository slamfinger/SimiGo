# CCVS-01 — Carrier Candidate & Performance Validation Study Charter

Date: 2026-10-06  
Status: `OPEN / PHASE A DELIVERED / CARRIER-NEUTRAL PRECONSTRUCTION DELIVERED / AWAITING HUMAN REVIEW`
Predecessor: `PICS-01 = ACCEPTED / BOUNDED PASS / CLOSED`  
Active route: `PALACE / INFORMATION SPACE FOUNDATION`  
Frozen Contracts: `UNCHANGED`  
Scope guard: `CANDIDATE DESIGN + INVENTORY + PROTOCOL AUTHORING + CARRIER-NEUTRAL INTERFACE PRECONSTRUCTION ONLY · NO BACKEND-SPECIFIC IMPLEMENTATION · NO OSS INTEGRATION · NO BENCHMARK EXECUTION · NO DATABASE SELECTION · NO MIGRATION · NO LAB REORGANIZATION · NO CONTRACT CHANGE`

## 1. Research object

Study how candidate carrier compositions behave under real Lab-shaped workloads
before selecting an architecture.

The study must compare:

```text
consistency
+ performance
+ interface cost
+ fault recovery
+ operational complexity
```

It must produce a defensible shortlist, not a final database selection.

## 2. Mandatory candidate structure

```text
BASELINE A — MINIMUM COMPONENTS
  The simplest viable carrier capable of representing the registered
  responsibilities. This baseline is mandatory.

CANDIDATE B — RELATIONAL REGISTRY + ENTITY STORE
  Durable relational metadata with external/entity file storage.

CANDIDATE C — CONTENT-ADDRESSED REPRESENTATION + REGISTRY
  Immutable representations with a separate logical registry/index.

CANDIDATE D — SERVER REGISTRY + OBJECT STORE + SEARCH
  Production-shaped multi-component topology.
```

Anti-multi-component bias:

```text
A composition is not superior merely because it has more components.
Baseline A may win if it meets correctness, recovery, and performance bounds
with lower operational complexity.

A more complex candidate must show measured advantage sufficient to justify:
  added deployment cost,
  operational burden,
  failure surface,
  consistency complexity,
  and migration cost.
```

## 3. Required validation dimensions

### 3.1 Consistency dimensions

```text
identity stability
revision succession
locator remapping
historical pin resolution
relation endpoint integrity
representation availability
delete/restore distinction
split/merge lineage
session append ordering
index rebuild equivalence
orphan detection
crash recovery
```

### 3.2 Performance dimensions

```text
P50 / P95 / P99 latency
ingest throughput
lookup throughput
search throughput
relation traversal latency
session append throughput
index rebuild time
crash recovery time
memory footprint
disk amplification
concurrency behavior
startup/open cost
large-file behavior
small-object behavior
```

### 3.3 Interface / operations dimensions

```text
carrier ↔ SimiGo resolution cost
adapter thickness
schema or mapping complexity
deployment component count
backup/restore burden
observability
failure isolation
data-import/export cost
```

## 4. Workload profile

The workload must include:

```text
CREATE
MOVE
RENAME
MODIFY
DELETE
RESTORE
COPY
SPLIT
MERGE
REVISION
HISTORICAL PIN
SEARCH
RELATION
SESSION APPEND
SESSION SUMMARY
REBUILD INDEX
CRASH RECOVERY
ORPHANED-IDENTITY DETECTION
```

Data classes must include:

```text
small UTF-8 documents
medium research documents
large binary/entity files
many small objects
raw session/event streams
summaries and judgments
relation graphs
historical pin sets
```

## 5. Candidate inventory requirements

For each candidate composition, record:

```text
responsibilities covered natively
responsibilities requiring composition
identity mechanism
revision/history mechanism
locator mechanism
relation mechanism
session append mechanism
search/index mechanism
consistency/transaction model
recovery model
deployment footprint
operational complexity
license / maintenance posture
migration burden from Lab evidence
expected interface thickness
```

The inventory must not become a commitment.

## 6. Phases

```text
PHASE A — DESIGN & INVENTORY
  Define topologies, eligibility, workloads, metrics, and protocol.
  Delivered.

PHASE A.5 — CARRIER-NEUTRAL INTERFACE PRECONSTRUCTION
  Build only protocols, DTOs/opaque IDs, dependency-injected composition root,
  fake implementation, conformance suite, benchmark harness, and metrics
  collector.
  Delivered; no backend-specific adapter is included.

PHASE B — PROTOCOL FREEZE
  Human approves benchmark fixtures, success/failure bounds, datasets,
  resource limits, and result classes.

PHASE C — CONTROLLED VALIDATION RUN
  Separate Human authorization required.

PHASE D — SHORTLIST REPORT
  Rank only qualified architectures, not final products.

PHASE E — SEPARATE SELECTION GATE
  Human may choose one candidate architecture for implementation planning.
```

## 7. Required outputs

```text
CCVS-D1 candidate inventory
CCVS-D2 topology definitions
CCVS-D3 workload specification
CCVS-D4 performance metric specification
CCVS-D5 consistency/fault specification
CCVS-D6 benchmark protocol
CCVS-D7 resource and safety limits
CCVS-D8 shortlist criteria
CCVS-D9 carrier-neutral interface package
CCVS-D10 conformance suite
CCVS-D11 benchmark harness and metrics collector
```

Phase A delivery:

```text
PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_PHASEA_DESIGN_20261006.md
```

## 8. Non-goals

```text
No benchmark execution in this phase.
No OSS integration.
No backend-specific adapter implementation.
No schema DDL or storage layout implementation.
No production deployment.
No migration of the Lab estate.
No physical Lab reorganization.
No final database selection.
No claim that a candidate is a complete Information Space.
No Higher-Layer ES↔IS semantic opening.
```

## 9. Decision gate

Phase A ends with Human review of:

```text
candidate inventory,
topology definitions,
workload specification,
metric definitions,
fault/recovery protocol,
resource limits,
and shortlist criteria.
```

Only after explicit Human approval may Phase B freeze the protocol, and only a
later separate authorization may run any benchmark.
