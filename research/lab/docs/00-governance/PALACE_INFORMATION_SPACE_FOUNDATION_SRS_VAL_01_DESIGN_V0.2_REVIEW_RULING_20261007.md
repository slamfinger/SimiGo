# SRS-VAL-01 Design v0.2 Review Ruling

> **Status:** SRS-VAL-01 Design v0.2 = **REVISE**
> **Review date:** 2026-10-07
> **Review authority:** Human independent review
> **Reviewed basis:** `7b4989b`
> **Required follow-up:** v0.3 decision precedence and navigation correction
> **SRS-VAL implementation / fixture / experiment:** NOT AUTHORIZED
> **IS mutation:** NOT AUTHORIZED

## 1. Ruling

```text
SRS-SEM-01 inheritance                 PASS
I-14 recompute authorization           PASS
I-15 exact reuse request               PASS
I-16 observation consistency           PASS
Freshness clearing                     PASS
SRS never authorizes recompute         PASS
Failure alone never means recompute    PASS
Independence boundary                  PASS
Non-recomputation boundary             PASS
Typed failure taxonomy                 PASS

Source invalidation precedence         REVISE
Decision mutual exclusivity            REVISE
Context Index current document pointer REVISE

SRS-VAL-01 Design v0.2                 REVISE
```

v0.2 resolved the four core v0.1 issues, but a total semantic function still
requires one final precedence freeze.

## 2. Required v0.3 corrections

```text
R1  Source-relation invalidation precedence:
    source-relation invalidation records are evaluated under the same failure-
    classification rules. An invalidation is HARD_BLOCK unless exact I-14
    authorization explicitly covers that invalidation class.

    I-14 authorization never overrides INVALIDATED / CONTESTED /
    UNRESOLVED_LIFECYCLE_CONFLICT lifecycle blockers.

R2  Decision precedence and mutual exclusivity:
    1. Any observation/structural/lifecycle HARD_BLOCK → BLOCK.
    2. Any applicability NOT_APPLICABLE or INDETERMINATE → BLOCK.
    3. All remaining failures explicitly covered by I-14 → RECOMPUTE.
    4. No failure remains → REUSE.

    Exactly one primary decision MUST be returned. REUSE, BLOCK, and RECOMPUTE
    are mutually exclusive.

R3  Context Index current navigation:
    the sole current SRS-VAL-01 design document must be v0.3. v0.1 remains only
    as superseded lineage.
```

## 3. Continuing prohibitions

```text
SRS-VAL implementation       NOT AUTHORIZED
SRS-VAL fixture              NOT AUTHORIZED
SRS-VAL experiment           NOT AUTHORIZED
IS mutation                  NOT AUTHORIZED
SimiGo code change           NOT AUTHORIZED
```
