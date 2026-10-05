# CCVS-01 Phase A — Candidate Composition & Validation Design

Date: 2026-10-06  
Status: `DELIVERED / AWAITING HUMAN REVIEW`  
Study: `CCVS-01 — Carrier Candidate & Performance Validation Study`  
Phase: `A / DESIGN & CANDIDATE-INVENTORY`  
Frozen Contracts: `UNCHANGED`  
Scope guard: `DOCUMENTATION ONLY · NO IMPLEMENTATION · NO OSS INTEGRATION · NO BENCHMARK EXECUTION · NO DATABASE SELECTION · NO MIGRATION · NO LAB REORGANIZATION · NO CONTRACT CHANGE`

## 0. Review discipline

The unit of comparison is a runnable architecture composition, not an isolated
product feature.

Therefore no conclusion of this form is valid:

```text
database X has good transactions
+ search Y has good retrieval
+ DAG Z has good history
  ⇒ X + Y + Z is best.
```

Every comparison must evaluate the whole write path, query path, recovery path,
and rebuild path after composition. Integration seams are measured objects.

## 1. CCVS-D1 — Candidate inventory

### 1.1 Component slots

| Slot | Responsibility | Candidate class | Representative OSS examples only, not commitments |
|---|---|---|---|
| R1 Embedded registry | ID, revision, locator, relation, availability records; local transaction. | Embedded relational / transactional KV. | SQLite; SQLite + FTS5; LMDB; RocksDB. |
| R2 Server registry | Durable registry for concurrent writers/readers. | Server relational database. | PostgreSQL; MariaDB; MySQL. |
| E1 Local entity store | Immutable files/objects; digest; size; media type. | Local filesystem or content-addressed file store. | POSIX filesystem; OSTree; Git object model as a substrate reference. |
| E2 Object/entity service | Durable large-object storage and lifecycle. | S3-compatible or distributed file/object service. | MinIO; SeaweedFS; Garage. |
| C1 Content-addressed representation | Immutable representation addressed by digest. | CAS / Merkle store. | Git object model; OSTree; content-addressed filesystem layer. |
| X1 Derived search | Rebuildable metadata/full-text retrieval. | Embedded or service search. | SQLite FTS5; Meilisearch; Typesense; OpenSearch. |

These are inventory entries. No product is selected or excluded here.

### 1.2 Composition eligibility

A candidate composition is eligible only if it can expose one common adapter
surface for all required operations. It must declare:

```text
runtime component list;
process/socket boundary for every seam;
durable acknowledgement point for every write;
transaction boundary;
serialization boundary;
representation-to-registry consistency rule;
locator update rule;
historical pin rule;
availability/tombstone rule;
index rebuild source;
crash recovery boundary;
backup/restore boundary;
adapter code responsibility.
```

A product description without these fields is not a valid candidate.

## 2. CCVS-D2 — Topology definitions

### 2.1 Baseline A — minimum components

```text
ONE local runtime process:
  embedded registry + local entity store + embedded derived index

Representative shape:
  embedded registry (for example SQLite/FTS5 or LMDB)
  + local immutable entity directory/CAS

Runtime component count = 1
Cross-process seams     = 0
Primary transaction     = local registry transaction
Entity durability       = file write + digest check + registry commit
Failure boundary        = process crash / host crash
```

Responsibilities:

```text
Native             = registry, locator, relation, session append, availability,
                     embedded search, local entity durability
Composed           = semantic Information Identity continuity
Not provided       = distributed concurrency, production service isolation
```

### 2.2 Candidate B — relational registry + entity store

```text
TWO runtime components:
  server/embedded relational registry
  + local or service-backed entity store

Representative shape:
  SQLite/PostgreSQL
  + POSIX entity directory or S3-compatible object service

Runtime component count = 1-2
Cross-process seams     = 0-1
Primary transaction     = registry transaction only
Entity transaction      = outbox/manifest or explicit repair protocol
Failure boundary        = registry crash; entity-store crash; seam desynchronization
```

Responsibilities:

```text
Native             = registry, locator, relation, session metadata,
                     availability, explicit revisions
Composed           = entity bytes, digest verification, entity-registry repair,
                     optional search
Not provided       = automatic semantic lineage
```

### 2.3 Candidate C — content-addressed representation + registry

