# Settled Relation State Reuse Validation Predicate — SRS-VAL-01 Design v0.6

> **Status:** DESIGN V0.6 REVISE — SUPERSEDED BY V0.7 — IMPLEMENTATION / EXPERIMENT NOT AUTHORIZED
> **Date:** 2026-10-07
> **Supersedes:** SRS-VAL-01 Design v0.5 for current review
> **Review basis:** Human REVISE ruling on v0.5 at `440b28a`
> **Revision purpose:** bind every decision-critical input into I-16 and correct current-object navigation.
> **Review ruling:** REVISE; see `docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_DESIGN_V0.6_REVIEW_RULING_20261007.md`.
> **Superseded by:** `docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_DESIGN_V0.7_20261007.md`.

## 1. Effect of v0.6

v0.6 inherits all v0.5 rules unless explicitly amended here.

It adds:

```text
A1  I-16 explicitly includes I-14, I-15, and the exact predicate-rule binding
    as decision-critical validation inputs.

A2  Every decision-critical semantic input MUST belong to the same lawful
    validation observation boundary.

A3  Omitted, ambiguous, unstable, or mixed-boundary decision-critical input
    evidence produces BLOCK / VALIDATION_INPUT_STATE_INCONSISTENT.

A4  Current navigation identifies the current submitted review object. At this
    delivery, that object is Design v0.6.
```

This revision does not alter the RECOMPUTE semantic envelope, canonical
identity-rule binding, predicate-rule stability rules, decision precedence, or
lifecycle precedence.

## 2. Expanded I-16 validation observation boundary

For every validation invocation, I-16 must explicitly record:

```text
boundary_identity;
observation_ordering_time_evidence;
included_srs_evidence_references;
included_dependency_state_references;
included_result_state_references;
included_freshness_policy_evidence_references;
included_lifecycle_evidence_references;
included_i14_governing_authorization_reference;
included_i15_current_reuse_request_reference;
included_predicate_rule_binding_reference;
consistency_method_evidence;
boundary_close_time_or_ordering_marker.
```

`included_predicate_rule_binding_reference` is mandatory whenever the
invocation classifies a remaining failure. If no failure classification is
invoked, the field must contain the exact typed marker
`PREDICATE_RULE_BINDING_NOT_USED_NO_FAILURE_CLASSIFICATION`, not be omitted.

The three decision-critical references are not peripheral metadata:

```text
I-14 determines whether a classified failure may be recomputed.
I-15 determines exact current-request applicability.
The predicate-rule binding determines failure classification.
```

Each reference must be immutable, exact, and resolvable to the same semantic
object used by the invocation. A mutable lookup label is not boundary evidence.

## 3. Boundary completeness rule

Before failure classification, I-14 coverage, or RECOMPUTE eligibility, verify:

```text
B1  I-16 exists and is exact;
B2  all ordinary validation evidence belongs to I-16;
B3  I-14 is explicitly included in I-16;
B4  I-15 is explicitly included in I-16;
B5  the predicate-rule binding is explicitly included in I-16;
B6  every included decision-critical input uses the same observation boundary;
B7  no required decision-critical input is omitted, ambiguous, unstable,
    expired where expiry applies, or integrity-invalid.
```

If any rule fails:

```text
the failure is not classified as RECOMPUTE_ELIGIBLE;
decision = BLOCK;
reason   = VALIDATION_INPUT_STATE_INCONSISTENT.
```

This rule precedes DP-3. It does not authorize mutation, execution, fixture
creation, or experiment.

## 4. Updated invariants

```text
INV-SRS-VAL-50  Every decision-critical semantic input, including I-14, I-15,
                and the predicate-rule binding when classification is invoked,
                is explicitly included in the same lawful I-16 validation
                observation boundary.

INV-SRS-VAL-51  Omission, ambiguity, instability, mixed-boundary membership,
                or missing decision-critical boundary evidence forces
                BLOCK / VALIDATION_INPUT_STATE_INCONSISTENT.

INV-SRS-VAL-52  Superseded SRS-VAL designs never remain as current navigation
                objects.
```

## 5. Current-object navigation rule

The Context Index fields for current active closure task, current design
document, current central review object, current SRS-VAL review object, and
current next transition must identify the current submitted review object.

At this delivery:

```text
Current active closure task = SRS-VAL-01 — Reuse Validation Predicate
                              Design v0.6;
Current design document     = this v0.6 document;
Current review object       = Design v0.6;
Current next transition     = HUMAN REVIEW OF SRS-VAL-01 DESIGN V0.6 ONLY.
```

When a later revision is delivered, all such fields move atomically to that
revision. Superseded designs remain only as explicitly labelled lineage and
never as current design, current review, or current next-transition objects.

## 6. Decision requested

```text
ACCEPT SRS-VAL-01 V0.6   freeze decision-critical boundary inclusion and permit
                         a separately reviewed implementation/fixture plan.
REVISE SRS-VAL-01 V0.6   return with registered defects.
REJECT SRS-VAL-01 V0.6   do not proceed.
```

No implementation, fixture, experiment, IS mutation, or code change is
authorized.
