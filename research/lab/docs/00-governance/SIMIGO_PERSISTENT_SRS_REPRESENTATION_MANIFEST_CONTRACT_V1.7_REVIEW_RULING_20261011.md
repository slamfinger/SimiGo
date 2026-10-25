# Persistent SRS Representation Manifest Contract v1.7 Review Ruling

> **Status:** `REVISE_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.7`
> **Ruling date:** 2026-10-11
> **Review authority:** Human independent design review
> **Reviewed basis:** `b1ba532b2fb013d3cabea83748b9ca0d54b095fc`
> **Reviewed object:** Persistence Manifest Contract v1.7

## 1. Ruling

Human returned:

```text
REVISE_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.7
```

Manifest Contract v1.7 is therefore `REVISE / SUPERSEDED BY V1.8`. It was never
accepted or frozen. I0 JSON Schema v1.6 remains unchanged and is bound by v1.8.

## 2. Prior blocking findings confirmed closed

```text
B1 R29-before-verdict ordering = FIXED;
B2 different-key content-addressed collision = FIXED as
   RECORD_CONTENT_IDENTITY_MISMATCH with no staging/rename/overwrite/delete or
   NEW_RECORD retry.
```

## 3. New blocking finding

```text
B3 When the proposed content path exists, passes R1–R28, has the same ordered
   logical key, but has different I1 bytes due to a payload-digest collision,
   v1.7 had no unique classification terminal. It could fall outside both the
   different-key mismatch and byte-equivalent idempotency branches.
```

## 4. Authorized next object

The only authorized next object is revised design contract v1.8 for separate
Human design review. The minimal revision must route this collision to
`PERSISTENT_LOGICAL_KEY_CONFLICT`, terminate immediately, and forbid staging,
rename, overwrite, deletion, `NEW_RECORD`, and alternate-filename retries.

## 5. Continuing prohibitions

```text
persistent implementation = NOT AUTHORIZED;
fixture preparation = NOT AUTHORIZED;
execution = NOT AUTHORIZED;
marker creation = FORBIDDEN;
evidence-root creation = FORBIDDEN;
canonical PALACE mutation = FORBIDDEN;
canonical Information Space mutation = FORBIDDEN;
MLX execution = FORBIDDEN;
V6 rerun = FORBIDDEN;
independent ES2 consumption = NOT AUTHORIZED;
non-recompute attribution = NOT AUTHORIZED;
production deployment / traffic = NOT AUTHORIZED.
```
