# ES–IS Settled Relation Coupling Architecture Audit Package

> **Status:** RESEARCH / GOVERNANCE CLARIFICATION PACKAGE DELIVERED FOR HUMAN REVIEW
> **Date:** 2026-10-06
> **Commission:** `docs/00-governance/SIMIGO_ES_IS_SETTLED_RELATION_COUPLING_ARCHITECTURE_COMMISSION_20261006.md`
> **Audit baseline:** `ca3d606`
> **Scope:** corpus audit, terminology map, architecture clarification, evidence matrix, and minimum next-experiment outline only.
> **Not authorized by this package:** implementation, experiment, fixture creation, IS mutation, RelationCore/InformationCore change, U-A change, backend selection, migration, PALACE product design, MCP, MemPalace integration, remote API, or agent-framework integration.

## 1. Executive conclusion

`Settled Relation State` is **not simply an existing term being renamed**. It
is a new canonical name for a required composite state whose parts already exist
across the corpus, but whose complete bundle does not.

```text
Existing research has many prerequisites:
  immutable Information,
  immutable Relation,
  provenance,
  revision,
  durable mapping,
  transactional carriers,
  continuation closure,
  freshness design,
  and a constitutional ES↔IS loop.

Existing research does not yet have a frozen, implemented, or experimentally
demonstrated composite object that binds:
  settled result
  + original relation
  + dependency identities/revisions
  + provenance
  + freshness/validity conditions
  + reuse semantics
into one independently consumable Settled Relation State.
```

Therefore:

```text
Settled Relation State = new canonical architecture term,
                        not a mere renaming of Relation,
                        IPAC, checkpoint, or cache.
```

## 2. Audit method

The audit inspected, rather than merely keyword-searched:

```text
SimiGo Research Constitution v1.0;
ES↔IS Core Reference Scenario;
IPAC Execution State Research Synthesis;
IPAC Synthesis Closure Review;
Execution / Information Space Boundary Synthesis;
Phase 2 Relation Boundary and Persistence decisions;
CORE / U-A / R01 / PIR evidence and design records;
RelationCore and InformationCore source definitions;
U-A Unified Minimal Composition Manifest.
```

Search terms included settled relation, relation closure, relational closure,
information topology, adopt settled result, reuse, recompute, cache, dependency
revision, and freshness/provenance. Candidate hits were then read in context.

## 3. Corpus passages relevant to the commission

### 3.1 The loop is already constitutional, but not yet specialized to settled reuse

`SIMIGO_LAB_RESEARCH_CONSTITUTION_20261005.md`, Article 1, lines 25–40:

> 建立并验证一个现实可运行的、由 Execution State 与 Information Space
> 双向耦合形成的持续计算系统。

```text
Information Space
        ↓ resolve / retrieve
Execution State
        ↓ execute
Trajectory / Result / New Information
        ↓ persist / index / relate
Information Space
        ↓
Next Execution ↺
```

Lines 49–57 define the five core edges:

```text
I→S, S→I, S↔I, S→S, I→I
```

Lines 156–160 already name the eventual capability:

```text
future execution can reconstruct continuation without recomputing history
```

This supports the new architecture but does not define `Settled Relation State`.

### 3.2 The Core Reference Scenario already names cross-execution reuse

`CORE_REFERENCE_SCENARIO.md`, lines 26–42:

```text
Task T1
  ↓ Execution State S1
  ↓ resolve / retrieve F1..F4
  ↓ Trajectory T1
  ↓ execute
  ↓ Result R1
  ↓ persist / index / relate
Information Space adds R1 + provenance + relations
Task T2
  ↓ resolve R1
Execution State S2
  ↓ incremental computation
continue — without recomputing T1
```

Lines 52–56 identify this as central:

```text
R-id identifies S2 as continuation of S1.
R-an anchors S2 in IS/computation.
R-res resumes T2 using R1 without recomputing T1.
```

This is conceptual support, not an executed cross-ES reuse experiment.

### 3.3 IPAC already asked the exact adoption question

`SIMIGO_LAB_IPAC_EXECUTION_STATE_RESEARCH_SYNTHESIS_20261003.md`, Q3, lines
114–125:

```text
When may a state adopt a settled result without recomputation?

the prior result is addressable;
the prior computation is settled;
the result is provable from persistent Information / provenance;
the result is semantically compatible with the current task;
the current Execution State can reference it without re-deriving it;
continuation conditions are satisfied.
```

