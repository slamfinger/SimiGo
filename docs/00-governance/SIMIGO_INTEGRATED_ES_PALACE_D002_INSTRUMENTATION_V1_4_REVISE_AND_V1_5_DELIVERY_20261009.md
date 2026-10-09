# D-002 Instrumentation Package v1.4 REVISE and v1.5 Delivery Record

> **Status:** v1.4 = REVISE / RETAINED — v1.5 = DELIVERED FOR HUMAN REVIEW  
> **Date:** 2026-10-09  
> **Canonical base:** `16d2d2ce3568cd31ec62499fece19f6cd7f32035`

## 1. Human ruling on v1.4

```text
Instrumentation Package v1.4 = REVISE;
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

The Human retained entered-stage chain completeness, non-circular failure binding,
in-Package trace-chain, EXPECTED isolation, read-only snapshot verification and
preflight taxonomy, but required v1.5 to close:

```text
R1 complete PASS/FAIL StageRecordCore schema;
R2 unique predecessor binding to StageRecordCore digest;
R3 component-by-component TOCTOU-resistant path opening and hard-link policy;
R4 FailureCapture write-failure termination protocol and independent verifier rule.
```

## 2. v1.5 response

v1.5 is design-only and:

```text
defines one exact StageRecordCoreV5 schema for PASS and FAIL;
renames predecessor identity to previous_stage_core_digest;
adds optional StageRecordFull envelope with non-predecessor full digest;
freezes frozen-root identity, component openat traversal, descriptor
revalidation and conservative hard-link rejection;
adds PRIMARY_EVIDENCE_CHANNEL and INDEPENDENT_TERMINATION_WITNESS_CHANNEL;
maps partial/failed evidence closure to auditable StageRecord states;
prohibits reconstruction of missing evidence.
```

No implementation, sealed evidence, D001 core, fixtures, snapshot, or PALACE
source is modified.

## 3. Delivered object

```text
docs/02-evidence/integrated-es-palace-d002-instrumentation-redesign-revision-v1.5-20261009/
  SIMIGO_INTEGRATED_ES_PALACE_D002_INSTRUMENTATION_REDESIGN_AUTHORIZATION_PACKAGE_V1.5_20261009.md.
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

v1.0–v1.4 remain write-once. This Record and v1.5 are registered by the canonical
commit introducing them.
