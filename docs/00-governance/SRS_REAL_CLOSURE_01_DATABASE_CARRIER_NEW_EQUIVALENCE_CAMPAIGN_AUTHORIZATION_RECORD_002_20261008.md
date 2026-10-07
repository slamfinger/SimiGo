# SRS-REAL-CLOSURE-01 — Database-Carrier New Equivalence Campaign Authorization Record 002

> **Status:** HUMAN AUTHORIZED / CAMPAIGN EXECUTION PENDING
> **Date:** 2026-10-08
> **Campaign ID:** `exec-dbcarrier-002-a951e4e`
> **Governing Request:** Harness Correction & New Equivalence Campaign
> Request v1.4 @ `0fe3321f6230fbccd0c94a71ce92f579492c7758`

## 1. Exact Part R bindings

```text
part_r_corrected_execution_commit =
  a951e4e6ecb6a8b44cc355bc2405b15da7e31e97;
part_r_tree =
  e85e252339c75da2e4759bb897fb3fdfa570adf1;
corrected_campaign_harness_blob =
  git:blob:249388c60b9438697b3f379f03a35b1927ae4d3c;
corrected_campaign_harness_sha256 =
  f09d8fd9ce896449595ba4104c1c1321bd2403e45d8363734c5bb6b2c245fec6;
correction_manifest_blob =
  git:blob:c4a2241cbf8dfd908629cea7e7a39426a0a93e3e;
correction_manifest_sha256 =
  dc76268b7dd1ed2aef432fc79a03f92de052047812733408ac5a13336614cfa8;

corrected_defect =
  HARNESS_WORKING_DATABASE_COPY_BINDING_DEFECT;
implementation_tree_vs_7392fcb = UNCHANGED.
```

The sole new campaign execution repository commit is Part R commit
`a951e4e…`. The later governance commit introducing this record is not the
execution repository commit.

## 2. Authorized execution

```text
new_campaign_budget = 1;
new_database_IS_mutation_campaign_budget = 1;
new_observer_equivalent_budget = 1;
automatic_renewal = forbidden.
```

Execute one frozen campaign from clean detached `a951e4e…`; evaluate
EQ-1..EQ-8 and REJ-1..REJ-14; produce complete provenance, O0..O5
observations, exact T-IMPL-01 decisions, observer-equivalent C1..C4 evidence
and SHA256SUMS; then STOP for Human evidence audit.

## 3. Forbidden scope

```text
old campaign/working database/evidence reuse;
carrier/schema semantic change;
runner/observer/fixture/tau modification;
T-IMPL-01 modification;
document-form EXEC-006 rerun;
logical import;
automatic equivalence establishment;
broader database/PALACE/production/LLM claim;
budget renewal.
```

## 4. Record integrity

```text
record_integrity_binding = registered by the governing commit introducing this
record on main; later modification creates a new content address and voids
this authorization.
```
