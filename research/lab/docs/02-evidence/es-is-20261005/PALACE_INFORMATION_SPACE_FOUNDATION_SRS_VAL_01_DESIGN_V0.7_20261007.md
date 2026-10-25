# Settled Relation State Reuse Validation Predicate — SRS-VAL-01 Design v0.7

> **Status:** DESIGN V0.7 REVISE — SUPERSEDED BY V0.8 — IMPLEMENTATION / EXPERIMENT NOT AUTHORIZED
> **Date:** 2026-10-07
> **Supersedes:** SRS-VAL-01 Design v0.6 for current review
> **Review basis:** Human REVISE ruling on v0.6 at `979bb02`
> **Revision purpose:** restore the conditional REUSE/RECOMPUTE separation for I-14 without weakening I-16.
> **Review ruling:** REVISE; see `docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_DESIGN_V0.7_REVIEW_RULING_20261007.md`.
> **Superseded by:** `docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_DESIGN_V0.8_20261007.md`.

## 1. Effect of v0.7

v0.7 inherits all v0.6 rules unless explicitly amended here.

It corrects:

```text
A1  I-14 is a conditional RECOMPUTE-path authorization, not a prerequisite
    for every validation invocation.

A2  I-15 remains mandatory for every invocation.

A3  The predicate-rule binding remains mandatory whenever failure
    classification is invoked; otherwise its exact not-used marker remains
    mandatory.

A4  A pure REUSE invocation records I-14 as not used and is not blocked for
    lacking recomputation authorization.

A5  A RECOMPUTE_ELIGIBLE failure requires an exact immutable I-14 binding in
    the same I-16 boundary.

A6  Current navigation identifies the current submitted review object. At this
    delivery, that object is Design v0.7.
```

No RECOMPUTE semantic envelope field, canonical identity-rule field, decision
precedence, lifecycle precedence, or predicate-rule identity rule is changed.

## 2. Conditional I-14 boundary representation

v0.6's `included_i14_governing_authorization_reference` is reinterpreted as a
path-aware I-16 record:

```text
included_i14_governing_authorization_reference =
  exact immutable I-14 governing authorization binding
    when the invocation is on a RECOMPUTE authorization path;

  I14_NOT_USED_NO_RECOMPUTE_PATH
    when no remaining failure has been classified RECOMPUTE_ELIGIBLE and the
    invocation does not otherwise enter RECOMPUTE authorization.
```

The marker records that I-14 is not a decision input for this invocation. It is
not an authorization, not an authorization placeholder, and not evidence that
RECOMPUTE is permitted.

Hard rules:

```text
I-14 never becomes a prerequisite for valid REUSE.

Absence of I-14 authorization on a pure REUSE path is not
VALIDATION_INPUT_STATE_INCONSISTENT.

If any remaining failure is classified RECOMPUTE_ELIGIBLE, the marker is
forbidden and the exact immutable I-14 binding is mandatory.

I-15 is mandatory for every invocation.

The predicate-rule binding remains conditional exactly as defined by v0.6.
```

## 3. Path selection and completeness

The completed I-16 record must distinguish:

```text
REUSE_PATH
  all checks pass; no remaining failure; no failure classification is invoked;
  I-14 = I14_NOT_USED_NO_RECOMPUTE_PATH.

BLOCKED_NON_RECOMPUTE_PATH
  one or more failures exist but none is classified RECOMPUTE_ELIGIBLE;
  I-14 = I14_NOT_USED_NO_RECOMPUTE_PATH; the governing failure rule supplies
  BLOCK.

RECOMPUTE_AUTHORIZATION_PATH
  one or more remaining failures are classified RECOMPUTE_ELIGIBLE;
  I-14 = exact immutable governing authorization binding.
```

For a RECOMPUTE_AUTHORIZATION_PATH:

```text
a contradictory I14_NOT_USED_NO_RECOMPUTE_PATH marker
  → BLOCK / VALIDATION_INPUT_STATE_INCONSISTENT;

missing, ambiguous, mutable, unversioned, expired, out-of-scope, or
integrity-invalid I-14
  → BLOCK under the appropriate existing authorization/envelope failure reason,
    including GOVERNING_RECOMPUTE_AUTHORIZATION_MISSING_OR_INVALID or
    RECOMPUTE_ENVELOPE_INVALID.
```

The boundary-completeness rule is therefore:

```text
B3'  I-16 explicitly records either an exact immutable I-14 binding for an
     active RECOMPUTE authorization path or
     I14_NOT_USED_NO_RECOMPUTE_PATH for a path that does not use I-14.
```

This rule does not make I-14 itself universally mandatory.

## 4. Updated invariants

```text
INV-SRS-VAL-53  Valid REUSE never requires I-14 recomputation authorization.

INV-SRS-VAL-54  A pure REUSE path records I14_NOT_USED_NO_RECOMPUTE_PATH, and
                that path is not BLOCKED merely because no I-14 authorization
                exists.

INV-SRS-VAL-55  A RECOMPUTE_ELIGIBLE failure requires an exact immutable I-14
                binding in the same I-16 observation boundary.

INV-SRS-VAL-56  A not-used I-14 marker on a RECOMPUTE_ELIGIBLE path is a
                boundary inconsistency; missing or invalid I-14 on that path
                is blocked by the appropriate authorization failure reason.
```

## 5. Current-object navigation

All current active-task, design, review, and next-transition navigation fields
identify:

```text
SRS-VAL-01 — Reuse Validation Predicate Design v0.7
```

When a later revision is delivered, these fields move atomically to that
revision. Superseded designs remain only as explicit lineage.

## 6. Decision requested

```text
ACCEPT SRS-VAL-01 V0.7   freeze conditional I-14 path separation and permit a
                         separately reviewed implementation/fixture plan.
REVISE SRS-VAL-01 V0.7   return with registered defects.
REJECT SRS-VAL-01 V0.7   do not proceed.
```

No implementation, fixture, experiment, IS mutation, or code change is
authorized.
