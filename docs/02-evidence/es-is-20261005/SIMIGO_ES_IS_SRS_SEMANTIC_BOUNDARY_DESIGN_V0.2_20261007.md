# Settled Relation State Semantic Boundary — SRS-SEM-01 Design v0.2

> **Status:** DESIGN V0.2 REVISE — SUPERSEDED BY V0.3 — SRS-VAL-01 NOT AUTHORIZED
> **Date:** 2026-10-07
> **Supersedes:** SRS-SEM-01 Design v0.1, retained as audit input
> **Review basis:** Human REVISE ruling on v0.1 at `a80577f`
> **Revision purpose:** semantic correction only; no architecture redesign, implementation, fixture, or experiment.
> **Review ruling:** REVISE; see `docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_SEM_01_DESIGN_V0.2_REVIEW_RULING_20261007.md`.
> **Superseded by:** `docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_SEM_01_DESIGN_V0.3_20261007.md`.

## 1. Effect of v0.2

v0.2 inherits the v0.1 direction and boundary discipline, then corrects six
review findings.

```text
R1  SRS records a settlement declaration; it does not define operational
    lawfulness of settlement.

R2  Dependency revision bindings are EXACT immutable revision identities in
    this semantic boundary. No semantic-equivalence back door is allowed.

R3  Lifecycle records do not blindly derive a reusable current status.
    Unresolved lifecycle conflict produces no determinate reusable status.

C4  result_state may reference or describe a result, but result identity is
    not SRS identity.

C5  Provenance states minimum semantic proof obligations; the detailed evidence
    model is deferred.

C6  SRS stores freshness requirements/conditions, not freshness verdicts.
```

Unless explicitly amended here, v0.1's distinctions from cache, bare result,
Relation, checkpoint, and generic graph edge remain.

## 2. Canonical definition — corrected

```text
Settled Relation State is an immutable, addressable semantic settlement record.

It records that a producing Execution State declared a source relation settled
under the governing ES settlement semantics, together with the result state,
dependency bindings, provenance, validity conditions, freshness requirements,
and relation semantics needed for a later Execution State to evaluate whether
the settled relation may be reused.
```

Important boundary:

```text
SRS-SEM-01 describes what a declared settlement means.

SRS-SEM-01 does not define when an ES is operationally entitled to declare
settlement success. That belongs to a later ES→IS settlement contract.
```

Short form:

```text
SRS =
  declared settled result
  + source relation
  + exact dependency bindings
  + provenance
  + validity conditions
  + freshness requirements
  + relation semantics
  + append-only lifecycle state.
```

## 3. Birth status — corrected

The birth status is:

```text
DECLARED_SETTLED
```

Semantic meaning:

```text
A producing Execution State declared, under the governing ES settlement
semantics, that the source relation reached a settled result.
```

This is not:

```text
an independent proof that the declaration was correct;
an assertion that later reuse must succeed;
an operational settlement-authorization record;
an ordinary cache-hit claim.
```

Later validation may reject the declaration if dependencies, provenance,
freshness, or semantics fail.

## 4. Dependency revision binding — corrected

Each dependency record must use:

```text
dependency_role
  input, assumption, policy, context, or other relation-required role.

information_id
  the depended-on Information identity.

binding_kind
  EXACT_REVISION for SRS-SEM-01.

revision_binding
  one exact immutable revision identity.

integrity_binding
  semantic integrity handle such as content digest or equivalent immutable
  evidence, when required by relation semantics.

necessity
  required or conditional.

freshness_requirement_class
  what class of later freshness evaluation is required.
```

Hard rule:

```text
revision_binding = exact immutable revision identity.

No semantically equivalent revision,
no implicit equivalence predicate,
and no equivalence upgrade is allowed in SRS-SEM-01.
```

A later task may propose an explicit:

```text
binding_kind = EQUIVALENCE_PROVEN
```

only as a separately reviewed semantic extension. It must not be implied by
natural language in the SRS boundary.

## 5. Result-state boundary — clarified

`result_state` may be:

```text
RESULT_VALUE
  a semantic value or state produced by the relation.

RESULT_REFERENCE
  a reference to formed Information or another lawful state record.

RESULT_STATE_DESCRIPTOR
  a semantic description of produced state when direct embedding is not part
  of the boundary.
```

Required distinctions:

