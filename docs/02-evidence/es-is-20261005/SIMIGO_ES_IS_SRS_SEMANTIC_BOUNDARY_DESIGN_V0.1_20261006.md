# Settled Relation State Semantic Boundary — SRS-SEM-01 Design v0.1

> **Status:** DESIGN V0.1 DELIVERED FOR HUMAN REVIEW — SRS-SEM-01 DESIGN CLOSURE CANDIDATE
> **Date:** 2026-10-06
> **Authorization:** Human opened `SRS-SEM-01` after Recovery Anchor closure at `57bc393`.
> **Task:** define the minimum semantic boundary of `Settled Relation State`.
> **Scope guard:** semantic boundary only. No implementation, schema, backend, fixture, experiment, IS mutation, RelationCore/InformationCore change, U-A change, Frozen Contract change, validation algorithm, PIR implementation, or user-file mutation is authorized.

## 1. Purpose

This design freezes the semantic boundary of `Settled Relation State`.

It answers:

```text
What must an ES-created settled relation mean,
independent of storage, carrier, API, schema, runtime, or validation algorithm?
```

It does **not** define:

```text
the operational reuse-validation algorithm;
PIR implementation;
carrier/database schema;
Swift/SQLite types;
storage API;
relation-query implementation;
experiment fixture;
runtime execution;
business-judgment policy.
```

## 2. Inherited baseline

This design inherits:

```text
Research Constitution ES↔IS loop;
Core Reference Scenario T1→R1→T2;
IPAC Q3 adoption conditions;
Phase 2 Relation D1–D3 and R1–R6;
U-A provenance / revision / mapping boundaries;
R01 bounded continuation result;
PIR v0.2 freshness vocabulary;
ES–IS Settled Relation Coupling Audit Package;
Recovery Anchor at `57bc393`.
```

## 3. Canonical definition

```text
Settled Relation State is an immutable, addressable semantic settlement record.

It records that an Execution State lawfully settled a source relation under a
specific dependency state, producing a result/state that a later Execution State
may consume only after validating the recorded dependency, revision, provenance,
validity, and freshness conditions.
```

Short form:

```text
SRS = settled result + source relation + dependency state + provenance +
      validity/freshness conditions + relation semantics + settlement status.
```

## 4. Required semantic fields

The semantic boundary requires all nine fields below.

| Field | Semantic requirement |
|---|---|
| `settlement_id` | stable, addressable identity for this settlement instance |
| `settlement_status_birth` | initial semantic status; normally `SETTLED` |
| `source_relation` | the relation or computation contract being settled |
| `result_state` | derived result/state produced by settlement |
| `dependency_set` | lawful input/assumption/policy dependencies with identity and revision bindings |
| `provenance` | producing ES, operation evidence, settlement evidence, input/output linkage |
| `validity_conditions` | conditions under which reuse remains semantically lawful |
| `freshness_conditions` | revision, age, source-state, or policy conditions requiring later validation |
| `relation_semantics` | sufficient meaning for another ES to know what was settled and how it may be consumed |

### 4.1 `settlement_id`

```text
settlement_id identifies this exact settlement instance.

It is semantic and addressable.
It is not a path, table key, serialization UUID requirement, or cache key.
```

Requirements:

```text
one settlement_id identifies one immutable settlement instance;
it remains stable when storage representation changes;
it does not encode business meaning;
it can be referenced by later ES and topology records.
```

### 4.2 `settlement_status_birth`

The birth status records the semantic state at creation.

```text
SETTLED
  the source relation was lawfully completed by an Execution State.
```

This design does not mutate that status.

Later lifecycle transitions belong to append-only status records:

```text
SRS_STATUS_SUPERSEDED
SRS_STATUS_INVALIDATED
SRS_STATUS_CONTESTED
SRS_STATUS_FRESHNESS_RECHECK_REQUIRED
```

Current status is derived from the original SRS plus its append-only lifecycle
records. The original SRS is never rewritten.

### 4.3 `source_relation`

`source_relation` records what relation or computation contract was settled.

Minimum semantic content:

```text
relation semantic type / predicate;
subject or input roles;
object or output role;
relation applicability boundary;
relation version or semantics version.
```

It may reference an existing immutable Relation, but a Relation alone is not
enough to form SRS.

