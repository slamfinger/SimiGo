# SRS-REAL-CLOSURE-01 — Database-Carrier Replication Design Package v0.1

> **Status:** DESIGN ONLY — DELIVERED FOR HUMAN REVIEW
> **Date:** 2026-10-07
> **Authorization:** Database-Carrier Replication Design Authorization Record
> 001 @ `e19fa0b`
> **Accepted baseline:** EXEC-006 bounded finding at `feb0a61`
> **Boundary:** design/schema authority and equivalence criteria only. This
> package authorizes no database implementation, initialization, execution,
> IS mutation, campaign, runner/fixture change, or broader claim.

## 1. Purpose and central rule

This package defines a controlled carrier-substitution boundary:

```text
document-form IS
        ↓
database-backed IS
```

The design question is not “how to make a good database.” The design question
is:

> Which IS semantics are carrier-independent, which database operations are
> mandatory to preserve them, and what observable differences force rejection?

Equivalence is the center of this package. A database carrier is admissible
only under the conjunction:

```text
same logical IS
+ same append/order semantics
+ same identities and content addresses
+ same object bytes/hashes
+ same revision semantics
+ same dependency-resolution semantics
+ same detection boundary
+ no extra observable semantic state
        ↓
carrier substitution is admissible
```

Any extra semantic affordance, reordering, hidden state, implicit identity,
implicit revision, eventual visibility, or carrier-specific decision input is
sufficient for rejection.

## 2. Frozen inputs and inherited boundaries

```text
accepted baseline commit = feb0a61f2ed87079c2a9e3572d0e1a3c9f9f0;
authorization record =
  SRS_REAL_CLOSURE_01_DATABASE_CARRIER_REPLICATION_DESIGN_AUTHORIZATION_RECORD_001
  @ e19fa0b9c6193e53b4a7befaf2331f6f1ce4f091;
accepted campaign = EXEC-006-69b2227;
accepted evidence commit = cb365a44c48d4b7b90b4cc2155fcae00d3e01572;
```

Frozen unchanged:

```text
ES semantics;
ES process behavior;
τ contracts;
T-IMPL-01 decision boundary;
observer detection boundary;
E1-E6 and N1 acceptance semantics;
IS logical content and ordering;
write-once object semantics;
append-only index semantics;
LAST-entry dependency resolution semantics.
```

This package does not reinterpret EXEC-006 and does not broaden its bounded
result.

## 3. Canonical carrier-independent IS logical model

The IS is defined by logical state, not by files, tables, rows, database
handles, or storage format.

### 3.1 Object space

An IS object is an immutable byte sequence identified by:

```text
object_id = SHA256(bytes)
```

Required properties:

```text
same bytes ⇒ same object_id;
different bytes ⇒ different object_id;
an existing object_id is never replaced by different bytes;
object bytes are retrievable exactly by object_id;
object creation is write-once;
object bytes have no carrier-visible metadata as semantic state.
```

Known EXEC-006 logical objects are:

```text
D    = 806fffadef09d3ad491d75c6b42738e99626ee1961ed1aecf2d593aefd55980c;
D'   = 8553f52449b67de21021bb50ad6380c455bf686ee2a06cc77ed51e9f30060955;
SRS  = 26025863df8311f536b067718e8c8466fb9dafa7924c629429e6766f2926c3f9;
CR   = 1703f2d664c58d4fe88032b7b3750ab885522c1a5a73e04570be108f7c6bf026.
```

### 3.2 SRS / continuation index

The index is an append-only logical sequence of records:

```text
IndexEntry {
  srs_identity  : string;
  record_object : object_id;
}
```

EXEC-006 logical index order was:

```text
1. srs_identity = 5e01d6ce… → object 26025863…;
2. srs_identity = "CR:CR-ES2-r2" → object 1703f2d6….
```

Required index semantics:

```text
append-only;
no reorder;
no deletion;
no overwrite;
resolution for an ordinary SRS identity follows the first matching entry,
matching the exact document-form runner behavior;
continuation identities remain distinct logical identities and are not
 aliases for SRS identities.
```

### 3.3 Current dependency resolution

