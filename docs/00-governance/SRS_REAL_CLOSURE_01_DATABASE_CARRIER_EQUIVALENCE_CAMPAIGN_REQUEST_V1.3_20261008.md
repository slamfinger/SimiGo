# SRS-REAL-CLOSURE-01 — Database-Carrier Equivalence Campaign Request v1.3

> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE
> AUTHORIZED
> **Date:** 2026-10-08
> **Requested stage set:** non-semantic campaign instrumentation + one frozen
> CarrierSQLite equivalence campaign + exact evidence + STOP.
> **Predecessor canonical stop:** `2f07b05f29da2bfc1fbf6dc4012754e69b96ec3f`

## 1. Purpose

Test one controlled carrier substitution against the accepted EXEC-006
document-form reference:

```text
document-form IS reference
        ↓
database-backed IS campaign copy
        ↓
same frozen logical sequence
        ↓
EQ-1..EQ-8 observation and REJ-1..REJ-14 rejection
```

This Request does not claim or presume CarrierSQLite equivalence. The only
admissible outcome is a canonical evidence package for later Human evidence
audit.

## 2. Exact accepted bindings

```text
accepted_design_package_commit =
  21acba4e07f312fcb818968f33fd9e0c185fccf0;
accepted_design_package_blob =
  git:blob:582c9b85c9ea1ec215a152d18d2ac0b6e0be1b25;
accepted_design_package_sha256 =
  73f80c26cd3bb6636b82edf29c71b57b9fc5fb028294d13edf519abb768c2cc4;

corrected_implementation_commit =
  7392fcb79fb7e8465b73f9e1837c4634e56c0409;
authoritative_implementation_artifact_sha256 = {
  README.md =
    24c112ae792b9f97ab76afa7eee22e8007480741cd73e375e4d4105f1b6d3ec0;
  db_is.py =
    dba16601069aa56acdea1bd365bdca73f4805c40b1c343a0edb5c3adb1bf4bbe;
  schema.sql =
    06ff8f976f436860d004b02ae032246e97021bed7280834c9a8bd904cf3d649a;
  selfcheck.py =
    d57f3667ed5b8aa5e340c88880d9b0617383551f32e7c37698db786c8d147bd5
};

fresh_initialization_governing_request =
  4588696313a65749f1eda6f8fdb1fd1d311ac1a5;
fresh_initialization_completion_commit =
  32ef3b06a4af808917cf7f4e248e9539c684b35f;
fresh_initialization_review_commit =
  2f07b05f29da2bfc1fbf6dc4012754e69b96ec3f;
fresh_initialization_database_sha256 =
  6baa7afa8b5c623c75b3111af267e270d76d663547e730af5e7ca62b7602d14d;
fresh_initialization_schema_sha256 =
  06ff8f976f436860d004b02ae032246e97021bed7280834c9a8bd904cf3d649a;

document_reference_execution_state =
  69b2227dbd9ec7bfc8ad744d65efe46e3a9ab33a;
document_reference_evidence_commit =
  cb365a44c48d4b7b90b4cc2155fcae00d3e01572;
accepted_bounded_finding_stop =
  feb0a61f2ed87079c2a9e3572d0e1a3c9f9f0;
canonical_adapter_runtime_sha256 =
  e88c996b9a64df10dd03f7622ffa8757551baf352908e4d7bf8704295eaffcc7.
```

### Manifest status disclosure

`database-carrier-replication/implementation/IMPLEMENTATION_MANIFEST.json`
inside `7392fcb…` contains stale pre-correction artifact hashes for README,
`db_is.py` and `selfcheck.py`. It is therefore classified as a historical
non-authoritative manifest for this campaign. No implementation repair is
requested. The campaign exact-binds the corrected implementation commit plus
the actual artifact hashes recorded by the accepted fresh initialization
manifest above. Campaign evidence must not cite the stale artifact map as an
authority.

## 3. Frozen document-form reference

The reference logical endpoint is taken only from accepted EXEC-006 evidence:

```text
objects = {
  806fffadef09d3ad491d75c6b42738e99626ee1961ed1aecf2d593aefd55980c,
  26025863df8311f536b067718e8c8466fb9dafa7924c629429e6766f2926c3f9,
  1703f2d664c58d4fe88032b7b3750ab885522c1a5a73e04570be108f7c6bf026,
  8553f52449b67de21021bb50ad6380c455bf686ee2a06cc77ed51e9f30060955
};

index append order = {
  SRS identity
    5e01d6ce03526c6ba6bf988a9caf6505af169c3155fe7bf4716ea717f893de8f
    -> object 26025863…,
  CR:CR-ES2-r2 -> object 1703f2d6…
};

dependency append order = {
  D-1 revision 1 -> object 806fffa… reason "initial materialization",
  D-1 revision 2 -> object 8553f524… reason
    "N1 negative-control state advance"
};

decisions = { ES2 = REUSE, ESN = BLOCK };
ledger counts = { ES1_U = 1, ES2_U = 0, ESN_U = 0 }.
```

