# SimiGo-Lab Research State / Memory Recovery Anchor

> **Status:** RECOVERY ANCHOR
> **Recovery baseline:** GitHub `slamfinger/SimiGo-Lab@main` = `0508e26`
> **Research-state content revision:** `bcc6b81`
> **Metadata correction:** this commit; verify current `main` dynamically with `git rev-parse HEAD`
> **Date:** 2026-10-06
> **Canonical source:** GitHub `slamfinger/SimiGo-Lab@main`
> **Purpose:** restore research state and research-memory entry without relying on chat memory, deleted branches, or superseded handoff paragraphs.
> **Boundary:** recovery only. This anchor does not start `SRS-SEM-01`, create a new mission/task tree, authorize implementation, fixture creation, experiment, IS mutation, or code change.

## 1. Canonical recovery order

A new session must recover in this order:

```text
1. This anchor.
2. docs/RESEARCH_CONTEXT_INDEX.md.
3. docs/RESEARCH_STATE.md — restored current-state section.
4. Issue #2 decomposition/control artifact.
5. ES–IS Settled Relation Coupling Architecture Audit Package.
6. Named Human rulings / frozen contracts / evidence artifacts when a claim is
   disputed.
```

Do not reconstruct state from conversation memory, agent recollection, deleted
branch names, or older handoff paragraphs that are explicitly marked as
superseded.

## 2. Global research goal

SimiGo is not a generic knowledge base or inference engine.

The current research goal is:

```text
Determine whether Execution State can form a real computational coupling with
a persistent Information Space, such that a relation settled by one Execution
State becomes lawful, verifiable, reusable computational state for an
independent later Execution State.
```

The reusable state must allow:

```text
validate dependency / revision / freshness / provenance;
reuse the settled relation without recomputation;
compute only genuinely new delta;
block or recompute when dependencies are stale, invalid, or unprovenanced.
```

This must be distinguished from an ordinary cache hit.

## 3. Canonical loop

```text
ES₁
  ↓ compute relation
Settled Relation State
  ↓ persist result + source relation + dependencies + revision + provenance +
    freshness + relation semantics + settlement status
Information Space
  ↓ independent resolution
ES₂
  ↓ validate dependency / revision / freshness / provenance
  ↓ if valid, reuse settled relation
  ↓ compute only Δ
New Settled Relation State
  ↓ persist
Information Space
  ↓
ES₃ ...
```

## 4. Canonical definitions

```text
ES = Execution State.
IS = Information Space.

ES and IS are mutually coupled computational state spaces.

SRS = Settled Relation State:
  settled result
  + source relation
  + dependency identities / revisions
  + provenance
  + validity / freshness conditions
  + relation semantics
  + settlement status.

SRS is not:
  opaque cache entry;
  bare result;
  mutable relation;
  runtime checkpoint;
  generic knowledge-graph edge.

SRS records are append-only.
Invalidation, supersession, or freshness change creates a new status/state
record; historical SRS must not be silently rewritten.

Information Topology =
  Information nodes
  + Relation / Settled Relation State edges
  + dependency / revision / freshness / provenance / policy validity
  accumulated by Execution State computation.

Information Topology is not:
  independent knowledge-graph product;
  similarity graph;
  vector index;
  separate PALACE semantic system.
```

## 5. Historical lineage

The current ES↔IS↔SRS architecture was progressively distilled from prior
research:

```text
Execution State
  → Information / Relation
  → relation persistence / identity / provenance / revision
  → ES continuation
  → Information Space foundation
  → PIR / physical reconciliation
  → Unified Carrier
  → ES↔IS coupling refinement
  → Settled Relation State
  → Information Topology
  → ES₁ → IS → independent ES₂ reuse
```

Authoritative lineage anchors:

```text
docs/00-governance/SIMIGO_LAB_PHASE2_RELATION_DECISIONS_SEALED_20261002.md
docs/00-governance/SIMIGO_LAB_PHASE2_RELATION_PERSISTENCE_SEMANTICS_GATE_RESULT_20261002.md
docs/00-governance/SIMIGO_LAB_IPAC_EXECUTION_STATE_RESEARCH_SYNTHESIS_20261003.md
docs/00-governance/SIMIGO_LAB_IPAC_SYNTHESIS_CLOSURE_REVIEW_20261003.md
docs/00-governance/SIMIGO_LAB_EXECUTION_INFORMATION_SPACE_BOUNDARY_SYNTHESIS_20261003.md
docs/00-governance/SIMIGO_LAB_RESEARCH_CONSTITUTION_20261005.md
docs/02-evidence/es-is-20261005/CORE_REFERENCE_SCENARIO.md
docs/02-evidence/es-is-20261005/ES_CSP_R01_EXECUTION/S3_COMPLETION_RECORD_20261006.md
docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_PIR_DESIGN_V0.2_20261006.md
docs/02-evidence/es-is-20261005/SIMIGO_ES_IS_SETTLED_RELATION_COUPLING_ARCHITECTURE_AUDIT_PACKAGE_20261006.md
docs/00-governance/SIMIGO_ES_IS_ARCHITECTURE_RESEARCH_DECOMPOSITION_CONTROL_20261006.md
```