```text
TWO runtime components:
  content-addressed representation store
  + registry/index layer

Representative shape:
  CAS/Merkle object substrate
  + embedded/server registry and derived index

Runtime component count = 2
Cross-process seams     = 1-2
Primary transaction     = registry transaction; representation objects immutable
Entity durability       = CAS write; digest becomes RepresentationID input
Failure boundary        = CAS availability; registry/index divergence
```

Responsibilities:

```text
Native             = immutable representation, digest identity, history substrate,
                     snapshot/pin support
Composed           = logical InformationID, revisions, current locator,
                     relations, availability, session, search
Not provided       = semantic identity continuity
```

### 2.4 Candidate D — server registry + object store + search

```text
THREE runtime components:
  server registry
  + object/entity service
  + derived search service

Representative shape:
  PostgreSQL
  + MinIO/SeaweedFS/Garage
  + Meilisearch/OpenSearch/Typesense

Runtime component count = 3
Cross-process seams     = 3 observed request seams plus ingestion/rebuild seams
Primary transaction     = registry transaction only
Entity/search transaction = explicit synchronization or eventual consistency
Failure boundary        = each service plus every synchronization seam
```

Responsibilities:

```text
Native             = durable registry, object storage, search, concurrent access
Composed           = end-to-end identity consistency, locator update,
                     index freshness, recovery, backup
Not provided       = SimiGo semantic validity or continuation reasoning
```

### 2.5 Composition cost table

| Topology | Components | Seams | Write hops | Write serializations | Query hops | Cross-component transaction | Main recovery boundary |
|---|---:|---:|---:|---:|---:|---|---|
| A | 1 | 0 | 1-2 | 1-2 | 1-2 | none | process/host crash |
| B | 1-2 | 0-1 | 2-3 | 2-3 | 1-2 | usually none; repair protocol required | registry/entity desynchronization |
| C | 2 | 1-2 | 2-4 | 2-4 | 2-3 | usually none; digest linkage required | CAS/registry divergence |
| D | 3 | 3+ | 3-5 | 3-5 | 2-4 | registry only; search/object eventual | service outage or sync lag |

The protocol must measure these costs, not accept the table as proof.

## 3. CCVS-D3 — Workload specification

### 3.1 Scale tiers

| Tier | Information objects | Entity files | Large files | Sessions | Session events | Relation edges | Approx. entity bytes |
|---|---:|---:|---:|---:|---:|---:|---:|
| SMALL | 1,000 | 100 | 10 × 10 MB | 10 | 1,000 | 2,000 | 100 MB |
| MEDIUM | 10,000 | 1,000 | 100 × 10 MB | 100 | 10,000 | 20,000 | 1 GB |
| LARGE | 100,000 | 10,000 | 1,000 × 10 MB | 1,000 | 100,000 | 200,000 | 10 GB |
| STRESS | 1,000,000 | 50,000 | 5,000 × 10 MB | 10,000 | 1,000,000 | 2,000,000 | 50 GB |

Phase B may adjust a number only with a registered reason. A candidate's result
must state its tier; results from different tiers are not comparable.

### 3.2 Required workload families

| Workload | Purpose | Required operations |
|---|---|---|
| WL1 Small-object lifecycle | Metadata, locator, and availability behavior under many small records. | create, move, rename, modify, delete, restore, copy, pin, lookup. |
| WL2 Large-file lifecycle | Entity-store throughput and disk amplification. | create large representation, digest, move, pin, delete-availability, restore. |
| WL3 High-frequency session | Ordered append and summary generation. | append events, periodic summary, attach provenance, historical read. |
| WL4 Relation-heavy graph | Identity-referenced relation traversal. | create endpoints/edges, 1-hop/2-hop/3-hop traversal, successor/predecessor walk, split/merge lineage. |
| WL5 Search and rebuild | Derived-index usefulness and rebuild cost. | ingest, query, update, full rebuild, rebuild-equivalence check. |
| WL6 Mixed research day | Realistic researcher/agent sequence. | create, read, revise, relate, search, summarize, pin, continue. |
| WL7 Fault and recovery | Failure boundary and orphan visibility. | kill at write points, restart, integrity check, repair or explicit detached state. |

Each result must report:

```text
topology ID;
component versions/config hash;
workload family;
scale tier;
deterministic seed;
cold/warm mode;
success/failure/incomplete count;
integrity result;
resource samples;
raw result files.
```

