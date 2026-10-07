# SRS-REAL-CLOSURE-01 — Database-Carrier Equivalence Campaign Authorization Record 001

> **Status:** HUMAN APPROVED / CAMPAIGN EXECUTION PENDING
> **Date:** 2026-10-08
> **Campaign ID:** `exec-dbcarrier-001-8ec72ba`
> **Human ruling, exact form:** `APPROVE INSTRUMENTATION + ONE FROZEN
> CAMPAIGN`

## 1. Exact governing chain

```text
governing_request_commit =
  a2739de0d76c3dc361d1a43e9abd12bedec9f269;
governing_request_blob =
  git:blob:f3b6646cccb09c80097fc61c19677e917ee6777a;
governing_request_sha256 =
  d178a6722971e917ac67dd7f37e1209a8e2686795ac5c961ff394a33e50439f5;

part_c_instrumentation_commit =
  8ec72ba51c039e5420b9fb3f5cdc0f970dbd2e3c;
part_c_tree =
  c92fe76f253f91f90d10cadda7f87b5b5a2a5a47;
campaign_harness_blob =
  git:blob:714cba55a951ca14b4210a97d80dd88ebf6a6e27;
campaign_harness_sha256 =
  7874ff5a44b5036564b505f532afa14b2fa9dbd5f91e58e6016e81888dcd1222;
instrumentation_manifest_blob =
  git:blob:6dc60a341cdb8daeed3c1d437f166cd8f00449d4;
instrumentation_manifest_sha256 =
  42dac9f02a9b1c0422e3c870418b6f1478d5f5956b948ab71642e2541cc46ce3.
```

The exact execution repository commit for the sole campaign is Part C commit
`8ec72ba…`. The governance commit introducing this authorization record is not
an execution repository commit.

## 2. Authorized execution

```text
authorized_stage_set = {
  one non-semantic Part C instrumentation cycle;
  one frozen database equivalence campaign;
  one database IS mutation campaign;
  one observer-equivalent bounded campaign;
  exact evidence generation;
  STOP for Human evidence audit
};

campaign_budget = 1;
database_IS_mutation_campaign_budget = 1;
observer_equivalent_budget = 1;
automatic_renewal = forbidden.
```

The campaign must exact-bind the accepted Design Package, corrected
implementation, accepted fresh initialization evidence, exact EXEC-006
reference, EQ-1..EQ-8 and REJ-1..REJ-14.

## 3. Forbidden scope

```text
carrier/schema semantic change;
runner/observer/fixture/tau modification;
T-IMPL-01 modification;
document-form EXEC-006 rerun;
logical import;
prior campaign database reuse;
automatic equivalence establishment;
broader database/PALACE/production/LLM claim;
EXEC-006 broadening;
budget renewal.
```

## 4. Record integrity

```text
record_integrity_binding = registered by the governing commit introducing this
record on main; later modification creates a new content address and voids
this authorization.
```
