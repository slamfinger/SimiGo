# D-002 Instrumentation Package v1.1 REVISE and v1.2 Delivery Record

> **Status:** v1.1 = REVISE / RETAINED — v1.2 = DELIVERED FOR HUMAN REVIEW
> **Date:** 2026-10-09
> **Canonical base:** `5922dc77638cc280577333d819c5cbea2215d29e`

## 1. Human ruling on v1.1

```text
Instrumentation Package v1.1 = REVISE;
design freeze                = NOT ACCEPTED;
implementation               = NOT AUTHORIZED;
dry materialization          = NOT AUTHORIZED;
validation execution         = NOT AUTHORIZED;
D-002 rerun / repair-run     = FORBIDDEN;
new campaign                 = NOT AUTHORIZED;
D-001 decide()               = NOT AUTHORIZED;
observer execution           = NOT AUTHORIZED;
canonical/PALACE mutation    = NOT AUTHORIZED;
evidence overwrite           = FORBIDDEN.
```

The Human accepted v1.1's four substantive additions but required v1.2 to close:

```text
R1 execution-boundary conflict around historical S13 and D001 replay;
R2 expected-vector leakage in typed mapping and unclosed causal lane;
R3 non-read-only snapshot path retained by S2;
R4 digest materialization/verification ambiguity, nested schema gaps,
   unspecified trace-chain encoding, and incomplete D001 Git identity binding.
```

## 2. v1.2 response

v1.2 is design-only and:

```text
separates historical static audit, active failure capture, and future D001 handoff;
makes EXPECTED vectors comparator-only and excludes them from causal input materialization;
limits S2 to read-only verification of the existing snapshot;
defines exact digest generation/verification, nested field contracts, trace-chain encoding,
and complete Git blob/content identity for all five D001 files.
```

It does not modify D-001, D-002 implementation, fixtures, PALACE source/snapshot,
or sealed evidence.

## 3. Delivered object

```text
docs/02-evidence/integrated-es-palace-d002-instrumentation-redesign-revision-20261009/
  SIMIGO_INTEGRATED_ES_PALACE_D002_INSTRUMENTATION_REDESIGN_AUTHORIZATION_PACKAGE_V1.2_20261009.md.
```

## 4. Continuing authority

```text
implementation                    = NOT AUTHORIZED;
dry materialization / validation  = NOT AUTHORIZED;
D-002 rerun / repair-run          = FORBIDDEN;
new campaign                      = NOT AUTHORIZED;
D-001 decide()                    = NOT AUTHORIZED;
observer execution                = NOT AUTHORIZED;
canonical/PALACE mutation         = NOT AUTHORIZED;
evidence overwrite                = FORBIDDEN;
E9 / EXP-004                      = NOT AUTHORIZED;
PIR                               = CLOSED / VALIDATION DEFERRED.
```

## 5. Record integrity

v1.1 remains write-once. This Record and v1.2 are registered by the canonical
commit introducing them.
