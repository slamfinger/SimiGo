# Phase 0 — MemPalace Source-Code Semantic Audit

Date: 2026-10-02  
Scope: `/Users/mr.simi/Library/Python/3.9/lib/python/site-packages/mempalace/` + `palace-v0/palace/chroma.sqlite3` real data  
Question: Which structures in MemPalace are Information, which are Execution/Continuity, and which are pure implementation mechanism?

---

## 1. Method

Direct source-code reading of the installed `mempalace` package (all 48 .py files),
tracing the full data path:

```text
source file → miner.py → chunk_text() → add_drawer() → ChromaDB upsert
                                                             ↓
searcher.py ← closet boost ← searcher.py ← searcher.py ← ChromaDB query
                                                             ↓
knowledge_graph.py ← LLM/entity extraction ← closet lines ← add_drawer metadata
                                                             ↓
layers.py (L0/L1/L2/L3) ← ChromaDB query ← identity.txt
                                                             ↓
mcp_server.py ← agent tool calls (44 tools)
```

All claims below are `observed code fact`, not `inferred storage design`.

---

## 2. Semantic Split Table

| Structure | What it actually is | Information? | Execution/Continuity? | Pure mechanism? |
|---|---|---|---|---|
| **drawer.content** (document text) | Verbatim chunk of a source file, possibly normalized (`strip_noise` for Claude Code JSONL) | **✓** (the text IS the Information — what happened, what was produced) | | |
| **drawer.metadata.source_file** | Absolute path to the origin file | **✓** (provenance — survives agent replacement) | | |
| **drawer.metadata.source_mtime** | File modification timestamp at ingest | **✓** (provenance) | | |
| **drawer.metadata.filed_at** | When the drawer was stored | **✓** (temporal identity) | | |
| **drawer.metadata.content_date** | The temporal date of the content itself (distinct from filed_at) | **✓** (temporal semantics) | | |
| **drawer.metadata.content_date_source** | How content_date was derived (mtime / file content / etc.) | **✓** (provenance of temporal claim) | | |
| **drawer.metadata.line_start / line_end** | Line range in structured source (xlsx/pdf extraction) | **✓** (provenance — exact position in source) | | |
| **drawer.metadata.chunk_index** | Position within chunked source | **✓** (structural identity — enables neighbor expansion) | | |
| **drawer.metadata.extract_mode / ingest_mode** | How content was extracted (format vs verbatim vs diary) | **✓** (provenance) | | |
| **drawer.metadata.normalize_version** | Schema version of the normalization pipeline | | | ✓ (implementation versioning) |
| **drawer.metadata.wing** | Top-level organizational namespace (project name) | *borderline* — filing taxonomy, not Information itself | | *borderline* |
| **drawer.metadata.room** | Sub-level organizational namespace (topic category) | *borderline* — filing taxonomy | | *borderline* |
| **drawer.metadata.hall** | Content-type categorization (identity/technical/diary) | *borderline* — filing taxonomy | | *borderline* |
| **drawer.metadata.entities** | Extracted proper nouns (semicolon-separated) | *derived* — searchable tags extracted FROM content | | ✓ (derived index) |
| **drawer.metadata.added_by** | Agent name that stored it | **✓** (provenance — who produced it) | | |
| **drawer.metadata.id_recipe** | ID generation recipe version | | | ✓ (implementation) |
| **drawer.id** (deterministic hash) | `drawer_{wing}_{room}_{sha256(source+chunk_idx)}` | | | ✓ (implementation ID scheme) |
| **closet (mempalace_closets collection)** | Compact pointer lines: `topic|entities|→drawer_ids` | | | ✓ (retrieval index / ranking signal — never a gate) |
| **KnowledgeGraph (knowledge_graph.sqlite3)** | Entity-relationship triples with temporal validity (`valid_from`/`valid_to`/`confidence`) | **✓** (structured facts about the world — the triple content IS Information) | | (the SQLite storage is mechanism) |
| **KnowledgeGraph.source_drawer_id** | Link back to the originating drawer | **✓** (provenance) | | |
| **hallways.json** | Entity co-occurrence graph (entity_a ↔ entity_b with strength/stability) | | | ✓ (derived navigation structure from entity co-occurrence — pure retrieval aid) |
| **Layer 0 (identity.txt)** | Agent identity text | | **✓** (who the current Execution IS — private continuity) | |
| **Layer 1 (Essential Story)** | Auto-generated summary from top-weight drawers | | **✓** (presentation for current Execution — derived, regenerable) | |
| **Layer 2 (On-Demand)** | Wing/room-filtered retrieval | | | ✓ (retrieval strategy) |
| **Layer 3 (Deep Search)** | Full semantic search | | | ✓ (retrieval strategy) |
| **ChromaDB backend** | Vector store + SQLite + HNSW index | | | **✓** (storage implementation) |
| **Embeddings** | Vector representations derived from content | | | **✓** (retrieval derivative — replaceable) |
| **BM25** | Keyword scoring re-ranker | | | **✓** (retrieval implementation) |
| **MCP server** | 44-tool external access protocol (JSON-RPC) | | | **✓** (protocol/interface) |
| **Miner/sweeper/convo_miner** | Ingestion pipelines (chunking, routing, normalization) | | | ✓ (ingestion mechanism) |
| **palace_graph (tunnels/hallways)** | Graph traversal over wing/room metadata | | | ✓ (derived navigation view) |
| **diary entries** | Agent-written journal entries stored as drawers with `room=diary` | *content is Information* (what happened) | *agent framing is Continuity* (how to continue, self-assessment) | |
| **WAL log** (`_wal_log`) | Operation audit trail written on MCP calls | **✓** (what happened — audit/history) | | |
| **checkpoint (memories_filed_away)** | Post-execution archive acknowledgment | | **✓** (session-end continuity — "what I just did" pointer for the current session) | |

