# PALACE — MINIMAL-PIR-EXP-001 Invalid Completion Record 030

> **Status:** RAW INVALID COMPLETION — HUMAN EVIDENCE AUDIT NOT OPEN
> **Date:** 2026-10-08
> **Experiment:** MINIMAL-PIR-EXP-001
> **Authorization/execution commit:** `36dc1de8d51d31f62f72db5f7b150a26c39a3667`
> **Runner commit:** `86cbfa119467f2836cabb1a324ebfdff17aef7a6`

## 1. Disposition

MINIMAL-PIR-EXP-001 is **INVALID / NON-ADJUDICATIVE**. The authorized one-shot
execution began with accepted E-L fixture policy and side-channel denial, but
fail-closed before physical reconciliation observations were persisted.

```text
outcome = INVALID / NON-ADJUDICATIVE;
stop_code =
  MINIMAL_PIR_OBSERVATION_JSONL_BYTES_TO_TEXT_PERSISTENCE_DEFECT;
root_cause_class =
  HARNESS_EXPERIMENT_EVIDENCE_BYTES_TO_TEXT_PERSISTENCE_DEFECT.
```

## 2. Failure boundary

The runner had completed bounded Physical Reconciliation in memory and then
attempted to persist `EV-P08` observations using `Path.write_text()` with bytes.
Python 3.9 rejected this:

```text
TypeError: data must be str, not bytes
```

This is an execution-recorder persistence defect. It is not PIR semantic
inference, IS mutation, whole-space scan, model guess, fixture mutation,
CarrierSQLite regression, E9 work, or an EQ/REJ criteria defect.

## 3. Evidence disposition

Only these measured-path artifacts were persisted before fail-closed:

```text
E-L/EV-P02_query_freshness_policy.json;
E-L/EV-P15_side_channel_denial_record.json.
```

No physical reconciliation observations, Fresh Closure, evaluation join,
phase vectors or experiment summary reached disk. Therefore no PIR verdict,
including no inference about E-L versus E-S, is established.

Two post-stop files are failure captures only and are not successful measured
evidence:

```text
POST_STOP_PROCESS_RESULT.json;
POST_STOP_STDERR.txt.
```

## 4. Budget disposition

```text
MINIMAL-PIR-EXP-001 execution budget = CONSUMED;
physical observation budget          = CONSUMED BY FAIL-CLOSED ATTEMPT;
experiment evidence budget           = CONSUMED BY FAIL-CLOSED ATTEMPT;
IS mutation budget                   = NOT USED;
repair                               = NOT AUTHORIZED;
rerun                                = NOT AUTHORIZED;
renewal                              = FORBIDDEN.
```

## 5. Claim disposition

```text
bounded physical reconciliation evidence = NOT ESTABLISHED;
PIR effectiveness                        = NOT ESTABLISHED;
PIR performance/complexity theorem       = NOT ESTABLISHED;
PALACE equivalence                       = NOT ESTABLISHED;
SimiGo integrated proof                  = NOT ESTABLISHED.
```

## 6. Next lawful object

The next lawful object is Human evidence audit of this INVALID run. If further
work is proposed, it requires a new independently budgeted Human-directed Request
scoped to experiment-recorder bytes/text persistence correction and any potential
future execution. Stopping without further PIR work is also lawful.

## 7. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing this
record; later modification creates a new content address and voids this
completion record.
```
