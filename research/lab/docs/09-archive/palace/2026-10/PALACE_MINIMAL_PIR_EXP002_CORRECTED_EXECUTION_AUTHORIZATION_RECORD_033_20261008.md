# PALACE — MINIMAL-PIR-EXP-002 Corrected Execution Authorization Record 033

> **ARCHIVED** 2026-10-20 · line: PALACE / Integrated ES · original: docs/00-governance/PALACE_MINIMAL_PIR_EXP002_CORRECTED_EXECUTION_AUTHORIZATION_RECORD_033_20261008.md
> Evidence status: unchanged (content frozen; moved only)


> **Status:** APPROVE — ONE NEW INDEPENDENT CORRECTED PIR EXECUTION
> **Date:** 2026-10-08
> **Human ruling, exact form:** `APPROVE 一次全新的 corrected PIR experiment。`
> **Predecessor canonical main:** `80fbda6a9b63d7a998ec1a463e4aee2e9bee664b`
> **Recorder correction commit:** `a11f637`
> **Execution identity support commit:** `2b866a6386d34160d81ee4eb58b35bfd68422cc9`
> **MINIMAL-PIR-EXP-001:** INVALID / CLOSED / NO RERUN

## 1. Authorization

One new, independent, frozen corrected PIR execution is authorized as:

```text
experiment_id = MINIMAL-PIR-EXP-002;
basis = accepted RM-001 + corrected EV-P08 recorder;
budgets = new independent experiment / physical-observation / evidence budgets;
fixture reuse = approved precharged fixture inputs only, unchanged;
E-001 evidence reuse = forbidden except read-only audit references;
output root = fresh corrected-run directory.
```

## 2. Frozen execution boundary

```text
E-L           N=10,000, R=20, M=5;
E-S           N=20, R=20, M=5;
C-NOCHANGE-L  N=10,000, R=20, M=0;
C-NOCHANGE-S  N=20, R=20, M=0;
W_obs_age     = 60,000 ms;
W_latency     = 5,000 ms;
phase-separated attribution = REQUIRED;
oracle isolation = REQUIRED;
Fresh Closure = REQUIRED;
EV-P01..EV-P18 = REQUIRED;
fail-closed = REQUIRED.
```

## 3. Prohibited during execution

```text
Probe v0.2 change;
RM-001 shape/window/attribution change;
fixture mutation;
IS mutation;
semantic inference;
whole-space scan;
model similarity or best guess;
Database-Carrier campaign work;
E9;
automatic PIR theorem/equivalence claim;
mid-run repair;
rerun;
evidence stitching.
```

## 4. Stop discipline

Any defect is fail-closed and makes this run INVALID / NON-ADJUDICATIVE. Successful completion produces bounded physical-reconciliation evidence only and requires separate Human Evidence Audit before any PIR finding.
