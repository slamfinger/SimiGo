# SRS-VAL-01 Run/Implementation Manifest Contract v0.8 Review Ruling

> **Status:** Run/Implementation Manifest Contract v0.8 = **REVISE / SUPERSEDED BY V0.9**
> **Review date:** 2026-10-07
> **Review authority:** Human independent review
> **Reviewed basis:** `d707cd3`
> **Frozen basis unchanged:** SRS-VAL-01 Design v0.8; Authorization Package v0.6; Implementation Boundary Audit v0.1
> **Required follow-up:** v0.9 typed read-realization relations and disposition-specific realization-evidence authority
> **Superseded by:** `docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_V0.9_20261007.md`.
> **SRS-VAL implementation / fixture / experiment:** NOT AUTHORIZED
> **IS mutation:** NOT AUTHORIZED
> **SimiGo code change:** NOT AUTHORIZED

## 1. Ruling

```text
SRS-VAL-01 Design v0.8              ACCEPT / FROZEN / UNCHANGED
Authorization Package v0.6          ACCEPT / FROZEN / UNCHANGED
Implementation Boundary Audit v0.1  ACCEPT / FROZEN / UNCHANGED
T-IMPL-01 SRS-VAL Decision Core     ACCEPT / FROZEN / UNCHANGED

M16 disposition closure              PASS
M17 phased temporal split            PASS
M17 totality/one-to-one mapping      PASS
M18 hidden semantic-read closure     PASS
M18 complete read-instance binding   PASS

M18 semantic-set/read-set typing     REVISE
M18 realization-evidence typing      REVISE

Run/Implementation Manifest v0.8     REVISE
```

`RequiredExternalSemanticInputSet`, `ExpectedReadInstanceSet`, and
`ObservedReadInstanceSet` contain different identity types. They must be related
by explicit functions/relations, not raw set equality. In addition, MATERIALIZED,
EXTERNAL_READ, and NOT_USED have different realization-evidence sources; only
external reads require observer-authoritative read evidence.

## 2. Required v0.9 corrections

```text
R1  Define and verify:
    RequiredExternalSemanticInputSet : Set<semantic_input_identity>;
    ExpectedReadInstanceSet          : Set<expected_read_instance_identity>;
    ObservedReadInstanceSet          : Set<observed_read_instance_identity>.

R2  Verify domains/codomains:
    dom(semantic_to_expected) =
      RequiredExternalSemanticInputSet;
    codomain(semantic_to_expected) =
      ExpectedReadInstanceSet;
    dom(expected_to_observed) =
      ExpectedReadInstanceSet;
    codomain(expected_to_observed) =
      ObservedReadInstanceSet.

R3  Prove every required external semantic input has exactly one expected read and
    exactly one observed realization through composed mapping.

R4  Use disposition-specific evidence:
    MATERIALIZED -> CLOSED_INVOCATION_RECORD_REALIZATION_EVIDENCE;
    EXTERNAL_READ -> OBSERVER_AUTHORITATIVE_READ_EVIDENCE;
    NOT_USED -> CLOSED_INVOCATION_RECORD_NEGATIVE_REALIZATION_EVIDENCE plus
    OBSERVER_NEGATIVE_READ_CLOSURE_EVIDENCE.

R5  Never require observer-authoritative evidence for all disposition types.
```

## 3. Continuing prohibitions

```text
SRS-VAL implementation       NOT AUTHORIZED
SRS-VAL fixture              NOT AUTHORIZED
SRS-VAL experiment           NOT AUTHORIZED
IS mutation                  NOT AUTHORIZED
SimiGo code change           NOT AUTHORIZED
```