The current dependency mapping is an append-only sequence:

```text
DependencyEntry {
  dependency_id  : string;
  content_address: object_id;
  revision       : positive integer;
  reason         : string;
}
```

Resolution is by LAST entry per dependency_id. EXEC-006 logical sequence was:

```text
1. D-1 → 806fffa… / revision 1 / initial materialization;
2. D-1 → 8553f524… / revision 2 / N1 negative-control state advance.
```

Required semantics:

```text
LAST entry per dependency_id is current;
earlier entries remain historical;
revision is explicit and never derived from bytes or row position;
pinned SRS dependency comparison compares explicit content address and
  revision from the SRS against explicit current mapping;
same dependency_id with different address/revision invalidates the pinned
  binding.
```

### 3.4 Logical read operations

The carrier-independent IS exposes only these semantic reads:

```text
read object bytes by exact object_id;
read index records in append order;
resolve ordinary SRS identity by first matching index entry;
resolve current dependency by LAST mapping entry;
verify object bytes by SHA256.
```

No additional semantic read is part of the IS contract.

## 4. Authoritative database-backed interface/schema

The database carrier must expose the same logical operations through an
explicit adapter boundary. The design below is normative at interface and
semantics level; physical SQL may vary only if every listed invariant holds.

### 4.1 Required logical operations

```text
DB.init_empty()
  creates an empty database-backed IS;
  no logical objects, index entries, or dependency mappings;

DB.write_object(bytes)
  computes object_id = SHA256(bytes);
  fails if object_id already exists with different bytes;
  stores bytes so later retrieval returns exactly those bytes;
  returns object_id;

DB.get_object(object_id)
  returns exact stored bytes or NOT_FOUND;

DB.append_index_entry(IndexEntry)
  appends one logical index record;
  preserves append order;
  does not reorder, overwrite, delete, or coalesce;

DB.resolve_srs_identity(srs_identity)
  returns the first matching index entry or NOT_FOUND;

DB.append_dependency_entry(DependencyEntry)
  appends one dependency mapping record;
  does not overwrite earlier history;

DB.resolve_current_dependency(dependency_id)
  returns the LAST mapping entry for dependency_id or NOT_FOUND;
```

### 4.2 Required database tables

A conforming baseline schema is:

```sql
CREATE TABLE is_objects (
  object_id   TEXT PRIMARY KEY,
  byte_size   INTEGER NOT NULL,
  content BLOB NOT NULL,
  created_order INTEGER NOT NULL
);

CREATE TABLE is_index_entries (
  append_order  INTEGER PRIMARY KEY,
  srs_identity  TEXT NOT NULL,
  record_object TEXT NOT NULL REFERENCES is_objects(object_id)
);

CREATE TABLE dependency_entries (
  append_order   INTEGER PRIMARY KEY,
  dependency_id  TEXT NOT NULL,
  content_address TEXT NOT NULL REFERENCES is_objects(object_id),
  revision       INTEGER NOT NULL,
  reason         TEXT NOT NULL
);
```

Required constraints:

```text
is_objects.object_id = lowercase hex SHA256(content);
is_objects.content is immutable after insert;
is_index_entries.append_order is dense or monotonically nondecreasing and
  preserves logical append order;
dependency_entries.append_order preserves append order;
LAST dependency row per dependency_id is current;
no cascade delete;
no trigger rewriting semantics;
no database-generated semantic identity replacing SHA256.
```

Indexes may exist for performance, but they are non-semantic implementation
detail and must not introduce observable ordering or identity semantics.

### 4.3 Transaction and visibility

```text
each logical write sequence shall be atomic;
object insertion, index append, and dependency append that belong to one
  logical operation shall become visible together;
crash before commit leaves no partially visible logical operation;
crash after commit leaves the complete logical operation;
there is no eventual consistency in the campaign boundary.
```

For EXEC-006-equivalent operations:

```text
materialize:
  D object insert + dependency revision-1 insert = one transaction;

ES1:
  SRS object insert + SRS index append = one transaction;

ES2 REUSE continuation:
  continuation object insert + continuation index append = one transaction;

mutate-n1:
  D' object insert + dependency revision-2 append = one transaction.
```