Each input object byte stream must be verified as SHA256 == object_id before
use. Exact reference object/index/dependency extraction is from evidence
commit `cb365a4…`; no reinterpretation of EXEC-006 is authorized.

## 4. Authorized campaign structure

### Part C — non-semantic instrumentation

One work cycle may add campaign-only files under
`database-carrier-replication/campaign/`. The instrumentation may:

```text
verify clean exact implementation and fresh-database bindings;
copy the accepted fresh database to a new campaign working file;
verify the copy SHA256 before first mutation;
extract and verify exact EXEC-006 reference inputs;
execute one frozen sequence through the accepted DB API:
  O0 empty;
  O1 materialize D + dependency revision 1;
  O2 ES1 SRS object + index append;
  O3 ES2 REUSE + continuation object/index append;
  O4 mutate-n1 D' + dependency revision 2;
  O5 ESN resolves revision 2 and returns BLOCK;
invoke exact canonical T-IMPL-01 for ES2/ESN decisions;
record observations at every O0..O5 point;
record transaction boundaries and read results;
perform observer-equivalent C1..C4 checks;
emit campaign outcome, EQ/REJ matrix, observation manifests and SHA256SUMS.
```

The instrumentation must not alter `db_is.py`, `schema.sql`, `selfcheck.py`,
runner, observer, fixture, τ, T-IMPL-01, or any frozen EXEC-006 artifact.

### Part E — one frozen campaign

After Part C is canonical, create a new campaign record set exact-binding the
post-instrumentation immutable commit, all §2 bindings and the frozen §3
reference. Then execute exactly one campaign and STOP for Human evidence
audit.

## 5. Required equivalence adjudication

At every observation point, evaluate:

```text
EQ-1 object set, bytes and hashes;
EQ-2 object immutability;
EQ-3 index records and append order;
EQ-4 dependency history and append order;
EQ-5 LAST-entry current resolution;
EQ-6 declared read results;
EQ-7 ES2 = REUSE and ESN = BLOCK;
EQ-8 no extra observable semantic state.
```

Any REJ-1..REJ-14 condition, schema mismatch, provenance mismatch, missing
artifact, adapter mismatch, observer C1..C4 mismatch, or unexpected database
semantic state maps to the Design Package failure taxonomy and campaign
INVALID/STOP. A matching final decision alone is insufficient.

## 6. Required evidence

The campaign evidence package must contain:

```text
exact preflight manifest;
fresh-database source hash and campaign-copy hash;
engine/platform/runtime provenance;
exact executable, argv, cwd, UTC/monotonic timing and returncode;
transaction boundary records;
O0..O5 object/index/dependency observation manifests;
ES2/ESN invocation and decision records;
U-ledger counts;
C1..C4 observer-equivalent verdict;
EQ and REJ adjudication matrix;
all required artifact existence/size/SHA256 checks;
explicit outcome and stop code;
SHA256SUMS.
```

## 7. Budgets

```text
campaign_instrumentation_work_cycle_budget = 1;
database_equivalence_campaign_budget = 1;
database_IS_mutation_campaign_budget = 1;
observer_equivalent_budget = 1;

implementation_repair_budget = 0;
schema_migration_budget = 0;
logical_import_budget = 0;
runner_repair_budget = 0;
fixture_repair_budget = 0;
tau_repair_budget = 0;
document_reference_rerun_budget = 0;
automatic_renewal = forbidden.
```

## 8. Forbidden scope

```text
carrier implementation modification;
schema modification or migration;
runner/observer/fixture/τ modification;
T-IMPL-01 modification;
document-form EXEC-006 rerun;
logical import;
reuse of any prior campaign database;
equivalence claim before Human evidence audit;
broader database/PALACE/production/LLM claim;
broadening EXEC-006;
automatic follow-on.
```

## 9. Required Human decision

```text
APPROVE INSTRUMENTATION + ONE FROZEN CAMPAIGN
APPROVE INSTRUMENTATION ONLY
REVISE REQUEST
DENY REQUEST
```

Opening this Request authorizes no stage. Until an explicit approval and a
new canonical record set exist:

```text
campaign instrumentation = NOT AUTHORIZED;
campaign execution       = NOT AUTHORIZED;
IS mutation              = NOT AUTHORIZED;
observer execution       = NOT AUTHORIZED.
```
