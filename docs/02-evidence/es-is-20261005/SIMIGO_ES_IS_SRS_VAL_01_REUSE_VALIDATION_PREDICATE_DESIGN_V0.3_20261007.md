# Settled Relation State Reuse Validation Predicate — SRS-VAL-01 Design v0.3

> **Status:** DESIGN V0.3 DELIVERED FOR HUMAN REVIEW — IMPLEMENTATION / EXPERIMENT NOT AUTHORIZED
> **Date:** 2026-10-07
> **Supersedes:** SRS-VAL-01 Design v0.2 for current review
> **Review basis:** Human REVISE ruling on v0.2 at `7b4989b`
> **Revision purpose:** freeze source-invalidation precedence, total decision precedence/mutual exclusivity, and correct current Context Index navigation.

## 1. Effect of v0.3

v0.3 inherits all v0.2 rules unless explicitly amended here.

It adds:

```text
A1  Source-relation invalidation follows the same failure-classification rules
    as dependency/freshness failures.

A2  A formal decision precedence invariant guarantees exactly one primary
    decision and mutual exclusivity.

A3  The current Context Index design pointer is v0.3; v0.1/v0.2 remain
    superseded lineage only.
```

## 2. Source-relation invalidation precedence

Replace v0.2 `V2.4` with:

```text
V2.4  source-relation invalidation records are evaluated against the
      failure-classification rules.

      An invalidation is HARD_BLOCK unless I-14 explicitly and exactly
      authorizes recomputation for that invalidation class.

      I-14 authorization never overrides INVALIDATED / CONTESTED /
      UNRESOLVED_LIFECYCLE_CONFLICT lifecycle blockers.
```

Priority:

```text
hard structural/lifecycle blocker
  > recompute eligibility
  > reuse
```

Hard rule:

```text
No failure class, authorization record, evaluator preference, ordering position,
or implementation shortcut may bypass this precedence.
```

## 3. Formal decision precedence

The predicate is a total semantic function:

```text
D(validated SRS inputs, current semantic request, governing authorization,
  lawful observation boundary)
  → exactly one of REUSE | BLOCK | RECOMPUTE
```

Decision precedence:

```text
DP-0  Observation boundary inconsistent, ambiguous, or unstable
        → BLOCK / VALIDATION_INPUT_STATE_INCONSISTENT

DP-1  Any observation, structural, provenance, resolution, policy, source-
      relation, or lifecycle HARD_BLOCK
        → BLOCK

DP-2  Any applicability NOT_APPLICABLE or APPLICABILITY_INDETERMINATE
        → BLOCK

DP-3  Any remaining validation failure exists and every such failure is
      explicitly covered by exact I-14 authorization
        → RECOMPUTE

DP-4  No validation failure remains and all checks pass
        → REUSE
```

Hard rules:

```text
Exactly one primary decision MUST be returned.

REUSE, BLOCK, and RECOMPUTE are mutually exclusive.

The result is determined by precedence, not by first failure, last failure,
failure count, severity intuition, implementation ordering, or evaluator
preference.

If multiple decisions would otherwise apply, the lowest numbered precedence rule
wins.
```

## 4. Worked precedence examples

```text
Example A
  dependency mismatch is RECOMPUTE_ELIGIBLE;
  freshness evidence missing is HARD_BLOCK.
  Decision: BLOCK (DP-1 wins).

Example B
  dependency mismatch is RECOMPUTE_ELIGIBLE;
  I-15 applicability is NOT_APPLICABLE.
  Decision: BLOCK (DP-2 wins).

Example C
  source relation invalidation exists;
  I-14 exactly covers that invalidation class;
  no structural/lifecycle/applicability blocker exists.
  Decision: RECOMPUTE (DP-3).

Example D
  source relation invalidation exists;
  I-14 does not explicitly cover that invalidation class.
  Decision: BLOCK (DP-1).

Example E
  no failures remain.
  Decision: REUSE (DP-4).
```

## 5. Updated invariants

```text
INV-SRS-VAL-11  source-relation invalidation is a classified validation
                failure, not an independent override of decision precedence.

INV-SRS-VAL-12  exact I-14 authorization may convert an eligible invalidation
                failure to RECOMPUTE, but never overrides lifecycle
                INVALIDATED / CONTESTED / UNRESOLVED_LIFECYCLE_CONFLICT.

INV-SRS-VAL-13  decision precedence is total and deterministic.

INV-SRS-VAL-14  REUSE, BLOCK, and RECOMPUTE are mutually exclusive.

INV-SRS-VAL-15  exactly one primary decision is returned for every lawful
                validation invocation.
```

## 6. Decision requested

```text
ACCEPT SRS-VAL-01 V0.3   freeze decision precedence and permit a separately
                         reviewed implementation/fixture plan.
REVISE SRS-VAL-01 V0.3   return with registered defects.
REJECT SRS-VAL-01 V0.3   do not proceed.
```

No implementation, fixture, experiment, IS mutation, or code change is
authorized.
