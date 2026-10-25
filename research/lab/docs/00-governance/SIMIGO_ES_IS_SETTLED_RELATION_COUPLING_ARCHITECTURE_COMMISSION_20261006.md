# SimiGo Core Architecture — ES–IS Settled Relation Coupling Commission

> **Status:** COMMISSIONED FOR LOCAL-AGENT RESEARCH / NO IMPLEMENTATION AUTHORIZED
> **Date:** 2026-10-06
> **Scope:** theoretical architecture definition and research-program alignment only

## 1. Commission

The current research record contains the ingredients of the ES–IS coupling problem, but does not yet state the following as the explicit central SimiGo architecture invariant:

> **Execution State and Information Space are two mutually coupled computational state spaces. Execution State performs model/internal computation and settles relations; Information Space persists the resulting information, relations, dependencies, provenance, and freshness conditions as reusable Settled Relation State. A later Execution State must be able to validate and consume that settled state and continue with only genuinely new computation, rather than recomputing already-settled relations.**

The local agent is commissioned to audit the existing SimiGo-Lab research corpus and establish whether this statement is already defined elsewhere under different terminology. Do not assume absence from search alone; inspect relevant architecture, governance, evidence, and historical research documents.

## 2. Required conceptual distinctions

The audit must explicitly distinguish:

### 2.1 Information
Information Space provides information objects and their physical/logical identity.

### 2.2 Relation
Relations express dependencies/constraints between information objects or derived states.

### 2.3 Freshness
Freshness/revision/provenance determines whether a prior settled relation remains legally consumable.

### 2.4 Settled Relation State
A settled computation must not be reduced to an opaque cached value. It must retain, at minimum as semantically required:

- derived result/state;
- source/input relation;
- dependency identities and revisions;
- provenance;
- validity/freshness conditions;
- sufficient relation semantics for later Execution State reuse.

### 2.5 Information Topology
The topology is not an independently invented knowledge graph. It is the structure formed by Information objects and the relations/settled relations produced and retained through Execution State computation.

Conceptual minimum:

```
Information = nodes
Relation / Settled Relation State = edges
Dependency / Revision / Freshness / Provenance = edge validity conditions
Execution State = computation that consumes and extends this topology
```

## 3. Core feedback loop

The architecture under audit must express the following loop:

```
Information Space
  → Information / Relation / Freshness
  → Execution State
  → computation
  → Settled Relation State
  → Information Space
  → validation / reuse
  → next Execution State
```

The research endpoint is not merely "ES can continue from IS".

It is:

```
ES₁ settles R₁
   ↓
IS persists R₁ + original relation/dependencies
   ↓
ES₂ validates R₁
   ↓
ES₂ consumes R₁ without recomputing R₁
   ↓
ES₂ computes only ΔR
   ↓
IS persists R₂
```

## 4. Core falsifiable research question

> Can a settled relation produced by one Execution State become a legally reusable computational state for a later, independent Execution State, such that the later Execution State avoids recomputation of the already-settled relation and only performs genuinely new computation, while invalid/stale dependencies force correct re-computation?

The experiment must distinguish this from ordinary cache hit.

A valid reuse path requires relation/dependency/freshness validation.

## 5. Research boundary

Do NOT broaden this commission into:

- PALACE product design;
- database selection;
- MCP;
- MemPalace;
- remote API;
- agent framework integration;
- performance optimization;
- generic knowledge graph design.

Those are downstream concerns.

## 6. Relationship to existing research

The audit must map existing work into prerequisite/supporting evidence:

- ES/IPAC: what constitutes a reusable execution state and continuation relation;
- R01 ES Continuation Sufficiency: whether Information Closure is sufficient for continuation;
- PIR: whether required information/relations can be brought to fresh lawful state;
- Identity/Revision/Provenance: whether settled relations can be validated;
- U-A / CCVS: whether derived information can be durably and consistently persisted;
- Information Topology / RelationCore material, if present;
- any prior relation-reuse, topology, derived-result, or cross-Execution-State material.

The audit must explicitly identify what has **not** yet been experimentally demonstrated.

## 7. Required output from local agent

Produce a research/governance clarification package containing:

1. corpus audit: existing documents and exact passages supporting or contradicting the core definition;
2. terminology map: existing terms → proposed canonical terms;
3. explicit statement of whether "Settled Relation State" is new terminology or renaming of an existing concept;
4. canonical ES–IS architecture definition;
5. Information Topology definition;
6. core research question and falsifiable hypothesis;
7. evidence matrix: established / partially established / not established;
8. minimum next experiment design outline for ES₁ → IS → ES₂ reuse;
9. list of documents that should be amended or superseded;
10. statement that no implementation or experiment is authorized by this commission.

## 8. Governance constraint

Do not silently reinterpret existing R01/PIR results as evidence for cross-ES relation reuse. Preserve their original scope.

The desired result is architecture clarification first, then a separately reviewed experiment.

