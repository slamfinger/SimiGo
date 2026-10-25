# SRS-REAL-CLOSURE-01 — Database-Carrier Harness Correction & New Equivalence Campaign Request v1.4

> **ARCHIVED** 2026-10-20 · line: E-I 连续计算 · original: docs/00-governance/SRS_REAL_CLOSURE_01_DATABASE_CARRIER_HARNESS_CORRECTION_AND_NEW_EQUIVALENCE_CAMPAIGN_REQUEST_V1.4_20261008.md
> Evidence status: unchanged (content frozen; moved only)


> **Status:** OPENED BY HUMAN AUTHORIZATION — PART R + ONE NEW PART E
> **Date:** 2026-10-08
> **Human authorization, exact form:** `授权一个新的、独立预算的 harness correction + one new frozen equivalence campaign.`
> **Predecessor canonical stop:** `bc7aaa0793d7f3e6b6ff0a76c9137ef3bcb9645b`

## 1. Purpose

Close only the registered Part C working-copy binding defect, then execute one
new independent frozen Database-Carrier equivalence campaign. The prior INVALID
attempt is not a semantic negative result and is not rerun or reused.

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

part_c_instrumentation_commit =
  8ec72ba51c039e5420b9fb3f5cdc0f970dbd2e3c;
failed_campaign_authorization_commit =
  771fb57091079f62c3e95d7419ae9ee41479d455;
failed_campaign_evidence_commit =
  bc7aaa0793d7f3e6b6ff0a76c9137ef3bcb9645b;

failed_campaign_id = exec-dbcarrier-001-8ec72ba;
failed_campaign_outcome = INVALID;
failed_campaign_stop_code = CAMPAIGN_PREFLIGHT_SCHEMA_EMPTY;
failed_campaign_root_cause =
  HARNESS_WORKING_DATABASE_COPY_BINDING_DEFECT;

document_reference_execution_state =
  69b2227dbd9ec7bfc8ad744d65efe46e3a9ab33a;
document_reference_evidence_commit =
  cb365a44c48d4b7b90b4cc2155fcae00d3e01572.
```

## 3. Old campaign disposition

```text
old campaign budget            CONSUMED;
old attempt                    INVALID / FAILURE EVIDENCE ONLY;
old Part C harness             NON-REUSABLE FOR EXECUTION;
old working zero-byte DB       NON-REUSABLE;
old EQ/REJ conclusions         NOT ESTABLISHED;
old semantic failure claim     NOT ESTABLISHED;
old evidence reuse             FORBIDDEN;
old working database reuse     FORBIDDEN.
```

The failed attempt neither invalidates EXEC-006 nor weakens the accepted
design, implementation, or fresh-initialization baselines.

## 4. Part R — exact correction scope

One work cycle may add only campaign-harness correction/provenance files and
may alter only the campaign harness working-copy binding:

```text
accepted fresh source database
    → byte-exact verified O0_DATABASE.sqlite
    → byte-exact verified CAMPAIGN_DATABASE.sqlite
    → only then DatabaseBackedIS open
    → fail-closed schema/table/zero-row preflight.
```

Required correction properties:

```text
working database must be materialized by explicit byte copy;
working copy SHA256 must equal accepted source SHA256 before open;
open must be fail-closed if any binding check fails;
implementation, schema, DB semantics, ES semantics, τ, fixture, runner,
observer, T-IMPL-01 and EQ/REJ criteria remain unchanged.
```

## 5. Part E — one new frozen campaign

After the Part R corrected commit is canonical, execute exactly one new
campaign from clean detached Part R commit:

```text
verify exact repository and unchanged implementation tree;
verify accepted source database byte identity;
materialize a new working database only by verified byte copy;
run frozen O0→O5 sequence;
invoke exact T-IMPL-01 for ES2/ESN;
evaluate EQ-1..EQ-8 and REJ-1..REJ-14;
produce complete provenance, observations, decision outputs, observer C1..C4
  evidence, campaign outcome and SHA256SUMS;
STOP for Human evidence audit.
```

The new campaign may reuse only accepted immutable reference/input bindings.
It must not reuse the failed working database as campaign state.

## 6. New independent budgets

```text
harness_correction_work_cycle_budget = 1;
new_database_equivalence_campaign_budget = 1;
new_database_IS_mutation_campaign_budget = 1;
new_observer_equivalent_budget = 1;

document_reference_rerun_budget = 0;
implementation_repair_budget = 0;
schema_migration_budget = 0;
logical_import_budget = 0;
fixture/runner/tau_repair_budget = 0;
T_IMPL_repair_budget = 0;
automatic_renewal = forbidden.
```

## 7. Required evidence and stop

The new campaign must emit:

```text
preflight manifests;
source/O0/working-copy SHA256 bindings;
engine/runtime/provenance records;
transaction operation classes and boundaries;
O0..O5 observation manifests;
ES2/ESN invocation and decision records;
U-ledger counts;
C1..C4 observer-equivalent verdict;
EQ and REJ adjudication matrix;
required artifact existence/size/hash checks;
explicit outcome and stop code;
SHA256SUMS.
```

Even a mechanically valid campaign may only produce
`CANDIDATE_EQUIVALENCE_PENDING_HUMAN_AUDIT`; equivalence itself requires a
separate Human evidence audit.

## 8. Forbidden scope

```text
old campaign/working database/old evidence reuse;
carrier or schema semantic change;
runner/observer/fixture/τ change;
T-IMPL-01 change;
document-form EXEC-006 rerun;
logical import;
budget renewal;
automatic equivalence establishment;
PALACE/production/LLM/general-database broadening;
broader claim.
```
