# AUTH-REQ-01 — Human Authorization Request v0.1

> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE AUTHORIZED
> **Date:** 2026-10-07
> **Request object:** AUTH-REQ-01 Human Authorization Request v0.1
> **Review ruling:** REVISE REQUEST; see `docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_AUTH_REQ_01_V0.1_REVIEW_RULING_20261007.md`.
> **Superseded by:** AUTH-REQ-01 Human Authorization Request v0.2.
> **Requested stage set:** `{ IMPLEMENTATION }`
> **Frozen predicate basis:** SRS-VAL-01 Design v0.8 at `1170208`
> **Frozen governance basis:** Authorization Package v0.6 at `047b221`, accepted at `6089f0b`
> **Frozen boundary basis:** Implementation Boundary Audit v0.1 at `cb95c09`
> **Frozen manifest contract:** Run/Implementation Manifest Contract v1.0 at `f69a0e2`
> **Phase 1 boundary directive:** AUTH-REQ-01 Phase 1 Boundary Directive v0.1
> **Implementation artifact:** NOT PRESENT BEFORE AUTHORIZATION
> **Implementation:** NOT AUTHORIZED
> **Fixture preparation:** NOT AUTHORIZED
> **Execution:** NOT AUTHORIZED
> **IS mutation:** NOT AUTHORIZED
> **SimiGo code change:** NOT AUTHORIZED

## 1. Request

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

## 2. Requester and destination

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

## 3. Authorized repository basis

```text
authorized_repository_revision =
  eef3d24901e23b734bb887841528c0c7b4b42aa0;

authorized_branch =
  main;

authorized_working_tree_at_request_opening =
  clean except this Authorization Request, its filled Manifest Instance, their
  binding record, and the Phase 1 Boundary Directive.
```

## 4. Requested implementation scope

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

## 5. Requested implementation effect set

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

## 6. Dependency and purity policy

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

## 7. Required artifact after separate approval

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

## 8. Validity and budget

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

## 9. Required Human decision

```text
APPROVE IMPLEMENTATION ONLY   create an IMPLEMENTATION-only Stage Authorization
                              Record exact-binding this Request.

REVISE REQUEST                return with registered defects.

DENY REQUEST                  do not implement.
```

No stage is authorized by opening this Request.

