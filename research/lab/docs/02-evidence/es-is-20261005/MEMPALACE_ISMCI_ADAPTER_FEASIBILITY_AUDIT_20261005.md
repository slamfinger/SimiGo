# MemPalace IS-MCI Adapter Feasibility Audit

Date: 2026-10-05  
Active route: `PALACE / INFORMATION SPACE FOUNDATION`  
Selected candidate: `MemPalace local file-backed core`  
Audit status: `DELIVERED / AWAITING HUMAN REVIEW`  
Audit type: `READ-ONLY FEASIBILITY AUDIT`  
Verdict: `NO-GO FOR MEMPALACE AS-IS`  
Reason: `4 CRITICAL GAPS · A THIN ADAPTER CANNOT SATISFY IS-MCI-01..08 WITHOUT TURNING MEMPALACE INTO A NEW CARRIER LAYER`

## 1. Scope and discipline

This audit asks only whether native MemPalace capabilities can satisfy the
accepted Information Space obligations `IS-MCI-01..08`.

It does **not**:

- implement an adapter;
- modify MemPalace or `palace-v0/palace`;
- execute `PRQ-ISF-01`;
- run a new experiment;
- modify Frozen Contracts;
- allow semantic search, summaries, inference, fuzzy retrieval, or completion to
  be counted as mechanical capability.

A `GAP` means native MemPalace does not provide the required discipline. Adding
that capability to MemPalace would no longer be an independent-carrier test.

## 2. Audit specimen

```text
Selected candidate kind      MemPalace local file-backed core
Source specimen              MemPalace 3.10.0, Python package
Source snapshot              .build/mempalace-src/mempalace
Historical source baseline   develop @ 5ea40d3 (registered in Palace V2 G0)
Active local instance        palace-v0/palace
Active backend               chromadb 1.5.9
Active drawers               9,398 per mempalace_status
SQLite integrity             ok; error_count = 0
Read-only calls used         status, taxonomy, list_wings, list_drawers,
                             graph_stats, kg_stats
Mutation calls               none
```

Additional read-only SQLite inspection found no active `logstream.sqlite3` in
`palace-v0/palace`; therefore the append-only event/artifact layer exists in the
source but was not initialized in the inspected live specimen.

## 3. Evidence base

| Area | Evidence |
|---|---|
| Drawer identity | `mempalace/sources/context.py:154-168`: drawer ID = `sha256(source_file)[:24] + "_" + chunk_index`. |
| Drawer persistence | `mempalace/sources/context.py:92-135`: `upsert_drawer()` writes content and metadata with Chroma `upsert`; same source/chunk is rewritten. |
| Conflict detection | `mempalace/collision_scan.py:1-50`: pre-mining scan catches conflicting duplicate IDs for same `(source_file, chunk_index)`. |
| Live shape | Read-only `list_drawers` returned drawer ID, wing, room, content preview, metadata including `chunk_index`, `filed_at`, `source`-adjacent fields, agent, topic, and type. |
| Provenance separation | Drawer content is separate from metadata; artifact/event records also have separate metadata, creator, replica, and timestamp fields. |
| Append-only event layer | `mempalace/logstream.py:1-18,492-540,674-760`: events/artifacts are append-only, with verbatim bodies, SHA-256 artifact index, referential check, and explicit size limits. |
| Graph/KG | Live `graph_stats`: 9 rooms, 14 room instances, 12 connections, 0 explicit tunnels. Live `kg_stats`: 0 entities and 0 triples. |

## 4. Obligation classification

Scale:

```text
DIRECT   native surface already satisfies the obligation.
ADAPTER  a thin mapping could satisfy it without semantic inference or repair.
GAP      native MemPalace lacks the required discipline; adding it would create
         a new carrier layer rather than test MemPalace independently.
```

