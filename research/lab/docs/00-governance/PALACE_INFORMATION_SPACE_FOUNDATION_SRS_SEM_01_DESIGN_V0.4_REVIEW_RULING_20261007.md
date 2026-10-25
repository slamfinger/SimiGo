# SRS-SEM-01 Design v0.4 Review Ruling

> **Status:** SRS-SEM-01 Design v0.4 = **REVISE / SUPERSEDED BY V0.5**
> **Review date:** 2026-10-07
> **Review authority:** Human independent review
> **Reviewed basis:** `79fc37a`
> **Required follow-up:** v0.5 identity-rule and evidence-reference stability correction
> **Superseded by:** `docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_SEM_01_DESIGN_V0.5_20261007.md`.
> **SRS-VAL-01:** NOT AUTHORIZED
> **Implementation / fixture / experiment:** NOT AUTHORIZED

## 1. Ruling

```text
v0.3 source identity scope independence       PASS
v0.3 result target immutability               PASS
v0.3 resolution-rule exact version            PASS
v0.3 recomputation prohibition relocation     PASS
v0.3 policy/semantic version stability        PASS
v0.3 Context Index consistency                PASS

Canonical identity-rule exact version binding REVISE
Provenance evidence immutable binding         REVISE
Lifecycle evidence immutable binding          REVISE

SRS-SEM-01 Design v0.4                        REVISE
SRS-VAL-01                                    NOT AUTHORIZED
```

v0.4 reached the semantic-freeze threshold except for two remaining instances
of the same stability axiom:

```text
Any external semantic dependency that can alter SRS interpretation or reuse
must bind to an immutable identity, exact immutable version, or immutable
content address.
```

## 2. Required v0.5 corrections

```text
R1  CANONICAL_DERIVED_RELATION_ID must bind the canonical identity-generation
    rule by EXACT_RULE_VERSION. The binding must include immutable rule
    semantic identity, exact immutable rule version, and integrity binding when
    required.

R2  Changing canonical identity-generation semantics requires a new rule
    identity/version. Existing SRS source identity must never be reinterpreted
    under a later rule.

R3  Every provenance or lifecycle evidence reference that can affect SRS
    interpretation or reuse validation must bind to:
      immutable evidence identity,
      exact immutable evidence revision,
      or immutable content address.

R4  Mutable or unversioned evidence references are insufficient for a
    determinate reusable SRS.

R5  Missing or unstable required evidence produces:
      PROVENANCE_EVIDENCE_UNSTABLE_OR_MISSING
      or LIFECYCLE_EVIDENCE_UNSTABLE_OR_MISSING
    and blocks lawful reuse.
```

## 3. Continuing prohibitions

```text
SRS-VAL-01                  NOT AUTHORIZED
SRS implementation          NOT AUTHORIZED
SRS fixture                 NOT AUTHORIZED
SRS experiment              NOT AUTHORIZED
RelationCore change         NOT AUTHORIZED
InformationCore change      NOT AUTHORIZED
Frozen Contract change      NOT AUTHORIZED
```
