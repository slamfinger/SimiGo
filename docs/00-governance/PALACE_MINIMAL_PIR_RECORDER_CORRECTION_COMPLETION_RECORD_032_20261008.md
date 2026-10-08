# PALACE — PIR Recorder Correction & Validation Completion Record 032

> **Status:** COMPLETE — RECORDER CORRECTION PASS / VALIDATION PASS
> **Date:** 2026-10-08
> **Governing Request v2.6:** `35d4c6b250134a81483d55c481e87b52866eacd5`
> **Correction commit:** `faa862cf6c1aa39b2da50a754f8921fd4eb18317`
> **Completion commit:** canonical commit introducing this record
> **MINIMAL-PIR-EXP-002:** NOT AUTHORIZED / NOT DRAFTED / NOT EXECUTED

## 1. Correction result

The EV-P08 caller now persists canonical reconciliation JSONL with:

```python
observations_path.write_bytes(observations_payload)
```

The payload is generated as exact compact JSONL bytes before persistence.
`Path.write_text()` is no longer used for EV-P08.

## 2. Validation result

```text
negative bytes → write_text guard = PASS;
positive bytes → write_bytes guard = PASS;
byte-exact persistence = PASS;
reread / parse = PASS;
JSONL physical-line contract = PASS;
fresh experiment-entry validation = PASS;
all checks = 4/4 PASS.
```

## 3. Boundary result

```text
Probe v0.2 design = UNCHANGED;
RM-001 shapes, W_obs_age, W_latency and attribution = UNCHANGED;
PIR semantic model = UNCHANGED;
oracle leakage = NONE;
fixture mutation = NONE;
IS mutation = ZERO;
stale-success recurrence = NONE;
EV-P08 destination binding = PASS;
MINIMAL-PIR-EXP-002 = NOT AUTHORIZED;
experiment execution = NOT AUTHORIZED.
```

## 4. Artifact bindings

```text
corrected runner SHA256 = 824df579dd0110abf1e3a9ed287d8afb44a942bed0d1b115992e34b3fb102828;
regression guard SHA256 = 338c8428b3256974de2a43785399856e6d1158bb1895fa7649cf36878d82fa03;
validation report SHA256 = 0e70e2dd49fe4eeff999970df6aefc81c0aae267545fe44cd62d441ab972b283;
request commit = 35d4c6b250134a81483d55c481e87b52866eacd5;
correction commit = faa862cf6c1aa39b2da50a754f8921fd4eb18317.
```

## 5. Next lawful object

The next lawful object is explicit Human Experiment Launch Review for a future
corrected PIR run. This record does not authorize `MINIMAL-PIR-EXP-002`, a new
budget, execution, fixture reuse, or any scope broadening.

## 6. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing this
record; later modification creates a new content address and voids this
completion record.
```
