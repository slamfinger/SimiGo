# PICS-01 — Carrier Component Study

Date: 2026-10-06  
Status: `ACCEPTED / BOUNDED PASS / CLOSED`
Charter status: `ACCEPTED / COMMISSIONED`  
Seam: `IS-IDLOC-SEAM-01 / v0.1`  
Frozen Contracts: `UNCHANGED`  
Scope: `DOCUMENTATION-ONLY · NO IMPLEMENTATION · NO OSS INTEGRATION · NO BACKEND SELECTION · NO DATABASE SCHEMA · NO EXPERIMENT`

## 1. Study question

For real files and real sessions, which carrier responsibilities and mature
system-class mechanisms can form a minimal physical substrate for Information
Space, while keeping SimiGo semantic responsibility separate?

This study does not select a database, product, schema, or implementation.

## 2. D1 — Responsibility ownership matrix

| Responsibility | Physical carrier may own | SimiGo / higher layer owns | Boundary |
|---|---|---|---|
| CCS-C1 Entity Representation Store | Immutable bytes/files/objects; digest; size; media type. | Meaning, applicability, membership. | Carrier stores representations; it does not decide what they mean. |
| CCS-C2 Information Registry | Durable registry records for IDs, revisions, representations, provenance timestamps. | Semantic Information Identity and identity-continuity rules. | Registry can persist identities; it cannot infer semantic continuity. |
| CCS-C3 Locator / File Index | Current and historical ID → representation → locator mappings. | Whether a representation is semantically applicable. | Moving a locator does not imply semantic change; content change does not imply identity continuity. |
| CCS-C4 Relation / History | Persist relation events and historical links. | Which semantic lineage predicates are valid and when. | Carrier stores lineage facts; SimiGo interprets lineage. |
| CCS-C5 Session Information | Append raw events; persist summaries and decisions as information objects. | Session interpretation, judgment, and continuation relevance. | Session storage is not session understanding. |
| CCS-C6 Derived Index / Search | Rebuildable index and retrieval structures. | Authority, validity, and admissibility. | Search is navigation, not authority. |
| CCS-C7 Availability / Access State | Existence, archived/detached/unavailable/restored state. | Information-space membership and ES accessibility. | Representation absence does not imply Information nonexistence. |
| CCS-C8 Execution Interface | Expose what can be resolved, consumed, produced, pinned, or continued. | IPAC, applicability, validity, judgment, continuation reasoning. | Carrier ↔ SimiGo interface, not carrier-native execution semantics. |

## 3. D2 — System-class capability mapping

| System class | Strong fit | Partial fit | Weak fit / risk |
|---|---|---|---|
| Embedded relational SQL | Registry, locator mappings, relations, transactions, small/local estates. | Session metadata; limited history through explicit revisions. | Large entity files; distributed concurrency; production operation. |
| Server relational SQL | Registry, locator, relations, session metadata, consistency. | Entity blobs; schema evolution; semantic history. | Large files should usually remain external; operational complexity. |
| KV / document store | Flexible registry records; scalable metadata; locator mappings. | Relations when modeled explicitly; append events. | Relational integrity and query power depend heavily on design. |
| Git / DAG | Immutable blobs; commit/tree snapshots; historical pins; diff/lineage substrate. | Content-addressed representations; branch history. | Mutable registry/current locator; high-frequency session append; large binary efficiency. |
| Object / file storage | Entity files, large blobs, durable physical locations, lifecycle controls. | Versioning and immutability depending on implementation. | Native registry, relations, semantic history, and query are usually absent. |
| Graph database | Relation traversal and graph-shaped lineage queries. | Registry and locator mappings as nodes/properties. | Large entity storage; general history and rebuildability are not automatic. |
| Search index | Derived retrieval and navigation. | Rebuildable projections. | It must never become semantic authority; it can lag or drift. |

No class is sufficient alone for all responsibilities.

## 4. D3 — Candidate OSS/component inventory

These are reference components, not selected backends.