### 4.4 Prohibited database-side semantics

A conforming carrier must not provide:

```text
implicit identity or revision generation as semantic IS state;
automatic ordering that changes logical append order;
case-insensitive identity resolution;
collation-dependent matching;
cascading update/delete;
triggers that alter or derive IS records;
stored procedures containing experiment semantics;
cached views exposed as IS state;
soft-delete rows;
automatic garbage collection of historical entries;
carrier-specific conflict resolution;
eventual consistency;
extra observable tables/views that affect IS decisions;
telemetry or metadata consulted by IS decisions.
```

Such features are not forbidden inside the database engine generally; they are
forbidden as observable semantic inputs to this experiment.

## 5. Document-IS ↔ database-IS mapping

### 5.1 Object mapping

```text
document file:
  is/objects/<object_id>

database row:
  is_objects(object_id, content)

equivalence:
  file bytes == database content bytes;
  SHA256(file bytes) == object_id == database object_id.
```

### 5.2 Index mapping

```text
document:
  is/index.jsonl append order;

database:
  is_index_entries.append_order;

record equivalence:
  srs_identity exact string equality;
  record_object exact object_id equality;
  append order exactly preserved.
```

### 5.3 Dependency mapping

```text
document:
  is/current/dependencies.jsonl append order;

database:
  dependency_entries.append_order;

entry equivalence:
  dependency_id exact string equality;
  content_address exact object_id equality;
  revision exact integer equality;
  reason exact string equality;
  append order exactly preserved;
  current resolution = LAST row per dependency_id.
```

### 5.4 No extra mapping

No database representation may add logical entities not present in the
document IS, such as dependency versions derived from timestamps, carrier row
IDs treated as revisions, database sequence numbers treated as SRS revisions,
or query results treated as additional IS state.

## 6. Carrier equivalence criteria

### 6.1 Observation points

For a future campaign, logical state must be extracted and compared at:

```text
O0 after empty initialization;
O1 after materialize;
O2 after ES1;
O3 after ES2 REUSE and continuation;
O4 after mutate-n1;
O5 after ESN BLOCK.
```

### 6.2 Required equivalence assertions

At each observation point:

```text
EQ-1 object-set equivalence:
      same logical object_ids;
      same object bytes;
      same SHA256 values;

EQ-2 object immutability:
      no object bytes changed after first write;

EQ-3 index equivalence:
      same logical index records;
      same append order;
      same identities and record object addresses;

EQ-4 dependency-history equivalence:
      same dependency entries in append order;
      same dependency_id/content_address/revision/reason values;

EQ-5 current-resolution equivalence:
      LAST entry per dependency_id resolves identically;

EQ-6 read-result equivalence:
      SRS resolution, dependency resolution, object bytes, schema validity,
      and byte hashes match;

EQ-7 decision equivalence:
      ES2 = REUSE and ESN = BLOCK under the frozen decision boundary;

EQ-8 no-extra-observable-state:
      no database-only state participates in decisions, ordering, identity,
      revision, or visibility.
```

### 6.3 Explicit reject conditions

Carrier equivalence is rejected if any of the following occurs:

```text
REJ-1 object bytes or object_id differ;
REJ-2 object history is mutable;
REJ-3 index append order differs;
REJ-4 dependency append order differs;
REJ-5 LAST-entry resolution differs;
REJ-6 revision semantics differ;
REJ-7 SRS identity resolution differs;
REJ-8 continuation identity handling differs;
REJ-9 database adds observable semantic state;
REJ-10 database hides or rewrites historical entries;
REJ-11 eventual visibility changes campaign results;
REJ-12 carrier metadata becomes decision input;
REJ-13 crash/recovery leaves a different logical state;
REJ-14 carrier-specific behavior changes ES2 or ESN decisions.
```

“Same final result” is insufficient. The observable logical path must match.

## 7. Initialization and migration design

### 7.1 Empty initialization

The preferred campaign initialization is:

```text
create empty database-backed IS;
create the three logical stores with no rows;
do not import document files;
allow the authorized campaign materialize step to create the initial logical
  IS state.
```

