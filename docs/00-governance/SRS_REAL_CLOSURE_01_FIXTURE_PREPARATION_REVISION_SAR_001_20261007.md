# SRS-REAL-CLOSURE-01 Stage Authorization Record — FIXTURE_PREPARATION REVISION 001

> **Status:** STAGE AUTHORIZATION RECORD — FIXTURE_PREPARATION REVISION ONLY — CREATED UNDER HUMAN RULING
> **Date:** 2026-10-07
> **Stage:** `FIXTURE_PREPARATION` (revision cycle; exactly one stage; no other stage authorized)
> **Authorization kind:** STAGE_AUTHORIZATION_RECORD
> **Governing request decision:** Human ruling of 2026-10-07: "裁定：A = ACCEPT"
> on FIXTURE_PREPARATION REVISION Authorization Request v0.6 (five-point
> closure audit PASS; SV-4c-0 event-order implementation requirement
> registered as an execution-time mechanical requirement of this SAR, §6).

## 1. Authorization identity and stage

```text
authorization_identity =
  SRS_REAL_CLOSURE_01_SAR_FIXTURE_PREPARATION_REVISION_001;

authorization_kind =
  STAGE_AUTHORIZATION_RECORD;

stage =
  FIXTURE_PREPARATION (revision cycle);

stage_set = {
  FIXTURE_PREPARATION
};

stage_set_expansion = forbidden.
```

## 2. Immutable trust chain (Authorization Package v0.6 §4.1–4.3)

```text
runner_trust_anchor_identity =
  SRS_VAL_01_AUTHORIZATION_PACKAGE_V0_6_RUNNER_TRUST_ANCHOR;
runner_trust_anchor_kind = IMMUTABLE_GOVERNANCE_ANCHOR;
runner_trust_anchor_governing_content =
  git:blob:fb05a60dc950f2f592580cfbc079dff2aa0f91db @ 6089f0b;
authorization_authority_root_identity = SRS_VAL_01_AUTHORIZATION_AUTHORITY_ROOT;
authorization_authority_root_content_address =
  git:blob:fb05a60dc950f2f592580cfbc079dff2aa0f91db;
trusted_human_authority_identity = HUMAN_AUTHORITY_SIMIGO_LAB_REPOSITORY_OWNER;
authorization_issuer_identity = SRS_REAL_CLOSURE_01_FIXTURE_REQUESTER;
issuer_status = ACTIVE_UNDER_THIS_RECORD;
human_ruling_identity = HUMAN_RULING_20261007_FIXTURE_REVISION_APPROVE;
human_ruling_content =
  Human decision of 2026-10-07, exact form: "裁定：A = ACCEPT" on
  FIXTURE_PREPARATION REVISION Authorization Request v0.2-lineage v0.6
  = APPROVE FIXTURE_PREPARATION REVISION ONLY;
approved_stage_or_role = FIXTURE_PREPARATION (revision cycle);
approval_status = APPROVED_FOR_NAMED_STAGE_OR_ROLE_ONLY;
approval_validity_boundary = until the revision completion record v2,
  Human withdrawal, or expiry; automatic renewal forbidden.
```

## 3. Approved record exact bindings

```text
approved_request_identity =
  SRS_REAL_CLOSURE_01_FIXTURE_PREPARATION_REVISION_AUTHORIZATION_REQUEST_V0_6;

approved_request_commit =
  c01f0bfbb578db3e371151d343906619270a67e6;

approved_request_git_blob_sha =
  d6eee39f6bf37f1536d152e56509f02f77d8afd3;

approved_request_sha256 =
  06c969c2dfe9dea527833690e519303b7aecb876673165ac12011db0f2c2722e;

inherited bindings (unchanged from the approved Request §1):
  defect_register (D-SEC-1 corrected), SRS-VAL v0.8, Authorization Package
  v0.6, Design v0.2, T-IMPL-01 three canonical components, FIXTURE_MANIFEST
  v1 and completion record v1 (to be superseded by this revision's v2
  outputs).
```

