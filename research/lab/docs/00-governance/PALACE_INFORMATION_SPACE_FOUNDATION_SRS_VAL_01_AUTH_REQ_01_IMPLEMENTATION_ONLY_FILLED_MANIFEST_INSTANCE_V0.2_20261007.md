# AUTH-REQ-01 — IMPLEMENTATION-only Filled Manifest Instance v0.2

> **Status:** OPENED / SUBMITTED WITH AUTH-REQ-01 V0.2 — NO STAGE AUTHORIZED
> **Date:** 2026-10-07
> **Manifest instance:** AUTH-REQ-01 IMPLEMENTATION-only Filled Manifest Instance v0.2
> **Supersedes:** IMPLEMENTATION-only Filled Manifest Instance v0.1
> **Revision reason:** add exact frozen-baseline content/integrity bindings
> **Manifest contract:** Run/Implementation Manifest Contract v1.0 at `f69a0e2`
> **Authorization request:** AUTH-REQ-01 Human Authorization Request v0.2
> **Requested stage set:** `{ IMPLEMENTATION }`
> **Authorized repository revision:** `eef3d24901e23b734bb887841528c0c7b4b42aa0`
> **Stage Authorization Record:** NOT_CREATED_PENDING_HUMAN_RULING
> **Implementation:** NOT AUTHORIZED
> **Fixture preparation:** NOT AUTHORIZED
> **Execution:** NOT AUTHORIZED
> **IS mutation:** NOT AUTHORIZED

## 1. Exact frozen-baseline bindings

Commit identities do not replace these content/integrity bindings.

```text
frozen_predicate_design_identity =
  SRS_VAL_01_DESIGN_V0_8;

frozen_predicate_design_commit =
  1170208bee91faf34bed5eb0f3359ab6009372ba;

frozen_predicate_design_content_address =
  git:blob:dbbeb5cb4c5aa3a78ea9bf39029a21579d2244d4;

frozen_predicate_design_integrity_binding =
  GIT_BLOB_SHA1:dbbeb5cb4c5aa3a78ea9bf39029a21579d2244d4;

frozen_predicate_design_sha256 =
  1f661bdabcb511f811c9b653e27f1d2242241fca76ca7f2d7614c56ad5b30fd2;

frozen_governance_package_identity =
  SRS_VAL_01_AUTHORIZATION_PACKAGE_V0_6;

frozen_governance_package_commit =
  6089f0bf630af6e85e705fe42f8de2d2327e5200;

frozen_governance_package_content_address =
  git:blob:fb05a60dc950f2f592580cfbc079dff2aa0f91db;

frozen_governance_package_integrity_binding =
  GIT_BLOB_SHA1:fb05a60dc950f2f592580cfbc079dff2aa0f91db;

frozen_governance_package_sha256 =
  e16ca843999959c7583a1b34199c14ea083e456747a86bbb607c342bc493fe37;

frozen_implementation_boundary_identity =
  SRS_VAL_01_IMPLEMENTATION_BOUNDARY_AUDIT_V0_1;

frozen_implementation_boundary_commit =
  cb95c095eb5ceddc3d6d0f7c6b85290e167e8a9d;

frozen_implementation_boundary_content_address =
  git:blob:71064a237c1c79db7547f5d551f7b334998dda4b;

frozen_implementation_boundary_integrity_binding =
  GIT_BLOB_SHA1:71064a237c1c79db7547f5d551f7b334998dda4b;

frozen_implementation_boundary_sha256 =
  a6499c00f050b76356c3df56d4acb103184fcac05fde17a77c06b8dd53a5c251;

manifest_contract_identity =
  SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_CONTRACT_V1_0;

manifest_contract_commit =
  f69a0e2506ae94707fd19f85de975b03d5d25c5f;

manifest_contract_content_address =
  git:blob:9d8853aaac98851ae5e4365d035a141efd5a6e60;

manifest_contract_integrity_binding =
  GIT_BLOB_SHA1:9d8853aaac98851ae5e4365d035a141efd5a6e60;

manifest_contract_sha256 =
  46c4eb4d44a9868c9668da92169a39bbc437a1071e7644eb1db7d3ab8d1e60ff.
```

Hard rules:

```text
Any changed identity, commit, content address, integrity binding, or SHA256 voids
this Manifest Instance and requires a new version.

Human approval must exact-bind this Manifest Instance, AUTH-REQ-01 Request v0.2,
and all four frozen-baseline bindings above.
```

## 2. Contract and request binding


