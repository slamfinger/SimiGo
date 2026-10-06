# Settled Relation State Reuse Validation Predicate — SRS-VAL-01 Design v0.4

> **Status:** DESIGN V0.4 REVISE — SUPERSEDED BY V0.5 — IMPLEMENTATION / EXPERIMENT NOT AUTHORIZED
> **Date:** 2026-10-07
> **Supersedes:** SRS-VAL-01 Design v0.3 for current review
> **Review basis:** Human REVISE ruling on v0.3 at `d2b6a93`
> **Revision purpose:** freeze the RECOMPUTE semantic envelope, canonical identity-generation rule binding, and unclassified-failure guard.
> **Review ruling:** REVISE; see `docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_DESIGN_V0.4_REVIEW_RULING_20261007.md`.
> **Superseded by:** `docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_DESIGN_V0.5_20261007.md`.

## 1. Effect of v0.4

v0.4 inherits all v0.3 rules unless explicitly amended here.

It adds:

```text
A1  I-14 must carry an exact immutable RECOMPUTE semantic envelope.

A2  The envelope must define:
      covered recomputation target semantic class;
      covered result-target identity/derivation boundary;
      covered canonical relation-identity generation rule binding.

A3  The canonical relation-identity generation rule must bind by
    EXACT_RULE_VERSION.

A4  RECOMPUTE authorization does not implicitly change the canonical
    identity-generation rule.

A5  Every remaining validation failure must first be classified
    RECOMPUTE_ELIGIBLE by a registered predicate rule.

A6  I-14 coverage alone cannot upgrade an unclassified failure.
```

## 2. I-14 recomputation semantic envelope

`I-14` is valid for `RECOMPUTE` only when it contains:

```text
recompute_target_semantic_class
  immutable identity or exact immutable version of the permitted result
  semantic class.

result_target_identity_derivation_boundary
  exact immutable statement of how a recomputed result target may be derived.

canonical_relation_identity_rule_binding
  exact immutable binding of the relation-identity generation rule.

covered_source_relation_scope
  exact source-relation semantics/instance class.

covered_invalidation_class
  exact invalidation class.

covered_request_class
  exact current reuse request class.

authorized_result_outcome
  RECOMPUTE.
```

All envelope components must bind to immutable identity, exact immutable
version, or immutable content address.

Missing, ambiguous, overbroad, mutable, unversioned, expired, or integrity-
failed envelope fields produce:

```text
RECOMPUTE_ENVELOPE_INVALID
```

## 3. Canonical relation-identity generation rule binding

When the envelope permits canonical relation-identity generation, it must
include:

```text
binding_kind =
  EXACT_RULE_VERSION;

rule_identity =
  immutable semantic identity of the canonical relation-identity generation
  rule;

rule_version =
  exact immutable version of that rule;

rule_integrity_binding =
  digest or equivalent immutable integrity evidence, when required.
```

Hard rules:

```text
A canonical rule name is only a registry lookup label.

The semantic SRS binding is the exact immutable rule identity/version.

Changing canonical identity-generation semantics requires a new rule
identity/version.

An existing SRS source identity is never reinterpreted under a later rule.

RECOMPUTE authorization does not implicitly replace or upgrade the canonical
identity-generation rule.
```

If the exact bound rule/version is missing, changed, or its integrity fails,
reuse validation fails:

```text
CANONICAL_IDENTITY_RULE_UNSTABLE_OR_MISSING
```

## 4. RECOMPUTE eligibility

`RECOMPUTE` is possible only when all are true:

```text
1.  the observation boundary is consistent;
2.  the SRS is semantically interpretable;
3.  no DP-0/DP-1 structural, provenance, lifecycle, result, source-relation,
    resolution, or policy HARD_BLOCK exists;
4.  no applicability NOT_APPLICABLE or APPLICABILITY_INDETERMINATE exists;
5.  at least one validation failure remains;
6.  every remaining failure was first classified RECOMPUTE_ELIGIBLE by a
    registered predicate rule;
7.  I-14 exactly covers every classified failure;
8.  I-14 contains the complete valid recomputation semantic envelope;
9.  the intended recomputed result remains inside the exact result semantic /
    target-generation envelope;
10. the exact canonical relation-identity generation rule remains bound and
    unchanged.
```

If any condition fails, the decision is:

```text
BLOCK
```

`I-14` coverage alone never converts an unclassified or hard-blocked failure
into `RECOMPUTE`.

## 5. Updated decision precedence

```text
DP-0  observation boundary inconsistent / ambiguous / unstable
        → BLOCK

DP-1  any structural, provenance, result, source-relation, resolution, policy,
      or lifecycle HARD_BLOCK
        → BLOCK

DP-2  applicability NOT_APPLICABLE or APPLICABILITY_INDETERMINATE
        → BLOCK

DP-3  every remaining failure is RECOMPUTE_ELIGIBLE by registered predicate
      rule and exactly covered by a valid I-14 semantic envelope
        → RECOMPUTE

DP-4  no failure remains and all checks pass
        → REUSE
```

Exactly one primary decision is returned.

`REUSE`, `BLOCK`, and `RECOMPUTE` are mutually exclusive.

## 6. Updated invariants

```text
INV-SRS-VAL-36  RECOMPUTE requires an exact immutable semantic envelope.

INV-SRS-VAL-37  The envelope binds target semantic class, result-target
                identity/derivation boundary, and canonical relation-identity
                generation rule.

INV-SRS-VAL-38  Canonical identity-generation rule binds EXACT_RULE_VERSION.

INV-SRS-VAL-39  Canonical identity-generation semantic changes require a new
                rule identity/version.

INV-SRS-VAL-40  Existing SRS source identity is never reinterpreted under a
                later canonical rule.

INV-SRS-VAL-41  Every remaining failure must be first classified
                RECOMPUTE_ELIGIBLE by registered predicate rule.

INV-SRS-VAL-42  I-14 coverage alone cannot upgrade an unclassified failure.

INV-SRS-VAL-43  Outside-envelope or envelope-invalid recomputation is blocked.
```

## 7. Decision requested

```text
ACCEPT SRS-VAL-01 V0.4   freeze the corrected predicate boundary and permit a
                         separately reviewed implementation/fixture plan.
REVISE SRS-VAL-01 V0.4   return with registered defects.
REJECT SRS-VAL-01 V0.4   do not proceed.
```

No implementation, fixture, experiment, IS mutation, or code change is
authorized.
