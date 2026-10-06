# SimiGo-Lab Research State / Memory Recovery Anchor

> **Status:** RECOVERY ANCHOR
> **Recovery baseline:** GitHub `slamfinger/SimiGo-Lab@main` = `0508e26`
> **Research-state content revision:** `bcc6b81`
> **Metadata correction:** this commit; verify current `main` dynamically with `git rev-parse HEAD`
> **Post-closure authorization:** Human later opened `SRS-SEM-01`; verify current state dynamically. See `SRS-SEM-01 Design v0.1`.
> **Date:** 2026-10-06
> **Canonical source:** GitHub `slamfinger/SimiGo-Lab@main`
> **Purpose:** restore research state and research-memory entry without relying on chat memory, deleted branches, or superseded handoff paragraphs.
> **Boundary:** recovery only. This anchor does not start `SRS-SEM-01`, create a new mission/task tree, authorize implementation, fixture creation, experiment, IS mutation, or code change.
> **Post-anchor update:** Human later opened, reviewed, and froze `SRS-SEM-01`; `SRS-VAL-01` design is now the active design-only task.

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

The SRS semantic boundary is clarified, accepted, and frozen.

```text
SRS-SEM-01 was originally SELECTED / NOT STARTED.
Human later explicitly opened it after Recovery Anchor closure.
After iterative review, Design v0.5 is ACCEPT / FROZEN.
Accepted design artifact:
`docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_SEM_01_DESIGN_V0.5_20261007.md`.
Current commissioned design:
`docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_V0.7_20261007.md`.
Authorization package status = ACCEPT / FROZEN; next stage NOT OPENED.
Implementation Boundary Audit v0.1 = ACCEPT / FROZEN.
Manifest Contract v0.1 = REVISE / SUPERSEDED BY V0.2.
Manifest Contract v0.2 = REVISE / SUPERSEDED BY V0.3.
Manifest Contract v0.3 = REVISE / SUPERSEDED BY V0.4.
Manifest Contract v0.4 = REVISE / SUPERSEDED BY V0.5.
Manifest Contract v0.5 = REVISE / SUPERSEDED BY V0.6.
Manifest Contract v0.6 = REVISE / SUPERSEDED BY V0.7.
Current manifest contract = Run/Implementation Manifest v0.7 DELIVERED FOR HUMAN REVIEW.
Accepted and frozen SRS-VAL design:
`docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_DESIGN_V0.8_20261007.md`.
Superseded SRS-VAL-01 design lineage:
V0.1 through V0.7 = REVISE / SUPERSEDED BY SUCCESSIVE REVISIONS.
```

The SRS-VAL authorization-package governance closure is complete. The current
object is the Run/Implementation Manifest contract. Implementation, fixture
preparation, execution, and experiment remain unauthorized.

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
SRS-VAL-01
Run/Implementation Manifest Contract

Status = MANIFEST V0.1 REVISE / MANIFEST V0.2 REVISE / MANIFEST V0.3 REVISE /
         MANIFEST V0.4 REVISE / MANIFEST V0.5 REVISE / MANIFEST V0.6 REVISE /
         MANIFEST V0.7 DELIVERED FOR HUMAN REVIEW — DESIGN ONLY
       + PACKAGE V0.1 REVISE / PACKAGE V0.2 REVISE / PACKAGE
         V0.3 REVISE / PACKAGE V0.4 REVISE / PACKAGE V0.5 REVISE / PACKAGE V0.6
         ACCEPT / FROZEN
       + SRS-VAL Design v0.8 ACCEPT / FROZEN

Next lawful object =
  Human review of Run/Implementation Manifest v0.7; no stage authorized

Current design document =
  docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_V0.7_20261007.md
```

Dependency chain:

```text
SRS-SEM-01
  ↓
SRS-VAL-01
  ↓
implementation / fixture / execution authorization package
  ↓
settlement contract
  ↓
reuse contract
  ↓
carrier-binding boundary
  ↓
minimal ES₁ → IS → ES₂ experiment design
  ↓
separate implementation / fixture / experiment authorization
```

`SRS-VAL-01` remains design-only:

```text
do not implement validation;
do not create fixtures;
do not run experiment;
do not mutate IS.
```

## 10. Immediately forbidden actions

```text
do not continue SRS-VAL-01 beyond the explicitly authorized design;
do not implement SRS-VAL-01;
do not create SRS-VAL fixtures;
do not run SRS-VAL experiment;
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