The same document states that this candidate is not formalized or experimentally
tested.

### 3.4 The synthesis model already had adopt / recompute branches

`SIMIGO_LAB_IPAC_SYNTHESIS_CLOSURE_REVIEW_20261003.md`, lines 16–28:

```text
Persistent Information Space
  history / provenance / settled result / relation / anchors
        ↓ resolve / validate
Execution State
        ↓ continuation decision
Adopt settled result → Continue
Cannot adopt         → Recompute / Reject
```

Lines 50–58 define Persistent Information Space as containing continuation-
relevant information outside current Execution State.

### 3.5 Boundary Synthesis later restated the adoption gate

`SIMIGO_LAB_EXECUTION_INFORMATION_SPACE_BOUNDARY_SYNTHESIS_20261003.md`, lines
140–157:

```text
When a new Execution State enters an Information Space, under what conditions
may it directly adopt a settled result and continue, rather than recompute?

Does C' satisfy R's applicability conditions?
  yes → adopt R → continue
  no  → recompute / reject
```

The document explicitly marks this nonbinding and requiring later formalization.

### 3.6 Relation semantics are already frozen narrowly

`SIMIGO_LAB_PHASE2_RELATION_DECISIONS_SEALED_20261002.md`, D1–D3:

```text
Relation = directed triple over two InformationIDs + provenance.
RelationID = opaque, deterministic, mechanism-side.
Relation = immutable; temporal mutation fields are not part of Phase 2.
```

`SIMIGO_LAB_PHASE2_RELATION_PERSISTENCE_SEMANTICS_GATE_RESULT_20261002.md`,
lines 24–26:

```text
PASS R1–R6 contract on SQLiteRelationStore
PASS R1–R6 contract on InMemoryRelationStore
PASS cross-backend: one Relation identity, two filings, one semantic fact
```

This supports Relation-as-edge, but not Settled Relation State, because Phase 2
deliberately excluded temporal validity, mutation, traversal, ranking, and
business semantics.

### 3.7 U-A already provides durable mapping/revision/provenance infrastructure

`PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UA_UNIFIED_MINIMAL_COMPOSITION_MANIFEST_20261006.md`,
lines 90–118:

```text
One walkable chain, provenance-bearing at every hop:
InformationID → CC-5 mapping → carrier → representation → bytes.

Backward:
bytes → digest → representation → record → CC-5 mappings → Information.

Mapping is append/annotate only; corrections are new entries with provenance;
history is never rewritten.
```

This supports persistence and validation prerequisites, not relation-reuse
semantics.

### 3.8 R01 proved continuation sufficiency, not cross-ES settlement reuse

`ES_CSP_R01_EXECUTION/S3_COMPLETION_RECORD_20261006.md`:

```text
S3 EXECUTED
research verdict PASS — CONTINUATION SUFFICIENT / BOUNDED
P-POS    C1 PASS / C2 CONTINUE_CERTAIN
N-A      blocked on unresolved input reference
N-B      blocked on ambiguous pointer set
C3       NOT_PERFORMED / OBSERVATION_ONLY
```

R01's fixtures tested continuation from a prepared registered closure. They did
not create an `ES₁`-computed relation, persist it as Settled Relation State,
then require independent `ES₂` to validate and reuse it while proving
non-recomputation.

### 3.9 PIR is accepted design, not executed reconciliation evidence

`PALACE_INFORMATION_SPACE_FOUNDATION_PIR_DESIGN_V0.2_20261006.md` defines
Query-Priority Reconciliation, Query Scope, Fresh Closure, and ICAC.

No PIR implementation, fixture, or experiment is authorized. Therefore PIR is a
freshness prerequisite design, not evidence that a settled relation has been
reused across Execution States.

## 4. Terminology map

