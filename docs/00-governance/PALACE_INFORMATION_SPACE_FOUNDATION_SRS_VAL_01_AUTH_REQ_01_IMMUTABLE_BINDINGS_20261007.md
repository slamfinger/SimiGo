# AUTH-REQ-01 Immutable Opening Bindings

> **Status:** REQUEST OPENED / NOT AUTHORIZED
> **Date:** 2026-10-07
> **Binding purpose:** immutable content bindings for the opened Authorization
> Request and IMPLEMENTATION-only Filled Manifest Instance.
> **Status note:** SUPERSEDED BY AUTH-REQ-01 Immutable Bindings v0.2.
> **Authorization:** NOT AUTHORIZED

## 1. Request binding

```text
request_object =
  AUTH-REQ-01 Human Authorization Request v0.1;

request_path =
  docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_AUTH_REQ_01_HUMAN_AUTHORIZATION_REQUEST_V0.1_20261007.md;

request_sha256 =
  0e2e55dec2c9c19291fa98b701838949ee0ecf866392ba5ee7051536684e9a11;

request_git_blob_sha =
  429136260ba0e6a5c7ddb5bcf1cb52f3868a39d7;

request_status =
  OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW;

requested_stage_set = {
  IMPLEMENTATION
};

stage_authorization_record =
  NOT_CREATED_PENDING_HUMAN_RULING.
```

## 2. Filled Manifest Instance binding

```text
manifest_instance_object =
  AUTH-REQ-01 IMPLEMENTATION-only Filled Manifest Instance v0.1;

manifest_instance_path =
  docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_AUTH_REQ_01_IMPLEMENTATION_ONLY_FILLED_MANIFEST_INSTANCE_V0.1_20261007.md;

manifest_instance_sha256 =
  8ef4912167cd374146e491c89194981940d8e505ef458f56cbf9950b8aa60a73;

manifest_instance_git_blob_sha =
  709a52f75270caf55c3f56d54850fcdd015942ab;

manifest_contract =
  Run/Implementation Manifest Contract v1.0;

manifest_instance_status =
  OPENED / SUBMITTED WITH AUTH-REQ-01;

authorized_stage_set = {
  IMPLEMENTATION
}.
```

## 3. Boundary directive binding

```text
boundary_directive_object =
  AUTH-REQ-01 Phase 1 Boundary Directive v0.1;

boundary_directive_path =
  docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_AUTH_REQ_01_PHASE1_BOUNDARY_DIRECTIVE_V0.1_20261007.md;

boundary_directive_sha256 =
  f950ced287f7ddae1e405ffdde6e64faf7e5586649e86a3ce56ce818b7206832;

boundary_directive_git_blob_sha =
  e4b2c1f241bd00c9273dbca7e7285f412ee5729a.
```

## 4. Binding rules

```text
Any change to a bound file creates a new content address and voids the prior
opened-object binding.

Human approval must exact-bind request_sha256 or request_git_blob_sha together
with request_path and requested_stage_set.

No approval exists.

No stage is authorized.
```
