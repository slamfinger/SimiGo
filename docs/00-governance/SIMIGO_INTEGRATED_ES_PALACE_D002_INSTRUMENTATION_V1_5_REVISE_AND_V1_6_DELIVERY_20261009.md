# D-002 Instrumentation Package v1.5 REVISE and v1.6 Delivery Record

> **Status:** v1.5 = REVISE / RETAINED — v1.6 = DELIVERED FOR HUMAN REVIEW  
> **Date:** 2026-10-09  
> **Canonical base:** `8ac4c0a5f50aeb1e564e0bc7b28bca986fee4ac4`

## 1. Human ruling on v1.5

```text
Instrumentation Package v1.5 = REVISE;
design freeze                = NOT ACCEPTED;
implementation               = NOT AUTHORIZED;
dry materialization          = NOT AUTHORIZED;
validation execution         = NOT AUTHORIZED;
D-002 rerun / repair-run     = FORBIDDEN;
new campaign                 = NOT AUTHORIZED;
D-001 decide()               = NOT AUTHORIZED;
observer execution           = NOT AUTHORIZED;
D-001 handoff                = NOT AUTHORIZED;
canonical/PALACE mutation    = NOT AUTHORIZED;
evidence overwrite           = FORBIDDEN.
```

The Human required a limit-of-scope v1.6 to correct only:

```text
R1 PASS-chain predecessor ambiguity;
R2 TerminationWitness-only closure when primary evidence is unavailable;
R3 formal classification of PATH_IDENTITY_NOT_FROZEN.
```

No new observation layer, digest layer, security mechanism, or general schema
expansion was authorized.

## 2. v1.6 response

v1.6 is design-only and:

```text
makes every non-initial stage cite prior trace_chain_digest_after_stage;
permits after_capture only as the terminal chain of a FAIL;
defines MODE B WITNESS_ONLY_TERMINATION_CLOSED without requiring primary
StageRecordCore reconstruction;
defines exact WITNESS_ONLY_TERMINATION fields, states and verifier rules;
marks primary chain INCOMPLETE_PRIMARY_CHAIN instead of fabricating completeness;
makes PATH_IDENTITY_NOT_FROZEN a formal path-guard rejection with precedence and
terminal failure record.
```

No implementation, sealed evidence, D001 core, fixtures, snapshot, or PALACE
source is modified.

## 3. Delivered object

```text
docs/02-evidence/integrated-es-palace-d002-instrumentation-redesign-revision-v1.6-20261009/
  SIMIGO_INTEGRATED_ES_PALACE_D002_INSTRUMENTATION_REDESIGN_AUTHORIZATION_PACKAGE_V1.6_20261009.md.
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

v1.0–v1.5 remain write-once. This Record and v1.6 are registered by the canonical
commit introducing them.