| Existing term | Canonical destination | Difference |
|---|---|---|
| Execution State | `Execution State` | remains the computation/control side; now explicitly consumes and extends topology |
| Information | `Information` node | remains immutable addressable information object |
| Relation | `Relation` / semantic edge | remains immutable directed relation between InformationIDs |
| Settled result | `Settled Relation State.result` | result alone is insufficient; must be bundled with relation/dependencies/validity |
| IPAC candidate adoption relation | `SRS Reuse Validation Predicate` | prior nonbinding conditions become the core reuse predicate |
| Persistent Information Space | `Information Space` | remains lawful external state; now contains accumulated topology |
| Checkpoint | not `Settled Relation State` | checkpoint is runtime-state capture; SRS is semantically reusable settlement |
| Cache | not `Settled Relation State` | cache emphasizes opaque value lookup; SRS requires relation, dependency, revision, provenance, and freshness |
| Knowledge graph | not `Information Topology` | topology is accumulated by ES computation, not independently designed ontology |
| Freshness / Revision / Provenance | `SRS validity conditions` | prerequisites become edge-validity conditions of settled state |

## 5. Is `Settled Relation State` new?

Conclusion:

```text
NEW CANONICAL TERM OVER EXISTING PARTS.
NOT A RENAMING OF ANY SINGLE EXISTING OBJECT.
NOT AN EXISTING IMPLEMENTED TYPE.
```

It is new because no audited document freezes a single object with all required
fields. It is not wholly foreign because its conditions were anticipated by:

```text
IPAC adoption conditions;
Core Reference Scenario reuse moment;
RelationCore immutable edge semantics;
U-A provenance/revision/mapping;
Constitution ES↔IS loop.
```

## 6. Canonical definitions

### 6.1 Information

```text
Information is an immutable, addressable information object in Information
Space.
```

It provides identity and content/semantic object boundary. It is a topology
node.

### 6.2 Relation

```text
Relation is an immutable directed semantic edge between Information objects:
subject → predicate → object, with provenance.
```

It expresses dependency or constraint. It does not by itself record settlement,
dependency revision set, validity interval, or reuse decision.

### 6.3 Settled Relation State

Canonical minimum:

```text
Settled Relation State =
(
  settlement_id,
  result,
  source_relation,
  dependency_set,
  provenance,
  validity_conditions,
  freshness_conditions,
  relation_semantics,
  settlement_status
)
```

Required fields:

```text
result
  derived state or formed Information produced by ES.

source_relation
  the relation/computation contract being settled.

dependency_set
  each dependency as:
    InformationID / selected revision or representation binding;
    required role;
    content or representation digest where required.

provenance
  producing ES identity;
  operation identity;
  settlement time;
  input/output evidence chain.

validity_conditions
  conditions under which reuse is lawful.

freshness_conditions
  age, revision equality, dependency freshness, policy, or PIR checks.

relation_semantics
  sufficient meaning for another ES to know what was settled and how it may be
  consumed.

settlement_status
  SETTLED / SUPERSEDED / INVALIDATED / CONTESTED / INDETERMINATE.
```

Hard exclusions:

```text
Settled Relation State ≠ opaque cache entry.
Settled Relation State ≠ bare result.
Settled Relation State ≠ mutable relation.
Settled Relation State ≠ runtime checkpoint.
Settled Relation State ≠ generic knowledge-graph edge.
```

Mutation rule:

```text
An SRS is append-only.
Invalidation, supersession, or freshness change creates a new SRS/status record
referencing the prior SRS. Existing SRS is not silently rewritten.
```

### 6.4 Information Topology

```text
Information Topology is the accumulated directed structure formed by:
  Information nodes;
  Relation edges;
  Settled Relation State edges;
  dependency/revision/freshness/provenance validity conditions;
  and the Execution State provenance that produced them.
```

Formal minimum:

```text
Nodes       = Information objects.
Edges       = Relation or Settled Relation State.
Edge labels = relation semantics / settlement semantics.
Edge validity = dependency revision + freshness + provenance + policy.
Growth      = Execution State consumes/validates prior topology and settles new
              relations into it.
```

Information Topology is not:

```text
an independently designed ontology;
a generic knowledge graph product;
a similarity graph;
a vector index;
a PALACE implementation.
```

## 7. Canonical architecture invariant

```text
Execution State and Information Space are mutually coupled computational state
spaces.

Execution State resolves and validates Information Topology, performs model or
relation computation, and settles new relations.

Information Space persists those settlements as Settled Relation State with
result, source relation, dependency revisions, provenance, freshness, and reuse
semantics.

A later, independent Execution State must validate and consume a lawful Settled
Relation State without recomputing it, compute only genuinely new work, and
settle the resulting delta back into Information Topology.
```

Canonical loop:

```text
Information Topology
  → resolve candidate Settled Relation State
  → validate dependencies / revisions / freshness / provenance
  → if valid: consume settled relation
  → if invalid: reject / recompute lawfully
  → Execution State computes only Δ
  → settle new relation/state
  → persist into Information Topology
  → next Execution State
```

## 8. Core falsifiable question

> Can a Settled Relation State produced by `ES₁` become lawful reusable
> computational state for an independent `ES₂`, such that `ES₂` validates its
> relation, dependencies, revisions, provenance, and freshness; consumes the
> settled relation without recomputing it; computes only genuinely new work; and
> correctly refuses reuse when a dependency is stale, invalid, or conflicted?

## 9. Falsifiable hypothesis

### H1 — lawful reuse

If a complete SRS is persisted by `ES₁`, then an independent `ES₂` that validates
all dependency revisions and freshness conditions can consume the settled result
and produce the pre-registered downstream continuation while its execution trace
shows no recomputation of the settled relation.

### H2 — invalidation safety

If any required dependency revision, digest, freshness condition, or provenance
link is invalid, then `ES₂` must reject the SRS and enter lawful recompute or
block; it must not consume the stale relation as fresh.

### H3 — non-cache distinction

Removing or altering the SRS relation/dependency/provenance/freshness bundle
while preserving only the bare result must make lawful reuse impossible even if
the bare result value remains available.

H3 is the key distinction from ordinary cache hit.

## 10. Evidence matrix

Status legend:

```text
ESTABLISHED          executed/accepted within its own bounded scope.
PARTIAL              supporting concept, design, or bounded evidence exists.
NOT ESTABLISHED      required core claim has not been demonstrated.
```

| Claim | Status | Evidence | Boundary |
|---|---|---|---|
| ES↔IS loop is the constitutional core | ESTABLISHED as governance | Research Constitution Article 1 | conceptual North Star, not implementation |
| ES continuation depends on Information Closure | ESTABLISHED / BOUNDED | R01 S3 PASS | prepared closure, one task lineage, no SRS reuse |
| New ES can adopt a settled result without recomputation | NOT ESTABLISHED | IPAC Q3 and Boundary Synthesis asked it | explicitly nonbinding and untested |
| Relation is immutable semantic edge over InformationIDs | ESTABLISHED | Phase 2 D1–D3; R1–R6 PASS | no temporal mutation, traversal, ranking, or settlement semantics |
| Relation persistence is lawful across two stores | ESTABLISHED / BOUNDED | R1–R6 PASS | harness-bound evidence; no SRS |
| Information identity is immutable and distinct from carrier/representation | ESTABLISHED | InformationCore + U-A CC-8 | no SRS dependency-set semantics |
| Carrier mappings/ledger can preserve provenance and revisions | ESTABLISHED / BOUNDED | U-A CC-5 / CC-8 / MA-7 / MA-8 | no relation-reuse semantics |
| Derived state can be durably and transactionally persisted | ESTABLISHED / BOUNDED | U-A Gate C acceptance | no cross-ES reuse test |
| Freshness can be query-scoped | DESIGN ACCEPTED, NOT DEMONSTRATED | PIR v0.2 + Addendum | no implementation/run |
| SRS bundle is already implemented | NOT ESTABLISHED | corpus audit | required composite absent |
| `ES₁ → IS → ES₂` relation reuse avoids recomputation | NOT ESTABLISHED | none found | core next experiment |
| Invalid dependency forces lawful recompute/block | NOT ESTABLISHED | none found | required negative arm |
| Bare result without SRS bundle is insufficient for lawful reuse | NOT ESTABLISHED | none found | H3 cache distinction |
| Information Topology accumulates across independent ES | NOT ESTABLISHED | conceptual only | topology growth untested |

## 11. Relationship to prior results without scope expansion

```text
ES runtime / IPAC
  prerequisite: ES has continuation-control semantics and relation-closure
  candidates.

R01
  prerequisite: a prepared registered Information Closure can make ES
  continuation lawful.

PIR
  prerequisite design: relevant Information can be brought to a prescribed
  freshness state at query time.

U-A / CCVS
  prerequisite: Information, carrier, representation, revision, mapping,
  ledger, and provenance can be durably and consistently managed.

RelationCore
  prerequisite: immutable semantic edges between Information objects.

These do not jointly prove ES₁ → IS → ES₂ settled-relation reuse.
```

