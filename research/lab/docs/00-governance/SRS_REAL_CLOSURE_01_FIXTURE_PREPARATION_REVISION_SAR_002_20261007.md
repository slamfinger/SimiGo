# SRS-REAL-CLOSURE-01 Stage Authorization Record — FIXTURE_PREPARATION REVISION 002

> **Status:** STAGE AUTHORIZATION RECORD — FIXTURE_PREPARATION REVISION ONLY —
> CREATED UNDER HUMAN RULING
> **Date:** 2026-10-07
> **Stage:** `FIXTURE_PREPARATION` (one new revision cycle; no other stage)
> **Authorization kind:** STAGE_AUTHORIZATION_RECORD
> **Governing request decision:** Human ruling of 2026-10-07: “同意 对 v0.7
> 的裁定” followed by “开展下一步工作” on Request v0.7 = APPROVE FIXTURE_
> PREPARATION REVISION ONLY.

## 1. Authorization identity and stage

```text
authorization_identity =
  SRS_REAL_CLOSURE_01_SAR_FIXTURE_PREPARATION_REVISION_002;
authorization_kind = STAGE_AUTHORIZATION_RECORD;
stage = FIXTURE_PREPARATION (revision cycle);
stage_set = { FIXTURE_PREPARATION };
stage_set_expansion = forbidden.
```

## 2. Immutable trust chain

```text
runner_trust_anchor_identity =
  SRS_VAL_01_AUTHORIZATION_PACKAGE_V0_6_RUNNER_TRUST_ANCHOR;
runner_trust_anchor_kind = IMMUTABLE_GOVERNANCE_ANCHOR;
runner_trust_anchor_governing_content =
  git:blob:fb05a60dc950f2f592580cfbc079dff2aa0f91db @ 6089f0b;
authorization_authority_root_identity = SRS_VAL_01_AUTHORIZATION_AUTHORITY_ROOT;
authorization_authority_root_content_address =
  git:blob:fb05a60dc950f2f592580cfbc079dff2aa0f91db;
trusted_human_authority_identity =
  HUMAN_AUTHORITY_SIMIGO_LAB_REPOSITORY_OWNER;
authorization_issuer_identity = SRS_REAL_CLOSURE_01_FIXTURE_REQUESTER;
issuer_status = ACTIVE_UNDER_THIS_RECORD;
human_ruling_identity = HUMAN_RULING_20261007_FIXTURE_REVISION_V0_7_APPROVE;
human_ruling_content =
  Human decision of 2026-10-07, exact form: “同意 对 v0.7 的裁定” +
  “开展下一步工作” on FIXTURE_PREPARATION REVISION Authorization Request
  v0.7 = APPROVE FIXTURE_PREPARATION REVISION ONLY;
approved_stage_or_role = FIXTURE_PREPARATION (revision cycle);
approval_status = APPROVED_FOR_NAMED_STAGE_OR_ROLE_ONLY;
approval_validity_boundary = until completion record v3, Human withdrawal,
  or expiry; automatic renewal forbidden.
```

## 3. Approved record exact bindings

```text
approved_request_identity =
  SRS_REAL_CLOSURE_01_FIXTURE_PREPARATION_REVISION_AUTHORIZATION_REQUEST_V0_7;
approved_request_commit = 5cfcc163a01bee4e801c886c8abc77133a956b72;
approved_request_git_blob_sha =
  77bc0c4f4de5d6c502a5752c3cd4a7b5c979621a;
approved_request_sha256 =
  bf21599175c62cdf3bdf536374bcd0a285b0bc82f2aa0857f58846780c1491dd;

inherited bindings (unchanged from Request v0.7 §2):
  Defect Register
    git:blob:c83c8b7597f0e1dc40d3e34d56fd8e5c3c521f2f,
    sha256 4851d4f7c650f2c1b23aa5948aed721217976b4efdb80a9956923029056a18c1;
  SRS_VAL_01_DESIGN_V0_8
    git:blob:dbbeb5cb4c5aa3a78ea9bf39029a21579d2244d4,
    sha256 1f661bdabcb511f811c9b653e27f1d2242241fca76ca7f2d7614c56ad5b30fd2;
  SRS_VAL_01_AUTHORIZATION_PACKAGE_V0_6
    git:blob:fb05a60dc950f2f592580cfbc079dff2aa0f91db,
    sha256 e16ca843999959c7583a1b34199c14ea083e456747a86bbb607c342bc493fe37;
  SRS-REAL-CLOSURE-01 Design v0.2
    git:blob:a28e8d9b95b35bb287644a0bc04175e7e800e18e,
    sha256 d43792b53ce6830cf19bac387be6bc24fd1e0205e3b96f78a695e5976917b6fe;
  consumed REVISION SAR 001 @ fdf45ea;
  canonical-but-not-final work state @ e729e32.
```

