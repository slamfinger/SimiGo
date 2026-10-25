# SRS-SEM-01 Design v0.3 Review Ruling

> **Status:** SRS-SEM-01 Design v0.3 = **REVISE / SUPERSEDED BY V0.4**
> **Review date:** 2026-10-07
> **Review authority:** Human independent review
> **Reviewed basis:** `d2b6a93`
> **Required follow-up:** v0.4 external-reference stability correction
> **Superseded by:** `docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_SEM_01_DESIGN_V0.4_20261007.md`.
> **SRS-VAL-01:** NOT AUTHORIZED
> **Implementation / fixture / experiment:** NOT AUTHORIZED

## 1. Ruling

```text
v0.2 required semantic gaps              CLOSED
Concrete relation-instance identity      PARTIAL PASS
Result resolvability                     PARTIAL PASS
FRESHNESS_RECHECK_REQUIRED blocking      PASS
Lifecycle evidence minimum               PASS
Exact revision vs freshness               PASS

Source identity scope dependence         REVISE
Result target immutability               REVISE
Resolution-rule stability                REVISE
Recomputation prohibition as SRS field   SHOULD-FIX
Policy / semantic-version binding        SHOULD-CLARIFY
Context Index canonical consistency      REVISE

SRS-SEM-01 Design v0.3                   REVISE
SRS-VAL-01                               NOT AUTHORIZED
```

v0.3 closed the prior semantic gaps but exposed a second-order requirement:
the immutable SRS must not reference mutable external identities, mutable
result targets, mutable resolution rules, or mutable policy semantics.

## 2. Required v0.4 corrections

```text
R1  UNAMBIGUOUS_SOURCE_DESCRIPTION must be a context-independent, immutable
    source-relation identity. Declared scope may validate uniqueness but must
    not be the identity authority.

R2  RESULT_REFERENCE / RESULT_STATE_DESCRIPTOR must resolve to an immutable
    result-state identity or exact immutable result revision. Mutable or
    unversioned targets are insufficient.

R3  resolution_rule_id must become resolution_rule_binding with exact immutable
    resolution-rule identity/version. Changing resolution semantics requires a
    new rule identity/version and must not silently alter an existing SRS.

S1  Remove recomputation_prohibition from SRS semantics. The no-recompute rule
    belongs to SRS-VAL-01 / reuse validation and experiment evaluation.

S2  Any semantic rule or policy affecting SRS reuse must be identified by an
    exact immutable semantic version/identity. Latest-version references are
    not lawful SRS bindings.

G1  RESEARCH_CONTEXT_INDEX.md must have one unambiguous current SRS-SEM-01
    object and must not contain competing v0.1/v0.2/v0.3 current-state claims.
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