---

## 3. Answers to the Three Questions

### Q1: What survives agent/memory implementation replacement?

```text
1. The verbatim content text itself (drawer.document)
2. Provenance: source_file, source_mtime, filed_at, added_by,
   extract_mode, ingest_mode, line_start/line_end, chunk_index
3. Temporal semantics: content_date, content_date_source
4. KnowledgeGraph triples: (subject, predicate, object,
   valid_from, valid_to, confidence, source_drawer_id)
5. The organizational taxonomy (wing/room/hall) is *arguable* —
   it classifies Information but is not itself Information.
   It could be re-derived from content. Tentatively: NOT core.
```

These form the minimum viable **Information** in a Swift Core:

```text
Information {
    content: String                    // verbatim text
    provenance: Provenance {
        source: String?                // source_file path
        source_time: Date?             // source_mtime
        produced_by: String?           // added_by
        produced_at: Date              // filed_at
        extraction_mode: String?       // how it was extracted
        position: (line_start?, line_end?, chunk_index?)?
    }
    temporal: TemporalSemantics {
        content_date: Date?            // when the content is about
        content_date_source: String?   // how that date was derived
    }
    identity: InformationID            // deterministic hash or UUID
}
```

### Q2: What is only the current Execution's continuity?

```text
1. Layer 0 (identity.txt) — who the current agent IS
2. Layer 1 (Essential Story) — auto-generated wake-up summary,
   regenerable from drawers, exists only to prime the current context
3. Diary entries — the content describes what happened (Information),
   but the framing is "my session diary, my self-assessment,
   my plan for what to do next" (Continuity). The two layers are
   mixed in one document today.
4. checkpoint / memories_filed_away — session-end state pointer
5. Closet pointer lines — routing hints for the current search
   (regenerable from content)
```

### Q3: What is pure implementation?

```text
1. ChromaDB (vector store, HNSW, SQLite persistence)
2. Embedding vectors (derived from content for retrieval)
3. BM25 re-ranking
4. MCP protocol (44 tools, JSON-RPC)
5. Miner/sweeper/convo_miner (ingestion pipelines)
6. Hallways/tunnels (derived entity co-occurrence navigation)
7. Layer 2/Layer 3 (retrieval strategies)
8. Palace graph (tunnel/hallway graph traversal)
9. WAL operation log (audit trail — though the *content* logged
   is Information-adjacent, the logging itself is mechanism)
10. Deterministic ID scheme (drawer_{wing}_{room}_{sha256})
11. normalize_version / id_recipe (implementation versioning)
```