### 4.4 `result_state`

`result_state` is the settled derived state or formed Information produced by the
source relation.

Minimum semantic requirement:

```text
the result must be addressable or semantically identifiable;
the result must be distinguishable from the SRS itself;
the result must be interpretable under `relation_semantics`;
the result must be linked to the same settlement provenance.
```

A bare result value is not an SRS.

### 4.5 `dependency_set`

The dependency set records the lawful input state used by settlement.

Each dependency must have:

```text
dependency_role
  input, assumption, policy, context, model state, or other semantically
  required role.

information_id
  the Information object on which settlement depends.

revision_binding
  the selected Information revision or semantically equivalent immutable
  revision binding.

integrity_binding
  a semantic integrity handle such as content digest or equivalent immutable
  evidence, when required by the relation semantics.

necessity
  required or conditional.

freshness_class
  what kind of later validation is semantically required.
```

The dependency set need not describe physical storage. Paths, tables, indexes,
carrier IDs, and serialization are implementation details unless they are part of
the relation semantics.

### 4.6 `provenance`

Minimum provenance:

```text
producing_es_identity
producing_operation_evidence
input_dependency_evidence
result_evidence
settlement_time_or_ordering_evidence
settlement_actor_or_process_class
```

Provenance must be sufficient to distinguish:

```text
lawful settlement from accidental result storage;
one settlement instance from another;
independent ES settlement from runtime-process reuse;
original SRS from later supersession.
```

### 4.7 `validity_conditions`

Validity conditions state when reuse remains semantically lawful.

They may include:

```text
dependency revision equality;
dependency integrity equality;
relation semantics version;
applicability boundary;
scope conditions;
policy constraints;
explicit exclusion conditions.
```

This design defines only that the conditions must exist and be interpretable. It
does not define the later validation algorithm.

### 4.8 `freshness_conditions`

Freshness conditions state what must be checked before reuse.

Semantic classes may include:

```text
dependency unchanged;
source objects still lawfully addressable;
revision current;
physical observation fresh enough under PIR policy;
no supersession record;
no invalidation record;
no unresolved conflict.
```

This design does not select a PIR implementation or numeric freshness window.

### 4.9 `relation_semantics`

`relation_semantics` must give a later ES enough meaning to know:

```text
what relation was settled;
what roles the dependencies played;
what the result means;
under what boundary the settlement applies;
what kind of downstream use is semantically intended.
```

It does not authorize business judgment.

## 5. Immutable and append-only rules

```text
I-1  An SRS instance is immutable.
I-2  A later SRS is a new settlement instance, not an in-place rewrite.
I-3  Lifecycle status changes are append-only status records.
I-4  Supersession references the old `settlement_id`.
I-5  Invalidation references the reason and evidence.
I-6  Historical SRS remains readable for audit.
I-7  Deletion is not part of semantic settlement.
```

Therefore:

```text
original SRS status     = birth status;
current SRS status      = birth status + append-only lifecycle records.
```

## 6. Boundary distinctions

### 6.1 SRS versus bare result

```text
Bare result:
  137

SRS:
  result 137
  + source relation sum(A,B)
  + A@revision-12
  + B@revision-7
  + producing ES and operation evidence
  + validity/freshness conditions
  + relation semantics
```

A bare result is not lawful reuse state.

### 6.2 SRS versus cache

```text
Cache asks:
  Does a value exist?

SRS asks:
  Was this relation lawfully settled,
  under which dependency state,
  by which ES,
  with which provenance,
  and is it still semantically valid?
```

### 6.3 SRS versus Relation

```text
Relation:
  immutable semantic edge between InformationIDs.

SRS:
  immutable settlement record that references a source relation, result state,
  dependency set, provenance, validity, freshness, and semantics.
```

A Relation may be part of SRS evidence, but it is not the whole SRS.

### 6.4 SRS versus checkpoint

```text
Checkpoint:
  runtime/process/control-state capture.

SRS:
  semantic settlement of a relation into reusable Information Space state.
```

### 6.5 SRS versus generic knowledge-graph edge

```text
Generic graph edge:
  independently designed association between nodes.

SRS:
  ES-settled, provenance-bearing, dependency-bound relation state produced
  through computation and persisted for later lawful reuse.
```