| ID | Obligation | Classification | Native finding |
|---|---|---|---|
| IS-MCI-01 | immutable content | **GAP** | Drawer IDs are derived from source path plus chunk index, not content digest. `upsert_drawer()` rewrites the same drawer. Content is extracted text, not arbitrary immutable bytes. The logstream artifact layer stores verbatim text with SHA-256, but was absent from the live specimen, is limited to UTF-8 text rather than arbitrary bytes, and is not the primary drawer carrier. |
| IS-MCI-02 | canonical records | **ADAPTER** | Chroma can persist records under deterministic drawer IDs and retrieve them with metadata. However canonical identity is source/path/chunk-based, not frozen-field identity, and records are mutable by native upsert. A separate write-once canonical-record convention would be required. |
| IS-MCI-03 | typed references | **GAP** | The system preserves structured drawer metadata and has graph/KG machinery, but there is no native general typed-reference surface for `result`, `used`, `surface`, and `continues`. Live KG has zero triples, and explicit tunnels are zero. |
| IS-MCI-04 | separated provenance | **DIRECT** | Drawer content is stored separately from metadata such as source path, chunk index, agent, adapter, timestamps, and source-directory identity. Artifact/event records also carry separate metadata and provenance fields. |
| IS-MCI-05 | pinning and historical retrieval | **GAP** | There is no native labeled pin or historical immutable version surface for the required continuation graph. Because drawers are upserted, a pin over a rewritten drawer cannot guarantee historical content. |
| IS-MCI-06 | evolution events | **ADAPTER** | MemPalace has an append-only event concept with explicit payload validation and immutable events. A thin convention could register version-succession events, but this is not automatically attached to drawer mutation and the live specimen had no initialized logstream. |
| IS-MCI-07 | traversable lineage | **GAP** | Graph/KG machinery exists, but there is no native continuation-lineage graph equivalent to `CR → parent → root`, no required-edge traversal for `used / surface / continues`, and no frozen acyclicity discipline over canonical records. |
| IS-MCI-08 | mechanical failure discipline | **GAP** | MemPalace has useful mechanical checks: SQLite integrity, deterministic IDs, collision errors, and explicit event/artifact validation. But required drawer upsert can silently replace prior content, and the frozen I-1 failure families cannot be produced without a new canonical validation layer. |

Count:

```text
DIRECT   = 1 / 8   IS-MCI-04
ADAPTER  = 2 / 8   IS-MCI-02, IS-MCI-06
GAP      = 5 / 8   IS-MCI-01, IS-MCI-03, IS-MCI-05, IS-MCI-07, IS-MCI-08
```

## 5. Why no thin adapter is feasible

The three decisive failures form one dependency chain:

```text
IS-MCI-01 immutable content missing
        ↓
IS-MCI-05 historical pins cannot be guaranteed
        ↓
IS-MCI-07 lineage cannot be mechanically preserved
        ↓
IS-MCI-08 frozen failure discipline cannot be mapped
```

An adapter could store additional canonical JSON, pin records, edge records, and
events beside MemPalace. But at that point the actual carrier would be a new
content-addressed lineage store that merely uses MemPalace as one persistence or
indexing surface. That would no longer test MemPalace as an independent carrier.

Semantic retrieval cannot close these gaps:

```text
semantic search    ≠ identity resolution
LLM summary        ≠ canonical content
semantic inference ≠ lineage
fuzzy retrieval    ≠ historical pin
auto-completion    ≠ mechanical failure
```

## 6. Feasibility verdict

```text
MEMPALACE AS-IS = NO-GO FOR PRQ-ISF-01 CARRIER TEST
THIN ADAPTER    = NOT FEASIBLE WITHOUT BUILDING A NEW CARRIER LAYER
CANDIDATE AUDIT = VALID NEGATIVE RESULT
```

This is not a defect judgment against MemPalace for its intended memory/workspace
purpose. It is a negative feasibility result against the stricter ES↔IS
`IS-MCI-01..08` obligations.

## 7. Permitted next decisions

No next action follows automatically. Human may explicitly choose:

```text
A1  revise the Foundation route to define a composite carrier,
    acknowledging that it is no longer an independent MemPalace test;

A2  search for a different independent candidate whose native model already
    provides immutable canonical records, typed references, lineage, and pins;

A3  pause the Foundation route with MemPalace preserved as a valid negative
    feasibility result;

A4  authorize a new research question studying what minimal carrier layer would
    be required, without implementing it yet.
```

MemPalace must not be modified merely to make it pass `PRQ-ISF-01`.
