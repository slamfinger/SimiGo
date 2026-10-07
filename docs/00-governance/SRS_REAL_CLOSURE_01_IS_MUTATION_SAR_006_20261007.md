# SRS-REAL-CLOSURE-01 Stage Authorization Record — IS_MUTATION 006

> **Status:** STAGE AUTHORIZATION RECORD — IS_MUTATION ONLY — CREATED UNDER
> HUMAN RULING
> **Date:** 2026-10-07
> **Human ruling, exact form:** “APPROVE S+E” on Request v0.9.
> **Required exact-commit instantiation:** the post-alignment execution
> repository commit is immutable `69b2227dbd9ec7bfc8ad744d65efe46e3a9ab33a`.
> The governance commit introducing this SAR is not the execution repository
> commit.

## 1. Authorization identity

```text
authorization_identity = SRS_REAL_CLOSURE_01_SAR_IS_MUTATION_006;
authorization_kind = STAGE_AUTHORIZATION_RECORD;
stage = IS_MUTATION;
stage_set = { IS_MUTATION };
stage_set_expansion = forbidden;
approved_request_identity =
  SRS_REAL_CLOSURE_01_EXECUTION_AUTHORIZATION_REQUEST_V0_9;
approved_request_commit = 51e6fd80a6435d566ba2a06ddd814e0945c46fce;
approved_request_git_blob_sha =
  c47e3c02fb499173222e137a3595c272dd7f1d9f;
approved_request_sha256 =
  01f55dc164e6980b5dec8edf1a067fe57bc37219387126f6fb7565995cc06afe;
human_ruling_identity =
  HUMAN_RULING_20261007_CORRECTED_EXECUTION_REQUEST_V0_9_APPROVE_S_PLUS_E;
human_ruling_content = “APPROVE S+E”;
exact_execution_repository_commit =
  69b2227dbd9ec7bfc8ad744d65efe46e3a9ab33a.
```

## 2. Authorized IS mutation effect

```text
is_mutation_scope =
  docs/02-evidence/srs-real-closure-01/runs/<run_id>/is/;
is_mutation_budget = one campaign's worth, exactly:
  1. materialize: D object + initial revision-1 mapping entry;
  2. es1: SRS record object + index entry;
  3. es2, only on REUSE: continuation record object + index entry;
  4. mutate-n1: D' object from aligned τN1 top-level d_prime_seed_path +
     revision-2 mapping entry.
```

The executor is exactly `es_runner.py` at Request v0.9 inherited state, modes
`materialize`, `es1`, `es2`, and `mutate-n1` only. All writes must obey
IS_LAYOUT invariants I-1..I-5. No overwrite, deletion, truncate, remap, or
out-of-scope write is authorized.

## 3. Boundary

```text
automatic_renewal = forbidden;
network_scope = NONE;
EXECUTION authority = EXECUTION SAR 006;
observer authority = OBSERVER AUTHORIZATION RECORD 006;
core claim = NOT ESTABLISHED.
```

## 4. Record integrity

```text
record_integrity_binding = registered by the governing commit introducing this
SAR on main; later modification creates a new content address and voids it.
```
