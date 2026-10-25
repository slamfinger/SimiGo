# Settled Relation State Reuse Validation Predicate — SRS-VAL-01 Design v0.8

> **Status:** DESIGN V0.8 ACCEPT / FROZEN — IMPLEMENTATION / EXPERIMENT NOT AUTHORIZED
> **Date:** 2026-10-07
> **Supersedes:** SRS-VAL-01 Design v0.7 for current review
> **Review basis:** Human REVISE ruling on v0.7 at `33f24cd`
> **Revision purpose:** make predicate classification unavoidable for surviving failures and close Recovery Anchor current-object drift.
> **Review ruling:** ACCEPT / FROZEN; see `docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_DESIGN_V0.8_ACCEPTANCE_20261007.md`.

## 1. Effect of v0.8

v0.8 inherits all v0.7 rules unless explicitly amended here.

It adds:

```text
A1  For every remaining validation failure that is not already resolved by a
    higher-precedence blocker, registered predicate-rule classification is a
    mandatory decision step.

A2  I14_NOT_USED_NO_RECOMPUTE_PATH never means that required classification was
    skipped.

A3  The marker is valid only after the invocation lawfully establishes that no
    RECOMPUTE authorization path is entered.

A4  Recovery Anchor current commissioned design identifies this v0.8 object.
```

No I-14 field, I-15 rule, predicate-rule identity rule, RECOMPUTE semantic
envelope, canonical identity-rule rule, DP outcome set, or lifecycle precedence
is changed.

## 2. Mandatory classification gate

After higher-precedence DP-0, DP-1, or DP-2 resolution has not already decided
the invocation, the gate is:

```text
G-CLASS
  If one or more validation failures remain, every such surviving failure MUST
  be evaluated by the exact registered predicate-rule binding before the
  invocation may resolve to BLOCKED_NON_RECOMPUTE_PATH or RECOMPUTE.
```

Therefore:

```text
remaining failure + skipped classification
  ≠ BLOCKED_NON_RECOMPUTE_PATH;

remaining failure + skipped classification
  → BLOCK / PREDICATE_RULE_CLASSIFICATION_REQUIRED.
```

If the required predicate-rule binding is missing, mutable, unversioned,
unstable, or integrity-invalid, classification cannot lawfully complete and the
existing v0.5 rule controls:

```text
decision = BLOCK
reason   = PREDICATE_RULE_BINDING_UNSTABLE_OR_MISSING
```

A higher-precedence DP-0, DP-1, or DP-2 outcome retains precedence. When such a
precedence rule already resolves the invocation, classification is not required
to manufacture the outcome.

## 3. Lawful I-14 not-used semantics

`I14_NOT_USED_NO_RECOMPUTE_PATH` is lawful only in one of these states:

```text
1.  No validation failure remains.

2.  A higher-precedence DP-0/DP-1/DP-2 rule already resolves the invocation.

3.  Mandatory classification has completed for every surviving failure and none
    is classified RECOMPUTE_ELIGIBLE.
```

The marker is invalid when a surviving failure still requires classification.
Its frozen meaning is:

```text
I14_NOT_USED_NO_RECOMPUTE_PATH
  = this invocation has lawfully established that no RECOMPUTE authorization
    path is entered;

I14_NOT_USED_NO_RECOMPUTE_PATH
  ≠ failure classification was skipped.
```

This preserves evaluator independence: the decision is determined by semantic
precedence and mandatory classification, not by whether an evaluator chooses to
classify.

## 4. Updated path definitions

```text
REUSE_PATH
  no failure remains; all checks pass;
  I-14 = I14_NOT_USED_NO_RECOMPUTE_PATH.

BLOCKED_NON_RECOMPUTE_PATH
  lawful only when a higher-precedence rule already resolves the invocation, or
  mandatory classification has completed and no surviving failure is
  RECOMPUTE_ELIGIBLE;
  I-14 = I14_NOT_USED_NO_RECOMPUTE_PATH.

RECOMPUTE_AUTHORIZATION_PATH
  mandatory classification has classified one or more surviving failures
  RECOMPUTE_ELIGIBLE;
  I-14 = exact immutable governing authorization binding.
```

Any incomplete classification state is not one of the three completed paths. It
produces BLOCK with the applicable typed reason.

## 5. Updated invariants

```text
INV-SRS-VAL-57  Every surviving validation failure undergoes exact registered
                predicate-rule classification unless a higher-precedence rule
                already resolves the invocation.

INV-SRS-VAL-58  I14_NOT_USED_NO_RECOMPUTE_PATH never represents skipped required
                classification.

INV-SRS-VAL-59  BLOCKED_NON_RECOMPUTE_PATH requires either prior higher-
                precedence resolution or completed mandatory classification with
                no RECOMPUTE_ELIGIBLE result.

INV-SRS-VAL-60  The current Recovery Anchor commissioned-design field identifies
                the current submitted SRS-VAL design, not superseded lineage.
```

## 6. Current-object navigation

All current navigation and the Recovery Anchor commissioned-design field
identify:

```text
SRS-VAL-01 — Reuse Validation Predicate Design v0.8
```

v0.1 through v0.7 remain only as explicitly superseded lineage.

## 7. Decision requested

```text
ACCEPT SRS-VAL-01 V0.8   freeze classification non-bypassability and permit a
                         separately reviewed implementation/fixture plan.
REVISE SRS-VAL-01 V0.8   return with registered defects.
REJECT SRS-VAL-01 V0.8   do not proceed.
```

No implementation, fixture, experiment, IS mutation, or code change is
authorized.
