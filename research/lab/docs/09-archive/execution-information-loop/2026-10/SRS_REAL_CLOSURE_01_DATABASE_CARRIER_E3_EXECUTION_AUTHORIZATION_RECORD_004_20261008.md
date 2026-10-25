# SRS-REAL-CLOSURE-01 — Database-Carrier E3 Execution Authorization Record 004

> **ARCHIVED** 2026-10-20 · line: E-I 连续计算 · original: docs/00-governance/SRS_REAL_CLOSURE_01_DATABASE_CARRIER_E3_EXECUTION_AUTHORIZATION_RECORD_004_20261008.md
> Evidence status: unchanged (content frozen; moved only)


> **Status:** E3 EXECUTION AUTHORIZED — EXACTLY ONE FROZEN CAMPAIGN
> **Date:** 2026-10-08
> **Campaign ID:** `exec-dbcarrier-003-c6c8b6f`

## 1. Governing chain

```text
request_v1_5_commit = 079822841b3c1a482251fd24c9311e0242ae345;
request_v1_5_blob = git:blob:e712581b85b8b7187f2025c7337a27870db948f1;
request_v1_5_sha256 =
  b5bb276c5359167dc547253046e89d9bf15d59c66963f499b83f63dadcf2f211;

r2_conditional_e3_authorization_record_commit =
  9119530459d27b56c586c591dcf27a41f2a9b710;
r2_conditional_e3_authorization_record_blob =
  git:blob:56ea06ff430af3a741b63ef828bc170dff002767;
r2_conditional_e3_authorization_record_sha256 =
  7690ac33ea5e280ccd3332ac4b57dc399c7900facc85b867c5ed40909aff6049;

evidence_path_release_review_commit =
  712aee56c523845440276923ac7053dc3ea91b3c;
evidence_path_release_review_blob =
  git:blob:cd096081e3d612c3bdc264ec766d04f2c6c54472;
evidence_path_release_review_sha256 =
  4f719283d4ff80049c711d5a60db7fc78057147ba40dddcb4896dca57de21458;
release_ruling = RELEASED FOR E3.
```

The later governance commit introducing this execution authorization is not
the campaign execution repository state.

## 2. Exact execution state

```text
exact_execution_repository_commit =
  c6c8b6fb0b532aa94496ac860f4e5faaa8cd05e7;
exact_execution_tree =
  7b3ced36e169e7d529ce9da5c335082f145cf93e;
accepted_implementation_commit =
  7392fcb79fb7e8465b73f9e1837c4634e56c0409;
implementation_tree_unchanged = true;

authoritative_path_map_blob =
  git:blob:c89413a25879e7436f7db94e14c08ed9b28dc6fc;
authoritative_path_map_sha256 =
  b1adc52cdfb152f17d941d6214d24f393bdfc2fcdd9a7858bd37fe9c0b27ebb7;

accepted_fresh_database_blob =
  git:blob:34c26d6cbef034d1271757f242cab67f0cdbeaf5;
accepted_fresh_database_sha256 =
  6baa7afa8b5c623c75b3111af267e270d76d663547e730af5e7ca62b7602d14d;

campaign_harness_blob =
  git:blob:f3bcffc0c554ae75bb7a2e4dfed2c4dd062c7ad1;
evidence_path_loader_blob =
  git:blob:f08dd6377a34568192ac21ceae79dab99c435d67.
```

The sole campaign output root is fixed by the authoritative path map:

```text
docs/02-evidence/database-carrier-equivalence-campaign-v1.5-20261008
```

## 3. Budget

```text
third_database_equivalence_campaign_budget = 1;
third_database_IS_mutation_campaign_budget = 1;
third_observer_equivalent_budget = 1;
automatic_renewal = forbidden;
rerun_after_any_stop = forbidden.
```

This record instantiates and consumes the E3 authorization gate at execution
start. Any fail-closed stop, missing artifact, EQ/REJ failure, invalid
provenance, or crash consumes the campaign. No rerun is authorized.

## 4. Required execution

Exactly one execution must:

```text
use a clean detached worktree at c6c8b6f…;
pass --expected-head c6c8b6f…;
use the exact authoritative output root inside that worktree;
consume the path map by exact destination identity;
copy and verify the accepted fresh database as O0 and working DB;
execute frozen O0..O5;
invoke exact T-IMPL-01 for ES2/ESN;
evaluate EQ-1..EQ-8 and REJ-1..REJ-14;
capture observer C1..C4;
write all 29 authoritative destinations;
stop for Human evidence audit.
```

## 5. Forbidden

```text
EXEC-DB-001 / EXEC-DB-002 rerun or state reuse;
old working database or evidence reuse;
implementation/schema/semantic change;
runner/observer/fixture/tau/T-IMPL-01 change;
document-form EXEC-006 rerun;
logical import;
automatic equivalence establishment;
PALACE/production/LLM/general-database broadening;
renewal.
```