## 12. Minimum next experiment outline

This is an outline only. It is not authorization.

### 12.1 Research object

```text
ES₁ computes and settles one relation R₁.
IS persists SRS(R₁).
An independent ES₂ later resolves SRS(R₁), validates it, and continues.
```

The experiment must use two logically independent Execution State contexts.
They may share only the lawful Information Space surface, not runtime process,
agent memory, hidden cache, or implementation singleton.

### 12.2 Required SRS fixture

`SRS(R₁)` must contain:

```text
result R₁;
source relation;
dependencies A@revision and B@revision;
provenance for ES₁;
freshness/validity conditions;
relation semantics;
settlement status.
```

Control `bare-result` must preserve only `R₁` and omit relation, dependency
revision, provenance, or freshness conditions.

### 12.3 Arms

```text
ARM-A VALID REUSE
  dependencies unchanged;
  freshness valid;
  ES₂ validates SRS and consumes R₁;
  ES₂ computes only ΔR₂.

ARM-B STALE DEPENDENCY
  required dependency revision or digest changes;
  ES₂ must reject SRS and lawfully recompute or block.

ARM-C MISSING PROVENANCE
  SRS provenance or source-relation link absent;
  ES₂ must refuse lawful reuse.

ARM-D BARE RESULT CONTROL
  only R₁ exists;
  ES₂ must not claim lawful reuse merely from result equality.

ARM-E INDEPENDENCE CONTROL
  ES₂ has no access to ES₁ runtime/process/memory;
  only lawful IS surface is shared.
```

### 12.4 Required measurements

```text
M1  validation decision: CONSUME / RECOMPUTE / BLOCK.
M2  whether R₁ computation op was re-executed.
M3  downstream result/continuation equality against pre-registered expectation.
M4  validation evidence read from SRS fields.
M5  invalidation reason for negative arms.
M6  independent-ES evidence: no shared runtime/process/memory path.
M7  cost vector:
      validation cost, reuse cost, recompute cost, Δ computation cost.
```

### 12.5 PASS conditions

```text
ARM-A  validate CONSUME; no R₁ recompute; downstream expectation holds.
ARM-B  validate RECOMPUTE or BLOCK; stale R₁ not consumed as fresh.
ARM-C  reject for missing lawful settlement evidence.
ARM-D  bare result does not authorize lawful reuse.
ARM-E  independence holds.
```

### 12.6 FAIL conditions

```text
ARM-A consumes stale/invalid SRS.
ARM-B consumes stale dependency.
ARM-C accepts missing provenance.
ARM-D treats bare result as settled state.
ARM-E secretly shares runtime/cache/process state.
Any arm lacks enough evidence to distinguish reuse from cache hit.
```

## 13. Documents requiring amendment or supersession

No frozen contract is amended by this package.

The following should later carry forward pointers to the new architecture:

```text
docs/RESEARCH_CONTEXT_INDEX.md
docs/RESEARCH_STATE.md
docs/00-governance/SESSION_HANDOFF_20261006.md
docs/02-evidence/es-is-20261005/CORE_REFERENCE_SCENARIO.md
IPAC synthesis records
R01 completion record
PIR Design v0.2 and Minimal PIR Probe records
future experiment register
```

The amendments should only add:

```text
Settled Relation State;
Information Topology;
ES₁→IS→ES₂ reuse gap;
pointer to this package.
```

They must not reinterpret R01 or PIR as already proving SRS reuse.

## 14. Governance conclusion

```text
Implementation                 NOT AUTHORIZED.
Experiment                     NOT AUTHORIZED.
Fixture creation               NOT AUTHORIZED.
IS mutation                    NOT AUTHORIZED.
RelationCore change            NOT AUTHORIZED.
InformationCore change         NOT AUTHORIZED.
U-A change                     NOT AUTHORIZED.
Frozen Contract change         NOT AUTHORIZED.
Backend selection              NOT AUTHORIZED.
PALACE product design          NOT AUTHORIZED.
MemPalace integration          NOT AUTHORIZED.
MCP / remote API               NOT AUTHORIZED.
```

The next lawful step is Human review of this package. If accepted, the separate
next artifact should be a detailed Minimal `ES₁ → IS → ES₂` Settled Relation
Reuse Experiment Design.
