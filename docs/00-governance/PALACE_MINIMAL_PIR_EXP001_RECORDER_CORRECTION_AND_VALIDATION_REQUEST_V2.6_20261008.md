# PALACE — MINIMAL-PIR-EXP-001 Recorder Correction & Validation Request v2.6

> **Status:** HUMAN-AUTHORIZED — RECORDER CORRECTION / VALIDATION ONLY
> **Date:** 2026-10-08
> **Exact Human ruling:** `继续，但只到 recorder correction / validation，不进入下一次实验执行。`
> **Predecessor E7 audit closure:** `35d4c6b250134a81483d55c481e87b52866eacd5`

## 1. Purpose

Correct the isolated EV-P08 bytes/text persistence contract violation and
validate the corrected experiment-entry boundary. This Request does not
authorize `MINIMAL-PIR-EXP-002` or any experiment execution.

## 2. Authorized scope

```text
repair EV-P08 bytes/text API contract;
prefer Path.write_bytes for canonical JSONL bytes;
add targeted bytes/text mismatch regression guard;
run synthetic recorder persistence validation;
validate fresh experiment-entry readiness without launching an experiment.
```

## 3. Forbidden scope

```text
MINIMAL-PIR-EXP-002 authorization/drafting/execution;
new physical observation or experiment budget;
IS mutation;
Probe v0.2 semantic/design change;
RM-001 run shape, W_obs_age, W_latency or attribution change;
JSONL serializer redesign;
oracle leakage;
fixture mutation;
CarrierSQLite / E8 formal ruling change;
E9 or Database-Carrier campaign work;
automatic experiment authorization.
```

## 4. Required validation

```text
EV-P08 byte-exact persistence = PASS;
reread / parse = PASS;
JSONL one-record-per-line contract = PASS;
bytes → write_text negative guard = PASS;
bytes → write_bytes positive guard = PASS;
oracle leakage = NONE;
IS mutation = ZERO;
fixture mutation = NONE;
PIR semantic change = NONE;
stale-success recurrence = NONE;
EV-P08 destination binding = PASS;
fresh experiment-entry check = PASS.
```

## 5. Stop

After correction and validation PASS, canonical state stops before any
experiment. A future execution remains a separate explicit Human decision.