```text
manifest_instance_identity =
  AUTH_REQ_01_IMPLEMENTATION_ONLY_FILLED_MANIFEST_INSTANCE_V0_2;

manifest_contract_identity =
  SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_CONTRACT_V1_0;

manifest_contract_basis_commit =
  f69a0e2506ae94707fd19f85de975b03d5d25c5f;

authorization_request_identity =
  AUTH_REQ_01_HUMAN_AUTHORIZATION_REQUEST_V0_2;

authorization_request_content_address =
  registered_in_AUTH_REQ_01_IMMUTABLE_BINDINGS_V0_2;

authorization_request = 
  AUTH-REQ-01 Human Authorization Request v0.2;

requested_stage_set = {
  IMPLEMENTATION
};

stage_set_expansion = forbidden;

human_ruling_reference =
  PENDING_HUMAN_REVIEW;

stage_authorization_record =
  NOT_CREATED_PENDING_HUMAN_RULING.
```

## 3. IMPLEMENTATION stage request record

```text
implementation_authorization_record_identity =
  PENDING_HUMAN_RULING;

authorized_repository_revision =
  eef3d24901e23b734bb887841528c0c7b4b42aa0;

target_module =
  SettledRelationValidationCore;

authorized_writable_path_set = {
  trackD-memory/Sources/SettledRelationValidationCore/;
  Package.swift
};

authorized_path_operation_constraint =
  Package.swift may be edited only to register
  SettledRelationValidationCore with no external dependency and no unrelated
  target change;

forbidden_path_set =
  every repository path outside the authorized writable path set;

forbidden_dependency_set = {
  MLX/LLM stack;
  CarrierInterface;
  CarrierSQLite;
  RelationCore;
  ExecutionCore;
  SimiGo2Experimental;
  filesystem access;
  network access;
  process execution;
  global mutable state;
  wall-clock/random/environment decision input
};

implementation_effect_set = {
  CREATE_FILES_UNDER_TRACKD_MEMORY_SOURCES_SETTLEDRELATIONVALIDATIONCORE;
  EDIT_ROOT_PACKAGE_SWIFT_FOR_TARGET_REGISTRATION_ONLY;
  CREATE_IMMUTABLE_SOURCE_MODULE_ARTIFACT_AFTER_APPROVAL
};

forbidden_effect_set = {
  RUN_VALIDATION_EXPERIMENT;
  CREATE_FIXTURE_ARTIFACTS;
  ACCESS_NETWORK;
  MUTATE_INFORMATION_SPACE;
  MODIFY_EXISTING_SEMANTIC_SOURCE;
  MODIFY_FROZEN_CONTRACT;
  AUTHORIZE_ANY_LATER_STAGE
};

validity_boundary =
  from Human approval, if granted, until withdrawal, expiration, or authorized
  completion record;

implementation_work_cycle_budget = 1;

execution_run_budget = 0;

fixture_preparation_budget = 0;

is_mutation_budget = 0.
```

## 4. Completion evidence requirements, not completion facts

No implementation has occurred. The following are required future fields only if
Human separately grants IMPLEMENTATION:

```text
result_artifact_identity =
  REQUIRED_AFTER_APPROVED_IMPLEMENTATION;

result_artifact_content_address =
  REQUIRED_AFTER_APPROVED_IMPLEMENTATION;

result_artifact_integrity_binding =
  REQUIRED_AFTER_APPROVED_IMPLEMENTATION;

changed_path_set =
  REQUIRED_AFTER_APPROVED_IMPLEMENTATION;

forbidden_path_violation_count =
  REQUIRED_AFTER_APPROVED_IMPLEMENTATION_AND_MUST_EQUAL_0;

forbidden_dependency_violation_count =
  REQUIRED_AFTER_APPROVED_IMPLEMENTATION_AND_MUST_EQUAL_0;

scope_compliance_verdict =
  REQUIRED_AFTER_APPROVED_IMPLEMENTATION_AND_MUST_EQUAL_PASS.
```

These fields are not placeholders for execution authorization. They may not be
used to authorize FIXTURE_PREPARATION, EXECUTION, or IS_MUTATION.

## 5. Later-stage records

```text
FIXTURE_PREPARATION Stage Authorization Record =
  NOT_REQUESTED / NOT_CREATED;

EXECUTION Stage Authorization Record =
  NOT_REQUESTED / NOT_CREATED;

IS_MUTATION Stage Authorization Record =
  NOT_REQUESTED / NOT_CREATED.
```

A later request must exact-bind the completed immutable implementation artifact
after it exists. Placeholders, future pointers, latest pointers, or estimated
artifact identities are forbidden.

## 6. Stage separation

```text
IMPLEMENTATION
  ≠ FIXTURE_PREPARATION
  ≠ EXECUTION
  ≠ IS_MUTATION.
```

This instance cannot expand, renew, substitute, or imply any later stage.
