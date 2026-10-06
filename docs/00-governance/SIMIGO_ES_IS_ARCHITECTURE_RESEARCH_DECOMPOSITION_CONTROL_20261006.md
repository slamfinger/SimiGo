# ES–IS Architecture Research Decomposition Control

> **Status:** DECOMPOSITION / CONTROL ARTIFACT DELIVERED FOR HUMAN REVIEW
> **Date:** 2026-10-06
> **Issue:** [slamfinger/SimiGo-Lab#2 — ES-IS architecture research decomposition and next closure task](https://github.com/slamfinger/SimiGo-Lab/issues/2)
> **Baseline:** ES–IS Settled Relation Coupling Architecture Audit Package at `6b99642`
> **Commission lineage:** `ca3d606`
> **Overall invariant:** `ES₁ settles relation → Information Space persists SRS → independent ES₂ validates and reuses it → only Δ is computed → new settlement`.
> **Boundary:** decomposition and next-closure selection only. No implementation, fixture, filesystem trial, IS mutation, experiment, or Frozen Contract change is authorized.

## 1. Purpose and non-purpose

This artifact converts the accepted Audit Package into a controlled research
sequence. It does **not** create a new research task tree, product architecture,
implementation plan, or governance system.

It answers four questions:

```text
1. What is already closed?
2. What is prerequisite evidence rather than core proof?
3. What is architecture-clarified but not demonstrated?
4. What is the one smallest next closure task?
```

It then stops. The selected next task still requires its own design artifact and
Human acceptance.

## 2. Historical lineage guard

The central ES–IS Settled Relation State / Information Topology architecture was
not assumed at project origin. It was progressively distilled:

```text
2026-10-02  Phase 2 seals Relation as an immutable directed semantic edge
            over InformationIDs, with provenance and no temporal mutation.

2026-10-03  IPAC synthesis asks when a later state may adopt a settled result
            without recomputation; Boundary Synthesis restates the adopt /
            recompute gate as nonbinding.

2026-10-05  Research Constitution makes ES↔IS mutual coupling the North Star
            and defines the closure loop.

2026-10-05  Core Reference Scenario formalizes T1→R1→T2 and names reuse
            without recomputation as the capability-delta moment.

2026-10-06  R01 proves bounded continuation from a prepared Information
            Closure.

2026-10-06  PIR v0.2 + Addendum accepts query-time freshness, Query Scope,
            and Fresh Closure as prerequisite design.

2026-10-06  Audit Package separates prerequisites from the still-unproven
            ES₁→IS→ES₂ Settled Relation Reuse claim.

2026-10-06  This artifact decomposes the remaining gap without claiming that
            the architecture was known from day one.
```

Therefore this artifact must not be read as retroactive architecture history.

## 3. Controlled research position

### 3.1 Established / closed

| Claim | Status | Boundary |
|---|---|---|
| ES↔IS mutual coupling is the constitutional research spine | ESTABLISHED as governance | North Star, not implementation |
| T1→R1→T2 reuse is the Core Reference Scenario | ESTABLISHED as governance | conceptual scenario, not executed SRS proof |
| Information is immutable and addressable | ESTABLISHED / BOUNDED | InformationCore semantics |
| Relation is an immutable directed semantic edge between InformationIDs | ESTABLISHED / BOUNDED | Phase 2 D1–D3; no temporal mutation or traversal semantics |
| Relation persistence works across two bounded stores | ESTABLISHED / BOUNDED | R1–R6 evidence |
| U-A carrier/revision/mapping/provenance machinery is durable and transactional | ESTABLISHED / BOUNDED | U-A Gate C scope only |
| A prepared registered Information Closure can support bounded continuation | ESTABLISHED / BOUNDED | R01 only; no SRS reuse proof |
| Query-time freshness and Query Scope are valid PIR design prerequisites | DESIGN ACCEPTED | PIR v0.2 + Addendum; no implementation/run |

### 3.2 Prerequisite evidence, not central proof

| Evidence | Supports | Does not prove |
|---|---|---|
| ES runtime / IPAC | ES has continuation-control and relation-closure candidates | lawful cross-ES adoption of settled results |
| R01 | prepared Information Closure can make continuation lawful | ES₁-computed SRS can be independently reused |
| PIR v0.2 | relevant Information can be designed for query-time freshness | freshness has been implemented or executed |
| U-A / CCVS | Information, carrier, representation, revision, ledger, provenance can be durably managed | relation reuse or settlement semantics |
| RelationCore | immutable semantic edges exist over Information objects | dependency revisions, freshness, settlement status, or reuse predicate |
| Constitution / Core Scenario | the target loop and reuse moment | implementation or experimental demonstration |

### 3.3 Architecture clarified but not demonstrated

| Clarified object | Current status |
|---|---|
| `Settled Relation State` | canonical composite defined in Audit Package; not implemented or demonstrated |
| `Information Topology` | canonical accumulated Information + Relation/SRS structure; not experimentally demonstrated |
| ES₁→IS→ES₂ reuse loop | architecture clarified; central claim NOT ESTABLISHED |
| Lawful reuse predicate | conceptually anticipated by IPAC; not formalized or tested |
| Invalidation / stale-dependency behavior | required future claim; not demonstrated |
| Bare-result insufficiency | required cache-distinction claim; not demonstrated |

### 3.4 Open gaps

These are decomposition nodes, not a new task tree. They are ordered by logical
dependency only.

```text
G1  Minimal Settled Relation State semantic boundary.
G2  SRS Reuse Validation Predicate.
G3  ES→IS settlement contract.
G4  IS→ES reuse contract.
G5  Durable SRS carrier-binding boundary.
G6  Minimal ES₁→IS→ES₂ reuse experiment design.
G7  ES₁→IS→ES₂ reuse experiment execution.
```

PIR v0.2 remains an accepted freshness-prerequisite design. Minimal PIR Probe
v0.2 is paused pending the central architecture ruling; it is not promoted back
by this artifact.

## 4. Selected next smallest closure task

```text
Task ID       SRS-SEM-01
Name          Minimal Settled Relation State Semantic Boundary
Selection     ONE smallest next closure task
Type          design / governance clarification only
Status        OPENED BY HUMAN AFTER RECOVERY CLOSURE — DESIGN V0.1 DELIVERED FOR REVIEW
```

### 4.1 Task statement

Define and freeze the smallest lawful semantic boundary of `Settled Relation
State`.

It must answer:

```text
1. Which fields are semantically required?
2. Which fields are carrier or implementation details, not SRS semantics?
3. How does SRS differ from:
     bare result;
     cache entry;
     runtime checkpoint;
     immutable Relation;
     generic knowledge-graph edge?
4. What are the immutable/append-only and supersession rules?
5. What is the minimum dependency representation?
6. What validity/freshness fields must exist semantically, without implementing
   a freshness engine?
7. What must remain undefined until the later validation-predicate task?
```

### 4.2 Why this is the smallest task

Every later node depends on this boundary:

```text
SRS Reuse Validation Predicate
  cannot be formalized until SRS fields and validity conditions are frozen.

ES→IS settlement contract
  cannot define what ES writes until SRS semantics are fixed.

IS→ES reuse contract
  cannot define what ES₂ validates until SRS semantics are fixed.

Durable SRS carrier binding
  cannot decide representation needs until semantic fields are separated from
  carrier details.

Minimal ES₁→IS→ES₂ experiment
  cannot define arms, evidence, or non-recomputation checks until the above
  contracts exist.
```

Therefore `SRS-SEM-01` is smaller and prior to validation, carrier, settlement,
reuse, and experiment tasks.

### 4.3 Prerequisites

No new implementation or experiment prerequisite is required.

Existing prerequisites:

```text
ES–IS Settled Relation Coupling Architecture Audit Package;
Research Constitution ES↔IS loop and Core Reference Scenario;
IPAC Q3 adoption conditions;
Phase 2 Relation D1–D3 and R1–R6;
U-A provenance/revision/mapping boundaries;
R01 bounded continuation result;
PIR v0.2 freshness vocabulary.
```

### 4.4 Required artifact

One design artifact:

```text
SIMIGO_ES_IS_SRS_SEMANTIC_BOUNDARY_DESIGN_V0.1.md
```

It must contain:

```text
canonical SRS field set;
required vs implementation-specific fields;
immutable / append-only rules;
supersession and invalidation reference rules;
minimum dependency representation;
relation-versus-SRS distinction;
result-versus-SRS distinction;
cache-versus-SRS distinction;
checkpoint-versus-SRS distinction;
explicit undefined-until-later list;
positive and negative examples;
human review questions.
```

It must not:

```text
define Swift/SQLite structures;
select a backend;
create schema;
modify RelationCore or InformationCore;
implement validation;
authorize IS mutation;
run an experiment;
reinterpret R01 or PIR.
```

### 4.5 Completion criterion

`SRS-SEM-01` is complete only when:

```text
1. the dedicated semantic-boundary design exists;
2. it preserves Audit Package lineage and does not claim prior proof;
3. it separates semantic fields from carrier/implementation fields;
4. it distinguishes SRS from result, cache, checkpoint, Relation, and generic
   graph edge;
5. it defines append/supersession rules without mutating history;
6. it explicitly defers the operational reuse-validation predicate;
7. Human rules the design ACCEPTED.
```

No implementation or experiment is authorized by completion.

### 4.6 Next dependency

After Human acceptance, the next candidate closure task is:

```text
SRS-VAL-01  Settled Relation State Reuse Validation Predicate
```

It may then define:

```text
CONSUME / RECOMPUTE / BLOCK decision inputs;
dependency revision equality rules;
freshness checks;
provenance completeness checks;
typed rejection reasons;
and the distinction between lawful reuse and cache hit.
```

Its own acceptance will still require Human review.

## 5. Control rule

The active central queue is:

```text
NOW      Human review of Recovery Anchor closure and this control artifact.
DONE     Human authorized SRS-SEM-01 after Recovery Anchor closure.
DELIVERED SRS-SEM-01 Design v0.1.
NEXT     Human review SRS-SEM-01 Design v0.1.
THEN     If accepted, prepare SRS-VAL-01 design only.
LATER    Settlement, reuse, carrier, and experiment designs remain gated.
```

No task may be started merely because it appears in the gap list.