```text
result_identity ≠ settlement_id.
result_information_identity ≠ SRS identity.
result_state ≠ SRS.
SRS = settlement bundle around the result, source relation, dependencies,
      validity, freshness, provenance, and semantics.
```

Therefore, forming an Information object for the result does not automatically
create or equal an SRS. Likewise, an SRS is not merely a wrapper that converts an
ordinary Information object into reusable state.

## 6. Provenance — clarified layering

The SRS requires enough provenance to answer:

```text
which producing ES;
which settlement declaration;
which dependency set;
which result;
which ordering or time evidence;
which actor/process class.
```

Minimum semantic proof obligations:

```text
producing_es_identity;
settlement_declaration_evidence;
dependency_evidence;
result_evidence;
ordering_or_time_evidence;
actor_or_process_class.
```

This is not a new provenance taxonomy.

It does not decide whether a particular item is object provenance, attempt
provenance, operation evidence, or carrier evidence. The detailed evidence model
belongs to the later ES→IS settlement contract.

## 7. Freshness — requirements, not verdicts

SRS stores:

```text
freshness_requirement_class;
required dependency revision equality;
required source-state checks;
required policy checks;
conditions that require later evaluation.
```

SRS does not store:

```text
a freshness verdict;
a PIR result;
a claim that physical observation is currently fresh;
an authorization to skip freshness evaluation.
```

Correct layering:

```text
SRS records freshness requirements
  → later validator evaluates those requirements
  → PIR or another lawful evidence path may provide evidence
  → REUSE / BLOCK / RECOMPUTE is decided only by the later validation task.
```

## 8. Lifecycle status — corrected conservative derivation

The birth record is:

```text
DECLARED_SETTLED
```

Lifecycle records are append-only. Recognized kinds are:

```text
SRS_STATUS_SUPERSEDED
SRS_STATUS_INVALIDATED
SRS_STATUS_CONTESTED
SRS_STATUS_FRESHNESS_RECHECK_REQUIRED
```

Current status is not obtained by blindly applying every lifecycle record.

Conservative derivation:

```text
L1  No lifecycle record:
    current status = DECLARED_SETTLED.

L2  CONTESTED present:
    current status = CONTESTED / NOT DETERMINATE REUSABLE.

L3  Exactly one terminal lifecycle record:
    current status = that terminal kind.

L4  Multiple terminal records:
    if they are exact semantic duplicates, the terminal kind remains; otherwise
    current status = UNRESOLVED_LIFECYCLE_CONFLICT.

L5  Incompatible terminal kinds, ambiguous successor references, or conflicting
    evidence:
    current status = UNRESOLVED_LIFECYCLE_CONFLICT.
```

`UNRESOLVED_LIFECYCLE_CONFLICT` and `CONTESTED` are not determinate reusable
statuses.

SRS-SEM-01 deliberately does not define a conflict-resolution algorithm.
Resolution belongs to a later contract or explicit Human ruling.

Until resolved, the only lawful posture is:

```text
BLOCK reuse;
preserve audit history;
recompute or re-settle only under a separately authorized contract.
```

## 9. Updated invariants

```text
INV-1  Semantic completeness:
       all required fields exist or the object is not an SRS.

INV-2  Declaration traceability:
       the producing ES and settlement declaration are traceable.

INV-3  Dependency traceability:
       each required dependency has identity and EXACT_REVISION binding
       evidence.

INV-4  Result separation:
       result identity is distinct from settlement identity.

INV-5  Provenance sufficiency:
       provenance can identify producing ES, declaration, dependency set, and
       result.

INV-6  Freshness requirement presence:
       freshness requirements exist, but freshness verdicts are not claimed.

INV-7  Immutability:
       original SRS is not rewritten.

INV-8  Append-only lifecycle:
       lifecycle transitions are new records.

INV-9  Conservative lifecycle derivation:
       unresolved lifecycle conflict has no determinate reusable status.

INV-10 Carrier neutrality:
       SRS semantics do not depend on SQLite, POSIX, PALACE, MemPalace, or any
       particular backend.

INV-11 No business authority:
       SRS records settlement; it does not make business decisions.

INV-12 No validation algorithm:
       this boundary does not define the later reuse-validation algorithm.

INV-13 No settlement-authorization semantics:
       this boundary does not define when an ES may lawfully declare settlement.

INV-14 No semantic revision equivalence:
       exact revision binding is the only revision binding kind allowed here.
```

