# SRS-REAL-CLOSURE-01 — Database-Carrier Equivalence Campaign Invalid Completion Record 001

> **Status:** CAMPAIGN INVALID / STOP FOR HUMAN DECISION
> **Date:** 2026-10-08
> **Campaign ID:** `exec-dbcarrier-001-8ec72ba`

## 1. Outcome

The sole campaign authorized by Authorization Record 001 was attempted from
clean detached Part C commit `8ec72ba51c039e5420b9fb3f5cdc0f970dbd2e3c`.
It stopped fail-closed at database schema preflight before any O1..O5 logical
mutation:

```text
outcome = INVALID;
stop_code = CAMPAIGN_PREFLIGHT_SCHEMA_EMPTY;
stop_point = PRE_MUTATION_SCHEMA_PREFLIGHT;
root_cause_class = HARNESS_WORKING_DATABASE_COPY_BINDING_DEFECT;
measured_working_schema = [];
logical_rows_written = 0;
adapter_invocations_attempted = 0;
observer_executed = false.
```

The defect is in the Part C harness working-copy binding: it copied the
accepted fresh database to `O0_DATABASE.sqlite` but not to
`CAMPAIGN_DATABASE.sqlite` before opening it. The accepted implementation,
accepted fresh database, exact T-IMPL-01 runtime, and reference inputs are not
classified as defective.

## 2. Canonical evidence

```text
docs/02-evidence/database-carrier-equivalence-campaign-v1.3-20261008

outcome_sha256 =
  f6f2cd941a7fd912c119c7310b77160581d5d3b81488f7faaef447c7bdfebb21;
process_result_sha256 =
  912a6430f9d10b4d0e233f8c8b59dcdc2477cbcfba939ce59b912b6240d4e394;
stderr_sha256 =
  f4015323e5398f678b5c67234dab3062c1507d8e1b57468e77d7cf1f7ae2eb7d;
working_database_sha256 =
  e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855;
source_database_sha256 =
  6baa7afa8b5c623c75b3111af267e270d76d663547e730af5e7ca62b7602d14d;
adapter_runtime_sha256 =
  e88c996b9a64df10dd03f7622ffa8757551baf352908e4d7bf8704295eaffcc7.
```

## 3. Research state

```text
semantic sequence       NOT RUN
E1-E6                   ABSENT
N1 BLOCK                ABSENT
positive REUSE          ABSENT
EQ/REJ adjudication     NOT EVALUATED
CarrierSQLite equivalence NOT ESTABLISHED
core broader claim      NOT ESTABLISHED

instrumentation budget  CONSUMED
campaign budget         CONSUMED BY FAIL-CLOSED ATTEMPT
automatic renewal       FORBIDDEN
harness repair          NOT AUTHORIZED
rerun                   NOT AUTHORIZED

next lawful object      Human decision on corrected campaign authorization
```
