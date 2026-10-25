# SRS-REAL-CLOSURE-01 Stage Authorization Record — EXECUTION 002

> **Status:** STAGE AUTHORIZATION RECORD — EXECUTION ONLY — CREATED UNDER
> HUMAN RULING
> **Date:** 2026-10-07
> **Human ruling, exact form:** “授权完整实验执行权限，即 `APPROVE A+B+C`”
> on corrected Request v0.4 = APPROVE A+B+C.
> **Required exact-commit instantiation:** the execution repository commit is
> immutable `9966d311e7e52ab3f5ca828e593ea569cddb008e`. The governance commit
> introducing this SAR is not the execution repository commit.

## 1. Authorization identity

```text
authorization_identity = SRS_REAL_CLOSURE_01_SAR_EXECUTION_002;
authorization_kind = STAGE_AUTHORIZATION_RECORD;
stage = EXECUTION;
stage_set = { EXECUTION };
stage_set_expansion = forbidden;
approved_request_identity =
  SRS_REAL_CLOSURE_01_EXECUTION_AUTHORIZATION_REQUEST_V0_4;
approved_request_commit = 79ce4e3d313f13b66f946e2ed1e948745e4a1e82;
approved_request_git_blob_sha =
  0b892d66103c736806a3ef54377cd82f3cbfe167;
approved_request_sha256 =
  d64e4ebcc821f70601960cc53bea5b7e42630bd0d61a3edfd29ae476ca8368c4;
human_ruling_identity =
  HUMAN_RULING_20261007_CORRECTED_EXECUTION_REQUEST_V0_4_APPROVE;
human_ruling_content =
  “授权完整实验执行权限，即 `APPROVE A+B+C`” = APPROVE A+B+C;
exact_repository_commit = 9966d311e7e52ab3f5ca828e593ea569cddb008e;
```

## 2. Authorized execution effect

```text
authorized_effect_set = {
  VERIFY_REQUEST_V0_4_BINDINGS_AT_STEP_0;
  BUILD_BOUND_ADAPTER_IN_TEMPORARY_DIRECTORY_BEFORE_FIRST_USE;
  RECONSTRUCT_AND_RUN_ENV_PROBE_V1_BEFORE_MATERIALIZATION;
  WRITE_RUNTIME_BINDING_JSON_AND_ENVIRONMENT_MEASUREMENT_JSON_UNDER_RUNS_
    RUN_ID;
  RUN_BOUND_DRIVER_AND_ES_PROCESSES_PER_FROZEN_SEQUENCE;
  WRITE_EVENT_LOGS_INVOCATION_GRAPHS_AND_DECISION_OUTPUTS_UNDER_RUNS_RUN_ID;
}

forbidden_effect_set = {
  INFORMATION_SPACE_MUTATION (authorized separately by IS_MUTATION SAR 002);
  observer execution (authorized separately by OAR 002);
  network; campaign rerun; fixture/source/governance mutation;
  post-hoc expected-decision reinterpretation; governance-text repair.
}
```

## 3. Runtime and environment

```text
runtime_artifact_identity =
  SRS-REAL-CLOSURE-01-ADAPTER-RUNTIME-ARTIFACT-V1;
runtime_artifact_integrity_binding =
  sha256 e88c996b9a64df10dd03f7622ffa8757551baf352908e4d7bf8704295eaffcc7;
environment_measurement_artifact =
  SRS-REAL-CLOSURE-01-ENV-PROBE-V1,
  sha256 79744078f5fca89f4f8b36701e4c05c7859bbf166451dcd0915b20b5fe6661af;
expected_environment_identity =
  sha256 ad2abb6809ead5a4d198f35d6f1b8a06624a803c6fc7e161dbb06f1f0838f15a.
```

The execution code and fixture inputs must come from detached exact state
`9966d31`. Step 0 must verify Request v0.4 and all Request §2 bindings, rebuild
and verify the adapter, reconstruct/run ENV-PROBE-V1, compare the corrected
environment identity, and write `runtime_binding.json` and
`environment_measurement.json` before materialization. Any mismatch stops the
campaign as INVALID.

## 4. Scope, budgets, and boundary

```text
execution_campaign_budget = 1;
fixture_preparation_budget = 0;
implementation_work_cycle_budget = 0;
automatic_renewal = forbidden;
writable_execution_evidence_scope =
  docs/02-evidence/srs-real-closure-01/runs/<run_id>/ except
  runs/<run_id>/is/, whose writes are exclusively under IS_MUTATION SAR 002;
temporary directory outside repository = build/probe only, discarded after
  evidence-package completion;
network_scope = NONE.
```

## 5. Record integrity

```text
record_integrity_binding = registered by the governing commit introducing
this SAR on main; later modification creates a new content address and voids
this SAR.
```
