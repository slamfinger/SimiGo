# Settled Relation State Semantic Boundary — SRS-SEM-01 Design v0.3

> **Status:** DESIGN V0.3 DELIVERED FOR HUMAN REVIEW — SRS-VAL-01 NOT AUTHORIZED
> **Date:** 2026-10-07
> **Amends:** SRS-SEM-01 Design v0.2, retained as immediate predecessor
> **Review basis:** Human REVISE ruling on v0.2 at `253a23f`
> **Revision purpose:** close concrete relation identity, result resolvability, freshness-blocking lifecycle, lifecycle evidence, revision/freshness disambiguation, and Context Index consistency.

## 1. Effect of v0.3

v0.3 inherits all v0.2 rules unless explicitly amended here.

It adds or corrects:

```text
A1  source_relation must identify the concrete relation instance being settled.

A2  A reusable SRS result must be directly consumable or lawfully resolvable
    without recomputing the settled relation.

A3  FRESHNESS_RECHECK_REQUIRED is a blocking, non-reusable lifecycle state.

A4  Every lifecycle record has minimum evidence fields.

A5  EXACT_REVISION equality and freshness are orthogonal.

A6  Current Context Index navigation must point to v0.3, not stale v0.1/v0.2.
```

All v0.2 rules remain: DECLARED_SETTLED rather than operational lawfulness;
exact revision binding only; result identity distinct from SRS identity;
minimum provenance obligations; freshness requirements rather than verdicts;
conservative lifecycle conflict handling; carrier neutrality; no implementation
or experiment authorization.

## 2. Source-relation instance identity — M1

`source_relation` must answer:

```text
Which concrete relation instance was settled?
```

It is insufficient to name only:

```text
relation semantics;
input roles;
output role.
```

For example, these are distinct source-relation instances even when their
apparent semantics match:

```text
Relation-17: A@12 + B@7 → R
Relation-42: A@12 + B@7 → R
```

### 2.1 Required relation-instance binding

Each SRS must contain:

```text
relation_instance_binding
  identifies the concrete relation instance being settled.
```

Allowed binding kinds:

```text
PERSISTED_RELATION_ID
  use when an immutable persisted Relation instance exists.
  MUST record its exact immutable Relation instance identity.

UNAMBIGUOUS_SOURCE_DESCRIPTION
  use only when no persisted Relation instance exists.
  MUST provide an unambiguous source-relation identity/description sufficient
  to distinguish this settled relation instance from every other candidate
  instance in the declared scope.
```

Minimum content for UNAMBIGUOUS_SOURCE_DESCRIPTION:

```text
relation semantics identity/version;
exact ordered/typed dependency bindings;
result binding;
producing settlement context;
source formation or declaration context;
any additional discriminator required by the governing settlement semantics.
```

Hard rules:

```text
relation semantics + A@12 + B@7 + result alone is not sufficient if it cannot
distinguish Relation-17 from Relation-42.

SRS must not invent or imply a persisted RelationID when none exists.

The later ES→IS settlement contract may specify representation, but SRS-SEM-01
already requires unique semantic identification.
```

## 3. Result resolvability — M2

The result forms part of reusable settlement only if a later ES can lawfully
obtain the result state without recomputing the settled relation.

### 3.1 Result modes

```text
RESULT_VALUE
  valid only when its semantic value is complete and directly consumable under
  relation semantics.

RESULT_REFERENCE
  valid only when it identifies an addressable result state that a later ES can
  lawfully resolve without recomputing the settled relation.

RESULT_STATE_DESCRIPTOR
  valid only when it provides or identifies addressable result state through a
  declared resolution rule sufficient for later lawful retrieval.
```

### 3.2 Non-resolvable descriptor

```text
DESCRIBE(result) ≠ RESOLVE(result).

Example:
  “R is the arithmetic sum of A and B”
describes how R could be computed.

It does not, by itself, provide R as reusable settled state.
```

A RESULT_STATE_DESCRIPTOR without a lawful resolution path is insufficient to
constitute a reusable SRS result.

The SRS must then record:

```text
RESULT_NOT_RESOLVABLE
```

and reuse of the settled relation must be blocked until a separately reviewed
settlement/resolution contract supplies lawful resolution.

### 3.3 Required result-resolvability evidence

Every result binding must record:

```text
result_mode              VALUE / REFERENCE / DESCRIPTOR;
result_resolvability     DIRECT / ADDRESSABLE / NOT_RESOLVABLE;
resolution_rule_id       when REFERENCE or DESCRIPTOR;
resolution_boundary      what later ES is allowed to use;
recomputation_prohibition
                         whether obtaining the result by recomputation would
                         violate the settled-reuse claim.
```

PASS-level reusable result requires:

```text
RESULT_VALUE with complete semantic value; or
RESULT_REFERENCE / RESULT_STATE_DESCRIPTOR with ADDRESSABLE resolution.
```

## 4. FRESHNESS_RECHECK_REQUIRED — M3

FRESHNESS_RECHECK_REQUIRED is a **blocking, non-reusable lifecycle state**.

It is not:

```text
a neutral observation;
a terminal success state;
an optional annotation;
permission to reuse while recheck is pending.
```

