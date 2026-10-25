# SRS-VAL-01 Run/Implementation Manifest Contract v0.7 Review Ruling

> **Status:** Run/Implementation Manifest Contract v0.7 = **REVISE / SUPERSEDED BY V0.8**
> **Review date:** 2026-10-07
> **Review authority:** Human independent review
> **Reviewed basis:** `407e003`
> **Frozen basis unchanged:** SRS-VAL-01 Design v0.8; Authorization Package v0.6; Implementation Boundary Audit v0.1
> **Required follow-up:** v0.8 observed disposition realization, phased read mappings, and complete read-instance evidence
> **Superseded by:** `docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_V0.8_20261007.md`.
> **SRS-VAL implementation / fixture / experiment:** NOT AUTHORIZED
> **IS mutation:** NOT AUTHORIZED
> **SimiGo code change:** NOT AUTHORIZED

## 1. Ruling

```text
SRS-VAL-01 Design v0.8              ACCEPT / FROZEN / UNCHANGED
Authorization Package v0.6          ACCEPT / FROZEN / UNCHANGED
Implementation Boundary Audit v0.1  ACCEPT / FROZEN / UNCHANGED
T-IMPL-01 SRS-VAL Decision Core     ACCEPT / FROZEN / UNCHANGED

M16 typed disposition design         PASS
M17 identity/type separation         PASS
M17 totality/one-to-one intent       PASS
M17 temporal closure                 REVISE
Observed disposition closure         REVISE
Read-instance evidence binding       REVISE

Run/Implementation Manifest v0.7     REVISE
```

A pre-run mapping cannot already contain an observer-produced
`observed_read_instance_identity`. In addition, matching declared dispositions
does not prove absence of undeclared semantic reads. Finally, mapping identities
must resolve to complete Authorization Package read-instance records, not mere
identifiers.

## 2. Required v0.8 gates

```text
M17  Split mappings into:
     PRE-RUN semantic_input ↔ expected_read_instance;
     POST-RUN expected_read_instance ↔ observed_read_instance;
     immutable composition only after observation closure.

M18  Realize every required disposition with observer-authoritative evidence:
     MATERIALIZED has the exact value and no undeclared semantic read;
     EXTERNAL_READ has exactly one complete observed read instance;
     NOT_USED has no realization and a valid frozen justification.

M18  The observed semantic read set must equal the required external-read
     realization set, with no undeclared, missing, or invented semantic read.

M18  Mapping identities must resolve to complete immutable read-instance records
     containing digest, channel, access mode, read boundary,
     snapshot/atomicity proof, observer authority, and consumed-content match.
```

## 3. Continuing prohibitions

```text
SRS-VAL implementation       NOT AUTHORIZED
SRS-VAL fixture              NOT AUTHORIZED
SRS-VAL experiment           NOT AUTHORIZED
IS mutation                  NOT AUTHORIZED
SimiGo code change           NOT AUTHORIZED
```
