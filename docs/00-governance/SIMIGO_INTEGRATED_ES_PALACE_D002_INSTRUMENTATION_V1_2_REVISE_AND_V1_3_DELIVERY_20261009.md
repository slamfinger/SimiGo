# D-002 Instrumentation Package v1.2 REVISE and v1.3 Delivery Record

> **Status:** v1.2 = REVISE / RETAINED — v1.3 = DELIVERED FOR HUMAN REVIEW
> **Date:** 2026-10-09
> **Canonical base:** `a89b980011ce37f347a2e89ccbf1af0e2a64c631`

## 1. Human ruling on v1.2

```text
Instrumentation Package v1.2 = REVISE;
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

The Human retained v1.2's lane separation, historical S13 audit, EXPECTED
isolation, read-only snapshot verification, source-field alignment, digest
separation, nested-check distinction, D001 identity bindings, and T0–T6 checks.

The Human required v1.3 to close only:

```text
R1 unique S8/S9 materialization and validation order;
R2 complete StageRecord schema and chain constraints;
R3 complete RAW_EXCEPTION_PAYLOAD / NORMALIZED_EXCEPTION contracts;
R4 complete and unique preflight rejection enum, including path safety.
```

## 2. v1.3 response

v1.3 is design-only and:

```text
defines active stages S0–S12 and makes S13 campaign-level historical audit;
makes S8 non-invocation D001 preflight only;
makes S9 a single ordered stage with materialization then final I6 preflight;
freezes complete StageRecordCore/Full schemas and chain rules;
restores two-object RAW/NORMALIZED exception closure;
freezes path-safe rejection and complete rejection precedence;
changes no implementation, sealed evidence, D001 core, fixtures, or PALACE data.
```

## 3. Delivered object

```text
docs/02-evidence/integrated-es-palace-d002-instrumentation-redesign-revision-v1.3-20261009/
  SIMIGO_INTEGRATED_ES_PALACE_D002_INSTRUMENTATION_REDESIGN_AUTHORIZATION_PACKAGE_V1.3_20261009.md;
SHA256 = 34d683083eddbc51a9f692c19516d974ae8853aaecec2ee87b8321858edd182a.
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

v1.0–v1.2 remain write-once. This Record and v1.3 are registered by the canonical
commit introducing them.
