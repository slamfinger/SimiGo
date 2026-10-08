# PALACE — MINIMAL-PIR-EXP-003 Execution Authorization Record 037

> **Status:** APPROVE — ONE NEW INDEPENDENT FROZEN PIR EXPERIMENT
> **Date:** 2026-10-08
> **Human ruling, exact form:** `APPROVE MINIMAL-PIR-EXP-003，作为一次全新的、独立预算、严格冻结的 PIR experiment。`
> **Fixture correction commit:** `4bf8494f03edd761cdaef1d8ae5c3c5eb8f55ed6`
> **Targeted validation commit:** `226acc3913841df66350b3af8bfb66782ba2d99c`
> **Exact execution commit:** canonical commit introducing this record

## 1. Authorization

One new, independent, frozen PIR experiment is authorized:

```text
experiment_id = MINIMAL-PIR-EXP-003;
relationship to EXP-002 = NEW / INDEPENDENT / NOT A RERUN;
E-L = N=10,000, R=20, M=5;
E-S = N=20, R=20, M=5;
C-NOCHANGE-L = N=10,000, R=20, M=0;
C-NOCHANGE-S = N=20, R=20, M=0;
W_obs_age = 60,000 ms;
W_latency = 5,000 ms.
```

Authorized budgets:

```text
experiment budget             = 1;
physical observation budget   = 1 frozen four-fixture execution;
evidence budget               = 1 frozen four-fixture execution;
repair budget                 = 0;
rerun budget                  = 0;
renewal                       = FORBIDDEN.
```

## 2. Frozen boundary

The run must use RM-001 accepted shapes/windows, corrected pre-change locator
snapshots, deterministic MOVE/RENAME correlation, typed verdicts, phase-separated
attribution, oracle isolation, Fresh Closure and EV-P01..EV-P18 bindings.

```text
PC-CREATE remains NOT EXERCISED / DEFERRED BY FROZEN DESIGN;
no Probe v0.2 change;
no RM-001 shape/window/attribution change;
no PIR semantic change;
no fixture mutation during run;
no IS mutation;
no oracle leakage;
no semantic inference;
no whole-space scan;
no model similarity or best guess;
no Database-Carrier campaign work;
no E9.
```

## 3. Execution discipline

Any implementation, harness, fixture, evidence or persistence defect is
fail-closed:

```text
FAIL-CLOSED
  → INVALID / NON-ADJUDICATIVE
  → no repair
  → no rerun
  → no evidence stitching.
```

Successful completion produces only bounded physical-reconciliation evidence and
requires separate Human Evidence Audit. It does not establish a PIR theorem,
PALACE equivalence, SimiGo architecture proof, performance theorem, or any
unbounded claim.

## 4. Exact binding

```text
execution commit = canonical commit introducing this authorization record;
fixture source = corrected fixtures at this commit;
output root = docs/02-evidence/es-is-20261005/PIR_RM001_EXP003_CORRECTED;
repository state = clean.
```