## 4. CCVS-D4 — Performance metric specification

### 4.1 Latency

Latency is client-observed wall-clock time from adapter call start to durable
or user-visible completion. It includes every required serialization, process
hop, and transaction boundary.

Report P50, P95, P99, maximum, count, and error count separately for:

```text
small-object create
small-object lookup
locator move/rename
revision create
historical pin read
availability update
relation insert
1-hop traversal
2-hop traversal
3-hop traversal
search query
session append
session summary read
large-file create/read
startup/open
```

### 4.2 Throughput

Report operations/sec and logical bytes/sec separately:

```text
small-object ingest
entity-file ingest
session-event append
relation ingest
search ingest
large-file read
large-file write
```

Throughput is invalid if errors or silent inconsistencies are excluded.

### 4.3 Resource and amplification

Sample at a fixed interval and report median/P95:

```text
process RSS
total measured component RSS
CPU seconds
physical bytes read
physical bytes written
disk amplification = physical bytes written / logical bytes submitted
open file descriptors
component restart count
```

Disk amplification must be reported for ingest, revision, move/rename, delete,
restore, and index rebuild.

### 4.4 Rebuild and recovery

Report:

```text
full index rebuild duration;
records indexed/sec;
query availability during rebuild;
crash detection time;
restart/open time;
integrity-check time;
repair time or explicit detached-state marking time;
time to lawful continuation readiness.
```

Recovery time does not include Human review time.

## 5. CCVS-D5 — Consistency and fault specification

### 5.1 Invariants

Every topology must pass:

```text
I1  Locator-only move does not change InformationID.
I2  Content modification creates a new representation/revision; it does not
    overwrite historical evidence.
I3  Same path with different digest does not silently preserve identity.
I4  Same digest at a new path is not promoted to identity continuity without
    an explicit rule.
I5  Every relation endpoint remains a stable InformationID, never a path.
I6  Historical pin resolves to exact prior representation/locator/digest.
I7  Delete changes availability, not historical existence.
I8  Restore does not erase the deletion observation.
I9  Split/merge preserves predecessor/successor lineage.
I10 Session events retain order and provenance.
I11 Index rebuild derives an equivalent retrieval view from authority.
I12 Orphaned representation or registry record is visible.
I13 Crash leaves either a complete logical operation or a detectable explicit
    incomplete/detached state.
```

### 5.2 Crash points

Inject restart/crash after each boundary:

```text
F1  after entity/CAS write, before registry commit
F2  after registry commit, before derived index update
F3  after old locator read, before new locator commit
F4  after new locator commit, before old locator archival
F5  during relation batch
F6  during session append
F7  during index rebuild
F8  during backup/export
F9  during restore
```

For each fault point, verify restart behavior and classify:

```text
PASS    complete operation, or incomplete operation explicitly visible
REPAIR  deterministic repair makes all invariants true and records repair fact
DETACHED incomplete operation remains explicitly unavailable, never silently adopted
FAIL    silent identity loss, silent adoption, broken relation, false history
```

## 6. CCVS-D6 — Benchmark protocol

### 6.1 Run preparation

```text
Use an isolated temporary data root.
Never mutate the Lab working tree.
Generate deterministic synthetic fixtures from a declared seed.
Record host CPU, memory, disk type, OS, versions, configs, component hashes.
Record every adapter setting before the first run.
Use the same adapter operation names for all topologies.
```

### 6.2 Run sequence

```text
P0  integrity baseline
P1  cold startup/open
P2  WL1 small-object lifecycle
P3  WL2 large-file lifecycle
P4  WL3 session append/summary
P5  WL4 relation creation/traversal
P6  WL5 search/rebuild
P7  WL6 mixed research day
P8  crash/recovery suites in fresh runs
P9  final integrity check and result export
```

Runs are cold unless declared warm. Warm results may supplement but not replace
cold results.

### 6.3 Repetition

```text
SMALL  = minimum 5 valid runs
MEDIUM = minimum 5 valid runs
LARGE  = minimum 3 valid runs
STRESS = minimum 1 valid run; 2 preferred if resource limits allow
```

A run is invalid if an invariant fails, the harness errors, required resource
samples are missing, or the configuration differs from the declared topology.
Invalid runs are retained and explained.

### 6.4 Fairness rules

