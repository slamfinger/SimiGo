# SRS-VAL-01 Design v0.1 Review Ruling

> **Status:** SRS-VAL-01 Design v0.1 = **REVISE / SUPERSEDED BY V0.2**
> **Review date:** 2026-10-07
> **Review authority:** Human independent review
> **Reviewed basis:** `f733457`
> **Required follow-up:** v0.2 predicate decision-boundary correction
> **Superseded by:** `docs/02-evidence/es-is-20261005/SIMIGO_ES_IS_SRS_VAL_01_REUSE_VALIDATION_PREDICATE_DESIGN_V0.2_20261007.md`.
> **SRS-VAL implementation / fixture / experiment:** NOT AUTHORIZED
> **IS mutation:** NOT AUTHORIZED

## 1. Ruling

```text
SRS-SEM-01 inheritance              PASS
Exact-binding validation            PASS
G-V1..G-V7 structure                PASS
REUSE semantics                     PASS / boundary completion needed
BLOCK semantics                     PARTIAL
RECOMPUTE semantics                 REVISE
Applicability input                 REVISE
Freshness recheck wording           SHOULD-FIX
Validation observation consistency  REVISE
Independence boundary               PASS
Non-recomputation boundary          PASS
Failure taxonomy                    PASS / additions needed

SRS-VAL-01 Design v0.1              REVISE
```

No structural rejection or implementation path was authorized.

## 2. Required v0.2 corrections

```text
B1  RECOMPUTE authorization source conflict:
    SRS never authorizes RECOMPUTE.
    Add an explicit governing recompute/reuse authorization binding as a
    predicate input. RECOMPUTE is possible only when that separately bound
    governing semantic contract/policy explicitly authorizes the current
    invalidation class.

B2  Current reuse request input:
    The predicate currently requires applicability but receives no exact
    current-request semantic input. Add a non-natural-language
    current_reuse_request binding, or conservatively BLOCK whenever
    applicability cannot be exactly determined.

B3  BLOCK versus RECOMPUTE must become a complete decision relation:
    every validation failure must first be classified; RECOMPUTE occurs only
    when a separately bound governing rule explicitly authorizes that
    invalidation class. RECOMPUTE does not mean “validation failed, so compute
    again.”

B4  Validation observation consistency:
    all inputs for one decision must belong to one lawful validation observation
    boundary. If cross-input consistency cannot be established, return BLOCK
    with a typed consistency reason.

C1  Freshness V7.6 must use positive clearing semantics:
    FRESHNESS_RECHECK_REQUIRED present and uncleared → BLOCK;
    explicitly cleared by lawful evidence → freshness evaluation may continue.
```

## 3. Continuing prohibitions

```text
SRS-VAL implementation       NOT AUTHORIZED
SRS-VAL fixture              NOT AUTHORIZED
SRS-VAL experiment           NOT AUTHORIZED
IS mutation                  NOT AUTHORIZED
SimiGo code change           NOT AUTHORIZED
```
