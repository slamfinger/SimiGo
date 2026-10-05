# Carrier Component Study — Scope & Research Question Charter

Date: 2026-10-06  
Status: `ACCEPTED / COMMISSIONED / PICS-01 OPEN`
Seam: `IS-IDLOC-SEAM-01 / v0.1`  
Study ID: `PICS-01`
Active route: `PALACE / INFORMATION SPACE FOUNDATION`  
Frozen Contracts: `UNCHANGED`  
Scope guard: `CHARTER PROPOSAL ONLY · NO IMPLEMENTATION · NO OSS INTEGRATION · NO BACKEND SELECTION · NO DATABASE SCHEMA DESIGN · NO MIGRATION · NO REPOSITORY REORGANIZATION · NO PROBE EXECUTION · NO EXPERIMENT · NO CONTRACT CHANGE`

## 1. Accepted reframing

Human research judgment proposes moving from:

```text
Can Git/GitHub implement Information Space?
```

to:

```text
For real files and real sessions, what physical carrier composition can carry
Information Space with the least unnecessary infrastructure?
```

The proposed Lab role becomes:

```text
SimiGo-Lab
  = research execution + evidence + capsules + index + carrier validation group

NOT
  = production Information Space implementation
```

This reframing does not demote the Lab. It bounds the Lab as an observation and
validation estate.

## 2. Immediate research object

The proposed study is not to assemble five products. It is to map mature
carrier responsibilities and determine the minimal composition needed for:

```text
physical files / blobs / sessions
  ↓
logical Information
  ↓
relations / history / availability
  ↓
future Execution State access
```

The prior five-system review—Nextcloud, Git, DVC, Noms, and lakeFS—is input,
not a mandated stack. Candidate components may include other systems or system
classes.

## 3. Candidate responsibility model

```text
CCS-C1 Entity Representation Store
  immutable bytes/files/objects;
  digest, size, media type, encoding;
  suitable for large or binary entities.

CCS-C2 Information Registry
  InformationID / RevisionID / RepresentationID;
  provenance;
  formation and observation timestamps;
  semantic identity remains a SimiGo responsibility.

CCS-C3 Locator / File Index
  current mapping:
    InformationID → Representation → Locator;
  historical mapping:
    InformationID → prior Representation → prior Locator / Pin;
  carrier, storage namespace, commit, path, URI, or object key.

CCS-C4 Relation / History
  successor, predecessor, derived-from, split-from, merged-from,
  supersedes, references, and historical pins.

CCS-C5 Session Information
  raw session, events, summaries, decisions, judgments, pending items,
  append/provenance semantics.

CCS-C6 Derived Index / Search
  rebuildable retrieval support;
  must not become semantic authority.

CCS-C7 Availability / Access State
  current, archived, detached, unavailable, missing, restored, or superseded;
  representation absence must not imply Information nonexistence.

CCS-C8 Execution Interface
  carrier ↔ SimiGo interface responsibilities only:
    expose what can be resolved, consumed, produced, pinned, or continued.
  This is NOT a carrier-native database capability.
  It does not require the carrier to execute SimiGo semantics.
  Detailed ES↔IS semantics remain reserved for later work.
```

Human acceptance note:

```text
CCS-C8 remains in the responsibility model as an interface boundary,
not as a required database capability. The carrier may store, locate, and
make information available; it does not thereby execute SimiGo semantics.
```

## 4. Research questions

```text
CCS-Q1
  Which responsibilities above are mandatory for a minimal physical carrier,
  and which are optional, derived, or later-layer?

CCS-Q2
  For each responsibility, which mature system class already provides a
  sufficient substrate: relational SQL, embedded SQL, KV/document, Git/DAG,
  object/file storage, graph database, or search index?

CCS-Q3
  Which integration seams are unavoidable, especially:
    registry ↔ entity store,
    registry ↔ locator index,
    locator ↔ relation/history,
    relation ↔ session information,
    and substrate ↔ SimiGo semantic layer?

CCS-Q4
  Which workload operations must any future validation observe?

CCS-Q5
  What failure and recovery semantics are required for partial move, rename,
  delete, restore, index rebuild, and identity-mapping loss?

CCS-Q6
  What bounded evidence can SimiGo-Lab provide without becoming a production
  Information Space claim?

CCS-Q7
  What minimal validation protocol could later compare candidate compositions
  without prematurely selecting a database type?
```

## 5. Workload operation set to register

Any later validation design should cover at least:

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

This list does not authorize execution.

## 6. Evaluation dimensions

Candidate classes or systems may later be compared by:

```text
identity stability
revision/history fidelity
locator remapping
entity-file suitability
relation expressiveness
session append behavior
search/index rebuildability
historical pin resolution
transactional boundaries
crash recovery
orphan/mapping-loss behavior
operational complexity
migration burden
semantic leakage into storage
fit with existing InformationCore substrate
```

No numerical ranking is authorized by this study charter.

## 7. Commissioned deliverables

```text
D1 Responsibility ownership matrix
D2 System-class capability mapping
D3 Candidate OSS/component inventory, without commitment
D4 Integration seam map
D5 Workload / observation matrix
D6 Minimal composition options A/B/C, without selection
D7 Carrier validation protocol design, without execution
D8 Gap / no-go register
```

All deliverables are documentary unless a later phase receives separate
authorization.

## 8. Explicit non-goals

```text
Do not select SQLite, graph, KV, Git, object storage, or any product.
Do not integrate five OSS projects.
Do not implement an adapter or store.
Do not modify InformationCore / RelationCore.
Do not migrate or reorganize SimiGo-Lab.
Do not treat Lab as production Information Space.
Do not turn derived search into semantic authority.
Do not reopen Frozen Contracts.
Do not open Higher-Layer Continuation Graph Semantics automatically.
```

## 9. Relationship to existing results

```text
Existing Systems Review
  supplies mechanism exemplars.

Core Identity Mechanism Audit
  shows that opaque formed-fact identity, immutable Information,
  identity-based relations, backend protocol, and optional filing separation
  already exist.

This charter
  studies the next physical composition layer without changing those
  boundaries.
```

## 10. Risks

```text
R1 Conflating Git object identity with semantic Information Identity.
R2 Conflating path with identity.
R3 Prematurely choosing a database type.
R4 Assembling five systems before responsibility mapping.
R5 Treating Lab as production carrier.
R6 Letting search index become authority.
R7 Turning the 80% infrastructure problem into a new SimiGo implementation.
R8 Opening Higher-Layer semantics before physical composition is understood.
```

## 11. Decision record

Human selected option A. The original options are retained below for audit.

```text
A  ACCEPT CHARTER
   Commission PICS-01 as documentation-only carrier-component study.

B  REVISE CHARTER
   Narrow or reorder responsibilities/questions before commissioning.

C  PARK
   Keep as registered proposal without opening work.

D  REJECT
   Return to Higher-Layer Continuation Graph Semantics or another route.
```

Selected by Human ruling: `A — ACCEPT CHARTER`.
