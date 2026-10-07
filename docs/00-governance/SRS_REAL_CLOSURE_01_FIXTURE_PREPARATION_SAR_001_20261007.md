# SRS-REAL-CLOSURE-01 Stage Authorization Record — FIXTURE_PREPARATION 001

> **Status:** STAGE AUTHORIZATION RECORD — FIXTURE_PREPARATION ONLY — CREATED UNDER HUMAN RULING
> **Date:** 2026-10-07
> **Stage:** `FIXTURE_PREPARATION` (exactly one stage; no other stage is authorized)
> **Authorization kind:** STAGE_AUTHORIZATION_RECORD
> **Governing request decision:** Human ruling of 2026-10-07 in the authorized
> review channel: "裁定：A = ACCEPT" on FIXTURE_PREPARATION Authorization
> Request v0.2 (six-point audit: R3 closure PASS, stage boundary PASS,
> self-verification boundary PASS, completion-record design PASS, lineage
> PASS, Critical Path untouched PASS).

## 1. Authorization identity and stage

```text
authorization_identity =
  SRS_REAL_CLOSURE_01_SAR_FIXTURE_PREPARATION_001;

authorization_kind =
  STAGE_AUTHORIZATION_RECORD;

stage =
  FIXTURE_PREPARATION;

stage_set = {
  FIXTURE_PREPARATION
};

stage_set_expansion = forbidden;
```

## 2. Immutable trust chain (Authorization Package v0.6 §4.1–4.3)

```text
runner_trust_anchor_identity =
  SRS_VAL_01_AUTHORIZATION_PACKAGE_V0_6_RUNNER_TRUST_ANCHOR;

runner_trust_anchor_kind =
  IMMUTABLE_GOVERNANCE_ANCHOR;

runner_trust_anchor_governing_content =
  git:blob:fb05a60dc950f2f592580cfbc079dff2aa0f91db @ 6089f0bf630af6e85e705fe42f8de2d2327e5200;

authorization_authority_root_identity =
  SRS_VAL_01_AUTHORIZATION_AUTHORITY_ROOT;

authorization_authority_root_content_address =
  git:blob:fb05a60dc950f2f592580cfbc079dff2aa0f91db
  (root record embedded in frozen Authorization Package v0.6 §4.2);

trusted_human_authority_identity =
  HUMAN_AUTHORITY_SIMIGO_LAB_REPOSITORY_OWNER;

authorization_issuer_identity =
  SRS_REAL_CLOSURE_01_FIXTURE_REQUESTER;

issuer_authority_scope =
  prepare, self-verify, and register the SRS-REAL-CLOSURE-01 fixture within
  the authorized scope below;

issuer_status =
  ACTIVE_UNDER_THIS_RECORD;

human_ruling_identity =
  HUMAN_RULING_20261007_FIXTURE_PREP_APPROVE;

human_ruling_content =
  Human decision of 2026-10-07, exact form: "裁定：A = ACCEPT" on
  FIXTURE_PREPARATION Authorization Request v0.2 = APPROVE
  FIXTURE_PREPARATION ONLY;

approved_stage_or_role =
  FIXTURE_PREPARATION;

approval_status =
  APPROVED_FOR_NAMED_STAGE_OR_ROLE_ONLY;

approval_validity_boundary =
  from this record's creation until the authorized fixture completion
  record, Human withdrawal, or expiry; automatic renewal forbidden.
```

## 3. Approved record exact bindings

```text
approved_request_identity =
  SRS_REAL_CLOSURE_01_FIXTURE_PREPARATION_AUTHORIZATION_REQUEST_V0_2;

approved_request_commit =
  7d590d7fe3a6b85b055567a4be4bd1846d60831a;

approved_request_git_blob_sha =
  99f13727db032fb31417f7f648a4893a0daab4ae;

approved_request_sha256 =
  dc5f3582bc2f1dbc5050007bb26e7c64903a9cb7e53b92336a0a34597e87a344;

binding_lineage (inherited from approved Request §1, unchanged):
  frozen_predicate_design   SRS_VAL_01_DESIGN_V0_8 @ 1170208,
                            git:blob:dbbeb5cb4c5aa3a78ea9bf39029a21579d2244d4,
                            sha256 1f661bdabcb511f811c9b653e27f1d2242241fca76ca7f2d7614c56ad5b30fd2;
  frozen_governance_package SRS_VAL_01_AUTHORIZATION_PACKAGE_V0_6 @ 6089f0b,
                            git:blob:fb05a60dc950f2f592580cfbc079dff2aa0f91db,
                            sha256 e16ca843999959c7583a1b34199c14ea083e456747a86bbb607c342bc493fe37;
  experiment_design         SRS_REAL_CLOSURE_01_DESIGN_…_V0_2 @ 050b918,
                            git:blob:a28e8d9b95b35bb287644a0bc04175e7e800e18e,
                            sha256 d43792b53ce6830cf19bac387be6bc24fd1e0205e3b96f78a695e5976917b6fe;
  implementation_completion_record @ 07176ec,
                            git:blob:0d75ef9bf7b072b91b960d733c3ba7dfcc155c66,
                            sha256 4a40492e9be09b1bf3ccfc38fbe06badf50243225ccbf6af89c4e1fbbc81e5f1;
  t_impl_01_components      git:blob:0fd65bdf40b7c9885de2ada491d66348ebfa28fa /
                            cbd24721a97f3c06e012fb02649feb19c2b9cb8b /
                            9f11ef1af45be6bc9450e0fbdc0117211f99a74a
                            (sha256 6583a804… / e219aeea… / 97252170…).
```