---

## 4. Key Structural Observations

### 4.1 The boundary is already visible in the metadata schema

The real ChromaDB data shows two distinct groups of metadata fields:

**Group A — "what is this Information and where did it come from"**  
`source_file, source_mtime, content_date, content_date_source, filed_at, added_by, extract_mode, ingest_mode, line_start, line_end, chunk_index`

**Group B — "how is this filed in the current memory system"**  
`wing, room, hall, entities, normalize_version, id_recipe`

Group A fields are about the Information itself (provenance + temporal identity).  
Group B fields are about the filing system (organizational taxonomy + implementation versioning).

### 4.2 The "boundary freeze" rules map cleanly

| BR rule | Code-level confirmation |
|---|---|
| **BR-1** (lifecycle form split) | `ingest_mode` field already distinguishes `extract` (structured) from other modes; the same source can produce drawers in different modes |
| **BR-2** (continuity metadata → private) | `agent` field on diary entries + `checkpoint` ack + Layer 0 identity — these exist only for the current Execution's continuity |
| **BR-3** (product → shared) | Drawer content is always stored verbatim, regardless of whether "someone needs it later" — this matches BR-3 exactly |
| **BR-5** (activation semantics) | Closet pointers are the only activation mechanism in the current code, and the searcher treats them as ranking signals, never gates — confirming "shared space does not summon itself" |

### 4.3 Mixed-layer problem in diary entries

Diary entries (produced by `tool_diary_write`) store agent self-assessment,
plan-for-next-session, and factual observations in a single document field.

This confirms the T1 finding: "work records carry both 'what was known'
(factual) and 'how to continue' (actionable recipe)" — the current
implementation does not split them. The Swift Core must handle this
explicitly.

### 4.4 Entities are derived, not core Information

`entities` metadata (extracted proper nouns) are computed from content
by regex/entity_detector at ingest time. They are a searchable index,
replaceable by re-derivation. They are NOT part of the Information's
identity — they are part of the retrieval implementation.

### 4.5 wing/room/hall taxonomy: an open question

The wing/room/hall filing taxonomy is present in every drawer's metadata.
It serves retrieval (filtering) and organization. But it is not
provenance, not temporal, and not content. It is a filing system.

**Open question for the Swift Core**: should the taxonomy live inside
the Information model (as an optional classification tag), or outside
it (as a separate filing layer that references Information)?

The current code couples them (the taxonomy is in the same metadata).
The boundary freeze rules suggest they should be separate — but this
is a design decision, not a code fact.

---

## 5. Minimum Swift Core Sketch (NOT code yet — only the semantic surface)

From the audit, the minimum types that survive implementation replacement:

```text
InformationID          — stable identity
InformationContent     — the verbatim text
Provenance             — where it came from, who produced it, when, how
TemporalSemantics      — when the content is about

InformationStore       — the storage interface (protocol)
InformationQuery       — the query interface (protocol)
```

NOT in the core (all external):

```text
ChromaBackend          — one implementation of InformationStore
EmbeddingModel         — one retrieval strategy
BM25Scorer             — one ranking strategy
MCPServer              — one access protocol
Miner                  — one ingestion pipeline
ClosetIndex            — one retrieval index
KnowledgeGraph         — one structured-Information view (the triples are Information, the KG storage is implementation)
HallwayGraph           — one navigation view
LayerStack             — one Execution Runtime presentation strategy
```

---

## 6. What This Audit Does NOT Answer

- Whether the wing/room taxonomy should live inside or outside the Information model (design decision)
- How diary entries should be split into Information vs Continuity layers (needs design)
- Whether the KnowledgeGraph triples should be promoted to first-class Information or remain a derived view (needs design)
- What the "activation semantics" should look like in the Swift Core (BR-5 says it must exist, but the shape is open)
- The exact Swift API surface (this audit defines what the types must carry, not how they compose)

---

## 7. Next Step

This audit establishes the semantic ground truth from the existing codebase.
The next step is to freeze the minimum Swift Core semantic surface based on
these findings and then write the actual Swift types.

Before writing code: the user should review §2 (the split table) and §5 (the
core sketch) and rule on the open questions in §6.