| Reference | Useful mechanism | Carrier lesson |
|---|---|---|
| Nextcloud file cache | Stable `fileid` separate from path; storage/path metadata; identity-to-mount migration concerns. | Entity identity and locator need explicit remapping across backend changes. |
| Git | Immutable blobs, trees, commits; snapshot history; path-to-object mapping. | Good representation/history substrate, not a complete mutable registry. |
| DVC | Content-addressed cache separated from workspace paths. | Content addressing supports representation integrity, not semantic Information Identity. |
| Noms | Immutable Merkle DAG values; datasets as named pointers; retained history. | Logical pointers can decouple names from immutable values. |
| lakeFS | Logical paths over object-store physical paths; commits as immutable checkpoints. | Logical-address ↔ physical-address indirection can support versioned estates. |

Other products may be added later only as inventory, not as commitment.

## 5. D4 — Integration seam map

```text
S1 Physical event ingestion
   filesystem/Git/object event
     → candidate logical consequence
     → registry / locator / relation update proposal

S2 Representation lifecycle
   create / modify / delete / restore
     → RepresentationID + digest + availability state

S3 Locator remapping
   move / rename / archive
     → locator update
     → InformationID unchanged under explicit identity continuity rule

S4 Revision / lineage
   predecessor / successor / derived-from / split-from / merged-from
     → relation/history layer

S5 Session ingestion
   raw session / event / summary / decision
     → information objects with provenance

S6 Derived index
   registry + representation + relation
     → rebuildable search/navigation projection

S7 Recovery
   crash / partial operation / orphaned mapping
     → invariant check + repair or explicit detached state

S8 Carrier ↔ SimiGo interface
   resolve / consume / produce / pin / continue
     → CCS-C8 interface boundary, not storage-side semantic execution
```

## 6. D5 — Workload / observation matrix

| Operation | Required observation | Logical risk |
|---|---|---|
| CREATE | New representation, digest, provenance, initial locator. | Treating creation path as permanent identity. |
| MOVE | Same digest/representation, changed locator, identity continuity decision. | Rewriting all relations because path changed. |
| RENAME | Locator/name change; semantic continuity not inferred from Git rename score. | Same filename ≠ same Information. |
| MODIFY | New revision/representation; predecessor link; old pin retained. | Treating update as destructive replacement. |
| DELETE | Representation unavailable; historical Information and pin remain. | Deleting file and deleting logical fact. |
| RESTORE | New/current availability state; historical gap remains visible. | Making rollback erase observation history. |
| COPY | Same digest may yield multiple representation references; identity decision required. | Treating all copies as independent Information by default. |
| SPLIT | Multiple successors; explicit derived-from/split-from lineage. | Losing relation context. |
| MERGE | Multiple predecessors; explicit merged-from lineage. | Collapsing source identities. |
| REVISION | Immutable old representation plus successor link. | Overwriting evidence. |
| HISTORICAL PIN | Exact commit/digest/path or carrier object recoverable. | Current locator replacing historical locator. |
| SEARCH | Rebuildable retrieval result. | Search result becoming authority. |
| RELATION | Endpoint identities remain stable across locator changes. | Relations pointing to paths. |
| SESSION APPEND | Ordered, provenance-bearing events. | Losing raw trace behind summary. |
| SESSION SUMMARY | Derived object linked to raw/events. | Summary replacing raw evidence. |
| REBUILD INDEX | Same logical state produces compatible retrieval view. | Index drift becoming truth. |
| CRASH RECOVERY | No silent partial identity/locator update. | Orphan representations or broken mappings. |
| ORPHANED-IDENTITY DETECTION | Missing locator/mapping is visible. | Silent identity loss. |

## 7. D6 — Minimal composition options

### Option A — Embedded registry + entity file store + derived index

```text
embedded relational/transactional registry
  + local/entity file or object store
  + rebuildable search index
```

Strengths:

```text
lowest local operational complexity;
clear separation of bytes and metadata;
suitable for a validation estate.
```

Risks:

```text
limited concurrent/server-scale operation;
external entity-file lifecycle must be observed carefully;
backup/recovery protocol is mandatory.
```

### Option B — Server registry + object/entity storage + search index

```text
server relational or transactional registry
  + object/file storage
  + derived search
```

Strengths:

```text
better concurrency and durability;
natural separation of large entities from metadata;
clearer production-shaped boundary.
```