## 7. Required invariants

```text
INV-1  Semantic completeness:
       all required fields exist or the object is not an SRS.

INV-2  Source traceability:
       the source relation and producing ES are traceable.

INV-3  Dependency traceability:
       each required dependency has identity and revision binding evidence.

INV-4  Result traceability:
       the result is linked to the settlement and relation semantics.

INV-5  Provenance completeness:
       producing ES, operation evidence, and settlement evidence are present.

INV-6  Freshness presence:
       semantic freshness conditions exist, even if their algorithm is later.

INV-7  Immutability:
       original SRS is not rewritten.

INV-8  Append-only lifecycle:
       status transitions are new records.

INV-9  Carrier neutrality:
       SRS semantics do not depend on SQLite, POSIX, PALACE, MemPalace, or any
       particular backend.

INV-10 No business authority:
       SRS records settlement; it does not make business decisions.

INV-11 No validation algorithm:
       this boundary does not define the later reuse-validation algorithm.

INV-12 No hidden runtime coupling:
       SRS reuse must be describable without requiring shared runtime process,
       memory, agent notes, or model state.
```

## 8. Explicitly deferred

The following remain undefined until later tasks:

```text
D-1  Operational reuse-validation algorithm — SRS-VAL-01.
D-2  Exact validation predicate inputs and outputs — SRS-VAL-01.
D-3  ES→IS settlement contract — after SRS-VAL-01.
D-4  IS→ES reuse contract — after settlement/validation contracts.
D-5  Durable SRS carrier binding — after semantic and validation boundaries.
D-6  Minimal ES₁→IS→ES₂ experiment — after contracts are reviewed.
D-7  PIR implementation — separately gated.
D-8  Storage schema / backend — separately gated.
D-9  RelationCore or InformationCore extension — separately gated.
```

## 9. Positive example

Abstract example:

```text
source_relation
  relation_semantics = arithmetic sum;
  subject/input role = A and B;
  object/output role = R.

dependency_set
  A = InformationID-A @ revision-12, required;
  B = InformationID-B @ revision-7, required.

result_state
  R = 137.

provenance
  producing_es = ES-1;
  operation = settle-sum;
  input evidence = A@12, B@7;
  result evidence = R=137;
  settlement evidence = ES-1 operation record.

validity_conditions
  A remains revision-12;
  B remains revision-7;
  relation semantics remains sum-v1.

freshness_conditions
  no A supersession;
  no B supersession;
  required PIR checks remain valid.
```

This is an SRS.

## 10. Negative examples

```text
NEG-1  `R = 137` alone.
       Not SRS: missing relation, dependencies, provenance, validity, freshness,
       and semantics.

NEG-2  Cached value keyed by prompt text.
       Not SRS: no source relation, dependency revision set, ES provenance, or
       semantic settlement boundary.

NEG-3  A Relation edge `A → sum → B`.
       Not sufficient as SRS: no result state, dependency revisions, settlement
       provenance, validity, or freshness bundle.

NEG-4  Mutable record whose status is updated in place.
       Violates immutable/append-only semantic boundary.

NEG-5  Runtime process checkpoint.
       Not SRS: runtime control state is not semantic relation settlement.
```

## 11. Human review questions

```text
HQ-1  Are the nine required fields minimal and sufficient?
HQ-2  Should any proposed field be moved to implementation detail?
HQ-3  Is dependency representation strong enough without choosing a backend?
HQ-4  Is the immutable / append-only lifecycle rule correct?
HQ-5  Is the Relation versus SRS boundary precise enough?
HQ-6  Is cache versus SRS boundary precise enough?
HQ-7  Are the deferred validation and carrier items correctly excluded?
HQ-8  Should additional semantic exclusions be registered before SRS-VAL-01?
```

## 12. Decision requested

```text
ACCEPT SRS-SEM-01   freeze this semantic boundary and permit SRS-VAL-01
                    design as the next separate task.
REVISE SRS-SEM-01   return with registered semantic defects.
REJECT SRS-SEM-01   do not proceed.
```

Acceptance does not authorize implementation, fixture creation, experiment, IS
mutation, RelationCore/InformationCore change, U-A change, Frozen Contract
change, or SRS-VAL-01 execution.
