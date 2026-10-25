# AUTH-REQ-01 — Human Authorization Request v0.2

> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE AUTHORIZED
> **Date:** 2026-10-07
> **Request object:** AUTH-REQ-01 Human Authorization Request v0.2
> **Supersedes:** AUTH-REQ-01 Human Authorization Request v0.1
> **Revision reason:** add exact frozen-baseline content/integrity bindings
> **Requested stage set:** `{ IMPLEMENTATION }`
> **Phase 1 boundary directive:** AUTH-REQ-01 Phase 1 Boundary Directive v0.1
> **Implementation artifact:** NOT PRESENT BEFORE AUTHORIZATION
> **Implementation:** NOT AUTHORIZED
> **Fixture preparation:** NOT AUTHORIZED
> **Execution:** NOT AUTHORIZED
> **IS mutation:** NOT AUTHORIZED
> **SimiGo code change:** NOT AUTHORIZED

## 1. Exact frozen-baseline bindings

These are immutable content bindings for every frozen basis used by this Request.
Commit identities do not replace these bindings.

```text
frozen_predicate_design_identity =
  SRS_VAL_01_DESIGN_V0_8;

frozen_predicate_design_path =
  docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_DESIGN_V0.8_20261007.md;

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

frozen_governance_package_path =
  docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_IMPLEMENTATION_FIXTURE_EXECUTION_AUTHORIZATION_PACKAGE_V0.6_20261007.md;

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

frozen_implementation_boundary_path =
  docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_IMPLEMENTATION_BOUNDARY_AUDIT_V0.1_20261007.md;

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

manifest_contract_path =
  docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_V1.0_20261007.md;

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
this Request and requires a new Request version.

Human approval must exact-bind this Request plus the four frozen-baseline bindings
above.
```

## 2. Request


This is a request for Human review and, only if approved, a separate
`IMPLEMENTATION`-only Stage Authorization Record.

```text
requested_stage_set = {
  IMPLEMENTATION
}
```

This request does not request:

```text
FIXTURE_PREPARATION;
EXECUTION;
IS_MUTATION;
network access;
Information Space mutation;
permission to modify Frozen Contracts;
permission to modify any unrelated target.
```

## 3. Requester and destination

```text
requester_identity =
  SRS_VAL_01_IMPLEMENTATION_REQUESTER;

requester_role =
  research agent acting on Human direction dated 2026-10-07;

request_destination_authority_chain =
  Runner Trust Anchor
    → Authorization Authority Root
    → Human Ruling;

request_destination_binding_rule =
  exact concrete anchor/root/ruling identities must be registered and verified
  before any Stage Authorization Record is created;

destination_binding_status =
  PENDING_HUMAN_RULING.
```

No Stage Authorization Record exists.

```text
stage_authorization_record =
  NOT_CREATED_PENDING_HUMAN_RULING.
```

## 4. Authorized repository basis

```text
authorized_repository_revision =
  eef3d24901e23b734bb887841528c0c7b4b42aa0;

authorized_branch =
  main;

authorized_working_tree_at_request_opening =
  clean except this Authorization Request, its filled Manifest Instance, their
  binding record, and the Phase 1 Boundary Directive.
```

## 5. Requested implementation scope

```text
target =
  T-IMPL-01 SRS-VAL Decision Core;

target_module =
  SettledRelationValidationCore;

candidate_source_placement =
  trackD-memory/Sources/SettledRelationValidationCore;
```

### 4.1 Authorized writable path set

```text
authorized_writable_path_set = {
  trackD-memory/Sources/SettledRelationValidationCore/;
  Package.swift
};
```

`Package.swift` may be edited only to register the new
`SettledRelationValidationCore` target with no external dependency and no change
to unrelated targets.

### 4.2 Forbidden path set

```text
forbidden_path_set = {
  every repository path not listed in authorized_writable_path_set;
  all existing source modules except new files under
    trackD-memory/Sources/SettledRelationValidationCore/;
  all Frozen Contract documents;
  all governance rulings and frozen manifest/package documents;
  all fixture directories;
  all execution/evidence directories;
  all Information Space storage.
}
```

## 6. Requested implementation effect set

```text
requested_effect_set = {
  CREATE_FILES_UNDER_TRACKD_MEMORY_SOURCES_SETTLEDRELATIONVALIDATIONCORE;
  EDIT_ROOT_PACKAGE_SWIFT_FOR_TARGET_REGISTRATION_ONLY;
  CREATE_IMMUTABLE_SOURCE_MODULE_ARTIFACT_AFTER_APPROVAL.
}
```

Forbidden effects:

```text
forbidden_effect_set = {
  RUN_VALIDATION_EXPERIMENT;
  CREATE_FIXTURE_ARTIFACTS;
  ACCESS_NETWORK;
  MUTATE_INFORMATION_SPACE;
  MODIFY_EXISTING_SEMANTIC_SOURCE;
  MODIFY_FROZEN_CONTRACT;
  AUTHORIZE_ANY_LATER_STAGE.
}
```

## 7. Dependency and purity policy

```text
allowed_dependency_set = {
  Swift standard library
};

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
  wall-clock/random/environment decision input.
}
```

## 8. Required artifact after separate approval

No implementation artifact exists in this Request. The following values are
deliberately absent and are not placeholders for future authorization:

```text
result_artifact_identity =
  NOT_PRESENT_BEFORE_IMPLEMENTATION_AUTHORIZATION;

result_artifact_content_address =
  NOT_PRESENT_BEFORE_IMPLEMENTATION_AUTHORIZATION;

result_artifact_integrity_binding =
  NOT_PRESENT_BEFORE_IMPLEMENTATION_AUTHORIZATION.
```

If Human grants IMPLEMENTATION only, the authorized work must produce:

```text
result_artifact_identity;
result_artifact_content_address;
result_artifact_integrity_binding;
changed_path_set;
forbidden_path_violation_count = 0;
forbidden_dependency_violation_count = 0;
scope_compliance_verdict.
```

That result artifact may not authorize FIXTURE_PREPARATION, EXECUTION, or
IS_MUTATION. A separate request and Human ruling are required.

## 9. Validity and budget

```text
validity_boundary =
  from Human approval, if granted, until Human withdrawal, expiration, or
  authorized completion record;

automatic_renewal = forbidden;

implementation_work_cycle_budget = 1;

execution_run_budget = 0;

fixture_preparation_budget = 0;

is_mutation_budget = 0.
```

## 10. Required Human decision

```text
APPROVE IMPLEMENTATION ONLY   create an IMPLEMENTATION-only Stage Authorization
                              Record exact-binding this Request.

REVISE REQUEST                return with registered defects.

DENY REQUEST                  do not implement.
```

No stage is authorized by opening this Request.

