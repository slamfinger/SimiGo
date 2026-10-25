# Persistent SRS Representation Manifest Contract v1.3 Review Ruling

> **Status:** `REVISE_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.3`
> **Ruling date:** 2026-10-11
> **Review authority:** Human independent design review
> **Reviewed basis:** `062aa519b7cb3bd6cb1c72cefc275b4456d6d3b0`
> **Reviewed objects:** Persistence Manifest Contract v1.3 and I0 JSON Schema v1.3

## 1. Ruling

Human returned:

```text
REVISE_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.3
```

Manifest Contract v1.3 and I0 JSON Schema v1.3 are therefore
`REVISE / SUPERSEDED BY V1.4`. They were never accepted or frozen.

## 2. Blocking findings

```text
B1 nullable Binding and UTC fields in the normative schema rejected values
   required by the contract;
B2 reader validation did not require canonical re-serialization byte equality;
B3 UTC calendar validity depended on optional JSON Schema format assertion;
B4 Swift default String equality could merge Unicode canonical-equivalent but
   byte-distinct logical identities.
```

## 3. Authorized next object

The only authorized next object is revised design contract and schema v1.4 for
separate Human design review.

## 4. Continuing prohibitions

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