This preserves the EXEC-006 sequence:

```text
empty IS → materialize D → ES1 settle → ES2 reuse.
```

### 7.2 Optional logical import

A separate design/campaign may define logical import from an exported
document-IS snapshot, but it must be explicit and non-default:

```text
import only logical objects/index entries/dependency entries;
preserve bytes, hashes, identities, and append order;
reject any source object whose hash differs from its name;
reject partial import;
produce an import manifest.
```

Database files, rowids, page images, and engine metadata are not imported as
semantic IS state.

### 7.3 No implicit migration

No implementation may migrate, rewrite, normalize, reconstruct, or “fix” the
logical IS as an unrequested side effect.

## 8. Provenance, audit, and non-goals

### 8.1 Required provenance

A future database campaign must record:

```text
database engine identity/version;
database file/container identity and hash where applicable;
final DDL/schema hash;
logical schema version;
initialization command and manifest;
every SQL/DML operation class;
transaction boundaries;
object/index/dependency observation manifests;
EPR-equivalent exact executable/cwd/argv/process facts;
required artifact existence/hash checks;
ES2/ESN decisions and expected-vs-actual results;
observer-equivalent C1-C4 checks;
failure/rejection taxonomy.
```

### 8.2 Anti-side-channel requirements

The database must not become a hidden semantic side channel:

```text
no experiment decision may read undocumented carrier metadata;
no state may persist outside the declared database plus audit artifacts;
no previous campaign database may be reused;
no trigger/procedure may inject SRS, dependency, revision, or continuation
  data;
no observer may rely on private database logs unavailable to exact evidence.
```

The future campaign must distinguish:

```text
carrier storage;
carrier implementation metadata;
semantic IS state;
audit evidence.
```

Only semantic IS state and declared audit evidence may affect results.

### 8.3 Non-goals

This design excludes:

```text
PALACE integration;
production SimiGo integration;
LLM autonomy;
multi-carrier federation;
distributed database consensus;
performance optimization;
concurrency stress testing;
production backup/restore certification;
general database abstraction;
claim that SQLite proves all database carriers;
claim that database equivalence establishes broader Execution State theory;
reinterpretation of EXEC-006.
```

## 9. Failure and rejection taxonomy

```text
SCHEMA_AUTHORITY_MISMATCH
OBJECT_ID_MISMATCH
OBJECT_BYTE_MISMATCH
OBJECT_IMMUTABILITY_VIOLATION
INDEX_ORDER_MISMATCH
INDEX_IDENTITY_MISMATCH
INDEX_OBJECT_ADDRESS_MISMATCH
DEPENDENCY_ORDER_MISMATCH
DEPENDENCY_IDENTITY_MISMATCH
DEPENDENCY_REVISION_MISMATCH
DEPENDENCY_REASON_MISMATCH
CURRENT_RESOLUTION_MISMATCH
SRS_RESOLUTION_MISMATCH
TRANSACTION_VISIBILITY_MISMATCH
EXTRA_OBSERVABLE_STATE
CARRIER_METADATA_AS_DECISION_INPUT
CRASH_RECOVERY_STATE_MISMATCH
EPR004_PROVENANCE_MISMATCH
OBSERVER_C1_C4_MISMATCH
```

Any of these causes carrier equivalence rejection and campaign INVALID.

## 10. Deliverable boundary

This package is design only. It does not authorize:

```text
SQLite implementation;
database creation;
schema initialization;
campaign execution;
IS mutation;
observer execution;
runner/fixture/τ modification;
new execution Request/records;
broadening the accepted finding.
```

Implementation or campaign requires a new explicit Human authorization
exact-binding this design, the post-alignment implementation commit, and all
carrier/runtime provenance.

## 11. Human decision requested

```text
ACCEPT DESIGN PACKAGE v0.1
      accept this carrier-independent IS model, database-backed interface
      requirements, equivalence criteria, initialization design, and
      non-goals; stop before implementation.

REVISE PACKAGE
      return with registered defects.

DENY / STOP
      do not proceed to database-carrier implementation or campaign.
```
