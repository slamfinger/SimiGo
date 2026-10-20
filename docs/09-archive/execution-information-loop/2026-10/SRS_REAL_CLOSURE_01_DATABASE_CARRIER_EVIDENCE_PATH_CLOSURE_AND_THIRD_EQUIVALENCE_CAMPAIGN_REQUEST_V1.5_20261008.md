# SRS-REAL-CLOSURE-01 — Database-Carrier Evidence-Path Closure & Third Equivalence Campaign Request v1.5

> **ARCHIVED** 2026-10-20 · line: E-I 连续计算 · original: docs/00-governance/SRS_REAL_CLOSURE_01_DATABASE_CARRIER_EVIDENCE_PATH_CLOSURE_AND_THIRD_EQUIVALENCE_CAMPAIGN_REQUEST_V1.5_20261008.md
> Evidence status: unchanged (content frozen; moved only)


> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE
> AUTHORIZED
> **Date:** 2026-10-08
> **Predecessor canonical stop:** `f8960bd662e60f5860fdb9e7341f8cab0bcc9ad1`

## 1. Purpose

Close the entire campaign evidence path before another semantic-sequence
attempt, then execute one independently budgeted third frozen equivalence
campaign. This Request replaces the failed pattern of repairing one known
defect and immediately running another campaign.

## 2. Exact inherited bindings

```text
accepted_design_package_commit =
  21acba4e07f312fcb818968f33fd9e0c185fccf0;
accepted_design_package_sha256 =
  73f80c26cd3bb6636b82edf29c71b57b9fc5fb028294d13edf519abb768c2cc4;

corrected_implementation_commit =
  7392fcb79fb7e8465b73f9e1837c4634e56c0409;
accepted_fresh_initialization_completion_commit =
  32ef3b06a4af808917cf7f4e248e9539c684b35f;
accepted_fresh_initialization_review_commit =
  2f07b05f29da2bfc1fbf6dc4012754e69b96ec3f;
accepted_fresh_database_sha256 =
  6baa7afa8b5c623c75b3111af267e270d76d663547e730af5e7ca62b7602d14d;

document_reference_execution_state =
  69b2227dbd9ec7bfc8ad744d65efe46e3a9ab33a;
document_reference_evidence_commit =
  cb365a44c48d4b7b90b4cc2155fcae00d3e01572.
```

## 3. Failed campaign disposition

### EXEC-DB-001

```text
part_c_commit = 8ec72ba51c039e5420b9fb3f5cdc0f970dbd2e3c;
authorization_commit = 771fb57091079f62c3e95d7419ae9ee41479d455;
evidence_commit = bc7aaa0793d7f3e6b6ff0a76c9137ef3bcb9645b;
campaign_id = exec-dbcarrier-001-8ec72ba;
harness_sha256 =
  7874ff5a44b5036564b505f532afa14b2fa9dbd5f91e58e6016e81888dcd1222;
outcome = INVALID;
stop_code = CAMPAIGN_PREFLIGHT_SCHEMA_EMPTY;
root_cause = HARNESS_WORKING_DATABASE_COPY_BINDING_DEFECT;
campaign_outcome_sha256 =
  f6f2cd941a7fd912c119c7310b77160581d5d3b81488f7faaef447c7bdfebb21;
campaign_process_result_sha256 =
  912a6430f9d10b4d0e233f8c8b59dcdc2477cbcfba939ce59b912b6240d4e394.
```

### EXEC-DB-002

```text
request_v1_4_commit = 0fe3321f6230fbccd0c94a71ce92f579492c7758;
part_r_commit = a951e4e6ecb6a8b44cc355bc2405b15da7e31e97;
authorization_commit = 4243961baf29d822985bb1ecf61a5850e60a6ff8;
evidence_commit = f8960bd662e60f5860fdb9e7341f8cab0bcc9ad1;
campaign_id = exec-dbcarrier-002-a951e4e;
harness_sha256 =
  f09d8fd9ce896449595ba4104c1c1321bd2403e45d8363734c5bb6b2c245fec6;
outcome = INVALID;
stop_code = CAMPAIGN_OBSERVATION_ARTIFACT_DIRECTORY_MISSING;
root_cause = HARNESS_OBSERVATION_OUTPUT_DIRECTORY_BINDING_DEFECT;
campaign_outcome_sha256 =
  2c93c9c16a14f831017885b99ea79799434fe047f163c9f318152d9d82ef7ec9;
campaign_process_result_sha256 =
  39e513409a214dd7577a3471e7a9b578a8a25d6646d1c70764bdc716e038c062.
```

