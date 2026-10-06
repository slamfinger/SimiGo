# SRS-SEM-01 Design v0.1 Review Ruling

> **Status:** SRS-SEM-01 Design v0.1 = **REVISE**
> **Review date:** 2026-10-07
> **Review authority:** Human independent review
> **Reviewed basis:** `a80577f`
> **Required follow-up:** small semantic correction v0.2
> **SRS-VAL-01:** NOT AUTHORIZED
> **Implementation / fixture / experiment:** NOT AUTHORIZED

## 1. Ruling

```text
Overall direction                    PASS
Scope discipline                     PASS
SRS vs cache                         PASS
SRS vs Relation                      PASS
Immutable SRS                       PASS
Append-only lifecycle                PASS
Carrier neutrality                   PASS

Lawful-settlement boundary           REVISE
Revision equivalence                 REVISE
Lifecycle conflict derivation        REVISE
Result-state boundary                CLARIFY
Provenance layering                  CLARIFY
Freshness/PIR boundary               CLARIFY

SRS-SEM-01 Design v0.1               REVISE
SRS-VAL-01                           NOT AUTHORIZED
```

No structural rejection, implementation, experiment, or design expansion was
required.

## 2. Required v0.2 corrections

```text
R1  Remove the lawful-settlement circularity.
    SRS-SEM-01 describes an ES settlement event declared as settled under
    governing ES settlement semantics. It does not define when the settlement
    operationally becomes lawful.

R2  Restrict revision_binding to exact immutable revision identity.
    Remove the semantic-equivalence back door. Any future equivalence binding
    must be a separate explicitly reviewed binding kind.

R3  Derive lifecycle status conservatively.
    Unresolved lifecycle conflict must produce no determinate reusable current
    status and must force reuse to be blocked.

C4  Clarify result-state boundary:
    result / formed Information identity is not SRS identity; SRS is the
    settlement bundle, not a wrapper that turns a result into SRS.

C5  Clarify provenance layering:
    SRS-SEM requires sufficient semantic proof obligations but does not invent
    a new provenance taxonomy or evidence model.

C6  Clarify freshness/PIR boundary:
    SRS stores freshness requirements/conditions, not freshness verdicts.
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
