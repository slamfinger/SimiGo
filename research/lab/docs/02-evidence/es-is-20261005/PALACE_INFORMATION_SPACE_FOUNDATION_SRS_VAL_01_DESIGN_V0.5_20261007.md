# Settled Relation State Reuse Validation Predicate — SRS-VAL-01 Design v0.5

> **Status:** DESIGN V0.5 REVISE — SUPERSEDED BY V0.6 — IMPLEMENTATION / EXPERIMENT NOT AUTHORIZED
> **Date:** 2026-10-07
> **Supersedes:** SRS-VAL-01 Design v0.4 for current review
> **Review basis:** Human REVISE ruling on v0.4 at `e205f6d`
> **Revision purpose:** bind predicate-rule classification to exact immutable rule identity/version/integrity and correct Context Index recovery consistency.
> **Review ruling:** REVISE; see `docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_DESIGN_V0.5_REVIEW_RULING_20261007.md`.
> **Superseded by:** `docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_DESIGN_V0.6_20261007.md`.

## 1. Effect of v0.5

v0.5 inherits all v0.4 rules unless explicitly amended here.

It adds:

```text
A1  Every remaining validation failure must be classified under an exact
    immutable registered predicate-rule binding.

A2  The binding must contain:
      predicate_rule_identity;
      exact predicate_rule_version;
      integrity/content-address binding.

A3  Classification MUST be evaluated only under the exact predicate-rule
    version bound to the validation invocation.

A4  A later predicate-rule revision MUST NOT retroactively reinterpret an
    earlier validation basis.

A5  Missing, mutable, unversioned, unstable, or failed predicate-rule binding
    prevents RECOMPUTE_ELIGIBLE classification and forces BLOCK.

A6  Context Index must present one unified current object: Design v0.4.
```

## 2. Registered predicate-rule binding

For every validation invocation that may classify a remaining failure as
`RECOMPUTE_ELIGIBLE`, the SRS-VAL record must include:

```text
registered_predicate_rule_binding
```

Required fields:

```text
binding_kind =
  EXACT_RULE_VERSION;

predicate_rule_identity =
  immutable semantic identity of the registered failure-classification rule;

predicate_rule_version =
  exact immutable version of that registered rule;

predicate_rule_integrity_binding =
  digest, immutable content address, or equivalent immutable integrity evidence;

covered_failure_classes =
  exact immutable list or semantic identity of failure classes the bound rule is
  authorized to classify.
```

Hard rules:

```text
A rule name alone is only a registry lookup label.

The semantic binding is the exact immutable rule identity/version.

The exact bound predicate-rule version determines whether the observed failure
is RECOMPUTE_ELIGIBLE or HARD_BLOCK.

Changing classification semantics requires a new predicate-rule identity/version.

An existing validation basis is never silently reinterpreted under a later rule.
```

## 3. Classification eligibility

`RECOMPUTE_ELIGIBLE` may be assigned only when:

```text
1.  registered_predicate_rule_binding is present;
2.  the binding is exact, immutable, and integrity-valid;
3.  the observed failure class is explicitly covered by the bound rule version;
4.  the bound predicate-rule version classifies the failure as
    RECOMPUTE_ELIGIBLE;
5.  I-14 separately and exactly covers that classified failure;
6.  the I-14 recomputation semantic envelope remains valid.
```

I-14 coverage alone cannot upgrade a failure.

If the predicate-rule binding is missing, mutable, unversioned, unstable, or
integrity-invalid:

```text
the failure is not RECOMPUTE_ELIGIBLE;
the validation decision is BLOCK;
the typed reason is PREDICATE_RULE_BINDING_UNSTABLE_OR_MISSING.
```

## 4. Non-retroactivity

For a validation invocation, the applicable predicate-rule basis is:

```text
the exact predicate_rule_identity + predicate_rule_version + integrity binding
recorded in that invocation's registered_predicate_rule_binding.
```

A later predicate-rule revision:

```text
MUST NOT retroactively reinterpret an earlier validation basis;
MUST NOT change the classification result of an already completed invocation;
MUST NOT be substituted into an existing SRS-VAL decision by updating a mutable
rule pointer.
```

A later revision may apply only to a new validation invocation.

## 5. Updated decision eligibility

Replace v0.4 DP-3 with:

```text
DP-3  every remaining failure is first classified RECOMPUTE_ELIGIBLE by an
      exact immutable registered predicate-rule binding, and I-14 exactly
      covers every classified failure
        → RECOMPUTE
```

The full precedence remains:

```text
DP-0  observation boundary inconsistent / ambiguous / unstable
        → BLOCK

DP-1  any structural, provenance, result, source-relation, resolution, policy,
      or lifecycle HARD_BLOCK
        → BLOCK

DP-2  applicability NOT_APPLICABLE or APPLICABILITY_INDETERMINATE
        → BLOCK

DP-3  all remaining failures have valid exact predicate-rule classification and
      exact I-14 coverage
        → RECOMPUTE

DP-4  no failure remains and all checks pass
        → REUSE
```

## 6. Updated invariants

```text
INV-SRS-VAL-44  Every RECOMPUTE_ELIGIBLE classification binds an exact immutable
                predicate-rule identity/version.

INV-SRS-VAL-45  Predicate-rule bindings include integrity/content-address
                evidence when required.

INV-SRS-VAL-46  Failure classification is evaluated only under the exact bound
                predicate-rule version.

INV-SRS-VAL-47  Later predicate-rule revisions do not retroactively reinterpret
                earlier validation bases.

INV-SRS-VAL-48  Missing/unstable predicate-rule binding forces BLOCK.

INV-SRS-VAL-49  I-14 coverage alone cannot upgrade an unclassified failure.
```

## 7. Context Index consistency

All current navigation fields must identify:

```text
SRS-VAL-01 — Reuse Validation Predicate Design v0.4
```

Specifically:

```text
Current active closure task = v0.4;
Current design document     = v0.4 document;
Current next transition     = Human review of v0.4.
```

v0.1, v0.2, and v0.3 may remain only as explicitly superseded lineage. They must
not appear as current design, current review, or current next-transition objects.

## 8. Decision requested

```text
ACCEPT SRS-VAL-01 V0.5   freeze predicate-rule stability and permit a separately
                         reviewed implementation/fixture plan.
REVISE SRS-VAL-01 V0.5   return with registered defects.
REJECT SRS-VAL-01 V0.5   do not proceed.
```

No implementation, fixture, experiment, IS mutation, or code change is
authorized.
