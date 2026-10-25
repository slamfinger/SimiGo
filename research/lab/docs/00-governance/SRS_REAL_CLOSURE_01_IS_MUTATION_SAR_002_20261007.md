# SRS-REAL-CLOSURE-01 Stage Authorization Record — IS_MUTATION 002

> **Status:** STAGE AUTHORIZATION RECORD — IS_MUTATION ONLY — CREATED UNDER
> HUMAN RULING
> **Date:** 2026-10-07
> **Human ruling, exact form:** “授权完整实验执行权限，即 `APPROVE A+B+C`”
> on corrected Request v0.4 = APPROVE A+B+C.
> **Required exact-commit instantiation:** the execution repository commit is
> immutable `9966d311e7e52ab3f5ca828e593ea569cddb008e`. The governance commit
> introducing this SAR is not the execution repository commit.

## 1. Authorization identity

```text
authorization_identity = SRS_REAL_CLOSURE_01_SAR_IS_MUTATION_002;
authorization_kind = STAGE_AUTHORIZATION_RECORD;
stage = IS_MUTATION;
stage_set = { IS_MUTATION };
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

## 2. Authorized IS mutation effect

```text
is_mutation_scope =
  docs/02-evidence/srs-real-closure-01/runs/<run_id>/is/;
is_mutation_budget = one campaign's worth, exactly:
  1. materialize: D object + initial revision-1 mapping entry;
  2. es1: SRS record object + index entry;
  3. es2, only on REUSE: continuation record object + index entry;
  4. mutate-n1: D' object + one revision-2 mapping entry.
```

The executor is exactly `es_runner.py` at Request v0.4 §2.1, modes
`materialize`, `es1`, `es2`, and `mutate-n1` only. All writes must obey
IS_LAYOUT invariants I-1..I-5. No overwrite, deletion, truncate, remap, or
out-of-scope write is authorized.

## 3. Boundary

```text
automatic_renewal = forbidden;
network_scope = NONE;
EXECUTION process authority = EXECUTION SAR 002;
observer authority = OBSERVER AUTHORIZATION RECORD 002;
core claim = NOT ESTABLISHED.
```

## 4. Record integrity

```text
record_integrity_binding = registered by the governing commit introducing
this SAR on main; later modification creates a new content address and voids
this SAR.
```
