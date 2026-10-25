# SRS-REAL-CLOSURE-01 Stage Authorization Record — IS_MUTATION 005

> **Status:** STAGE AUTHORIZATION RECORD — IS_MUTATION ONLY — CREATED UNDER
> HUMAN RULING
> **Date:** 2026-10-07
> **Human ruling, exact form:** “批准`APPROVE T+E`” on Request v0.7 =
> APPROVE T+E.
> **Required exact-commit instantiation:** the post-completion execution
> repository commit is immutable
> `fef0b2fa5b3ac817a099bac885522fd17f4d3362`. The governance commit introducing
> this SAR is not the execution repository commit.

## 1. Authorization identity

```text
authorization_identity = SRS_REAL_CLOSURE_01_SAR_IS_MUTATION_005;
authorization_kind = STAGE_AUTHORIZATION_RECORD;
stage = IS_MUTATION;
stage_set = { IS_MUTATION };
stage_set_expansion = forbidden;
approved_request_identity =
  SRS_REAL_CLOSURE_01_EXECUTION_AUTHORIZATION_REQUEST_V0_7;
approved_request_commit = e721f7a7460d3fbe0fe42c388bd4d07ce44709c2;
approved_request_git_blob_sha =
  e04a1219931327fc9a612d7e328a458f27085a8f;
approved_request_sha256 =
  fa393cabb5af5f881c912d5b8b12c6791c25c33240bc166ec3b8e0c52998b577;
human_ruling_identity =
  HUMAN_RULING_20261007_CORRECTED_EXECUTION_REQUEST_V0_7_APPROVE_T_PLUS_E;
human_ruling_content = “批准`APPROVE T+E`” = APPROVE T+E;
exact_execution_repository_commit =
  fef0b2fa5b3ac817a099bac885522fd17f4d3362.
```

## 2. Authorized IS mutation effect

```text
is_mutation_scope =
  docs/02-evidence/srs-real-closure-01/runs/<run_id>/is/;
is_mutation_budget = one campaign's worth, exactly:
  1. materialize: D object + initial revision-1 mapping entry;
  2. es1: SRS record object + index entry;
  3. es2, only on REUSE: continuation record object + index entry;
  4. mutate-n1: D' object from completed τN1 d_prime_seed_path +
     revision-2 mapping entry.
```

The executor is exactly `es_runner.py` at Request v0.7 §2.1, modes
`materialize`, `es1`, `es2`, and `mutate-n1` only. All writes must obey
IS_LAYOUT invariants I-1..I-5. No overwrite, deletion, truncate, remap, or
out-of-scope write is authorized.

## 3. Boundary

```text
automatic_renewal = forbidden;
network_scope = NONE;
EXECUTION authority = EXECUTION SAR 005;
observer authority = OBSERVER AUTHORIZATION RECORD 005;
core claim = NOT ESTABLISHED.
```

## 4. Record integrity

```text
record_integrity_binding = registered by the governing commit introducing this
SAR on main; later modification creates a new content address and voids it.
```
