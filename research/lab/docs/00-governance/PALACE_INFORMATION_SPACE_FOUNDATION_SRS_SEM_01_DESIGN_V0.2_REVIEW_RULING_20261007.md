# SRS-SEM-01 Design v0.2 Review Ruling

> **Status:** SRS-SEM-01 Design v0.2 = **REVISE / SUPERSEDED BY V0.3**
> **Review date:** 2026-10-07
> **Review authority:** Human independent review
> **Reviewed basis:** `253a23f`
> **Required follow-up:** minimal v0.3 semantic/governance correction
> **Superseded by:** `docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_SEM_01_DESIGN_V0.3_20261007.md`.
> **SRS-VAL-01:** NOT AUTHORIZED
> **Implementation / fixture / experiment:** NOT AUTHORIZED

## 1. Ruling

```text
v0.1 six findings closed                  PASS
Scope discipline                          PASS
Carrier neutrality                        PASS
DECLARED_SETTLED boundary                 PASS
EXACT_REVISION boundary                   PASS
Result identity separation                PASS
Provenance boundary                       PASS
Freshness/verdict separation              PASS

Concrete source-relation identity         REVISE
Result resolvability                      REVISE
FRESHNESS_RECHECK_REQUIRED lifecycle      REVISE
Lifecycle evidence minimum                SHOULD-FIX
revision-current wording                  CLARIFY
Research Context Index consistency        GOVERNANCE FIX

SRS-SEM-01 Design v0.2                    REVISE
SRS-VAL-01                                NOT AUTHORIZED
```

v0.2 closed all six v0.1 findings, but three new semantic boundary issues and
one governance-navigation issue must be corrected before Fixture / Run Manifest.

## 2. Required v0.3 corrections

```text
M1  source_relation MUST identify the concrete relation instance being settled
    when a persisted Relation instance exists. If no persisted Relation instance
    exists, SRS MUST carry an equivalent unambiguous source-relation identity or
    description sufficient to distinguish the settled relation instance.

M2  RESULT_VALUE must be directly consumable when its semantic value is complete.
    RESULT_REFERENCE or RESULT_STATE_DESCRIPTOR is valid only when it provides or
    identifies addressable result state that a later ES can lawfully resolve
    without recomputing the settled relation. A non-resolvable descriptor alone
    is insufficient for a reusable SRS result.

M3  FRESHNESS_RECHECK_REQUIRED is a non-reusable blocking lifecycle state.
    SRS carrying it must not be reused until a separately defined freshness
    recheck produces evidence that clears the condition. It is a blocker, not a
    neutral or terminal success status.

S1  Every lifecycle record must carry minimum evidence:
    lifecycle kind, target settlement, declaring authority/event, reason,
    evidence references, ordering/time, successor settlement when SUPERSEDED,
    and affected dependency/freshness condition when relevant. Incomplete
    lifecycle evidence cannot justify a determinate reusable status.

C1  Exact dependency revision equality is separate from freshness.
    Do not use revision-current as a freshness class. Freshness may check
    source-state/observation/policy freshness, but it never relaxes
    EXACT_REVISION equality.

G1  RESEARCH_CONTEXT_INDEX.md must not show stale v0.1 fields as current while
    later fields name v0.2. The current SRS-SEM-01 object must be unambiguous.
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
