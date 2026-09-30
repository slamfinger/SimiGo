# SimiGo-Lab PALACE Core Research Hypothesis

**Date:** 2026-09-30  
**Status:** RESEARCH HYPOTHESIS / LONG-TERM RESEARCH TRACK  
**Scope:** PALACE / Personal State Space  
**Relationship:** Second core research direction alongside Execution State / Backend Independence

---

## 1. Research Trigger

Recent Execution State and backend-boundary work suggests a deeper possibility:

> **Execution State may be the technical middle layer, while PALACE may contain the longer-lived and more distinctive value of the system.**

Execution State sits between upstream computation/user/agent semantics and downstream model/backend/physical representation. Its value depends on preserving semantic stability despite changes in both directions.

PALACE may operate at a different level: preserving a person's long-term knowledge, experience, reasoning history, execution history, and recoverable computational state independently of any particular model, backend, representation, or document format.

This is a research hypothesis, not yet an established conclusion.

---

## 2. Core Hypothesis: H-PALACE-1

> **H-PALACE-1:** The long-term irreplaceable value of a personal computing system may lie not in preserving a particular model or individual computation, but in preserving a recoverable, navigable, and evolvable **Personal State Space**. Execution State is the runtime state of computation within that space, while Backend Independence is a foundational capability that prevents the long-term state space from becoming locked to a particular computation engine.

Short form:

> **Engine is replaceable. Representation is replaceable. Personal State should be the long-term asset.**

---

## 3. PALACE Is Not Primarily a Database

PALACE must not initially be defined as:

- a document database;
- a generic knowledge base;
- a RAG system;
- a vector database;
- a graph database;
- a file-management replacement.

SQL, KV, event log, graph storage, object storage, or other mechanisms are physical storage candidates only.

The research object is:

> **A persistent personal State Space and its topology.**

The storage implementation must remain an open research question until the semantic requirements are understood.

---

## 4. What PALACE Preserves

Personal information is not merely a collection of files.

A durable personal State Space may need to preserve:

- knowledge/content;
- relations;
- temporal context;
- causality;
- evidence;
- reasoning history;
- assumptions;
- experiments;
- conclusions;
- rejected or superseded conclusions;
- execution lineage;
- fork history;
- recoverable execution state;
- representation references;
- provenance and evolution.

A file should therefore be regarded as one possible **representation** of a state or state-derived artifact, rather than necessarily being the fundamental unit of personal memory.

---

## 5. Execution State vs PALACE

The current conceptual distinction is:

> **Execution State is where computation can return and fork. PALACE records the completed and evolving whole.**

Execution State concerns the active computational branch:

- current position;
- lifecycle;
- continuation;
- fork;
- restore;
- continue;
- representation binding.

PALACE concerns the durable state space surrounding those computations:

- what states existed;
- how they relate;
- how they evolved;
- why they changed;
- what knowledge and evidence they contained;
- which branches were explored;
- which conclusions superseded others;
- which execution states can be recovered.

Conceptually:

```
                    PALACE
             Personal State Space
                       |
        +--------------+--------------+
        |              |              |
     Knowledge      History       Execution
        |              |              |
        +--------------+--------------+
                       |
                Execution State
                       |
          +------------+------------+
          |            |            |
         MLX         llama       future
```

Thus:

> **Execution State manages one computational state/branch; PALACE manages the person's long-term computational history and state space.**

---

## 6. Why This May Be a Strong Personal Need

Knowledge- and experience-intensive work has a recurring problem:

- important information is accumulated gradually;
- much of it appears insignificant at the time;
- later, the person may remember that something existed but not where it was;
- the original reasoning context is often lost;
- documents preserve artifacts but not necessarily the state of thought that produced them;
- human attention and memory are finite;
- a person cannot continuously focus on every subject they may later need.

This suggests a broader requirement:

> **An external long-term memory should preserve not only what a person knew, but enough state and context to recover how that knowledge was acquired, related, revised, and used.**

The potential target population is therefore broader than SimiGo's immediate engineering use:

> **People whose work depends materially on accumulated knowledge, experience, decisions, experiments, and reasoning history.**

This includes personal/business contexts as a hypothesis about demand, but demand strength remains to be validated rather than assumed.

---

