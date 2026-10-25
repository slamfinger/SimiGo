# Persistent SRS Representation Manifest Instance v1.2 Review Ruling

> **Status:** `REVISE_PERSISTENT_SRS_MANIFEST_INSTANCE_V1.2`
> **Ruling date:** 2026-10-11
> **Review authority:** Human independent review
> **Reviewed basis:** `c81f9ee8edfcc1c9cc5b3a50b1aef87f20a0e7e3`
> **Reviewed object:** Persistent SRS Representation Manifest Instance v1.2

## 1. Contract state unchanged

```text
Persistence Manifest Contract v1.8 = ACCEPT / DESIGN FROZEN / NO STAGE AUTHORIZED;
bound I0 JSON Schema v1.6 = unchanged.
```

Only the Manifest Instance is revised.

## 2. Prior findings confirmed fixed

```text
B3 immutable attempts, batch supersession, and unique FINAL_ATTEMPT closure were
   substantially fixed;
B4 shared production classifier requirement was added.
```

## 3. New blocking findings

```text
B5 the per-batch sixteen-execution cap and one-execution-per-scenario rule were
   lost in the v1.2 rewrite;
B6 the shared classifier input was described as verified record descriptors,
   conflicting with synthetic collision descriptors;
B7 FAILED_CLOSED batch supersession and attempt-level exit from closure were
   undefined.
```

## 4. Authorized next object

The only authorized next object is Manifest Instance v1.3. It must restore the
per-batch budget, define a ClassificationDescriptor contract shared by
production and test, and separate batch states from attempt states with explicit
FAILED_CLOSED handling.

## 5. Continuing prohibitions

```text
IMPLEMENTATION = NOT AUTHORIZED;
FIXTURE_PREPARATION = NOT AUTHORIZED;
EXECUTION_BATCH_nn = NOT AUTHORIZED;
independent JSON Schema validator run = NOT AUTHORIZED;
independent ES2 consumption = NOT AUTHORIZED;
non-recompute attribution = NOT AUTHORIZED;
marker creation = FORBIDDEN;
evidence-root creation = FORBIDDEN;
canonical PALACE mutation = FORBIDDEN;
canonical Information Space mutation = FORBIDDEN;
MLX execution = FORBIDDEN;
V6 rerun = FORBIDDEN;
production deployment / traffic = NOT AUTHORIZED.
```