## 4. Repository revision and environment

```text
repository_revision_at_authorization =
  7d590d7fe3a6b85b055567a4be4bd1846d60831a (branch main, working tree clean
  at ruling time; this SAR's introducing commit is the next commit);

environment_identity =
  darwin 25.6.0 arm64; Apple Swift 6.4 (swift-driver 1.168.6);
  swift-tools-version 5.9 root manifest; python3 (system);

fixture_identities =
  TO_BE_REGISTERED_BY_FIXTURE_MANIFEST (produced under this record);
```

## 5. Authorized effect, filesystem scope, and budgets

```text
authorized_effect_set = {
  CREATE_FIXTURE_FILES_UNDER_DOCS_02_EVIDENCE_SRS_REAL_CLOSURE_01_FIXTURE;
  CREATE_FIXTURE_MANIFEST_AFTER_PREPARATION;
  CREATE_FIXTURE_STAGE_COMPLETION_RECORD_WITHIN_FIXTURE_SUBTREE;
  FIXTURE_BUILD_VERIFICATION_IN_TEMPORARY_DIRECTORY.
}

forbidden_effect_set = {
  RUN_VALIDATION_EXPERIMENT;
  MATERIALIZE_INFORMATION_SPACE;
  ACCESS_NETWORK;
  MODIFY_T_IMPL_01_ARTIFACT_OR_COMPLETION_RECORD;
  MODIFY_FROZEN_CONTRACT;
  MODIFY_REPOSITORY_SOURCES_OR_MANIFEST;
  WRITE_OUTSIDE_THE_AUTHORIZED_FIXTURE_SUBTREE;
  AUTHORIZE_ANY_LATER_STAGE.
}

filesystem_scope = {
  authorized_writable_path_set = {
    docs/02-evidence/srs-real-closure-01/fixture/
  };
  explicitly included (R3): fixture/FIXTURE_PREPARATION_COMPLETION_RECORD.md;
  explicitly forbidden: docs/00-governance/ in its entirety; Package.swift;
  all source modules; all Frozen Contract documents; all other evidence
  directories;
  forbidden_path_violation_count must equal 0 at completion.
}

network_scope = NONE;

execution_run_budget = 0;
is_mutation_budget = 0;
implementation_work_cycle_budget = 0;
fixture_preparation_work_cycle_budget = 1;
use_budget = 1 fixture preparation work cycle;
automatic_renewal = forbidden.
```

## 6. Completion obligations (Request v0.2 §8, R3-closed)

Upon completion, INSIDE the authorized fixture subtree, the work must produce:

```text
fixture/FIXTURE_MANIFEST.md
  per-artifact content addresses and SHA256 bindings; computation
  parameters (N = 50000; procedure identity/version); IS layout
  declaration reference;

fixture/FIXTURE_PREPARATION_COMPLETION_RECORD.md
  registering: fixture_stage_completion_record_identity;
  fixture_stage_completion_record_content_address;
  fixture_manifest_identity + content address + integrity binding;
  per-artifact bindings; changed_path_set (all within the fixture subtree);
  forbidden_path_violation_count = 0; forbidden_dependency_violation_count = 0;
  scope_compliance_verdict = PASS (required); completion_validity_boundary.
```

This record does not authorize EXECUTION or IS_MUTATION. The later EXECUTION
authorization request must exact-bind the completed fixture manifest and
completion record and declare the explicitly scoped IS_MUTATION effect set
(Design v0.2 §9) before any process runs.

## 7. Record integrity binding

```text
record_integrity_binding =
  registered by the governing commit that introduces this record on main;
  any later modification of this file creates a new content address and
  voids this record;

sequence_discipline =
  SAR first (this commit); fixture preparation only after this record is
  canonical; fixture completion artifacts pushed and ls-remote verified
  before the stage is reported complete.
```
