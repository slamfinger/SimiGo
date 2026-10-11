# Persistent SRS Representation Manifest Instance v2.1 Review Ruling

> **Status:** `REVISE_PERSISTENT_SRS_MANIFEST_INSTANCE_V2.1`
> **Ruling date:** 2026-10-12
> **Review authority:** Human independent review
> **Reviewed basis:** `9a376dd5c093b17dad390d1c3ee5690cc46b140d`
> **Reviewed object:** Persistent SRS Representation Manifest Instance v2.1

## 1. Contract state unchanged

```text
Persistence Manifest Contract v1.8 = ACCEPT / DESIGN FROZEN / NO STAGE AUTHORIZED;
bound I0 JSON Schema v1.6 = unchanged.
```

## 2. Prior finding confirmed fixed

```text
B17 manifest_revision_parent_commit correctly points to 62d128062dcde6021d803989e85c612c7dbc7148,
    the direct Git parent of Manifest Instance v2.1.
```

## 3. New administrative finding

```text
B18 manifest_revision_parent_commit was updated to v2.1's direct Git parent, but
   manifest_revision_source_instance and manifest_revision_source_document_sha256
   still identified v1.9. This conflicted with the stated semantics that those
   fields identify the directly superseded Manifest Instance.
```

## 4. Authorized next object

The only authorized next object is Manifest Instance v2.2 with the minimal
provenance synchronization:

```text
manifest_revision_parent_commit =
  9a376dd5c093b17dad390d1c3ee5690cc46b140d;

manifest_revision_source_instance =
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_INSTANCE_V2.1;

manifest_revision_source_document_sha256 =
  837f8c25db1c7fb9dbd8e6863f8d1d0565bd55e6c84d99165322e440d27390d7.
```

If the new revision's actual Git parent differs, the parent field must use that
actual parent. No Contract v1.8, I0 Schema v1.6, encoding-vector, semantic, or
stage-authorization change is authorized.

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