Both attempts are non-reusable failure evidence only. Their budgets are
consumed. Neither old working database, old evidence package, nor old harness
may be reused as campaign state. Neither attempt establishes or weakens any
EQ/REJ result, EXEC-006 finding, accepted implementation, or fresh
initialization baseline.

## 4. Part R2 — evidence-path closure only

One work cycle may modify only campaign evidence-path instrumentation. It must
create a complete preflight contract for every required campaign artifact
destination before semantic-sequence mutation.

Required destination classes:

```text
O0..O5 observation JSON paths;
O0 and O5 database snapshot paths;
working CAMPAIGN_DATABASE.sqlite;
transaction log;
adapter build directory, source manifests and build command record;
ES2/ESN adapter input and output paths;
runtime/provenance/preflight manifests;
observer verdict;
EQ/REJ adjudication matrix;
campaign outcome/process result/stderr records;
SHA256SUMS.
```

For every destination, preflight must record:

```text
expected absolute repository-relative path;
parent directory exists;
parent directory is writable;
destination is not a directory;
destination is not a symlink;
fresh-campaign destination is absent before execution;
exclusive write probe succeeds;
probe file is removed;
final fail-closed result.
```

Part R2 must emit an `EVIDENCE_PATH_BINDING_MANIFEST` binding:

```text
accepted source database
  → verified O0 database copy
  → verified working database
  → all O0..O5 artifact roots and filenames
  → all adapter/process/observer/outcome destinations
  → final SHA256SUMS;
```

with exact path, type, symlink status, existence status, writable status,
probe result, cleanup result, and overall PASS/FAIL for each destination.

Part R2 must not execute O1..O5, invoke T-IMPL-01, mutate logical IS rows,
change schema, change ES semantics, change decision boundary, change τ,
fixture, runner, observer, T-IMPL-01, or EQ/REJ criteria.

Part R2 ends at canonical completion and STOP for Human evidence-path review.

## 5. Part E3 — conditional third frozen campaign

Only after Human evidence-path release review accepts Part R2 may a new
authorization record instantiate one campaign exact-binding:

```text
Request v1.5;
Part R2 corrected commit;
complete evidence-path binding manifest;
accepted design/implementation/fresh database bindings;
EXEC-006 document reference;
EQ-1..EQ-8;
REJ-1..REJ-14.
```

Then execute exactly one frozen campaign from clean detached Part R2 commit,
capture O0..O5, invoke exact T-IMPL-01 for ES2/ESN, evaluate EQ/REJ, produce
the complete evidence package, and STOP for Human evidence audit.

## 6. Independent budgets

```text
evidence_path_harness_correction_work_cycle_budget = 1;
third_database_equivalence_campaign_budget = 1;
third_database_IS_mutation_campaign_budget = 1;
third_observer_equivalent_budget = 1;

document_reference_rerun_budget = 0;
implementation_repair_budget = 0;
schema_migration_budget = 0;
logical_import_budget = 0;
fixture/runner/tau_repair_budget = 0;
T_IMPL_repair_budget = 0;
old_budget_reuse = forbidden;
automatic_renewal = forbidden.
```

## 7. Required evidence

Part R2 must deliver:

```text
evidence path binding manifest;
destination probe results;
fail-closed behavior record;
source/working database copy contract;
implementation-unchanged proof;
no-semantic-mutation proof;
explicit stop code;
SHA256SUMS.
```

Part E3, if released, must deliver the complete campaign evidence package,
including exact provenance, O0..O5 observations, adapter decisions, U-ledger
counts, observer C1..C4, EQ/REJ matrix, required artifact hashes and explicit
outcome. Even a mechanically valid campaign is only
`CANDIDATE_EQUIVALENCE_PENDING_HUMAN_AUDIT`.

## 8. Forbidden scope

```text
old campaign/working database/evidence reuse;
carrier/schema semantic change;
runner/observer/fixture/tau modification;
T-IMPL-01 modification;
document-form EXEC-006 rerun;
logical import;
automatic equivalence establishment;
PALACE/production/LLM/general-database broadening;
budget renewal.
```

## 9. Required Human decision

```text
APPROVE R2 ONLY
APPROVE R2+E3
REVISE REQUEST
DENY REQUEST
```

Opening this Request authorizes no stage. `APPROVE R2+E3` authorizes only the
conditional path stated above; Part E3 still requires a successful canonical
Part R2 and explicit Human evidence-path release review.
