# SRS-SEM-01 Design v0.4 Delivery Record

> **Status:** DESIGN V0.4 DELIVERED FOR HUMAN REVIEW
> **Date:** 2026-10-07
> **Responds to:** REVISE ruling on v0.3 at `d2b6a93`
> **Commission boundary:** external-reference stability correction only
> **SRS-VAL-01:** NOT AUTHORIZED
> **Implementation / fixture / experiment:** NOT AUTHORIZED

## 1. Delivered artifact

```text
docs/02-evidence/es-is-20261005/
  PALACE_INFORMATION_SPACE_FOUNDATION_SRS_SEM_01_DESIGN_V0.4_20261007.md
```

## 2. Findings addressed

```text
R1  source-relation identity is context-independent and immutable.
    Declared Scope is uniqueness-validation context, not identity authority.

R2  RESULT_REFERENCE / DESCRIPTOR must bind to exact immutable result-state
    identity or exact immutable result revision. Mutable/latest targets are
    forbidden.

R3  resolution_rule_id is replaced by resolution_rule_binding to exact immutable
    rule identity/version. Resolution semantic changes require a new rule
    identity/version.

S1  recomputation_prohibition is removed as an SRS field. The no-recompute rule
    belongs to SRS-VAL-01 / reuse validation.

S2  semantic rules and policies affecting reuse bind to exact immutable
    policy/semantic versions. Latest-version references are forbidden.

G1  Context Index now has a single current SRS-SEM-01 object; stale v0.1/v0.2
    current-state navigation is corrected.
```

## 3. Current boundary

```text
SRS-SEM-01 v0.4             SUBMITTED FOR HUMAN REVIEW
SRS-VAL-01                  NOT AUTHORIZED
SRS implementation          NOT AUTHORIZED
SRS fixture                 NOT AUTHORIZED
SRS experiment              NOT AUTHORIZED
RelationCore change         NOT AUTHORIZED
InformationCore change      NOT AUTHORIZED
Frozen Contract change      NOT AUTHORIZED
```
