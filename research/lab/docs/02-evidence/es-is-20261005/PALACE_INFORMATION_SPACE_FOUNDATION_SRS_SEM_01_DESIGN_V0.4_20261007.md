# Settled Relation State Semantic Boundary — SRS-SEM-01 Design v0.4

> **Status:** DESIGN V0.4 REVISE — SUPERSEDED BY V0.5 — SRS-VAL-01 NOT AUTHORIZED
> **Date:** 2026-10-07
> **Supersedes:** SRS-SEM-01 Design v0.3 for current review
> **Review basis:** Human REVISE ruling on v0.3 at `d2b6a93`
> **Revision purpose:** freeze external-reference stability for source identity, result target, resolution rule, and semantic/policy versions; remove recomputation prohibition from SRS semantics.
> **Review ruling:** REVISE; see `docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_SEM_01_DESIGN_V0.4_REVIEW_RULING_20261007.md`.
> **Superseded by:** `docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_SEM_01_DESIGN_V0.5_20261007.md`.

## 1. Stability axiom

```text
The meaning of an immutable SRS must not drift because an external scope,
result slot, named resolution rule, or named policy changes.

Therefore every semantic reference that can alter SRS reuse must bind to an
immutable identity or exact immutable version.
```

v0.4 inherits all v0.3 corrections unless explicitly amended here.

## 2. Source-relation identity — scope-independent

`relation_instance_binding` must identify a context-independent, immutable
source-relation instance.

Allowed binding kinds:

```text
PERSISTED_RELATION_ID
  exact immutable Relation instance identity.

CANONICAL_DERIVED_RELATION_ID
  immutable identity assigned or derived by a pre-registered canonical
  identity rule from the relation instance's semantic tuple and authority
  context.
```

Minimum immutable semantic tuple:

```text
relation semantics identity/version;
exact ordered/typed dependency bindings;
result binding;
producing settlement context;
source formation or declaration context;
required discriminator fields.
```

Hard rules:

```text
Declared Physical/Information Scope may validate that the identity was unique
within that scope at settlement time.

Declared Scope MUST NOT be the source of uniqueness.

Later appearance of another relation with matching surface semantics cannot
retroactively make an existing SRS ambiguous.

A natural-language description alone is not an identity.

If no context-independent immutable identity can be produced, the SRS result is
NOT_SETTLED_IDENTITY_STABLE and lawful reuse is blocked.
```

## 3. Result-state target — immutable binding

`RESULT_VALUE` is valid only when its semantic value is complete and immutable
under relation semantics.

`RESULT_REFERENCE` and `RESULT_STATE_DESCRIPTOR` are reusable only when they
carry one of:

```text
EXACT_RESULT_STATE_IDENTITY
  exact immutable result-state identity.

EXACT_RESULT_REVISION
  exact immutable revision of the referenced result state.
```

Required fields:

```text
result_target_binding_kind =
  EXACT_RESULT_STATE_IDENTITY | EXACT_RESULT_REVISION;

result_target_identity =
  immutable result-state identity;

result_target_revision =
  exact immutable result revision, when applicable;

result_integrity_binding =
  digest or equivalent immutable integrity evidence, when required.
```

Forbidden:

```text
mutable result slot;
unversioned result pointer;
latest-result reference;
current-result reference;
semantic equivalence substitution.
```

If the bound result target is missing, changed, or cannot be resolved exactly,
the SRS remains an immutable historical declaration, but reuse validation must
fail:

```text
RESULT_TARGET_UNSTABLE_OR_MISSING
```

The SRS itself is not rewritten.

## 4. Resolution-rule binding — exact immutable version

Replace `resolution_rule_id` with:

```text
resolution_rule_binding
```

Required fields:

```text
binding_kind =
  EXACT_RULE_VERSION;

resolution_rule_identity =
  immutable semantic identity of the resolution rule;

resolution_rule_version =
  exact immutable version of that rule;

resolution_rule_integrity_binding =
  digest or equivalent immutable integrity evidence, when required.
```

Hard rules:

```text
A named rule key may be used only as a registry lookup label.

The semantic SRS binding is the exact immutable rule identity/version.

Changing resolution semantics requires a new rule identity/version.

An existing SRS must never silently resolve under new resolution semantics.
```

