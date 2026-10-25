# Persistent SRS Representation Manifest Instance v1.7 Review Ruling

> **Status:** `REVISE_PERSISTENT_SRS_MANIFEST_INSTANCE_V1.7`
> **Ruling date:** 2026-10-11
> **Review authority:** Human independent review
> **Reviewed basis:** `caf2e16f112c4365ff87558832ef114944a0253b`
> **Reviewed object:** Persistent SRS Representation Manifest Instance v1.7

## 1. Contract state unchanged

```text
Persistence Manifest Contract v1.8 = ACCEPT / DESIGN FROZEN / NO STAGE AUTHORIZED;
bound I0 JSON Schema v1.6 = unchanged.
```

Only the Manifest Instance is revised.

## 2. Prior findings confirmed fixed

```text
B12 non-circular base digest, completion order key, and sealed evidence digest
   were defined;
B13 one linear closure chain, consecutive head references, fork rejection, and
   no-fallback-after-invalidation were defined.
```

## 3. New blocking finding

```text
B14 the fixed encoding vector was internally inconsistent:
    completion_order_key_value_length was 142 although the frozen field formula
      yields 110 bytes;
    sealed_canonical_data_length was 1135 and was consistent with a 110-byte
      order key;
    the promised full core, order-key, and sealed canonical byte sequences were
      absent.
```

## 4. Authorized next object

The only authorized next object is Manifest Instance v1.8. It must correct the
order-key length to 110, include full core, order-key, and sealed canonical byte
sequences, and ensure lengths, bytes, and digests agree. No other governance
scope is authorized.

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
