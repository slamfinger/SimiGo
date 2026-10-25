# SRS-VAL-01 Design v0.4 Review Ruling

> **Status:** SRS-VAL-01 Design v0.4 = **REVISE / SUPERSEDED BY V0.5**
> **Review date:** 2026-10-07
> **Review authority:** Human independent review
> **Reviewed basis:** `e205f6d`
> **Required follow-up:** v0.5 predicate-rule immutable binding and Context Index consistency correction
> **Superseded by:** `docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_DESIGN_V0.5_20261007.md`.
> **SRS-VAL implementation / fixture / experiment:** NOT AUTHORIZED
> **IS mutation:** NOT AUTHORIZED

## 1. Ruling

```text
v0.3 RECOMPUTE semantic envelope             PASS
Result target / derivation boundary           PASS
Canonical rule EXACT_RULE_VERSION             PASS
No implicit canonical rule replacement        PASS
Unclassified failure guard                    PASS
DP-0..DP-4                                    PASS
Mutual exclusivity                            PASS
Lifecycle precedence                          PASS
Freshness semantics                           PASS

Predicate-rule immutable binding              REVISE
Context Index recovery consistency            REVISE

SRS-VAL-01 Design v0.4                        REVISE
```

v0.4 successfully sealed recomputation object drift. The remaining issues are:

```text
1.  “registered predicate rule” does not yet bind an immutable rule identity,
    exact immutable version, and integrity/content-address evidence.

2.  RESEARCH_CONTEXT_INDEX.md contains competing current-state pointers:
    v0.2 in the recovery entry, v0.4 in the detail block, and v0.3 in the next
    transition.
```

## 2. Required v0.5 corrections

```text
R1  Every remaining failure classified RECOMPUTE_ELIGIBLE MUST be evaluated
    under an exact registered predicate-rule binding containing:
      predicate_rule_identity;
      exact predicate_rule_version;
      integrity/content-address binding.

R2  Failure classification MUST be evaluated under the exact immutable
    predicate-rule version bound to the validation invocation.

R3  A later predicate-rule revision MUST NOT retroactively reinterpret an
    earlier validation basis.

R4  Missing, mutable, unversioned, unstable, or failed predicate-rule binding
    prevents RECOMPUTE_ELIGIBLE classification and forces BLOCK.

R5  Context Index must unify all current / next-transition / recovery-entry
    pointers to SRS-VAL-01 Design v0.4. No competing current object is
    permitted.
```

## 3. Continuing prohibitions

```text
SRS-VAL implementation       NOT AUTHORIZED
SRS-VAL fixture              NOT AUTHORIZED
SRS-VAL experiment           NOT AUTHORIZED
IS mutation                  NOT AUTHORIZED
SimiGo code change           NOT AUTHORIZED
```