If the exact bound rule/version is unavailable or its integrity fails, reuse
validation fails:

```text
RESOLUTION_RULE_UNSTABLE_OR_MISSING
```

## 5. Recomputation prohibition moved out of SRS

`recomputation_prohibition` is removed as an SRS semantic field.

SRS describes:

```text
what was declared settled;
under which exact dependencies;
with which provenance, validity, freshness, and semantics.
```

SRS does not prescribe downstream evaluator behavior.

The no-recompute requirement becomes an invariant of reuse validation:

```text
If SRS validation accepts the SRS as reusable, the validating/reusing path must
not obtain the settled result by recomputing the settled relation.

It must obtain it from the exact immutable result binding.

Experiment evaluation may separately detect, measure, or prove this property.
```

## 6. Semantic policy and rule-version stability

Any semantic rule or policy whose interpretation can affect SRS reuse must be
referenced by:

```text
policy_semantic_identity;
policy_semantic_version;
policy_integrity_binding, when required.
```

Allowed:

```text
EXACT_POLICY_VERSION binding.
```

Forbidden:

```text
latest-policy binding;
mutable policy name as semantic authority;
unversioned policy identifier as sole SRS reference.
```

A policy-name key may be used for registry lookup, but the SRS semantic binding
is the exact immutable policy version.

If the exact policy version is missing or its semantics cannot be verified, reuse
validation fails:

```text
POLICY_VERSION_UNSTABLE_OR_MISSING
```

## 7. Updated invariants

```text
INV-SRS-SEM-21  Source-relation identity is context-independent, immutable, and
                not derived from mutable declared scope.

INV-SRS-SEM-22  Declared Scope is a uniqueness-validation context, not the
                authority that makes source identity unique.

INV-SRS-SEM-23  Reusable RESULT_REFERENCE / DESCRIPTOR binds to exact immutable
                result-state identity or exact immutable result revision.

INV-SRS-SEM-24  Mutable, unversioned, latest-result targets cannot support
                lawful reuse.

INV-SRS-SEM-25  Resolution rules bind to exact immutable rule identity/version.

INV-SRS-SEM-26  Resolution semantic changes require a new rule identity/version.

INV-SRS-SEM-27  Reuse policies and semantic rules bind to exact immutable
                policy/semantic versions.

INV-SRS-SEM-28  Recomputation prohibition is a reuse-validation invariant, not
                an SRS field.
```

## 8. Corrected example

```text
source_relation
  relation_instance_binding.kind =
    CANONICAL_DERIVED_RELATION_ID;
  relation_instance_binding.identity =
    canonical-relation-id;
  relation_instance_identity_integrity =
    digest-of-canonical-tuple;
  relation_semantics = arithmetic sum v1;
  input roles = A and B;
  output role = R.

dependency_set
  A: EXACT_REVISION = revision-12;
  B: EXACT_REVISION = revision-7.

result_state
  result_kind                    = RESULT_VALUE;
  result_target_binding_kind     = EXACT_RESULT_STATE_IDENTITY;
  result_target_identity         = immutable-result-state-identity;
  result_integrity_binding       = digest-R137-state;
  result_semantics               = arithmetic sum output under sum-v1.

resolution_rule_binding
  binding_kind                   = EXACT_RULE_VERSION;
  resolution_rule_identity       = direct-value-resolution;
  resolution_rule_version        = v1;
  resolution_rule_integrity_binding = digest-resolution-rule-v1.

validity_conditions
  A remains exactly revision-12;
  B remains exactly revision-7;
  relation semantics remains sum-v1;
  result target remains exactly immutable-result-state-identity;
  resolution rule remains exactly direct-value-resolution v1;
  freshness policy remains exactly policy-v1.
```

The example records no `recomputation_prohibition` field. The later validator
still may not obtain R by recomputation if it accepts the SRS as reusable.

## 9. Decision requested

```text
ACCEPT SRS-SEM-01 V0.4   freeze external-reference stability and commission
                         SRS-VAL-01 design as the next separate task.
REVISE SRS-SEM-01 V0.4   return with registered defects.
REJECT SRS-SEM-01 V0.4   do not proceed.
```

Acceptance does not authorize implementation, fixture creation, experiment, IS
mutation, RelationCore/InformationCore change, U-A change, Frozen Contract
change, or execution of SRS-VAL-01.