## 10. Positive example — corrected

```text
source_relation
  relation_semantics = arithmetic sum v1;
  input roles        = A and B;
  output role        = R.

dependency_set
  A:
    dependency_role             = input;
    information_id              = InformationID-A;
    binding_kind                = EXACT_REVISION;
    revision_binding            = revision-12;
    integrity_binding           = digest-A@12;
    necessity                   = required;
    freshness_requirement_class = revision-current.

  B:
    dependency_role             = input;
    information_id              = InformationID-B;
    binding_kind                = EXACT_REVISION;
    revision_binding            = revision-7;
    integrity_binding           = digest-B@7;
    necessity                   = required;
    freshness_requirement_class = revision-current.

result_state
  result_kind      = RESULT_VALUE;
  result_reference = R=137;
  result_semantics = arithmetic sum output under sum-v1.

provenance
  producing_es_identity           = ES-1;
  settlement_declaration_evidence = ES-1 declared sum settled;
  dependency_evidence             = A@12 and B@7;
  result_evidence                 = R=137;
  ordering_or_time_evidence       = settlement ordering record;
  actor_or_process_class          = ES settlement process.

validity_conditions
  A remains exactly revision-12;
  B remains exactly revision-7;
  relation semantics remains sum-v1.

freshness_requirements
  later validation must confirm A/B revision currency and required source-state
  freshness before reuse.

birth_status
  DECLARED_SETTLED.
```

This is an SRS declaration record. It is not proof that later reuse must succeed.

## 11. Negative examples — corrected

```text
NEG-1  R = 137 alone.
       Not SRS: missing declared relation, exact dependencies, provenance,
       validity, freshness requirements, and semantics.

NEG-2  Cached value keyed by prompt text.
       Not SRS: no declared relation, exact dependency state, ES provenance, or
       semantic settlement boundary.

NEG-3  Relation edge A → sum → B.
       Not sufficient as SRS: no declared result, exact dependency bindings,
       provenance, validity, freshness requirements, or lifecycle state.

NEG-4  Mutable record whose status is updated in place.
       Violates immutable/append-only semantic boundary.

NEG-5  Runtime process checkpoint.
       Not SRS: runtime control state is not semantic relation settlement.

NEG-6  SRS with A@12 reused against A@19 because validator calls them
       semantically equivalent.
       Invalid under v0.2: SEM permits only exact revision binding. Equivalence
       would require a separately reviewed binding kind and validation rule.

NEG-7  SRS with SUPERSEDED and INVALIDATED lifecycle records.
       No determinate reusable current status under v0.2; reuse must block
       pending separately defined resolution.
```

## 12. Deferred items

```text
D-1  Operational reuse-validation algorithm — SRS-VAL-01.
D-2  Exact validation predicate inputs/outputs — SRS-VAL-01.
D-3  ES→IS settlement contract.
D-4  IS→ES reuse contract.
D-5  Durable SRS carrier binding.
D-6  Minimal ES₁→IS→ES₂ experiment.
D-7  PIR implementation.
D-8  Storage schema/backend.
D-9  RelationCore or InformationCore extension.
D-10 Equivalence binding semantics beyond EXACT_REVISION.
D-11 Lifecycle conflict-resolution algorithm.
```

## 13. Human review questions

```text
HQ-1  Is DECLARED_SETTLED sufficient to remove the lawful-settlement circularity?
HQ-2  Is EXACT_REVISION-only correct for the SRS semantic boundary?
HQ-3  Is the conservative lifecycle derivation sufficient for SRS-SEM-01?
HQ-4  Is the result/state separation strong enough to prevent result identity
      from becoming SRS identity?
HQ-5  Is the provenance minimum correct without inventing a taxonomy?
HQ-6  Is the freshness requirement/verdict separation correct?
HQ-7  Should any additional ambiguity be frozen before SRS-VAL-01?
```

## 14. Decision requested

```text
ACCEPT SRS-SEM-01 V0.2   freeze the corrected semantic boundary and commission
                         SRS-VAL-01 design as the next separate task.
REVISE SRS-SEM-01 V0.2   return with registered semantic defects.
REJECT SRS-SEM-01 V0.2   do not proceed.
```

Acceptance does not authorize implementation, fixture creation, experiment, IS
mutation, RelationCore/InformationCore change, U-A change, Frozen Contract
change, or execution of SRS-VAL-01.
