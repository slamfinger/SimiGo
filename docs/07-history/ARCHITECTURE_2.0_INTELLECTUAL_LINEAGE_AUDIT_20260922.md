# Architecture 2.0 Intellectual Lineage Audit — 2026-09-22

**Purpose:** verify that the high-value Architecture 2.0 ideas recovered from available session context are represented in the SimiGo-Lab repository without turning historical discussion into current evidence or authority.

**Scope:** SimiGo-Lab / SimiGo 2.0 only. SimiGo 1.x product-development material is excluded.

## 1. Result

The current archive now preserves the major conceptual transitions that are recoverable from the available session context:

```
long-context practical limit
        ↓
computation decomposition question
        ↓
Compute once, multiple futures
        ↓
Execution State as a missing semantic layer
        ↓
heterogeneous / hybrid state semantics
        ↓
physical-resource boundary correction
        ↓
open-source deduplication
        ↓
mechanism existence before implementation
        ↓
runtime embodiment question
        ↓
unit discovery
        ↓
residency / access / semantic-dependency questions
        ↓
evidence-gated architecture
```

The detailed curated reconstruction is in:

`docs/07-history/ARCHITECTURE_2.0_SESSION_KNOWLEDGE_20260922.md`

Durable cross-Agent memories are now additionally recorded as:

- RM-018 — Compute-once / multiple-futures is the conceptual origin of Execution State
- RM-019 — Execution State is a semantic layer above raw KV storage
- RM-020 — Deduplicate before inventing
- RM-021 — Architecture decomposition must respect physical resource boundaries
- RM-022 — Mechanism existence must precede implementation authority
- RM-023 — The research object can move upward when lower-layer mechanisms are already available

## 2. What is preserved

### Origin / central idea

Preserved:
- the shift from “faster long-context inference” toward reusable, branchable, recoverable execution state;
- the phrase/concept “Compute once, multiple futures”;
- the reason Execution State became the central abstraction.

### Conceptual boundary

Preserved:
- Execution State is not synonymous with raw KV bytes;
- identity and continuation semantics are part of the stronger abstraction;
- hybrid model state may require component-specific fork semantics under one external lifecycle.

### Negative / corrective knowledge

Preserved:
- application-level task splitting on one saturated GPU does not itself create new hardware resources;
- kernel-level and multi-device decomposition belong to different research layers;
- lower-layer open-source mechanisms should be checked before proposing duplicate research.

### Methodological evolution

Preserved:
- architecture hypothesis must not become implementation specification automatically;
- mechanism existence should be established before implementation authority;
- simulation mechanism is distinct from runtime embodiment;
- operational unit discovery precedes implementation choice;
- semantic availability is distinct from semantic dependency.

### Research-direction evolution

Preserved:
- access/co-access as a candidate basis for useful granularity;
- the move from storage mechanisms toward execution state, residency, observable runtime boundaries, and policy/planner questions;
- the research tree and closure of branches as durable knowledge.

## 3. Provenance discipline

This audit does **not** claim to be an exhaustive reconstruction of every Architecture 2.0 conversation.

The source available for this curation consisted of retained session context and already-archived SimiGo-Lab research material. Where a detailed original transcript was not available, the archive uses explicit “curated reconstruction” language rather than fabricating quotations, dates, or exact conversational order.

The repository therefore distinguishes:

```
historical session reconstruction
        ≠
verbatim transcript
        ≠
experimental evidence
        ≠
current research state
```

## 4. Promotion check

The newly preserved memories do not:

- reopen Track B;
- reopen Track E;
- register RQ-F-01;
- start STEP ⑤;
- authorize Swift/MLX implementation;
- authorize measurement or data collection;
- promote Architecture 2.0 into production architecture.

Current state remains governed by `docs/RESEARCH_STATE.md` and the registered endpoint / gate records.

## 5. Remaining historical gap

A remaining gap is explicitly recorded rather than guessed:

> The exact earliest conversational chronology before the “Compute once, multiple futures” formulation is not fully reconstructable from the currently retained context.

In particular, the archive can preserve the conceptual transition from long-context optimization to Execution State, but should not invent a minute-by-minute or message-by-message origin story where source material is absent.

This gap is not a research blocker. It is a provenance limitation.

## 6. Recovery criterion for a new Agent

A new Agent reading the current repository should now be able to recover:

1. why Architecture 2.0 exists;
2. why Execution State became central;
3. which tempting lower-level directions were rejected or separated;
4. which ideas remain hypotheses;
5. why implementation does not automatically follow from architecture documents;
6. which research branches are closed;
7. where the current gate is;
8. which durable memories may seed future research questions.

That is the intended minimum viable intellectual memory of Architecture 2.0.
