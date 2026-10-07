# AUTH-REQ-01 Immutable Bindings v0.2

> **Status:** REQUEST V0.2 OPENED / NOT AUTHORIZED
> **Date:** 2026-10-07
> **Purpose:** exact content bindings for AUTH-REQ-01 Request v0.2, its
> IMPLEMENTATION-only Filled Manifest Instance v0.2, and all frozen bases.
> **Authorization:** NOT AUTHORIZED

## 1. Frozen-baseline bindings

```text
frozen_predicate_design_identity =
  SRS_VAL_01_DESIGN_V0_8;
frozen_predicate_design_commit =
  1170208bee91faf34bed5eb0f3359ab6009372ba;
frozen_predicate_design_git_blob_content_address =
  git:blob:dbbeb5cb4c5aa3a78ea9bf39029a21579d2244d4;
frozen_predicate_design_integrity_binding =
  GIT_BLOB_SHA1:dbbeb5cb4c5aa3a78ea9bf39029a21579d2244d4;
frozen_predicate_design_sha256 =
  1f661bdabcb511f811c9b653e27f1d2242241fca76ca7f2d7614c56ad5b30fd2;

frozen_governance_package_identity =
  SRS_VAL_01_AUTHORIZATION_PACKAGE_V0_6;
frozen_governance_package_commit =
  6089f0bf630af6e85e705fe42f8de2d2327e5200;
frozen_governance_package_git_blob_content_address =
  git:blob:fb05a60dc950f2f592580cfbc079dff2aa0f91db;
frozen_governance_package_integrity_binding =
  GIT_BLOB_SHA1:fb05a60dc950f2f592580cfbc079dff2aa0f91db;
frozen_governance_package_sha256 =
  e16ca843999959c7583a1b34199c14ea083e456747a86bbb607c342bc493fe37;

frozen_implementation_boundary_identity =
  SRS_VAL_01_IMPLEMENTATION_BOUNDARY_AUDIT_V0_1;
frozen_implementation_boundary_commit =
  cb95c095eb5ceddc3d6d0f7c6b85290e167e8a9d;
frozen_implementation_boundary_git_blob_content_address =
  git:blob:71064a237c1c79db7547f5d551f7b334998dda4b;
frozen_implementation_boundary_integrity_binding =
  GIT_BLOB_SHA1:71064a237c1c79db7547f5d551f7b334998dda4b;
frozen_implementation_boundary_sha256 =
  a6499c00f050b76356c3df56d4acb103184fcac05fde17a77c06b8dd53a5c251;

manifest_contract_identity =
  SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_CONTRACT_V1_0;
manifest_contract_commit =
  f69a0e2506ae94707fd19f85de975b03d5d25c5f;
manifest_contract_git_blob_content_address =
  git:blob:9d8853aaac98851ae5e4365d035a141efd5a6e60;
manifest_contract_integrity_binding =
  GIT_BLOB_SHA1:9d8853aaac98851ae5e4365d035a141efd5a6e60;
manifest_contract_sha256 =
  46c4eb4d44a9868c9668da92169a39bbc437a1071e7644eb1db7d3ab8d1e60ff.
```

## 2. Request v0.2 binding

```text
request_object =
  AUTH-REQ-01 Human Authorization Request v0.2;
request_path =
  docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_AUTH_REQ_01_HUMAN_AUTHORIZATION_REQUEST_V0.2_20261007.md;
request_sha256 =
  a59d9ca4e922551f3fb8476d8223fb82b3d67d1840fb7e2416a78b91186b9511;
request_git_blob_sha =
  faedde10ad004d831481e1e160cee40fa0cbb0f2;
request_status =
  OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW;
requested_stage_set = {
  IMPLEMENTATION
}.
```

## 3. Filled Manifest Instance v0.2 binding

```text
manifest_instance_object =
  AUTH-REQ-01 IMPLEMENTATION-only Filled Manifest Instance v0.2;
manifest_instance_path =
  docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_AUTH_REQ_01_IMPLEMENTATION_ONLY_FILLED_MANIFEST_INSTANCE_V0.2_20261007.md;
manifest_instance_sha256 =
  6e43ac7d0e02cd07626f5f25bfa7a34606b277a316e63275334c2dc43614ab06;
manifest_instance_git_blob_sha =
  2ae23796f83a4bc6a16ef267910894a7e9bc973e;
manifest_instance_status =
  OPENED / SUBMITTED WITH AUTH-REQ-01 V0.2;
requested_stage_set = {
  IMPLEMENTATION
}.
```

## 4. Binding rules

```text
Any change to a bound file creates a new content address and voids this binding.

Human approval must exact-bind Request v0.2 and Manifest Instance v0.2 together
with all four frozen-baseline bindings above.

No approval exists.

No stage is authorized.
```