## 6. Established conclusions

### 6.1 Constitutional core

```text
ES and IS are mutually coupled computational state spaces.
```

This is governance-level architecture, not yet a completed SRS-reuse
implementation or experiment.

### 6.2 Information / Relation foundation

```text
Information Identity is established.
Information is immutable.
Relation is an immutable semantic edge over InformationIDs.
Relation persistence has bounded two-store evidence.
Dependency / revision / provenance mechanisms exist at the carrier and
relation-prerequisite level.
```

### 6.3 R01 — ES Continuation Sufficiency

```text
S3                    PASS
C1                    PASS
C2                    PASS
P-POS                 PASS
N-A                   PASS
N-B                   PASS
I-1                   PASS
I-2                   PASS
C3                    OBSERVATION ONLY

Research verdict      PASS — CONTINUATION SUFFICIENT
Scope                 BOUNDED
Universal continuation   NOT ESTABLISHED
Production readiness     NOT ESTABLISHED
SRS reuse proof          NOT ESTABLISHED
```

R01 proves only that a prepared registered Information Closure was sufficient
for bounded continuation. It does not prove `ES₁ → IS → ES₂` SRS reuse.

### 6.4 U-A / CCVS

```text
Unified Carrier is established for FILE + SESSION under one contract and
guarantee set.

Information Identity ≠ Carrier Identity ≠ Representation Identity.

Revision, transaction, ledger, mapping, and provenance mechanisms are
established within U-A Gate C scope.

Gate C = CLOSED / ACCEPT.
```

U-A / CCVS support physical carrying correctness of Information Space. They do
not prove SRS reuse.

### 6.5 PIR

```text
PIR v0.2 path:
Query → Scope → Candidate Index → Relevant Objects → Physical Check →
Fresh Closure.

Query-Priority Reconciliation        PASS / ACCEPTED
PIR Design v0.2                      ACCEPTED
Clarification Addendum              ACCEPTED
F1–F5                                RESOLVED
PIR implementation                   NOT AUTHORIZED
PIR experiment                       NOT AUTHORIZED
PIR fixture                          NOT AUTHORIZED
Minimal PIR Probe v0.2               PAUSED pending central architecture ruling
```

PIR is the freshness / physical-reconciliation prerequisite architecture. It is
not SRS-reuse evidence.

## 7. Clarified but not demonstrated

### 7.1 Settled Relation State

The SRS semantic boundary is clarified but not finally closed.

```text
SRS-SEM-01 = SELECTED / NOT STARTED.
```

It must not be advanced without explicit Human instruction and acceptance.

### 7.2 Information Topology

Information Topology is canonically defined but not demonstrated as accumulating
across independent Execution States.

## 8. Unproved core claims

```text
1.  ES₂ can lawfully adopt a relation settled by ES₁.
2.  ES₂ can validate dependency / revision / freshness / provenance.
3.  Valid reuse actually avoids re-executing the settled relation.
4.  ES₂ computes only genuinely new work.
5.  Stale dependency forces block or lawful recompute.
6.  Missing provenance fails validation.
7.  Bare result alone cannot authorize lawful reuse.
8.  Information Topology can accumulate and be reused across independent ES.
```

These claims must not be inferred from R01, PIR, U-A, or RelationCore.

## 9. Current active closure task

```text
SRS-SEM-01
Minimal Settled Relation State Semantic Boundary

Status = SELECTED / NOT STARTED
```

Dependency chain:

```text
SRS-SEM-01
  ↓
SRS-VAL-01
  ↓
settlement contract
  ↓
reuse contract
  ↓
carrier-binding boundary
  ↓
minimal ES₁ → IS → ES₂ experiment design
  ↓
separate execution authorization
```

`SRS-SEM-01` must remain sufficiently abstract:

```text
do not freeze full validation algorithm;
do not freeze PIR implementation;
do not freeze carrier schema;
do not start experiment design.
```

## 10. Immediately forbidden actions

```text
do not continue SRS-SEM-01 without explicit Human instruction;
do not start SRS-VAL-01;
do not create SRS fixtures;
do not run ES₁→IS→ES₂ experiment;
do not modify RelationCore or InformationCore;
do not modify U-A, Manifest v1.1, UA v1.0, PB v1.2, or Frozen Contracts;
do not reinterpret R01 / PIR / U-A as SRS-reuse proof;
do not revive deleted branches as current state.
```

## 11. Supersession rule for old handoff text

`SESSION_HANDOFF_20261006.md` contains many chronological UPDATE paragraphs.
They are historical. If any older UPDATE conflicts with this anchor, this anchor
and the current `docs/RESEARCH_STATE.md` restored section win.