## 4. Repository revision and environment

```text
repository_revision_at_authorization =
  c01f0bfbb578db3e371151d343906619270a67e6 (branch main, clean tree; this
  SAR's introducing commit is the next commit);

environment_identity =
  darwin 25.6.0 arm64; Apple Swift 6.4; python3 (system);
```

## 5. Authorized effect, filesystem scope, and budgets

```text
authorized_effect_set = {
  REPAIR_ES_RUNNER_PER_F1_F4;
  RUN_INSTRUMENT_SELF_VALIDATION_SV1_SV6_IN_TEMPORARY_DIRECTORY;
  DELIVER_F5_OUTPUTS_FIXTURE_MANIFEST_V2_AND_COMPLETION_RECORD_V2;
}

forbidden_effect_set = {
  RUN_ANY_FULL_OR_PARTIAL_CAMPAIGN_SEQUENCE_UNDER_ANY_NAME;
  RUN_OBSERVER_CAMPAIGN;
  MATERIALIZE_INFORMATION_SPACE (outside the sandbox, which is discarded);
  ACCESS_NETWORK;
  MODIFY_T_IMPL_01_ARTIFACT_OR_COMPLETION_RECORD;
  MODIFY_FROZEN_CONTRACT;
  MODIFY_REPOSITORY_SOURCES_OR_PACKAGE_SWIFT;
  WRITE_ANY_REPO_PATH_OUTSIDE_DOCS_02_EVIDENCE_SRS_REAL_CLOSURE_01_FIXTURE;
  AUTHORIZE_ANY_LATER_STAGE.
}

filesystem_scope = {
  authorized_writable_path_set = {
    docs/02-evidence/srs-real-closure-01/fixture/
      (runner/es_runner.py; FIXTURE_MANIFEST.md;
       FIXTURE_PREPARATION_COMPLETION_RECORD.md);
  };
  plus the temporary self-validation directory outside the repository
  (discarded after SV-1..SV-6);
  docs/00-governance/ in its entirety = forbidden to the work cycle
  (this SAR governance commit precedes and authorizes it);
  forbidden_path_violation_count must equal 0 at completion.
}

network_scope = NONE;
execution_run_budget = 0;
is_mutation_budget = 0;
implementation_work_cycle_budget = 0;
fixture_revision_work_cycle_budget = 1;
automatic_renewal = forbidden.
```

## 6. Work-cycle obligations and mechanical requirements

```text
sequence:
  1. apply F-1..F-4 to es_runner.py (Defect Register D-6/D-7/D-8/D-9;
     §9 IMMUTABLE_SNAPSHOT_PRESEALED instrument with mapping snapshot
     boundary, metadata-only post-snapshot checks, closed-world writer
     invariant);
  2. run SV-1..SV-6 in the temporary directory;
     SV-4c-0 EVENT-ORDER REQUIREMENT (Human directive, binding):
       the harness must strictly fix the event order
         capture start_size → freeze the test boundary → append rev2 →
         complete the prefix capture;
       "append before acquisition" must be implemented as append AFTER
       start_size capture and BEFORE prefix-capture completion — never as
       an append that precedes start_size capture (which would test a new
       instance instead of the exclusion of the append from an established
       snapshot);
  3. deliver F-5 outputs: FIXTURE_MANIFEST v2 (changed artifacts re-bound,
     unchanged artifacts carried, changelog mapped to defect IDs) and
     FIXTURE_PREPARATION_COMPLETION_RECORD v2 (inside the fixture subtree
     per R3; violation counts 0; scope PASS);
  4. push + ls-remote verify; STOP.

this record does not authorize EXECUTION, IS_MUTATION, or any campaign
sequence. The next lawful object after the STOP is EXECUTION Authorization
Request v0.3, exact-binding the revised manifest.
```

## 7. Record integrity binding

```text
record_integrity_binding =
  registered by the governing commit that introduces this record on main;
  any later modification of this file creates a new content address and
  voids this record.
```
