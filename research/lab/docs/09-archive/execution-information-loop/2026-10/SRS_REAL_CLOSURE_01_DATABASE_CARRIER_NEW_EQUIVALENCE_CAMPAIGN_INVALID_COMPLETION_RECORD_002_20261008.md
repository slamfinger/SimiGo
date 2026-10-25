# SRS-REAL-CLOSURE-01 — Database-Carrier New Equivalence Campaign Invalid Completion Record 002

> **ARCHIVED** 2026-10-20 · line: E-I 连续计算 · original: docs/00-governance/SRS_REAL_CLOSURE_01_DATABASE_CARRIER_NEW_EQUIVALENCE_CAMPAIGN_INVALID_COMPLETION_RECORD_002_20261008.md
> Evidence status: unchanged (content frozen; moved only)


> **Status:** CAMPAIGN INVALID / STOP FOR HUMAN DECISION
> **Date:** 2026-10-08
> **Campaign ID:** `exec-dbcarrier-002-a951e4e`

## 1. Outcome

The sole new campaign authorized by New Equivalence Campaign Authorization
Record 002 was attempted from clean detached Part R commit
`a951e4e6ecb6a8b44cc355bc2405b15da7e31e97`. The Request v1.4 working-copy
correction passed. The attempt then stopped fail-closed when writing the first
observation artifact:

```text
outcome = INVALID;
stop_code = CAMPAIGN_OBSERVATION_ARTIFACT_DIRECTORY_MISSING;
stop_point = O0_EVIDENCE_PERSISTENCE_PRE_MUTATION;
root_cause_class = HARNESS_OBSERVATION_OUTPUT_DIRECTORY_BINDING_DEFECT;
working_copy_binding = PASS;
schema_preflight = PASS;
logical_rows_written = 0;
adapter_invocations_attempted = 0;
observer_executed = false.
```

This is a second, independent harness evidence-path defect. It does not alter
the accepted carrier, implementation, fresh initialization, EXEC-006 finding,
or EQ/REJ criteria.

## 2. Canonical evidence

```text
docs/02-evidence/database-carrier-equivalence-campaign-v1.4-20261008

working_copy_binding_json = PASS;
O0 database SHA256 =
  6baa7afa8b5c623c75b3111af267e270d76d663547e730af5e7ca62b7602d14d;
working database SHA256 =
  6baa7afa8b5c623c75b3111af267e270d76d663547e730af5e7ca62b7602d14d;
adapter runtime SHA256 =
  e88c996b9a64df10dd03f7622ffa8757551baf352908e4d7bf8704295eaffcc7.
```

The complete artifact set is bound by its canonical `SHA256SUMS`.

## 3. Research state

```text
semantic sequence       NOT RUN
E1-E6                   ABSENT
N1 BLOCK                ABSENT
positive REUSE          ABSENT
EQ/REJ adjudication     NOT EVALUATED
CarrierSQLite equivalence NOT ESTABLISHED
core broader claim      NOT ESTABLISHED

Request v1.4 Part R     CORRECTION DELIVERED
new campaign budget     CONSUMED BY FAIL-CLOSED ATTEMPT
automatic renewal       FORBIDDEN
harness repair          NOT AUTHORIZED
rerun                   NOT AUTHORIZED

next lawful object      Human decision on a further corrected campaign
```
