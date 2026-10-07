# AUTH-REQ-01 — IMPLEMENTATION-only Filled Manifest Instance v0.1

> **Status:** OPENED / SUBMITTED WITH AUTH-REQ-01 — NO STAGE AUTHORIZED
> **Date:** 2026-10-07
> **Manifest instance:** AUTH-REQ-01 IMPLEMENTATION-only Filled Manifest Instance v0.1
> **Manifest contract:** Run/Implementation Manifest Contract v1.0 at `f69a0e2`
> **Authorization request:** AUTH-REQ-01 Human Authorization Request v0.1
> **Requested stage set:** `{ IMPLEMENTATION }`
> **Authorized repository revision:** `eef3d24901e23b734bb887841528c0c7b4b42aa0`
> **Stage Authorization Record:** NOT_CREATED_PENDING_HUMAN_RULING
> **Implementation:** NOT AUTHORIZED
> **Fixture preparation:** NOT AUTHORIZED
> **Execution:** NOT AUTHORIZED
> **IS mutation:** NOT AUTHORIZED

## 1. Contract binding

```text
manifest_instance_identity =
  AUTH_REQ_01_IMPLEMENTATION_ONLY_FILLED_MANIFEST_INSTANCE_V0_1;

manifest_contract_identity =
  SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_CONTRACT_V1_0;

manifest_contract_basis_commit =
  f69a0e2506ae94707fd19f85de975b03d5d25c5f;

authorization_request =
  AUTH-REQ-01 Human Authorization Request v0.1;

requested_stage_set = {
  IMPLEMENTATION
};

stage_set_expansion = forbidden;

human_ruling_reference =
  PENDING_HUMAN_REVIEW;

stage_authorization_record =
  NOT_CREATED_PENDING_HUMAN_RULING.
```

## 2. IMPLEMENTATION stage request record

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

## 3. Completion evidence requirements, not completion facts

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

## 4. Later-stage records

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

## 5. Stage separation

```text
IMPLEMENTATION
  ≠ FIXTURE_PREPARATION
  ≠ EXECUTION
  ≠ IS_MUTATION.
```

This instance cannot expand, renew, substitute, or imply any later stage.
