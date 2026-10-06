# Settled Relation State Semantic Boundary — SRS-SEM-01 Design v0.5

> **Status:** DESIGN V0.5 DELIVERED FOR HUMAN REVIEW — SRS-VAL-01 NOT AUTHORIZED
> **Date:** 2026-10-07
> **Supersedes:** SRS-SEM-01 Design v0.4 for current review
> **Review basis:** Human REVISE ruling on v0.4 at `79fc37a`
> **Revision purpose:** extend the SRS stability axiom to canonical identity-generation rules and provenance/lifecycle evidence references.

## 1. Stability axiom — completed

```text
The meaning of an immutable SRS must not drift because an external scope,
result slot, named resolution rule, named policy, canonical identity-generation
rule, or evidence reference changes.

Therefore:
  source identity generation,
  provenance evidence,
  and lifecycle evidence
must bind to immutable identity, exact immutable version, or immutable content
address.
```

v0.5 inherits all v0.4 rules unless explicitly amended here.

## 2. Canonical identity-generation rule binding

When `relation_instance_binding.kind = CANONICAL_DERIVED_RELATION_ID`, the SRS
must include:

```text
canonical_identity_rule_binding
```

Required fields:

```text
binding_kind =
  EXACT_RULE_VERSION;

canonical_identity_rule_identity =
  immutable semantic identity of the canonical identity-generation rule;

canonical_identity_rule_version =
  exact immutable version of that rule;

canonical_identity_rule_integrity_binding =
  digest or equivalent immutable integrity evidence, when required.
```

Hard rules:

```text
A canonical rule name may be used only as a registry lookup label.

The semantic SRS binding is the exact immutable rule identity/version.

The rule determines how the relation instance's immutable semantic tuple and
authority context map to a canonical relation identity.

Changing canonical identity-generation semantics requires a new rule
identity/version.

An existing SRS must never be reinterpreted under a later canonical rule.
```

If the bound canonical rule/version is missing, changed, or its integrity cannot
be verified, reuse validation fails:

```text
CANONICAL_IDENTITY_RULE_UNSTABLE_OR_MISSING
```

`PERSISTED_RELATION_ID` remains valid as an exact immutable persisted Relation
identity. If that persisted identity itself was minted by a canonical rule
relevant to interpreting the SRS, the same exact rule-version binding
requirement applies.

## 3. Provenance evidence stability

Any provenance evidence reference that can affect SRS interpretation or reuse
validation must use one of:

```text
IMMUTABLE_EVIDENCE_IDENTITY
EXACT_EVIDENCE_REVISION
IMMUTABLE_CONTENT_ADDRESS
```

Required evidence binding fields:

```text
evidence_binding_kind =
  IMMUTABLE_EVIDENCE_IDENTITY |
  EXACT_EVIDENCE_REVISION |
  IMMUTABLE_CONTENT_ADDRESS;

evidence_identity_or_address =
  immutable evidence identity, exact immutable revision identity, or immutable
  content address;

evidence_revision =
  exact immutable revision when applicable;

evidence_integrity_binding =
  digest or equivalent immutable integrity evidence, when required.
```

This applies to evidence references for:

```text
producing_es_identity;
settlement_declaration_evidence;
dependency_evidence;
result_evidence;
ordering_or_time_evidence;
actor_or_process_class evidence, when reference-bearing.
```

Forbidden:

```text
mutable evidence pointer;
unversioned evidence name;
latest-event reference;
latest-record reference;
mutable record slot;
semantic-equivalence substitution for evidence identity.
```

If a required evidence reference is missing, mutable, unversioned, changed, or
its integrity cannot be verified, reuse validation fails:

```text
PROVENANCE_EVIDENCE_UNSTABLE_OR_MISSING
```

## 4. Lifecycle evidence stability

Every lifecycle record must satisfy the same evidence-binding rule.

This applies to:

```text
SRS_STATUS_SUPERSEDED
SRS_STATUS_INVALIDATED
SRS_STATUS_CONTESTED
SRS_STATUS_FRESHNESS_RECHECK_REQUIRED
```

Minimum immutable lifecycle evidence:

```text
lifecycle_kind;
target settlement_id;
declaring authority/event;
reason;
immutable evidence reference set;
ordering/time evidence;
successor settlement_id when SUPERSEDED;
affected dependency / freshness requirement when relevant;
policy identifier when applicable.
```

If a required lifecycle evidence reference is missing, mutable, unversioned,
changed, or its integrity cannot be verified, the lifecycle record cannot
establish a determinate reusable status. Reuse validation fails:

```text
LIFECYCLE_EVIDENCE_UNSTABLE_OR_MISSING
```

An incomplete or unstable lifecycle record also cannot clear an existing blocker
such as:

```text
FRESHNESS_RECHECK_REQUIRED
```

## 5. Updated invariants

```text
INV-SRS-SEM-29  CANONICAL_DERIVED_RELATION_ID binds its canonical
                identity-generation rule by exact immutable rule
                identity/version.

INV-SRS-SEM-30  Canonical identity-generation semantic changes require a new
                rule identity/version.

INV-SRS-SEM-31  Existing SRS source identity is never reinterpreted under a
                later canonical rule.

INV-SRS-SEM-32  Provenance evidence references bind to immutable evidence
                identity, exact immutable evidence revision, or immutable
                content address.

INV-SRS-SEM-33  Lifecycle evidence references bind to immutable evidence
                identity, exact immutable evidence revision, or immutable
                content address.

INV-SRS-SEM-34  Mutable or unversioned provenance/lifecycle evidence cannot
                support determinate reusable SRS.

INV-SRS-SEM-35  Missing or unstable provenance/lifecycle evidence blocks lawful
                reuse.
```

## 6. Corrected example

```text
source_relation
  relation_instance_binding.kind =
    CANONICAL_DERIVED_RELATION_ID;
  relation_instance_binding.identity =
    canonical-relation-id;
  canonical_identity_rule_binding.binding_kind =
    EXACT_RULE_VERSION;
  canonical_identity_rule_binding.rule_identity =
    canonical-relation-identity-rule;
  canonical_identity_rule_binding.rule_version =
    v1;
  canonical_identity_rule_binding.integrity_binding =
    digest-canonical-relation-identity-rule-v1.

provenance
  producing_es_identity =
    ES-1;

  settlement_declaration_evidence_binding.kind =
    IMMUTABLE_CONTENT_ADDRESS;
  settlement_declaration_evidence_binding.content_address =
    sha256:...;

  dependency_evidence_binding.kind =
    EXACT_EVIDENCE_REVISION;
  dependency_evidence_binding.revision =
    dependency-evidence-revision-4;

  result_evidence_binding.kind =
    IMMUTABLE_EVIDENCE_IDENTITY;
  result_evidence_binding.identity =
    immutable-result-evidence-id;

  ordering_or_time_evidence_binding.kind =
    IMMUTABLE_CONTENT_ADDRESS;
  ordering_or_time_evidence_binding.content_address =
    sha256:...
```

No evidence field uses a mutable event name, latest record pointer, or
unversioned slot.

## 7. Decision requested

```text
ACCEPT SRS-SEM-01 V0.5   freeze canonical identity-rule and evidence-reference
                         stability; commission SRS-VAL-01 design as the next
                         separate task.
REVISE SRS-SEM-01 V0.5   return with registered defects.
REJECT SRS-SEM-01 V0.5   do not proceed.
```

Acceptance does not authorize implementation, fixture creation, experiment, IS
mutation, RelationCore/InformationCore change, U-A change, Frozen Contract
change, or execution of SRS-VAL-01.
