# PALACE — MINIMAL-PIR-EXP-001 Execution Authorization Record 029

> **Status:** APPROVE MINIMAL-PIR-EXP-001 — ONE FRESH FROZEN EXECUTION
> **Date:** 2026-10-08
> **Human ruling, exact form:** `APPROVE MINIMAL-PIR-EXP-001，一次、全新、冻结执行。`
> **Governing Request v2.4:** `f6a0e5e17e8d5ce0a130f8a58de0dd824384a2f2`
> **Execution recorder commit:** `9c691eaa4152602a173c975e444fdf152ac7c7d1`
> **Frozen Minimal PIR Probe v0.2 SHA256:** `94667081704f8e27bcd3bbb5cdd1685ee004adf8cf762fa27e24bb3edff23bd1`
> **Accepted RM-001 SHA256:** `4df7ba8f764fc44ef5a087c83e7075a60fe4fd5cafc7fd4c9d77f0c18d71bfc0`

## 1. Authorization

Exactly one execution of `MINIMAL-PIR-EXP-001` is authorized over the four
prepaid fixture sets:

```text
E-L           N=10,000, R=20, M=5;
E-S           N=20, R=20, M=5;
C-NOCHANGE-L  N=10,000, R=20, M=0;
C-NOCHANGE-S  N=20, R=20, M=0.

W_obs_age = 60,000 ms;
W_latency = 5,000 ms.
```

Authorized budgets:

```text
physical observation budget = 1 frozen set execution;
experiment evidence budget  = 1 frozen set execution;
IS mutation budget          = 0;
repair budget               = 0;
rerun budget                = 0;
renewal                     = FORBIDDEN.
```

## 2. Forbidden during execution

```text
Probe v0.2 change;
RM-001 run shape / W_obs_age / W_latency / attribution change;
fixture change during run;
IS mutation;
semantic inference;
whole-space scan;
model similarity or best guess;
Database-Carrier campaign work;
E9;
automatic repair;
automatic rerun;
automatic budget renewal;
PIR equivalence claim.
```

## 3. Stop discipline

Any implementation, harness, evidence, threshold, scope, attribution or
serialization defect is fail-closed and makes the run INVALID /
NON-ADJUDICATIVE. No field repair, rerun, cross-run stitching or forced result
is authorized. Completion produces bounded physical-reconciliation evidence
only and requires separate Human evidence audit.

## 4. Exact execution binding

```text
execution commit = the canonical commit introducing this authorization record;
fixture source = accepted prepared fixtures at this commit;
output root = docs/02-evidence/es-is-20261005/PIR_RM001_EXPERIMENT;
expected fixtures = E-L, E-S, C-NOCHANGE-L, C-NOCHANGE-S.
```
