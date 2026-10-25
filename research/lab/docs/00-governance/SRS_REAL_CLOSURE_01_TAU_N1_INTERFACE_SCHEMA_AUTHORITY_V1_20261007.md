# SRS-REAL-CLOSURE-01 — τN1 Interface Schema Authority v1

> **Status:** AUTHORITATIVE INTERFACE SCHEMA — BINDING FOR FUTURE CORRECTED
> EXECUTION REQUESTS AND RECORDS
> **Date:** 2026-10-07
> **Authority basis:** EXEC-005 Schema Authority Forensic Audit @ `9616133…`
> ruling `TAU_N1_RUNNER_SCHEMA_AUTHORITY_ABSENCE`.
> **Purpose:** establish the single authoritative τN1 interface contract before
> any corrected Request/records are drafted.
> **Authorization effect:** NONE. This schema does not modify τN1, runner,
> fixture, or campaign state and does not authorize execution.

## 1. Schema identity

```text
schema_authority_identity =
  SRS_REAL_CLOSURE_01_TAU_N1_INTERFACE_SCHEMA_AUTHORITY_V1;
applies_to =
  static fixture τN1 and its runtime copy after srs_identity substitution;
canonical_execution_cwd =
  <exact_worktree>/docs/02-evidence/srs-real-closure-01;
d_prime_path_resolution_base = canonical_execution_cwd;
```

## 2. Required top-level fields

For `mutate-n1`, the authoritative contract requires these fields at τN1
top level:

```text
dependencies:
  array of length 1;
  dependencies[0].dependency_id = "D-1" (string);

d_prime_seed_path:
  string "fixture/inputs/D_prime.md";
  resolved against canonical_execution_cwd;

d_prime_expected_sha256:
  string
  "8553f52449b67de21021bb50ad6380c455bf686ee2a06cc77ed51e9f30060955";

d_prime_revision:
  integer 2.
```

The legacy nested locations

```text
dependencies[0].d_prime_seed_path
dependencies[0].d_prime_expected_sha256
dependencies[0].d_prime_revision
```

are deprecated by this authority and are forbidden in any post-alignment τN1
representation.

## 3. Consumed and preserved fields

Existing fields remain valid and preserved:

```text
task;
srs_identity;
request_id;
request_class;
boundary_id;
run_order;
tau_content_ref;
expected_decision;
expected_path;
expected_typed_failure.
```

For static τN1, `srs_identity` remains the placeholder
`RESOLVED_FROM_IS_INDEX_BY_ES1_OUTPUT`. For runtime τN1, driver substitution
replaces it with the actual ES1 SRS identity.

## 4. Validation order

Launch-time validation shall fail closed in this order:

```text
1. exact repository commit = 9966d311… or the later immutable post-alignment
   commit exact-bound by an approved Request;
2. command cwd == canonical_execution_cwd;
3. τN1 parses as JSON;
4. required top-level fields exist with exact types/values;
5. nested deprecated d_prime fields are absent;
6. d_prime_seed_path resolves beneath canonical_execution_cwd;
7. resolved D' file exists as a regular file;
8. resolved D' SHA256 equals d_prime_expected_sha256.
```

Any failure produces a typed schema/validation error and prevents campaign
progress.

## 5. Relationship to exact runner

The exact runner at `9966d31` consumes:

```text
tau["d_prime_seed_path"];
tau["dependencies"][0]["dependency_id"].
```

This authority deliberately adopts top-level D' fields and retains the
existing `dependencies[0].dependency_id` consumption. No runner change is
authorized or implied.

## 6. Record integrity

```text
record_integrity_binding = registered by the governing commit introducing this
schema authority on main; later modification creates a new content address and
voids this authority version.
```