Risks:

```text
higher operational complexity;
identity/location migration across backend changes must be explicit;
more failure modes in distributed seams.
```

### Option C — Content-addressed representation layer + registry/index

```text
content-addressed/DAG representation store
  + durable registry
  + locator/index layer
```

Strengths:

```text
strong representation integrity;
natural immutable history;
good historical pins and snapshots.
```

Risks:

```text
still requires a mutable logical registry;
content hash is not semantic Information Identity;
session append and current-locator management may be awkward.
```

No option is selected.

## 8. D7 — Validation protocol design

### 8.1 Fixture classes

```text
F1 small UTF-8 research documents
F2 renamed/moved document set
F3 modified document lineage
F4 binary/large entity file
F5 raw session + events + summaries
F6 relation graph with citations and lineage
F7 historical pin set
F8 crash/partial-operation fixtures
```

### 8.2 Required checks

```text
identity stability under locator-only move
new representation under content modification
historical pin resolves to exact prior state
relations follow IDs, not paths
delete produces availability change, not logical erasure
split/merge retain predecessor/successor facts
index can be rebuilt from authoritative substrate
orphaned identity/mapping is visible
crash leaves no silent partial logical update
CCS-C8 exposes access without executing semantic judgment
```

### 8.3 Result classes

```text
PASS
  operation produces the registered logical consequence without semantic leakage.

FAIL
  identity, locator, history, availability, or relation invariant is broken.

INDETERMINATE
  result depends on an undefined semantic continuity or membership rule.
```

### 8.4 Execution boundary

A future validation run requires separate Human authorization. This document
only designs the protocol.

## 9. D8 — Gap / no-go register

| ID | Finding | Consequence |
|---|---|---|
| PICS-GAP-01 | Semantic Information Identity continuity is still undefined. | No carrier may be declared a complete Information Space by substrate alone. |
| PICS-GAP-02 | Current `InformationID` is formed-fact/representation-leaning, not proven durable logical-entity identity. | Revision and refiling rules require higher-layer definition. |
| PICS-GAP-03 | No current locator resolver exists in InformationCore. | Locator layer remains future composition work. |
| PICS-GAP-04 | No first-class historical pin exists in Core. | Git/commit pins remain external for now. |
| PICS-GAP-05 | Availability/tombstone semantics are absent from Core. | Representation absence and Information nonexistence must not be conflated. |
| PICS-GAP-06 | Session Information layer is not implemented. | Session cannot yet be treated as first-class Information Space object. |
| PICS-GAP-07 | Relation backend asymmetry remains implementation/test debt. | It must not be interpreted as a semantic conclusion. |
| PICS-GAP-08 | Arbitrary-byte fidelity remains conditional outside the accepted text-domain ruling. | It does not trigger InformationCore modification now. |
| PICS-NOGO-01 | No backend selection. | This study classifies options only. |
| PICS-NOGO-02 | No schema design. | Responsibility and seam mapping only. |
| PICS-NOGO-03 | No OSS integration. | Reference systems remain inventory. |
| PICS-NOGO-04 | No production claim. | Lab remains a validation estate. |

## 10. Verdict

```text
Physical carrier composition should be built from mature substrate mechanisms.
SimiGo's distinct work is the semantic layer:
  semantic identity continuity,
  revision/applicability,
  Information-space membership,
  availability meaning,
  historical pin interpretation,
  lineage semantics,
  and ES accessibility/continuation.

Therefore:
  do not select a backend from this document;
  do not implement a carrier from this document;
  use D1-D8 as the boundary for a separately authorized validation design.
```

## 11. Human closure addendum

Human accepted D1-D8 as a bounded documentary study:

```text
PICS-01 = ACCEPTED / BOUNDED PASS / CLOSED
D1-D8   = ACCEPTED
CCS-C8  = ACCEPTED
```

The registered gap is that D5/D7 covered semantic and consistency observations
but did not make performance a formal acceptance dimension. Performance is not
a reason to reopen PICS-01; it becomes a central obligation of the successor
Carrier Candidate & Performance Validation Study.

Successor:

```text
CCVS-01 — Carrier Candidate & Performance Validation Study
```
