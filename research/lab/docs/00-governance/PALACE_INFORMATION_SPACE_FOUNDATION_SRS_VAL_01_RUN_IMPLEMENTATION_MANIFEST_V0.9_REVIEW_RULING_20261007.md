# SRS-VAL-01 Run/Implementation Manifest Contract v0.9 Review Ruling

> **Status:** Run/Implementation Manifest Contract v0.9 = **REVISE / SUPERSEDED BY V1.0**
> **Review date:** 2026-10-07
> **Review authority:** Human independent review
> **Reviewed basis:** `0a8a693`
> **Frozen basis unchanged:** SRS-VAL-01 Design v0.8; Authorization Package v0.6; Implementation Boundary Audit v0.1
> **Required follow-up:** v1.0 independent observed-read semantic-role classification authority
> **Superseded by:** `docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_V1.0_20261007.md`.
> **SRS-VAL implementation / fixture / experiment:** NOT AUTHORIZED
> **IS mutation:** NOT AUTHORIZED
> **SimiGo code change:** NOT AUTHORIZED

## 1. Ruling

```text
SRS-VAL-01 Design v0.8              ACCEPT / FROZEN / UNCHANGED
Authorization Package v0.6          ACCEPT / FROZEN / UNCHANGED
Implementation Boundary Audit v0.1  ACCEPT / FROZEN / UNCHANGED
T-IMPL-01 SRS-VAL Decision Core     ACCEPT / FROZEN / UNCHANGED

M18 typed identity relations         PASS
M18 disposition-specific authority   PASS
M16/M17 regression                   NONE FOUND

Observed-read semantic-role
classification authority             REVISE

Run/Implementation Manifest v0.9     REVISE
```

Observer-authoritative read facts do not authorize Observer to decide semantic
role. A read may be decision-relevant even if Observer labels it
`NON_SEMANTIC_MECHANICAL_READ`. An independent external classification verifier is
required.

## 2. Required v1.0 correction

```text
R1  Add a root-backed observed-read classification verifier and immutable
    classification record.

R2  Observer provides observed read facts only.

R3  Independent Classification Verifier decides:
      SEMANTIC_REALIZATION_OF_REQUIRED_EXTERNAL_INPUT,
      NON_SEMANTIC_MECHANICAL_READ,
      FORBIDDEN_UNDECLARED_SEMANTIC_READ.

R4  Observer cannot alone downgrade a semantic read to mechanical.

R5  Mechanical classification is valid only after independent verification against
    frozen semantic-input universe, category assignment, predicate semantic basis,
    and authorization/observation boundaries.

R6  M18 classification applies to the subject's consumable read universe;
    governance/observation control inputs are not implicitly mechanical.
```

## 3. Continuing prohibitions

```text
SRS-VAL implementation       NOT AUTHORIZED
SRS-VAL fixture              NOT AUTHORIZED
SRS-VAL experiment           NOT AUTHORIZED
IS mutation                  NOT AUTHORIZED
SimiGo code change           NOT AUTHORIZED
```
