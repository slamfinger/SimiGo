# SRS-REAL-CLOSURE-01 Stage Authorization Record — IS_MUTATION 001

> **Status:** STAGE AUTHORIZATION RECORD — IS_MUTATION ONLY — CREATED UNDER
> HUMAN RULING
> **Date:** 2026-10-07
> **Human ruling, exact form:** “批准” on Request v0.3 = APPROVE A+B+C.
> **Required exact-commit instantiation:** the execution repository commit is
> immutable `edf7d4adaac8b43bf6e63b64f177708268cf0428`. The later governance
> commit introducing this SAR is not the execution repository commit.

## 1. Authorization identity

```text
authorization_identity = SRS_REAL_CLOSURE_01_SAR_IS_MUTATION_001;
authorization_kind = STAGE_AUTHORIZATION_RECORD;
stage = IS_MUTATION;
stage_set = { IS_MUTATION };
stage_set_expansion = forbidden;
approved_request_identity =
  SRS_REAL_CLOSURE_01_EXECUTION_AUTHORIZATION_REQUEST_V0_3;
approved_request_commit = 1088a0c27f64fcbd59c207460d9b7576e6797e9e;
approved_request_git_blob_sha =
  a3760c8de0bc7c2ad9cd70ac0eaecce8fbdc433f;
approved_request_sha256 =
  b63c71aa1a0ac978a3e6deeae02a168dac5be9a599d553ccd4ba633f0664671f;
human_ruling_identity =
  HUMAN_RULING_20261007_EXECUTION_REQUEST_V0_3_APPROVE;
human_ruling_content = “批准” = APPROVE A+B+C;
exact_repository_commit = edf7d4adaac8b43bf6e63b64f177708268cf0428;
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

The executor is exactly `es_runner.py` at §2.1 of Request v0.3, modes
`materialize`, `es1`, `es2`, and `mutate-n1` only. All writes must obey
IS_LAYOUT invariants I-1..I-5. No overwrite, deletion, truncate, remap, or
out-of-scope write is authorized.

## 3. Boundary

```text
automatic_renewal = forbidden;
network_scope = NONE;
EXECUTION process authority = EXECUTION SAR 001;
observer authority = OBSERVER AUTHORIZATION RECORD 001;
core claim = NOT ESTABLISHED.
```

## 4. Record integrity

```text
record_integrity_binding = registered by the governing commit introducing
this SAR on main; later modification creates a new content address and voids
this SAR.
```
