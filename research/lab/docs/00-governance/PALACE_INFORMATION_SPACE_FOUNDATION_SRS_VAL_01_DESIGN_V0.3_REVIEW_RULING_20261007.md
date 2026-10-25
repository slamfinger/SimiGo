# SRS-VAL-01 Design v0.3 Review Ruling

> **Status:** SRS-VAL-01 Design v0.3 = **REVISE / SUPERSEDED BY V0.4**
> **Review date:** 2026-10-07
> **Review authority:** Human independent review
> **Reviewed basis:** `d2b6a93`
> **Required follow-up:** v0.4 recomputation semantic-envelope correction
> **Superseded by:** `docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_DESIGN_V0.4_20261007.md`.
> **SRS-VAL implementation / fixture / experiment:** NOT AUTHORIZED
> **IS mutation:** NOT AUTHORIZED

## 1. Ruling

```text
v0.2 required corrections                     CLOSED
Source-relation invalidation precedence        PASS
DP-0..DP-4 decision precedence                 PASS
REUSE / BLOCK / RECOMPUTE mutual exclusivity    PASS
Context Index current pointer to v0.3          PASS
Prior superseded lineage retained              PASS

RECOMPUTE target semantic scope                REVISE
Result target identity/derivation scope        REVISE
Canonical identity-generation scope            REVISE
Unclassified failure → RECOMPUTE guard          REVISE

SRS-VAL-01 Design v0.3                         REVISE
```

v0.3 correctly closed the prior source-invalidation precedence and decision-
mutual-exclusivity issues. The remaining problem is that `I-14` still permits
`RECOMPUTE` without freezing the semantic boundary of the recomputed result.

## 2. Required v0.4 corrections

```text
R1  I-14 must contain an exact immutable RECOMPUTE semantic envelope:
      covered recomputation target semantic class;
      covered result-target identity/derivation boundary;
      covered canonical relation-identity generation rule binding.

R2  The canonical relation-identity generation rule must bind by
    EXACT_RULE_VERSION with immutable rule identity, exact immutable version,
    and integrity binding when required.

R3  RECOMPUTE authorization does not implicitly permit changing the canonical
    identity-generation rule.

R4  RECOMPUTE is eligible only when the recomputed result remains inside the
    exact result semantic / target-generation envelope authorized by I-14.

R5  Every remaining validation failure MUST first be classified as
    RECOMPUTE_ELIGIBLE by a registered predicate rule.

R6  I-14 coverage alone MUST NOT upgrade an otherwise unclassified failure into
    RECOMPUTE_ELIGIBLE.
```

## 3. Continuing prohibitions

```text
SRS-VAL implementation       NOT AUTHORIZED
SRS-VAL fixture              NOT AUTHORIZED
SRS-VAL experiment           NOT AUTHORIZED
IS mutation                  NOT AUTHORIZED
SimiGo code change           NOT AUTHORIZED
```
