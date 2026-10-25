# Persistent SRS Representation Manifest Contract v1.8 Delivery Record

> **Status:** CONTRACT V1.8 DELIVERED FOR HUMAN DESIGN REVIEW — DESIGN ONLY /
> NO STAGE AUTHORIZED
> **Date:** 2026-10-11
> **Supersedes:** Persistence Manifest Contract v1.7
> (`REVISE / SUPERSEDED / NEVER FROZEN`)
> **Binds:** unchanged I0 JSON Schema v1.6 as candidate schema
> **Implementation:** NOT AUTHORIZED
> **Fixture preparation:** NOT AUTHORIZED
> **Execution:** NOT AUTHORIZED
> **Canonical PALACE / Information Space mutation:** NOT AUTHORIZED
> **MLX / V6 rerun:** NOT AUTHORIZED

## 1. Ruling addressed

```text
REVISE_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.7
```

Ruling record:

```text
docs/00-governance/SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_CONTRACT_V1.7_REVIEW_RULING_20261011.md
```

## 2. Delivered artifacts

```text
docs/02-evidence/persistent-srs-20261011/SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_CONTRACT_V1.8_20261011.md
docs/02-evidence/persistent-srs-20261011/PERSISTENT_SRS_RECORD_JSON_SCHEMA_V1.6.json
```

Content SHA256:

```text
contract_v1_8_sha256 =
  ba8d7fe609a26bdb88ee90e8af0bcd4778372c0ef552a838e158f7204aed47c0;

json_schema_v1_6_sha256 =
  8e373d27afd9c30f8c5e728d03ac71f2c6784f2ba51c2f3195fabd76d6348b41;
```

The I0 JSON Schema is unchanged from the v1.7 candidate.

## 3. Blocking finding addressed

For a proposed content-addressed path that exists and passes R1–R28:

```text
verified logical key differs from proposed key
  -> RECORD_CONTENT_IDENTITY_MISMATCH;

verified logical key equals proposed key and I1 bytes are equivalent
  -> EXISTING_EQUIVALENT_RECORD;

verified logical key equals proposed key but I1 bytes differ, even when the
  payload digest is the same
  -> PERSISTENT_LOGICAL_KEY_CONFLICT.
```

The same-key, same-digest, different-I1 collision terminates immediately. It
cannot fall through to `NEW_RECORD`, scanning for a substitute result, staging,
rename, overwrite, deletion, or an alternate filename.

Contract section 14.2 now covers both collision outcomes, and PR-A41 verifies the
newly closed same-key path.

## 4. Current boundary

```text
persistent implementation = NOT AUTHORIZED;
persistent fixture preparation = NOT AUTHORIZED;
persistent execution = NOT AUTHORIZED;
conditional Manifest Instance v0.1 = NOT EXECUTABLE UNTIL REBOUND;
independent ES2 consumption = NOT AUTHORIZED;
non-recompute attribution = NOT AUTHORIZED;
canonical PALACE mutation = FORBIDDEN;
canonical Information Space mutation = FORBIDDEN;
MLX execution = FORBIDDEN;
V6 rerun = FORBIDDEN;
production proof = NOT ESTABLISHED.
```

## 5. Next lawful object

Human design review of Persistence Manifest Contract v1.8 and unchanged I0 JSON
Schema v1.6. If accepted, the next artifact is a rebound Persistent SRS Manifest
Instance, followed by separate Human Authorization Records for each requested
stage.