## 4. Repository revision and environment

```text
repository_revision_at_authorization =
  b36468d7d3b9435e4e8b87a55d32dd3005573435
  (branch main, clean tree, origin/main verified; this SAR's introducing
  commit is the next commit);
environment_identity = Darwin 25.6.0 arm64; Python 3.9.6.
```

## 5. Authorized effect, scope, and budgets

```text
authorized_effect_set = {
  REPAIR_ES_RUNNER_PER_RF4_5_RF4_6_ONLY;
  RUN_INSTRUMENT_SELF_VALIDATION_SV1_SV6_IN_ONE_TEMPORARY_DIRECTORY;
  DELIVER_FIXTURE_MANIFEST_V3_AND_COMPLETION_RECORD_V3;
  PUSH_AND_LS_REMOTE_VERIFY;
}

forbidden_effect_set = {
  RUN_ANY_FULL_OR_PARTIAL_CAMPAIGN_SEQUENCE_UNDER_ANY_NAME;
  RUN_OBSERVER_CAMPAIGN;
  MATERIALIZE_INFORMATION_SPACE outside the discarded sandbox;
  ACCESS_NETWORK from fixture code;
  MODIFY_F1_F2_F3_SNAPSHOT_MECHANICS_WRITER_INVARIANT_DESIGN_OR_FROZEN_
    CONTRACTS;
  MODIFY_T_IMPL_01_ADAPTER_SCHEMA_LAYOUT_TAU_ORIGINALS_OBSERVER_REPOSITORY_
    SOURCES_OR_PACKAGE_SWIFT;
  WRITE_ANY_REPO_PATH_OUTSIDE_DOCS_02_EVIDENCE_SRS_REAL_CLOSURE_01_FIXTURE;
  AUTHORIZE_EXECUTION_IS_MUTATION_OR_ANY_LATER_STAGE.
}

filesystem_scope = {
  authorized_writable_path_set = {
    docs/02-evidence/srs-real-closure-01/fixture/runner/es_runner.py;
    docs/02-evidence/srs-real-closure-01/fixture/FIXTURE_MANIFEST.md;
    docs/02-evidence/srs-real-closure-01/fixture/
      FIXTURE_PREPARATION_COMPLETION_RECORD.md;
  };
  plus one temporary self-validation directory outside the repository,
  discarded after SV-1..SV-6;
  docs/00-governance/ is forbidden to the work cycle because this SAR
  governance commit precedes and authorizes it;
  forbidden_path_violation_count must equal 0.
}

network_scope = NONE;
execution_run_budget = 0;
is_mutation_budget = 0;
implementation_work_cycle_budget = 0;
fixture_revision_work_cycle_budget = 1;
automatic_renewal = forbidden.
```

## 6. Work-cycle obligations

```text
sequence:
  1. after this SAR is canonical and push/ls-remote verified, apply only
     RF-4.5, RF-4.6, and RF-4.6m to es_runner.py;
  2. rerun SV-1..SV-6 in the temporary sandbox, including field-level
     SV-4.5 / SV-4.6 / SV-4.6m assertions and the v0.6 SV-4c-0 event order;
  3. deliver FIXTURE_MANIFEST v3 and completion record v3, carrying the ten
     unchanged artifacts byte-identically and mapping changes only to
     RF-4.5 / RF-4.6 / RF-4.6m;
  4. push + ls-remote verify; STOP for fresh Human acceptance review.

This record does not authorize EXECUTION, IS_MUTATION, an Observer campaign,
or any core-claim assertion.
```

## 7. Record integrity binding

```text
record_integrity_binding = registered by the governing commit introducing
this SAR on main; any later modification creates a new content address and
voids this record.
```