## 7. Why Ordinary Files Are Insufficient as the Research Model

A folder hierarchy primarily expresses a tree:

```
folder
  ├── document
  ├── document
  └── folder
```

But personal knowledge evolves more like a graph plus time:

```
[idea]
  |
  +-- derived-from --> [experiment]
  |
  +-- supported-by --> [evidence]
  |
  +-- contradicted-by --> [later result]
  |
  +-- caused --> [design change]
  |
  +-- forked-from --> [previous state]
  |
  +-- supersedes --> [old conclusion]
```

The research question is therefore not simply:

> How do we index more documents?

It is:

> **How do we represent and navigate the topology of a person's accumulated knowledge, experience, reasoning, and computational state?**

---

## 8. Potential Long-Term Differentiation

If H-PALACE-1 proves correct, the durable asset is not the model or backend.

The durable asset is the accumulated personal State Space:

```
Years of work
     |
     v
knowledge + experience + reasoning + execution history
     |
     v
Personal State Space
     |
     +---- model can change
     +---- backend can change
     +---- representation can change
     +---- storage can evolve
     |
     v
personal continuity remains
```

This creates a different kind of system value from an inference engine or ordinary knowledge-management product.

The claim is intentionally limited:

> **The potential defensibility comes from accumulated personal state and topology, not from ownership of a particular inference implementation.**

Whether this becomes a genuine technical or product moat is an open research question.

---

## 9. Research Object and Boundary

The immediate research object is:

> **What is the minimum semantic structure required for a Personal State Space to remain recoverable, navigable, and evolvable across time, models, backends, and representations?**

This implies research into:

1. State identity;
2. lineage;
3. temporal ordering;
4. causality;
5. relations;
6. evidence/provenance;
7. evolution and supersession;
8. execution continuity;
9. representation independence;
10. indexing and topology;
11. recovery semantics;
12. long-term migration.

It does **not** yet authorize:

- selecting SQLite or another storage engine;
- designing a final PALACE database schema;
- implementing a graph database;
- building a RAG product;
- adding vector search merely because it is available;
- defining a final persistence protocol;
- expanding current Execution State semantics prematurely.

---

## 10. Relationship to the Existing SimiGo Research Route

Current route:

```
Execution State semantic contract
        |
        v
Backend / Representation boundary
        |
        v
PALACE durable-state model
        |
        v
Storage architecture candidates
        |
        v
Topology / indexing
        |
        v
Long-term personal memory and recoverable computation
```

Therefore PALACE does not invalidate current Execution State work.

Instead:

> **Execution State provides the runtime semantic substrate that a future PALACE may preserve and organize over the long term.**

Backend Independence is consequently a supporting capability:

> A durable personal State Space should not disappear or become semantically hostage to the current inference engine.

---

## 11. Current Research Status

**Status: HYPOTHESIS REGISTERED — NOT YET PROVEN**

Evidence currently supporting the hypothesis is architectural and conceptual:

- Execution State has been separated from Physical Representation;
- backend seam research has demonstrated that a real transport-backed adapter can compose with the existing E1/E3 boundary without taking semantic ownership;
- PALACE research has identified durable semantic snapshots, lineage, representation bindings, and state topology as distinct concerns.

This is sufficient to justify PALACE as a serious research track.

It is **not** sufficient to claim:

- validated product-market demand;
- universal need;
- commercial viability;
- technical feasibility of a complete PALACE;
- superiority over existing knowledge-management systems.

Those are future research questions.

---

## 12. Research Principle

The current guiding principle is:

> **Do not store only what the person produced. Preserve enough of the person's state space to recover what they knew, how it related, how it evolved, and where computation can continue.**

And, at the system level:

> **SimiGo should make computation replaceable while making personal continuity durable.**

---

## 13. Next Gate

PALACE should enter a **semantic research / architecture-definition track**, not immediate implementation.

The next legitimate research question is:

> **What is the minimum PALACE semantic model that can represent a person's durable knowledge, reasoning history, lineage, temporal/casual relations, and recoverable Execution State without collapsing back into a document database or generic knowledge graph?**

No storage technology is selected by this document.

No product scope is selected by this document.

No demand conclusion is selected by this document.

Only the research hypothesis and its boundary are registered.
