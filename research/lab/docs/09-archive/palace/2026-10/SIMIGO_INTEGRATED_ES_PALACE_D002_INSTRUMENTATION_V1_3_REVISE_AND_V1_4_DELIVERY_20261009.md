# D-002 Instrumentation Package v1.3 REVISE and v1.4 Delivery Record

> **ARCHIVED** 2026-10-20 · line: PALACE / Integrated ES · original: docs/00-governance/SIMIGO_INTEGRATED_ES_PALACE_D002_INSTRUMENTATION_V1_3_REVISE_AND_V1_4_DELIVERY_20261009.md
> Evidence status: unchanged (content frozen; moved only)


> **Status:** v1.3 = REVISE / RETAINED — v1.4 = DELIVERED FOR HUMAN REVIEW  
> **Date:** 2026-10-09  
> **Canonical base:** `6e631a3d4f7bbfe4dbaa36294a7076373d28b01c`

## 1. Human ruling on v1.3

```text
Instrumentation Package v1.3 = REVISE;
design freeze                = NOT ACCEPTED;
implementation               = NOT AUTHORIZED;
dry materialization          = NOT AUTHORIZED;
validation execution         = NOT AUTHORIZED;
D-002 rerun / repair-run     = FORBIDDEN;
D-001 decide()               = NOT AUTHORIZED;
observer execution           = NOT AUTHORIZED;
D-001 handoff                = NOT AUTHORIZED;
canonical/PALACE mutation    = NOT AUTHORIZED;
evidence overwrite           = FORBIDDEN.
```

The Human retained the S8/S9 order and rejection enum, but required v1.4 to close:

```text
R1 entered-stage StageRecord scope and early-failure termination;
R2 non-circular FailureCapture/StageRecord digest binding;
R3 complete in-Package trace-chain algorithm;
R4 universal path-safety checks before all path reads.
```

## 2. v1.4 response

v1.4 is design-only and:

```text
defines exactly one StageRecord for each entered stage;
makes early-failure chains complete and legal;
introduces non-circular FailureAnchorCore → FailureCapture →
StageRecordCoreFinal → StageRecordFull binding;
restates complete per-case genesis/stage/failure chain algorithms and invalid
chain classes;
requires an eight-step universal read-path guard before all path reads in
S1–S12;
does not modify code, sealed evidence, D001 core, fixtures, or PALACE data.
```

## 3. Delivered object

```text
docs/02-evidence/integrated-es-palace-d002-instrumentation-redesign-revision-v1.4-20261009/
  SIMIGO_INTEGRATED_ES_PALACE_D002_INSTRUMENTATION_REDESIGN_AUTHORIZATION_PACKAGE_V1.4_20261009.md.
```

## 4. Continuing authority

```text
implementation                    = NOT AUTHORIZED;
dry materialization / validation  = NOT AUTHORIZED;
D-002 rerun / repair-run          = FORBIDDEN;
new campaign                      = NOT AUTHORIZED;
D-001 decide()                    = NOT AUTHORIZED;
observer execution                = NOT AUTHORIZED;
D-001 handoff                     = NOT AUTHORIZED;
canonical/PALACE mutation         = NOT AUTHORIZED;
evidence overwrite                = FORBIDDEN;
E9 / EXP-004                      = NOT AUTHORIZED;
PIR                               = CLOSED / VALIDATION DEFERRED.
```

## 5. Record integrity

v1.0–v1.3 remain write-once. This Record and v1.4 are registered by the canonical
commit introducing them.