```text
No topology may receive workload-specific tuning hidden from others.
All durable writes must be acknowledged at the topology's normal durable point.
No candidate may skip digest verification unless all skip it.
No candidate may use an undeclared cache as authority.
No component may be warmed for one topology and not another.
Every optimization must be part of the declared architecture.
```

## 7. CCVS-D7 — Resource and safety limits

### 7.1 Data safety

```text
Benchmark roots must be outside the Lab working tree.
No Lab file may be moved, renamed, deleted, or rewritten.
No private secret, credential, or unregistered personal data may become a fixture.
Fixtures are synthetic or derived only from registered non-sensitive metadata.
```

### 7.2 Resource gates

Before each run, require:

```text
free disk >= 3 × declared new bytes for the run;
free memory >= 2 × declared maximum resident set;
no other registered benchmark process active;
enough time remaining for the declared timeout plus final integrity check.
```

If a gate fails, stop and record `RESOURCE_GATE_BLOCKED`; do not silently shrink
the tier.

### 7.3 Timeouts

```text
SMALL  = 15 minutes per workload family
MEDIUM = 60 minutes per workload family
LARGE  = 4 hours per workload family
STRESS = 12 hours per full topology sequence
```

A timeout is a result, not a silent retry.

### 7.4 Abort conditions

Stop immediately if:

```text
free disk falls below 20%;
required output files become unwritable;
memory pressure forces registered swap thrashing;
any protected Lab path is affected;
an unrecoverable integrity violation appears;
component logs show data loss without a registered recovery rule.
```

## 8. CCVS-D8 — Shortlist criteria

### 8.1 Hard eligibility gates

All must pass on MEDIUM:

```text
G1  all consistency invariants pass;
G2  every crash point is PASS, REPAIR, or DETACHED — never FAIL;
G3  orphaned identity/mapping is visible;
G4  historical pin resolves;
G5  index rebuild is possible from declared authority;
G6  all required metrics and raw logs are present;
G7  configuration and versions are reproducible;
G8  backup/restore boundary is declared and tested at smoke level.
```

### 8.2 Comparative dimensions

Qualified candidates are compared only as complete compositions:

```text
consistency/fault result;
binding-workload P95/P99;
ingest/session/search/relation throughput;
disk and memory amplification;
write/query hop count;
serialization count;
cross-component synchronization cost;
rebuild/recovery duration;
component count;
adapter thickness;
backup/restore burden;
migration/import-export cost.
```

### 8.3 Anti-complexity rule

If Baseline A passes all hard gates and meets the Phase B performance bounds,
a more complex topology may enter the shortlist only if it demonstrates:

```text
>=30% better P95 on the binding workload, or
>=50% higher durable throughput on the binding workload, or
a required capability that Baseline A cannot provide without breaking a
registered boundary.
```

The complex topology must also show that recovery and consistency do not become
worse. Otherwise Baseline A remains preferred.

### 8.4 Shortlist classes

```text
SHORTLIST-QUALIFIED
  passes G1-G8 and beats or justifies complexity under 8.3.

CONDITIONAL
  passes correctness but lacks LARGE/STRESS evidence; may proceed only to a
  targeted Phase B/C test.

ELIMINATED
  fails a hard gate, loses historical evidence, silently breaks locator/relation
  continuity, or cannot recover within declared bounds.

NOT-COMPARABLE
  missing metrics, changed topology mid-run, or workload tier mismatch.
```

No final database selection is made here.

## 9. Deliverable status

```text
CCVS-D1 candidate inventory                         = DELIVERED
CCVS-D2 topology definitions                        = DELIVERED
CCVS-D3 workload specification                      = DELIVERED
CCVS-D4 performance metric specification            = DELIVERED
CCVS-D5 consistency/fault specification             = DELIVERED
CCVS-D6 benchmark protocol                          = DELIVERED / NOT EXECUTED
CCVS-D7 resource and safety limits                  = DELIVERED
CCVS-D8 shortlist criteria                          = DELIVERED
```

## 10. Next gate

Human must review D1-D8 and choose:

```text
A  ACCEPT PHASE A / PROCEED TO PHASE B PROTOCOL FREEZE
B  REVISE topologies, workloads, metrics, limits, or shortlist rules
C  PARK CCVS-01
D  REJECT and return to another route
```

Phase B still does not execute benchmarks. Phase C requires separate Human
authorization.