If present, the effective status is:

```text
BLOCKED_FRESHNESS_RECHECK_REQUIRED
```

Reuse is forbidden until a separately defined freshness recheck produces
evidence sufficient to clear the required condition.

Clearing requires:

```text
the freshness requirement identifier;
lawful freshness evidence;
evaluation authority/event;
time/ordering evidence;
explicit cleared-by record.
```

This design does not define the recheck algorithm.

## 5. Lifecycle evidence minimum — S1

Every lifecycle record must be independently interpretable.

Minimum fields:

```text
lifecycle_kind;
target settlement_id;
declaring authority/event;
reason;
evidence reference set;
ordering/time evidence;
successor settlement_id when lifecycle_kind = SUPERSEDED;
affected dependency / freshness requirement when relevant;
policy identifier when applicable.
```

Required minimum by kind:

```text
SRS_STATUS_SUPERSEDED
  reason + evidence + successor settlement_id.

SRS_STATUS_INVALIDATED
  reason + evidence.

SRS_STATUS_CONTESTED
  claim + contestant/authority + evidence.

SRS_STATUS_FRESHNESS_RECHECK_REQUIRED
  failed freshness requirement + evidence + required recheck class.
```

Conservative rule:

```text
An incomplete lifecycle record cannot itself establish a determinate reusable
status.

If incomplete lifecycle evidence is the only basis for a status decision, the
effective status is:
  INDETERMINATE_LIFECYCLE_EVIDENCE

Reuse is BLOCKED.

An incomplete record also cannot clear an existing blocker such as
FRESHNESS_RECHECK_REQUIRED.
```

This does not define a full lifecycle state machine.

## 6. Exact revision versus freshness — C1

Exact dependency revision and freshness are orthogonal.

```text
EXACT_REVISION:
  the SRS dependency remains exactly the recorded revision.

FRESHNESS:
  current lawful observation/source-state evidence satisfies the declared
  freshness policy.
```

Therefore:

```text
revision-current is forbidden as a freshness_requirement_class.

“revision-current” must not mean “any latest revision is acceptable.”

It also must not be used to relax an SRS dependency bound to revision-12 or
revision-7.
```

Allowed freshness classes include only policy-defined classes such as:

```text
SOURCE_STATE_FRESHNESS
OBSERVATION_FRESHNESS
POLICY_FRESHNESS
```

Freshness checks may additionally confirm that the exact bound revision is still
the one being observed. They may not substitute a different revision through
freshness language.

Correct example:

```text
dependency binding:
  binding_kind                = EXACT_REVISION;
  revision_binding            = revision-12;

freshness_requirement_class:
  SOURCE_STATE_FRESHNESS.

Meaning:
  the dependency must still be exactly revision-12,
  and the corresponding source-state evidence must satisfy the freshness policy.
```

## 7. Updated result/lifecycle invariants

```text
INV-SRS-SEM-15  source_relation must uniquely identify the concrete relation
                instance being settled.

INV-SRS-SEM-16  a reusable result must be directly consumable or lawfully
                resolvable without recomputing the settled relation.

INV-SRS-SEM-17  FRESHNESS_RECHECK_REQUIRED blocks reuse.

INV-SRS-SEM-18  every lifecycle record carries minimum evidence.

INV-SRS-SEM-19  incomplete lifecycle evidence cannot establish determinate
                reusable status and cannot clear a blocker.

INV-SRS-SEM-20  exact revision equality is not relaxed or replaced by
                freshness language.
```

## 8. Corrected example

```text
source_relation
  relation_instance_binding.kind = PERSISTED_RELATION_ID;
  relation_instance_binding.value = Relation-17;
  relation_semantics = arithmetic sum v1;
  input roles = A and B;
  output role = R.

dependency_set
  A: EXACT_REVISION = revision-12;
     freshness_requirement_class = SOURCE_STATE_FRESHNESS.

  B: EXACT_REVISION = revision-7;
     freshness_requirement_class = SOURCE_STATE_FRESHNESS.

result_state
  result_mode                  = RESULT_VALUE;
  result_resolvability         = DIRECT;
  result                       = R=137;
  recomputation_prohibition    = reuse must not recompute sum(A@12,B@7).

lifecycle
  birth_status = DECLARED_SETTLED.
```

This is a valid reusable SRS declaration shape.

Invalid contrast:

```text
source_relation
  relation_semantics = arithmetic sum v1;
  inputs = A and B;

result_state
  result_mode = RESULT_STATE_DESCRIPTOR;
  result_resolvability = NOT_RESOLVABLE;
  descriptor = “R is the sum of A and B”.
```

That descriptor alone cannot constitute a reusable SRS result.

## 9. Decision requested

```text
ACCEPT SRS-SEM-01 V0.3   freeze the corrected boundary and commission
                         SRS-VAL-01 design as the next separate task.
REVISE SRS-SEM-01 V0.3   return with registered defects.
REJECT SRS-SEM-01 V0.3   do not proceed.
```

Acceptance does not authorize implementation, fixture creation, experiment, IS
mutation, RelationCore/InformationCore change, U-A change, Frozen Contract
change, or execution of SRS-VAL-01.
