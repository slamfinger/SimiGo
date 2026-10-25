# Persistent SRS Representation Manifest Instance v1.8 Review Ruling

> **Status:** `REVISE_PERSISTENT_SRS_MANIFEST_INSTANCE_V1.8`
> **Ruling date:** 2026-10-11
> **Review authority:** Human independent review
> **Reviewed basis:** `6da0378eba1930e84f01e10a4c678811c2065f0e`
> **Reviewed object:** Persistent SRS Representation Manifest Instance v1.8

## 1. Contract state unchanged

```text
Persistence Manifest Contract v1.8 = ACCEPT / DESIGN FROZEN / NO STAGE AUTHORIZED;
bound I0 JSON Schema v1.6 = unchanged.
```

Only the Manifest Instance is revised.

## 2. Prior finding confirmed fixed

```text
B15 completion-order length, full canonical byte sequences, and digest
   consistency were design-review accepted.
```

## 3. New blocking finding

```text
B16 request_base_commit was b1ba532b..., but Manifest Instance v1.8's Git parent
   was caf2e16f.... The object did not distinguish the persistence-contract
   request base from the manifest revision source/parent commit.
```

## 4. Authorized next object

The only authorized next object is Manifest Instance v1.9. It must explicitly
separate:
  persistence_contract_request_base_commit;
  manifest_revision_parent_commit;
  manifest_revision_source_instance;
  manifest_revision_source_document_sha256;
and rebind the resulting document content digest. No other semantic, Contract
v1.8, I0 Schema v1.6, or governance scope may change.

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
